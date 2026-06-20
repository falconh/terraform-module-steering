################################################################################
# Write-only AUTH token sink (Secrets Manager)
#
# The Redis AUTH token arrives via the ephemeral variable `var.auth_token_wo`,
# which is NEVER written to Terraform state or plan. The ONLY place it is
# persisted is this Secrets Manager secret, using the provider's write-only
# `secret_string_wo` argument (write_only = true) — so the token never enters
# Terraform state here either. Applications read the token from this secret.
#
# Rotation is version-driven: bump `var.auth_token_wo_version` together with a
# new `var.auth_token_wo` to publish a new secret version (write-only values
# cannot be diffed by Terraform, so an explicit version is how change is signalled).
################################################################################

resource "aws_secretsmanager_secret" "auth_token" {
  # checkov:skip=CKV2_AWS_57:Redis AUTH rotation must be coordinated with a cluster-side modify-replication-group call; a generic Secrets Manager rotation lambda cannot do that. Rotation here is operator-driven and version-controlled via auth_token_wo_version.
  name        = "elasticache/redis/${var.name}/auth-token"
  description = "Redis AUTH token for ElastiCache replication group ${var.name} (write-only; never in TF state)."
  kms_key_id  = aws_kms_key.this.arn

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "auth_token" {
  secret_id = aws_secretsmanager_secret.auth_token.id

  # Write-only sink: the value is consumed at apply and never stored in state.
  secret_string_wo         = var.auth_token_wo
  secret_string_wo_version = var.auth_token_wo_version
}
