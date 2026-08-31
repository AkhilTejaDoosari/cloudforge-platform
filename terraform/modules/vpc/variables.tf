variable "name" {
  description = "Name prefix for all resources in this module (e.g. cloudforge-dev)."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across. EKS requires at least 2."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ, same order as var.azs."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ, same order as var.azs."
  type        = list(string)
}

variable "cluster_name" {
  description = <<-EOT
    EKS cluster name that will use this VPC. Used only to set the
    kubernetes.io/cluster/<name> discovery tag EKS and the AWS Load Balancer
    Controller require on subnets — this module creates no EKS resources
    itself.
  EOT
  type        = string
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
