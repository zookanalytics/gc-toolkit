---
name: A molecule ends with the work it was poured for
description: Design record for tk-3lr25yr. How a parked graph.v2 molecule's lifetime is bound to its source work bead through an end bead and a blocks edge, why that mechanism and not an event order, a gascity reap or a sweep, how the disposer's PR guard reads a closed work bead, and what the change leaves uncovered.
---

# A molecule ends with the work it was poured for

## The problem

`molecule-hold.sh` parks a molecule when a polecat declines work it must not
close: a duplicate dispatch, a premise found false, work already delivered. The
park recorded how it should end as a sentence in a step note, such as "releases
when the operator closes the superseded source". Nothing acted on the sentence.
On 2026-10-10 the gc-toolkit store held 36 non-closed `mol-polecat-work` roots
under dead owners. All 36 were parks, and for 28 of them the work bead was
already closed.

## What changed

A molecule's lifetime is bound to its source, the one bead its input convoy
tracks. `assets/scripts/molecule-end.sh` holds the binding, and
`molecule-hold.sh` runs it as the last act of every hold, after the blocking
write and the quiesce.

- **The work has closed.** The molecule ends there, the held step with it.
  `dead-molecule-dispose.sh` runs with `--owner`, which leaves the caller's
  own session out of the liveness guard, and with `--if-source-closed`.
- **The work is still open.** The molecule gets one end bead. It is a member
  (`gc.root_bead_id`, `gc.step_ref=molecule-end`), routed to the held step's
  pool, and `blocks`-edged on the work bead and on every open escalation visit
  tracking the root or the work. `bd ready` withholds it while any blocker is
  open. Once they close, whichever writer closes them, the pool is offered the
  end bead, and the polecat that claims it runs `molecule-end.sh` on it, which
  ends the molecule, the end bead included. The hold has cleared the held
  step's route and the root's by the time the end runs, so it names the pool
  with `--route`.
- **A step a fresh session claims over closed work.** Three entry steps gate
  on the work bead's status and route a closed one through `molecule-hold.sh`,
  which ends the molecule before the step does anything. The gated steps are
  `mol-polecat-work`'s self-review iteration and submit-and-exit, and
  `mol-validate`'s load-dispatch. Load-context already routed a closed bead
  through the hold. This covers a molecule that was mid-flight, not parked,
  when its work closed: its next step is claimed, and the claim ends it.

A disposer refusal is a wait on what it names. An open visit joins the end
bead's blockers. A work bead reopened between the read and the end keeps the
end bead waiting on it. A live session still running a step of the molecule
owns its end, so nothing is armed, and an end bead its claimant holds is
retired. A refusal the disposer would repeat, such as a member carrying
`branch`, files a visit keyed `molecule-end-<root>` through `escalate.sh`, and
the end waits on that visit.

## Why the end runs last, and which sessions keep a molecule

A live session running a step of the molecule owns its end, because its own
way out ends it: a hold runs the end as its last act, the gated steps send
closed work through a hold, and a molecule that runs on finishes at its
terminal step. The end's claimant retires the end bead when it finds such a
session. That is safe only if the session it defers to really does end the
molecule, and two rules make sure it does.

**The end runs after the hold's own writes.** The work can close while a hold
is running, and the end bead is offered as soon as it does. The pre-open
correctness review of this branch reproduced the failure when the end ran
before the hold: the hold armed the end, the work closed before the blocking
write, a second polecat claimed the end bead, saw the holder still running its
step, and retired the only end bead. The hold then finished and drained, and
nothing ever read the work again. The final state was a root `in_progress`, a
held step, closed work and no live end bead. With the end last, a claimant
that reads the holder's claims before the hold's writes finish leaves the
molecule to the holder, and the end the hold runs after those writes finds
the work closed and ends the molecule. A claimant that reads after them finds
the holder running nothing, and ends the molecule itself.

