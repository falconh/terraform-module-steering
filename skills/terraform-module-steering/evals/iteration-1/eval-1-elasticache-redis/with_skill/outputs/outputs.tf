################################################################################
# Replication group
################################################################################

output "replication_group_id" {
  description = "ID of the ElastiCache Redis replication group."
  value       = module.elasticache.replication_group_id
}

output "replication_group_arn" {
  description = "ARN of the ElastiCache Redis replication group."
  value       = module.elasticache.replication_group_arn
}

output "primary_endpoint_address" {
  description = "Primary (write) endpoint address. Connect over TLS (rediss://)."
  value       = module.elasticache.replication_group_primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader (read-only) endpoint address. Connect over TLS (rediss://)."
  value       = module.elasticache.replication_group_reader_endpoint_address
}

output "port" {
  description = "Port the replication group listens on."
  value       = module.elasticache.replication_group_port
}

output "member_clusters" {
  description = "Identifiers of the nodes (primary + replicas) in the replication group."
  value       = module.elasticache.replication_group_member_clusters
}

################################################################################
# Encryption / AUTH
################################################################################

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key used for at-rest encryption, slow logs, and the AUTH secret."
  value       = aws_kms_key.this.arn
}

output "kms_key_id" {
  description = "ID of the customer-managed KMS key."
  value       = aws_kms_key.this.key_id
}

output "auth_token_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the Redis AUTH token (write-only; never in Terraform state)."
  value       = aws_secretsmanager_secret.auth_token.arn
}

output "auth_token_secret_name" {
  description = "Name of the Secrets Manager secret holding the Redis AUTH token."
  value       = aws_secretsmanager_secret.auth_token.name
}

################################################################################
# Logging / network
################################################################################

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group receiving Redis slow-log delivery."
  value       = try(module.elasticache.cloudwatch_log_groups["slow-log"].name, null)
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group receiving Redis slow-log delivery."
  value       = try(module.elasticache.cloudwatch_log_groups["slow-log"].arn, null)
}

output "security_group_id" {
  description = "ID of the module-managed security group for the replication group."
  value       = module.elasticache.security_group_id
}

output "subnet_group_name" {
  description = "Name of the custom (non-default) ElastiCache subnet group."
  value       = module.elasticache.subnet_group_name
}
