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

  name       = "example-svc"
  cidr_block = "10.60.0.0/16"
  azs        = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

module "service" {
  source = "../.."

  name            = "example-svc"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  container_image = "public.ecr.aws/nginx/nginx:1.29"
  cpu             = 512
  memory          = 1024
  min_capacity    = 2
  max_capacity    = 6

  environment = {
    LOG_LEVEL = "info"
  }
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = module.service.cluster_name
}
