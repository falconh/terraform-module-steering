variable "name" {
  description = "Base name for the replication group and its companion resources (KMS alias, Secrets Manager secret, subnet group, security group)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name))
    error_message = "name must be 2-40 chars, lowercase alphanumeric/hyphen, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment. Drives mandatory tagging."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "vpc_id" {
  description = "VPC in which the module-managed security group is created."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the custom cache subnet group. Must NOT be the default subnet group (FSBP ElastiCache.7). Provide at least two subnets in different AZs for multi-AZ."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Provide at least two subnet IDs in different AZs so multi-AZ with automatic failover is satisfiable."
  }
}

variable "auth_token" {
  description = "Redis AUTH token (password). WRITE-ONLY: declared ephemeral + sensitive, so it is NEVER persisted to Terraform state or plan. It is stored only in AWS Secrets Manager via the write-only secret_string_wo argument. Must be 16-128 printable characters with no '/', '\"', '@', or spaces (ElastiCache AUTH constraints)."
  type        = string
  ephemeral   = true
  sensitive   = true

  validation {
    condition     = can(regex("^[ -~]{16,128}$", var.auth_token)) && !can(regex("[/\"@ ]", var.auth_token))
    error_message = "auth_token must be 16-128 printable ASCII chars and must not contain '/', '\"', '@', or spaces."
  }
}

variable "auth_token_rotation" {
  description = "Monotonic integer that triggers re-application of the write-only AUTH token to Secrets Manager. Increment to rotate the stored secret value."
  type        = number
  default     = 1

  validation {
    condition     = var.auth_token_rotation >= 1
    error_message = "auth_token_rotation must be >= 1."
  }
}

variable "node_type" {
  description = "Cache node instance type. Default is a small Graviton node that supports TLS and AUTH."
  type        = string
  default     = "cache.t4g.small"
}

variable "engine_version" {
  description = "Redis OSS engine version. Default 7.1 supports TLS and AUTH."
  type        = string
  default     = "7.1"
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (1 primary + N-1 replicas). Minimum 2 so automatic failover and multi-AZ are valid."
  type        = number
  default     = 2

  validation {
    condition     = var.num_cache_clusters >= 2
    error_message = "num_cache_clusters must be >= 2 to support automatic failover and multi-AZ (1 primary + at least 1 replica)."
  }
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period (days) before the customer-managed KMS key is deleted after destruction."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30."
  }
}

variable "cloudwatch_log_retention_in_days" {
  description = "Retention (days) for the slow-log CloudWatch log group created by the module."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Additional tags merged UNDER the module's mandatory tags (consumer tags cannot drop the mandatory ones)."
  type        = map(string)
  default     = {}
}
