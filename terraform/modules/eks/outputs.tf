output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_arn" {
  value = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

# Every EKS-managed node group is a member of this security group by
# default, even without a custom launch template - used to scope the RDS
# security group's ingress rule to "only the cluster's own nodes".
output "cluster_security_group_id" {
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
