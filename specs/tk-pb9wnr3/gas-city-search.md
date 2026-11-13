---
name: Gas City search for a sitting that stays until its work returns
description: Use when you review the stay that converse-signoff.sh's --stay writes, or the entry converse-entry.sh gives a sitting, and need the Gas City and bd primitives they compose, the native signals the entry looked for and why none tells a return from a fresh sitting, the session wait the stay does not use and why, and why the surface is a mode of the sign-off, a notes line and one read script rather than a store, a key or a service of its own.
---

# Gas City search: a sitting that stays until its work returns

A sitting the operator asks to stay must sleep with its conversation open and
wake, with that conversation, when the work it sent closes. The change adds one
mode to an existing writer, `converse-signoff.sh --stay`, and one kind of line in
a conversation's notes, `staying:`. Everything that sleeps and wakes the sitting
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
  answer, and many conversations reply to none. So `--stay` writes its notes
  line before anything else, runs the sign-off's writes and, in place of the
  close, writes the line again naming the work, then the edge and the guarded
  status write above. It adds no store, no metadata key, no lifecycle state and
  no bead kind.
- **The `staying:` notes line.** A woken sitting's claim answers `drain` while
  the work is out and `ready_assignment` once it lands, which is what a fresh
  sitting reads too. So the sitting's entry reads the newest of a
  conversation's `holding:` and `staying:` lines (The entry, below). The stay
  writes `staying: <what was agreed>` before every other write, so a restart
  anywhere in the call reads as a stay, and `staying: <what was agreed>
  (waits on <the work>)` once all but the wait has landed. The entry reads a
  stay as waiting or returned only when each bead that second line names has
  the conversation's edge or has closed, since a conversation keeps its edges
  onto the work of a stay that returned. It is a line in bd's notes, not a key.
- **Two readers learn the state.** The per-rig board reads a conversation that a
  wait of its own holds as no ask, through the wait reader it already runs
  (`services/gctk/waits`). `gc-helm engage` attaches an asleep sitting at once,
  through `gc session attach`, which wakes it. Neither adds a verb or a key.

## The entry, and what it reads

A sitting must know, each time its session starts or wakes, whether it has a
new conversation, a restart mid-sitting, work still out after an early attach,
or work returned, and an unreadable state must never read as any of them. The
search looked for a native signal that says so, at the same upstream commit.

- **The claim.** `gc hook --claim --json` answers `work` with reason
  `ready_assignment` for a ready bead assigned to the session, whether a sitting
  takes it up for the first time or its work has just returned: both run the
  assigned-ready tier and its claim (`assignedReadyTierCommand` in
  `internal/config/workquery.go`, the `ready_assignment` result in
  `cmd/gc/cmd_hook_claim.go`). An in-progress bead comes back as
  `existing_assignment` (`hookClaimExistingAssignment`). A bead that waits on
  open work is not served, an in-progress one included
  (`inProgressBlockedByEnrichmentScript` in `internal/config/workquery.go`), so
  the claim answers `drain` with reason `no_work` and exits 1
  (`writeHookClaimNoWork`). The result carries no other hint of why the session
  runs (`hookClaimJSONResult`, `schemas/hook/result.schema.json`). A drain's
  other reasons, the `hookClaimReason*` constants in `cmd/gc/cmd_hook_claim.go`,
  say why it claimed nothing. `drain_pending` comes from a session whose row
  reads draining, and its stderr line names the `gc runtime drain-ack <session>`
  to run (`writeHookClaimDrainPending`). `stale_session`,
  `missing_session_registration` and the city, agent and rig suspensions stop a
  session the hook will not serve. `claims_errored` is ready work whose every
  claim errored (`writeHookClaimNoWork`). Only `no_work` says nothing ready is
  assigned to the session. A stop hands the session no work, giving back a
  claim it had taken (`unwindUndeliveredHookClaim`), so it says nothing about a
  conversation the session holds.
- **The session.** The start environment carries identity and epochs, and no
  wake cause (`RuntimeEnvWithSessionContext` in `internal/session/lifecycle.go`).
  A resume gets the whole startup prompt again as its first input
  (`resumeStartupPromptPlan` in `cmd/gc/startup_prompt_delivery.go`), and the
  prompt's context has no wake field (`PromptContext` in `cmd/gc/prompt.go`).
- **The provider hooks.** Claude's SessionStart hook runs `gc prime` on the
  `startup` matcher only (`internal/hooks/config/claude.json`), so a resume or a
  wake runs none, and what it prints does not vary with how the session started.
- **The notices.** The core order `cascade-nudge-on-blocker-close` nudges the
  assignee of a closed bead's dependent with fixed text, as a reminder held
  until after the turn, so it arrives behind the claim. A session wait's
  `Wait satisfied` notice is cancelled by the attach that wakes a sleeping
  session (`Store.wakeSessionFromBead` in `internal/session/wait_store.go`,
  which calls `cancelWaitsAndCollectNudgeIDs`).

No native signal tells a conversation a sitting first takes up from one whose
work has returned, so the pack reads its own record:

- **`converse-entry.sh`**, one read script the converse prompt runs first. It
  composes the claim above, the conversation's row, `gctk bead holds` for the
  work still open, the newest of the conversation's `holding:` and `staying:`
  lines, which the hold and the stay already write, and the status of a bead
  that newest `staying:` line names with no edge onto it. It prints the
  entry, the conversation's values and the skill to load next, and exits 1
  with `unreadable` when any read fails, so a sitting never drains or closes on
  a state it could not read. It reads the record only on a `no_work` drain or a
  claim. A `claims_errored` drain reads as `unreadable`, and a drain for any
  other reason answers `stop`, which passes on the hook's stderr, so the
  sitting acknowledges Gas City's drain the way Gas City asks. It adds no store, no metadata key, no lifecycle
  state and no bead kind, and it writes nothing but the claim.
  `assets/scripts/converse-entry.test.sh` runs each entry and each unreadable
  case.
