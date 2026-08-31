output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials. The password itself is never a Terraform output."
  value       = aws_secretsmanager_secret.db.arn
}

output "security_group_id" {
  value = aws_security_group.db.id
}
