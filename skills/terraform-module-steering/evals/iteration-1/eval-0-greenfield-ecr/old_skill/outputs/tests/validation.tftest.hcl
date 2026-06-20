# Input-validation tests. These use `command = plan` and expect failures, so no
# provider interaction is needed; a mock_provider keeps them credential-free.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# ---- environment must be one of the allowed values ----
run "rejects_invalid_environment" {
  command = plan

  variables {
    name        = "bad-env-app"
    environment = "production"
  }

  expect_failures = [var.environment]
}

# ---- repository name must be a valid ECR name ----
run "rejects_invalid_name" {
  command = plan

  variables {
    name        = "Invalid Name With Spaces"
    environment = "prod"
  }

  expect_failures = [var.name]
}

# ---- lifecycle thresholds are bounded ----
run "rejects_out_of_range_untagged_expiry" {
  command = plan

  variables {
    name                       = "range-app"
    environment                = "prod"
    untagged_image_expiry_days = 0
  }

  expect_failures = [var.untagged_image_expiry_days]
}

run "rejects_out_of_range_image_count" {
  command = plan

  variables {
    name                   = "range-app"
    environment            = "prod"
    max_tagged_image_count = 0
  }

  expect_failures = [var.max_tagged_image_count]
}

# ---- a fully valid configuration plans cleanly ----
run "valid_config_plans" {
  command = plan

  variables {
    name        = "valid-app"
    environment = "test"
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "Valid config must enable key rotation."
  }
}
