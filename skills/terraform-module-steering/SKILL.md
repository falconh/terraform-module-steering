---
name: terraform-module-steering
description: >-
  Generate a reusable steering/context document that drives spec-driven work on high-quality,
  secure-by-default Terraform/OpenTofu modules — then optionally orchestrate the full superpowers
  brainstorm → plan → build → verify flow from it. Use this WHENEVER the user wants to create,
  scaffold, design, or plan a NEW Terraform module (e.g. "build a terraform module for X",
  "create terraform-module-aws-<service>"), OR improve, extend, add a feature to, harden, or audit
  an EXISTING Terraform module (e.g. "add Y to my terraform module", "make our S3 module CIS/FSBP
  compliant", "harden this module", "what controls is my module missing?"), wants a steering/context
  document to feed into brainstorming or planning of such work, or wants to set up a Terraform module
  workspace (terraform, tflint, checkov, required plugins). The skill researches the target service's
  CIS Benchmark + provider security best practices (e.g. AWS FSBP) per service and proposes them,
  defaults to wrapping proven upstream modules with minimal inputs and hardcoded, non-overridable
  security, treats backward compatibility + semver as first-class when changing an existing module,
  always documents the result (a clear consumer README + a durable spec/feature/security-control
  design record), and produces local content only (NO git operations).
---

# Terraform Module Steering

Turn "I need a Terraform module for X" — or "improve / add a feature to my existing module" — into a
governed, secure-by-default change, by first producing a **steering document** (a portable context
artifact) and then, if the creator wants, driving the spec-driven build from it.

The steering document is the point. It captures every decision *before* code changes, so any
spec-driven framework (superpowers, a teammate, a future session) can produce a consistent, compliant
result from it. The skill can hand the document to `superpowers:brainstorming` and
`superpowers:writing-plans`, or just leave it on disk for manual use.

## Operating rules (read first)

- **Produce local content only. NEVER perform git operations** (no init/add/commit/push/branch).
  Leave version control entirely to the creator.
- **Security is researched per service, not recalled from memory.** CIS Benchmark + the provider's
  security best practices (AWS FSBP, CIS GCP/Azure) differ by service. Research the actual controls
  for *this* service, propose them, and let the creator decide. See
  [references/security-research.md](references/security-research.md).
- **Mandatory controls are enforced as hardcoded literals, not variables**, so a consumer cannot
  weaken them. Minimise consumer inputs (typically just `name` + `environment`).
- **Reuse before building.** Prefer wrapping a proven upstream module pinned to a version.
- **When changing an existing module, do no harm.** Default to non-breaking, additive changes;
  surface any breaking change with a semver-major bump + migration note. See
  [references/brownfield-mode.md](references/brownfield-mode.md).
- **Document for reuse.** Every module you build or change ships a clear consumer `README.md` and
  preserves its spec/features/security-controls as a durable design record (the steering/change doc in
  the module's `docs/`). Documentation is part of "done". See
  [references/module-documentation.md](references/module-documentation.md).
- **Evidence before claims.** Never say "compliant"/"passing" without running the verification
  pipeline. See [references/verification-pipeline.md](references/verification-pipeline.md).

## Workflow

### 1. Orient — capture intent and determine the MODE
Decide which mode applies (ask only if it's genuinely ambiguous):
- **NEW module (greenfield):** there is no existing module; you're creating one. → Path A.
- **CHANGE to an existing module (brownfield):** the creator names or points at an existing module and
  wants to add a feature, extend, harden, or audit it. → Path B.

Gather only what's needed to steer: provider, service, module name/path, target environment(s), and a
one-line goal. Apply the naming convention `terraform-module-<provider>-<service>` for new modules. If
the request already states these, restate your understanding and move on.

### 2. Workspace check (shared) — verify, report, then ask before installing
Run the bundled checker in **report mode** (changes nothing):
```bash
bash <skill-dir>/scripts/setup-workspace.sh
```
Show the creator which CLIs (`terraform`, `tflint`, `checkov`, optional `terraform-docs`/`trivy`) and
plugins (`terraform-skill@antonbabenko`, `context7`) are present vs missing. **Only with permission**,
run `bash <skill-dir>/scripts/setup-workspace.sh --install`. Honest caveat: CLIs work immediately, but
newly-installed **plugins load only after a Claude Code restart**. Skip if they only want the document.

---

### Path A — NEW module (greenfield)

**3A. Reuse research.** Use `context7` (resolve-library-id → query-docs) and web search to find whether
a proven upstream module covers this service. Record: wrap `<module>` pinned `vX.Y.Z`, or scratch with
a reason. Wrapping is strongly preferred — it inherits maintenance and lets you hardcode security by
passing literals and exposing no override variable.

**4A. Security research (per service).** Research the actual CIS + provider controls for this service;
map each to a hardcoded enforcement. Default to CIS/the provider benchmark. ([security-research.md](references/security-research.md))

**5A. Propose & negotiate.** Present the control set; the creator may add/remove (with a reason) or add
custom benchmarks. Record every decision + justification.

**6A. Write the steering document** by filling [references/steering-template.md](references/steering-template.md)
to a local path (default `./<module-name>-steering.md`). Worked example:
[assets/steering-example-aws-s3.md](assets/steering-example-aws-s3.md).

**7A. Runtime fork** (see below).

---

### Path B — EXISTING module (brownfield)

Full method: [references/brownfield-mode.md](references/brownfield-mode.md). In brief:

**3B. Assess the existing module.** Read its `versions.tf`/`variables.tf`/`outputs.tf`/`main.tf` (+ topic
files), tests, examples, and current version. Capture the current interface, the controls it already
enforces, its structure, and its test coverage. Change nothing yet. (Use `code-intelligence`/`rg`.)

**4B. Gap-diff + capture the feature.** Research the service's CIS/provider controls (as in 4A), then
**diff against what the module already enforces** → the missing controls. Add the creator's requested
new feature(s) and any convention drift worth fixing.

**5B. Propose the change set + backward-compatibility analysis.** Present feature + gaps + fixes. For
EACH change, classify **additive (safe)** vs **breaking** (removing/renaming an input or output,
changing a default's behaviour, making optional→required, resource-address churn). Default to
non-breaking; when a break is unavoidable (e.g. hardcoding a control that was a variable), flag it,
require justification, and propose a **semver-major bump + migration note** (and `moved` blocks for
address churn). The creator negotiates with reasons.

**6B. Write the delta steering document** by filling
[references/change-steering-template.md](references/change-steering-template.md): current state →
target state → the delta (add/modify/preserve, each with its backward-compat class) → semver decision +
migration → verification delta (existing tests stay green + new tests).

**7B. Runtime fork** (see below).

---

### 7. Runtime fork — stop, or continue into superpowers
After the document is written, **ask the creator**:
> "Steering doc written to `<path>`. Stop here so you can use it manually, or shall I continue into the
> superpowers brainstorm → plan → build → verify workflow using it?"

- **Stop:** done — the document is portable and self-contained.
- **Continue:** hand off using the doc as *governing context*
  ([references/superpowers-handoff.md](references/superpowers-handoff.md)). For brownfield, this is a
  feature-add/refactor: TDD by writing failing tests for the new feature + each closed gap, keeping all
  existing tests green, then implementing. Still **no git operations**.

## How "automatic" the superpowers chaining is (be honest)
Instruction-driven, not a programmatic import: you generate the doc into the conversation, then invoke
the superpowers skills and tell them to treat it as binding constraints. Reliable but not atomic. A
fully hands-off trigger (inject the doc on every prompt in a Terraform repo) is possible via a
`UserPromptSubmit` hook — offer it only if the creator wants zero-touch behaviour.

## Reference files
- [references/security-research.md](references/security-research.md) — per-service CIS/FSBP research + propose/negotiate.
- [references/steering-template.md](references/steering-template.md) — steering-doc template (new modules).
- [references/brownfield-mode.md](references/brownfield-mode.md) — assess → gap-diff → backward-compat → delta doc (existing modules).
- [references/change-steering-template.md](references/change-steering-template.md) — delta steering-doc template (existing modules).
- [references/module-documentation.md](references/module-documentation.md) — consumer README structure + durable design-record convention (both modes).
- [references/superpowers-handoff.md](references/superpowers-handoff.md) — passing the doc into brainstorming/writing-plans.
- [references/verification-pipeline.md](references/verification-pipeline.md) — fmt/validate/tflint/checkov/test + checkov FP handling.
- [assets/steering-example-aws-s3.md](assets/steering-example-aws-s3.md) — a complete worked example.
