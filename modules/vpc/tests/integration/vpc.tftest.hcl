# Integration test: applies the module against LocalStack, reads the result
# back through the AWS API and destroys everything at the end of the file.
# The endpoint comes from AWS_ENDPOINT_URL and the dummy credentials from the
# standard AWS_* environment variables (see .github/workflows/ci.yml).

provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

variables {
  name             = "it-vpc"
  cidr_block       = "10.42.0.0/16"
  azs              = ["us-east-1a", "us-east-1b", "us-east-1c"]
  nat_gateway_mode = "per_az"
  tags = {
    Environment = "test"
    Project     = "terraform-aws-platform"
  }
}

run "apply_vpc" {
  command = apply

  assert {
    condition     = startswith(output.vpc_id, "vpc-")
    error_message = "VPC was not created."
  }

  assert {
    condition     = length(output.public_subnet_ids) == 3 && length(output.private_subnet_ids) == 3 && length(output.intra_subnet_ids) == 3
    error_message = "Expected nine subnets across three tiers."
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 3
    error_message = "per_az mode must create three NAT gateways."
  }

  assert {
    condition     = output.flow_log_id != null && output.flow_log_group_name == "/aws/vpc-flow-logs/it-vpc"
    error_message = "Flow log was not created."
  }
}

run "read_back_from_api" {
  command = apply

  module {
    source = "./tests/integration/verify"
  }

  variables {
    vpc_id = run.apply_vpc.vpc_id
  }

  assert {
    condition     = output.cidr_block == "10.42.0.0/16"
    error_message = "VPC CIDR read from the API does not match."
  }

  assert {
    condition     = output.subnet_count == 9
    error_message = "API does not report nine subnets in the VPC."
  }

  assert {
    condition     = output.flow_log_count == 1
    error_message = "API does not report a flow log attached to the VPC."
  }

  assert {
    condition     = output.default_sg_ingress_rules == 0 && output.default_sg_egress_rules == 0
    error_message = "Default security group must have no rules."
  }
}
