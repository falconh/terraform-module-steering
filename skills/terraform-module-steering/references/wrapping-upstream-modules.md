# Wrapping an upstream module — get the interface from source, not memory

Wrapping a proven upstream module is the default: it inherits maintenance and lets you hardcode
security by passing literals and exposing no override variable. The failure mode that wastes the most
build time is **authoring the module call from remembered or registry-documented names** — because
exact input/output names, and especially nested object/map input shapes, differ between modules and
drift across major versions.

## The rule

Author every wrapped-module call **from the module's downloaded source**, not from memory, the registry
web docs, or `context7` (those are directional — good for "does a control exist?", unreliable for exact
spelling).

1. Pin the exact version first (query the registry for the latest stable, or honour the creator's pin).
2. `terraform init -backend=false` to download it.
3. Read the real interface:
   ```bash
   grep -nE 'variable "|output "' .terraform/modules/<name>/variables.tf .terraform/modules/<name>/outputs.tf
   # then read the specific blocks for exact types, defaults, and value shapes
   ```
4. Author the module call against what you just read. Confirm the version floors here too
   (`.terraform/modules/<name>/versions.tf`) and reconcile them into the steering doc — the floors you
   guessed earlier are provisional until this step.

## What specifically drifts (look for these)

- **Renamed scalars** — e.g. `subnet_ids` vs `subnets`, `instance_class` vs `cluster_instance_class`.
- **Per-element settings inside a map/object input** — a setting you'd expect at top level may live
  inside an `instances`/`nodes` map of type `map(object({ ... }))`; to hardcode it you set it on each
  element, not once at the top.
- **Object-typed inputs** — e.g. a parameter group passed as one `object({ family, parameters })`
  rather than several flat `create_*` / `*_family` / `*_parameters` variables.
- **Prefixed variants** — cluster-level vs instance-level (`cluster_<x>` vs `<x>`); the wrong scope
  silently no-ops or errors.
- **Output value shapes** — one module returns an ARN string, another returns an object/list you must
  index (`...[0].secret_arn`). Unify these in *your* module's outputs.

## When selecting between two upstream modules

If you `count`-gate two wraps (one input picks module A or B), remember Terraform evaluates **both**
branches of a ternary and static scanners read **both** module bodies:

- Guard output expressions with `one(module.X[*].out)` (yields the element or `null`) instead of
  `module.X[0].out`, which errors when that wrap is `count = 0`.
- Expect checkov to flag the un-instantiated branch; confirm the control is wired in
  `.terraform/modules/...` and suppress with a documented reason (see verification-pipeline.md).

## Brownfield

When a change **bumps an existing wrapped pin**, repeat this from-source confirmation against the *new*
version. A bump that renames or restructures an input or output changes the module's own consumer
interface — classify and surface it as a **breaking change** (semver-major + migration), don't absorb
it silently.
