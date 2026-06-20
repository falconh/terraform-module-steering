################################################################################
# Customer-managed KMS key (FSBP ElastiCache.4 — encryption at rest with a CMK)
# Also encrypts the CloudWatch slow-log group and the AUTH-token secret.
################################################################################

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "kms" {
  # checkov:skip=CKV_AWS_111:KMS *key policies* scope to the key itself; the policy resource is always "*" (the key) — constraining it is not applicable to key policies.
  # checkov:skip=CKV_AWS_356:Same — a KMS key policy's resource is implicitly the key; "*" here means "this key", which is the documented AWS pattern.
  # checkov:skip=CKV_AWS_109:Service principals (elasticache/logs/secretsmanager) need standard data-key actions on THIS key; no permissions-management actions are granted.
  # Root account retains full administrative control of the key.
  statement {
    sid       = "EnableRootAccount"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Allow ElastiCache to use the key for at-rest encryption of the replication group.
  statement {
    sid    = "AllowElastiCache"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["elasticache.amazonaws.com"]
    }
  }

  # Allow CloudWatch Logs (slow-log group) to use the key.
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/elasticache/*"]
    }
  }

  # Allow Secrets Manager to use the key for the AUTH-token secret.
  statement {
    sid    = "AllowSecretsManager"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["secretsmanager.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "CMK for ElastiCache Redis ${var.name} (at-rest, slow-log, AUTH secret)"
  deletion_window_in_days = 30
  enable_key_rotation     = true # key hygiene (CIS KMS rotation intent)
  policy                  = data.aws_iam_policy_document.kms.json

  tags = local.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/elasticache-redis-${var.name}"
  target_key_id = aws_kms_key.this.key_id
}
