# Handoff — driving superpowers from the steering document

This is **instruction-driven chaining**, not a programmatic import. The steering document is in the
conversation; you invoke the superpowers skills and tell them to treat it as binding constraints.
That is reliable but not atomic — if a superpowers step tries to re-decide something the steering doc
already settled, point it back at the doc.

Only do this if the creator chose "continue" at the runtime fork. Otherwise stop after writing the doc.

## Sequence

1. **`superpowers:brainstorming`** — invoke it, but state up front that the steering doc has already
   settled: provider/service, reuse decision, interface, security controls, conventions, and the
   verification pipeline. So brainstorming should NOT re-litigate those — it should only resolve
   whatever is genuinely still open (naming edge cases, optional features, environment specifics) and
   then produce/confirm the design that matches the steering doc. The design doc it writes must not
   contradict the steering doc.

2. **`superpowers:writing-plans`** — produce the task-by-task implementation plan from the (steering-
   aligned) design. The plan's tasks should map directly onto the steering doc's file layout,
   interface, controls, examples, and tests. Use TDD-style steps where they fit Terraform: write the
   native test / pick the checkov target first, then implement to green.

3. **Implement** — follow the plan. Honour the hard rules: hardcoded-literal security, minimal inputs,
   wrap-upstream, mandatory tags. Keep files focused per the conventions.

4. **Verify** — run the full pipeline from [verification-pipeline.md](verification-pipeline.md) and
   show evidence before claiming the module is done/compliant.

## What to carry into each step
Pass these explicitly so the superpowers skills don't drift from the steering doc:
- the reuse decision (module + pinned version, or scratch);
- the negotiated control table (kept/removed/added + justifications);
- the interface contract (required/optional inputs, the non-exposed hardcoded set, outputs);
- the verification bar (the exact commands that define "done").

## Hard rule — no git, and exactly where each superpowers step tries to do it
**No git operations** at any point. Each chained skill has a built-in git step that conflicts with
this — neutralise them explicitly so you don't rediscover the conflict mid-flow:

- **`superpowers:brainstorming`** wants to *write the design doc AND commit it*. Write the doc; **skip
  the commit.**
- **`superpowers:writing-plans`** templates a per-task **"Commit"** step (and `git add`). **Omit those
  steps** from the plan; tasks end at "tests green", not "committed".
- **`superpowers:executing-plans`** ends by invoking **`superpowers:finishing-a-development-branch`**
  (merge / PR / branch cleanup — all git). **Skip that terminal hand-off entirely**; report completion
  with the verification evidence instead.

Tell the creator once that the skill leaves version control to them. If the creator later **explicitly**
asks for git (init / commit / push / tag / PR), that is their instruction and it overrides this default
— do it then, but never on your own initiative.

## Optional: fully hands-off triggering (only if asked)
To inject the steering doc automatically on every prompt inside a Terraform repo (zero-touch), a
`UserPromptSubmit` hook in `settings.json` can `cat` the steering file into context. This is a harness
change with real blast radius (it fires on every prompt in that project) — propose it only if the
creator explicitly wants zero-touch behaviour, and use the `update-config` skill to make the change.
