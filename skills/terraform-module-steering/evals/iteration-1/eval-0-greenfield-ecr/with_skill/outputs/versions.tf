terraform {
  # Floor matches the wrapped upstream module terraform-aws-modules/ecr/aws v3.2.0
  # (.terraform/modules/ecr/versions.tf declares required_version >= 1.5.7).
  # Developed/tested on Terraform v1.15.6 (latest stable). Floor kept low so
  # consumers are not forced onto the latest toolchain.
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Floor matches the upstream module's declared aws provider floor (>= 6.28).
      version = ">= 6.28"
    }
  }
}
