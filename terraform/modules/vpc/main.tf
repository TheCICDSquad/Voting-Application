# Hand-rolled VPC: one public + one private subnet per AZ, one internet
# gateway, and at most one NAT gateway (never one per AZ - that's the
# single biggest avoidable cost in a multi-AZ VPC). RDS always lives in the
# private subnets; EKS worker nodes live in private (enable_nat_gateway =
# true) or public (enable_nat_gateway = false) subnets depending on the
# environment - see modules/eks and environments/*.tfvars.

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = { for idx, az in var.azs : az => idx }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.cidr, 4, each.value)
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.name}-public-${each.key}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_subnet" "private" {
  for_each = { for idx, az in var.azs : az => idx }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 4, each.value + 8)

  tags = {
    Name                                        = "${var.name}-private-${each.key}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${var.name}-nat"
  }
}

# Single NAT gateway for the whole VPC (not one per AZ) - halves/thirds the
# ~$32/mo NAT cost at the price of cross-AZ data transfer for private
# subnets in AZs other than the first. Fine for a personal project's traffic
# volume.
resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[var.azs[0]].id

  tags = {
    Name = "${var.name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-private"
  }
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
