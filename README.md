# terraform-module-steering

A **Claude Code and Codex** skill + plugin that turns "I need a Terraform module for X" into a
governed, secure-by-default module — by first producing a portable **steering document** (a context
artifact that captures every decision before code exists), then optionally driving the whole
spec-driven build from it.

It ships manifests for both agents (`.claude-plugin/` and `.codex-plugin/`) over a single shared
skill, so the same plugin can be listed by a marketplace and installed from either tool.

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

This plugin is distributed through a centralized plugin marketplace that lists it for both agents.
Replace `<marketplace>` with that marketplace's name.

**Claude Code:**

```bash
claude plugin install terraform-module-steering@<marketplace> --scope user
# then restart Claude Code so the skill loads
```

For local or manual Claude Code use you can also load the skill directory for a single session with
`claude --plugin-dir /path/to/terraform-module-steering`.

**Codex:** add the marketplace, then enable the plugin from the `/plugins` directory:

```bash
codex plugin marketplace add <owner>/<marketplace-repo>
# then, inside Codex, run /plugins and enable terraform-module-steering
```

Once installed, just ask — e.g. *"create a terraform module for an AWS SNS topic"* or *"harden our
existing S3 module against CIS/FSBP"* — and the skill triggers.

## Layout

```
.
├── .claude-plugin/
│   └── plugin.json        # Claude Code manifest (skills -> ./skills)
├── .codex-plugin/
│   └── plugin.json        # Codex manifest (skills -> ./skills/)
└── skills/
    └── terraform-module-steering/
        ├── SKILL.md
        ├── references/    # security-research, steering + change templates, brownfield-mode, superpowers-handoff, verification, module-documentation
        ├── scripts/       # setup-workspace.sh (verify / --install)
        └── assets/        # worked example (AWS S3)
```

## License

[MIT](LICENSE).
