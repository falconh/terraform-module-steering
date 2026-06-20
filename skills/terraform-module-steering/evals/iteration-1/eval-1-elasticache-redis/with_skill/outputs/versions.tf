terraform {
  # >= 1.11 is required for `ephemeral`/write-only variables (the AUTH-token design)
  # and write-only resource arguments (Secrets Manager `secret_string_wo`).
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.93"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}
