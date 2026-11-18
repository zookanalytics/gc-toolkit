---
name: Gas City search for a fix that lands ahead of a PR (tk-ilh8rgh)
description: The primitives searched in Gas City and bd for each need of a review finding whose fix lands ahead of the PR in a PR of its own, such as a missing architecture document, with what each covers and why the gap needs `gctk review ahead`, the `ahead` ruling and review-run.sh's `ahead` verb. Read it when building or reviewing that surface, as AGENTS.md asks of a change that adds a command, a verb or a key in a step's output.
---

# Gas City search for a fix that lands ahead of a PR

A review run's round meets a finding whose fix must not land on the PR's
branch. The arch method's missing architecture document is the case: the
document lands in a PR of its own, and the change waits for it, so retiring the
change cannot discard the document. The round needs four things, and each
below names the primitive searched, at Gas City upstream main 03f6fe825c
(2026-11-18) and bd 1.3.4 (`github.com/steveyegge/beads v1.3.4`, the version
that Gas City's `go.mod` names there).

## Hold the PR until the fix lands

**Covered: bd's `blocks` dependency.** The ask that holds the PR waits on the
fix by a `blocked-by` entry in its own create's `--deps`, so it is held from
the moment it exists. bd keeps a bead whose blocker is open out of `bd ready`,
and lets it back once the blocker closes (bd's
`docs/core-concepts/dependencies.md`: "When issue-1 is open, issue-2 won't
appear in `bd ready`"). The ask's own `blocks` edge on the PR's bead is the wait
the pack's merge already reads. Gas City writes no edge across stores
(`docs/runbooks/split-storage-classes.md`, "No edge ever crosses stores"), so
the fix is filed in the store of the PR's bead.

## Start the fix now

**Covered: `gc sling`.** "Route a bead to a session config or agent using the
target's sling_query", with `--on <formula>` for the formula it is poured on
(`docs/reference/cli.md`, "gc sling"). Nothing holds the fix, so it is slung at
once rather than armed for deferred dispatch.

A fix found by its title can carry one of Gas City's hold labels: `hold:mayor`
and `hold:external` (`DispatchHoldLabels`) or `human` (`HumanLabel`), in
`internal/beadmeta/hold_labels.go`. A pool's serve rule leaves out a bead that
carries one (`internal/config/workquery.go`), but the sling reads none of them:
no code under `internal/sling`, and none in `cmd/gc/cmd_sling.go`, names a hold
label. So the verb asks the arm domain's `HoldLabel`, which reads those labels
as Gas City compares them, and slings no fix that one holds.

## Judge the PR again once the fix lands

**Not covered by Gas City.** Its event for a closed blocker is core's
`cascade-nudge-on-blocker-close` order (`internal/bootstrap/packs/core/orders/`),
which nudges a dependent's assignee, or its `gc.routed_to` target when no one
holds it. An ask has neither, because no pool claims it, and a nudge pours no
workflow. No other order in that directory, and no `gc` command in
`docs/reference/cli.md`, starts a review of a PR when a bead closes.

The pack already covers it: the landing order pours a review run for an ask
that nothing holds, and the run takes it
([specs/tk-1tfzr71.108/design.md](../tk-1tfzr71.108/design.md), "Asks: work on
the PR's branch"). The ask sends the lane's check back, and the run judges the
PR's head again. This change composes that and adds no order.

## Record the ruling, and refuse one with no wait

**Not covered by Gas City.** The round's rulings are the pack's own output of a
review run's step (`services/gctk/review/run.go`), which no Gas City reader
reads. None of its rulings, must-fix, declined, deferred, answered and
question, says that a fix lands ahead of the PR. A deferred point renders as
work done "once this PR lands", which is false here.
So the change adds the ruling `ahead`, and the key `waits` in the round's
output, which names the ask. The output check refuses an `ahead` ruling whose
`waits` names no open ask on the bead, so no round can claim the wait without
it. Without that check, the round would pass and the PR would merge with the
document missing.

## What the change adds, and what it does not

- `gctk review ahead`, which finds the fix an open ask on the PR already waits
  on, else the open fix of its title, or files it, slings it, and files the ask
  in one create with its wait. These are bd's create and
  `gc sling`, and the same create again, run as one call, so it adds no noun
  ([review-arch.md](../../docs/review-arch.md), check 2).
- The ruling `ahead` and the key `waits` in the round's output.
- review-run.sh's `ahead` verb, which puts the command behind the script's
  step-ownership and shadow checks, as its `withdraw` verb does for
  `gctk pr withdraw`.
- No order, no bead kind, no lifecycle state and no metadata key. The fix is a
  task bead, and the ask is the shape `gctk review ask` already files. `target`
  is already registered in `lifecycle/lifecycle.toml`, and pr/record declares
  it so that gctk can write it.
