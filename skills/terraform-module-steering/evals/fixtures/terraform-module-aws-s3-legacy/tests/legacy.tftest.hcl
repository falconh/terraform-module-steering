# Existing tests that ship with the legacy module. A correct brownfield change must
# keep these green (do-no-harm to existing consumers) while adding new tests for the
# feature and each closed gap.

mock_provider "aws" {}

run "creates_named_bucket" {
  command = plan

  variables {
    bucket_name = "legacy-fixture-bucket"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "legacy-fixture-bucket"
    error_message = "bucket name was not wired through to aws_s3_bucket.this"
  }
}

run "versioning_enabled" {
  command = plan

  variables {
    bucket_name = "legacy-fixture-bucket"
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "versioning should be enabled"
  }
}
