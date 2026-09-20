# Lets GitHub Actions authenticate to AWS via short-lived OIDC tokens
# instead of long-lived IAM access keys stored as repo secrets. One shared
# role for the whole repo (all three environments) - the deploy pipeline
# scopes *which* cluster/environment it touches at the kubectl/kustomize
# level (see docs/devops/02-cicd-pipeline.md), not via separate IAM roles.

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restricted to the main branch of this repo - PR runs (which only plan/
    # test, never apply/deploy) don't need to assume this role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = var.ecr_repository_arns
  }

  statement {
    sid       = "EKSDescribe"
    actions   = ["eks:DescribeCluster"]
    resources = var.eks_cluster_arns
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.project_name}-github-actions-deploy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.permissions.json
}
