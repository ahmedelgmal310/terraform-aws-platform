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

module "plan_role" {
  source = "../.."

  role_name = "github-terraform-plan"
  subjects = [
    "repo:my-org/infrastructure:pull_request",
    "repo:my-org/infrastructure:ref:refs/heads/main",
  ]

  policy_statements = [
    {
      sid       = "ReadState"
      actions   = ["s3:GetObject", "s3:ListBucket"]
      resources = ["arn:aws:s3:::my-org-tfstate", "arn:aws:s3:::my-org-tfstate/*"]
    },
    {
      sid       = "Lock"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
      resources = ["arn:aws:dynamodb:eu-west-1:111111111111:table/my-org-tfstate-lock"]
    },
  ]
}

output "role_arn" {
  description = "Use as role-to-assume in aws-actions/configure-aws-credentials."
  value       = module.plan_role.role_arn
}
