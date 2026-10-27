variable "environment" {
  description = "Environment name; drives naming, tagging and the OIDC subject."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "project" {
  description = "Project slug used in names and the Project tag."
  type        = string
  default     = "platform"
}

variable "owner" {
  description = "Owning team (Owner tag)."
  type        = string
  default     = "platform-team"
}

variable "region" {
  description = "AWS region of the environment."
  type        = string
  default     = "eu-west-1"
}

variable "az_suffixes" {
  description = "Availability zone letters used in the region (three by default)."
  type        = list(string)
  default     = ["a", "b", "c"]
}

variable "allowed_account_ids" {
  description = "AWS account IDs this environment may be applied to. Empty disables the check (CI plans against LocalStack)."
  type        = list(string)
  default     = []
}

variable "github_owner" {
  description = "GitHub organisation or user that owns the deploying repository."
  type        = string
  default     = "ahmedelgmal310"
}

variable "github_repo" {
  description = "Name of the repository whose workflows may deploy this environment."
  type        = string
  default     = "terraform-aws-platform"
}

variable "vpc_cidr" {
  description = "VPC CIDR block. Each environment gets a non-overlapping /16 so they can be peered later."
  type        = string
}

variable "nat_gateway_mode" {
  description = "none, single or per_az."
  type        = string
}

variable "flow_log_retention_days" {
  description = "VPC flow log retention in days."
  type        = number
}

variable "db" {
  description = "Database sizing and resilience settings."
  type = object({
    instance_class                      = string
    allocated_storage                   = number
    max_allocated_storage               = number
    multi_az                            = bool
    backup_retention_days               = number
    deletion_protection                 = bool
    skip_final_snapshot                 = bool
    performance_insights_retention_days = number
    monitoring_interval                 = number
  })
}

variable "app" {
  description = "ECS service sizing."
  type = object({
    cpu                = number
    memory             = number
    desired_count      = number
    min_capacity       = number
    max_capacity       = number
    use_fargate_spot   = bool
    log_retention_days = number
  })
}

variable "container_image" {
  description = "Application image, pinned by tag or digest."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29"
}
