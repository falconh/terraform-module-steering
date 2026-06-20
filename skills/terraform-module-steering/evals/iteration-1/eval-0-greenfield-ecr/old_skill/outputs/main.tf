################################################################################
# terraform-module-aws-ecr
#
# Secure-by-default private ECR repository. Wraps terraform-aws-modules/ecr/aws
# pinned to 3.2.0. Every FSBP ECR control is passed as a HARDCODED LITERAL below
# and is NOT exposed as a consumer variable, so it cannot be weakened.
################################################################################

locals {
  # Mandatory tags are merged OVER consumer tags so they cannot be dropped.
  tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "terraform-module-aws-ecr"
    },
  )

  # FSBP ECR.3 — a lifecycle policy is ALWAYS attached. Only the thresholds are
  # tunable (untagged_image_expiry_days / max_tagged_image_count); the presence
  # of the policy is hardcoded via create_lifecycle_policy = true below.
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent ${var.max_tagged_image_count} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.max_tagged_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "3.2.0"

  repository_type = "private"
  repository_name = var.name

  # ---- FSBP ECR.2: immutable tags (hardcoded literal) ----
  repository_image_tag_mutability = "IMMUTABLE"

  # ---- FSBP ECR.1: scan on push (hardcoded literal) ----
  repository_image_scan_on_push = true

  # ---- FSBP ECR.5: encryption at rest with a customer-managed CMK ----
  repository_encryption_type = "KMS"
  repository_kms_key         = aws_kms_key.this.arn

  # ---- FSBP ECR.3: a lifecycle policy is always attached ----
  create_lifecycle_policy     = true
  repository_lifecycle_policy = local.lifecycle_policy

  # Consumer-tunable, safe defaults (not security controls).
  repository_force_delete = var.force_delete

  tags = local.tags
}
