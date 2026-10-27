# RDS is not available in LocalStack Community, so this module is covered by
# mocked unit tests and by the per-environment plans only.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/unit-db-rds-mon" }
  }
}

variables {
  identifier                 = "unit-db"
  instance_class             = "db.t4g.micro"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb", "subnet-0cccccccccccccccc"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
}

run "encrypted_private_and_backed_up" {
  command = plan

  assert {
    condition     = aws_db_instance.this.storage_encrypted
    error_message = "Storage must be encrypted."
  }

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "Instance must not be publicly accessible."
  }

  assert {
    condition     = aws_db_instance.this.iam_database_authentication_enabled
    error_message = "IAM database authentication must be enabled."
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password
    error_message = "Master password must be managed by RDS in Secrets Manager."
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period == 7 && aws_db_instance.this.copy_tags_to_snapshot
    error_message = "Backups must be retained for 7 days by default and snapshots tagged."
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection && aws_db_instance.this.skip_final_snapshot == false
    error_message = "Deletion protection and a final snapshot are the defaults."
  }

  assert {
    condition     = aws_db_instance.this.final_snapshot_identifier == "unit-db-final"
    error_message = "Final snapshot identifier must be derived from the identifier."
  }

  assert {
    condition     = length(aws_kms_key.this) == 1 && aws_kms_key.this[0].enable_key_rotation
    error_message = "A rotating KMS key must be created when none is supplied."
  }

  assert {
    condition     = toset(aws_db_instance.this.enabled_cloudwatch_logs_exports) == toset(["postgresql", "upgrade"])
    error_message = "PostgreSQL and upgrade logs must be exported."
  }
}

run "tls_is_forced" {
  command = plan

  assert {
    condition     = anytrue([for p in aws_db_parameter_group.this.parameter : p.name == "rds.force_ssl" && p.value == "1"])
    error_message = "Parameter group must force TLS."
  }

  assert {
    condition     = aws_db_parameter_group.this.family == "postgres17"
    error_message = "Parameter group family must follow the engine major version."
  }
}

run "network_access_is_scoped" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_security_groups) == 1 && length(aws_vpc_security_group_ingress_rule.from_cidrs) == 0
    error_message = "Only the allowed security group may connect."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_security_groups["sg-0123456789abcdef0"].from_port == 5432 && aws_vpc_security_group_ingress_rule.from_security_groups["sg-0123456789abcdef0"].to_port == 5432
    error_message = "Ingress must be limited to the PostgreSQL port."
  }
}

run "production_profile" {
  command = plan

  variables {
    instance_class                      = "db.r7g.large"
    multi_az                            = true
    backup_retention_days               = 35
    performance_insights_retention_days = 93
    engine_version                      = "16.4"
  }

  assert {
    condition     = aws_db_instance.this.multi_az && aws_db_instance.this.backup_retention_period == 35
    error_message = "Production profile must be Multi-AZ with 35 days of backups."
  }

  assert {
    condition     = aws_db_instance.this.performance_insights_enabled && aws_db_instance.this.performance_insights_retention_period == 93
    error_message = "Performance Insights retention must be applied."
  }

  assert {
    condition     = aws_db_parameter_group.this.family == "postgres16"
    error_message = "Minor versions must map to the major family."
  }
}

run "monitoring_disabled" {
  command = plan

  variables {
    monitoring_interval                 = 0
    performance_insights_retention_days = 0
  }

  assert {
    condition     = length(aws_iam_role.monitoring) == 0 && aws_db_instance.this.performance_insights_enabled == false
    error_message = "Disabling monitoring must not create the monitoring role."
  }
}

run "rejects_public_cidr" {
  command = plan

  variables {
    allowed_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "rejects_disabled_backups" {
  command = plan

  variables {
    backup_retention_days = 0
  }

  expect_failures = [var.backup_retention_days]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_unsupported_engine" {
  command = plan

  variables {
    engine_version = "11.22"
  }

  expect_failures = [var.engine_version]
}

run "rejects_reserved_username" {
  command = plan

  variables {
    master_username = "postgres"
  }

  expect_failures = [var.master_username]
}

run "rejects_storage_ceiling_below_floor" {
  command = plan

  variables {
    allocated_storage     = 200
    max_allocated_storage = 100
  }

  expect_failures = [var.max_allocated_storage]
}
