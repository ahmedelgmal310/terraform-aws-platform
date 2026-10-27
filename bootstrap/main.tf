# One-time stack that creates the remote state backend used by live/*.
# It keeps its own state locally (commit nothing: *.tfstate is ignored) or can
# be migrated into the bucket it creates once it exists.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "shared"
      Owner       = var.owner
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = coalesce(var.state_bucket_name, "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}")
}

module "state_bucket" {
  source = "../modules/s3-secure-bucket"

  bucket_name                        = local.bucket_name
  force_destroy                      = var.force_destroy
  noncurrent_version_expiration_days = 365
}

resource "aws_dynamodb_table" "lock" {
  name                        = "${var.project}-tfstate-lock"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "LockID"
  deletion_protection_enabled = !var.force_destroy

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = module.state_bucket.kms_key_arn
  }
}
