output "replication_group_id" {
  description = "Identifier of the ElastiCache Redis replication group."
  value       = module.redis.replication_group_id
}

output "replication_group_arn" {
  description = "ARN of the ElastiCache Redis replication group."
  value       = module.redis.replication_group_arn
}

output "primary_endpoint_address" {
  description = "Primary endpoint address (cluster mode disabled). Connect with TLS."
  value       = module.redis.replication_group_primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint address (cluster mode disabled). Connect with TLS."
  value       = module.redis.replication_group_reader_endpoint_address
}

output "port" {
  description = "Port of the replication group primary."
  value       = module.redis.replication_group_port
}

output "member_clusters" {
  description = "Identifiers of all member nodes in the replication group."
  value       = module.redis.replication_group_member_clusters
}

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key used for at-rest encryption, the AUTH secret, and slow logs."
  value       = aws_kms_key.this.arn
}

output "kms_key_alias" {
  description = "Alias of the customer-managed KMS key."
  value       = aws_kms_alias.this.name
}

output "auth_token_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the Redis AUTH token. The token VALUE is never exposed by this module; read it from this secret at runtime."
  value       = aws_secretsmanager_secret.auth_token.arn
}

output "auth_token_secret_name" {
  description = "Name of the Secrets Manager secret holding the Redis AUTH token."
  value       = aws_secretsmanager_secret.auth_token.name
}

output "cloudwatch_log_groups" {
  description = "Map of CloudWatch log groups created for slow-log delivery."
  value       = module.redis.cloudwatch_log_groups
}

output "security_group_id" {
  description = "ID of the module-managed security group for the replication group."
  value       = module.redis.security_group_id
}

output "subnet_group_name" {
  description = "Name of the custom cache subnet group."
  value       = module.redis.subnet_group_name
}
