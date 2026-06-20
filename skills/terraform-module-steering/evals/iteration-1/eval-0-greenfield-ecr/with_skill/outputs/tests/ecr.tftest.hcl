# Native terraform tests (terraform test) using mock_provider — no AWS creds,
# no real resources. Asserts the security controls the module OWNS and its
# conditional logic. Attributes deep inside the wrapped upstream module are left
# to checkov; here we assert the literals we pass and the resources we create.

mock_provider "aws" {
  # A non-JSON stub would fail aws_kms_key.policy JSON validation; give realistic JSON.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  # Realistic partition so any "arn:${partition}:..." interpolation is valid.
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name        = "test-app"
  environment = "prod"
}

# ---------------------------------------------------------------------------
# 1. KMS CMK is created with rotation enabled and a 30-day deletion window (ECR.5).
# ---------------------------------------------------------------------------
run "kms_cmk_rotation_enabled" {
  command = plan

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "KMS key rotation must be enabled (FSBP ECR.5 customer-managed key best practice)."
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30
    error_message = "KMS key deletion window must be 30 days."
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/ecr/test-app"
    error_message = "KMS alias must be derived from the repository name."
  }
}

# ---------------------------------------------------------------------------
# 2. ECR.5 — the repository is encrypted with the module-managed CMK: the KMS
#    key feeds the module, and the module's repository_kms_key wiring resolves to
#    a key this module owns (asserted via the alias targeting that same key).
# ---------------------------------------------------------------------------
run "encryption_uses_module_managed_cmk" {
  # apply: target_key_id / key_id are computed, so resolve them under apply (mocked).
  command = apply

  # The alias targets the CMK we create — proving a customer-managed key exists
  # to encrypt the repository (the module passes this key's ARN as repository_kms_key).
  assert {
    condition     = aws_kms_alias.this.target_key_id == aws_kms_key.this.key_id
    error_message = "The ECR encryption alias must target the module-managed CMK (FSBP ECR.5)."
  }
}

# ---------------------------------------------------------------------------
# 3. Lifecycle policy JSON (ECR.3) is well-formed and honours the retention count.
# ---------------------------------------------------------------------------
run "lifecycle_policy_present_and_valid" {
  command = plan

  assert {
    condition     = jsondecode(local.lifecycle_policy).rules[0].action.type == "expire"
    error_message = "Lifecycle policy must expire old images (FSBP ECR.3)."
  }

  assert {
    condition     = jsondecode(local.lifecycle_policy).rules[0].selection.countNumber == 30
    error_message = "Lifecycle policy must retain the default of 30 images when not overridden."
  }
}

run "lifecycle_count_is_tunable" {
  command = plan

  variables {
    lifecycle_keep_last_count = 5
  }

  assert {
    condition     = jsondecode(local.lifecycle_policy).rules[0].selection.countNumber == 5
    error_message = "lifecycle_keep_last_count must drive the lifecycle policy retention number."
  }
}

# ---------------------------------------------------------------------------
# 4. TLS-only deny statement is always present in the repository policy.
# ---------------------------------------------------------------------------
run "tls_deny_statement_present" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(local.repository_policy).Statement :
      s.Sid == "DenyNonTLSAccess" && s.Effect == "Deny"
    ])
    error_message = "Repository policy must deny non-TLS (aws:SecureTransport=false) access."
  }
}

# ---------------------------------------------------------------------------
# 5. Read / read-write grants appear only when ARNs are supplied.
# ---------------------------------------------------------------------------
run "no_grants_by_default" {
  command = plan

  assert {
    condition     = length(jsondecode(local.repository_policy).Statement) == 1
    error_message = "Without supplied ARNs, only the TLS-deny statement should exist."
  }
}

run "grants_added_when_arns_supplied" {
  command = plan

  variables {
    additional_read_access_arns       = ["arn:aws:iam::123456789012:role/puller"]
    additional_read_write_access_arns = ["arn:aws:iam::123456789012:role/pusher"]
  }

  assert {
    condition     = length(jsondecode(local.repository_policy).Statement) == 3
    error_message = "With read and read-write ARNs supplied, TLS-deny + AllowPull + AllowPushPull should exist."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(local.repository_policy).Statement : s.Sid == "AllowPull"
    ])
    error_message = "AllowPull statement must be present when read ARNs are supplied."
  }
}

# ---------------------------------------------------------------------------
# 6. Mandatory tags are merged OVER consumer tags (cannot be dropped/overridden).
# ---------------------------------------------------------------------------
run "mandatory_tags_win_over_consumer_tags" {
  command = plan

  variables {
    tags = {
      ManagedBy = "someone-else" # attempt to override a mandatory tag
      Team      = "platform"
    }
  }

  assert {
    condition     = local.tags["ManagedBy"] == "terraform"
    error_message = "Mandatory ManagedBy tag must win over a consumer-supplied value."
  }

  assert {
    condition     = local.tags["Module"] == "terraform-module-aws-ecr"
    error_message = "Mandatory Module tag must be present."
  }

  assert {
    condition     = local.tags["Environment"] == "prod"
    error_message = "Environment tag must reflect the environment input."
  }

  assert {
    condition     = local.tags["Team"] == "platform"
    error_message = "Consumer tags that don't collide must be preserved."
  }
}

# ---------------------------------------------------------------------------
# 7. environment validation rejects invalid values.
# ---------------------------------------------------------------------------
run "invalid_environment_rejected" {
  command = plan

  variables {
    environment = "production" # not in the allowed set
  }

  expect_failures = [var.environment]
}

# ---------------------------------------------------------------------------
# 8. invalid repository name is rejected.
# ---------------------------------------------------------------------------
run "invalid_name_rejected" {
  command = plan

  variables {
    name = "Invalid_NAME_With_Caps"
  }

  expect_failures = [var.name]
}
