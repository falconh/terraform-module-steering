# BUILD_LOG — terraform-module-aws-ecr

Greenfield build of a secure-by-default private Amazon ECR module, following the
`terraform-module-steering` skill (Path A). All work is local; **no git operations** were performed.

## Environment / tooling

- **Latest Terraform identified:** v1.15.6 is the latest **supported/stable** release (June 2026);
  v1.16.0 is only in alpha (`1.16.0-alpha`). Used the installed **Terraform v1.15.6** (`darwin_arm64`).
- Workspace check (`scripts/setup-workspace.sh`, report mode) result:
  - `terraform` v1.15.6 — ok
  - `tflint` 0.63.1 — ok
  - `checkov` 3.3.1 — ok
  - `terraform-docs` — MISSING (optional) → Inputs/Outputs tables hand-written in README.
  - `trivy` — MISSING (optional) → not required for the pipeline.
  - Required plugins (`terraform-skill@antonbabenko`, `context7`) — present.
- AWS provider resolved during init: **hashicorp/aws v6.50.0** (floor `>= 6.28`).

## Fork / default decisions (no human available — defaults chosen and noted)

1. **MODE = greenfield (Path A).** No existing module named → new module `terraform-module-aws-ecr`.
2. **Reuse = WRAP** `terraform-aws-modules/ecr/aws` pinned **`3.2.0`** (latest, Jan 2026). It exposes
   every input needed for the FSBP controls, so wrapping lets us hardcode security via literals.
3. **Repository type = private.** ECR.4 (public-repo tagging) is therefore N/A; documented as removed.
4. **Benchmark scope = AWS FSBP (ECR.1–ECR.5).** Research confirmed **CIS AWS Foundations has no
   ECR-specific controls**; FSBP is the per-service standard. Noted plainly per the skill's
   "little/no CIS posture" guidance.
5. **ECR.5 = customer-managed CMK** (not AES256 / not the AWS-managed `aws/ecr` key). Secure-by-default
   choice: a module-managed `aws_kms_key` with `enable_key_rotation = true`, 30-day deletion window,
   and a scoped key policy (account-root admin + ECR service use constrained by `kms:CallerAccount`).
6. **KMS key policy region scoping:** used `kms:CallerAccount` rather than the region-specific
   `kms:ViaService` (ecr.<region>.amazonaws.com), because the consumer owns the provider region and the
   module must not hardcode a region.
7. **Lifecycle policy (ECR.3):** *presence* is hardcoded (`create_lifecycle_policy = true` + non-empty
   policy); only the thresholds (`untagged_image_expiry_days`, `max_tagged_image_count`) are tunable
   inputs with safe defaults.
8. **Runtime fork = CONTINUE to a full build** (the task requires a complete implementation), rather
   than stopping at the steering doc.
9. **Docs:** Inputs/Outputs tables hand-written (terraform-docs not installed).

## How the wrapped module's input/output interface was confirmed (exactly)

Not from memory — confirmed against the real pinned source:

1. Created a throwaway probe (`_probe/main.tf`) referencing `terraform-aws-modules/ecr/aws` `version =
   "3.2.0"` and ran:
   `terraform -chdir=_probe init -backend=false`
   → downloaded the module to `_probe/.terraform/modules/ecr/`. The init log also revealed the provider
   floor (`>= 6.28.0`).
2. **Read the actual downloaded source files** (verbatim):
   - `.terraform/modules/ecr/versions.tf` → `required_version >= 1.5.7`, `aws >= 6.28`.
   - `.terraform/modules/ecr/variables.tf` → confirmed exact input names/types/defaults:
     `repository_type` (default `private`), `repository_name`, `repository_image_tag_mutability`
     (default `IMMUTABLE`), `repository_image_scan_on_push` (default `true`),
     `repository_encryption_type` (`KMS`/`AES256`), `repository_kms_key`, `create_lifecycle_policy`
     (default `true`), `repository_lifecycle_policy`, `repository_force_delete`, `tags`, etc.
   - `.terraform/modules/ecr/outputs.tf` → confirmed the exact outputs:
     `repository_name`, `repository_arn`, `repository_registry_id`, `repository_url`.
   - `.terraform/modules/ecr/main.tf` → confirmed how each input wires to the resource:
     `image_scanning_configuration.scan_on_push`, `image_tag_mutability`, the
     `encryption_configuration { encryption_type, kms_key }` block, and the separate
     `aws_ecr_lifecycle_policy` resource. Also confirmed the repo policy uses an
     `aws_iam_policy_document` (relevant for the mock_provider JSON default in tests).
