data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  create_kms_key = var.kms_key_arn == null
  kms_key_arn    = local.create_kms_key ? aws_kms_key.logs[0].arn : var.kms_key_arn

  log_group_name = "/ecs/${var.name}"
  log_group_arn  = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}"

  container_definitions = [{
    name                   = var.name
    image                  = var.container_image
    essential              = true
    readonlyRootFilesystem = true
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    environment = [for k in sort(keys(var.environment)) : { name = k, value = var.environment[k] }]
    secrets     = [for k in sort(keys(var.secrets)) : { name = k, valueFrom = var.secrets[k] }]
    linuxParameters = {
      initProcessEnabled = true
      capabilities       = { drop = ["ALL"] }
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = local.log_group_name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "app"
      }
    }
  }]

  tags = merge(var.tags, { "platform:module" = "ecs-fargate" })
}

################################################################################
# Cluster
################################################################################

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  # ECS Exec stays disabled on the service; this only guarantees that if it
  # is ever turned on, sessions are encrypted and audited.
  configuration {
    execute_command_configuration {
      kms_key_id = local.kms_key_arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.this.name
      }
    }
  }

  tags = local.tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 1
    weight            = var.use_fargate_spot ? 0 : 1
  }

  dynamic "default_capacity_provider_strategy" {
    for_each = var.use_fargate_spot ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = 1
    }
  }
}

################################################################################
# Logging
################################################################################

resource "aws_kms_key" "logs" {
  count = local.create_kms_key ? 1 : 0

  description             = "Encrypts container logs for ${var.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogsUse"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = local.log_group_arn }
        }
      },
    ]
  })

  tags = merge(local.tags, { Name = "${var.name}-logs" })
}

resource "aws_kms_alias" "logs" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/${var.name}-ecs-logs"
  target_key_id = aws_kms_key.logs[0].key_id
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = local.kms_key_arn

  tags = local.tags
}

################################################################################
# IAM
################################################################################

locals {
  ecs_tasks_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

# Used by the ECS agent to pull the image, write logs and resolve secrets.
resource "aws_iam_role" "execution" {
  name_prefix        = "${substr(var.name, 0, 24)}-exec-"
  assume_role_policy = local.ecs_tasks_trust

  tags = local.tags
}

resource "aws_iam_role_policy" "execution" {
  name = "task-execution"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "WriteOwnLogGroup"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = ["${local.log_group_arn}:*"]
        },
      ],
      length(var.ecr_repository_arns) == 0 ? [] : [
        {
          # GetAuthorizationToken does not support resource-level permissions.
          Sid      = "EcrLogin"
          Effect   = "Allow"
          Action   = ["ecr:GetAuthorizationToken"]
          Resource = ["*"]
        },
        {
          Sid      = "PullFromOwnRepositories"
          Effect   = "Allow"
          Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
          Resource = var.ecr_repository_arns
        },
      ],
      length(var.secrets) == 0 ? [] : [{
        Sid      = "ReadInjectedSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "ssm:GetParameters"]
        Resource = distinct(values(var.secrets))
      }],
    )
  })
}

# Assumed by the application itself. Starts with no permissions; callers
# attach what the workload needs through the task_role_name output.
resource "aws_iam_role" "task" {
  name_prefix        = "${substr(var.name, 0, 24)}-task-"
  assume_role_policy = local.ecs_tasks_trust

  tags = local.tags
}

################################################################################
# Networking
################################################################################

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-svc-"
  description = "ECS service ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name}-svc" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "app" {
  for_each = toset(var.allowed_ingress_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "App traffic from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = each.value

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to AWS APIs and registries"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "extra" {
  for_each = { for r in var.egress_rules : "${r.security_group_id}-${r.port}" => r }

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.security_group_id

  tags = local.tags
}

################################################################################
# Task definition and service
################################################################################

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode(local.container_definitions)

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  tags = local.tags
}

resource "aws_ecs_service" "this" {
  name                    = var.name
  cluster                 = aws_ecs_cluster.this.id
  task_definition         = aws_ecs_task_definition.this.arn
  desired_count           = var.desired_count
  enable_execute_command  = false
  propagate_tags          = "SERVICE"
  enable_ecs_managed_tags = true
  platform_version        = "LATEST"

  dynamic "capacity_provider_strategy" {
    for_each = var.use_fargate_spot ? { FARGATE = 0, FARGATE_SPOT = 1 } : { FARGATE = 1 }
    content {
      capacity_provider = capacity_provider_strategy.key
      weight            = capacity_provider_strategy.value
      base              = capacity_provider_strategy.key == "FARGATE" ? 1 : 0
    }
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}

resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity

  tags = local.tags
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_utilization
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
