variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "craftista"
}

variable "environment" {
  description = "dev | nonprod | prod - set per environment in environments/*.tfvars"
  type        = string

  validation {
    condition     = contains(["dev", "nonprod", "prod"], var.environment)
    error_message = "environment must be one of: dev, nonprod, prod."
  }
}

variable "environments" {
  description = "Every environment name that exists (used only to build each one's EKS cluster ARN for the shared GitHub Actions role's IAM policy - see main.tf's locals)"
  type        = list(string)
  default     = ["dev", "nonprod", "prod"]
}

variable "services" {
  description = "Service names - one ECR repository each. Created only when environment == \"dev\" (see main.tf); every other environment looks the same repositories up via a data source, since ECR repos are shared/global, not per-environment."
  type        = list(string)
  default     = ["frontend", "catalogue", "voting", "recommendation"]
}

variable "github_repository" {
  description = "GitHub org/repo allowed to assume the shared deploy role via OIDC, e.g. craftista/craftista"
  type        = string
  default     = "craftista/craftista"
}

# --- Networking ------------------------------------------------------------
variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "enable_nat_gateway" {
  description = "true = worker nodes in private subnets behind a NAT gateway (~$32-35/mo extra). false = nodes in public subnets, no NAT gateway. See terraform/modules/vpc."
  type        = bool
  default     = false
}

# --- EKS --------------------------------------------------------------
variable "cluster_version" {
  type    = string
  default = "1.29"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "node_capacity_type" {
  type    = string
  default = "SPOT"
}

variable "node_group_min_size" {
  type = number
}

variable "node_group_max_size" {
  type = number
}

variable "node_group_desired_size" {
  type = number
}

# --- RDS (catalogue) --------------------------------------------------
variable "db_password" {
  description = "Master password for the catalogue RDS instance - pass via TF_VAR_db_password or a CI secret, never commit it"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_deletion_protection" {
  type    = bool
  default = false
}
