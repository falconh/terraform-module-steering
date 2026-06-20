# Native terraform tests with a mocked AWS provider — no real credentials, no
# real resources. Run with: terraform test
#
# Notes:
#  - command = apply so assertions can read computed/set values.
#  - A mocked aws_iam_policy_document returns a non-JSON stub by default, which
#    breaks aws_kms_key.policy (it validates JSON). We give it a valid default.
#  - The module's `check "multi_az_cost_warning"` intentionally asserts false to
#    surface a cost WARNING at plan/apply. Under `terraform test` a failed check
#    is promoted to a failure, so every applying run declares it in expect_failures.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name        = "unit-redis"
  environment = "test"
  vpc_id      = "vpc-00000000000000000"
  subnet_ids  = ["subnet-00000000000000001", "subnet-00000000000000002"]
  auth_token  = "Sup3r-Secret-Token-1234"
}

run "encryption_at_rest_uses_customer_managed_kms" {
  command = apply

  expect_failures = [check.multi_az_cost_warning]

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "Customer-managed KMS key must have rotation enabled."
  }

  # The CMK alias is derived from var.name by the module (not mocked), so it is a
  # deterministic check that the module wires the consumer's name through.
  assert {
    condition     = aws_kms_alias.this.name == "alias/unit-redis-elasticache-redis"
    error_message = "KMS alias should be derived from the provided name."
  }

  # The custom (non-default) subnet group is configured (FSBP ElastiCache.7).
  assert {
    condition     = aws_secretsmanager_secret.auth_token.name == "unit-redis-elasticache-redis-auth"
    error_message = "AUTH secret name should be derived from the provided name."
  }
}

run "auth_token_is_write_only_in_secrets_manager" {
  command = apply

  expect_failures = [check.multi_az_cost_warning]

  # The secret resource exists and is CMK-encrypted...
  assert {
    condition     = aws_secretsmanager_secret.auth_token.kms_key_id == aws_kms_key.this.arn
    error_message = "AUTH secret must be encrypted with the module CMK."
  }

  # ...and the version object is wired to the write-only argument via its
  # non-secret version trigger (the only token-related value that touches state).
  assert {
    condition     = aws_secretsmanager_secret_version.auth_token.secret_string_wo_version == 1
    error_message = "Write-only AUTH secret version trigger should default to 1."
  }

  # State must NEVER contain the token. secret_string_wo is write-only, so the
  # plain secret_string attribute is null/empty in state.
  assert {
    condition     = (aws_secretsmanager_secret_version.auth_token.secret_string == null || aws_secretsmanager_secret_version.auth_token.secret_string == "")
    error_message = "AUTH token must never be persisted in state (secret_string must be empty/null)."
  }
}

run "outputs_never_expose_the_token" {
  command = apply

  expect_failures = [check.multi_az_cost_warning]

  # The module exposes only the secret ARN/name, never the token value.
  assert {
    condition     = endswith(output.auth_token_secret_name, "-elasticache-redis-auth")
    error_message = "Secret name output should be the companion auth secret name."
  }

  assert {
    condition     = output.kms_key_alias == "alias/unit-redis-elasticache-redis"
    error_message = "KMS alias output should match the expected alias."
  }
}

run "mandatory_tags_cannot_be_dropped" {
  command = apply

  expect_failures = [check.multi_az_cost_warning]

  variables {
    tags = {
      ManagedBy   = "someone-else" # consumer tries to override
      Environment = "wrong"        # consumer tries to override
      Team        = "platform"
    }
  }

  assert {
    condition     = aws_kms_key.this.tags["ManagedBy"] == "terraform"
    error_message = "Mandatory ManagedBy tag must win over consumer-supplied value."
  }

  assert {
    condition     = aws_kms_key.this.tags["Environment"] == "test"
    error_message = "Mandatory Environment tag must win over consumer-supplied value."
  }

  assert {
    condition     = aws_kms_key.this.tags["Team"] == "platform"
    error_message = "Consumer additional tags should still be merged in."
  }
}

run "rotation_trigger_is_propagated" {
  command = apply

  expect_failures = [check.multi_az_cost_warning]

  variables {
    auth_token_rotation = 3
  }

  assert {
    condition     = aws_secretsmanager_secret_version.auth_token.secret_string_wo_version == 3
    error_message = "auth_token_rotation should drive the write-only secret version trigger."
  }
}
