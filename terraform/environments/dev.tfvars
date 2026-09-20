# Cheapest environment: 1 SPOT node, no NAT gateway (nodes sit in public
# subnets - see enable_nat_gateway in terraform/modules/vpc). Expect this
# to be applied for a work session and destroyed afterwards, not left
# running - see docs/devops/04-terraform-infrastructure.md.

environment = "dev"

vpc_cidr = "10.0.0.0/16"
azs      = ["us-east-1a", "us-east-1b"]

enable_nat_gateway = false

node_instance_types     = ["t3.small"]
node_capacity_type      = "SPOT"
node_group_min_size     = 1
node_group_max_size     = 1
node_group_desired_size = 1

db_instance_class      = "db.t3.micro"
db_multi_az            = false
db_deletion_protection = false
