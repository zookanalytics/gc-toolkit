---
name: WS4 gate exception/verdict lifecycle — implementation record
description: What shipped for tk-5eikz (WS4 of tk-zgse0), why the substrate is the observer reconcile arm rather than gascity's internal/convergence loop, the two deliberate divergences from the merged design, and what was scoped out.
date: 2026-08-11
status: IMPLEMENTED
epic: tk-6d0vb
follow_up: tk-zgse0
workstream: WS4 — gate exception state machine (R5, R8, R11, R12, R20)
work_bead: tk-5eikz
design: specs/tk-zgse0.2/merge-gate-exception-lifecycle.md
extends: docs/work-bead-state-machine.md
---

# WS4 gate exception/verdict lifecycle — implementation record

The design is `specs/tk-zgse0.2/merge-gate-exception-lifecycle.md` (merged as
PR #219). This record covers only what implementing it decided: the substrate
question the bead and the design answer differently, two places the
implementation diverges from the design's literal wording, and what was
deliberately left out.

## What shipped

| Piece | File |
|---|---|
| The verdict output contract (R5, R20) — a total function from marker to verdict | `assets/scripts/reconcile-gate-verdicts.sh`, block `gate-verdict-contract` |
| The exception reconcile arm (R8, R11, R12) | same file |
| Wired into the refinery idle pass, after the observer | `formulas/mol-refinery-patrol.toml`, pass `(a2)` |
| Stale-gate arm learns all three verbs | `assets/scripts/reconcile-merged-prs.sh` |
| Heal skips on `green@`/`exception@`, dispatches on `fixable@` | `assets/scripts/check-set-heal.sh` |
| Held exceptions surfaced to `gc doctor` | `doctor/check-merge-gate-drop/run.sh`, arm 3 |
| Spec | `docs/work-bead-state-machine.md`, §"Gate verdicts: the marker verb" |
| Regression | `assets/scripts/reconcile-gate-verdicts.test.sh` (69 assertions) |

`merge-skill.sh` is **untouched**, which is the design's central claim and it
holds unmodified: it merges only while every declared gate equals
`green@<live-head>`, so a new marker verb already holds the merge. The new pass
never writes `green` and never merges — every write it makes holds the merge or
keeps it held — so no failure mode of it can land work. The regression asserts
that invariant directly (`NEVERGREEN`).

## The substrate: two different things are called "the convergence primitive"

The bead says:

> SUBSTRATE: host the exception/verdict lifecycle on gascity core's convergence
> primitive (`internal/convergence/`; `metadata.go`, `gate.go`). This is a FIRST
> ADOPTION, not a refactor — zero gc-toolkit formulas use convergence today.

The design doc the same bead names as its requirements source says something
else by the same name:

> It is a new instance of the **convergence primitive** already in the codebase —
> the observer's idempotent, head-bound, idle-cadence reconcile arm, whose
> canonical instance is the stale-base rebase arm.

and, on where the arm should physically live:

> recommend the same home as the stale-base arm — a convergent `reconcile-*.sh`
> pass invoked on the refinery idle wake — so the exception arm shares the
> observer's existing state/liveness/time read rather than adding a new driver.

These are not two descriptions of one thing. **Implemented per the design doc**,
for three reasons established by reading the gascity package rather than by
preference:

1. **It is not head-bound, and head-binding is the whole convergence argument.**
   `internal/convergence/` counts a global `convergence.iteration` on a loop root
   bead (`create.go`, `handler.go`, `trigger.go`, `reconcile.go`). Nothing in it
   knows about a git head, so no datum in it goes stale when the head moves. The
   design's exit from exception — "the head advances and every head-bound datum is
   stale for the new head and re-arms" — has nothing to hang on there. Adding it
   is a gascity-side change, i.e. a different repo and a cross-rig bead.

2. **It would add a second driver over the same anchors.** The loop is driven by
   the **controller** (`cmd/gc/convergence_tick.go` — a socket-served event loop
   processing `wisp_closed`), while the check-set is driven by the refinery patrol.
   Hosting the verdict lifecycle there puts two drivers on one anchor. The bead
   itself forbids exactly that: *"the convergence loop is subordinate and there is
   no two-owner conflict"* — which is achievable only by making the loop advisory,
   at which point it is not the substrate.

3. **The design's guarantees are stated against the observer reading.** "No new
   driver, no new writer of merged-truth, no merge-skill change" is true of a
   reconcile arm and false of a controller-driven loop.

The gascity loop remains a plausible host for a *future* WS1/WS2 phase-1 review
loop, where "run a formula until a gate passes, bounded by max_iterations" is the
actual shape wanted and no head-binding is required. Recorded here so the next
reader does not re-derive it: the finding is "not this workstream", not "not
useful".

## Two deliberate divergences from the design's literal wording

**1. The round count is not reset per head.** The design describes
`check.<name>.attempts` as "remediation rounds spent on this head". Taken
literally the counter resets whenever the head moves — but a rework round that
does any work at all moves the head *by construction*, so the bound would reset
every single round and R11's "convert to exception rather than re-spawning again"
could never fire. The runaway R11 exists to stop is a sequence of rounds across
**moving** heads (one PR reached 15). So the bound counts remediation children of
the anchor across all statuses — a closed child is a completed round, which is how
the shipped signoff round cap already counts it — and it is the **escalation**
that is head-bound, which is what the doc's one-per-head rule is actually
protecting against (notification spam, per AE-WS4-4). The head is still stamped
alongside the count, so `attempts=<n>@<sha>` reads as "n rounds spent, observed at
this head".

**2. `fixable` is recorded only where it is observable.** The design has the gate
skill emit fixable. This arm is an observer: it does not run skills, so it records
`fixable@<head>` only when there is an open remediation child — which is what
"the skill found addressable problems and remediation is in flight" looks like
from outside. With no open child the gate is left **unevaluated** rather than
stamped fixable. Stamping it there would assert a finding nobody made, and — worse
— would tell `check-set-heal.sh` that a gate with nothing in flight needs no
dispatch, re-creating the indefinite hold this work exists to end.

## The hazard this change had to clear

Adding verbs to `check.<name>` is only additive if **every existing reader** knows
them. Two did not, and both would have failed in the same direction — a silent
indefinite hold, the exact class WS4 addresses:

- **`reconcile-merged-prs.sh` stale-gate arm** matched `green@*` only. A head that
  moved past a `fixable@`/`exception@` marker would have fallen through the arm
  entirely: no re-review, no rework bead, `merge-skill.sh` holding forever on a
  marker bound to a dead commit. Now matches any known verb at a non-live oid,
  which is also what the design's lifecycle requires (a head move drops OK,
  fixable and exception alike back to unevaluated).
