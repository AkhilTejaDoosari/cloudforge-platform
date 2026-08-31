variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "cloudforge-dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "cluster_iam_role_name" {
  description = <<-EOT
    Passed through to the eks module. Leave null for normal use (resolves to
    "$${cluster_name}-cluster"). Set explicitly only for environments with an
    external naming constraint, e.g. the KodeKloud sandbox lab — see
    modules/eks/variables.tf and docs/phases.md's Phase 6 notes.
  EOT
  type        = string
  default     = null
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 2
}

variable "enable_rds" {
  description = <<-EOT
    Clean on/off switch for provisioning RDS. Defaults to true (normal
    expected behavior for a real AWS account). Set false in
    terraform.tfvars (gitignored) for environments where RDS can't be
    provisioned — e.g. the KodeKloud sandbox lab, where rds:CreateDBInstance
    is denied — without touching this file or using `-target`.
  EOT
  type        = bool
  default     = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "github_org" {
  type    = string
  default = "AkhilTejaDoosari"
}

variable "github_repo" {
  type    = string
  default = "cloudforge-platform"
}
