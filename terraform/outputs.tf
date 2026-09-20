output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "catalogue_db_endpoint" {
  value = module.rds.endpoint
}

output "ecr_repository_urls" {
  description = "Created by the \"dev\" apply, looked up by every other environment - see main.tf"
  value       = local.ecr_repository_urls
}

output "github_actions_role_arn" {
  description = "Created by the \"dev\" apply, looked up by every other environment - see main.tf"
  value       = local.github_actions_role_arn
}
