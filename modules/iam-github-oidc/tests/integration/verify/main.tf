# Read-only helper used by the integration test to read the role and the
# OIDC provider back from the IAM API.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

variable "role_name" {
  description = "Role to inspect."
  type        = string
}

data "aws_iam_role" "this" {
  name = var.role_name
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  trust = jsondecode(data.aws_iam_role.this.assume_role_policy)
}

output "trusted_subjects" {
  description = "Subject claims allowed by the live trust policy."
  value       = flatten([local.trust.Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]])
}

output "provider_client_ids" {
  description = "Audiences registered on the live OIDC provider."
  value       = tolist(data.aws_iam_openid_connect_provider.github.client_id_list)
}
