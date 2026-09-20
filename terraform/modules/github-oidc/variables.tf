variable "project_name" {
  type = string
}

variable "github_repository" {
  description = "GitHub org/repo allowed to assume this role via OIDC, e.g. craftista/craftista"
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs the role may push/pull images to"
  type        = list(string)
}

variable "eks_cluster_arns" {
  description = "ARNs of every environment's EKS cluster this role is allowed to describe/authenticate against (dev, nonprod, prod)"
  type        = list(string)
}
