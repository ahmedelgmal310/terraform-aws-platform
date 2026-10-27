variable "name" {
  description = "Name of the cluster and service (for example `acme-dev-api`)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "vpc_id" {
  description = "VPC of the service security group."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets the tasks run in. Tasks never get a public IP."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Use at least two subnets in different AZs."
  }
}

variable "container_image" {
  description = "Container image, pinned by tag or digest. `latest` and untagged images are rejected."
  type        = string

  validation {
    condition     = can(regex("(@sha256:[a-f0-9]{64}$)|(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$)", var.container_image)) && !endswith(var.container_image, ":latest")
    error_message = "container_image must be pinned to an explicit tag or sha256 digest, and must not use :latest."
  }
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1024 && var.container_port <= 65535
    error_message = "container_port must be an unprivileged port (1024-65535) so the container can run as non-root."
  }
}

variable "cpu" {
  description = "Task CPU units (256, 512, 1024, 2048, 4096, 8192 or 16384)."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu must be a Fargate CPU value: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "memory" {
  description = "Task memory in MiB. Must be a valid Fargate combination for the chosen CPU."
  type        = number
  default     = 512

  validation {
    condition = (
      var.cpu == 256 ? contains([512, 1024, 2048], var.memory) :
      var.cpu == 512 ? var.memory >= 1024 && var.memory <= 4096 && var.memory % 1024 == 0 :
      var.cpu == 1024 ? var.memory >= 2048 && var.memory <= 8192 && var.memory % 1024 == 0 :
      var.cpu == 2048 ? var.memory >= 4096 && var.memory <= 16384 && var.memory % 1024 == 0 :
      var.cpu == 4096 ? var.memory >= 8192 && var.memory <= 30720 && var.memory % 1024 == 0 :
      var.cpu == 8192 ? var.memory >= 16384 && var.memory <= 61440 && var.memory % 4096 == 0 :
      var.memory >= 32768 && var.memory <= 122880 && var.memory % 8192 == 0
    )
    error_message = "memory is not a valid Fargate combination for the selected cpu."
  }
}

variable "cpu_architecture" {
  description = "CPU architecture of the image: ARM64 (Graviton, cheaper) or X86_64."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "desired_count" {
  description = "Initial number of tasks. Autoscaling owns the value afterwards."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must not be negative."
  }
}

variable "min_capacity" {
  description = "Minimum number of tasks kept by autoscaling."
  type        = number
  default     = 1

  validation {
    condition     = var.min_capacity >= 0
    error_message = "min_capacity must not be negative."
  }
}

variable "max_capacity" {
  description = "Maximum number of tasks autoscaling may run."
  type        = number
  default     = 2

  validation {
    condition     = var.max_capacity >= var.min_capacity
    error_message = "max_capacity must be greater than or equal to min_capacity."
  }
}

variable "cpu_target_utilization" {
  description = "Average CPU utilisation (percent) that target tracking aims for."
  type        = number
  default     = 60

  validation {
    condition     = var.cpu_target_utilization >= 10 && var.cpu_target_utilization <= 90
    error_message = "cpu_target_utilization must be between 10 and 90."
  }
}

variable "use_fargate_spot" {
  description = "Prefer FARGATE_SPOT capacity (keeps one on-demand task as a base). Suitable for non-production."
  type        = bool
  default     = false
}

variable "environment" {
  description = "Plain-text environment variables for the container. Do not put secrets here; use `secrets`."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of environment variable name to Secrets Manager secret ARN (or SSM parameter ARN) injected at start-up."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for v in values(var.secrets) : can(regex("^arn:aws[a-z-]*:(secretsmanager|ssm):", v))])
    error_message = "secrets values must be Secrets Manager or SSM parameter ARNs."
  }
}

variable "ecr_repository_arns" {
  description = "Private ECR repositories the task execution role may pull from. Leave empty for public images."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.ecr_repository_arns : can(regex("^arn:aws[a-z-]*:ecr:[a-z0-9-]+:[0-9]{12}:repository/.+$", a))])
    error_message = "ecr_repository_arns must contain ECR repository ARNs (wildcards in the account or region are not allowed)."
  }
}

variable "allowed_ingress_security_group_ids" {
  description = "Security groups (for example a load balancer) allowed to reach the container port."
  type        = list(string)
  default     = []
}

variable "egress_rules" {
  description = "Additional egress to security groups inside the VPC, such as a database. HTTPS egress to the internet (image pulls, AWS APIs) is always allowed."
  type = list(object({
    description       = string
    port              = number
    security_group_id = string
  }))
  default = []
}

variable "log_retention_days" {
  description = "Retention of the container log group in days."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value."
  }
}

variable "kms_key_arn" {
  description = "KMS key used for the log group. When null a dedicated key with rotation is created."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