**Under `--if-source-closed`, only a session running a step counts as live.**
The disposer reads a session's names only off a step the session has claimed
(assigned, or `in_progress`) and can still run. Its claim on the held step
(`blocked`) does not count, because the hold keeps that claim only so a re-run
can find the step. The root does not count: it runs no step, though a live
root can carry a polecat's `gc.session_name` (this rework's own molecule root
carried the name of the polecat running it). The end bead's claim does not
count, because its claimant is there to end the molecule. Without this, the
holder's end would find the end bead's claimant live while that claimant found
the holder live, and each would leave the molecule to the other. Only
`molecule-end.sh` passes `--if-source-closed`, so the disposer's other callers,
`dead-molecule-sweep.sh` and `orphan-dispose.sh`, keep the broader guard.

## Why an end bead routed to the pool

The bead asked for an end that runs when the source closes, whoever closes it,
with no sweep and no cadence order. It also asked for the wait to be a graph
edge (rule tk-n7r69z). The mechanisms considered, against gascity at
d9d05b065:

- **A `bead.closed` event order.** Order triggers include `event`, but the
  exec receives no bead id or event subject, and several events collapse into
  one run (`cmd/gc/order_store.go`, `cmd/gc/order_dispatch.go`). The order
  would have to search for the molecules to end on every close in the city,
  which is a sweep with a different trigger.
- **gascity's molecule and wisp autoclose.** The controller runs them on
  `bead.closed`, but both skip a non-terminal root on purpose, to protect
  human-gate checkpoints (`cmd/gc/molecule_autoclose.go`,
  `cmd/gc/wisp_autoclose.go`). The molecule arm also keys on
  `gc.source_bead_id`, which a convoy-first `--on` pour never stamps.
- **A control bead the dispatcher runs.** The control-dispatcher runs a pack
  script only as a ralph check gate, after an iteration bead closes
  (`internal/dispatch/ralph.go`). A legacy `gc.kind=check` bead blocked by the
  work would run its script when the work closed. But a failing gate clones
  its subject as the next attempt, and here the subject would be the work
  bead. The gate also runs in a sandbox where `gc` can be cold, so the
  disposer's `gc session list` liveness guard could not run.
- **A second `workflow-finalize` bead.** `processWorkflowFinalize` closes the
  root and force-closes the members, but without the disposer's guards and
  without de-routing first. The bead required the guarded de-route-then-close.
- **`deferred-dispatch`.** An arm slings a bead when it becomes ready. The bead
  noted the order was disabled in gc-toolkit; it was resumed at town commit
  f038047 (2026-10-10T05:56Z). It is not needed here: a plain route on a bead
  held by a `blocks` edge is already gated by `bd ready`, and
  `doctor/check-blocked-work-armed` names `gc.routed_to` as a dispatch path for
  blocked work. An arm is for an `--on` sling, which pours at once.
- **Each closing writer ends the molecule.** `gc-helm.sh takeaway --release`
  already reaps a released anchor's molecule. Extending that to `merge.sh`,
  `bead-rehome.sh`, `scaffolding-sweep.sh`, `pr-dispose.sh` and converse would
  still miss an operator's `bd close`.

The end bead is a plain pool route behind a `blocks` edge, so the pool tier
offers it when the work closes, and no part of the city searches for it. Its
cost is one short polecat session per molecule that outlives its work.

## The source-mid-PR guard and a closed work bead

The cleanup preview (tk-29y8gx) found four molecules the disposer refused with
`source_pr_unresolved`. Each source was a rework child closed moot that still
carried its anchor's `pr_number` with an empty `merge_result`.

The guard keeps the disposer from orphaning a PR the molecule could still be
carrying, such as a rework molecule that has not yet pushed to an open PR. That
can only be true while the work bead is open. `merge.sh` lands open anchors
only, as `doctor/check-closed-implies-landed` (I5) states, so a PR a closed bead
names has merged, was retired with its anchor (which carries
`gc.superseded_by`), or is its anchor's to land. No step of the closed bead's
molecule carries anything to it. So the guard now applies to an open work bead
only. An open work bead mid-PR still refuses, and so does one carrying an
unresolved PR reference. The four anchors behind the preview's refusals were
all closed, either merged or superseded.

