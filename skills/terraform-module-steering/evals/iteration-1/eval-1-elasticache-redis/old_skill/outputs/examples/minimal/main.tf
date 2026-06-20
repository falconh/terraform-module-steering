terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# The AUTH token is an ephemeral (write-only) variable: it is never written to
# state or plan. In real usage, source it from an ephemeral resource (e.g.
# `ephemeral "aws_secretsmanager_secret_version"`) or a CI secret — not a tfvars
# file committed to disk.
variable "redis_auth_token" {
  type      = string
  ephemeral = true
  sensitive = true
}

module "redis" {
  source = "../../"

  name        = "example-redis"
  environment = "dev"

  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0aaa1111bbbb2222c", "subnet-0ddd3333eeee4444f"]

  auth_token = var.redis_auth_token
}

output "primary_endpoint_address" {
  value = module.redis.primary_endpoint_address
}

output "auth_token_secret_arn" {
  value = module.redis.auth_token_secret_arn
}