3. The probe directory was deleted after reading; the module's interface is now also exercised live by
   `terraform init` + `terraform validate` + `terraform test` from the module root.

FSBP control source: AWS Security Hub "Security Hub CSPM controls for Amazon ECR" page (ECR.1 image
scanning, ECR.2 tag immutability, ECR.3 lifecycle policy, ECR.4 public-repo tagging, ECR.5 CMK
encryption).

## Verification pipeline — exact commands and REAL results

Run from the module root (`.../old_skill/outputs/`):

| # | Command | Result |
|---|---------|--------|
| 1 | `terraform fmt -check -recursive` | **PASS** (exit 0, no diff) |
| 2 | `terraform init -backend=false` | **PASS** (aws v6.50.0 installed, module 3.2.0 downloaded) |
| 3 | `terraform validate` | **PASS** — "Success! The configuration is valid." |
| 4 | `tflint --init && tflint --recursive` | **PASS** (exit 0, no findings; aws ruleset 0.45.0) |
| 5 | `terraform test` | **PASS — 10 passed, 0 failed** (2 files: defaults + validation) |
| 6 | `checkov -d examples/minimal --download-external-modules true --config-file .checkov.yaml` | **PASS — 27 passed, 0 failed, 3 skipped** (exit 0) |

### terraform test detail (10 runs, all pass)
- `defaults.tftest.hcl` (mock_provider, `command = apply`): kms_key_has_rotation_enabled,
  kms_alias_created, encryption_type_is_kms, mandatory_tags_enforced, lifecycle_policy_rendered.
- `validation.tftest.hcl` (`command = plan`): rejects_invalid_environment, rejects_invalid_name,
  rejects_out_of_range_untagged_expiry, rejects_out_of_range_image_count, valid_config_plans.
- mock_provider supplies `aws_iam_policy_document.json` = a valid empty IAM policy so the upstream
  repository-policy document and our KMS policy apply cleanly (the skill's documented gotcha).

### checkov detail — FSBP controls verified PASS on the real resources
With `download-external-modules true`, checkov follows the wrapper to the actual
`aws_ecr_repository.this` and confirms:
- **CKV_AWS_163** "ECR image scanning on push is enabled" → **PASSED** (FSBP ECR.1).
- **CKV_AWS_136** "ECR repositories are encrypted using KMS" → **PASSED** (FSBP ECR.5).
- KMS key checks on our CMK: **CKV_AWS_7** (rotation), **CKV_AWS_33** (no wildcard principal),
  **CKV_AWS_227** (enabled), **CKV2_AWS_64** (policy defined) → all **PASSED**.

### checkov — the 3 documented skips (honest, scoped)
The only initial failures were on our own KMS key-policy data source and the module version pin —
not on any FSBP ECR control. Each is suppressed with a recorded reason:
- **CKV_AWS_111 / CKV_AWS_356 / CKV_AWS_109** — inline `#checkov:skip` on
  `data.aws_iam_policy_document.kms` (kms.tf). These flag the mandatory `EnableRootPermissions`
  statement (`kms:*` on `"*"`), which is the AWS-required key-policy root grant scoped to the
  account-root principal; removing it can lock the account out of the key. True false positives.
- **CKV_TF_1** — global `skip-check` in `.checkov.yaml`: it demands a git commit-hash module source,
  which is incompatible with the skill-mandated registry **version-tag** pin (`3.2.0`); the
  complementary **CKV_TF_2** ("use a version tag") **passes**. Fires on the `module` block, which can't
  carry an inline skip the way a resource can. Documented out-of-scope/convention conflict.

## Git confirmation

**No git operations were performed at any point** — no `init`, `add`, `commit`, `branch`, `push`, or
`tag`. The module root is intentionally not a git repository (`git rev-parse` confirms
"not a git repository"). Version control is left entirely to the creator.

## Deliverables produced (local only)

```
terraform-module-aws-ecr-steering.md   # steering doc (Path A)
versions.tf  variables.tf  main.tf  kms.tf  outputs.tf
examples/minimal/main.tf               # smallest consumer + checkov fixture
tests/defaults.tftest.hcl              # control assertions (mock_provider)
tests/validation.tftest.hcl           # input-validation assertions
.tflint.hcl  .checkov.yaml             # tool configs
README.md                              # consumer docs + Security controls table
docs/DESIGN.md                         # steering doc preserved as durable design record
BUILD_LOG.md                           # this file
```
