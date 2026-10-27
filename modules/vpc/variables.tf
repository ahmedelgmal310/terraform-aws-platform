variable "name" {
  description = "Name prefix applied to every resource in the VPC (for example `acme-dev`)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "cidr_block" {
  description = "IPv4 CIDR block of the VPC. Must be a private (RFC 1918) range between /16 and /24."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR, for example 10.10.0.0/16."
  }

  validation {
    condition = try(
      tonumber(split("/", var.cidr_block)[1]) >= 16 && tonumber(split("/", var.cidr_block)[1]) <= 24,
      false
    )
    error_message = "cidr_block prefix length must be between /16 and /24."
  }

  validation {
    condition = anytrue([
      startswith(var.cidr_block, "10."),
      can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.cidr_block)),
      startswith(var.cidr_block, "192.168."),
    ])
    error_message = "cidr_block must be inside an RFC 1918 private range (10/8, 172.16/12 or 192.168/16)."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across. One public, one private and one intra subnet is created per AZ."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 4
    error_message = "Provide between 2 and 4 availability zones (3 is recommended)."
  }

  validation {
    condition     = length(distinct(var.azs)) == length(var.azs)
    error_message = "azs must not contain duplicates."
  }
}

variable "subnet_newbits" {
  description = "Number of bits added to the VPC prefix for every subnet (a /16 VPC with 4 newbits yields /20 subnets)."
  type        = number
  default     = 4

  validation {
    condition     = var.subnet_newbits >= 2 && var.subnet_newbits <= 8
    error_message = "subnet_newbits must be between 2 and 8."
  }

  validation {
    condition     = 3 * length(var.azs) <= pow(2, var.subnet_newbits)
    error_message = "subnet_newbits is too small: three subnet tiers per AZ do not fit in the VPC range."
  }
}

variable "nat_gateway_mode" {
  description = "Egress for private subnets: `none` (no NAT), `single` (one shared NAT gateway, cheaper) or `per_az` (one NAT gateway per AZ, highly available)."
  type        = string
  default     = "single"

  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be one of: none, single, per_az."
  }
}

variable "enable_flow_logs" {
  description = "Ship VPC flow logs to an encrypted CloudWatch Logs group."
  type        = bool
  default     = true
}

variable "flow_log_traffic_type" {
  description = "Traffic captured by the flow log: ACCEPT, REJECT or ALL."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "flow_log_retention_days" {
  description = "Retention of the flow log group in days. Must be a value CloudWatch Logs accepts."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}

variable "flow_log_kms_key_arn" {
  description = "ARN of an existing KMS key used to encrypt the flow log group. When null a dedicated key with rotation is created."
  type        = string
  default     = null

  validation {
    condition     = var.flow_log_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.flow_log_kms_key_arn))
    error_message = "flow_log_kms_key_arn must be a KMS key ARN."
  }
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
