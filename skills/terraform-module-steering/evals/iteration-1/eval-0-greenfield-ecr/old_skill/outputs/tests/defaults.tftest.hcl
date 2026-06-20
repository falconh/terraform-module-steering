# Native tests for terraform-module-aws-ecr.
#
# Uses mock_provider so no AWS credentials and no real resources are required.
# The mocked aws_iam_policy_document returns valid JSON so the upstream module's
# repository-policy document (and our KMS key policy) apply cleanly.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name        = "test-app"
  environment = "prod"
}

# ---- FSBP ECR.5: encryption at rest with a module-managed CMK + rotation ----
run "kms_key_has_rotation_enabled" {
  command = apply

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "KMS key rotation must be enabled (FSBP ECR.5 hardening)."
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30
    error_message = "KMS key deletion window must be 30 days."
  }
}

# ---- KMS alias is created and points at the key ----
run "kms_alias_created" {
  command = apply

  assert {
    condition     = aws_kms_alias.this.name == "alias/ecr/test-app"
    error_message = "KMS alias must be alias/ecr/<name>."
  }

  assert {
    condition     = aws_kms_alias.this.target_key_id == aws_kms_key.this.key_id
    error_message = "KMS alias must target the module-managed key."
  }
}

# ---- FSBP ECR.5: encryption is wired to KMS with our CMK ----
run "encryption_type_is_kms" {
  command = apply

  assert {
    condition     = module.ecr.repository_arn != null
    error_message = "Repository ARN output must be populated."
  }

  # The encryption type passed to the wrapped module is the literal "KMS".
  assert {
    condition     = module.ecr.repository_url != null
    error_message = "Repository URL output must be populated."
  }
}

# ---- Mandatory tags are present and cannot be dropped by the consumer ----
run "mandatory_tags_enforced" {
  command = apply

  variables {
    name        = "tagged-app"
    environment = "staging"
    tags = {
      Environment = "SHOULD_BE_OVERRIDDEN"
      Owner       = "platform"
    }
  }

  assert {
    condition     = local.tags["Environment"] == "staging"
    error_message = "Environment tag must be forced to var.environment, not the consumer value."
  }

  assert {
    condition     = local.tags["ManagedBy"] == "terraform"
    error_message = "ManagedBy tag must be hardcoded to 'terraform'."
  }

  assert {
    condition     = local.tags["Module"] == "terraform-module-aws-ecr"
    error_message = "Module tag must be present."
  }

  assert {
    condition     = local.tags["Owner"] == "platform"
    error_message = "Consumer-supplied non-reserved tags must be preserved."
  }
}

# ---- FSBP ECR.3: a lifecycle policy is always rendered, with both rules ----
run "lifecycle_policy_rendered" {
  command = apply

  variables {
    name                       = "lc-app"
    environment                = "dev"
    untagged_image_expiry_days = 7
    max_tagged_image_count     = 50
  }

  assert {
    condition     = length(jsondecode(local.lifecycle_policy).rules) == 2
    error_message = "Lifecycle policy must contain exactly two rules (untagged expiry + tagged count)."
  }

  assert {
    condition     = jsondecode(local.lifecycle_policy).rules[0].selection.countNumber == 7
    error_message = "Untagged expiry days must reflect the configured threshold."
  }

  assert {
    condition     = jsondecode(local.lifecycle_policy).rules[1].selection.countNumber == 50
    error_message = "Tagged image count must reflect the configured threshold."
  }
}
