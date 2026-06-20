variable "name" {
  description = "Name of the private ECR repository to create."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._/-][a-z0-9]+)*$", var.name))
    error_message = "name must be a valid ECR repository name: lowercase alphanumerics, optionally separated by '.', '_', '-' or '/'."
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

variable "tags" {
  description = "Additional tags to apply. Mandatory tags (Environment, ManagedBy, Module) are merged on top and cannot be overridden."
  type        = map(string)
  default     = {}
}

variable "force_delete" {
  description = "If true, the repository can be destroyed even while it still contains images. Defaults to the safe value (false)."
  type        = bool
  default     = false
}

variable "untagged_image_expiry_days" {
  description = "Number of days after which untagged images expire (FSBP ECR.3 lifecycle policy threshold). The policy itself is always enforced; only the threshold is tunable."
  type        = number
  default     = 14

  validation {
    condition     = var.untagged_image_expiry_days >= 1 && var.untagged_image_expiry_days <= 3650
    error_message = "untagged_image_expiry_days must be between 1 and 3650."
  }
}

variable "max_tagged_image_count" {
  description = "Maximum number of tagged images to retain (FSBP ECR.3 lifecycle policy threshold). The policy itself is always enforced; only the threshold is tunable."
  type        = number
  default     = 100

  validation {
    condition     = var.max_tagged_image_count >= 1 && var.max_tagged_image_count <= 1000
    error_message = "max_tagged_image_count must be between 1 and 1000."
  }
}
