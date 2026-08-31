output "repository_urls" {
  description = "Map of repository name to its push/pull URL."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of repository name to its ARN, for scoping IAM policies (e.g. the GitHub OIDC role)."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
