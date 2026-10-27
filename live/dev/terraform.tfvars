# dev: smallest footprint, cheap and disposable.
environment = "dev"

vpc_cidr                = "10.10.0.0/16"
nat_gateway_mode        = "single"
flow_log_retention_days = 30

db = {
  instance_class                      = "db.t4g.micro"
  allocated_storage                   = 20
  max_allocated_storage               = 50
  multi_az                            = false
  backup_retention_days               = 7
  deletion_protection                 = false
  skip_final_snapshot                 = true
  performance_insights_retention_days = 7
  monitoring_interval                 = 0
}

app = {
  cpu                = 256
  memory             = 512
  desired_count      = 1
  min_capacity       = 1
  max_capacity       = 2
  use_fargate_spot   = true
  log_retention_days = 30
}
