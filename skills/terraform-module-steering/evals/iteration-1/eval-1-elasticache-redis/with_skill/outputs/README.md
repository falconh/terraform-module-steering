# terraform-module-aws-elasticache-redis

A secure-by-default Amazon ElastiCache for Redis **replication group**. Wraps the proven
[`terraform-aws-modules/elasticache/aws`](https://registry.terraform.io/modules/terraform-aws-modules/elasticache/aws)
module (pinned to `v1.11.0`) and hardcodes the AWS FSBP ElastiCache controls so consumers get a
compliant cluster from a minimal interface — and cannot weaken the security posture.

## Features

- **Encryption at rest with a customer-managed KMS key (CMK)** — the module creates and owns the CMK
  (rotation enabled) and passes it to the replication group. Hardcoded, non-overridable.
- **Encryption in transit (TLS) enforced** — `transit_encryption_enabled = true` with
  `transit_encryption_mode = "required"`. Connect with `rediss://`.
- **Write-only Redis AUTH token** — supplied as an `ephemeral` Terraform variable, so it is **never
  written to Terraform state or plan**. It is persisted only to AWS Secrets Manager via the provider's
  write-only `secret_string_wo` sink. Applications read it from the secret.
- **Multi-AZ with automatic failover, ON by default** — `multi_az_enabled` and
  `automatic_failover_enabled` are hardcoded `true`. A `check` block emits a **cost WARNING** at
  `plan`/`apply` so the cost implication is visible.
- **Slow-log delivery to CloudWatch** (JSON), into a KMS-encrypted log group.
- **No default subnet group, custom security group, auto minor version upgrades, automatic backups** —
  all hardcoded to the FSBP-aligned secure value.
- **Mandatory tags** (`Environment`, `ManagedBy`, `Module`) merged over consumer tags.

## Security controls enforced

Benchmarks: **AWS Foundational Security Best Practices (FSBP)** + CIS AWS Foundations posture.
All settings below are **hardcoded literals** in the module — none are exposed as variables.

| Control (id) | Enforcement | Overridable? |
|---|---|---|
| FSBP ElastiCache.4 — encrypt at rest | `at_rest_encryption_enabled = true` + module-managed **CMK** (`kms_key_arn`) | No — hardcoded |
| FSBP ElastiCache.5 — encrypt in transit | `transit_encryption_enabled = true`, `transit_encryption_mode = "required"` | No — hardcoded |
| FSBP ElastiCache.3 — automatic failover | `automatic_failover_enabled = true`, `multi_az_enabled = true` | No — hardcoded |
| FSBP ElastiCache.6 — Redis AUTH | Engine pinned to a RBAC-capable line (default `7.1`); AUTH token provisioned **write-only** into Secrets Manager; TLS required | No — hardcoded |
| FSBP ElastiCache.7 — no default subnet group | custom subnet group from your `subnet_ids` | No — hardcoded |
| FSBP ElastiCache.2 — auto minor version upgrade | `auto_minor_version_upgrade = true` | No — hardcoded |
| FSBP ElastiCache.1 — automatic backups | `snapshot_retention_limit = 7` | No — hardcoded |
| Slow-log to CloudWatch | `log_delivery_configuration` → `cloudwatch-logs` / `slow-log` / `json`, KMS-encrypted log group | No — hardcoded |
| KMS key rotation | `enable_key_rotation = true` on the CMK | No — hardcoded |
| AUTH token never in state | `ephemeral` variable + Secrets Manager `secret_string_wo` (write-only) | No — by design |

> **Note on the AUTH token → cluster association.** The AWS provider's
> `aws_elasticache_replication_group` resource does **not** yet expose a write-only `auth_token_wo`
> argument (HashiCorp provider issue [#42239], open). Routing the token through it would persist it to
> state, violating the write-only guarantee. This module therefore stores the token write-only in
> Secrets Manager and does **not** set it on the resource. To bind the token to the running cluster,
> run once after apply:
> ```bash
> aws elasticache modify-replication-group \
>   --replication-group-id <name> \
>   --auth-token "$(aws secretsmanager get-secret-value --secret-id <auth_token_secret_name> --query SecretString --output text)" \
>   --auth-token-update-strategy SET --apply-immediately
> ```
> When the provider ships `auth_token_wo`, the module can wire it directly. RBAC user groups are the
> FSBP-recommended alternative for Redis 6+.

## Usage

```hcl
# Supply the AUTH token via an ephemeral variable (e.g. TF_VAR_auth_token_wo),
# never as a literal in version-controlled HCL.
variable "auth_token_wo" {
  type      = string
  ephemeral = true
  sensitive = true
}

module "redis" {
  source = "github.com/your-org/terraform-module-aws-elasticache-redis"

  name        = "orders-cache"
  environment = "prod"

  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0aaa1111", "subnet-0bbb2222"] # >= 2 AZs

  auth_token_wo       = var.auth_token_wo
  allowed_cidr_blocks = ["10.0.0.0/16"]
}
```

At `plan`/`apply` you will see the intentional cost warning:

```
Warning: Check block assertion failed
COST WARNING: Multi-AZ with automatic failover is ENABLED (secure-by-default HA). ...
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.11 (ephemeral/write-only variables) |
| aws | >= 5.93 |
| random | >= 3.0 |

Wrapped module: `terraform-aws-modules/elasticache/aws` `1.11.0`.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Base name/identifier for the replication group and companion resources. | `string` | n/a | yes |
| `environment` | Deployment environment (`dev`/`test`/`staging`/`prod`). | `string` | n/a | yes |
| `vpc_id` | VPC where the module-managed security group is created. | `string` | n/a | yes |
| `subnet_ids` | VPC subnet IDs for the custom subnet group (>= 2, different AZs). | `list(string)` | n/a | yes |
| `auth_token_wo` | Redis AUTH token. **Ephemeral/write-only** — never in state. 16–128 chars. | `string` (ephemeral) | n/a | yes |
| `auth_token_wo_version` | Version for the write-only token; increment to rotate. | `number` | `1` | no |
| `node_type` | ElastiCache node instance class. | `string` | `"cache.t4g.small"` | no |
| `engine_version` | Redis engine version (RBAC-capable by default). | `string` | `"7.1"` | no |
| `num_cache_clusters` | Number of nodes (primary + replicas); >= 2 for Multi-AZ. | `number` | `2` | no |
| `allowed_cidr_blocks` | CIDRs allowed to reach the Redis TLS port (6379). | `list(string)` | `[]` | no |
| `apply_immediately` | Apply modifications immediately vs. maintenance window. | `bool` | `false` | no |
| `tags` | Additional tags (mandatory tags are merged over these). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `replication_group_id` | ID of the replication group. |
| `replication_group_arn` | ARN of the replication group. |
| `primary_endpoint_address` | Primary (write) endpoint. Connect over TLS. |
| `reader_endpoint_address` | Reader (read-only) endpoint. Connect over TLS. |
| `port` | Listener port. |
| `member_clusters` | Node identifiers (primary + replicas). |
| `kms_key_arn` | ARN of the customer-managed KMS key. |
| `kms_key_id` | ID of the customer-managed KMS key. |
| `auth_token_secret_arn` | Secrets Manager ARN holding the write-only AUTH token. |
| `auth_token_secret_name` | Secrets Manager secret name. |
| `cloudwatch_log_group_name` | CloudWatch log group receiving slow-log delivery. |
| `cloudwatch_log_group_arn` | ARN of that log group. |
| `security_group_id` | Module-managed security group ID. |
| `subnet_group_name` | Custom (non-default) subnet group name. |

## Examples

- [minimal](examples/minimal) — required inputs only.

## Verification

This module is verified with: `terraform fmt -check -recursive`, `terraform validate`, `tflint`,
`terraform test` (native tests with `mock_provider`, no credentials), and `checkov`. See
[docs/DESIGN.md](docs/DESIGN.md) for the control mapping and [BUILD_LOG.md](BUILD_LOG.md) for evidence.

## License

MIT (or your organisation's standard module license).

[#42239]: https://github.com/hashicorp/terraform-provider-aws/issues/42239
