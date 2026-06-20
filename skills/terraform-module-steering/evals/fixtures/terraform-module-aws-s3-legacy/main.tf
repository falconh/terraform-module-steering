# Intentionally-imperfect "legacy" S3 module used as the brownfield eval fixture.
# It is valid Terraform and reaches a green pipeline, but deliberately leaves
# CIS/FSBP gaps for the steering skill's brownfield (Path B) flow to find and close
# without breaking the existing interface.

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Weakenable + weak: optional, and AES256 rather than a customer-managed CMK.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count  = var.encryption_enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Weakenable: driven by a consumer flag instead of being hardcoded on.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

# GAPS deliberately left for the hardening pass to close:
#   - no bucket policy denying non-TLS access (aws:SecureTransport=false)  [FSBP S3.5]
#   - no server access logging                                            [CIS / FSBP S3.9]
#   - no lifecycle configuration
#   - encryption is optional + SSE-S3, not an enforced CMK                [FSBP S3.x / ECR.5-style]
