variable "repository_names" {
  description = <<-EOT
    ECR repository names to create, e.g. ["cloudforge/backend",
    "cloudforge/frontend"]. Must match the REPO naming the CI workflow
    (.github/workflows/ci.yml) already pushes to.
  EOT
  type        = list(string)
}

variable "untagged_image_expiry_days" {
  description = "Days after which untagged images are automatically expired, to control storage cost."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
