################################################################################
# Secure-by-default ElastiCache for Redis replication group.
# Wraps terraform-aws-modules/elasticache/aws (pinned), passing security as
# hardcoded literals (from locals.tf) so consumers cannot weaken them.
################################################################################

module "elasticache" {
  # checkov:skip=CKV_TF_1:Registry modules are pinned by EXACT version (1.11.0), which is the correct supply-chain practice; CKV_TF_2 (version tag) passes. Commit-hash pinning does not apply to registry sources.
  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.11.0"

  replication_group_id = var.name
  description          = "Secure-by-default Redis replication group for ${var.name} (${var.environment})"

  engine         = local.engine
  engine_version = var.engine_version
  node_type      = var.node_type

  # High availability (FSBP ElastiCache.3) — hardcoded ON. Cost surfaced via checks.tf.
  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = local.automatic_failover_enabled
  multi_az_enabled           = local.multi_az_enabled

  # Encryption at rest with a customer-managed KMS key (FSBP ElastiCache.4) — hardcoded.
  at_rest_encryption_enabled = local.at_rest_encryption_enabled
  kms_key_arn                = aws_kms_key.this.arn

  # Encryption in transit / TLS required (FSBP ElastiCache.5) — hardcoded.
  transit_encryption_enabled = local.transit_encryption_enabled
  transit_encryption_mode    = local.transit_encryption_mode

  # AUTH token is deliberately NOT routed through the resource: doing so would
  # persist it to Terraform state. The token is provisioned write-only into
  # Secrets Manager (secrets.tf). See docs/DESIGN.md §8.
  auth_token = null

  # Patching and backups (FSBP ElastiCache.2 / ElastiCache.1) — hardcoded.
  auto_minor_version_upgrade = local.auto_minor_version_upgrade
  snapshot_retention_limit   = local.snapshot_retention_limit

  # Slow-log delivery to CloudWatch (JSON), KMS-encrypted log group.
  log_delivery_configuration = local.log_delivery_configuration

  apply_immediately = var.apply_immediately

  # Custom (non-default) subnet group from consumer subnets (FSBP ElastiCache.7).
  create_subnet_group = true
  subnet_group_name   = var.name
  subnet_ids          = var.subnet_ids

  # Module-managed security group; ingress on the Redis port from allowed CIDRs.
  create_security_group = true
  security_group_name   = var.name
  vpc_id                = var.vpc_id
  security_group_rules  = local.security_group_rules

  tags = local.tags

  depends_on = [aws_secretsmanager_secret_version.auth_token]
}
