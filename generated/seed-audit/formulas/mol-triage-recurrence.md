Formula: mol-triage-recurrence
Description: mol-triage-recurrence — wakes standing triage conversations when they
have something NEW to talk about.

What it does, plainly: the operator keeps standing "triage subjects" —
beads marked task_kind=triage-subject, each defining a pool of beads it
curates (examples: "triage: held ideas", "triage: all P1s of this
rig"). This formula runs on a daily order and, for each triage subject,
files ONE visit (a routed conversation sitting) IF the subject's
candidate set has CHANGED since the last visit this step filed AND no
visit for it is already live — open OR held (a held visit is
`in_progress`). An unchanged set, a scope that was already empty, or a
visit already live → it files nothing for that subject. A scope that
just EMPTIED is a change like any other: it files one last visit naming
what left, then goes quiet. The result: each triage conversation
appears on the board exactly when it has new material, and never
stacks.

Why a set-delta and not just "the scope is non-empty": the non-empty
test skips STACKING but not RECURRENCE. A **park-shaped** subject — one
whose scope matches exactly the beads parking puts into it, e.g.
`label:parked-debt` — never drains, so a non-empty test re-asks the same
already-answered question every cooldown forever. Three of them fired at
once on 2026-08-10, each on a set unchanged from the day before, each
costing a sitting. Only "the set moved" tells a park worth revisiting
from one that is simply still parked.

Deliberate gap: a purely STRATEGIC change — the line that parked work
belongs to becomes live again, so everything in scope turns ripe at once
— moves no ids and so files nothing. That trigger is the operator's, by
hand via mol-visit; a subject that wants it says so in its own prose. Do
not try to infer it here.

The triage itself (enumerate candidates, rank, frame promote/park/kill)
is NOT this formula's job — the converse session does that at visit
time. This formula only answers "is a visit warranted right now?"

Contract: graph.v2, so the compiled workflow root is Ready-visible and
a scale-from-zero pool wakes for it. The step closes its own step bead
with gc.outcome.

Spec: specs/2026-08-fresh-start/liveness-and-triage-spec.md §3.


Steps (2):
  ├── mol-triage-recurrence.evaluate-and-file: Per triage subject: skip if a visit is live or the scope set is unchanged; file a visit on a delta
  └── mol-triage-recurrence.workflow-finalize: Finalize workflow [needs: mol-triage-recurrence.evaluate-and-file]
