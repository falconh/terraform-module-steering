################################################################################
# Required inputs
################################################################################

variable "name" {
  description = "Base name/identifier for the ElastiCache replication group and its companion resources (KMS key alias, secret, security group, subnet group). Lowercased by ElastiCache."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name))
    error_message = "name must be 2-40 chars, start with a letter, contain only lowercase letters, digits and hyphens, and not end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment. Drives the mandatory Environment tag."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "vpc_id" {
  description = "Identifier of the VPC where the module-managed security group is created."
  type        = string
}

variable "subnet_ids" {
  description = "List of VPC subnet IDs for the (custom, non-default) ElastiCache subnet group. Enforces FSBP ElastiCache.7 (no default subnet group). Use subnets in at least two AZs for Multi-AZ."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Provide at least two subnet_ids (in different AZs) so Multi-AZ automatic failover can place nodes across AZs."
  }
}

################################################################################
# Write-only AUTH token (ephemeral — never stored in Terraform state)
################################################################################

variable "auth_token_wo" {
  description = "The Redis AUTH token (password). Declared write-only/ephemeral: it is NEVER persisted to Terraform state or plan files. It is written only to the module-managed AWS Secrets Manager secret via the provider's write-only `secret_string_wo` sink. Must be 16-128 printable characters."
  type        = string
  ephemeral   = true
  sensitive   = true

  validation {
    # length() works on ephemeral values; the literal is never persisted.
    condition     = length(var.auth_token_wo) >= 16 && length(var.auth_token_wo) <= 128
    error_message = "auth_token_wo must be between 16 and 128 characters (ElastiCache Redis AUTH requirement)."
  }
}

variable "auth_token_wo_version" {
  description = "Monotonic version for the write-only AUTH token. Increment this whenever you supply a new auth_token_wo to trigger a new Secrets Manager secret version (write-only values cannot be diffed, so rotation is version-driven)."
  type        = number
  default     = 1

  validation {
    condition     = var.auth_token_wo_version >= 1 && floor(var.auth_token_wo_version) == var.auth_token_wo_version
    error_message = "auth_token_wo_version must be a positive integer."
  }
}

################################################################################
# Optional inputs (safe defaults)
################################################################################

variable "node_type" {
  description = "ElastiCache node instance class for the replication group."
  type        = string
  default     = "cache.t4g.small"
}

variable "engine_version" {
  description = "Redis engine version. Pinned to a RBAC-capable (>= 6.0) line by default."
  type        = string
  default     = "7.1"
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (primary + replicas) in the replication group. Must be >= 2 so Multi-AZ automatic failover has a replica to promote."
  type        = number
  default     = 2

  validation {
    condition     = var.num_cache_clusters >= 2
    error_message = "num_cache_clusters must be at least 2 (a primary and at least one replica) for Multi-AZ automatic failover."
  }
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks permitted to reach the Redis port (6379/TLS) on the module-managed security group. Empty by default (no ingress until you scope it)."
  type        = list(string)
  default     = []
}

variable "apply_immediately" {
  description = "Whether modifications are applied immediately rather than in the next maintenance window."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply. Mandatory tags (Environment, ManagedBy, Module) are merged over these and cannot be dropped."
  type        = map(string)
  default     = {}
}
