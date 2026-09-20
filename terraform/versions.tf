terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Partial config - each environment supplies its own state key so dev,
  # nonprod and prod never share (or collide on) one state file, without
  # using Terraform workspaces:
  #   terraform init -backend-config=backend-configs/dev.hcl
  #   terraform init -backend-config=backend-configs/nonprod.hcl
  #   terraform init -backend-config=backend-configs/prod.hcl
  # See docs/devops/04-terraform-infrastructure.md.
  backend "s3" {}
}
