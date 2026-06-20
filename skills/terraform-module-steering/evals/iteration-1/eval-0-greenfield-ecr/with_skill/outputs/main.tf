################################################################################
# Secure-by-default Amazon ECR private repository.
#
# Wraps terraform-aws-modules/ecr/aws (pinned v3.2.0). Every security-relevant
# input below is a HARDCODED LITERAL — none is exposed as a consumer variable —
# so the CIS/FSBP controls cannot be weakened by a consumer.
################################################################################

module "ecr" {
  #checkov:skip=CKV_TF_1:Registry modules are pinned by exact version (3.2.0), the correct practice — CKV_TF_2 (version tag) passes. A commit hash does not apply to registry sources.
  source  = "terraform-aws-modules/ecr/aws"
  version = "3.2.0"

  # --- Repository identity (consumer-controlled) ---
  repository_type = "private" # hardcoded: private-only module
  repository_name = var.name

  repository_force_delete = var.force_delete

  # --- FSBP ECR.2: immutable tags (hardcoded) ---
  repository_image_tag_mutability = "IMMUTABLE"

  # --- FSBP ECR.1: scan images on push (hardcoded) ---
  repository_image_scan_on_push = true

  # --- FSBP ECR.5: encrypt at rest with the module-managed customer-managed CMK (hardcoded) ---
  repository_encryption_type = "KMS"
  repository_kms_key         = aws_kms_key.this.arn

  # --- FSBP ECR.3: lifecycle policy is always present (hardcoded on/off; retention count tunable) ---
  create_lifecycle_policy     = true
  repository_lifecycle_policy = local.lifecycle_policy

  # --- TLS-only repository policy + optional read / read-write grants (defense-in-depth) ---
  # create_repository_policy = false makes the upstream apply our literal policy verbatim.
  attach_repository_policy = true
  create_repository_policy = false
  repository_policy        = local.repository_policy

  tags = local.tags
}
