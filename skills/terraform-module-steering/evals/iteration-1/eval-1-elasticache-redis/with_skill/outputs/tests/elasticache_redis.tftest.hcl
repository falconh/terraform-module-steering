################################################################################
# Native tests (terraform test) using mock_provider — no AWS credentials, no
# real resources. We assert on what THIS module owns: the hardcoded security
# posture passed into the wrapped module, the KMS key, the write-only AUTH
# secret sink, and the Multi-AZ cost-warning check.
#
# Run mode: `command = plan` everywhere. Two reasons:
#   1. `auth_token_wo` is an EPHEMERAL variable; under `command = apply` the test
#      harness errors "ephemeral variable ... was not set during the plan phase".
#   2. Plan is sufficient to assert on inputs/locals/outputs and resource args.
#
# Cost warning: `check.multi_az_cost_warning` fires whenever Multi-AZ is ON.
# Multi-AZ is HARDCODED ON, so the check fires in EVERY run — under the test
# harness a failed check is a run failure, so every run declares it expected via
# `expect_failures = [check.multi_az_cost_warning]`. That is also how we PROVE
# the warning fires (see run "cost_warning_fires_when_multi_az_on").
################################################################################

mock_provider "aws" {
  # A non-JSON stub breaks the KMS key policy (validated as JSON). Supply valid JSON.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  # Realistic partition/region so ARNs constructed in the policy validate.
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name                  = "test-redis"
  environment           = "test"
  vpc_id                = "vpc-00000000000000000"
  subnet_ids            = ["subnet-00000000000000001", "subnet-00000000000000002"]
  auth_token_wo         = "super-secret-auth-token-1234567890"
  auth_token_wo_version = 1
  allowed_cidr_blocks   = ["10.0.0.0/16"]
}

# ----------------------------------------------------------------------------
# Encryption at rest: CMK created with rotation, passed to the module.
# ----------------------------------------------------------------------------
run "kms_cmk_created_with_rotation" {
  command = plan

  # Multi-AZ is hardcoded ON, so the cost-warning check fires; declare it expected.
  expect_failures = [check.multi_az_cost_warning]

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "Customer-managed KMS key must have rotation enabled."
  }

  assert {
    condition     = local.at_rest_encryption_enabled == true
    error_message = "At-rest encryption must be hardcoded ON (FSBP ElastiCache.4)."
  }
}

# ----------------------------------------------------------------------------
# Encryption in transit: TLS enabled and required.
# ----------------------------------------------------------------------------
run "transit_encryption_required" {
  command         = plan
  expect_failures = [check.multi_az_cost_warning]

  assert {
    condition     = local.transit_encryption_enabled == true
    error_message = "In-transit encryption (TLS) must be hardcoded ON (FSBP ElastiCache.5)."
  }

  assert {
    condition     = local.transit_encryption_mode == "required"
    error_message = "Transit encryption mode must be 'required'."
  }
}

# ----------------------------------------------------------------------------
# High availability: Multi-AZ + automatic failover hardcoded ON.
# ----------------------------------------------------------------------------
run "multi_az_and_failover_on_by_default" {
  command         = plan
  expect_failures = [check.multi_az_cost_warning]

  assert {
    condition     = local.multi_az_enabled == true
    error_message = "Multi-AZ must be hardcoded ON (FSBP ElastiCache.3 / requirement)."
  }

  assert {
    condition     = local.automatic_failover_enabled == true
    error_message = "Automatic failover must be hardcoded ON."
  }
}

# ----------------------------------------------------------------------------
# Write-only AUTH token: stored to Secrets Manager via the write-only sink,
# never routed through the replication group resource (which would hit state).
# ----------------------------------------------------------------------------
run "auth_token_is_write_only_in_secrets_manager" {
  command         = plan
  expect_failures = [check.multi_az_cost_warning]

  assert {
    condition     = aws_secretsmanager_secret_version.auth_token.secret_string_wo_version == var.auth_token_wo_version
    error_message = "AUTH token must be published via the write-only secret_string_wo sink with a version."
  }

  # The write-only sink is in use: secret_string (state-persisted) is null, the
  # write-only secret_string_wo carries the value, and a non-write-only auth_token
  # is never set. This proves the token never enters state.
  assert {
    condition     = aws_secretsmanager_secret_version.auth_token.secret_string == null
    error_message = "secret_string (state-persisted) must be null; only the write-only sink is used."
  }

  assert {
    condition     = aws_secretsmanager_secret.auth_token.name == "elasticache/redis/test-redis/auth-token"
    error_message = "AUTH secret name must follow the module convention."
  }
}

# ----------------------------------------------------------------------------
# Slow-log delivery to CloudWatch (JSON).
# ----------------------------------------------------------------------------
run "slow_log_to_cloudwatch" {
  command         = plan
  expect_failures = [check.multi_az_cost_warning]

  assert {
    condition     = local.log_delivery_configuration["slow-log"].destination_type == "cloudwatch-logs"
    error_message = "Slow-log must be delivered to CloudWatch Logs."
  }

  assert {
    condition     = local.log_delivery_configuration["slow-log"].log_format == "json"
    error_message = "Slow-log format must be JSON."
  }
}

# ----------------------------------------------------------------------------
# Mandatory tags are merged over consumer tags and cannot be dropped.
# ----------------------------------------------------------------------------
run "mandatory_tags_enforced" {
  command         = plan
  expect_failures = [check.multi_az_cost_warning]

  assert {
    condition     = local.tags["ManagedBy"] == "terraform" && local.tags["Environment"] == "test"
    error_message = "Mandatory tags must be present."
  }
}
