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

data "aws_s3_bucket" "this" {
  bucket = var.bucket
}

data "aws_dynamodb_table" "lock" {
  name = var.table
}

output "bucket_arn" {
  description = "ARN of the state bucket reported by S3."
  value       = data.aws_s3_bucket.this.arn
}

output "table_pitr_enabled" {
  description = "Whether point-in-time recovery is enabled on the lock table."
  value       = one(data.aws_dynamodb_table.lock.point_in_time_recovery).enabled
}

output "table_hash_key" {
  description = "Hash key of the lock table reported by DynamoDB."
  value       = data.aws_dynamodb_table.lock.hash_key
}

output "table_sse_enabled" {
  description = "Whether DynamoDB reports server-side encryption on the lock table."
  value       = one(data.aws_dynamodb_table.lock.server_side_encryption).enabled
}
