variable "name" {
  description = "Name of the ECR private repository to create."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._/-][a-z0-9]+)*$", var.name)) && length(var.name) <= 256
    error_message = "name must be a valid ECR repository name: lowercase alphanumerics separated by ., _, -, or /, and at most 256 characters."
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
  description = "Additional tags to apply. Mandatory tags (ManagedBy, Module, Environment) are merged over these and cannot be dropped."
  type        = map(string)
  default     = {}
}

variable "force_delete" {
  description = "If true, the repository (and any images it contains) can be deleted by Terraform. Defaults to false to protect images."
  type        = bool
  default     = false
}

variable "lifecycle_keep_last_count" {
  description = "Number of most-recent images to retain under the mandatory lifecycle policy. A lifecycle policy is always present (FSBP ECR.3) regardless of this value."
  type        = number
  default     = 30

  validation {
    condition     = var.lifecycle_keep_last_count >= 1 && var.lifecycle_keep_last_count <= 10000
    error_message = "lifecycle_keep_last_count must be between 1 and 10000."
  }
}

variable "additional_read_access_arns" {
  description = "IAM principal ARNs to grant pull (read) access to the repository via the repository policy."
  type        = list(string)
  default     = []
}

variable "additional_read_write_access_arns" {
  description = "IAM principal ARNs to grant push/pull (read-write) access to the repository via the repository policy."
  type        = list(string)
  default     = []
}
