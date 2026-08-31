variable "identifier" {
  description = "RDS instance identifier."
  type        = string
}

variable "engine_version" {
  type    = string
  default = "16"
}

variable "instance_class" {
  description = "Instance class. db.t4g.micro (ARM/Graviton) is the cheapest option that still supports Postgres 16."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Storage in GB."
  type        = number
  default     = 20
}

variable "db_name" {
  type    = string
  default = "cloudforge"
}

variable "db_username" {
  type    = string
  default = "cloudforge"
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the DB subnet group."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect on the Postgres port (e.g. the EKS node security group). Nothing else can reach this database."
  type        = list(string)
}

variable "multi_az" {
  description = <<-EOT
    Whether to run a synchronous standby in a second AZ. Roughly doubles RDS
    cost for automatic failover — worth it in production, not for a demo
    environment with disposable data.
  EOT
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = <<-EOT
    If true, `terraform destroy` deletes the database with no final backup.
    Appropriate for a dev environment holding no real data; a production
    environment should set this false so destroy always leaves a recovery
    point.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
