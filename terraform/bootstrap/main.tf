# Bootstraps the S3 bucket that environments/* will use as their remote
# state backend. This is the one legitimate place in this project that uses
# local state on purpose: Terraform's own backend configuration can't point
# at a bucket that Terraform itself hasn't created yet. Apply this once,
# manually, before any `environments/*` root is ever initialized.
#
# Uses Terraform's native S3 state locking (`use_lockfile`, backend.tf in
# environments/dev), so no separate DynamoDB lock table is needed.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name

  # Prevents `terraform destroy` from ever silently deleting the bucket that
  # holds every other environment's state.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # recovers a previous state file if one is ever corrupted or wrongly overwritten
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket_name" {
  value = aws_s3_bucket.state.id
}
