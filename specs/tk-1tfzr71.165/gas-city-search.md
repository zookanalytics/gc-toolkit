---
name: Gas City search for the refinery's wake on a changed head
description: The Gas City primitives searched for the landing order's wake of the refinery, for a PR's changed head on the pending record while a conversation holds the PR's bead, what each does at a named upstream commit, and why none covers the need. Read it when changing or reviewing that wake, or when the arch check asks for the search.
---

# Gas City search for the refinery's wake on a changed head

Read on 2026-11-16 at `gastownhall/gascity` main 192fa2d394 and
`gastownhall/gascity-packs` main 0f07496d2f. The bead's own analysis read Gas
City at c7eb6d2f43ca, and `git diff c7eb6d2f43ca 192fa2d394` over every Gas City
file cited here changes only two of the core pack's provider overlay pages.

## The need

On the pending record, the landing order sends a PR's changed head back to the
refinery: the bead goes open, `merge_result=pull_request_head_changed`, still
assigned to the refinery (`Requeue` in `services/gctk/pr/record/record.go`).
The refinery takes such a bead at its patrol's find-work once nothing but
conversations and asks holds it (`assets/scripts/refinery-find-work.sh`), and
it needs a turn to run find-work. A conversation on the PR holds the bead
through a `blocks` edge, which holds the PR's merge and nothing else, and an
ask on the PR holds the merge the same way until a review run answers it.
While either is open, the changed head becomes the refinery's to take at one
of two moments: when the landing order requeues it with no review run attached
and no withdrawal open, or when the review run or the withdrawal that held it
ends. The need is a turn for the refinery at that moment, while the
conversation or the ask is still open.

## What was searched

- **A session's demand.** Gas City keeps a named session awake for the work
  assigned to it. An open bead counts only while the store reads it ready, and
  an in-progress one only while it is not blocked (`workBeadHasAwakeDemand` in
  `cmd/gc/compute_awake_set.go`). The readiness is the store's verdict, which
  folds in the bead's open blocking dependencies (the work-bead loop in
  `cmd/gc/compute_awake_bridge.go`). The open `blocks` edge onto a conversation
  or an ask keeps the bead from reading ready, so the bead is no demand for the
  refinery while either is open.
- **Core's cascade nudge.** The core order `cascade-nudge-on-blocker-close`
  runs on `bead.closed` and nudges each open dependent's assignee, but only when
  no other blocker still holds the dependent once the closed one has closed
  (`still_held` in
  `internal/bootstrap/packs/core/assets/scripts/cascade-nudge-on-blocker-close.sh`).
  When the review run's root closes, or the withdrawal does, the conversation
  or the ask still holds the bead, so the script records the pair as handled
  and sends no nudge. The last of their own closes is the one it reports, and
  a conversation's can be hours later.
- **A session wait.** `gc session wait <session> --on-beads <ids> --note <text>`
  registers a wait on the beads named, and Gas City wakes the session and
  delivers the note once they close (`doSessionWait` in `cmd/gc/cmd_wait.go`,
  and `dispatchReadyWaitNudgesWithSnapshot` in the same file). It could watch a
  review run's root, but it does not cover the need, for two reasons. A requeue
  with no run attached has nothing to watch, since its head is the refinery's
  to take at once. And a wait on the refinery does not last: `gc session wake`
  cancels every open wait of the session it wakes (`Store.WakeSession`, through
  `wakeSessionFromBead`, in `internal/session/wait_store.go`, which
  `doSessionWake` in `cmd/gc/cmd_session_wake.go` calls), and every polecat's
  hand-off to the refinery runs `gc session wake` on it
  (`assets/scripts/work-submit.sh`).
- **An event order.** An exec order on `bead.closed`, the trigger the cascade
  nudge uses, could see a review run's root close, but not a requeue with no run
  attached. It would be a second order beside the landing order, which already
  reads both moments.

## What the change composes

The landing order already reads the bead's blockers and its attached review
runs under the record lock on each run, and it keeps the record's marker while
a withdrawal is open, so a later run carries the withdrawal out. The change
keeps the marker while a review run is attached too, so a later run reads the
run's end. Gas Town's requeue clears the marker in its own write
(`requeue_changed_open_head` in `gastown/commands/pr-merge-reconcile/run.sh`),
so the record departs from Gas Town's here, as it already does for a
withdrawal. When only conversations and asks hold the bead at the moment its
changed head becomes the refinery's to take, the run wakes the refinery and
nudges it before the write that clears the marker. The wake is the two calls a
polecat's hand-off makes, `gc session wake` and `gc session nudge`, each as
`docs/reference/cli.md` documents it. A nudge to a session that is asleep, or
not yet at a safe boundary, is queued (`gc nudge` in `cmd/gc/cmd_nudge.go`).
When nothing holds the bead, the change wakes no one, because the demand and the
cascade nudge above give the refinery its turn.
