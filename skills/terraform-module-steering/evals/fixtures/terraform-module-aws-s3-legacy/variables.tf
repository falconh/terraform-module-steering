variable "bucket_name" {
  description = "Name of the S3 bucket."
  type        = string
}

variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "dev"
}

# GAP (weakenable control): encryption is exposed as a toggle, so a consumer can
# turn it off — and even when on it is only SSE-S3 (AES256), not a customer-managed
# CMK. A hardening pass should make encryption non-negotiable and CMK-backed.
variable "encryption_enabled" {
  description = "Whether to enable default server-side encryption."
  type        = bool
  default     = true
}

# GAP (weakenable control): public-access blocking is a single consumer-settable
# flag that defaults on but can be turned off. It should be hardcoded on.
variable "block_public_access" {
  description = "Whether to block all public access."
  type        = bool
  default     = true
}
