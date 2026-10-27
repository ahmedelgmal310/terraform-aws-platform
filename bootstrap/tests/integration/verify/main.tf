# Read-only helper used by the integration test.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

variable "bucket" {
  description = "State bucket to inspect."
  type        = string
}

variable "table" {
  description = "Lock table to inspect."
  type        = string
}

data "aws_s3_bucket_versioning" "this" {
  bucket = var.bucket
}

data "aws_dynamodb_table" "lock" {
  name = var.table
}

output "bucket_versioning" {
  description = "Versioning status reported by S3."
  value       = one(data.aws_s3_bucket_versioning.this.versioning_configuration).status
}

output "table_sse_enabled" {
  description = "Whether DynamoDB reports server-side encryption on the lock table."
  value       = one(data.aws_dynamodb_table.lock.server_side_encryption).enabled
}
