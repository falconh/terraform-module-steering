# Fixture: terraform-module-aws-s3-legacy

A deliberately **imperfect but working** S3 module. It is the target for the brownfield
eval (`eval-2`) — the steering skill's Path B flow should assess it, find the CIS/FSBP
gaps, and close them **without breaking the existing interface**.

This is a fixture, not a recommended module. Do not use it in production.

## Starting state (verified)

- `terraform fmt` clean, `terraform validate` succeeds.
- `terraform test` → **2 passed / 0 failed** (`tests/legacy.tftest.hcl`). A correct
  brownfield change must keep these green.
- `checkov` → **10 passed / 5 failed**. The failures are the gaps to close.

## Deliberate gaps (what a correct hardening pass should fix)

| Gap | Control | How it shows up |
|-----|---------|-----------------|
| Encryption optional + SSE-S3 (not CMK) | CKV_AWS_145 / FSBP | `encryption_enabled` toggle, `AES256` |
| No default-encryption enforcement | CKV_AWS_19 | encryption can be turned off |
| No server access logging | CKV_AWS_18 / CIS | absent |
| No TLS-only bucket policy | FSBP S3.5 | no `aws:SecureTransport=false` deny |
| Public-access block is weakenable | FSBP S3.1 | driven by `block_public_access` var |
| No lifecycle configuration | — | absent |

## Backward-compatibility traps (the point of the eval)

- `encryption_enabled` and `block_public_access` are **public variables**. Hardcoding
  these controls removes the variables → a breaking change unless handled with the
  soft path (keep the variable, validate it to reject insecure values).
- Adding required inputs would break consumers — new inputs must be optional with safe
  defaults.
- Switching encryption to a CMK mutates a live resource — the change must call out the
  operational impact.
