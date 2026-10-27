# Read-only helper used by the integration test to read the bucket policy
# back from the S3 API.

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
  description = "Bucket to inspect."
  type        = string
}

data "aws_s3_bucket_policy" "this" {
  bucket = var.bucket
}

locals {
  statements = jsondecode(data.aws_s3_bucket_policy.this.policy).Statement
}

output "policy_statement_count" {
  description = "Number of statements in the live bucket policy."
  value       = length(local.statements)
}

output "policy_has_tls_deny" {
  description = "Whether the live policy denies aws:SecureTransport=false."
  value = anytrue([
    for s in local.statements :
    s.Effect == "Deny" && try(tostring(s.Condition.Bool["aws:SecureTransport"]), "") == "false"
  ])
}
