# prod: NAT and database standby in every AZ, long retention, on-demand capacity.
environment = "prod"

vpc_cidr                = "10.30.0.0/16"
nat_gateway_mode        = "per_az"
flow_log_retention_days = 365

db = {
  instance_class                      = "db.r7g.large"
  allocated_storage                   = 100
  max_allocated_storage               = 500
  multi_az                            = true
  backup_retention_days               = 35
  deletion_protection                 = true
  skip_final_snapshot                 = false
  performance_insights_retention_days = 93
  monitoring_interval                 = 15
}

app = {
  cpu                = 1024
  memory             = 2048
  desired_count      = 3
  min_capacity       = 3
  max_capacity       = 10
  use_fargate_spot   = false
  log_retention_days = 365
}
