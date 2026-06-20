terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.93"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# The AUTH token is supplied as an ephemeral (write-only) variable so it never
# enters Terraform state. In real use, source it from a secrets backend /
# `TF_VAR_auth_token_wo` env var rather than a literal.
variable "auth_token_wo" {
  description = "Redis AUTH token (write-only/ephemeral)."
  type        = string
  ephemeral   = true
  sensitive   = true
}

module "redis" {
  source = "../../"

  name        = "example-redis"
  environment = "dev"

  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0aaa1111", "subnet-0bbb2222"]

  auth_token_wo = var.auth_token_wo

  allowed_cidr_blocks = ["10.0.0.0/16"]
}

output "primary_endpoint_address" {
  description = "Primary endpoint for the Redis replication group."
  value       = module.redis.primary_endpoint_address
}

output "auth_token_secret_arn" {
  description = "Secrets Manager ARN holding the write-only AUTH token."
  value       = module.redis.auth_token_secret_arn
}
