data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # ---- Mandatory tags (merged OVER consumer tags so they cannot be dropped) ----
  mandatory_tags = {
    ManagedBy   = "terraform"
    Module      = "terraform-module-aws-ecr"
    Environment = var.environment
  }
  tags = merge(var.tags, local.mandatory_tags)

  # ---- FSBP ECR.3: lifecycle policy (always present) ----
  # Keep the most-recent N images; expire older ones automatically.
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the most recent ${var.lifecycle_keep_last_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.lifecycle_keep_last_count
        }
        action = { type = "expire" }
      }
    ]
  })

  # ---- TLS-only repository policy (defense-in-depth) ----
  # Deny every ECR API action against this repository over a non-TLS connection,
  # plus optional read / read-write grants for supplied principal ARNs.
  read_access_arns       = var.additional_read_access_arns
  read_write_access_arns = var.additional_read_write_access_arns

  repository_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid       = "DenyNonTLSAccess"
          Effect    = "Deny"
          Principal = "*"
          Action    = "ecr:*"
          Condition = {
            Bool = { "aws:SecureTransport" = "false" }
          }
        }
      ],
      length(local.read_access_arns) > 0 ? [
        {
          Sid       = "AllowPull"
          Effect    = "Allow"
          Principal = { AWS = local.read_access_arns }
          Action = [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability",
          ]
        }
      ] : [],
      length(local.read_write_access_arns) > 0 ? [
        {
          Sid       = "AllowPushPull"
          Effect    = "Allow"
          Principal = { AWS = local.read_write_access_arns }
          Action = [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability",
            "ecr:PutImage",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload",
          ]
        }
      ] : [],
    )
  })
}
