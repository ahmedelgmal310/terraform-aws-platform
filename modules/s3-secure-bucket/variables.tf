variable "bucket_name" {
  description = "Globally unique bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits, dots and hyphens, beginning and ending with a letter or digit."
  }

  validation {
    condition     = !can(regex("\\.\\.|^\\d+\\.\\d+\\.\\d+\\.\\d+$|^xn--|-s3alias$|--ol-s3$", var.bucket_name))
    error_message = "bucket_name must not contain consecutive dots, look like an IP address, or use a reserved prefix/suffix."
  }
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key for SSE-KMS. When null a dedicated key with rotation is created."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

variable "kms_key_deletion_window_days" {
  description = "Waiting period before a module-created KMS key is deleted."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_days >= 7 && var.kms_key_deletion_window_days <= 30
    error_message = "kms_key_deletion_window_days must be between 7 and 30."
  }
}

variable "force_destroy" {
  description = "Allow Terraform to delete the bucket even when it still contains objects. Keep false outside of ephemeral environments."
  type        = bool
  default     = false
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which noncurrent object versions are permanently deleted."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}

variable "abort_incomplete_multipart_days" {
  description = "Days after which incomplete multipart uploads are aborted."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_days >= 1
    error_message = "abort_incomplete_multipart_days must be at least 1."
  }
}

variable "access_logging" {
  description = "Server access logging target. `bucket` may be another module's output: only whether this object is null decides if logging is configured, so the plan stays fully known. Null disables logging (use for the log bucket itself). `prefix` defaults to `s3/<bucket_name>/`."
  type = object({
    bucket = string
    prefix = optional(string)
  })
  default = null
}

variable "accept_access_logs" {
  description = "Mark this bucket as an S3 server access log destination: grants the S3 logging service write access for sources in this account."
  type        = bool
  default     = false
}

variable "additional_policy_statements" {
  description = "Extra IAM policy statements (already decoded objects) merged into the bucket policy after the mandatory TLS and encryption statements."
  type        = list(any)
  default     = []
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
