# Brownfield mode — changing an existing module safely

Use this when the creator wants to **improve, extend, add a feature to, harden, or audit** a module
that already exists. The greenfield engine (per-service security research, minimal inputs, hardcoded
security, verification pipeline, no git) still applies — brownfield adds three things greenfield never
needs: **assessment, gap-diff, and backward-compatibility discipline.**

The prime directive: **do no harm to existing consumers.** A module is an API. People depend on its
inputs, outputs, and behaviour. Default to additive, non-breaking change.

## A. Assess the existing module (read, don't touch)

Locate the module (the creator names a path/repo). Read and record — change nothing yet:

- **Interface:** every variable (name, type, default, whether validated) and every output.
- **Controls already enforced:** which security settings are set, and *how* — hardcoded literal,
  variable-with-default, or absent. Note any security setting currently exposed as a variable (that is
  itself a gap: it can be weakened).
- **Structure & conventions:** file layout, wrap-vs-scratch, version pins, provider floors.
- **Tests & examples:** what `tests/*.tftest.hcl` and `examples/` already cover.
- **Current version:** from CHANGELOG/tags/registry, to anchor the next semver. If the module carries
  no version anywhere, treat it as `0.1.0` and say so.
- **Before-state pipeline snapshot:** run the pipeline on the *unchanged* module first
  (`scripts/verify.sh`) and record the numbers — the `terraform test` count and the checkov
  passed/failed tally. That is your baseline: the change must keep every existing test green and reduce
  checkov failures, and you can only *prove* that against the before-state.

Use `code-intelligence`/`rg` to navigate. Produce a short "current state" snapshot.

> If the change includes **bumping a wrapped upstream module or provider pin**, re-confirm the *new*
> version's interface from its downloaded source (`.terraform/modules/...`) — a bump can silently rename
> or restructure inputs/outputs, which is a **breaking change** to surface, not absorb. See
> [wrapping-upstream-modules.md](wrapping-upstream-modules.md).

## B. Gap-diff + capture the feature

1. Research the service's CIS + provider controls exactly as greenfield does
   ([security-research.md](security-research.md)).
2. **Diff against the current state** → the set of controls the module does NOT yet enforce (gaps),
   and any control currently weakenable (exposed as a variable) that should become a hardcoded literal.
3. Capture the creator's requested **new feature(s)** precisely.
4. Note convention drift worth fixing *only if it serves the goal* — don't scope-creep an unrelated
   rewrite (surgical changes).

## C. Propose the change set + negotiate

Present three buckets: **new feature(s)**, **security gaps to close**, **convention fixes**. The creator
adds/removes with a documented reason and may add custom benchmarks. Record every decision.

If the change would **introduce, swap, or drop a wrapped base module** (start wrapping where the module
was scratch, move to a different upstream, or drop the wrapper), treat that like greenfield reuse:
present the candidate and let the creator choose — use it, supply their own preferred module, or stay
as-is. It's a foundational decision, and a base swap is itself a breaking change (see §D).

## D. Backward-compatibility analysis (the part greenfield doesn't have)

Classify EVERY proposed change. This drives the semver bump and the migration note.

| Change | Class | Default handling |
|---|---|---|
| New **optional** input (with default), new output, new internal resource, a new hardcoded control that doesn't touch the existing interface | **Additive — safe** | minor (feature) / patch (fix) |
| New **required** input, or optional→required | **Breaking** | major + migration; prefer giving it a safe default instead |
| Remove or rename an input/output | **Breaking** | major + migration; prefer deprecate-then-remove |
| Change a default value so existing behaviour changes | **Breaking (behavioural)** | major + call out the operational impact |
| Hardcoding a control that was a **variable** (removes the variable) | **Breaking** | major; OR keep the variable but validate it to reject insecure values (soft path) |
| Change that alters resource addresses (`count`→`for_each`, renames, new wrapper) | **Breaking (state churn)** | major + `moved {}` blocks so consumers don't see destroy/recreate |
| Raise the declared `required_version` or provider floor (e.g. to adopt the latest Terraform) | **Breaking (consumer toolchain)** | major + note; recommend latest for *your* dev/CI toolchain without forcing it on consumers unless justified |

Special care when **closing a security gap on a live resource** (e.g. now enforcing encryption, or
switching to a CMK): applying it may **replace or mutate real infrastructure**. Say so plainly —
which resources change, whether it forces replacement, and whether state moves / data handling are
needed. The creator must accept that operational impact knowingly.

Bias order: **additive default → soft-deprecation → major bump**. Reach for a breaking change only when
there's no safe path, and always with justification.

## E. Write the delta steering document

Fill [change-steering-template.md](change-steering-template.md): current state → target state → the
delta table (each row classified additive/breaking) → the semver decision + migration notes →
verification delta. This is the deliverable.

## F. Runtime fork → optional superpowers handoff

Same fork as greenfield (stop, or continue). If continuing, the build is a feature-add/refactor:
- **TDD:** write a failing `terraform test` for the new feature and for each closed gap first; ensure
  the **existing** tests still pass throughout; then implement.
- **"Keep existing tests green" is not "never touch the test files".** A new hardening resource that
  validates its input as JSON (a KMS key policy, a TLS bucket policy) can make a bare
  `mock_provider "aws" {}` in an existing test fail. Updating that test's `mock_data` *defaults* (not
  its `run`/`assert` blocks) to satisfy the new resource is a permitted, expected part of keeping the
  suite green — see the mock defaults in [verification-pipeline.md](verification-pipeline.md).
- Add `moved {}` blocks for any address churn; verify with the full pipeline
  ([verification-pipeline.md](verification-pipeline.md)).
- Still **no git operations** — leave the version bump/changelog/commit to the creator (you only state
  the recommended new version in the doc).
