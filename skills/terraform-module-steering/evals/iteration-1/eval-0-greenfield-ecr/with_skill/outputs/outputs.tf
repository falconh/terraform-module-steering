output "repository_arn" {
  description = "Full ARN of the ECR repository."
  value       = module.ecr.repository_arn
}

output "repository_name" {
  description = "Name of the ECR repository."
  value       = module.ecr.repository_name
}

output "repository_url" {
  description = "URL of the ECR repository (used as the image push/pull target)."
  value       = module.ecr.repository_url
}

output "repository_registry_id" {
  description = "Registry ID (account ID) where the repository was created."
  value       = module.ecr.repository_registry_id
}

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key encrypting the repository."
  value       = aws_kms_key.this.arn
}

output "kms_key_id" {
  description = "ID of the customer-managed KMS key encrypting the repository."
  value       = aws_kms_key.this.key_id
}

output "kms_key_alias_arn" {
  description = "ARN of the alias for the customer-managed KMS key."
  value       = aws_kms_alias.this.arn
}
