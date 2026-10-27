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

module "vpc" {
  source = "../.."

  name             = "example"
  cidr_block       = "10.0.0.0/16"
  azs              = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  nat_gateway_mode = "per_az"

  enable_flow_logs        = true
  flow_log_retention_days = 365

  tags = {
    Environment = "example"
    Owner       = "platform-team"
  }
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnet_ids
}
