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
| Heal skips on `green@`/`exception@`/unmappable, dispatches on `fixable@` | `assets/scripts/check-set-heal.sh` |
| Held exceptions surfaced to `gc doctor` | `doctor/check-merge-gate-drop/run.sh`, arm 3 |
| Pre-open re-arm: a stale `green@`/`exception@` on a `pre_open_gate` anchor is cleared, since nothing else re-arms a pre-open gate | `assets/scripts/reconcile-gate-verdicts.sh` |
| Spec | `docs/work-bead-state-machine.md`, §"Gate verdicts: the marker verb" |
| Regression | `assets/scripts/reconcile-gate-verdicts.test.sh` (102 assertions); the heal-side verb classification in `assets/scripts/check-set-heal.test.sh` (cases `EXCEPT`/`FIXABLE`/`WEIRD`/`NOVERB`) |

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
the anchor — the same population the shipped signoff round cap counts — and it is
the **escalation** that is head-bound, which is what the doc's one-per-head rule
is actually protecting against (notification spam, per AE-WS4-4). The head is
still stamped alongside the count, so `attempts=<n>@<sha>` reads as "n rounds
spent, observed at this head".

The count is over **closed** children only, and the exhaustion trigger separately
requires that no child is open. That is *not* a third divergence — it is the
design read literally ("when a remediation child closes unresolved, the gate
increments attempts") and it is where the first shipped cut got it wrong: counting
all statuses made a round *in flight* count as a round *spent*, so at `MAX=3` two
closed rounds plus a live third read as exhausted and the arm stamped `exception`
— terminal until an operator acts — over a branch a worker was actively fixing.
The two guards answer different questions ("how many rounds finished" and "is one
running right now") and come apart whenever a child is filed outside the signoff
cap's accounting, so both are enforced. It costs at most one idle wake: the cap
fires on the wake after the last child closes, and the operational lifecycle
guarantees that close — a rework child closes at hand-back, as landed-on-branch.
The signoff cap can keep counting all statuses because it asks at a single instant,
immediately before filing the next child, where nothing is in flight.

**2. `fixable` is recorded only where it is observable.** The design has the gate
skill emit fixable. This arm is an observer: it does not run skills, so it records
`fixable@<head>` only when there is an open remediation child — which is what
"the skill found addressable problems and remediation is in flight" looks like
from outside. With no open child the gate is left **unevaluated** rather than
stamped fixable. Stamping it there would assert a finding nobody made — a verdict
standing in for the absence of one, which puts the gate's state back to something
inferred from open children rather than the pure read this record exists to give.

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
  dispatch forever. Now the marker is classified **totally**, the way
  `gate_verdict` classifies it: skip on `green@` (satisfiable), on `exception@`
  (terminal until an operator acts), and on any value naming **no verb at all**
  (R12 unmappable — see below); dispatch on `fixable@` and on an absent marker.

  The unmappable arm was added in round-3 rework (review `tk-i688b`, P1), and it
  is an **ordering** fix rather than a vocabulary one. `check-set-heal.sh` runs
  *before* `reconcile-gate-verdicts.sh` in the same patrol step, so dispatching on
  an unmappable marker queues a codex review in the window before the exception
  arm records `exception@<head>` for it. That review outlives the window — it is
  claimed on a later wake — and a passing verdict stamps `green@<head>` over the
  exception, lifting by ordinary automation a hold R12 defines as
  terminal-until-operator with no automated pass-or-fixable path. Skipping costs
  one wake of latency and nothing else: the merge is held under both markers,
  since `merge-skill.sh` holds on anything that is not `green@<live head>`.

  Nothing is stranded by the extra skip. An unmappable marker never goes stale —
  `gate_verdict` answers `unmappable` at *every* head, because an unreadable verb
  leaves no oid comparison to make — so it does not need the pre-open re-arm
  below. It is converted to `exception@<head>` by the very next pass in the same
  wake, and from there it is an ordinary stale exception that the re-arm already
  clears.

`merge-skill.sh` and `pre-open-resolve.sh` were checked and needed **no** change:
both compare for equality against `green@<head>`, so a new verb holds correctly.

**But teaching a reader the verbs is only half of it — something has to re-arm
them.** `check-set-heal.sh` now skips on two verbs, and its skip is *bead-side*:
it resolves no head, so it cannot tell a current verdict from residue left behind
by a head that has since moved. Post-open, `reconcile-merged-prs.sh`'s stale-marker
arm supplies the missing head-awareness and files the re-review. **Pre-open it does
not exist**: that arm enumerates `merge_result=pull_request` only, there is no PR
to read a head from, and no other pass re-armed a pre-open gate. So an
`exception@<old>` on a `pre_open_gate` anchor outlived the operator fix it was
waiting for — the operator fixed the branch, the head advanced, the heal pass kept
skipping, `pre-open-resolve.sh` kept refusing to open a PR that was not green at
the *live* branch head, and the branch sat held with nothing left to raise it. The
same hole swallowed a stale `green@<old>` pre-open, for the same reason and with
the same result.

`reconcile-gate-verdicts.sh` closes it, because it is the one pass that already
resolves the pre-open head: on a `pre_open_gate` anchor whose gate reads
unevaluated with nothing in flight, a stale `green@`/`exception@` marker is
**cleared**, and the gate returns to unevaluated for `check-set-heal.sh` to
dispatch on the next wake (this pass runs after the heal pass, so the re-arm and
the dispatch are one wake apart — convergent, not immediate). Scope is deliberate
in three ways: only the two verbs that block a dispatch (`fixable@` blocks
nothing, and the fixable record overwrites it anyway); only with no open child
(with one, the `fixable@<head>` record *is* the re-arm, in the same pass); and only
pre-open, because post-open the stale marker is the evidence
`reconcile-merged-prs.sh` keys on and clearing it would take the case away from the
arm that already heals it. The pass's safety invariant is untouched: clearing can
only hold harder, since an absent marker is green at no head.

**And the re-arm is only reachable if the dead review is retired** (pre-open
signoff finding, review `tk-bjyld`). The R12 worker-lost scan condemned a review
bead on three facts — open, assignee answered by no live session, untouched past
the deadline — none of which is bound to a head, because a review bead records no
dispatch head. Left open, the same corpse therefore answered the scan again at
*every* later head: the operator fixed the branch, the head moved, `gate_verdict`
read the old marker as unevaluated exactly as designed, and then the corpse
re-derived `worker-lost` and re-stamped `exception@<new head>` *before* the re-arm
above could clear anything. The head move was consumed on every wake. `exception`
was not "terminal until the input changes", it was terminal full stop, and the
operator escape this whole lifecycle is built around did not exist. Post-open the
same residue could stamp exception over a genuine re-review that
`reconcile-merged-prs.sh` had just dispatched at the new head.

Two halves fix it, and neither is sufficient alone:

- **Suppress** a fresh worker-lost condemnation while an `exception@<old head>`
  marker is still on the anchor, so the re-arm runs instead. That is as much
  head-binding as this arm can have without a dispatch-time head stamp, and
  pre-open it is a proof rather than a heuristic: `check-set-heal.sh` skips its
  dispatch on `exception@*`, so nothing *can* have dispatched a review for the
  current head while that marker sat there — any review found under it is residue
  of the old one. Suppressing only defers, since the residue is retired in the same
  pass, and it errs in the safe direction: an unrecorded exception under-reports a
  hold the marker keeps holding anyway, while a wrongly-recorded one is terminal
  until a human acts.
- **Retire** the condemned review — mark it `gate_verdict_condemned=<head>` (so it
  can never spend a second condemnation even if the close is refused) and **close**
  it. The close is what makes the escape real: `check-set-heal.sh`'s in-flight probe
  asks `--status=open,in_progress` on the exact `anchor_bead` surface and trusts a
  hit outright, so a dead review left open reads as "a signoff is already in flight"
  forever and the replacement dispatch never goes out. Marking alone would stop the
  re-condemnation and still leave the gate un-dispatchable — the same silent hold,
  one step along.

Retirement is confined to gates that are **not** OK, which is why every call site
sits below the `verdict = ok` early-continue. Post-open an open review bead is
itself a merge hold (`merge-skill.sh` holds on any unclosed rework/review bead for
the anchor), so closing one *releases* a hold; off the OK path this gate's marker
is by construction not `green@<live head>`, so `checkset_hold_gate` holds the merge
on the marker alone throughout and the never-merges invariant survives whichever
order the writes land in. On an OK gate the open review could be the only remaining
hold, and this pass never touches one. Two supporting details: the scan now takes
**all** the dead reviews rather than stopping at the first (a second corpse left
open poisons the next head by itself), and the close takes a `--force` retry
because `bd close` is assignee-gated and this bead's assignee is foreign by
construction — a session that no longer exists. That gate protects a *live*
holder's work, and the two-part test that selected the bead is the proof there is
none; it is the same evidence already trusted to record a terminal verdict and mail
an operator.

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
