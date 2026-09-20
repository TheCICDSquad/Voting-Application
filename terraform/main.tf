# Single entry point for the whole per-environment stack: every module
# lives under terraform/modules/ and is called from here only. Still one
# independent state file per environment (three .tfvars, three
# backend-configs, no Terraform workspaces - see
# docs/devops/04-terraform-infrastructure.md), NOT one shared state.
#
# ECR repositories and the GitHub OIDC deploy role are account-level
# singletons - they must exist exactly once, not once per environment, or
# the 2nd/3rd `terraform apply` fails with "already exists". Rather than a
# separate global/ stack, this file creates them only when
# environment = "dev" (module.ecr / module.github_oidc, guarded by
# local.is_primary_environment) and every other environment looks the same
# resources up by their (deterministic) name via a data source instead.
# Practical implication: apply "dev" at least once before "nonprod" or
# "prod" - see doc 4's bootstrap steps.

locals {
  name         = "${var.project_name}-${var.environment}"
  cluster_name = "${local.name}-eks"

  is_primary_environment = var.environment == "dev"

  # No NAT gateway (enable_nat_gateway = false, the dev/nonprod default) =>
  # nodes must sit in the public subnets to reach the internet/ECR/EKS API.
  node_subnet_ids = var.enable_nat_gateway ? module.vpc.private_subnet_ids : module.vpc.public_subnet_ids

  # Deterministic cluster ARNs for every environment (not just this one) -
  # used to scope the shared GitHub Actions role's eks:DescribeCluster
  # permission without depending on the other environments' state.
  eks_cluster_arns = [
    for env in var.environments :
    "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.project_name}-${env}-eks"
  ]

  github_actions_role_arn = local.is_primary_environment ? module.github_oidc[0].role_arn : data.aws_iam_role.github_actions[0].arn

  ecr_repository_urls = local.is_primary_environment ? module.ecr[0].repository_urls : {
    for name, repo in data.aws_ecr_repository.shared : name => repo.repository_url
  }
}

# --- Shared/singleton resources - created only by the "dev" apply --------
module "ecr" {
  count  = local.is_primary_environment ? 1 : 0
  source = "./modules/ecr"

  project_name = var.project_name
  services     = var.services
}

module "github_oidc" {
  count  = local.is_primary_environment ? 1 : 0
  source = "./modules/github-oidc"

  project_name        = var.project_name
  github_repository   = var.github_repository
  ecr_repository_arns = module.ecr[0].repository_arns
  eks_cluster_arns    = local.eks_cluster_arns
}

# Looked up (not created) by every non-"dev" environment - these must
# already exist, i.e. "dev" must have been applied at least once.
data "aws_ecr_repository" "shared" {
  for_each = toset(local.is_primary_environment ? [] : var.services)
  name     = "${var.project_name}-${each.key}"
}

data "aws_iam_role" "github_actions" {
  count = local.is_primary_environment ? 0 : 1
  name  = "${var.project_name}-github-actions"
}

# --- Per-environment resources - created by every environment ------------
module "vpc" {
  source = "./modules/vpc"

  name               = local.name
  cidr               = var.vpc_cidr
  azs                = var.azs
  cluster_name       = local.cluster_name
  enable_nat_gateway = var.enable_nat_gateway
}

module "eks" {
  source = "./modules/eks"

  cluster_name             = local.cluster_name
  cluster_version          = var.cluster_version
  vpc_id                   = module.vpc.vpc_id
  control_plane_subnet_ids = concat(module.vpc.public_subnet_ids, module.vpc.private_subnet_ids)
  node_subnet_ids          = local.node_subnet_ids

  node_instance_types     = var.node_instance_types
  node_capacity_type      = var.node_capacity_type
  node_group_min_size     = var.node_group_min_size
  node_group_max_size     = var.node_group_max_size
  node_group_desired_size = var.node_group_desired_size

  github_actions_role_arn = local.github_actions_role_arn
}

module "rds" {
  source = "./modules/rds"

  name                      = local.name
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  allowed_security_group_id = module.eks.cluster_security_group_id

  db_password         = var.db_password
  instance_class      = var.db_instance_class
  multi_az            = var.db_multi_az
  deletion_protection = var.db_deletion_protection
}
