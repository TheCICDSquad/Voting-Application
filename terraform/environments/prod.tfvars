# The one environment worth paying the NAT gateway (~$32-35/mo) for private
# worker nodes and ON_DEMAND capacity (no SPOT interruptions). Everything
# else stays at the same minimal sizing as dev/nonprod (db.t3.micro,
# single-AZ RDS, t3.small nodes) - this is a personal project, not a
# workload that justifies Multi-AZ or larger instances.

environment = "prod"

vpc_cidr = "10.2.0.0/16"
azs      = ["us-east-1a", "us-east-1b", "us-east-1c"]

enable_nat_gateway = true

node_instance_types     = ["t3.small"]
node_capacity_type      = "ON_DEMAND"
node_group_min_size     = 2
node_group_max_size     = 3
node_group_desired_size = 2

db_instance_class      = "db.t3.micro"
db_multi_az            = false
db_deletion_protection = false
