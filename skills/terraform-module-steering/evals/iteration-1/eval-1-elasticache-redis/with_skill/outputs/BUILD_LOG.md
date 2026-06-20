# BUILD_LOG — terraform-module-aws-elasticache-redis

Automated build following the `terraform-module-steering` skill (Path A — new/greenfield module).
No human was available; every fork was resolved with a reasonable default, noted inline, and the build
was driven to completion. **No git operations were performed at any point.**

---

## 0. Toolchain / latest Terraform

- Latest Terraform identified via `https://checkpoint-api.hashicorp.com/v1/check/terraform`:
  **`1.15.6`** — and that is exactly the installed version (`terraform v1.15.6`). No upgrade needed.
- Other tools present (workspace checker, report mode): `tflint 0.63.1`, `checkov 3.3.1`,
  `tfenv`. `terraform-docs` and `trivy` absent (optional) → Inputs/Outputs tables hand-written.
- Upstream module floors (confirmed from downloaded source, see §2) are `>= 1.0` / aws `>= 5.93` /
  random `>= 3.0` with **no upper bound**, so the latest Terraform + aws provider 6.50.0 satisfy them.
  Module `required_version` set to **`>= 1.11`** to guarantee the `ephemeral`/write-only language
  features the AUTH-token design needs.

---

## 1. Fork decisions (each resolved with a default, no human asked)

| # | Fork point | Default chosen | One-line rationale |
|---|---|---|---|
| 1 | Mode (new vs change) | **New module (Path A)** | nothing existed to change |
| 2 | Runtime fork (stop after steering doc vs continue to build) | **Continue to full build** | task requires a complete, verified module |
| 3 | Upstream wrap vs scratch | **Wrap `terraform-aws-modules/elasticache/aws` `v1.11.0`** | exposes every RG control needed; inherits maintenance |
| 4 | Auth model (RBAC user groups vs AUTH token) | **AUTH token** (Secrets Manager, write-only) | requirement says "Redis AUTH token"; RBAC noted as the FSBP-preferred alternative |
| 5 | **How to keep the AUTH token out of state** | **ephemeral variable + Secrets Manager `secret_string_wo`; do NOT route token through the RG resource** | the RG resource attribute is not write-only (see §3) — routing it would persist it to state |
| 6 | Cost-warning mechanism | **`check` block** that warns when Multi-AZ is on | `check` warns (not errors) in real plan/apply; requirement asks for a visible warning |
| 7 | Default engine / node / sizing | `engine_version = 7.1`, `node_type = cache.t4g.small`, `num_cache_clusters = 2` | RBAC-capable engine; small cost-sane default; 2 nodes required for Multi-AZ |
| 8 | Checkov suppressions | **inline `#checkov:skip` with reasons** (+ documented `.checkov.yaml`) | scoped tightly; each is a documented FP or out-of-scope item |

---

## 2. Confirming the wrapped module's exact interface (from source, not memory)

Commands run (in a throwaway `.probe/` dir, later deleted; repeated in the real root):

```bash
# pin + download
terraform init -backend=false      # installed aws v6.50.0, random v3.9.0; module under .terraform/modules/elasticache
# read the REAL interface
cat   .terraform/modules/elasticache/versions.tf       # floors: tf >=1.0, aws >=5.93, random >=3.0
read  .terraform/modules/elasticache/variables.tf      # exact input names + types + defaults
grep  -nE 'auth_token|transit_encryption|at_rest|kms_key|automatic_failover|multi_az|log_delivery|num_cache_clusters' \
      .terraform/modules/elasticache/main.tf           # how each input is wired onto the resource
grep  -nE 'output "' .terraform/modules/elasticache/outputs.tf
terraform providers schema -json                        # to inspect write-only attributes (see §3)
```

Key facts that drove authoring (and would have caused rework if guessed):
- The module wires `auth_token = var.auth_token` directly onto `aws_elasticache_replication_group`
  (a **non-write-only** argument) — it does **not** expose `auth_token_wo`.
