# evals/

Evaluation evidence for the `terraform-module-steering` skill. Start with **[EVALS.md](EVALS.md)** for
the methodology, results, and capability-coverage matrix. This README is just the directory map.

## Layout

```
evals/
├── EVALS.md                     # ← read this: method, results, coverage matrix, what was left out
├── evals.json                   # eval definitions, assertions, and the brownfield spec (eval 2)
├── baseline-skill-snapshot/     # the pre-change skill the `old_skill` arm ran (A/B provenance)
│   └── terraform-module-steering/
└── iteration-1/
    ├── review.html              # styled side-by-side viewer for the runs
    ├── eval-0-greenfield-ecr/
    │   ├── eval_metadata.json   # prompt + assertions for this eval
    │   ├── old_skill/           # pre-change skill arm
    │   │   ├── grading.json     # per-assertion pass/fail + cited evidence
    │   │   ├── timing.json      # tokens, wall-clock, tool uses
    │   │   └── outputs/         # the FULL generated module
    │   │       ├── *.tf, examples/, tests/*.tftest.hcl
    │   │       ├── README.md            # consumer docs the build produced
    │   │       ├── docs/DESIGN.md       # durable design record
    │   │       ├── *-steering.md        # the steering document
    │   │       └── BUILD_LOG.md         # every fork point + decision the run made
    │   └── with_skill/          # current-skill arm (same shape)
    └── eval-1-elasticache-redis/   # same shape; this is the differentiating eval
```

## How to read a run

1. **`eval_metadata.json`** — what was asked and the assertions it's graded on.
2. **`grading.json`** (per arm) — did each assertion pass, with the evidence.
3. **`BUILD_LOG.md`** (per arm) — the narrative: mode chosen, module wrapped, gotchas hit, how green
   was reached.
4. **`outputs/`** — the actual module produced (this is the deliverable being judged).
5. **`review.html`** — open in a browser for an `old_skill` vs `with_skill` side-by-side.

## Reproducing

Each arm was a full autonomous build (research → steering doc → wrap upstream → hardcode CIS/FSBP →
`terraform fmt/validate` → `tflint` → `terraform test` → `checkov`). Tooling used: Terraform 1.15.6,
TFLint 0.63.1, checkov 3.3.1. The `outputs/` here exclude `.terraform/` caches, so re-running starts
with `terraform init`.

`eval-2` (brownfield, Path B) is specified in [`evals.json`](evals.json) but **not yet run** — see the
"brownfield gap" section of [EVALS.md](EVALS.md).