- **`check-set-heal.sh`** treated *any* non-empty marker as "the gate is
  satisfiable, no dispatch" — sound when green was the only verb there was. A
  `fixable@` marker left after remediation ended would have suppressed the
  dispatch forever. Now: skip on `green@` (satisfiable) and on `exception@`
  (terminal until an operator acts), dispatch on everything else.

`merge-skill.sh` and `pre-open-resolve.sh` were checked and needed **no** change:
both compare for equality against `green@<head>`, so a new verb holds correctly.

## Scoped out of this branch

**R7/R10/R23 — per-finding child fan-out with `finding_key` dedup** (filed as `tk-elc0x`). The design
maps each accepted finding to one child of the anchor, deduped by a stable
`finding_key`. Today the codex signoff files **one** rework child per round
(`template-fragments/polecat-non-impl-done.template.md`, the `REQUEST_CHANGES`
arm), not one per finding. Converting that is a rewrite of the live signoff
dispatch path — a different change, in a different file, with its own failure
modes — and R7/R10 are "supporting" requirements for WS4 rather than its core
(R5/R8/R11/R12/R20). Filed separately rather than half-landed here, per the bead's
own instruction.

**A dispatch-time deadline stamp.** The design has the gate dispatch carry a
deadline. R12 is implemented without one: a gate is called dead when its review
bead is untouched past `GC_GATE_DEADLINE` (default 4h) **and** no live session
answers its assignee. Both conditions are required, so a slow-but-live reviewer is
never condemned, and an unreadable session roster disables the arm outright rather
than condemning every assignee at once. A per-gate deadline stamped at dispatch
would be a refinement, not a prerequisite.
