# terraform-module-steering — evaluation results

Evidence that the skill produces complete, secure-by-default, verified Terraform modules — and a
**runnable** suite for testing the current state of the skill going forward.

## Baseline policy

**`master` is the baseline.** There is no frozen skill snapshot in the repo — to compare against a
past state, check out the skill at that point.

- **Testing the current state of the skill:** run `with_skill` (the skill on `master`) vs
  `without_skill` (no skill). Does the skill measurably improve the output?
- **Evaluating a new feature:** run the feature branch vs `master`. `master` is the thing your change
  must beat (and must not regress).

`iteration-1/` below is **historical**: it is the A/B that justified the change now living on `master`
(it compares the pre-change `old_skill` against `with_skill`). Keep it as the record of why master is
where it is; use the baseline policy above for anything new.

## How the evals work

Each run is a full autonomous build driven by the skill: research → steering doc → wrap upstream →
hardcode CIS/FSBP → `terraform fmt/validate` → `tflint` → `terraform test` (mock_provider) →
`checkov`. Grading is per-assertion pass/fail with cited evidence (see `evals.json` for assertions).
The deterministic pipeline stage is bundled as [`verify.sh`](verify.sh) so every run grades the same
way. See [`README.md`](README.md) for the step-by-step run procedure (standard skill-creator practice).

Tooling on the build host: Terraform 1.15.6, TFLint 0.63.1, checkov 3.3.1.

## Results — iteration-1 (historical)

| Eval | Mode | `old_skill` | `with_skill` | Verdict |
|------|------|-------------|--------------|---------|
| 0 — ECR | greenfield | test 10/0 · checkov 27/0/3 · 102.5k tok · 605s | test 10/0 · checkov 27/0/3 · 106.2k tok · 683s | **TIE** (no-regression check) |
| 1 — ElastiCache Redis | greenfield (gotchas) | test 5/0 · checkov 37/0/4 · 113.6k tok · 895s | test 10/0 · checkov 43/0/5 · 137.3k tok · 940s | **WIN** for `with_skill` |

`checkov` shown as passed/failed/skipped; skips are documented baseline/false-positive suppressions.
Single run per arm — qualitative differentiator checks, not a statistically powered benchmark.

### Eval 1 — ElastiCache Redis (the differentiator)

Engineered to hit the exact gotchas the change targets: a **write-only auth token** (ephemeral var,
never in state, tests use `command=plan`) and a **`check` block warning** that fails `terraform test`
unless anticipated with `expect_failures`. `old_skill` discovered the check-block problem **blind**
(first `terraform test` came back `0 passed / 1 failed`, then it diagnosed and fixed — that round-trip
is rework). `with_skill` **cited the gotcha up front** and landed **test 10/0 (vs 5/0)** and
**checkov 43/0/5 (vs 37/0/4)**. Both handled the write-only token correctly. See the two `BUILD_LOG.md`
files and `grading.json` for the cited evidence.

## Capability coverage

| Capability (from `SKILL.md`) | Covered by | Status |
|------------------------------|-----------|--------|
| Greenfield NEW module, wrap proven upstream | evals 0, 1 | ✅ |
| Interface built **from downloaded source**, not memory | evals 0, 1 | ✅ |
| Per-service CIS/FSBP research → hardcoded, non-overridable controls | evals 0, 1 | ✅ |
| Minimal consumer inputs | evals 0, 1 | ✅ |
| Verification pipeline (fmt/validate/tflint/terraform test/checkov) | evals 0, 1 · `verify.sh` | ✅ |
| Latest-Terraform identification + feasibility gate | evals 0, 1 | ✅ |
| Write-only / ephemeral secret handling (no state leak) | eval 1 | ✅ |
| `check`-block warning handled (warning fires AND tests green) | eval 1 | ✅ |
| Consumer README + durable design record (DESIGN/steering) | evals 0, 1 | ✅ |
| No git operations | evals 0, 1 | ✅ |
| **Brownfield CHANGE (Path B): assess → gap-diff → backward-compat → semver → `moved {}`** | **eval 2 (runnable, not yet run)** | ⚙️ ready |

## Eval 2 — brownfield (runnable; tests the current skill)

Path B is half the skill (`references/brownfield-mode.md`) and the greenfield runs never touch it.
Eval 2 closes that gap and is **self-contained and runnable** against the current `master` skill.

- **Target:** [`fixtures/terraform-module-aws-s3-legacy`](fixtures/terraform-module-aws-s3-legacy) — a
  valid, **green-but-imperfect** S3 module (verified: `terraform test` 2/0, `checkov` 10 passed /
  5 failed). It leaves real CIS/FSBP gaps (no access logging, encryption optional + SSE-S3 not CMK,
  no TLS-only policy) and exposes two security controls as **weakenable variables**
  (`encryption_enabled`, `block_public_access`) — so hardcoding them is a *breaking* change unless the
  soft path is used. That is the backward-compat trap the eval grades.
- **Task:** harden to CIS/FSBP **and** add one feature **without breaking consumers**.
- **Arms:** `without_skill` vs `with_skill` (the skill on `master`) — a **capability** axis.
- **Graded on** (see `evals.json`): assessed the existing interface; named the gaps incl. the
  weakenable vars; classified every change additive vs breaking; semver decision + migration note;
  `moved {}` for address churn; existing tests stay green; new tests for feature + gaps; called out
  live-resource operational impact; reached green; no git.
- **Run it:** see `README.md` → "Running an eval". Drop artifacts under
  `iteration-<N>/eval-2-brownfield-harden-legacy-s3/{without_skill,with_skill}/`.

## What is deliberately not in the repo

- `.terraform/` provider/module caches and any nested upstream `.git` (build noise, not evidence).
- A frozen baseline skill snapshot — superseded by the baseline policy (check out `master`).
- The empty `benchmark.json` / `benchmark.md` template stubs — superseded by this file.
- The description-triggering optimization run: every case reported a `0.0` trigger rate (broken
  harness artifact, no defensible conclusion).
- The standalone SNS build comparison: its baseline "discovered the on-disk skill … not a clean
  control".