- `kms_key_id = var.at_rest_encryption_enabled ? var.kms_key_arn : null`.
- `automatic_failover_enabled = var.multi_az_enabled || var.cluster_mode_enabled ? true : var.automatic_failover_enabled`.
- `log_delivery_configuration` is `type = any`; the module auto-creates the CloudWatch log group
  (`/aws/elasticache/<id>`) and accepts `cloudwatch_log_group_kms_key_id`.
- Security-group rules use the **`aws_vpc_security_group_ingress_rule`** shape: key `ip_protocol`
  (not `protocol`) and a **single** `cidr_ipv4` string per rule (not a list). My first draft used
  `protocol`/list → corrected to a per-CIDR map built in `locals.tf` **before** any test run.
- The `cloudwatch_log_group_name` output is `try(...this[0]...)` but the log group is `for_each`-keyed
  (a map), so `[0]` returns null → I derive the slow-log group from the `cloudwatch_log_groups` map
  output instead.

---

## 3. The write-only AUTH token — implementation + how tests handle it

**Requirement:** the AUTH token must never be stored in Terraform state.

**Constraint discovered (hard evidence, not memory):**
- `terraform providers schema -json` for aws 6.50.0 shows **no `write_only` flag** on any
  `aws_elasticache_replication_group` auth attribute.
- A throwaway probe assigning an ephemeral var to `auth_token` produced:
  ```
  Error: Ephemeral values are not valid for "auth_token", because it is not a
  write-only attribute and must be persisted to state.
  ```
