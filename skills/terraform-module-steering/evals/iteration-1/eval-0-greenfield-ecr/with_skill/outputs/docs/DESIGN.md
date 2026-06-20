# Steering Document — `terraform-module-aws-ecr`

> Durable design record (steering doc) preserved with the module. This is the binding context for
> the build: interface, reuse decision, researched security controls, conventions, and the
> verification bar. Mirrored by the consumer-facing `README.md`.

## 1. Identity
- **Module name:** `terraform-module-aws-ecr`
- **Provider / service:** AWS / Elastic Container Registry (ECR) — private repository
- **Purpose (one line):** A secure-by-default Amazon ECR **private** repository that satisfies the
  mandatory CIS / AWS FSBP ECR controls (image scanning, tag immutability, lifecycle policy,
  customer-managed KMS encryption, TLS-only access) with a minimal consumer interface.
- **Target environments:** dev / test / staging / prod

## 2. Reuse decision
- **Wrap or scratch:** **Wrap** `terraform-aws-modules/ecr/aws` pinned **`v3.2.0`** (exact pin).
- **Why:** The upstream module exposes every input needed for the ECR controls (scan-on-push,
  tag mutability, encryption type + KMS key, repository policy, lifecycle policy). Wrapping inherits
  its maintenance and lets us hardcode security by passing literals and exposing no override variable.
- **Provider + Terraform version floor:** `terraform >= 1.5.7`, `aws >= 6.28` — **confirmed against the
  downloaded upstream `versions.tf`** (`.terraform/modules/ecr/versions.tf`), which declares
  `required_version >= 1.5.7` and `aws >= 6.28`. Both are floors (`>=`), no upper bound, so the latest
  Terraform satisfies them. Latest stable Terraform identified: **v1.15.6** (checkpoint API). Installed
  toolchain is v1.15.6 → already latest; the module's declared floor stays at the upstream `>= 1.5.7` so
  consumers are not forced onto the latest.
- **Upstream interface — confirmed from source (not memory):** ran `terraform init -backend=false` on a
  throwaway harness, then read `.terraform/modules/ecr/variables.tf`, `outputs.tf`, `versions.tf`, and the
  `aws_ecr_repository` / `aws_ecr_lifecycle_policy` / `aws_ecr_repository_policy` resource blocks in
  `main.tf`. Confirmed exact input names and wiring:
  - `repository_encryption_type` (string, default `null`) → `encryption_configuration.encryption_type`
  - `repository_kms_key` (string, default `null`) → `encryption_configuration.kms_key`
  - `repository_image_scan_on_push` (bool, default `true`) → `image_scanning_configuration.scan_on_push`
  - `repository_image_tag_mutability` (string, default `IMMUTABLE`) → `image_tag_mutability`
  - `create_lifecycle_policy` (bool, default `true`) + `repository_lifecycle_policy` (string) → `aws_ecr_lifecycle_policy.policy`
  - `attach_repository_policy` / `create_repository_policy` / `repository_policy` → `aws_ecr_repository_policy.policy`
    (when `create_repository_policy = false`, the module applies `var.repository_policy` verbatim)
  - `repository_type` (default `private`), `repository_name`, `repository_force_delete`, `tags`
  - Outputs: `repository_name`, `repository_arn`, `repository_registry_id`, `repository_url`.

## 3. Consumer interface (minimise inputs)
- **Required inputs:** `name` (repository name), `environment` (validated to dev/test/staging/prod).
- **Optional inputs (safe defaults):**
  - `tags = {}` — merged **under** mandatory tags (consumer cannot drop the mandatory ones).
  - `force_delete = false` — safe default; lets a consumer opt into deleting a non-empty repo.
  - `lifecycle_keep_last_count = 30` — retention count for the (mandatory) lifecycle policy; ECR.3 is
    satisfied regardless of the value, so exposing the count does not weaken the control.
  - `additional_read_access_arns = []` — IAM principals granted pull (read) access via the repo policy.
  - `additional_read_write_access_arns = []` — IAM principals granted push/pull access.
- **NOT exposed (hardcoded literals — the non-overridable guarantee):**
  - Encryption type (`KMS`) and use of a module-managed customer-managed CMK — **ECR.5**.
  - `scan_on_push = true` — **ECR.1**.
  - `image_tag_mutability = "IMMUTABLE"` — **ECR.2**.
  - Presence of a lifecycle policy (`create_lifecycle_policy = true`) — **ECR.3**.
  - TLS-only (deny non-`aws:SecureTransport`) repository policy statement — defense-in-depth.
  - KMS key rotation enabled; `repository_type = "private"`.
- **Outputs:** `repository_arn`, `repository_name`, `repository_url`, `repository_registry_id`,
  `kms_key_arn`, `kms_key_id`, `kms_key_alias_arn`.
- **Provider config:** the module does **NOT** configure the aws provider; the consumer owns region/creds.

## 4. Security controls (researched, proposed, negotiated)
Benchmarks: **CIS AWS Foundations Benchmark + AWS Foundational Security Best Practices (FSBP)**.
Source: AWS Security Hub "Controls for Amazon ECR" (ECR.1–ECR.5).

