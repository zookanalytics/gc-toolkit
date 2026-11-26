---
name: Gas City search for giving a held step back before the drain-ack
description: The accommodation record AGENTS.md asks for on work_drain in assets/scripts/work-lib.sh, which gives back the step a session still holds before `gc runtime drain-ack`. It holds Gas City's reason for refusing that ack, cited at gastownhall/gascity d6d5784f9cff, the measurement that tests the reason in this city, and why no fix at the source is owed. Read it before changing which of mol-polecat-work's stops give their step back, or when Gas City changes what drain-ack does with a started claim.
---

# Gas City search for giving a held step back before the drain-ack

Gas City is cited at `gastownhall/gascity` d6d5784f9cff (upstream main,
2026-11-24), by symbol and file. The functions below are the same at
dfd5200c3ee3, which the change's first commits cite.

## The behavior

A session's own `gc runtime drain-ack` is refused, with nothing released,
while the session holds a claim it started and has not finished
(`releaseUnexecutedClaimsForSession` in `cmd/gc/cmd_runtime_drain.go`, and
`releaseDrainAckClaims` with `refuseStarted` in `cmd/gc/session_beads.go`).
Drain-ack's release keeps each claim the seat's own started records name
(`releaseDrainAck` in `releasePolicies`, with `startedNamedKeeps`, in
`cmd/gc/work_release.go`). A mol-polecat-work stop that ran the ack while its
step was in progress left the step held by a session that had stopped working
on it.

`work_drain` gives that step back to the pool through `hand-back.sh` before it
runs the ack, when the step reads in progress under one of the session's names.

## Gas City's reason

`releaseUnexecutedClaimsForSession` gives it: a seat's own ack "is the seat
saying it holds nothing", and it is refused while the seat holds started work
the release would keep, because "acking would stop the seat with that claim
kept on it, the assigned-work wake would restart it, and the cycle would
repeat." The refusal's text names the way out: continue the work, or have an
operator ack from outside the session with `--operator`.

The assigned-work wake is the controller's pool demand for work assigned to a
seat (`computePoolDesiredStatesParkedAt` in `cmd/gc/pool_desired_state.go`):
in-progress work assigned to a seat that is asleep is demand to wake a seat of
its template for it.

## The measurement

**What was counted.** Every stop of a polecat seat in this city, from the
templates `gc-toolkit.polecat` and `gc-toolkit.polecat-codex` in every rig,
over the city's event log and its archives, 2026-11-17 06:03Z to 2026-11-24
10:02Z. Read on 2026-11-24 by replaying the log in sequence order: the
`bead.created`, `bead.updated`, `bead.closed` and `bead.deleted` events give
which beads are in progress under each session, so each `session.stopped`
event shows the claims the stopping seat kept, and the next `session.woke`
event of the same session shows what the controller did next.

**Result.** Polecat seats stopped 1,885 times. 13 of the stops left a step in
progress on the seat, each a mol-polecat-work `workspace-setup` or
`preflight-tests` step. All 13 seats were woken again under the same session,
7 to 50 seconds after the stop (median 12), and each then closed its step. At
one of them, the stop holding tk-sttmmjn at 2026-11-21 03:59Z, the controller
also created two more polecat sessions within two seconds. Both found the step
held, and drained with no work (`session.demand_claim_divergence`, with
`trigger_status_at_drain` in progress).

**What it shows.** The reason holds here. A seat that stops with a started
claim kept on it is woken again to that claim within seconds. A seat that
stopped because it could not finish its step, such as one whose store did not
answer, would be woken to the same step and stop again for as long as the
cause lasted, which is the cycle the reason names. The refusal is therefore
not a fault in this city, and no fix at the source is owed.

## The composition

Gas City's refusal leaves a seat that cannot continue its started work one
thing to do before it acks: give the work back. Gas City's verb for that is
`gc bd release-if-current` (`ReleaseIfCurrent` in
`internal/beads/bdstore_conditional_release.go`), which writes
`bd update <id> --if-assignee <holder> --if-status in_progress --status open
--assignee ""`. It leaves the claim's session pins, `gc.session_id` and
`gc.session_name`, which the witness ranks ahead of the assignee and reads as
an orphan's, so `hand-back.sh` writes the same guarded update with the pins
removed (its header says so). The step keeps its route, so its pool offers it
to the next worker, and the session then holds nothing, so its ack goes
through.

Giving the step back is right only where the next worker can finish it.
Gas City's claim-loop guard (`cmd/gc/claim_loop_guard.go`) holds a bead's
demand once three seats fail to claim it with the same error, and it reads only
failed claims (`bead.claim_failed`). A step given back is claimed without
error, so the guard never sees a stop that every worker meets the same way.
Core's own polecat formula makes the same split for a refused push
(`internal/bootstrap/packs/core/formulas/mol-polecat-commit.toml`, step
`commit-and-push`): the session that read the refusal retries it, and a push
it cannot land fails the step "instead of handing the push back to the pool".
So `work_drain` gives a step back only from a stop whose cause can clear by the
next worker's turn: a store that does not answer, an origin that does not
answer before or after the push, a bring-current guard that did not finish,
and a store-only exit `store-only-exit.sh` refused, which the next worker takes
again or, when the run has work to land, lands the normal way. A stop every
worker would meet
the same way does not reach it. A push origin answers and refuses exits 3, so
the session merges origin's branch or fixes its commits and runs the hand-off
again. A refinery address that names no agent ends the run on a gate for a
person to correct the binding.
