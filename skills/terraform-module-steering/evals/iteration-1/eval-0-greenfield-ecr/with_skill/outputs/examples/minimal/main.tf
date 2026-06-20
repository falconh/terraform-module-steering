terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Smallest possible consumer: only the two required inputs.
module "ecr" {
  source = "../../"

  name        = "example-app"
  environment = "prod"
}

output "repository_url" {
  description = "URL to push/pull images."
  value       = module.ecr.repository_url
}

output "repository_arn" {
  description = "ARN of the repository."
  value       = module.ecr.repository_arn
}

output "kms_key_arn" {
  description = "ARN of the CMK encrypting the repository."
  value       = module.ecr.kms_key_arn
}
