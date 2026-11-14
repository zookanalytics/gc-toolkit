---
name: Gas City search for a stay on work that runs on the conversation's own subject
description: Use when you review the stay converse-signoff.sh writes when its --waiting-on names the conversation's own subject, or converse-entry.sh's reading of that stay, and need the Gas City and bd primitives it composes, why the conversation waits on the convoy the subject's dispatch poured its run over rather than on the subject, the run's root, a session wait, a bead gate or a convoy of the pack's own, and what the controller's sweep leaves open.
---

# Gas City search: a stay on its own subject

A sitting the operator asks to stay sleeps until the work it sent closes, and
then compares what landed with what was agreed. Its conversation waits on that
work through bd `blocks` edges, one onto each bead of it. When the ruling's work
is the subject itself, sent on a formula or taking its recommendation, there is
no edge to write: the conversation already tracks the subject. This record names
what the stay composes instead and what it looked at first.

Gas City citations are at upstream `gastownhall/gascity` commit `cf33557276ef`.
The installed build, `6589a7df45`, holds the same functions. bd citations are at
upstream `gastownhall/beads` commit `1d22ef9be218`.

## What it composes

- **The input convoy of the subject's dispatch.** A graph.v2 sling of a bead
  pours its run over a convoy that tracks that bead alone:
  `graphv2.NormalizeInputConvoy` calls `graphv2.CreateSingleItemInputConvoy`
  (`internal/graphv2/invocation.go`) for a bead target, which creates a bead of
  type `convoy`, titled `input convoy for <id>`, with no `owned` label, and one
  `tracks` edge onto the bead. Accept's dispatch is such a sling, and so is the
  sitting's own `gc sling <rig>/<pool> <subject> --on <formula>`.
- **Gas City's close of a convoy.** `doConvoyAutocloseWith`
  (`cmd/gc/cmd_convoy.go`) finds every convoy that tracks a bead that closed
  (`internal/convoy/membership.go`, `trackingConvoys`) and closes each one with
  no `owned` label whose members have all closed (`convoyStillAutocloses`,
  `closeCompletedConvoyAcross`). The controller runs it on each `bead.closed`
  (`beadCloseAutoclose`, `cmd/gc/api_state.go`), and its autoclose sweep retries
  a run that did not finish (`cmd/gc/autoclose_sweep.go`).
  [`gc convoy check`](https://docs.gascity.com/reference/cli#gc-convoy-check)
  closes any open convoy whose children have all closed. So the input convoy
  closes when the subject does, whatever became of the run: Gas City's run
  cancel closes the root and the members under it and leaves the convoy, which
  is no member of the root, open (`cancelRun`,
  `internal/api/huma_handlers_runs.go`).
- **bd's `blocks` edge, as the wait.** The conversation's edge onto that convoy
  holds it out of bd's ready work until the convoy closes. The convoy's close is
  a `bead.closed` like any other: this city's event log has one for the convoy
  `tk-0aqclln`, 6 s after the one for the bead it tracked. So the wake and the
  `cascade-nudge-on-blocker-close` notice reach the sitting as they do for any
  other stay's work.

Measured on this city's gc-toolkit store on 2026-11-14: over the last 7 days,
1109 convoys closed by autoclose, 20 s after the last bead they tracked closed at
the median, 48 s at the 90th percentile and 69 s at the most. All 35 open
convoys tracked a bead that was still open.

## What was searched and does not cover the need

- **An edge from the conversation onto the subject.** bd keeps one edge from a
  bead onto another and refuses a second type for the pair
  (`DependencyTypeConflictError`, beads `beads.go` and
  `internal/storage/domain/dependency.go`). The conversation's `tracks` edge
  holds that pair, and every reader of a conversation's shape finds the
  conversation by it, so it stays.
- **A session wait.**
  [`gc session wait <session> --on-beads <ids>`](https://docs.gascity.com/reference/cli#gc-session-wait)
  watches a bead's close. But `WakeSession` (`cmd/gc/cmd_session_wake.go`)
  cancels every wait of a session it wakes, and an attach to a sleeping sitting
  wakes it, so the first time the operator looks in, the stay would be gone.
- **A bd gate of type `bead`.** bd's `gate check --type=bead` would close it,
  but core's `gate-sweep` order runs `gate check` for `timer` and `gh` gates only,
  and its script says bead gates are skipped
  (`internal/bootstrap/packs/core/assets/scripts/gate-sweep.sh`). Nothing would
  close one.
- **The run's root.** A root closes when its own steps finish, which for
  `mol-polecat-work` is the hand-off to the refinery, before the merge closes
  the subject. A stay on it would come back before anything landed, while every
  other stay comes back when its work closes.
- **A convoy of the pack's own.** One filed for the stay would close the same
  way. But the helm city board lists every convoy whose title is not a machine
  convoy's (`admitConvoy`, `services/helm/internal/source/beads.go`) and marks
  one without the `owned` label as an orphan, "unowned convoy — no owning bead",
  at high severity. A convoy filed per stay would put that false alarm on the
  board for every such stay, and the `owned` label that would stop it also stops
  Gas City from closing the convoy. The input convoy carries the title the board
  and the liveness classifier read as machine, so composing it adds nothing the
  operator sees but the conversation's "Waits on" the convoy.
- **New work that both the subject and the conversation wait on.** That changes
  which bead a recommendation's formula runs on, which is the operator's call,
  as the bead's description says. This change leaves it to them.

## What the change adds

No script, verb, key, bead kind or state. The sign-off's `--waiting-on` takes
the subject beside `--stay`, where it refused it before, and the entry reads a
`blocks` edge onto a convoy that tracks the subject as the stay's wait on the
subject.

## What it leaves in place

- **A close the controller does not see.** The autoclose sweep diffs each live
  cache against its previous pass, and its first pass after a start only seeds
  the census, so a bead that closes while the controller is down never has its
  convoy closed by it (`cmd/gc/autoclose_sweep.go`, "Known limits", which names
  the fix as deriving autoclose from journal operations). The convoy then stays
  open until `gc convoy check` closes it, and the sitting sleeps until then. The
  cause is Gas City's, and the pack adds no sweep for it.
- **The order of a sitting that sends the subject.** The dispatch must exist
  before the stay waits on its convoy, and a run whose bead is still held by a
  gate is declined by its own load-context (`work-gate.sh`). So that sitting
  answers the ruling's gates on a turn that does not sign off, sends the
  subject, and then stays. A stay with no convoy to wait on and no `--accept` is
  refused before any write.
