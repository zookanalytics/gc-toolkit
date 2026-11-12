---
name: Gas City search for a sitting that stays until its work returns
description: Use when you review the stay that converse-signoff.sh's --stay writes and need the Gas City and bd primitives it composes, the session wait it does not use and why, and why its surface is a mode of the sign-off and a notes line rather than a store, a key or a service of its own.
---

# Gas City search: a sitting that stays until its work returns

A sitting the operator asks to stay must sleep with its conversation open and
wake, with that conversation, when the work it sent closes. The change adds one
mode to an existing writer, `converse-signoff.sh --stay`, and one line in a
conversation's notes, `staying:`. Everything that sleeps and wakes the sitting
is Gas City's or bd's. Each Gas City citation is at upstream
`gastownhall/gascity` commit `6bd609f5bf`, whose files named here match the
installed build, and [stay-probe.md](stay-probe.md) ran each one.

## What it composes

- **bd's `blocks` edge, as the wait.** The conversation waits on the work through
  `gc bd dep add <conversation> <work> --type blocks`, and bd's ready work leaves
  out a bead that an open blocker holds. In the probe, `bd ready` listed the
  work and not the conversation while the work was open.
- **Gas City's assigned-work demand, as the wake.** A session with in-progress
  work, or ready open work assigned to it, is wanted awake, and open work counts
  only with `Ready=true` (`cmd/gc/compute_awake_set.go`, the "Sessions with
  assigned work" pass at 453 and `workBeadHasAwakeDemand` at 955). Readiness is
  the store's verdict, not a guess from the status (`cmd/gc/compute_awake_bridge.go`
  at 180). So the work's close makes the open conversation ready work assigned to
  the sitting's alias, and that wakes the sitting.
- **Gas City's idle sleep, as the sleep.** `sleep_after_idle` sleeps a session
  that holds no claimed work and has no client attached. A claimed in-progress
  bead vetoes it, and a blocked open assignment does not
  (`cmd/gc/compute_awake_set.go`, the comment at 647 to 650 and
  `holdsClaimedWork` at 671). So the stay drops the claim, putting the
  conversation back to `open` under the alias, and the sitting sleeps once no
  tab is attached. An attached client keeps it awake (the attached override at
  601).
- **`wake_mode = "resume"`, as the thread.** The woken session relaunches on its
  session key, and the probe found its thread intact after each wake.

## What it does not use, and why

**`gc session wait <session> --on-beads <ids> --note <text> --sleep`**
(`docs/reference/cli.md` at 5033, `cmdSessionWait` in `cmd/gc/cmd_wait.go` at
301) registers a wait bead, sets a wait hold that stops the session, and wakes
it with a `Wait satisfied` reminder once the beads close. It covers the sleep and
the wake, and the probe ran it. A sitting does not use it, because the wake path
that an attach to a sleeping session runs cancels every wait of the session
(`wakeSessionFromBead` in `internal/session/wait_store.go` at 606, which calls
`cancelWaitsAndCollectNudgeIDs`). An operator who looks in on a staying sitting
would cancel its wait. The sitting would then hold its claimed conversation,
which vetoes the idle sleep, so it would never sleep again until it registered
the wait anew. The edge outlives any attach, and the sitting sleeps again on its
own once the tab detaches. The session wait does reach a bead in another rig's
store, which a `blocks` edge cannot, so a sitting whose work is in another store
ends at the hand-off.

**A watch of its own** (a sweep or an order that wakes a sitting when its work
closes) would duplicate the assigned-work demand above, so none is built.

## The surface it adds, and why

- **`converse-signoff.sh --stay "<text>"`.** The stay must write everything a
  sign-off writes, the subject's headline and wait, its close brief, its
  validating closer's arm and the answers to the gates, so the record stands if
  the sitting never returns. The sign-off is the one writer of those, in one
  order. Its `--answer` mode keeps the conversation open but takes a gate to
  answer, and many conversations reply to none. So `--stay` runs the sign-off's
  writes and, in place of the close, writes the edge, the notes line and the
  guarded status write above. It adds no store, no metadata key, no lifecycle
  state and no bead kind.
- **The `staying:` notes line.** A woken sitting's claim answers `drain` while
  the work is out and `ready_assignment` once it lands, which is what a fresh
  sitting reads too. So the converse prompt's restart rule reads the newest of a
  conversation's `holding:` and `staying:` lines, as it reads `holding:` today.
  It is a line in bd's notes, not a key.
- **Two readers learn the state.** The per-rig board reads a conversation that a
  wait of its own holds as no ask, through the wait reader it already runs
  (`services/gctk/waits`). `gc-helm engage` attaches an asleep sitting at once,
  through `gc session attach`, which wakes it. Neither adds a verb or a key.
