# terraform-module-steering

A Claude Code **skill + plugin** that turns "I need a Terraform module for X" into a governed,
secure-by-default module — by first producing a portable **steering document** (a context artifact
that captures every decision before code exists), then optionally driving the whole spec-driven
build from it.

It is distributed as a single-plugin **marketplace**, so it can be installed anywhere.

## What it does

- **Generates a steering document** for any new Terraform/OpenTofu module: identity, reuse decision,
  minimal interface, security controls, conventions, and the verification bar.
- **Researches security per service.** It looks up the *actual* CIS Benchmark + provider
  security-best-practice controls (AWS FSBP, CIS GCP/Azure) for the target service, proposes them,
  and lets you add/remove (with a documented reason) or add custom benchmarks — defaulting to
  CIS/the provider benchmark when you have no specific opinion.
- **Prefers wrapping proven upstream modules** (e.g. `terraform-aws-modules`) pinned to a version,
  with **minimal inputs** (`name` + `environment`) and **hardcoded, non-overridable** security.
- **Optionally orchestrates** the `superpowers` brainstorm → plan → build → verify workflow using the
  steering doc as the governing context (you choose at runtime — stop at the doc, or continue).
- **Verifies** with `terraform fmt`/`validate`, `tflint`, native `terraform test` (mock_provider),
  and `checkov` — including guidance for the checkov false positives that wrapping modules produce.
- **Bundles a workspace setup script** that verifies (and, with your consent, installs) the required
  CLIs and plugins.

It performs **no git operations** — it produces local content only and leaves version control to you.

## Install

```bash
# 1. Add this repo as a marketplace
claude plugin marketplace add falconh/terraform-module-steering

# 2. Install the plugin (user scope)
claude plugin install terraform-module-steering@falconh --scope user

# 3. Restart Claude Code so the skill loads
```

Then just ask, e.g. *"create a terraform module for an AWS SNS topic"* or *"write me a steering doc
for terraform-module-aws-s3"*, and the skill triggers.

## Layout

```
.
├── .claude-plugin/
│   ├── marketplace.json   # marketplace "falconh" listing this plugin (source ".")
│   └── plugin.json        # plugin manifest (skills -> ./skills)
└── skills/
    └── terraform-module-steering/
        ├── SKILL.md
        ├── references/    # security-research, steering-template, superpowers-handoff, verification-pipeline
        ├── scripts/       # setup-workspace.sh (verify / --install)
        └── assets/        # worked example (AWS S3)
```

## License

[MIT](LICENSE).
