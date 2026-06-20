# Verification pipeline — the definition of done

"Done" / "compliant" / "passing" requires **evidence from these commands**, not assertion. Run them
from the module root.

```bash
terraform fmt -check -recursive
terraform init -backend=false           # fetches upstream module + provider; no creds needed
terraform validate
tflint --init && tflint                 # provider ruleset from .tflint.hcl
terraform test                          # native tests (mock_provider) — no creds, no real resources
checkov -d examples/minimal --config-file .checkov.yaml --download-external-modules true
```

A module is done when fmt is clean, validate succeeds, tflint is clean, every `terraform test` run
passes, and checkov reports the in-scope security controls as passed (0 unexplained failures).

## `terraform test` with mock_provider (no credentials)

Use `command = apply` with a mocked provider so assertions can read computed and **set-type** values
(encryption rules, lifecycle, policy statements are set/dynamic blocks and cannot be indexed `[0]`
under `command = plan`).

Critical gotcha learned the hard way: a mocked `aws_iam_policy_document` returns a non-JSON stub, which
fails any resource that validates a policy as JSON (e.g. `aws_kms_key.policy`). Give it a valid default:

```hcl
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
```

Assert on what the module *owns* (a created KMS key's rotation flag, conditional resource counts,
outputs). Asserting on attributes deep inside a wrapped upstream module is brittle — leave those to
checkov.

## checkov false positives when wrapping `terraform-aws-modules`-style modules

These modules configure encryption/versioning/lifecycle as **separate, `count`-indexed resources
rendered through `dynamic` blocks**. checkov's static *directory* scan often can't link them back to
the bucket/resource, so it reports false failures (commonly seen: `CKV_AWS_19` encryption,
`CKV_AWS_21` versioning, `CKV_AWS_145` KMS, `CKV_AWS_300` abort-multipart). The controls ARE
configured — confirm by reading the downloaded module under `.terraform/modules/...`, and note that
they pass under **plan-based** scanning:

```bash
terraform plan -out=tfplan          # needs provider creds
terraform show -json tfplan | checkov -f -
```

### Suppress honestly, scoped tightly
- **Inline `#checkov:skip=<ID>:<reason>`** on resources *you* own (e.g. your KMS policy doc). This
  keeps the check active everywhere else. Prefer this.
- **Global `skip-check` in `.checkov.yaml`** ONLY for checks that fire on upstream-internal resources
  you cannot annotate. Document each with a reason. Example:

```yaml
download-external-modules: true
compact: true
skip-check:
  - CKV_AWS_19    # encryption -> aws_s3_bucket_server_side_encryption_configuration (false positive under static scan)
  - CKV_AWS_21    # versioning -> aws_s3_bucket_versioning (false positive under static scan)
  - CKV_AWS_144   # cross-region replication — out of CIS/FSBP scope for this module
```

Never silently suppress a real control. Every skip is a documented false-positive or an explicit
out-of-scope decision recorded in the steering doc.

## Tooling notes
- Pass `config_file: .checkov.yaml` to the `bridgecrewio/checkov-action` in CI; without it the action
  ignores the documented suppressions and the compliance job fails.
- For a reusable module, do **not** commit `.terraform.lock.hcl` (it's for root configs) — but that's
  the creator's call; this skill performs no git operations regardless.
