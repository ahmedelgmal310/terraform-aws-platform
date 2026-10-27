# staging: production-shaped but single-AZ data tier and Spot capacity.
environment = "staging"

vpc_cidr                = "10.20.0.0/16"
nat_gateway_mode        = "single"
flow_log_retention_days = 90

db = {
  instance_class                      = "db.t4g.small"
  allocated_storage                   = 50
  max_allocated_storage               = 100
  multi_az                            = false
  backup_retention_days               = 14
  deletion_protection                 = true
  skip_final_snapshot                 = false
  performance_insights_retention_days = 7
  monitoring_interval                 = 60
}

app = {
  cpu                = 512
  memory             = 1024
  desired_count      = 2
  min_capacity       = 2
  max_capacity       = 4
  use_fargate_spot   = true
  log_retention_days = 90
}
