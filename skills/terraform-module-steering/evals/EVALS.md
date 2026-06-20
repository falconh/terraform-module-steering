# terraform-module-steering — evaluation results

Evidence that the skill produces complete, secure-by-default, verified Terraform modules, and that
the changes in it earn their keep. This is a small, hand-graded **A/B build eval**: the same prompt is
run end-to-end with the **pre-change skill** (`old_skill`, snapshot in
[`baseline-skill-snapshot/`](baseline-skill-snapshot/)) and with the **current skill** (`with_skill`),
and the two outputs are graded against explicit assertions.

Eval definitions and assertions live in [`evals.json`](evals.json). Raw per-arm artifacts (full
generated module source, `BUILD_LOG.md`, `docs/DESIGN.md`, consumer `README.md`, `tests/`,
`grading.json`, `timing.json`) live under [`iteration-1/`](iteration-1/). A styled side-by-side viewer
is in [`iteration-1/review.html`](iteration-1/review.html).

## Method

- **Configurations:** `old_skill` (skill at `origin/master`, pre-change) vs `with_skill` (current skill).
- **Each run** is a full autonomous build — no human in the loop — driven by the skill: research →
  steering doc → wrap upstream → hardcode CIS/FSBP → `terraform fmt/validate` → `tflint` →
  `terraform test` (mock_provider) → `checkov`. Every fork point took a recorded default (see each
  arm's `BUILD_LOG.md`).
- **Grading** is per-assertion pass/fail with cited evidence (`grading.json` in each arm).
- **Cost** is captured in `timing.json` (tokens, wall-clock, tool uses) — directional, single-run.
- **Model:** Terraform v1.15.6, TFLint 0.63.1, checkov 3.3.1 on the build host.

> Single run per arm — these are qualitative differentiator checks, not a statistically powered
> benchmark. (The repo previously carried `benchmark.json` / `benchmark.md`; those were empty template
> stubs — `<model-name>`, 0% pass, no runs — and were intentionally **not** merged. This file is the
> real record.)

## Results (iteration-1)

| Eval | Mode | `old_skill` | `with_skill` | Verdict |
|------|------|-------------|--------------|---------|
| 0 — ECR | greenfield | test 10/0 · checkov 27/0/3 · 102.5k tok · 605s | test 10/0 · checkov 27/0/3 · 106.2k tok · 683s | **TIE** (no-regression check) |
| 1 — ElastiCache Redis | greenfield (gotchas) | test 5/0 · checkov 37/0/4 · 113.6k tok · 895s | test 10/0 · checkov 43/0/5 · 137.3k tok · 940s | **WIN** for `with_skill` |

`checkov` shown as passed/failed/skipped; skips are documented baseline/false-positive suppressions.

### Eval 0 — ECR (no-regression)

A simple service, deliberately. Both arms reached green, built the interface from the downloaded
upstream source (not from memory), identified latest Terraform (v1.15.6), and produced no `.git`. The
point was to confirm the change **didn't regress** the easy path. It didn't. Cost was ~equal.

### Eval 1 — ElastiCache Redis (the differentiator)

This prompt is engineered to hit the exact gotchas the skill change targets: a **write-only auth
token** (ephemeral var, must never land in state, tests must use `command=plan`), and a **`check`
block warning** that fails `terraform test` unless it is anticipated and handled with `expect_failures`.

- **`old_skill`** reached green, but **discovered the check-block problem blind** — its first
  `terraform test` came back `0 passed / 1 failed`, and only then did it diagnose the cause and add
  `expect_failures`. That round-trip is rework.
- **`with_skill`** **cited the gotcha up front** ("exactly as the skill warned"), wrote the
  `expect_failures` and a dedicated warning-fires run pre-emptively, and landed **`terraform test`
  10/0 (vs 5/0)** and **checkov 43/0/5 (vs 37/0/4)** — more coverage, no blind failure.

Both handled the write-only token correctly (persisted only via Secrets Manager `secret_string_wo`,
`command=plan` throughout). The skill change converts a diagnose-after-failure loop into a handled-first
build. See the two `BUILD_LOG.md` files and `grading.json` for the cited evidence.

## Capability coverage

How much of the skill's surface these evals actually exercise.

| Capability (from `SKILL.md`) | Covered by | Status |
|------------------------------|-----------|--------|
| Greenfield NEW module, wrap proven upstream | evals 0, 1 | ✅ |
| Interface built **from downloaded source**, not memory | evals 0, 1 | ✅ |
| Per-service CIS/FSBP research → hardcoded, non-overridable controls | evals 0, 1 | ✅ |
| Minimal consumer inputs | evals 0, 1 | ✅ |
| Verification pipeline (fmt/validate/tflint/terraform test/checkov) | evals 0, 1 | ✅ |
| Latest-Terraform identification + feasibility gate | evals 0, 1 | ✅ |
| Write-only / ephemeral secret handling (no state leak) | eval 1 | ✅ |
| `check`-block warning handled (warning fires AND tests green) | eval 1 | ✅ |
| Consumer README + durable design record (DESIGN/steering) | evals 0, 1 | ✅ |
| No git operations | evals 0, 1 | ✅ |
| **Brownfield CHANGE (Path B): assess → gap-diff → backward-compat → semver → `moved {}`** | **eval 2 (spec only)** | ⚠️ **gap** |
| Steering-doc-only stop fork (hand off, don't build) | — | ⚠️ not isolated (builds run the continue fork) |
| Workspace setup (`setup-workspace.sh`) as a standalone task | — | ⚠️ exercised in report-mode inside builds only |

## The brownfield gap (eval 2 — spec authored, not yet run)

Path B is half the skill (`references/brownfield-mode.md`) and the merged runs don't touch it. Eval 2
in [`evals.json`](evals.json) is a complete, ready-to-run spec that targets exactly the parts greenfield
never needs — **assessment, gap-diff, and backward-compatibility discipline**:

- **Target:** an existing, intentionally imperfect module (e.g. `terraform-module-aws-s3`) that is
  missing CIS/FSBP controls and exposes a security setting as an overridable variable.
- **Task:** harden to CIS/FSBP **and** add one feature **without breaking consumers**.
- **Graded on:** assessed the existing interface; named the gaps (incl. the weakenable variable);
  classified every change additive vs breaking; made a semver decision with a migration note; added
  `moved {}` blocks for any address churn; kept existing tests green; added tests for the feature and
  each closed gap; called out live-resource operational impact; reached green; no git.
- **Arms:** `without_skill` vs `with_skill` — a **capability** axis (does the skill produce correct
  brownfield discipline at all?), distinct from the old-vs-new **regression** axis of evals 0/1.

Run it the same way as iteration-1 and drop the artifacts under
`iteration-1/eval-2-brownfield-.../{without_skill,with_skill}/`.

## What was deliberately left out

- `.terraform/` provider/module caches and any nested upstream `.git` (build noise, not evidence).
- `benchmark.json` / `benchmark.md` — empty template stubs, superseded by this file.
- The separate description-triggering **optimization run** (workspace `opt-results/`): every case
  reported a `0.0` trigger rate — a broken/misconfigured harness artifact, not signal — so it carries
  no defensible conclusion and was excluded.
- The standalone **SNS** build comparison: its baseline "discovered the on-disk skill … not a clean
  control" (per its own note), so it isn't a sound A/B and was excluded.
