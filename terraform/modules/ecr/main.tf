# One repository per service, shared across all environments - images are
# built once per commit and the *same* tag is promoted dev -> nonprod ->
# prod (see docs/devops/02-cicd-pipeline.md), so these live in the global
# stack rather than being duplicated per environment.

resource "aws_ecr_repository" "this" {
  for_each = toset(var.services)

  name                 = "${var.project_name}-${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.image_retention_count} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.image_retention_count
      }
      action = { type = "expire" }
    }]
  })
}
