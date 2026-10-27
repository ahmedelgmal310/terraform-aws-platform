variable "identifier" {
  description = "RDS instance identifier; also used as a name prefix for the subnet group, parameter group and security group."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.identifier)) && !strcontains(var.identifier, "--")
    error_message = "identifier must start with a letter, contain only lowercase letters, digits and single hyphens, and be at most 63 characters."
  }
}

variable "engine_version" {
  description = "PostgreSQL major or major.minor version, for example `17` or `17.6`."
  type        = string
  default     = "17"

  validation {
    condition     = can(regex("^(1[4-8])(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must be a supported PostgreSQL version between 14 and 18."
  }
}

variable "instance_class" {
  description = "Instance class, for example `db.t4g.micro` or `db.r7g.large`."
  type        = string

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must look like db.<family>.<size>."
  }
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "allocated_storage must be between 20 and 65536 GiB."
  }
}

variable "max_allocated_storage" {
  description = "Upper limit for storage autoscaling in GiB. Set equal to allocated_storage to disable autoscaling."
  type        = number
  default     = 100

  validation {
    condition     = var.max_allocated_storage >= var.allocated_storage
    error_message = "max_allocated_storage must be greater than or equal to allocated_storage."
  }
}

variable "multi_az" {
  description = "Run a synchronous standby in a second AZ."
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.db_name))
    error_message = "db_name must start with a letter and contain only lowercase letters, digits and underscores."
  }
}

variable "master_username" {
  description = "Master user name. The password is created and rotated by RDS in Secrets Manager; it never appears in Terraform state."
  type        = string
  default     = "platform_admin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,15}$", var.master_username)) && !contains(["admin", "postgres", "rdsadmin", "root"], var.master_username)
    error_message = "master_username must be 1-16 lowercase characters and not a reserved name."
  }
}

variable "vpc_id" {
  description = "VPC that hosts the database security group."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the DB subnet group. Use intra or private subnets; at least two AZs are required."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least two subnets in different AZs are required."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect on the PostgreSQL port."
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect on the PostgreSQL port. Must be private ranges."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_cidr_blocks : can(cidrhost(c, 0)) && !contains(["0.0.0.0/0", "::/0"], c)])
    error_message = "allowed_cidr_blocks must be valid CIDRs and must not open the database to the internet."
  }
}

variable "kms_key_arn" {
  description = "KMS key for storage, Performance Insights and the managed master secret. When null a dedicated key with rotation is created."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

variable "backup_retention_days" {
  description = "Automated backup retention in days."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35; automated backups cannot be turned off."
  }
}

variable "backup_window" {
  description = "Daily backup window (UTC), hh24:mi-hh24:mi."
  type        = string
  default     = "02:00-03:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC), ddd:hh24:mi-ddd:hh24:mi."
  type        = string
  default     = "sun:03:30-sun:04:30"
}

variable "deletion_protection" {
  description = "Block deletion of the instance through the API."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on deletion. Only for throwaway environments."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights (encrypted with the module KMS key)."
  type        = bool
  default     = true
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention: 7 (free tier) or a multiple of 31 up to 731."
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_days == 7 || (var.performance_insights_retention_days % 31 == 0 && var.performance_insights_retention_days <= 731)
    error_message = "performance_insights_retention_days must be 7 or a multiple of 31 up to 731."
  }
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0 disables it)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of during the maintenance window."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
