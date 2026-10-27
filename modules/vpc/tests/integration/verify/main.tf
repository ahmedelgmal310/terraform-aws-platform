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

variable "flow_log_group_name" {
  description = "Log group the module reported for flow logs."
  type        = string
}

data "aws_cloudwatch_log_group" "flow_logs" {
  name = var.flow_log_group_name
}

output "cidr_block" {
  description = "CIDR block reported by the API."
  value       = data.aws_vpc.this.cidr_block
}

output "subnet_count" {
  description = "Number of subnets reported by the API."
  value       = length(data.aws_subnets.all.ids)
}

output "flow_log_group_kms_key_id" {
  description = "KMS key protecting the flow log group, as reported by CloudWatch Logs."
  value       = data.aws_cloudwatch_log_group.flow_logs.kms_key_id
}

output "flow_log_group_retention" {
  description = "Retention of the flow log group, as reported by CloudWatch Logs."
  value       = data.aws_cloudwatch_log_group.flow_logs.retention_in_days
}

output "default_sg_ingress_rules" {
  description = "Ingress rules on the default security group."
  value       = length([for r in data.aws_vpc_security_group_rule.default : r if !r.is_egress])
}

output "default_sg_egress_rules" {
  description = "Egress rules on the default security group."
  value       = length([for r in data.aws_vpc_security_group_rule.default : r if r.is_egress])
}
