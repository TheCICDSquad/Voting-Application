# Backs the catalogue service's Postgres schema (see catalogue/db.create.py
# and catalogue/app.py's get_db_connection()). The frontend, voting and
# recommendation services are stateless / use in-memory H2 and need no RDS.
# db.t3.micro + single-AZ + gp3 minimum storage by default across every
# environment - this is a personal project, not a workload that needs
# Multi-AZ failover.

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-catalogue-db"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.name}-catalogue-db"
  description = "Allow Postgres access from the EKS cluster only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from EKS nodes/pods"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.allowed_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-catalogue-db"
  engine         = "postgres"
  engine_version = "15"
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = var.deletion_protection
}
