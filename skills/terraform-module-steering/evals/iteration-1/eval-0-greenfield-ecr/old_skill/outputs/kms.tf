################################################################################
# Customer-managed KMS key for ECR encryption at rest (FSBP ECR.5)
#
# A module-managed CMK with annual rotation. The key and its usage are hardcoded
# into the repository (see main.tf) and are NOT exposed as consumer variables.
################################################################################

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "kms" {
  # The "EnableRootPermissions" statement (kms:* on resource "*") is the AWS-required
  # KMS key-policy root statement; without it the account can be locked out of the key.
  # It is scoped to THIS account's root principal only. The following checks flag the
  # wildcard action/resource on that mandatory statement and are false positives here.
  #checkov:skip=CKV_AWS_111:Root key-policy statement requires kms:* on "*" (AWS-recommended; scoped to account root principal).
  #checkov:skip=CKV_AWS_356:KMS key policy must target the key itself via "*"; scoped to the account-root principal.
  #checkov:skip=CKV_AWS_109:Root key-policy statement is the AWS-required admin grant, scoped to account root principal.

  # Account root retains full administrative control of the key.
  statement {
    sid       = "EnableRootPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Allow the ECR service to use the key for encrypt/decrypt of repository data,
  # scoped to this account via the kms:ViaService condition.
  statement {
    sid    = "AllowECRServiceUse"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["ecr.amazonaws.com"]
    }

    # Scope service use to this account. (kms:ViaService is region-specific
    # (ecr.<region>.amazonaws.com) and the consumer owns the provider region,
    # so we constrain by caller account rather than hardcoding a region.)
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "CMK for ECR repository ${var.name} encryption at rest (FSBP ECR.5)"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json

  tags = local.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/ecr/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}
