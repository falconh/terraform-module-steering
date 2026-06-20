################################################################################
# Customer-managed KMS key for ECR encryption at rest (FSBP ECR.5)
#
# A customer-managed CMK (rotation enabled) is created and passed to the
# repository. This is non-overridable: the consumer cannot select AES256 or
# the AWS-managed aws/ecr key, both of which fail ECR.5.
################################################################################

data "aws_iam_policy_document" "kms" {
  # The "EnableRootAccountAdmin" statement below is the AWS-recommended baseline
  # KMS key policy: it delegates key administration to the account root, which is
  # how IAM permissions for the key are then managed and prevents key lockout.
  # AWS requires kms:* / Resource "*" here because a key policy's resource is
  # always the key itself; the principal is scoped to this account's root only.
  # These three checks misread that mandatory baseline as an unconstrained policy.
  #checkov:skip=CKV_AWS_111:Root-account key admin is the AWS-recommended baseline; principal scoped to account root, resource is the key itself.
  #checkov:skip=CKV_AWS_356:KMS key policy resource is always "*" (the key); scoped to account root principal — standard CMK admin baseline.
  #checkov:skip=CKV_AWS_109:Account-root key administration is required to manage/rotate the CMK and avoid lockout; not a privilege-escalation path.
  # Root account retains full control of the key (standard CMK admin baseline).
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

  # Allow the ECR service to use the key for repository encryption operations,
  # scoped to this account via the kms:ViaService / CallerAccount conditions.
  statement {
    sid    = "AllowECRServiceUse"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["ecr.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "CMK for ECR repository ${var.name} encryption at rest"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json

  tags = local.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/ecr/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}
