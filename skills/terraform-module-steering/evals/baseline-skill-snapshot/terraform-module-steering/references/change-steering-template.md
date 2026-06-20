# Change Steering Document — `terraform-module-<provider>-<service>` (existing module)

> For improving/extending/hardening an EXISTING module. Fill every section; delete _italic_ guidance.
> This is the binding context for the change — a spec-driven framework should produce the change from
> it without re-deciding anything. **No git operations** are performed; the version bump is a
> recommendation for the creator to apply.

## 1. Target & goal
- **Module (path):** _e.g. ./terraform-module-aws-s3_
- **Provider / service:** _AWS / S3_
- **Goal (one line):** _the feature to add / the hardening to apply / the audit requested_
- **Current version:** _e.g. 1.3.0_

## 2. Current state (assessed, not assumed)
- **Interface today:** _required + optional inputs; outputs (note any security setting exposed as a variable)_
- **Controls already enforced:** _list, and how (hardcoded / variable / absent)_
- **Structure / pins / tests:** _file layout, upstream + provider pins, what tests & examples cover_

## 3. Target state
- _One paragraph: what the module should do/enforce after this change._

## 4. The delta (change set)
_Buckets: new feature(s); security gaps to close; convention fixes. Every row classified._

| # | Change | Type (feature/gap/fix) | Enforcement / how | Back-compat class | Justification |
|---|---|---|---|---|---|
| 1 | _add `x`_ | feature | _new optional input default …_ | additive | _…_ |
| 2 | _enforce KMS at rest_ | gap (FSBP S3.x) | _hardcoded literal_ | _additive / breaking?_ | _…_ |

_Removed/declined items + reasons go here too. Custom benchmarks here._

## 5. Backward compatibility & versioning
- **Breaking changes:** _list, or "none"._
- **For each breaking change:** _migration note + `moved {}` blocks for address churn + the safe
  alternative considered._
- **Operational impact of closing gaps on live resources:** _what gets replaced/mutated; state moves;
  data handling._
- **Recommended next version (semver):** _patch (fix) / minor (additive feature) / major (breaking)._
  _(Recommendation only — the creator applies the bump + changelog + commit.)_

## 6. Verification delta (definition of done)
- **Existing tests must stay green.** _Name the ones touching changed behaviour._
- **New tests** _per [verification-pipeline.md]: assert the feature + each closed gap (mock_provider)._
- Re-run `fmt`/`validate`/`tflint`/`terraform test`/`checkov`. Done = all green, with evidence, and no
  unexplained regression vs. the pre-change baseline.
- **Update docs:** refresh `README.md` (inputs/outputs, and the Security-controls table if controls
  changed), update the design record (`docs/DESIGN.md`), and add a `CHANGELOG.md` entry with the
  recommended semver bump + any migration. (Content only — the creator commits.) See
  [module-documentation.md](module-documentation.md).

## 7. Hard rules
- Default to additive, non-breaking change; breaking changes need a reason + major bump + migration.
- New mandatory controls are **hardcoded literals, not variables**.
- **No git operations** performed while building from this document.
