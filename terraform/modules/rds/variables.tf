variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group allowed to reach Postgres on 5432 (the EKS cluster security group)"
  type        = string
}

variable "db_name" {
  type    = string
  default = "catalogue"
}

variable "db_username" {
  type    = string
  default = "devops"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "instance_class" {
  description = "db.t3.micro is free-tier eligible - keep it unless the workload genuinely needs more"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "skip_final_snapshot" {
  type    = bool
  default = true
}

variable "backup_retention_period" {
  type    = number
  default = 1
}
