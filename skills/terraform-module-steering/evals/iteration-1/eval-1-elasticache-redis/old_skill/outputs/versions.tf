terraform {
  # Write-only arguments (secret_string_wo) require Terraform >= 1.11.
  # Ephemeral input variables require >= 1.10; we take the stricter floor.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}
