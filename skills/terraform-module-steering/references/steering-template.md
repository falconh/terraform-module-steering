# Steering Document — `terraform-module-<provider>-<service>`

> Fill every section. Delete guidance in _italics_. This document is the binding context for
> building the module — any spec-driven framework should be able to produce the module from it
> without re-deciding anything here.

## 1. Identity
- **Module name:** `terraform-module-<provider>-<service>`
- **Provider / service:** _e.g. AWS / S3_
- **Purpose (one line):** _what the module deploys and for whom_
- **Target environments:** _dev / test / staging / prod_

## 2. Reuse decision
- **Wrap or scratch:** _wrap `<registry/module>` pinned `vX.Y.Z` / build from scratch_
- **Why:** _the upstream module exposes the needed controls / nothing suitable exists_
- **Provider + Terraform version floor:** _e.g. terraform >= 1.6, aws >= 6.42._ Floors are
  **provisional until confirmed against the pinned upstream module's `versions.tf`** at build — match
  (or exceed) it; don't guess. Prefer the **latest** Terraform for the toolchain when feasible (SKILL.md
  step 2). Where the provider offers it, resolve version-like defaults from a **data source** (a "latest
  GA" lookup) rather than a hardcoded literal that goes stale.
- **Upstream interface — confirm from source, not memory:** author every wrapped-module call from the
  module's *downloaded* `variables.tf`/`outputs.tf` (exact input/output names + nested object/map shapes
  drift across versions). See [wrapping-upstream-modules.md](wrapping-upstream-modules.md).

## 3. Consumer interface (minimise inputs)
- **Required inputs:** _typically `name`, `environment`_
- **Optional inputs (safe defaults):** _name = default, why each is safe_
- **NOT exposed (hardcoded):** _every security-relevant setting — list them; this is the
  non-overridable guarantee_
- **Outputs:** _ids, arns, and any keys/log targets consumers need_
- **Provider config:** the module does NOT configure the provider; the consumer owns region/creds.

## 4. Security controls (researched, proposed, negotiated)
_Benchmarks used: CIS <provider> + <provider best-practice standard> (+ any custom)._

| Control (id) | Intent | Enforcement (hardcoded literal) | Decision | Justification |
|---|---|---|---|---|
| _CIS x.y / FSBP S3.x_ | _…_ | _`setting = value`_ | kept/removed/added | _reason_ |

_Removed controls must have a reason. Custom/extra benchmarks go here too._

## 5. Conventions
- **Files:** `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, plus topic files (`kms.tf`,
  `logging.tf`…). Create a topic file only when it owns **real resources**; fold pure-expression logic
  (mappings, effective values) into `locals.tf` rather than an empty-ish topic file. (Brownfield: match
  the existing module's layout instead of imposing this.) Standard naming; reserve `this` for genuine
  singletons; descriptive resource names.
- **Block ordering:** resource → `count`/`for_each` first, then args, then `tags`, then `depends_on`,
  then `lifecycle`. Variables → description → type → default → validation.
- **Version pinning:** pin the upstream module to an exact version; set a provider version floor.
- **Tagging:** mandatory tags merged over consumer tags (consumer cannot drop them).

## 6. Verification pipeline (the definition of done)
- `terraform fmt -check -recursive`
- `terraform validate`
- `tflint` (with provider ruleset)
- `terraform test` (native tests; `mock_provider` so no creds are needed)
- `checkov` (document any false-positive / out-of-scope suppressions, with reasons)
- **Done = all green, with evidence.** See verification-pipeline.md for the checkov FP handling.

## 7. Examples, tests & documentation to include
- `examples/minimal/` — the smallest consumer (required inputs only); doubles as a scan fixture.
- `tests/*.tftest.hcl` — assert the controls the module owns + conditional logic.
- `README.md` — consumer docs: purpose, usage, requirements, inputs/outputs, and a **Security controls
  enforced** table (mark all hardcoded / non-overridable). See
  [module-documentation.md](module-documentation.md).
- `docs/DESIGN.md` — this steering doc, preserved with the module as the durable design record.

## 8. Out of scope / limitations
- _Account-wide or org-wide settings, anything needing a console/CLI-only step (e.g. MFA-delete),
  features explicitly deferred (replication, lifecycle tiering, event notifications)._

## 9. Hard rules
- Security controls are **hardcoded literals, not variables**.
- **No git operations** are performed while building from this document.
