# Shared integration/staging environment. Still SPOT + no NAT gateway to
# keep it cheap, but allows scaling to 2 nodes under load.

environment = "nonprod"

vpc_cidr = "10.1.0.0/16"
azs      = ["us-east-1a", "us-east-1b"]

enable_nat_gateway = false

node_instance_types     = ["t3.small"]
node_capacity_type      = "SPOT"
node_group_min_size     = 1
node_group_max_size     = 2
node_group_desired_size = 1

db_instance_class      = "db.t3.micro"
db_multi_az            = false
db_deletion_protection = false
