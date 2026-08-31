output "role_arn" {
  description = "Set this as the AWS_ROLE_ARN repo variable in GitHub (Settings > Secrets and variables > Actions > Variables) to activate the ECR push step in .github/workflows/ci.yml."
  value       = aws_iam_role.this.arn
}
