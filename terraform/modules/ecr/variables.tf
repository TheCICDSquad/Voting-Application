variable "project_name" {
  type = string
}

variable "services" {
  description = "Service names to create one ECR repository each for"
  type        = list(string)
}

variable "image_retention_count" {
  description = "Keep only the most recent N images per repository (cost control - ECR storage is billed per GB-month)"
  type        = number
  default     = 10
}
