# BUILD_LOG — `terraform-module-aws-elasticache-redis`

Automated build following the `terraform-module-steering` skill (Path A, greenfield). No human was
available, so every fork was resolved with a reasonable default, noted inline as **DECISION**. No git
operations were performed at any point.

## Environment / tool versions
- **Terraform: v1.15.6** (latest stable; confirmed via the GitHub releases page — released 2026-06-10).
- TFLint 0.63.1 (+ aws ruleset 0.44.0).
- Checkov 3.3.1.
- Latest AWS provider identified: **v6.50.0** (released 2026-06-10); module floor pinned to `>= 6.0`.
- terraform-docs: not installed (optional) → Inputs/Outputs tables in README hand-written.

## Fork decisions
1. **Mode:** NEW module → Path A (greenfield). No clarifying questions (automated).
2. **Reuse:** WRAP `terraform-aws-modules/elasticache/aws` pinned **`1.11.0`** (latest, 2026-01-29).
   Rationale: exposes every needed control as inputs (at-rest+KMS, transit+mode, multi-AZ, failover,
   num_cache_clusters, log_delivery_configuration with self-managed CW log group, snapshots, minor
   upgrades, custom subnet group).
3. **Benchmark:** FSBP ElastiCache controls govern; **CIS AWS Foundations Benchmark has no
   ElastiCache-specific controls** — stated plainly (skill's generalisation rule). CMK rotation applied
   as a CIS-aligned posture.
4. **Write-only AUTH token mechanism:** stored only in Secrets Manager via write-only `secret_string_wo`,
   sourced from an `ephemeral` variable; NOT routed through the upstream `auth_token`. (Details below.)
5. **Cost warning mechanism:** `check "multi_az_cost_warning"` block (non-fatal warning at plan/apply) +
   `expect_failures` in every applying test run. (Details below.)
6. **Interface defaults:** `node_type=cache.t4g.small`, `engine_version=7.1`, `num_cache_clusters=2`
   (minimum for failover/multi-AZ), `snapshot_retention_limit=7`, `transit_encryption_mode=required`,
   `kms_deletion_window=30`, `cloudwatch_log_retention=365`. Each noted in DESIGN.md §3.
7. **checkov suppressions:** CKV_TF_1 (registry semver pin is by design; CKV_TF_2 passes) and CKV2_AWS_57
   (auto rotation Lambda out of scope) — documented; plus pre-emptive CKV_AWS_29/30/31 for upstream
   separate-resource FPs (not triggered by this checkov version, left documented).

## How the wrapped module's interface was confirmed (commands/files)
Read the upstream source **directly at tag `v1.11.0`** rather than trusting memory or the JS-rendered
registry page:
- `variables.tf` → full input list + defaults (confirmed `at_rest_encryption_enabled`, `kms_key_arn`,
  `transit_encryption_enabled`, `transit_encryption_mode`, `multi_az_enabled`, `automatic_failover_enabled`,
  `auth_token`, `auth_token_update_strategy`, `num_cache_clusters`, `log_delivery_configuration`,
  `create_subnet_group`, `subnet_ids`, `create_security_group`, `vpc_id`, `snapshot_retention_limit`,
  `auto_minor_version_upgrade`).
- `outputs.tf` → output names (`replication_group_id/arn`, `replication_group_primary_endpoint_address`,
  `replication_group_reader_endpoint_address`, `replication_group_port`, `replication_group_member_clusters`,
  `cloudwatch_log_groups`, `security_group_id`, `subnet_group_name`).
- `main.tf` → wiring: confirmed the module **derives** `automatic_failover_enabled = multi_az_enabled ||
  cluster_mode_enabled ? true : var.automatic_failover_enabled` (so setting `multi_az_enabled=true` forces
  failover on), and that it **creates its own** `aws_cloudwatch_log_group.this` for each
  `log_delivery_configuration` entry with `destination_type=="cloudwatch-logs"`, reading per-entry keys
  `cloudwatch_log_group_name/retention_in_days/kms_key_id/class`.
- `versions.tf` → upstream floors: terraform `>= 1.0`, aws `>= 5.93`, random `>= 3.0`. We raised
  terraform to `>= 1.11` and aws to `>= 6.0` for the write-only path.

It was further confirmed at build time by `terraform init -backend=false` (downloaded the module to
`.terraform/modules/redis`) and by checkov resolving the real upstream resources (e.g. CKV2_AWS_50
multi-AZ check PASSED against `aws_elasticache_replication_group.this[0]`).

## Write-only AUTH token: implementation + how tests handle it
**Research:** the native `auth_token_wo` write-only argument is an open enhancement
(hashicorp/terraform-provider-aws#42239) and is **absent** from AWS provider 6.50.0; `auth_token` persists
to state. **Empirical probes (run during the build):**
- `auth_token = var.<ephemeral>` on `aws_elasticache_replication_group` →
  `Error: Ephemeral values are not valid for "auth_token", because it is not a write-only attribute and must be persisted to state.`
- Same ephemeral value into the **upstream module's** `auth_token` →
  `Error: Ephemeral value not allowed ... This input variable is not declared as accepting a ephemeral values.`
- Ephemeral value into `aws_secretsmanager_secret_version.secret_string_wo` → **`Success! The configuration is valid.`**

**Implementation:** wrapper variable `auth_token` is `ephemeral = true` + `sensitive = true` (never in
state/plan). It is written ONLY to a CMK-encrypted Secrets Manager secret via `secret_string_wo` (paired
with `secret_string_wo_version = var.auth_token_rotation`). It is deliberately NOT passed to the upstream
module's `auth_token`. The token value is never an output (only `auth_token_secret_arn`/`_name`).

**Tests handle it** (`tests/redis.tftest.hcl`, `mock_provider`, `command = apply`):
- assert `aws_secretsmanager_secret_version.auth_token.secret_string` is null/empty → proves the token is
  **not in state**;
- assert `secret_string_wo_version == 1` (and `== 3` when `auth_token_rotation=3`) → the write-only
  trigger is wired;
- assert the secret is CMK-encrypted and the outputs expose only the ARN/name, never the value.
No failures were encountered with the write-only token in tests — the mock provider returns null for the
write-only `secret_string`, exactly matching the "never in state" assertion.

## Cost warning: implementation + interaction with `terraform test`
**Implementation:** `check "multi_az_cost_warning"` in `main.tf` with an assertion that is intentionally
always false (`var.num_cache_clusters < 0`, referencing a config object as Terraform requires) and a
`COST WARNING: ...` `error_message`. At `terraform plan`/`apply` this prints a **non-fatal Warning**
(verified — the warning text renders; the apply is not blocked by it).

**Interaction with `terraform test` (this is the fork the task flagged):** a naked `check` block **fails**
`terraform test` — a probe showed `0 passed, 1 failed` because `terraform test` promotes a failed check
assertion into a test failure. **Resolution (verified):** declare
`expect_failures = [check.multi_az_cost_warning]` in every applying `run` → probe then showed
`1 passed, 0 failed` with the warning still emitted. This pattern is used in all 5 runs.

Two false-start errors were fixed while wiring the check block (caught by `terraform init`/`validate`):
- `Check blocks must have at least one assert block` / `condition expression must refer to at least one
  object` — fixed by making the condition reference `var.num_cache_clusters` (instead of the literal
  `false`).

## Verification commands and REAL results

| Stage | Command | Result | Fix/rerun cycles |
|---|---|---|---|
| 1. fmt | `terraform fmt -check -recursive` | first run exit **3** (main.tf), after `terraform fmt -recursive` → **exit 0** | **1** |
| 2. validate | `terraform init -backend=false` + `terraform validate` | first init **failed** (check-block errors), after fix → init ok, `validate` → **Success! The configuration is valid.** | **1** |
| 3. tflint | `tflint --recursive` (after `tflint --init`) | **exit 0**, no findings (module + example) | **0** |
| 4. terraform test | `terraform test` | first run **4 passed, 1 failed** (mocked computed `replication_group_id`), after fix → **5 passed, 0 failed** | **1** |
| 5. checkov | `checkov -d examples/minimal --config-file .checkov.yaml --download-external-modules true` | first run **37 passed, 2 failed** (CKV_TF_1, CKV2_AWS_57), after documented suppressions → **37 passed, 0 failed, 4 skipped**, **exit 0** | **1** |

**Final consolidated pipeline run (all green together):**
```
1. terraform fmt -check -recursive   -> exit 0
2. terraform validate                -> Success! The configuration is valid.  (exit 0)
3. tflint --recursive                -> exit 0
4. terraform test                    -> 5 passed, 0 failed
5. checkov                           -> Passed checks: 37, Failed checks: 0, Skipped checks: 4  (exit 0)
```

The 5 passing tests:
`encryption_at_rest_uses_customer_managed_kms`, `auth_token_is_write_only_in_secrets_manager`,
`outputs_never_expose_the_token`, `mandatory_tags_cannot_be_dropped`, `rotation_trigger_is_propagated`.

The cost warning was also confirmed to render at `terraform plan`:
```
Warning: Check block assertion failed
  on main.tf line 26, in check "multi_az_cost_warning":
  COST WARNING: This module hardcodes Multi-AZ with automatic failover ENABLED. ...
```

## Fix/rerun cycle summary
- fmt: 1 cycle (apply formatting).
- validate: 1 cycle (check-block assert/condition rules).
- tflint: 0 cycles.
- terraform test: 1 cycle (re-target one assertion off a mock-randomised computed attribute).
- checkov: 1 cycle (two documented suppressions).

## Git confirmation
**No git operations were performed** — no `init`, `add`, `commit`, `push`, `branch`, `tag`, or config
changes to any repository. All output is local files under this directory. `.terraform.lock.hcl` was
created by `terraform init` (a tooling side-effect, not a git action); the creator decides whether to
keep it.
