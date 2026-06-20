# Steering Document — `terraform-module-aws-s3` (worked example)

> A filled example showing the level of detail the steering doc should reach. Based on a real
> secure-by-default S3 module. Use it as a reference for shape, not as a fixed template.

## 1. Identity
- **Module name:** `terraform-module-aws-s3`
- **Provider / service:** AWS / S3
- **Purpose:** A secure-by-default S3 bucket that satisfies mandatory CIS + AWS FSBP S3 controls with a minimal interface.
- **Target environments:** dev / test / staging / prod

## 2. Reuse decision
- **Wrap or scratch:** Wrap `terraform-aws-modules/s3-bucket/aws` pinned `v5.14.0`.
- **Why:** It already exposes every input needed for the controls (public-access block, SSE, versioning, logging, ownership, TLS policy), so wrapping inherits its maintenance and lets us hardcode security by passing literals and exposing no override variables.
- **Version floor:** terraform `>= 1.6`; aws provider `>= 6.42` (matches upstream v5.14.0).

## 3. Consumer interface
- **Required inputs:** `name`, `environment` (validated to dev/test/staging/prod).
- **Optional inputs (safe defaults):** `tags = {}`; `log_bucket_name = null` (→ auto-create companion log bucket); `force_destroy = false`.
- **NOT exposed (hardcoded):** encryption (KMS), all four public-access-block flags, object ownership, versioning, TLS-only policy, access logging — none are variables.
- **Outputs:** `bucket_id`, `bucket_arn`, `bucket_domain_name`, `kms_key_arn`, `kms_key_alias`, `log_bucket_id`, `log_bucket_arn`.
- **Provider config:** module does NOT configure the aws provider.

## 4. Security controls (researched, proposed, negotiated)
Benchmarks: CIS AWS Foundations Benchmark + AWS FSBP.

| Control | Intent | Enforcement (hardcoded) | Decision | Justification |
|---|---|---|---|---|
| CIS 2.1.1 / FSBP S3.4, S3.17 | Encrypt at rest (KMS) | SSE-KMS, module-managed CMK + bucket key | kept | data protection |
| CIS 2.1.2 / FSBP S3.5 | Deny non-TLS | `attach_deny_insecure_transport_policy=true` + require-latest-TLS | kept | in-transit protection |
| CIS 2.1.4-5 / FSBP S3.2,S3.3,S3.8 | Block public access | all four PAB flags `true` | kept | prevent exposure |
| FSBP S3.12 | Disable ACLs | `object_ownership="BucketOwnerEnforced"` | kept | modern access model |
| FSBP S3.14 | Versioning | `versioning={enabled=true}` | kept | recoverability |
| FSBP S3.9 | Access logging | log to companion/supplied bucket | kept | auditability |
| FSBP S3.1 | Account-level BPA | — | removed | account-wide, not per-bucket — documented as a recommendation |

_Custom benchmarks: none. MFA-Delete noted as not settable via the Terraform/AWS API._

## 5. Conventions
- Files: `versions.tf`, `variables.tf`, `main.tf`, `kms.tf`, `logging.tf`, `outputs.tf`.
- Mandatory tags merged over consumer tags. Exact module version pin; provider version floor.

## 6. Verification pipeline (definition of done)
fmt-check → validate → tflint → `terraform test` (mock_provider) → checkov (with documented
`.checkov.yaml` suppressions for separate-resource false positives). Done = all green with evidence.

## 7. Examples, tests & documentation
- `examples/minimal/` — `name` + `environment` only.
- `tests/*.tftest.hcl` — assert KMS rotation, the companion-log-bucket conditional, and outputs.
- `README.md` — usage + a "Security controls enforced" table (all hardcoded / non-overridable).
- `docs/DESIGN.md` — this steering doc preserved as the durable design record.

## 8. Out of scope
Account-level BPA (S3.1), MFA-Delete (not API-settable), replication, lifecycle tiering beyond log
expiry, event notifications.

## 9. Hard rules
Security = hardcoded literals, not variables. No git operations performed while building.
