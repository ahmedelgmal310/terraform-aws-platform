terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

data "aws_caller_identity" "current" {}

module "access_logs" {
  source = "../.."

  bucket_name        = "example-access-logs-${data.aws_caller_identity.current.account_id}"
  accept_access_logs = true
}

module "data" {
  source = "../.."

  bucket_name    = "example-data-${data.aws_caller_identity.current.account_id}"
  access_logging = { bucket = module.access_logs.bucket_id }

  tags = {
    Environment = "example"
    Owner       = "platform-team"
  }
}

output "data_bucket_arn" {
  description = "ARN of the data bucket."
  value       = module.data.bucket_arn
}
