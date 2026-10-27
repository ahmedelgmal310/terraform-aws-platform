package terraform.sizing_test

import data.terraform.sizing

rc(type, env, after) := {
	"address": concat(".", [type, "this"]),
	"mode": "managed",
	"type": type,
	"change": {
		"actions": ["create"],
		"after": object.union(after, {"tags_all": {"Environment": env}}),
		"after_unknown": {},
	},
}

db(env, overrides) := rc("aws_db_instance", env, object.union(
	{
		"instance_class": "db.t4g.micro",
		"max_allocated_storage": 50,
		"backup_retention_period": 7,
		"multi_az": false,
		"deletion_protection": false,
		"skip_final_snapshot": true,
	},
	overrides,
))

prod_db(overrides) := db("prod", object.union(
	{
		"instance_class": "db.r7g.large",
		"max_allocated_storage": 500,
		"backup_retention_period": 35,
		"multi_az": true,
		"deletion_protection": true,
		"skip_final_snapshot": false,
	},
	overrides,
))

test_dev_micro_db_passes if {
	count(sizing.deny) == 0 with input as {"resource_changes": [db("dev", {})]}
}

test_dev_large_db_denied if {
	some msg in sizing.deny with input as {"resource_changes": [db("dev", {"instance_class": "db.r7g.large"})]}
	contains(msg, "not allowed in dev")
}

test_dev_storage_ceiling_denied if {
	some msg in sizing.deny with input as {"resource_changes": [db("dev", {"max_allocated_storage": 1000})]}
	contains(msg, "storage ceiling")
}

test_prod_db_passes if {
	count(sizing.deny) == 0 with input as {"resource_changes": [prod_db({})]}
}

test_prod_single_az_denied if {
	some msg in sizing.deny with input as {"resource_changes": [prod_db({"multi_az": false})]}
	contains(msg, "multi_az must be enabled in prod")
}

test_prod_without_deletion_protection_denied if {
	some msg in sizing.deny with input as {"resource_changes": [prod_db({"deletion_protection": false})]}
	contains(msg, "deletion_protection")
}

test_prod_short_backups_denied if {
	some msg in sizing.deny with input as {"resource_changes": [prod_db({"backup_retention_period": 7})]}
	contains(msg, "at least 30 days")
}

test_prod_skip_final_snapshot_denied if {
	some msg in sizing.deny with input as {"resource_changes": [prod_db({"skip_final_snapshot": true})]}
	contains(msg, "final snapshot")
}

test_dev_task_cpu_limit if {
	td := rc("aws_ecs_task_definition", "dev", {"cpu": "2048"})
	some msg in sizing.deny with input as {"resource_changes": [td]}
	contains(msg, "task CPU 2048")
}

test_staging_task_cpu_within_limit if {
	td := rc("aws_ecs_task_definition", "staging", {"cpu": "1024"})
	count(sizing.deny) == 0 with input as {"resource_changes": [td]}
}

test_dev_autoscaling_limit if {
	target := rc("aws_appautoscaling_target", "dev", {"max_capacity": 10})
	some msg in sizing.deny with input as {"resource_changes": [target]}
	contains(msg, "max_capacity 10")
}

test_prod_spot_denied if {
	svc := rc("aws_ecs_service", "prod", {"capacity_provider_strategy": [
		{"capacity_provider": "FARGATE", "weight": 0, "base": 1},
		{"capacity_provider": "FARGATE_SPOT", "weight": 1, "base": 0},
	]})
	some msg in sizing.deny with input as {"resource_changes": [svc]}
	contains(msg, "FARGATE_SPOT")
}

test_dev_spot_allowed if {
	svc := rc("aws_ecs_service", "dev", {"capacity_provider_strategy": [{"capacity_provider": "FARGATE_SPOT", "weight": 1, "base": 0}]})
	count(sizing.deny) == 0 with input as {"resource_changes": [svc]}
}

test_prod_short_log_retention_denied if {
	lg := rc("aws_cloudwatch_log_group", "prod", {"retention_in_days": 30})
	some msg in sizing.deny with input as {"resource_changes": [lg]}
	contains(msg, "365 days")
}
