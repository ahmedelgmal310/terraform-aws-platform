# Unit tests: no AWS API is called. The aws provider is mocked and only the
# data sources whose values feed string interpolation are pinned.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-1" }
  }
  # Arguments that the provider validates as ARNs need ARN-shaped mock values.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/vpc-flow-logs/unit-vpc" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/unit-vpc-flow-logs" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }
}

variables {
  name       = "unit-vpc"
  cidr_block = "10.10.0.0/16"
  azs        = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

run "three_tier_layout" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3 && length(aws_subnet.intra) == 3
    error_message = "Expected one public, private and intra subnet per AZ."
  }

  assert {
    condition     = output.public_subnet_cidrs == ["10.10.0.0/20", "10.10.16.0/20", "10.10.32.0/20"]
    error_message = "Public subnets must be the first three /20 blocks."
  }

  assert {
    condition     = output.private_subnet_cidrs == ["10.10.48.0/20", "10.10.64.0/20", "10.10.80.0/20"]
    error_message = "Private subnets must follow the public subnets."
  }

  assert {
    condition     = output.intra_subnet_cidrs == ["10.10.96.0/20", "10.10.112.0/20", "10.10.128.0/20"]
    error_message = "Intra subnets must follow the private subnets."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Public subnets must not auto-assign public IPs."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames && aws_vpc.this.enable_dns_support
    error_message = "DNS support and hostnames must be enabled."
  }
}

run "single_nat_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eip.nat) == 1
    error_message = "Default mode must create exactly one NAT gateway."
  }

  assert {
    condition     = length(aws_route.private_nat) == 3
    error_message = "Every private route table needs a default route through the shared NAT."
  }
}

run "nat_per_az" {
  command = plan

  variables {
    nat_gateway_mode = "per_az"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "per_az must create one NAT gateway per AZ."
  }

  assert {
    condition     = length(aws_route.private_nat) == 3
    error_message = "per_az must route each private subnet through a NAT gateway."
  }
}

run "no_nat" {
  command = plan

  variables {
    nat_gateway_mode = "none"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_route.private_nat) == 0
    error_message = "none must not create NAT gateways or default routes."
  }
}

run "intra_has_no_internet_route" {
  command = apply

  assert {
    condition     = length([for r in aws_route.private_nat : r if r.route_table_id == aws_route_table.intra.id]) == 0
    error_message = "Intra route table must not have a default route."
  }
}

run "flow_logs_encrypted_with_dedicated_key" {
  command = plan

  variables {
    flow_log_retention_days = 365
  }

  assert {
    condition     = length(aws_flow_log.this) == 1 && aws_flow_log.this[0].traffic_type == "ALL"
    error_message = "Flow logs must be enabled and capture ALL traffic by default."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].retention_in_days == 365
    error_message = "Retention variable must reach the log group."
  }

  assert {
    condition     = length(aws_kms_key.flow_logs) == 1 && aws_kms_key.flow_logs[0].enable_key_rotation
    error_message = "A rotating KMS key must be created when none is supplied."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.flow_logs[0].policy).Statement[0].Resource == [
      "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/vpc-flow-logs/unit-vpc:*"
    ]
    error_message = "Flow log role must be scoped to its own log group."
  }
}

run "flow_logs_with_existing_key" {
  command = plan

  variables {
    flow_log_kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = length(aws_kms_key.flow_logs) == 0
    error_message = "No key must be created when an existing key ARN is given."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].kms_key_id == var.flow_log_kms_key_arn
    error_message = "Existing key must be used for the log group."
  }
}

run "flow_logs_disabled" {
  command = plan

  variables {
    enable_flow_logs = false
  }

  assert {
    condition     = length(aws_flow_log.this) == 0 && length(aws_kms_key.flow_logs) == 0 && length(aws_iam_role.flow_logs) == 0
    error_message = "Disabling flow logs must remove all flow log resources."
  }
}

run "rejects_public_cidr" {
  command = plan

  variables {
    cidr_block = "8.8.0.0/16"
  }

  expect_failures = [var.cidr_block]
}

run "rejects_too_small_prefix" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/8"
  }

  expect_failures = [var.cidr_block]
}

run "rejects_single_az" {
  command = plan

  variables {
    azs = ["eu-west-1a"]
  }

  expect_failures = [var.azs]
}

run "rejects_unknown_nat_mode" {
  command = plan

  variables {
    nat_gateway_mode = "two"
  }

  expect_failures = [var.nat_gateway_mode]
}

run "rejects_invalid_retention" {
  command = plan

  variables {
    flow_log_retention_days = 42
  }

  expect_failures = [var.flow_log_retention_days]
}

run "rejects_subnets_that_do_not_fit" {
  command = plan

  variables {
    subnet_newbits = 2
    azs            = ["eu-west-1a", "eu-west-1b"]
  }

  expect_failures = [var.subnet_newbits]
}
