# terraform-module-aws-elasticache-redis

A secure-by-default Amazon **ElastiCache for Redis replication group**. It wraps the proven
[`terraform-aws-modules/elasticache/aws`](https://registry.terraform.io/modules/terraform-aws-modules/elasticache/aws)
module (pinned `1.11.0`) and hardcodes the relevant AWS Foundational Security Best Practices (FSBP)
ElastiCache controls so a consumer cannot weaken them.

## Features

- **Encryption at rest with a customer-managed KMS key** (module-created CMK, rotation enabled).
- **Encryption in transit (TLS) enforced** — `transit_encryption_mode = "required"`, not merely preferred.
- **Write-only Redis AUTH token** — the token is an `ephemeral` input that is **never written to
  Terraform state or plan**. It is stored only in AWS Secrets Manager via the provider's write-only
  `secret_string_wo` argument (the value is discarded by Terraform after use).
- **Multi-AZ with automatic failover ENABLED by default** — and the module **emits a cost WARNING** at
  every `plan`/`apply` so the cost implication is visible.
- **Slow-log delivery to CloudWatch** — a CMK-encrypted, module-managed log group in JSON format.
- **Automatic backups**, **automatic minor version upgrades**, and a **custom (non-default) subnet group**.
- **Mandatory tags** merged over consumer tags (consumers cannot drop them).

## Security controls enforced

Benchmark: **AWS FSBP** (the Security Hub ElastiCache controls). _Note: the CIS AWS Foundations
Benchmark has no ElastiCache-specific controls; FSBP is the governing service benchmark. The CMK uses
CIS-aligned key rotation._

| Control (FSBP id) | Enforcement | Overridable? |
|---|---|---|
| ElastiCache.4 — encryption at rest | `at_rest_encryption_enabled = true` + module CMK `kms_key_arn` | No — hardcoded |
| ElastiCache.5 — encryption in transit | `transit_encryption_enabled = true`, `transit_encryption_mode = "required"` | No — hardcoded |
| ElastiCache.6 — Redis AUTH | AUTH token stored write-only in Secrets Manager (`secret_string_wo`); TLS on | No — hardcoded |
| ElastiCache.3 — automatic failover | `automatic_failover_enabled = true` | No — hardcoded |
| Multi-AZ (HA) | `multi_az_enabled = true` (emits a cost WARNING) | No — hardcoded |
| ElastiCache.1 — automatic backups | `snapshot_retention_limit = 7` | No — hardcoded |
| ElastiCache.2 — auto minor version upgrades | `auto_minor_version_upgrade = true` | No — hardcoded |
| ElastiCache.7 — custom subnet group | `create_subnet_group = true` from your `subnet_ids` | No — hardcoded |
| KMS key rotation (CIS-aligned) | `enable_key_rotation = true` on the CMK | No — hardcoded |
| AUTH secret encrypted with CMK | `kms_key_id = <module CMK>` on the secret | No — hardcoded |

## The write-only AUTH token (read this)

`aws_elasticache_replication_group` does **not** yet support a native write-only `auth_token_wo`
argument (tracked in [hashicorp/terraform-provider-aws#42239](https://github.com/hashicorp/terraform-provider-aws/issues/42239)),
and its `auth_token` argument persists to state. To guarantee the token never lands in Terraform state,
this module:

1. Accepts the token through the `auth_token` variable, declared **`ephemeral = true`** (so the value is
   never serialized to state or plan).
2. Stores it **only** in a module-managed, CMK-encrypted **Secrets Manager** secret using the write-only
   `secret_string_wo` argument. Terraform discards the value after the apply.
3. Does **not** pass the token into the upstream module's `auth_token` (doing so would persist it, and
   Terraform actively rejects routing an ephemeral value there).

**Operational note:** because the cluster argument is not write-only, applying/rotating the AUTH token on
the running replication group is an out-of-band step — your application and operators read the live token
from `auth_token_secret_arn`. Rotate the stored value by incrementing `auth_token_rotation`.

## Cost warning

Multi-AZ + automatic failover are hardcoded **ON**. This provisions at least one replica per primary
(roughly doubling node-hours) and adds cross-AZ data-transfer charges. The module surfaces a non-fatal
`Warning: Check block assertion failed` with a `COST WARNING:` message on **every** `terraform plan` and
`terraform apply` so the implication is never silent. The apply still succeeds.

## Usage

```hcl
# The AUTH token is ephemeral/write-only — source it from an ephemeral resource
# or a CI secret, never a committed tfvars.
variable "redis_auth_token" {
  type      = string
  ephemeral = true
  sensitive = true
}

module "redis" {
  source = "github.com/your-org/terraform-module-aws-elasticache-redis" # or your registry path

  name        = "orders-cache"
  environment = "prod"

  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0aaa...", "subnet-0bbb..."] # >= 2 private subnets in different AZs

  auth_token = var.redis_auth_token
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.11 |
| aws | >= 6.0 |
| random | >= 3.0 |

> Terraform **1.11+** is required for write-only arguments (`secret_string_wo`).

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Base name for the replication group and companion resources. | `string` | n/a | yes |
| `environment` | Deployment environment (`dev`/`test`/`staging`/`prod`). | `string` | n/a | yes |
| `vpc_id` | VPC for the module-managed security group. | `string` | n/a | yes |
| `subnet_ids` | Private subnet IDs for the custom subnet group (>= 2, different AZs). | `list(string)` | n/a | yes |
| `auth_token` | Redis AUTH token. **Ephemeral / write-only** — never stored in state. | `string` (ephemeral) | n/a | yes |
| `auth_token_rotation` | Integer trigger to re-apply the write-only secret value (rotation). | `number` | `1` | no |
| `node_type` | Cache node instance type. | `string` | `"cache.t4g.small"` | no |
| `engine_version` | Redis OSS engine version. | `string` | `"7.1"` | no |
| `num_cache_clusters` | Nodes (1 primary + replicas); >= 2 for failover/multi-AZ. | `number` | `2` | no |
| `kms_deletion_window_in_days` | CMK deletion waiting period (7–30). | `number` | `30` | no |
| `cloudwatch_log_retention_in_days` | Slow-log retention in days. | `number` | `365` | no |
| `tags` | Additional tags merged UNDER the mandatory tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `replication_group_id` | Identifier of the replication group. |
| `replication_group_arn` | ARN of the replication group. |
| `primary_endpoint_address` | Primary endpoint (connect with TLS). |
| `reader_endpoint_address` | Reader endpoint (connect with TLS). |
| `port` | Replication group port. |
| `member_clusters` | Identifiers of all member nodes. |
| `kms_key_arn` | CMK ARN (at-rest, auth secret, logs). |
| `kms_key_alias` | CMK alias. |
| `auth_token_secret_arn` | ARN of the Secrets Manager secret holding the AUTH token (value never exposed). |
| `auth_token_secret_name` | Name of the AUTH secret. |
| `cloudwatch_log_groups` | Map of CloudWatch log groups created for slow-log delivery. |
| `security_group_id` | Module-managed security group ID. |
| `subnet_group_name` | Custom cache subnet group name. |

## Examples

- [minimal](examples/minimal) — required inputs only; doubles as the checkov scan fixture.

## Verification

This module is verified with `terraform fmt`, `terraform validate`, `tflint`, `terraform test`
(native tests with `mock_provider`, no AWS credentials), and `checkov`. See
[docs/DESIGN.md](docs/DESIGN.md) and `BUILD_LOG.md` for the control mapping, design decisions, and
recorded command output.

## License

Apache-2.0 (placeholder — set to your organisation's license).
