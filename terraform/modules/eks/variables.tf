variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC ID to deploy the cluster into."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for worker nodes."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = <<-EOT
    Public subnet IDs, added to the control plane's subnet list alongside
    private ones so a public-facing ALB (Phase 6+) can be provisioned by the
    AWS Load Balancer Controller. Worker nodes themselves are only ever
    scheduled into private subnets.
  EOT
  type        = list(string)
}

variable "endpoint_public_access" {
  description = <<-EOT
    Whether the EKS API server endpoint is reachable from the public
    internet. true is the simpler choice for a personal dev cluster (kubectl
    works from a laptop with no VPN/bastion); a production cluster would set
    this false and require a VPN or bastion host into the VPC instead.
  EOT
  type        = bool
  default     = true
}

variable "cluster_iam_role_name" {
  description = <<-EOT
    Override for the EKS cluster's IAM role name. Defaults to null, which
    resolves to "$${cluster_name}-cluster" — parameterized by cluster name so
    multiple clusters can coexist in one AWS account. Set this explicitly
    only when an external constraint requires one exact literal name — e.g.
    this project's KodeKloud sandbox lab, whose attached IAM policy grants
    iam:PassRole to eks.amazonaws.com only for a role named exactly
    "eksClusterRole" (confirmed via aws iam simulate-principal-policy; see
    docs/phases.md's Phase 6 notes). A real, non-sandboxed AWS account
    should leave this null.
  EOT
  type        = string
  default     = null
}

variable "additional_endpoint_public_access_cidrs" {
  description = <<-EOT
    Extra CIDRs (beyond the caller's own current IP, detected automatically)
    allowed to reach the public API endpoint — e.g. a second location, or a
    CI runner's egress range.
  EOT
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = <<-EOT
    EC2 instance type(s) for worker nodes. Only index [0] is currently used
    (this module's launch template takes a single instance_type, not a
    mixed-instances policy) — kept as a list for future extensibility
    without a breaking change. t3.small is a reasonable small/cheap default
    for a dev cluster generally, not just for a constrained sandbox.
  EOT
  type        = list(string)
  default     = ["t3.small"]
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

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