| Control (id) | Intent | Enforcement (hardcoded literal) | applies? | Decision | Justification |
|---|---|---|---|---|---|
| FSBP **ECR.1** | Identify image vulnerabilities — scan on push | `repository_image_scan_on_push = true` | yes | kept | basic image scanning, non-overridable |
| FSBP **ECR.2** | Immutable tags — a tag always maps to one image | `repository_image_tag_mutability = "IMMUTABLE"` | yes | kept | prevents tag overwrite / supply-chain tampering |
| FSBP **ECR.3** | At least one lifecycle policy (avoid stale images) | `create_lifecycle_policy = true` + JSON keeping last N images | yes | kept | automated cleanup; ECR.3 needs a policy to exist |
| FSBP **ECR.5** | Encrypt at rest with a **customer-managed** KMS key | module-managed `aws_kms_key` (rotation on) + `encryption_type = "KMS"` + `repository_kms_key = <cmk arn>` | yes | kept | data-at-rest protection under a key the account controls |
| CIS (general, in-transit) | Deny non-TLS access | repo policy statement: `Deny` when `aws:SecureTransport = false` | yes | added | defense-in-depth; ECR pull/push is HTTPS but the policy makes it explicit & non-bypassable |
| FSBP **ECR.4** | Public repositories should be tagged | — | no | removed | applies to **public** repos; this module is private-only (out of scope) |
| Registry-level enhanced scanning (Inspector) | Continuous CVE scanning across the registry | — | n/a | removed | account/registry-wide setting, not per-repository; documented as a recommendation in §8 |

_Custom benchmarks: none requested. No control removed without a reason._

## 5. Conventions
- **Files:** `versions.tf`, `variables.tf`, `locals.tf` (effective values + JSON policies — pure
  expressions), `kms.tf` (real CMK + alias resources), `main.tf` (the wrapped module call), `outputs.tf`.
  No empty topic files: lifecycle/repo-policy JSON live in `locals.tf` because they are pure expressions
  passed to the upstream module (no owned resources of their own).
- **Block ordering:** resource → `count`/`for_each` first, then args, then `tags`, then `lifecycle`.
  Variables → description → type → default → validation.
- **Version pinning:** upstream module pinned to exact `v3.2.0`; provider declared as a floor (`>= 6.28`).
- **Tagging:** mandatory tags (`ManagedBy=terraform`, `Module=terraform-module-aws-ecr`,
  `Environment=<environment>`) merged **over** consumer `tags` so a consumer cannot drop or override them.

## 6. Verification pipeline (definition of done)
`terraform fmt -check -recursive` → `terraform validate` → `tflint` → `terraform test` (native,
`mock_provider`, no creds) → `checkov -d examples/minimal` (with documented suppressions for
static-scan false positives on the wrapped module's separate `count`-indexed resources, and the
`CKV_TF_1` commit-hash check which is wrong for a version-pinned registry module). Done = all green,
with evidence.

## 7. Examples, tests & documentation to include
- `examples/minimal/` — `name` + `environment` only; doubles as the checkov fixture.
- `tests/*.tftest.hcl` — assert the hardcoded controls the module owns: KMS key + rotation, the
  encryption/scanning/mutability literals passed to the wrap, the lifecycle policy presence, the TLS-deny
  statement, mandatory-tag merge precedence, and `environment` validation.
- `README.md` — consumer docs incl. a **Security controls enforced** table (all hardcoded / non-overridable).
- `docs/DESIGN.md` — this steering doc (durable design record).

## 8. Out of scope / limitations
- **Public ECR repositories** (`aws_ecrpublic_repository`) and ECR.4 — private-only module.
- **Registry-level enhanced scanning** (Amazon Inspector continuous scanning) and registry replication /
  pull-through cache — these are account/registry-wide, not per-repository. Recommended separately.
- **Repository policy beyond TLS-deny + the optional read/read-write grants** — full custom policy
  authoring is deferred; the module hardcodes the TLS-deny guardrail and exposes only ARN-list grants.
- KMS key deletion window is set to a safe 30 days; cross-region replication of images is not configured.

## 9. Hard rules
- Security controls are **hardcoded literals, not variables**.
- **No git operations** are performed while building from this document.

---
### Fork decisions made automatically (no human in the loop)
1. **Mode:** greenfield (Path A) — no existing module named. 
2. **Reuse:** wrap `terraform-aws-modules/ecr/aws v3.2.0` (the proven community module) rather than
   building `aws_ecr_repository` from scratch.
3. **Scope:** private repository only (the dominant ECR use case); public repos / ECR.4 excluded.
4. **Encryption:** create a module-managed CMK (rotation on) to satisfy ECR.5's *customer-managed* key
   requirement, rather than the AWS-managed `aws/ecr` key (which would fail ECR.5).
5. **Lifecycle retention default:** keep last 30 images (`lifecycle_keep_last_count = 30`), tunable but
   always present so ECR.3 holds.
6. **TLS-deny:** added as defense-in-depth beyond the FSBP set.
7. **Runtime fork:** continued straight into build+verify (automated eval requires a complete build).
</content>
