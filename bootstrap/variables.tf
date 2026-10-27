variable "project" {
  description = "Project slug used in resource names."
  type        = string
  default     = "platform"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project))
    error_message = "project must be 2-21 lowercase letters, digits or hyphens."
  }
}

variable "owner" {
  description = "Team that owns the state backend (Owner tag)."
  type        = string
  default     = "platform-team"
}

variable "region" {
  description = "Region of the state bucket and lock table."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Override the state bucket name. Defaults to <project>-tfstate-<account id>."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow destroying a non-empty bucket and drop deletion protection on the lock table. Only for test runs."
  type        = bool
  default     = false
}
