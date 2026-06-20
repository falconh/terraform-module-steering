# Steering Document — `terraform-module-aws-elasticache-redis`

> Durable design record (the steering doc preserved with the module). This is the binding context
> for building the module. No git operations were performed while building from this document.
>
> **Automated build note:** this build ran with no human in the loop. Every negotiation/clarifying
> fork was resolved with a reasonable default, recorded inline as `DEFAULT:`.

## 1. Identity
- **Module name:** `terraform-module-aws-elasticache-redis`
- **Provider / service:** AWS / ElastiCache for Redis (replication group)
- **Purpose:** A secure-by-default Amazon ElastiCache for Redis replication group that satisfies the
  mandatory CIS-aligned + AWS FSBP ElastiCache controls with a minimal consumer interface.
- **Target environments:** dev / test / staging / prod

## 2. Reuse decision
- **Wrap or scratch:** Wrap `terraform-aws-modules/elasticache/aws` pinned **`v1.11.0`**, plus a small
  amount of own-resource glue (CMK, CloudWatch log group's KMS key, Secrets Manager secret for the
  write-only AUTH token).
- **Why:** The upstream module exposes every replication-group input the controls need
  (`at_rest_encryption_enabled`, `kms_key_arn`, `transit_encryption_enabled`,
  `automatic_failover_enabled`, `multi_az_enabled`, `num_cache_clusters`,
  `log_delivery_configuration`, `auto_minor_version_upgrade`, `snapshot_retention_limit`,
  `create_subnet_group`/`subnet_ids`). Wrapping inherits its maintenance and lets us hardcode security
  by passing literals.
- **Version floor (confirmed from downloaded `.terraform/modules/elasticache/versions.tf`):**
  terraform `>= 1.0`; aws `>= 5.93`; random `>= 3.0`. **No upper bounds** — the latest Terraform
  (**v1.15.6**, confirmed via `checkpoint-api.hashicorp.com`) and aws provider **v6.50.0** both
  satisfy them and were used for the build. For a NEW module we set `required_version >= 1.11` to
  guarantee the **`ephemeral`/write-only** language features the AUTH-token design depends on.
- **Upstream interface — confirmed from source (not memory):** ran `terraform init -backend=false`,
  then read `.terraform/modules/elasticache/variables.tf`, `outputs.tf`, `main.tf`. Key facts that
  drove the design:
  - The module wires `auth_token = var.auth_token` (a **non-write-only** argument) directly onto
    `aws_elasticache_replication_group`. It does **not** expose `auth_token_wo`.
  - `kms_key_id = var.at_rest_encryption_enabled ? var.kms_key_arn : null`.
  - `automatic_failover_enabled = var.multi_az_enabled || var.cluster_mode_enabled ? true : var.automatic_failover_enabled`.
  - `log_delivery_configuration` is `type = any`; the module auto-creates the CloudWatch log group
    (named `/aws/elasticache/<id>`) when `destination_type = "cloudwatch-logs"` and
    `create_cloudwatch_log_group` is truthy, and accepts `cloudwatch_log_group_kms_key_id`.
  - Outputs are prefixed `replication_group_*`, `cloudwatch_log_group_*`, `subnet_group_name`,
    `security_group_*`.

## 3. Consumer interface (minimise inputs)
- **Required inputs:**
  - `name` — base name/identifier for the replication group and companion resources.
  - `environment` — validated to `dev|test|staging|prod`.
  - `subnet_ids` — VPC subnets for the (custom, non-default) subnet group (FSBP ElastiCache.7).
  - `vpc_id` — VPC for the module-managed security group.
- **Write-only required input (ephemeral):**
  - `auth_token_wo` — the Redis AUTH token, declared `ephemeral = true` (write-only). Never persisted
    to state or plan. Paired with `auth_token_wo_version` to drive rotation.
- **Optional inputs (safe defaults):**
  - `node_type = "cache.t4g.small"`, `engine_version = "7.1"`, `num_cache_clusters = 2`
    (primary + 1 replica; required for Multi-AZ), `tags = {}`,
    `auth_token_wo_version = 1`, `allowed_cidr_blocks = []` (ingress on 6379),
    `apply_immediately = false`.
- **NOT exposed (hardcoded — the non-overridable guarantee):** at-rest encryption + CMK, in-transit
  TLS (`required` mode), Multi-AZ + automatic failover (ON by default), slow-log delivery to
  CloudWatch (JSON), auto minor version upgrade, snapshot retention, custom subnet group (no default
  subnet group), KMS key rotation, the Secrets-Manager write-only sink for the AUTH token.
- **Outputs:** `replication_group_id`, `replication_group_arn`, `primary_endpoint_address`,
  `reader_endpoint_address`, `port`, `member_clusters`, `kms_key_arn`, `kms_key_id`,
  `auth_token_secret_arn`, `auth_token_secret_name`, `cloudwatch_log_group_name`,
  `cloudwatch_log_group_arn`, `security_group_id`, `subnet_group_name`.
- **Provider config:** the module does NOT configure the aws provider; the consumer owns region/creds.

## 4. Security controls (researched, proposed, negotiated)
Benchmarks: **AWS FSBP (Security Hub ElastiCache controls)** + CIS AWS Foundations (general
encryption/logging posture). Researched live from
`docs.aws.amazon.com/securityhub/.../elasticache-controls.html`.

