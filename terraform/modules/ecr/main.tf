resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE" # tags (e.g. a git SHA) should never be silently overwritten

  image_scanning_configuration {
    scan_on_push = true # native ECR scanning, complementing Trivy at CI build time
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

# Expires untagged images (left behind by IMMUTABLE tag pushes that reused a
# tag name, or manual pushes) after N days so storage cost doesn't grow
# unbounded. Tagged images (git SHA, "latest") are never touched by this rule.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after ${var.untagged_image_expiry_days} days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = var.untagged_image_expiry_days
      }
      action = {
        type = "expire"
      }
    }]
  })
}
