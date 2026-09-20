variable "name" {
  description = "Prefix for all resource names/tags, e.g. craftista-dev"
  type        = string
}

variable "cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across (2 is enough for EKS; 3 for prod)"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name that will live in this VPC - used for the kubernetes.io/cluster/<name> subnet discovery tag"
  type        = string
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway for the private subnets (~$32-35/mo). Set false for environments where worker nodes run in the public subnets instead (see node_subnets output) to save that cost."
  type        = bool
  default     = true
}