| Control (id) | Intent | Enforcement (hardcoded literal) | Decision | Justification |
|---|---|---|---|---|
| FSBP ElastiCache.4 | Encrypt at rest | `at_rest_encryption_enabled = true` + `kms_key_arn = <module CMK>` (customer-managed KMS) | kept | data-at-rest protection; requirement asks for a CMK specifically |
| FSBP ElastiCache.5 | Encrypt in transit | `transit_encryption_enabled = true` + `transit_encryption_mode = "required"` | kept | TLS enforced for all client/replica traffic |
| FSBP ElastiCache.3 | Automatic failover | `automatic_failover_enabled = true`, `multi_az_enabled = true` (default) | kept | HA; requirement: Multi-AZ + auto failover ON by default |
| FSBP ElastiCache.6 | Redis AUTH (pre-6.0) | Engine pinned `>= 7.x` (RBAC-capable); AUTH token provisioned write-only into Secrets Manager; TLS required | kept (adapted) | requirement asks for an AUTH token; for 7.x TLS+AUTH/RBAC is the posture (see §8 for the state-leak constraint) |
| FSBP ElastiCache.7 | No default subnet group | `create_subnet_group = true` from consumer `subnet_ids`; module never uses `default` | kept | network isolation |
| FSBP ElastiCache.2 | Auto minor version upgrade | `auto_minor_version_upgrade = true` | kept | timely security patches |
| FSBP ElastiCache.1 | Automatic backups | `snapshot_retention_limit = 7` (>= 1) | kept | recoverability |
| — Slow-log delivery | Audit/observability | `log_delivery_configuration` → `cloudwatch-logs`, `slow-log`, `json`; log group KMS-encrypted | added | requirement: slow-log to CloudWatch |
| — KMS key rotation | Key hygiene (CIS 3.x family intent) | `enable_key_rotation = true` on the module CMK | added | best practice |
| — Cost guardrail | Surface Multi-AZ cost | `check "multi_az_cost_warning"` warns at plan/apply when `multi_az_enabled = true` | added | requirement: emit a WARNING about Multi-AZ cost |

_No controls removed without reason. Custom benchmarks: none beyond FSBP/CIS._

### Cost warning mechanism (and its `terraform test` interaction)
Implemented as a `check "multi_az_cost_warning"` block. In real `plan`/`apply` a failed `check`
assertion only **warns** — perfect for surfacing the Multi-AZ cost note. But under `terraform test` a
failed `check` is a **run failure**. Because Multi-AZ defaults ON, the warning fires by default, which
would fail every test. Per the skill's verification guidance: the shared `variables{}` in the test
files set `multi_az_enabled`'s effective state to the **non-warning** value for unrelated runs, and a
**dedicated** run flips it on with `expect_failures = [check.multi_az_cost_warning]` — that run is how
we prove the warning fires.

### Write-only AUTH token mechanism (the hard requirement)
"The AUTH token must never be stored in Terraform state." Confirmed empirically:
`aws_elasticache_replication_group.auth_token` is **not** a write-only attribute (provider 6.50.0),
and Terraform rejects feeding an ephemeral value into it:
`Error: Ephemeral values are not valid for "auth_token", because it is not a write-only attribute and
must be persisted to state.` The provider feature request for `auth_token_wo` (hashicorp issue #42239)
is **open / unimplemented**. So:
- The token is a Terraform **`ephemeral` (write-only) variable** `auth_token_wo` (+
  `auth_token_wo_version`). Ephemeral variables are omitted from state and plan by design.
- It is persisted **only** to AWS Secrets Manager via
  `aws_secretsmanager_secret_version.secret_string_wo` — the one **write-only** sink that exists today
  (`write_only = true` confirmed in the provider schema). Applications read the token from the secret.
- The wrapped module is called with `auth_token = null` (we do **not** route the token through the
  resource, which would persist it to state and violate the requirement). Associating the AUTH token
  with the cluster is a documented one-line post-apply step until the provider ships `auth_token_wo`.

## 5. Conventions
- Files: `versions.tf`, `variables.tf`, `locals.tf`, `main.tf` (wrapped module call), `kms.tf`,
  `secrets.tf`, `checks.tf`, `outputs.tf`. Topic files own real resources; pure expressions live in
  `locals.tf`.
- Block ordering: `count`/`for_each` → args → `tags` → `lifecycle`. Variables: description → type →
  default → validation.
- Pin upstream to exact `v1.11.0`; provider floors only.
- Mandatory tags (`Environment`, `ManagedBy`, `Module`) merged **over** consumer tags.

## 6. Verification pipeline (definition of done)
`terraform fmt -check -recursive` → `terraform validate` → `tflint` → `terraform test` (mock_provider,
no creds) → `checkov -d examples/minimal` (documented suppressions for static-scan false positives and
out-of-scope checks). Done = all green, with evidence.

## 7. Examples, tests & documentation
- `examples/minimal/` — required inputs only (name, environment, vpc_id, subnet_ids, auth token).
- `tests/*.tftest.hcl` — assert KMS rotation, TLS-required, at-rest + CMK wiring, Multi-AZ/auto-failover
  defaults, the secret's write-only sink, the subnet-group/no-default control, and the cost-warning
  `check` (via a dedicated `expect_failures` run).
- `README.md` — usage + "Security controls enforced" table (all hardcoded / non-overridable).
- `docs/DESIGN.md` — this document.

## 8. Out of scope / limitations
- **AUTH-token → cluster association:** because `aws_elasticache_replication_group` has no write-only
  `auth_token_wo` yet (#42239), the module stores the token write-only in Secrets Manager but does not
  set it on the resource (doing so would leak it into state). One documented post-apply step
  (`aws elasticache modify-replication-group --auth-token ... --auth-token-update-strategy SET`) or a
  future provider bump closes this. RBAC user groups are the FSBP-preferred alternative for Redis 6+.
- Global/cross-region replication, data tiering, cluster-mode sharding, custom parameter groups,
  account/org-wide settings.

## 9. Hard rules
- Security controls are **hardcoded literals, not variables**.
- **No git operations** performed while building from this document.
