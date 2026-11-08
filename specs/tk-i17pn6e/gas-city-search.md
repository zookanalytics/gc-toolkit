---
name: Gas City search for a PR's size line
description: The search the arch check asks for before the pack adds tools/measure.sh --pr, the deletion plan's file list as tools/deletion-plan.tsv, and the CI job that posts a PR's size section. What Gas City and the packs it publishes ship for measuring a change's lines, read at named upstream commits, and why the pack computes the line from its own rules. Read it when checking whether the size line can move onto a Gas City primitive.
---

# Gas City search for a PR's size line

Rule 3 of the built-once target
([built-once-target.md](../../docs/built-once-target.md#the-rules)) has every
gc-toolkit PR show its size change, computed from git from the merge base to
the head. It gives the net runtime and test lines by subsystem, and names
separately the lines the change adds to files the deletion plan retires, with
the bead that retires each. It carries no budget and fails nothing. The arch
check asks what Gas City already ships for that need before the pack adds
surface for it ([review-arch.md](../../docs/review-arch.md#the-checks),
check 1). Neither Gas City nor any pack it publishes splits a change's lines by
kind or subsystem, or reads a plan of retiring files. The nearest primitive is
GitHub's own count of a PR's added and deleted lines, which one published pack
reads to refuse an oversized PR. The split the rule asks for comes from facts
only gc-toolkit's tree holds, so the pack computes the line.

## The surface

- `tools/measure.sh --pr BASE HEAD` prints the section in markdown: the net
  runtime and test lines from the merge base of BASE and HEAD, a row per
  subsystem, the kinds beside the pack, and each file the deletion plan retires
  that the change adds lines to, with the bead that retires it. It prints
  nothing for a merge base that does not carry the tool.
- `tools/deletion-plan.tsv` is the plan's file list as data: one row per file,
  the path and the bead that retires it. The tool reads it at the merge base.
- `.github/workflows/pr-size.yml`, a job in gc-toolkit's own CI, runs
  `pr-size.sh` beside it on each push to a PR. The script takes the tool from
  the merge base, runs it to the PR's head, and keeps one comment on the PR
  current with the section under a `## Size` heading. Both are gc-toolkit's
  own check, not pack content another rig runs.

The change adds no bead key, metadata field, order, agent or command, and
nothing to the PR summary the pack's refinery writes. The search ran while the
design put the section in that summary, which is why its terms include a PR
body's writer. The operator then ruled that the line applies only to
gc-toolkit, and it moved to gc-toolkit's CI.

## Where the search looked

- Gas City at main `e6abcce27a3a`, the commit GitHub's
  `repos/gastownhall/gascity/commits/main` named on 2026-10-26, outside its
  tests: code, docs and engineering docs.
- Every pack in `gastownhall/gascity-packs` at main `dac12a4a802c`, from a depth
  1 clone.

The terms were those of a change's size (`numstat`, `shortstat`,
`diff --stat`, `diffstat`, `additions`, `deletions`, `changedFiles`,
`lines changed`, `lines added`, `net lines`) and of a PR body's writer
(`gh pr create`, `gh pr edit` with a body, `--body-file`).

## What ships near the need

- **GitHub's totals.** A PR carries `additions`, `deletions` and
  `changedFiles`, shown on its page and read with `gh pr view --json`. They
  count every changed line of every file together: docs, the record under
  `specs/`, generated files and tooling sit in one number with runtime and
  tests, and nothing in them knows a subsystem or a retiring file.
- **pr-pipeline's size guard.** `pr-pipeline/commands/pr/review/run.sh` reads
  `gh pr view --json additions,deletions,changedFiles`, and
  `pr-pipeline/formulas/mol-pr-review.formula.toml` refuses to review a PR
  whose additions and deletions exceed `--max-diff-lines` (5000 by default),
  recording `verdict: too_large`. That is a budget gate on GitHub's totals, the
  kind of check the rule leaves out.
- **bmad's code review.** `bmad/skills/bmad-code-review/steps/step-01-gather-context.md`
  has the reviewing model present diff stats, files changed and lines added and
  removed, before it reviews. That is a model's account inside its review, not
  a line computed onto the PR.
- **Gas City itself.** `internal/api/handler_rigs.go` counts a rig checkout's
  changed files from `git status --porcelain` for the rig's status, which is
  whether the working tree is dirty, not the size of a change. The `Makefile`
  runs `git diff --stat` over the generated API schema to show drift. Gas City
  writes no PR body, and core's `mol-polecat-report` names `gh pr create` only
  as a step a report does not take.

## Why the pack computes the line

The rule's line rests on three facts that live only in gc-toolkit's tree: which
kind a path is (runtime, test, or one of the kinds beside the pack), which
subsystem it belongs to (its row in section 4 of `docs/component-model.md`, or
the measuring rules), and which files the deletion plan retires. GitHub's
totals mix the kinds together and carry no subsystem, and no primitive reads a
plan. The tool reads all three from git objects at the commits it measures, so
the line needs no stored state. Only gc-toolkit's own CI posts it, so another
rig the pack serves gets no line. The rule rules
out a budget and a size gate, so pr-pipeline's guard is not a fit either.