## What this leaves uncovered

- **The backlog.** Molecules parked before this change carry no end bead, and
  nothing ends them when their work closes. The one-time cleanup tk-29y8gx
  ended 26 parks on 2026-10-10 and closed. It left the parks whose work was
  still open, and the five it refused: the four PR-guard refusals and one park
  behind an open visit. On 2026-10-11, 21 parked molecules had a non-closed
  root, 7 of them over closed work. tk-vpzxq4l runs `molecule-end.sh` once on
  each one still parked after this lands. That ends a molecule whose work has
  closed, the four PR-guard refusals included now that the guard reads an open
  work bead only, and arms an end bead on each of the rest.
- **A work bead closed with `gc.work_outcome=blocked`.** gascity's readiness
  treats such a blocker as still blocking (`DependencySatisfied`,
  `internal/beads/beads.go`), so the end bead stays unready. No pack writer
  closes a bead that way today.
- **Formulas without an entry gate.** A `mol-review` molecule, or any formula
  not gated above, runs a step over closed work until the step completes the
  molecule or holds it. A hold ends it.
- **A live session running a step when the end bead fires.** The end bead
  retires and leaves the molecule to that session, whose hold, gate or
  terminal step ends it. A session that drains mid-chain without holding hands
  its next step to a fresh session, and on a gated step that session ends the
  molecule.
- **The held step's own marker.** The held step still carries
  `blocked_reason` with no `blocks` edge of its own, which
  `doctor/check-wait-is-an-edge` (I1) reports at warning severity, as it did
  before. The molecule's wait on its work is the end bead's edge. An edge on
  the held step would also hold a lift, which returns the step to `open`, until
  that blocker closed, and lifting a hold is tk-p9wh2oh's path.

## Coordination

tk-p9wh2oh (PR #1174) also changes `molecule-hold.sh`'s sibling quiesce, so
that a step waiting behind the held one keeps its route. The end bead is
skipped by its own `gc.step_ref` filter, which composes with that change. Under
#1174 the end bead would read as ready on its own, since its blocker is outside
the molecule, so without the skip it would be de-routed.

## Validation

- `assets/scripts/molecule-end.test.sh` runs the real hold, end and disposer
  over the shared stub store. It parks a molecule, closes its source, and
  observes the end bead's run close the molecule with no sweep. It also
  covers an open source left alone, each refusal as a wait, park-after-close,
  a `mol-validate` molecule, the create, block and route order, a create that
  answers with no id, failed writes and dry runs. Three race cases each end
  the molecule. In the first, the review's interleaving, the work closes and
  the end bead is claimed and run while the hold is still running. In the
  second, the work closes before the parker drains. In the third, an end
  bead's live claimant is present when another session's hold reads the
  closed work. Run against the scripts as they stood before this fix, the first
  reproduces the review's state: the claimant's run reports `result=live`, and
  the root stays `in_progress`, the held step `blocked`, with no end bead left.
- `molecule-hold.test.sh` covers the end running last, after the blocking
  write, the sibling quiesce and the root's de-route, with the pool passed as
  `--route`. It also covers an ended molecule exiting 0 when the quiesce left a
  route, a failed end failing the hold, a step whose molecule cannot be
  resolved getting no end, an end bead whose molecule cannot be resolved
  failing its own step, the end bead keeping its route, and the three formula
  gates extracted and executed.
- `dead-molecule-dispose.test.sh` covers `--owner`, `--if-source-closed` and
  the sessions it counts live, and the PR guard on a closed work bead.
- Each of these targeted mutants fails a suite: no `--owner`, no visits at
  arm, the end bead de-routed by the hold, the end bead never routed, the PR
  guard on a closed source, a reopened source not re-armed, an end bead whose
  create answered with no id left unfound, an end bead's own step exiting 0
  when its molecule cannot be resolved, the end run before the hold, the end
  run before the quiesce, no `--route`, and a failed quiesce overriding an
  ended molecule. So does each of these under `--if-source-closed`: a live
  session counted through the root, through a held step, through an end bead,
  or through a step nobody has claimed.
