variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "allowed_branch" {
  description = "Only this branch may assume the role — a PR from a fork or any other branch cannot, even with a valid GitHub OIDC token for this repo."
  type        = string
  default     = "main"
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs this role is allowed to push/pull. Least privilege: not ecr:* on *."
  type        = list(string)
}

variable "role_name" {
  type    = string
  default = "github-actions-cloudforge-ci"
}

variable "create_oidc_provider" {
  description = <<-EOT
    An AWS account can only have one OIDC provider per issuer URL. If this
    AWS account already trusts token.actions.githubusercontent.com (from a
    different project's setup), set this false and pass its ARN via
    existing_oidc_provider_arn instead of trying to create a duplicate.
  EOT
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "Required when create_oidc_provider = false."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
