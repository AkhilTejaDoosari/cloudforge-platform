# Points at the bucket created by terraform/bootstrap (see that directory's
# README before applying this environment). use_lockfile uses Terraform's
# native S3 state locking (>=1.10) — no DynamoDB table needed.
#
# This file is intentionally NOT read during Phase 5 validation: we run
# `terraform init -backend=false`, which skips backend initialization
# entirely and needs no AWS access at all.
terraform {
  backend "s3" {
    bucket       = "cloudforge-platform-tfstate" # must match terraform/bootstrap's bucket_name output
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
