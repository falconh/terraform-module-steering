# Security research — per service, propose, default to the benchmarks

The creator's rule: **CIS Benchmark + the provider's security best practices differ per service.
Research the relevant controls for *this* service, propose them, and let the creator add/remove
(with a documented reason) or add custom benchmarks. CIS + the provider benchmark are the defaults
when the creator has no specific opinion.**

Do NOT enumerate controls from memory — they change, and they are service-specific. Research them.

## Step 1 — Identify the benchmark sources for the provider

| Provider | Default benchmarks |
|---|---|
| AWS | CIS AWS Foundations Benchmark + AWS Foundational Security Best Practices (FSBP, the Security Hub standard) |
| GCP | CIS Google Cloud Platform Foundations Benchmark |
| Azure | CIS Microsoft Azure Foundations Benchmark |

If the creator names a different standard (PCI-DSS, HIPAA, NIST 800-53, their own internal baseline),
treat it as additive — research it alongside the defaults.

## Step 2 — Research the controls for THIS service

Use, in order of preference:
1. **context7** — `resolve-library-id` then `query-docs` against the provider's security docs or the
   upstream module's docs (the module's inputs reveal which controls are configurable).
2. **Web search** — "<service> CIS benchmark controls", "<service> AWS FSBP controls",
   provider Security Hub / Benchmark documentation.
3. **The upstream module's variables** — if wrapping a module, its security-related inputs map almost
   1:1 to the controls you must set (encryption, public-access, logging, TLS, IAM, versioning…).

For each control, capture a row:

| field | meaning |
|---|---|
| `id` | control id (e.g. CIS 2.1.1, FSBP S3.5) — note ids drift between benchmark versions; cite the version or map by intent |
| `intent` | what it protects against, in one line |
| `enforcement` | the exact hardcoded setting the module will apply (literal, not a variable) |
| `applies?` | does this service actually have this posture? (a dashboard has no "encryption at rest") |

## Step 3 — Map each control to a HARDCODED enforcement

The module enforces mandatory controls by passing **literals** to its resources/upstream module and
**not exposing them as variables** — that is the mechanism that makes them non-overridable. Example
shape (AWS S3): `block_public_acls = true` (literal), never `block_public_acls = var.block_public_acls`.

If wrapping an upstream module, the enforcement is "pass this literal input"; if building from
scratch, it's "set this argument / create this resource".

## Step 4 — Propose & negotiate

Present the researched control set as a table. Then explicitly invite changes:
> "These are the CIS/<provider-benchmark> controls I found for <service>. You can add or remove any
> — tell me the reason so I record it — and add custom benchmarks for your use case. If you're not
> sure, we keep the full CIS/<benchmark> set as the default."

Record in the steering doc, for every control: kept / removed / added, and the **justification**.
A control removed without a reason is a red flag — ask for one before proceeding.

## Step 5 — Note scanner reality

Some controls will be flagged by static scanners (checkov/tfsec/trivy) as failing even when correctly
configured — especially when wrapping modules that use separate/`count`-indexed/`dynamic` resources.
Capture, per control, whether it is a true gap or a known scanner false-positive, and how it's
verified (e.g. plan-based scan). Details: [verification-pipeline.md](verification-pipeline.md).

## Generalisation — services with little or no security posture

If the research yields few or no controls (e.g. a CloudWatch dashboard, an SNS topic, a DNS record),
say so plainly and produce a short proposal. Do **not** invent encryption/public-access/logging
framing where it does not apply. This is how the skill stays useful for *any* module, not just
data-plane ones.

**The benchmarks don't cover the same services.** A service can have provider controls (AWS FSBP) but
**no** CIS Foundations controls — e.g. ECR is FSBP-only (ECR.1/2/3) with no CIS-AWS-Foundations
entries. Don't pad the table with invented CIS IDs to mirror the FSBP rows: map each control by intent,
cite the benchmark that actually defines it, and leave the other column empty when it has nothing.
