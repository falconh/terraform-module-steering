data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Customer-managed KMS key used for:
#   - ElastiCache encryption at rest (FSBP ElastiCache.4)
#   - the Secrets Manager secret that holds the write-only AUTH token
#   - the slow-log CloudWatch log group
# Key rotation is hardcoded on (CIS-aligned KMS posture). Not overridable.
resource "aws_kms_key" "this" {
  description             = "CMK for ${var.name} ElastiCache Redis (at-rest, auth-secret, logs)"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json

  tags = local.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-elasticache-redis"
  target_key_id = aws_kms_key.this.key_id
}

# Key policy: account root admin + allow the CloudWatch Logs service in this
# region to use the key for the slow-log group, and allow ElastiCache/Secrets
# Manager (via the consumer's principals) through the default IAM path.
data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Key policy intentionally grants kms:* to the account root so IAM policies govern access (AWS-recommended default key policy).
  #checkov:skip=CKV_AWS_111:Root account administration of the CMK is the AWS-recommended baseline; scoped service grants are added below.
  #checkov:skip=CKV_AWS_356:Resource "*" within a single-key policy refers to the key itself; scoping to the key ARN is not possible inside its own policy document.
  statement {
    sid       = "EnableRootAccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

data "aws_region" "current" {}
