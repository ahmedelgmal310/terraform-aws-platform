# Per-environment size limits and resilience floors. Environment is read from
# the Environment tag that the provider's default_tags put on every resource.
package terraform.sizing

import data.terraform.lib

limits := {
	"dev": {
		"db_instance_classes": {"db.t4g.micro", "db.t4g.small"},
		"max_db_storage_gib": 100,
		"max_task_cpu": 512,
		"max_tasks": 2,
		"min_backup_days": 1,
	},
	"staging": {
		"db_instance_classes": {"db.t4g.small", "db.t4g.medium", "db.t4g.large"},
		"max_db_storage_gib": 500,
		"max_task_cpu": 1024,
		"max_tasks": 4,
		"min_backup_days": 7,
	},
	"prod": {
		"db_instance_classes": {
			"db.t4g.large",
			"db.m7g.large", "db.m7g.xlarge", "db.m7g.2xlarge",
			"db.r7g.large", "db.r7g.xlarge", "db.r7g.2xlarge",
		},
		"max_db_storage_gib": 2000,
		"max_task_cpu": 4096,
		"max_tasks": 20,
		"min_backup_days": 30,
	},
}

deny contains msg if {
	some db in lib.changes_of("aws_db_instance")
	env := lib.environment(db)
	class := lib.after(db).instance_class
	not class in limits[env].db_instance_classes
	msg := sprintf("%s: instance class %s is not allowed in %s (allowed: %v)", [db.address, class, env, sort(limits[env].db_instance_classes)])
}

deny contains msg if {
	some db in lib.changes_of("aws_db_instance")
	env := lib.environment(db)
	max_storage := object.get(lib.after(db), "max_allocated_storage", 0)
	max_storage > limits[env].max_db_storage_gib
	msg := sprintf("%s: storage ceiling %d GiB exceeds the %s limit of %d GiB", [db.address, max_storage, env, limits[env].max_db_storage_gib])
}

deny contains msg if {
	some db in lib.changes_of("aws_db_instance")
	env := lib.environment(db)
	lib.after(db).backup_retention_period < limits[env].min_backup_days
	msg := sprintf("%s: %s requires a backup retention of at least %d days", [db.address, env, limits[env].min_backup_days])
}

deny contains msg if {
	some db in lib.changes_of("aws_db_instance")
	lib.environment(db) == "prod"
	some setting in ["multi_az", "deletion_protection"]
	lib.after(db)[setting] != true
	msg := sprintf("%s: %s must be enabled in prod", [db.address, setting])
}

deny contains msg if {
	some db in lib.changes_of("aws_db_instance")
	lib.environment(db) == "prod"
	lib.after(db).skip_final_snapshot == true
	msg := sprintf("%s: prod databases must take a final snapshot", [db.address])
}

deny contains msg if {
	some td in lib.changes_of("aws_ecs_task_definition")
	env := lib.environment(td)
	cpu := to_number(lib.after(td).cpu)
	cpu > limits[env].max_task_cpu
	msg := sprintf("%s: task CPU %d exceeds the %s limit of %d", [td.address, cpu, env, limits[env].max_task_cpu])
}

deny contains msg if {
	some target in lib.changes_of("aws_appautoscaling_target")
	env := lib.environment(target)
	lib.after(target).max_capacity > limits[env].max_tasks
	msg := sprintf("%s: max_capacity %d exceeds the %s limit of %d tasks", [target.address, lib.after(target).max_capacity, env, limits[env].max_tasks])
}

deny contains msg if {
	some svc in lib.changes_of("aws_ecs_service")
	lib.environment(svc) == "prod"
	some strategy in lib.after(svc).capacity_provider_strategy
	strategy.capacity_provider == "FARGATE_SPOT"
	strategy.weight > 0
	msg := sprintf("%s: prod services must not run on FARGATE_SPOT", [svc.address])
}

deny contains msg if {
	some lg in lib.changes_of("aws_cloudwatch_log_group")
	lib.environment(lg) == "prod"
	lib.after(lg).retention_in_days < 365
	msg := sprintf("%s: prod log groups must be retained for at least 365 days", [lg.address])
}
