---
name: Gas City search for a decline that ends its own run uninterrupted
description: Use when you need the evidence for why run-cancel.sh --step puts the step its session holds back to not started before it sends Gas City's run cancel, which Gas City and bd primitives that write composes, and which ones were searched and do not cover it.
---

# Gas City search: a decline that ends its own run uninterrupted

A session that declines its work ends the run it is executing through Gas
City's run cancel, and the cancel interrupts the turn of every session that
holds a started step of the run, the sender included. The change grows
`run-cancel.sh --step` by one write. Before the cancel, the step this session
holds goes from `in_progress` back to `open`, keeping its assignee and session
pins, in one write guarded on that status and assignee. It adds no script,
flag, metadata key, kind or state. Each primitive searched is below, with what
it covers.

Read at `gastownhall/gascity` main f143846427 on 2026-11-11. The city's `gc`
build, 36ad5186a, holds the same `internal/api/huma_handlers_runs.go`,
`internal/api/huma_types_runs.go` and `internal/molecule/workflow_stop.go`
byte for byte. At main 6bd609f5b, the tip later that day, the one commit since
that touches these files (eb5f0b0422) moves the cancel and the workflow delete
onto the plan's workflow legs, and `inProgressAssignees` and the delete's
`skipped` outcome read the same. Where a line says "observed", it was also run
on bd 1.3.4.

## What the cancel interrupts

**Ending the run: the supervisor's run cancel.** Covers the end, and is where
the interrupt comes from. `humaHandleRunCancel` in
`internal/api/huma_handlers_runs.go` runs `cancelRun`, whose first write marks
the root `gc.cancel_requested`. `planRunCancel` then collects
`inProgressAssignees`, the assignees of the run's members whose status is
`in_progress`, and `interruptRunHolders` sends each live one the interrupt
`POST /session/{id}/stop` sends (`session.Manager.StopTurn`), which ends the
tool call the turn is running. A session declining its own run holds the step
it is executing, so it is among them, and its call ends before the drain that
follows the cancel.

**Sparing the sender: no primitive.** `RunCancelInput` in
`internal/api/huma_types_runs.go` carries only the city scope and the run id,
so the cancel cannot tell who sent it, and no request option exempts a session.
No `gc` verb cancels a run; `gc wait cancel` cancels a wait.

## What keeps the sender out of the holders

**Leaving `in_progress`: bd's guarded update.** Covers it. `inProgressAssignees`
skips every member whose status is not `in_progress`, whoever it is assigned
to. `bd update <step> --if-status=in_progress --if-assignee=<holder>
--status=open` makes that move in one write, and a step that changed after it
was read refuses it whole. Observed in a scratch store: the write moved a step
from `in_progress` to `open` and kept its assignee and its `gc.session_id`; the
same write again, and one guarded on another assignee, each exited 13 with
nothing written.

**Keeping the step out of every other claim: the assignment it keeps.** Covers
it. `hookCandidateClaimable` in `cmd/gc/cmd_hook_claim.go` lets a fresh claim
take only an unassigned candidate, so a step that is open and assigned to this
session is that session's ready assignment and no other session's. Once the
cancel's mark lands, `workflowRootStop` in `internal/molecule/workflow_stop.go`
reads the root as cancelled, and the claim gate refuses the step to anyone.

**Giving the claim back to the pool: `ReleaseIfCurrent`.** Covers the
interrupt, and opens a gap the kept assignment does not. `ReleaseIfCurrent` in
`internal/beads/bdstore_conditional_release.go`, the write `gc bd
release-if-current` makes, is `bd update <id> --if-assignee <holder>
--if-status in_progress --status open --assignee ""`. It clears the assignee,
so between that write and the cancel's mark the step is unassigned and
`hookCandidateClaimable` lets any pool session claim it, and the cancel then
interrupts that session instead.

## Other ends of a run

**Deleting the workflow: `DELETE /v0/workflow/{workflow_id}`.** Does not cover
it. `humaHandleWorkflowDelete` in `internal/api/huma_handlers_convoys.go`
interrupts no session, but it closes the run's open members with
`gc.outcome=skipped` and stamps no cancel intent, so `workflowRootStop` reads
the run as settled, not cancelled. A decline is a cancel, and the pack keeps
this route for members a closed root left open.
