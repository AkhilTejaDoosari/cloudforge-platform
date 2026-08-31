output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the real cluster."
  value       = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region}"
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "rds_endpoint" {
  description = "null when enable_rds = false."
  value       = var.enable_rds ? module.rds[0].db_endpoint : null
}

output "rds_secret_arn" {
  description = "Fetch the actual DB credentials with: aws secretsmanager get-secret-value --secret-id <this-arn>. null when enable_rds = false."
  value       = var.enable_rds ? module.rds[0].secret_arn : null
}

output "worker_asg_name" {
  value = module.eks.worker_asg_name
}

output "cluster_iam_role_name" {
  value = module.eks.cluster_iam_role_name
}

output "github_actions_role_arn" {
  description = "Set this as the AWS_ROLE_ARN repository variable in GitHub to activate the ECR push step in .github/workflows/ci.yml."
  value       = module.github_oidc.role_arn
}
