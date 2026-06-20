locals {
  # Mandatory tags merged OVER consumer tags so a consumer cannot drop them.
  mandatory_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "terraform-module-aws-elasticache-redis"
  }
  tags = merge(var.tags, local.mandatory_tags)

  # Hardcoded security posture (literals, not variables) — the non-overridable guarantee.
  at_rest_encryption_enabled = true # FSBP ElastiCache.4
  transit_encryption_enabled = true # FSBP ElastiCache.5
  transit_encryption_mode    = "required"
  automatic_failover_enabled = true # FSBP ElastiCache.3
  multi_az_enabled           = true # HA default (cost surfaced via checks.tf)
  auto_minor_version_upgrade = true # FSBP ElastiCache.2
  snapshot_retention_limit   = 7    # FSBP ElastiCache.1 (>= 1)
  engine                     = "redis"

  # Slow-log delivery to CloudWatch (JSON), with the log group KMS-encrypted by our CMK.
  log_delivery_configuration = {
    slow-log = {
      destination_type                = "cloudwatch-logs"
      log_format                      = "json"
      log_type                        = "slow-log"
      create_cloudwatch_log_group     = true
      cloudwatch_log_group_kms_key_id = aws_kms_key.this.arn
    }
  }

  # One ingress rule per allowed CIDR on the Redis (TLS) port. Empty list => no ingress.
  # Upstream module expects aws_vpc_security_group_ingress_rule shape: ip_protocol + single cidr_ipv4.
  security_group_rules = {
    for idx, cidr in var.allowed_cidr_blocks : "ingress_redis_${idx}" => {
      type        = "ingress"
      from_port   = 6379
      to_port     = 6379
      ip_protocol = "tcp"
      description = "Redis (TLS) from ${cidr}"
      cidr_ipv4   = cidr
    }
  }
}
