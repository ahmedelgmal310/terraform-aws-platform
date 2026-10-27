# Identical in every environment; only terraform.tfvars differs. CI fails if
# the shared files drift apart (see the "drift" step in .github/workflows/ci.yml).

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name       = "${var.project}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  azs        = slice(sort(data.aws_availability_zones.available.names), 0, 3)

  artifacts_bucket = "${local.name}-artifacts-${local.account_id}"
  logs_bucket      = "${local.name}-access-logs-${local.account_id}"
}

module "vpc" {
  source = "../../modules/vpc"

  name                    = local.name
  cidr_block              = var.vpc_cidr
  azs                     = local.azs
  nat_gateway_mode        = var.nat_gateway_mode
  enable_flow_logs        = true
  flow_log_retention_days = var.flow_log_retention_days
}

module "access_logs_bucket" {
  source = "../../modules/s3-secure-bucket"

  bucket_name        = local.logs_bucket
  accept_access_logs = true
}

module "artifacts_bucket" {
  source = "../../modules/s3-secure-bucket"

  bucket_name       = local.artifacts_bucket
  access_log_bucket = module.access_logs_bucket.bucket_id
}

module "app" {
  source = "../../modules/ecs-fargate"

  name               = "${local.name}-app"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  container_image    = var.container_image
  cpu                = var.app.cpu
  memory             = var.app.memory
  desired_count      = var.app.desired_count
  min_capacity       = var.app.min_capacity
  max_capacity       = var.app.max_capacity
  use_fargate_spot   = var.app.use_fargate_spot
  log_retention_days = var.app.log_retention_days

  environment = {
    APP_ENV          = var.environment
    ARTIFACTS_BUCKET = local.artifacts_bucket
    DB_HOST          = module.db.address
  }

  secrets = {
    DB_MASTER_SECRET = module.db.master_user_secret_arn
  }

  egress_rules = [{
    description       = "PostgreSQL"
    port              = 5432
    security_group_id = module.db.security_group_id
  }]
}

module "db" {
  source = "../../modules/rds-postgres"

  identifier                 = "${local.name}-db"
  instance_class             = var.db.instance_class
  allocated_storage          = var.db.allocated_storage
  max_allocated_storage      = var.db.max_allocated_storage
  multi_az                   = var.db.multi_az
  backup_retention_days      = var.db.backup_retention_days
  deletion_protection        = var.db.deletion_protection
  skip_final_snapshot        = var.db.skip_final_snapshot
  monitoring_interval        = var.db.monitoring_interval
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.intra_subnet_ids
  allowed_security_group_ids = [module.app.security_group_id]

  performance_insights_retention_days = var.db.performance_insights_retention_days
}

# Role for this repository's deploy workflow (GitHub environment = var.environment).
# It can ship artifacts and roll the ECS service, nothing else.
module "deploy_role" {
  source = "../../modules/iam-github-oidc"

  role_name = "${local.name}-github-deploy"
  subjects  = ["repo:${var.github_repository}:environment:${var.environment}"]

  policy_statements = [
    {
      sid       = "ListArtifacts"
      actions   = ["s3:ListBucket"]
      resources = ["arn:${local.partition}:s3:::${local.artifacts_bucket}"]
    },
    {
      sid       = "ReadWriteArtifacts"
      actions   = ["s3:GetObject", "s3:PutObject"]
      resources = ["arn:${local.partition}:s3:::${local.artifacts_bucket}/*"]
    },
    {
      sid       = "UseArtifactsKeyThroughS3"
      actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
      resources = [module.artifacts_bucket.kms_key_arn]
      conditions = [
        { test = "StringEquals", variable = "kms:ViaService", values = ["s3.${var.region}.amazonaws.com"] },
        { test = "StringEquals", variable = "kms:CallerAccount", values = [local.account_id] },
      ]
    },
    {
      sid       = "RegisterTaskDefinitions"
      actions   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
      resources = ["*"]
    },
    {
      sid       = "RollService"
      actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
      resources = ["arn:${local.partition}:ecs:${var.region}:${local.account_id}:service/${local.name}-app/${local.name}-app"]
    },
    {
      sid     = "PassTaskRoles"
      actions = ["iam:PassRole"]
      resources = [
        "arn:${local.partition}:iam::${local.account_id}:role/${local.name}-app-exec-*",
        "arn:${local.partition}:iam::${local.account_id}:role/${local.name}-app-task-*",
      ]
      conditions = [
        { test = "StringEquals", variable = "iam:PassedToService", values = ["ecs-tasks.amazonaws.com"] },
      ]
    },
  ]
}