- The provider feature request for `auth_token_wo` is open/unimplemented
  (hashicorp/terraform-provider-aws #42239).
- By contrast, `aws_secretsmanager_secret_version.secret_string_wo` **is** write-only
  (`write_only = true` in the schema).

**Implementation chosen:**
1. `variable "auth_token_wo"` declared `ephemeral = true` (omitted from state/plan by design), with a
   length validation (`length()` works on ephemeral values; the literal is never persisted), plus
   `auth_token_wo_version` to drive version-based rotation.
2. `aws_secretsmanager_secret_version.auth_token` persists it **only** via `secret_string_wo` +
   `secret_string_wo_version` — the one write-only sink available. Secret is CMK-encrypted.
3. The wrapped module is called with `auth_token = null` — the token is deliberately **not** routed
   through the RG resource (which would leak it to state). Binding the token to the live cluster is a
   one-line documented post-apply `aws elasticache modify-replication-group` step until the provider
   ships `auth_token_wo`. (Documented in README + DESIGN §8.)

**How the tests handle it:**
- All runs use `command = plan`. Reason: `auth_token_wo` is ephemeral, and under `command = apply`
  the test harness errors *"ephemeral variable … was not set during the plan phase"* (ephemeral values
  don't survive plan→apply in a test). Plan is sufficient for every assertion here.
- Ephemeral variables **can** be set in a test `variables {}` block, so the suite supplies a token.
- Assertions prove the write-only property without reading the secret value: `secret_string == null`
  (the state-persisted field is unused), `secret_string_wo_version == var.auth_token_wo_version`, and a
  length-validation run (`auth_token_too_short_rejected`) confirms the guard.

---

## 4. The Multi-AZ cost warning — implementation + interaction with `terraform test`

**Implementation:** `check "multi_az_cost_warning"` in `checks.tf`, asserting
`local.multi_az_enabled != true`. Since Multi-AZ is hardcoded ON, the assertion fails → in real
`plan`/`apply` a failed `check` only **warns**, surfacing the cost note to consumers (verified: the
warning text renders in test output).

**Interaction with `terraform test` (the gotcha the skill warned about):** under the test harness a
failed `check` is a **run failure**, not a warning. Because Multi-AZ is always ON, the check fires in
**every** run. Resolution (per the skill's verification-pipeline guidance):
- Every functional run declares `expect_failures = [check.multi_az_cost_warning]` — turning the
  expected warning into a passing expectation.
- A dedicated run `cost_warning_fires_when_multi_az_on` exists purely to **prove** the warning fires
  (it would error with "missing expected failure" if the warning ever stopped firing — regression net).
- Validation runs (short token / too-few-subnets / bad environment) trip the check **as well as** the
  variable validation, because `expect_failures` does not halt plan evaluation — so those runs list
  **both** the `var.X` and `check.multi_az_cost_warning` expected failures.

---

## 5. Verification pipeline — real results and fix/rerun cycles

Final clean run of every stage (from the module root):

| Stage | Command | Result | Fix/rerun cycles |
|---|---|---|---|
| fmt | `terraform fmt -check -recursive` | **CLEAN** (exit 0) | 0 (1 auto-format applied during dev) |
| validate | `terraform validate` | **Success! The configuration is valid.** | 0 |
| tflint | `tflint` (root) + `tflint --chdir=examples/minimal` | **CLEAN** (exit 0, both) | 0 |
| test | `terraform test` | **10 passed, 0 failed** (2 files) | **2** (see below) |
| checkov | `checkov -d examples/minimal --config-file .checkov.yaml` | **43 passed, 0 failed, 5 skipped** | **1** (see below) |

### `terraform test` fix-cycles (2)
- **Cycle 1 — "Unknown condition value":** an assertion compared a computed wrapped-module output
  (`module.elasticache.replication_group_id != ""`) and a computed KMS ARN
  (`secret.kms_key_id == kms_key.arn`) under `command = plan`. Both are unknown until apply. Removed
  the wrapped-output assertion and re-pointed the secret assertion at plan-known fields
  (`secret_string == null`, `secret_string_wo_version`, secret name).
- **Cycle 2 — validation runs failing on the cost check:** the variable-validation runs also tripped
  `check.multi_az_cost_warning` (expect_failures doesn't halt the plan). Added
  `check.multi_az_cost_warning` to those runs' `expect_failures`. → **10/10 green.**

(Intermediate progressions observed: `0 passed/1 failed/5 skipped` → `3 passed/1 failed/2 skipped` →
`6 passed/0 failed` → adding the validations file `7 passed/1 failed/2 skipped` → `10 passed/0 failed`.)

### `checkov` fix-cycles (1)
First pass: **43 passed, 5 failed**. The 5 failures were all known false-positives / out-of-scope:
- `CKV_AWS_111`, `CKV_AWS_356`, `CKV_AWS_109` on `aws_iam_policy_document.kms` — a KMS **key policy**
  always scopes its resource to the key itself (`"*"` == this key); constraining it is N/A. Inline
  `#checkov:skip` with reasons.
- `CKV_TF_1` (commit-hash module source) — registry modules pin by **exact version** (`1.11.0`);
  `CKV_TF_2` (version tag) passes. Inline skip.
- `CKV2_AWS_57` (Secrets Manager auto-rotation) — Redis AUTH rotation needs a coordinated cluster-side
  `modify-replication-group`; out of scope for a generic rotation lambda. Inline skip.
After adding scoped inline skips (+ a documented `.checkov.yaml`): **43 passed, 0 failed, 5 skipped.**

**ElastiCache security controls all PASS in checkov** (no suppression):
`CKV_AWS_29` at-rest, `CKV_AWS_30` in-transit, `CKV_AWS_31` transit+auth, `CKV_AWS_191` CMK,
`CKV2_AWS_50` Multi-AZ failover, `CKV_AWS_322` auto-minor-upgrade, `CKV_AWS_323` no default subnet
group, plus `CKV_AWS_7` KMS rotation, `CKV_AWS_149` secret CMK encryption, `CKV2_AWS_64` KMS policy.

---

## 6. Deliverables produced (all local, no git)

```
.checkov.yaml          .tflint.hcl
versions.tf  variables.tf  locals.tf  main.tf  kms.tf  secrets.tf  checks.tf  outputs.tf
README.md              docs/DESIGN.md (durable steering/design record)
examples/minimal/main.tf
tests/elasticache_redis.tftest.hcl   tests/validations.tftest.hcl
BUILD_LOG.md (this file)
```

## 7. Git confirmation

No `git init/add/commit/push/branch/tag` (or any other git command) was run. The output directory is
not a git repository (`git rev-parse` → "not a git repository"). The `.git` directory that appears
under `examples/minimal/.external_modules/...` is checkov's own vendored download of the upstream
module, not a repository created by this build.
