variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "control_plane_subnet_ids" {
  description = "Subnets for the EKS control plane ENIs (public + private is fine here)"
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnets worker nodes launch into - private (with NAT) for a locked-down environment, public (no NAT) to save the NAT gateway cost - see environments/*.tfvars"
  type        = list(string)
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT - SPOT is materially cheaper and fine for dev/nonprod personal-project use"
  type        = string
  default     = "SPOT"
}

variable "node_disk_size" {
  type    = number
  default = 20
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

variable "github_actions_role_arn" {
  description = "IAM role the GitHub Actions deploy pipeline assumes - granted cluster-admin access via an EKS access entry"
  type        = string
}
