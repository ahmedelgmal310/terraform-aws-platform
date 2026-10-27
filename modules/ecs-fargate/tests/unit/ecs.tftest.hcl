# ECS is not available in LocalStack Community, so this module is covered by
# mocked unit tests and by the per-environment plans only.

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
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/unit-svc" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:eu-west-1:123456789012:cluster/unit-svc" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:eu-west-1:123456789012:task-definition/unit-svc:1" }
  }
}

variables {
  name            = "unit-svc"
  vpc_id          = "vpc-0123456789abcdef0"
  subnet_ids      = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  container_image = "public.ecr.aws/nginx/nginx:1.29"
  secrets = {
    DATABASE_SECRET = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:db-AbCdEf"
  }
  environment = {
    LOG_LEVEL = "info"
  }
}

run "hardened_task_definition" {
  command = plan

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].readonlyRootFilesystem
    error_message = "Root filesystem must be read-only."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].linuxParameters.capabilities.drop == ["ALL"]
    error_message = "All Linux capabilities must be dropped."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets[0].valueFrom == var.secrets.DATABASE_SECRET
    error_message = "Secrets must be injected via valueFrom, not as plain environment variables."
  }

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment) == 1
    error_message = "Only the plain environment variables belong in environment."
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "256" && aws_ecs_task_definition.this.memory == "512"
    error_message = "Default size is 0.25 vCPU / 512 MiB."
  }
}

run "private_networking" {
  command = plan

  assert {
    condition     = one(aws_ecs_service.this.network_configuration).assign_public_ip == false
    error_message = "Tasks must not receive public IPs."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.app) == 0
    error_message = "No ingress unless a source security group is given."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.https.from_port == 443 && aws_vpc_security_group_egress_rule.https.to_port == 443
    error_message = "Internet egress must be limited to HTTPS."
  }

  assert {
    condition     = aws_ecs_service.this.enable_execute_command == false
    error_message = "ECS Exec must be off by default."
  }
}

run "execution_role_is_scoped" {
  command = plan

  assert {
    condition = contains(
      flatten([for s in jsondecode(aws_iam_role_policy.execution.policy).Statement : s.Resource if s.Sid == "ReadInjectedSecrets"]),
      "arn:aws:secretsmanager:eu-west-1:123456789012:secret:db-AbCdEf"
    )
    error_message = "Execution role may only read the injected secrets."
  }

  assert {
    condition = contains(
      flatten([for s in jsondecode(aws_iam_role_policy.execution.policy).Statement : s.Resource if s.Sid == "WriteOwnLogGroup"]),
      "arn:aws:logs:eu-west-1:123456789012:log-group:/ecs/unit-svc:*"
    )
    error_message = "Execution role may only write to its own log group."
  }
}

run "no_ecr_access_for_public_images" {
  command = plan

  assert {
    condition     = length([for s in jsondecode(aws_iam_role_policy.execution.policy).Statement : s if startswith(s.Sid, "Ecr") || startswith(s.Sid, "Pull")]) == 0
    error_message = "Execution role must not get ECR permissions when no repositories are given."
  }
}

run "ecr_pull_scoped_to_repositories" {
  command = plan

  variables {
    ecr_repository_arns = ["arn:aws:ecr:eu-west-1:123456789012:repository/app"]
  }

  assert {
    condition = flatten([
      for s in jsondecode(aws_iam_role_policy.execution.policy).Statement : s.Resource if s.Sid == "PullFromOwnRepositories"
    ]) == ["arn:aws:ecr:eu-west-1:123456789012:repository/app"]
    error_message = "Image pulls must be limited to the listed repositories."
  }
}

run "ingress_and_egress_rules" {
  command = plan

  variables {
    allowed_ingress_security_groups = { alb = "sg-0aaaaaaaaaaaaaaaa" }
    egress_rules = {
      postgres = { description = "PostgreSQL", port = 5432, security_group_id = "sg-0bbbbbbbbbbbbbbbb" }
    }
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.app["alb"].from_port == 8080 && aws_vpc_security_group_ingress_rule.app["alb"].referenced_security_group_id == "sg-0aaaaaaaaaaaaaaaa"
    error_message = "Ingress must be limited to the container port from the given security group."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.extra["postgres"].to_port == 5432
    error_message = "Extra egress rules must be keyed by their static name."
  }
}

run "spot_capacity" {
  command = plan

  variables {
    use_fargate_spot = true
  }

  assert {
    condition     = length(aws_ecs_service.this.capacity_provider_strategy) == 2
    error_message = "Spot mode must mix FARGATE (base) and FARGATE_SPOT."
  }
}

run "autoscaling_bounds" {
  command = plan

  variables {
    cpu           = 1024
    memory        = 2048
    desired_count = 3
    min_capacity  = 3
    max_capacity  = 10
  }

  assert {
    condition     = aws_appautoscaling_target.this.min_capacity == 3 && aws_appautoscaling_target.this.max_capacity == 10
    error_message = "Autoscaling bounds must follow the inputs."
  }

  assert {
    condition     = aws_appautoscaling_policy.cpu.target_tracking_scaling_policy_configuration[0].target_value == 60
    error_message = "CPU target tracking must default to 60%."
  }
}

run "rejects_latest_tag" {
  command = plan

  variables {
    container_image = "nginx:latest"
  }

  expect_failures = [var.container_image]
}

run "rejects_untagged_image" {
  command = plan

  variables {
    container_image = "nginx"
  }

  expect_failures = [var.container_image]
}

run "rejects_invalid_fargate_size" {
  command = plan

  variables {
    cpu    = 256
    memory = 4096
  }

  expect_failures = [var.memory]
}

run "rejects_privileged_port" {
  command = plan

  variables {
    container_port = 80
  }

  expect_failures = [var.container_port]
}

run "rejects_inverted_capacity" {
  command = plan

  variables {
    min_capacity = 5
    max_capacity = 2
  }

  expect_failures = [var.max_capacity]
}

run "rejects_plaintext_secret" {
  command = plan

  variables {
    secrets = { DB_PASSWORD = "hunter2" }
  }

  expect_failures = [var.secrets]
}
