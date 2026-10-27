data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  create_kms_key = var.kms_key_arn == null
  kms_key_arn    = local.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn
  major_version  = split(".", var.engine_version)[0]
  port           = 5432

  tags = merge(var.tags, { "platform:module" = "rds-postgres" })
}

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "Encrypts RDS storage, Performance Insights and the master secret for ${var.identifier}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AccountAdministration"
      Effect    = "Allow"
      Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })

  tags = merge(local.tags, { Name = var.identifier })
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/rds/${var.identifier}"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_db_subnet_group" "this" {
  name        = var.identifier
  description = "Subnets for ${var.identifier}"
  subnet_ids  = var.subnet_ids

  tags = local.tags
}

resource "aws_security_group" "this" {
  name_prefix = "${var.identifier}-db-"
  description = "PostgreSQL access to ${var.identifier}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.identifier}-db" })

  lifecycle {
    create_before_destroy = true
  }
}

# No egress rules: the database never initiates connections.
resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  referenced_security_group_id = each.value

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "from_cidrs" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "PostgreSQL from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
  cidr_ipv4         = each.value

  tags = local.tags
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.identifier}-pg${local.major_version}-"
  family      = "postgres${local.major_version}"
  description = "Hardened parameters for ${var.identifier}"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name_prefix = "${substr(var.identifier, 0, 24)}-rds-mon-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class
  port           = local.port
  db_name        = var.db_name

  username                      = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = local.kms_key_arn

  iam_database_authentication_enabled = true

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = local.kms_key_arn

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.this.name

  backup_retention_period   = var.backup_retention_days
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final"

  auto_minor_version_upgrade      = true
  allow_major_version_upgrade     = false
  apply_immediately               = var.apply_immediately
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  performance_insights_enabled          = var.performance_insights_retention_days > 0
  performance_insights_kms_key_id       = var.performance_insights_retention_days > 0 ? local.kms_key_arn : null
  performance_insights_retention_period = var.performance_insights_retention_days > 0 ? var.performance_insights_retention_days : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  tags = merge(local.tags, { Name = var.identifier })

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}
