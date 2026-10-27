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
  source = "../../../vpc"

  name       = "example-db"
  cidr_block = "10.50.0.0/16"
  azs        = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

module "db" {
  source = "../.."

  identifier          = "example-db"
  instance_class      = "db.t4g.micro"
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.intra_subnet_ids
  allowed_cidr_blocks = module.vpc.private_subnet_cidrs

  multi_az              = true
  backup_retention_days = 14
}

output "endpoint" {
  description = "PostgreSQL endpoint."
  value       = module.db.endpoint
}
