output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "ARN of the cluster's OIDC provider, for IRSA trust policies (AWS Load Balancer Controller, External Secrets Operator, etc.)."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  value = aws_iam_openid_connect_provider.eks.url
}

output "node_security_group_id" {
  description = "Security group EKS attaches to worker nodes — used by the RDS module to allow inbound Postgres traffic only from cluster nodes."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
