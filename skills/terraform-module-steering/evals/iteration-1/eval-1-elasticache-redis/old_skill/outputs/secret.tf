# --- Write-only AUTH token storage -------------------------------------------
# The Redis AUTH token is a WRITE-ONLY value. It reaches this module only through
# the `auth_token` variable, which is declared `ephemeral = true` (never written
# to Terraform state or plan). We persist it ONLY into AWS Secrets Manager using
# the provider's write-only argument `secret_string_wo`, which Terraform discards
# without storing in state. The paired `secret_string_wo_version` (a normal,
# non-secret integer) is the only token-related value that lands in state and is
# what triggers re-application/rotation.
#
# The token is deliberately NOT passed to the upstream module's `auth_token`
# input: that argument is not write-only and would persist the secret to state,
# and Terraform rejects routing an ephemeral value into it. Applications and the
# operator read the live token from this secret at runtime and apply/rotate it on
# the cluster out-of-band (see README).

resource "aws_secretsmanager_secret" "auth_token" {
  #checkov:skip=CKV2_AWS_57:Automatic Lambda-based rotation is out of scope. The Redis AUTH token is rotated by bumping auth_token_rotation (new write-only secret version) paired with ElastiCache auth_token_update_strategy; adding a rotation Lambda is a separate operational concern recorded in docs/DESIGN.md.
  name        = "${var.name}-elasticache-redis-auth"
  description = "Redis AUTH token for ${var.name} (write-only; never stored in Terraform state)."
  kms_key_id  = aws_kms_key.this.arn

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "auth_token" {
  secret_id = aws_secretsmanager_secret.auth_token.id

  # Write-only: value is consumed by the provider and discarded, never persisted
  # to state. Sourced from the ephemeral `auth_token` variable.
  secret_string_wo         = var.auth_token
  secret_string_wo_version = var.auth_token_rotation
}
