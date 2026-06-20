# evals/

Evaluation evidence and a **runnable** suite for the `terraform-module-steering` skill. Start with
**[EVALS.md](EVALS.md)** for the baseline policy, methodology, results, and coverage matrix. This
README is the directory map plus how to run an eval.

## Layout

```
evals/
├── EVALS.md                     # ← read this: baseline policy, results, coverage matrix
├── evals.json                   # eval definitions, assertions, baseline policy, run pointer
├── verify.sh                    # the deterministic pipeline (fmt/init/validate/tflint/test/checkov)
├── fixtures/
│   └── terraform-module-aws-s3-legacy/   # green-but-imperfect S3 module — target for eval 2
└── iteration-1/                 # HISTORICAL recorded runs (the A/B that produced today's master)
    ├── review.html              # styled side-by-side viewer
    ├── eval-0-greenfield-ecr/        old_skill/ + with_skill/
    └── eval-1-elasticache-redis/     old_skill/ + with_skill/
        └── <arm>/
            ├── grading.json     # per-assertion pass/fail + cited evidence
            ├── timing.json      # tokens, wall-clock, tool uses
            └── outputs/         # the FULL generated module (.tf, tests/, README, docs/DESIGN, BUILD_LOG)
```

## Baseline policy (short version)

`master` is the baseline; there is no frozen snapshot. To test the current skill, compare
`with_skill` (master) vs `without_skill` (no skill). To evaluate a new feature, compare the feature
branch vs `master`. Full rationale in [EVALS.md](EVALS.md).

## Running an eval (standard skill-creator practice)

The runs themselves are not committed — generate them into a workspace when you run. For each eval in
[`evals.json`](evals.json):

1. **Spawn two builds in the same pass** — one `with_skill` (the skill on `master` available), one
   baseline. Baseline is `without_skill` (no skill) for current-state testing, or `master` when
   evaluating a feature branch. Give each the eval `prompt` and have it save the produced module to
   `iteration-<N>/<eval-name>/<arm>/outputs/`.
2. **Capture cost** from each run into `iteration-<N>/<eval-name>/<arm>/timing.json`
   (`{ "total_tokens": ..., "duration_ms": ..., "total_duration_seconds": ... }`).
3. **Verify** each produced module with the bundled pipeline:
   ```bash
   ./verify.sh iteration-<N>/<eval-name>/<arm>/outputs
   ```
4. **Grade** each arm against the eval's `assertions` into
   `iteration-<N>/<eval-name>/<arm>/grading.json` — expectations use the fields `text`, `passed`,
   `evidence` (the skill-creator viewer depends on these names).
5. **Aggregate + view** with the skill-creator tooling (from the skill-creator plugin dir):
   ```bash
   python -m scripts.aggregate_benchmark <evals>/iteration-<N> --skill-name terraform-module-steering
   python eval-viewer/generate_review.py  <evals>/iteration-<N> --skill-name terraform-module-steering \
       --benchmark <evals>/iteration-<N>/benchmark.json
   ```

`eval-2` (brownfield) is ready to run now: point the build at
`fixtures/terraform-module-aws-s3-legacy` (see its README for the deliberate gaps and the
backward-compat traps it grades).

## Reproducing iteration-1

These recorded `outputs/` exclude `.terraform/` caches, so re-running starts with `terraform init`.
Read a run as: `eval_metadata.json` (what was asked) → `grading.json` (did it pass, with evidence) →
`BUILD_LOG.md` (the narrative) → `outputs/` (the deliverable) → `review.html` (side-by-side).
