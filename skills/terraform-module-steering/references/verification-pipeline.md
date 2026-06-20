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

Scan the **example** (`-d examples/minimal`), which instantiates the module with real inputs — not the
bare module root with `checkov -d .`, which also scans anything cached under `.terraform/` (the
downloaded provider/module) and inflates the counts with findings you don't own.

## `terraform test` with mock_provider (no credentials)

Choose the run mode deliberately:
- **`command = plan`** — when you assert on inputs, locals, outputs, or conditional resource *counts*.
  Faster, and it avoids the apply-only pitfalls below.
- **`command = apply`** — only when an assertion needs a **computed** or **set-type** value (e.g. a
  created key's rotation flag, or set/dynamic blocks that can't be indexed `[0]` under plan).
- If the module declares an **`ephemeral`** (write-only) variable — e.g. a `password_wo` — then
  `command = apply` fails with *"ephemeral variable … was not set during the plan phase"* because
  ephemeral values don't carry plan→apply in a test. Use `command = plan` for those runs — which means
  you **cannot assert on computed values** in them (computed attributes are unknown under plan); assert
  only on plan-known inputs/locals/config. And "write-only" is a *resource capability*, not a given:
  before promising it, check the provider schema (`terraform providers schema -json`) for a `write_only`
  attribute. Many resources have none (e.g. an ElastiCache replication group's `auth_token`); the
  portable path is to route the secret into Secrets Manager (`secret_string_wo`) and associate it
  out-of-band, not pass it to the resource.

Mock the data sources whose output is **format-validated** downstream, or the upstream module errors on
mock junk. Two that bite almost every AWS wrap:

```hcl
mock_provider "aws" {
  # A non-JSON stub fails any resource that validates a policy as JSON (e.g. aws_kms_key.policy).
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  # A random partition makes IAM policy ARNs ("arn:${partition}:iam::aws:policy/…") fail ARN validation.
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  # Same idea for any data source whose value is parsed/validated (engine/version lookups, regions, …):
  # give it a realistic default rather than letting the mock invent one.
}
```

Assert on what the module *owns* (a created key's rotation flag, conditional resource counts,
outputs). Asserting on attributes deep inside a wrapped upstream module is brittle — leave those to
checkov. In particular, **a wrapped module does not expose its inputs back as outputs**: you cannot
read the literals you passed via `module.<name>.<input>` (only its declared outputs exist), so the
hardcoded security values you set can't be asserted that way. Verify those via checkov on the planned
resource, or add an explicit pass-through output to *your* module if a value must be assertable.

### Gotchas that will waste a build cycle if you don't know them
- **`check` block assertions are test *failures*, not warnings, under `terraform test`.** In real
  plan/apply a failed `check` only warns — but the test harness fails the run. So a module whose
  controls default ON, plus `check` blocks that warn when a (cost/safety) feature is enabled/disabled,
  fails *every* test. Handle it on purpose: in the shared `variables {}` set those toggles to their
  non-warning value so unrelated runs stay green, and add **dedicated** runs that flip each toggle with
  `expect_failures = [check.<name>]` — those runs *are* how you test that the warning fires. (This bites
  often, because the steering pattern itself favours `check`-block warnings.)
- **`expect_failures` does not halt the plan.** It records that a checkable object (a variable
  validation, a `check`) failed, but Terraform keeps evaluating — so an incomplete/skeleton config can
  throw an *unrelated* error that fails the run even though your expected failure also fired. Either
  finish enough of the config to plan cleanly, or read the skeleton error *as* your RED and move to GREEN.
- **A ternary evaluates BOTH branches.** `local.is_x ? module.a[0].out : module.b[0].out` errors when
  the non-selected module is `count = 0` (indexing an empty list). Use `one(module.a[*].out)` /
  `one(module.b[*].out)`, which yield the single element or `null`.
- **Guard variant lookups with a default.** A map keyed on a validated input
  (`{ "a" = …, "b" = … }[var.kind]`) hard-errors on an out-of-range key *before* the variable's
  validation message surfaces. Use `lookup(map, key, <safe-default>)` so the validation wins.

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

Two more sources of false failures specific to **wrapping registry modules**:
- **A `count`-gated wrap is scanned even when its `count = 0`.** If one input selects between two
  upstream modules (e.g. `deployment = "a" | "b"`), checkov statically scans *both* module bodies
  regardless of which is instantiated, so the un-selected branch's resources — often configured through
  `coalesce(each.value.x, var.<group>_x)` indirection it can't resolve — report failures. Confirm the
  control is actually wired in `.terraform/modules/...`, then suppress.
- **Registry-source / native-capability checks that don't apply.** A "use a commit hash for the module
  source" check (`CKV_TF_1`) is wrong for registry modules — you pin by *exact version*, which is the
  correct practice; and a check that demands a *managed* service (e.g. an AWS Backup plan) is out of
  scope when the module deliberately uses the resource's **native** capability (e.g. native automated
  backups + point-in-time recovery).

**KMS key-policy checks misfire on every module-managed CMK.** This skill's signature pattern is a
module-managed customer CMK, whose key policy *must* keep a root-admin statement and use
`Resource: "*"` (a key policy already scopes to the key it's attached to). checkov's IAM-identity
checks — `CKV_AWS_109` (no constraints), `CKV_AWS_111` (write without constraint), `CKV_AWS_356`
(`Resource: "*"`) — read that as over-broad and fail it. They are false positives on a *key* policy;
suppress them with that reason wherever you create a CMK.

### Suppress honestly, scoped tightly
- **Inline `#checkov:skip=<ID>:<reason>`** on resources *you* own (e.g. your KMS policy doc). This
  keeps the check active everywhere else. Prefer this — but it only works on resources defined in *your*
  files: a finding reported *through a module call* (the resource lives under `.terraform/modules/...`)
  cannot be annotated inline, so those have to go in the global `.checkov.yaml`.
- **Global `skip-check` in `.checkov.yaml`** ONLY for checks that fire on upstream-internal resources
  you cannot annotate. Document each with a reason. Example:

```yaml
download-external-modules: true
compact: true
skip-check:
  - CKV_AWS_19    # encryption -> aws_s3_bucket_server_side_encryption_configuration (false positive under static scan)
  - CKV_AWS_21    # versioning -> aws_s3_bucket_versioning (false positive under static scan)
  - CKV_AWS_144   # cross-region replication — out of CIS/FSBP scope for this module
  - CKV_TF_1      # registry modules pin by exact version, not a commit hash — not applicable
  - CKV_AWS_109   # KMS *key* policy must allow root admin — false positive (IAM-identity check on a key policy)
  - CKV_AWS_111   # KMS *key* policy "write without constraint" — false positive on a key policy
  - CKV_AWS_356   # KMS *key* policy Resource:"*" is correct (scopes to the key) — false positive
```

Never silently suppress a real control. Every skip is a documented false-positive or an explicit
out-of-scope decision recorded in the steering doc.

## Tooling notes
- Pass `config_file: .checkov.yaml` to the `bridgecrewio/checkov-action` in CI; without it the action
  ignores the documented suppressions and the compliance job fails.
- **Don't leave build artifacts in the module.** Verification downloads things: `.terraform/` and
  `.terraform.lock.hcl` (provider/module cache) and — easy to miss — `examples/minimal/.external_modules/`,
  a full git clone that `checkov --download-external-modules` writes, plus any `tfplan`. Delete these
  before the module is "done" (they are caches, not output).
- For a reusable module, do **not** commit `.terraform.lock.hcl` (it's for root configs) — but that's
  the creator's call; this skill performs no git operations regardless.
