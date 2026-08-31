# Password is generated at apply-time and never appears as a Terraform
# variable, default, or plan output — it exists only in state (which is why
# the state backend, terraform/bootstrap, uses an encrypted S3 bucket) and in
# Secrets Manager. This is the real, production version of the gitignored
# secrets.env pattern used for local Kubernetes in Phase 3 — the backend pods
# will fetch this from Secrets Manager via External Secrets Operator in
# Phase 9, instead of a Kustomize secretGenerator.
resource "random_password" "db" {
  length  = 32
  special = false # avoids characters that need URL-encoding in a DATABASE_URL connection string
}

resource "aws_secretsmanager_secret" "db" {
  name = "${var.identifier}-postgres-credentials"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    dbname   = var.db_name
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
  })
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "db" {
  name        = "${var.identifier}-rds"
  description = "Allow Postgres from EKS worker nodes only"
  vpc_id      = var.vpc_id

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  # count, not for_each: the referenced security group ID (e.g. the EKS
  # cluster's) isn't known until apply, but the *number* of entries in
  # var.allowed_security_group_ids is known at plan time regardless — count
  # only needs the latter. for_each would need to know the actual values
  # up front to compute its keys, which fails here with "Invalid for_each
  # argument" (caught by `terraform plan`, not `terraform validate`).
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.db.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage      = var.allocated_storage
  storage_encrypted      = true
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  publicly_accessible       = false
  multi_az                  = var.multi_az
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final-snapshot"

  tags = var.tags
}
