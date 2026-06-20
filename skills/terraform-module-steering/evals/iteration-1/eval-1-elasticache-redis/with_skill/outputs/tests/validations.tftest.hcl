################################################################################
# Dedicated tests for: the Multi-AZ cost-warning check, and input validations.
# These use the same mock_provider; validation runs fail at the variable level
# before any provider call, so mocking is only needed for the check run.
################################################################################

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
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
}

# The cost warning MUST fire because Multi-AZ is hardcoded ON. We prove it by
# expecting exactly that check to fail under the test harness. If the warning
# stopped firing (e.g. someone made Multi-AZ overridable and off), this run
# would error with "missing expected failure" and catch the regression.
run "cost_warning_fires_when_multi_az_on" {
  command         = plan
  expect_failures = [check.multi_az_cost_warning]
}

# auth_token_wo shorter than 16 chars must be rejected by variable validation.
# (The cost-warning check also fires during the same plan — `expect_failures`
# does not halt evaluation — so both expected failures are declared.)
run "auth_token_too_short_rejected" {
  command = plan

  variables {
    auth_token_wo = "short"
  }

  expect_failures = [
    var.auth_token_wo,
    check.multi_az_cost_warning,
  ]
}

# Fewer than two subnets must be rejected (Multi-AZ needs >= 2 AZs).
run "too_few_subnets_rejected" {
  command = plan

  variables {
    subnet_ids = ["subnet-00000000000000001"]
  }

  expect_failures = [
    var.subnet_ids,
    check.multi_az_cost_warning,
  ]
}

# An invalid environment must be rejected.
run "invalid_environment_rejected" {
  command = plan

  variables {
    environment = "production"
  }

  expect_failures = [
    var.environment,
    check.multi_az_cost_warning,
  ]
}
