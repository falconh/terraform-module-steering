locals {
  # Mandatory tags merged OVER consumer tags: consumers cannot drop these.
  tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "terraform-module-aws-elasticache-redis"
    },
  )
}

# Cost warning surfaced at every `terraform plan` / `terraform apply`.
# Multi-AZ + automatic failover are hardcoded ON, which roughly doubles
# node-hours and adds cross-AZ data-transfer charges. A `check` block emits a
# non-fatal WARNING (the apply still succeeds) so consumers always see this.
#
# Under `terraform test`, a failed check is promoted to a failure, so each test
# `run` that applies this module declares `expect_failures = [check.multi_az_cost_warning]`.
check "multi_az_cost_warning" {
  assert {
    # Intentionally always false: multi_az is hardcoded ON, so num_cache_clusters
    # is always >= 2. Referencing the variable satisfies Terraform's requirement
    # that a check condition reference a config object, while guaranteeing the
    # warning fires on every plan/apply.
    condition     = var.num_cache_clusters < 0
    error_message = "COST WARNING: This module hardcodes Multi-AZ with automatic failover ENABLED. It provisions at least one replica node per primary (num_cache_clusters = ${var.num_cache_clusters}, roughly doubling node-hours) and incurs cross-AZ data-transfer charges. This is intentional for production resilience (FSBP ElastiCache.3). Budget accordingly."
  }
}

module "redis" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.11.0"

  # --- Identity / topology ---
  replication_group_id     = var.name
  create_cluster           = false
  create_replication_group = true
  description              = "Secure-by-default Redis replication group for ${var.name} (${var.environment})."
  engine                   = "redis"
  engine_version           = var.engine_version
  node_type                = var.node_type
  num_cache_clusters       = var.num_cache_clusters

  # --- HARDCODED security controls (non-overridable) ---
  # FSBP ElastiCache.4 — encryption at rest with a customer-managed KMS key.
  at_rest_encryption_enabled = true
  kms_key_arn                = aws_kms_key.this.arn

  # FSBP ElastiCache.5 — encryption in transit (TLS) ENFORCED, not merely preferred.
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"

  # FSBP ElastiCache.3 + Multi-AZ — automatic failover and multi-AZ ON by default.
  # (Upstream also forces automatic_failover_enabled=true when multi_az_enabled=true.)
  multi_az_enabled           = true
  automatic_failover_enabled = true

  # FSBP ElastiCache.2 — automatic minor version upgrades.
  auto_minor_version_upgrade = true

  # FSBP ElastiCache.1 — automatic backups (>= 1 day).
  snapshot_retention_limit = 7

  # FSBP ElastiCache.7 — custom (non-default) subnet group.
  create_subnet_group      = true
  subnet_group_name        = "${var.name}-redis"
  subnet_group_description = "Custom subnet group for ${var.name} Redis (FSBP ElastiCache.7)."
  subnet_ids               = var.subnet_ids

  # Module-managed security group (no inline ingress; consumer attaches rules via
  # their own SG references in production). Egress kept default-closed by upstream.
  create_security_group = true
  vpc_id                = var.vpc_id
  security_group_name   = "${var.name}-redis"
  security_group_rules  = {}

  # Slow-log delivery to a module-created CloudWatch log group (JSON), CMK-encrypted.
  log_delivery_configuration = {
    slow-log = {
      destination_type                       = "cloudwatch-logs"
      log_format                             = "json"
      log_type                               = "slow-log"
      cloudwatch_log_group_name              = "${var.name}-redis-slow"
      cloudwatch_log_group_retention_in_days = var.cloudwatch_log_retention_in_days
      cloudwatch_log_group_kms_key_id        = aws_kms_key.this.arn
    }
  }

  # AUTH token is intentionally NOT passed here. See secret.tf — the token is
  # write-only and is stored only in Secrets Manager, never in Terraform state.
  # Routing the ephemeral value into this non-write-only argument is rejected by
  # Terraform by design.

  tags = local.tags
}
