---
name: deferred-dispatch reconcile leaked one input convoy per pass — root cause and fix (tk-xemty8)
description: Why the deferred-dispatch reconcile pass minted a fresh "input convoy for tk-p82tvo" every 2–3 minutes (47 stray open husks) on an arm whose work was already delivered, the two-layer cause (a stale arm with no failure memory in reconcile, and gc sling minting a convoy per call in gascity), the reconcile-side fix, and the sweep. Read before touching cmd_reconcile's sling/retry path or the slung/fail-count markers.
---

# deferred-dispatch reconcile leaked one input convoy per pass

## Symptom

`tk-p82tvo` carried a `gc.dispatch_when_ready` arm (armed 2026-09-08, bare pool
target, no `--on`) to dispatch its work once its blocker closed. The blocker
closed around 2026-09-21, but the work had already been delivered by another
path: branch `polecat/tk-p82tvo` was pushed, PR #812 was open, and the bead
carried `merge_result=pull_request`. From then the reconcile pass minted a fresh
`input convoy for tk-p82tvo` every 2–3 minutes — the order's own interval — and
47 stray open convoy husks had accumulated by the time the arm was disarmed by
hand (visit tk-y7nugp). One of those slings finalized far enough to pour a whole
`mol-polecat-work` molecule (root `tk-hlrdix`, convoy `tk-akzq3f`), which a
polecat then held at load-context as a duplicate.

## Root cause, in two layers

**gascity — `gc sling` mints an input convoy on every call.** A pool sling of a
bare bead auto-creates an input convoy to carry the pour (the `--no-convoy`
flag opts out). So every reconcile sling of the armed bead created one convoy,
whether or not the pour behind it finalized. This is the object that leaked.

**gc-toolkit — reconcile re-slung that bead every pass with no memory.** Two
gaps in `cmd_reconcile` let the sling repeat unboundedly:

1. **No already-delivered guard.** `bd list --ready` answers open, unblocked
   beads. `tk-p82tvo` was open (its PR had not merged) and unblocked (the
   blocker had closed), so it read as ready and dispatchable, and its
   `gc.routed_to` was empty. Nothing in reconcile noticed that `merge_result`
   was already set — that the work this arm existed to start had already been
   produced. `cmd_arm` guards arm-time against an already-dispatched bead, but
   the world changed *after* the arm was recorded, and reconcile re-checked
   none of it.

2. **The failure rollback erased the attempt.** On a sling that returned
   non-zero, reconcile unset the `gc.dispatch_when_ready_slung` marker and left
   the arm. The next pass then saw a bead with an empty marker, ready and
   unassigned — indistinguishable from a first attempt — and slung again. With
   the marker rolled all the way back to empty, reconcile had no record that it
   had just failed, so it retried forever, one convoy per pass.

The two compose into the leak: a stale arm that can never finalize, retried with
no backoff, on a `gc sling` that leaves a convoy behind each time.

## Fix (reconcile side)

Both guards keep the arm rather than retire an unproven dispatch, so ready work
is never silently lost.

- **Already-delivered retire.** Before slinging a ready bead, if it carries a
  `merge_result` delivery stamp, retire the arm the way a proven `slung@` marker
  does. The dispatch this arm wanted already happened; there is nothing to lose,
  only a redundant pour to stop. This alone would have prevented every one of
  the 47 leaks, because `tk-p82tvo` carried `merge_result=pull_request`
  throughout.

- **Bounded retry.** A `gc.dispatch_when_ready_fail_count` counts sling
  attempts; the pre-sling stamp write bumps it, so a failure or a death both
  leave it raised, and `disarm` clears it so a proven dispatch resets the
  budget. Once the count reaches `MAX_SLING_FAILURES` (`GC_MAX_DISPATCH_SLING_FAILURES`,
  default 3), reconcile stops re-slinging, escalates once through `escalate.sh`
  (deduped on `deferred-dispatch-sling-failed.<id>`), and leaves the arm for a
  person. The leak is bounded to at most the cap by construction, whatever the
  cause of the non-finalizing sling. Modeled on `record-failure-cap.sh`, the
  same pattern merge.sh uses for its record retry.

`cmd_list` surfaces both states (`DELIVERED`, `CAPPED`) so a stuck arm is
visible without reading the sling logs.

## Sweep

- Reaped the held duplicate molecule `tk-hlrdix` (root plus nine steps, 10
  beads) with `gc convoy delete tk-hlrdix --force`, which closes the whole tree
  with `gc.outcome=skipped`. A partial close would have made workspace-setup
  ready and let a polecat rebuild a duplicate PR; the whole-tree close cannot.
  The work is delivered on PR #812, so the duplicate owed nothing.
- Closed all 48 stray `input convoy for tk-p82tvo` convoy husks with
  `gc convoy close` — 47 bare convoy beads plus `tk-akzq3f`, the convoy that had
  carried `tk-hlrdix`. Re-surveyed to zero.

## Residual and related

- **gascity follow-up.** `gc sling` leaving an orphan input convoy when the pour
  behind it does not commit is the deepest cause. The reconcile fix bounds how
  often a failing sling is retried, but a genuinely-failing sling still leaks up
  to the cap before escalation. A transactional convoy — created only once the
  pour commits, or rolled back on failure — would remove the leak at its source.
  Tracked in gascity as gc-zh5fp.
- **tk-ngh2tn** asked for a two-state slung marker so a crash mid-dispatch
  re-slings rather than silently retiring the arm. That marker
  (`slinging@`/`slung@`) already landed under tk-b5g1pw, with tests covering the
  crash-before-sling path, so tk-ngh2tn is resolved; this bead's fix sits beside
  it and does not replace it.
