---
name: Upstream contribution drafts — build-factory trial findings
description: Ready-to-file issue drafts for the five upstream defects surfaced by the 2026-08-08 build-factory trial (evidence in build-factory-trial-reactions.md), each with reproduction and a proposed fix. For the operator to file against gastownhall/gascity-packs (or gascity core where noted) at their leisure; bodies are self-contained.
---

# Upstream contribution drafts

Five defects, all surfaced by one `build-basic` run (2026-08-08, split
city/rig layout, gascity pack 0.4.0 `f69ec02`). Evidence:
[build-factory-trial-reactions.md](build-factory-trial-reactions.md).
Ordered by severity. Each body below is self-contained for filing.

## 1. `build-basic`'s artifact gate silently never runs in a split city/rig layout

**Repo:** gastownhall/gascity-packs · **severity: high** (silent loss of
the factory's main quality mechanism)

> **Body draft:** In a city whose rigs are not rooted at the city root,
> every `[steps.check]` in `build-base.formula.toml` fails to start and
> the chain proceeds ungated. The check path
> `.gc/scripts/checks/build-artifact-valid.sh` is relative and resolves
> against the **rig root**, but `.gc/scripts/` exists only at the city
> root: each stage logs a control-quarantine
> (`lstat …/<rig>/.gc/scripts: no such file or directory`) and the
> workflow continues, so all four artifacts pass without schema
> validation and the 3-attempt repair loop is inert. Nothing in the run
> surfaces this as a failure. Compounding: the pack ships the scripts
> and `github-issue-fix`'s workflow installs them
> (`cp -R {{pack_root}}/assets/scripts .gc/scripts`), but `build-basic`'s
> `prepare` step never does. **Proposed fix:** install the check scripts
> in `build-basic`'s prepare (mirroring github-issue-fix), or resolve
> check paths against the pack/city root; and make a check that cannot
> start fail the step rather than quarantine-and-continue.

## 2. `decompose` proceeds past a `changes_required` review verdict

**Repo:** gastownhall/gascity-packs · **severity: high** (the review
stage looks load-bearing and is not)

> **Body draft:** In `build-base.formula.toml`, `decompose` declares
> `needs = ["plan-review"]` but nothing reads the review artifact's
> `status`/verdict, so a `changes_required` verdict is structurally
> advisory: decomposition reads the plan exactly as written and files
> beads from it. In our run the reviewer knew this and edited the plan
> in place as its only way to prevent a false finding from becoming an
> implementation bead. **Proposed fix:** gate `decompose` on the review
> verdict (block or loop on `changes_required`), or document explicitly
> that review is advisory and the sanctioned gate is external. If
> data-driven gating is planned, this is a natural first member.

## 3. Misleading sling-time warning about bead context (invites a stage-destroying "fix")

**Repo:** gastownhall/gascity (warning text) · **severity: medium**

> **Body draft:** Slinging a bead at `build-basic` prints a warning that
> the bead description "is not carried into the formula's rendered
> context … the formula's brainstorm will not see them." The description
> *does* arrive — via the auto-created input convoy — and our
> requirements stage demonstrably read material referenced only from the
> bead body. The warning is worse than inaccurate: the obvious operator
> correction is `--var requirements_path=<doc>`, which makes the factory
> *reuse* that document as the requirements artifact and silently skip
> the requirements stage. **Proposed fix:** reword the warning for
> formulas that create an input convoy, and document the distinction
> between `context_path` (extra context) and the stage-skipping
> `*_path` vars.

## 4. Decomposer claims "per the headless contract" under `interaction_mode=interactive`

**Repo:** gastownhall/gascity-packs · **severity: low** (mode plumbing
or prompt bug; misleads audits)

> **Body draft:** With the workflow configured
> `interaction_mode=interactive`, the decompose stage recorded decisions
> "rather than asked, per the headless contract." Either the var is not
> reaching the stage prompts, or the stage text defaults to headless
> phrasing regardless of mode. Small, but it makes run records claim a
> mode the operator did not set. **Proposed fix:** thread the actual
> `interaction_mode` value into stage prompts (or their rendered
> headers) so stages cite the configured mode.

## 5. `validate_build_artifact.py` hard-requires PyYAML, undeclared

**Repo:** gastownhall/gascity-packs · **severity: low**

> **Body draft:** The manual fallback validator exits
> `error: PyYAML is required`; nothing declares the dependency and no
> stdlib fallback exists, so on hosts without PyYAML both the automated
> gate (issue 1) and the manual fallback are unavailable — and in our
> run a stage *claimed* validation had run when it could not have.
> **Proposed fix:** declare the dependency (or vendor a minimal
> frontmatter parser), and make the validator's absence loud in the
> stages that reference it.
