# Read-only helper used by the integration test to confirm, through the AWS
# API, that the resources the module reported actually exist.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

variable "vpc_id" {
  description = "VPC to inspect."
  type        = string
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_security_group" "default" {
  vpc_id = var.vpc_id
  name   = "default"
}

data "aws_vpc_security_group_rules" "default" {
  filter {
    name   = "group-id"
    values = [data.aws_security_group.default.id]
  }
}

data "aws_vpc_security_group_rule" "default" {
  for_each               = toset(data.aws_vpc_security_group_rules.default.ids)
  security_group_rule_id = each.value
}

data "aws_flow_logs" "vpc" {
  filter {
    name   = "resource-id"
    values = [var.vpc_id]
  }
}

output "cidr_block" {
  description = "CIDR block reported by the API."
  value       = data.aws_vpc.this.cidr_block
}

output "subnet_count" {
  description = "Number of subnets reported by the API."
  value       = length(data.aws_subnets.all.ids)
}

output "flow_log_count" {
  description = "Number of flow logs attached to the VPC."
  value       = length(data.aws_flow_logs.vpc.ids)
}

output "default_sg_ingress_rules" {
  description = "Ingress rules on the default security group."
  value       = length([for r in data.aws_vpc_security_group_rule.default : r if !r.is_egress])
}

output "default_sg_egress_rules" {
  description = "Egress rules on the default security group."
  value       = length([for r in data.aws_vpc_security_group_rule.default : r if r.is_egress])
}
