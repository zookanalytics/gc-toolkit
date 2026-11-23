---
name: Gas City search for the takeaway's command
description: The Gas City and bd primitives read for `gctk bead takeaway`, the command that writes a bead's headline and with --release takes the bead out of play or sends it on, what each covers at a named upstream commit, and the gap the command fills by composing them. Read it to review the command's surface, or before changing what a release writes.
---

# Gas City search for the takeaway's command

Read on 2026-11-20 at `gastownhall/gascity` main b31d0b1194. The command moves
`gc-helm.sh takeaway` into gctk unchanged (design decision 5 of
`specs/tk-1tfzr71.213/design.md`), so the need is what that verb does, and the
search starts where section 8 of that design says it starts: bd's guarded
update for the release.

## The need

One act records what a bead's handling concluded, as a one-line headline with
who wrote it and whether anything still waits, and can take the bead out of
play in the same act: stop a run beneath it, stop an arm from starting it
again, reopen it unassigned and routed to no pool, or send it on to a pool or a
named agent. A close or a claim that lands after the act reads the bead must
still stand, and a claim a live session holds must not be taken.

## What was searched

- **bd's guarded update.** `gc bd update --if-status --if-assignee` writes
  nothing and exits 13 when the bead has left the status or the assignee named.
  `bdstore_conditional_release.go` documents it as
  `bd update <id> --if-assignee <expected> --if-status in_progress --status open --assignee ""`.
  It covers the guard, and the command composes it: the release is one such
  update carrying the headline, the reopen, the route and session pins cleared
  and the hold label lifted.
- **`gc bd release-if-current <issue-id> <assignee>`** (`gc bd` in
  `docs/reference/cli.md`, `BdStore.ReleaseIfCurrent` in
  `internal/beads/bdstore.go`). It resets an in-progress assignment only while
  the bead still has that assignee, through the guarded update above with
  `--status open --assignee ""` and nothing else. It does not cover the need:
  it writes no headline, leaves the bead's route and session pins, which offer
  it to its pool again, guards only an in-progress bead, so it skips an open or
  hooked one, and ends no run.
- **Gas City's run cancel**, `POST /v0/city/{cityName}/runs/{run_id}/cancel`
  (`humaHandleRunCancel` in `internal/api/huma_handlers_runs.go`). It closes the
  run's root and every member that is not closed, and interrupts the sessions
  that hold one. It covers the run's end, and the command composes it through
  the pack's `run-cancel.sh`, the city's one caller of the route. No `gc`
  command cancels a run.
- **`gc sling <target> <bead> --no-formula --no-convoy`** (`gc sling` in
  `docs/reference/cli.md`): it routes a raw bead to a target, pouring nothing and
  filing no convoy. It covers sending a released bead to a pool, and the command
  composes it once the run beneath the bead has ended.
- **`gc session nudge --delivery immediate`** (`gc session nudge` in
  `docs/reference/cli.md`): it reaches a running turn where the session's
  runtime can steer. It covers asking a live holder to give the bead back, and
  the command composes it. The city's build also carries `--reference-bead` from
  its fork, which collapses repeated nudges about one bead.
- **`gc session list --json`** (`gc session list` in `docs/reference/cli.md`),
  which lists every session that has not closed. It covers telling whether a
  claim's holder is gone, and the command reads it before it names a holder in
  its guard.
- **A headline on a bead.** Neither bd's fields (title, description, design,
  acceptance criteria, notes) nor Gas City's metadata keys hold a one-line
  conclusion with its writer. The takeaway's keys stand in for it, and design
  decision 5 keeps them until tk-1tfzr71.216 decides whether they retire onto
  the bead's notes or stay with a warrant.

## Why the command

No primitive takes a bead out of play whole. Gas City's pieces each cover one
part, and the command adds what they leave to a caller: the order that keeps a
stop safe (the arm removed first, the guarded update, the run's end, then the
sling), the read of which change a refused guard met, the refusals that keep a
bead from being sent where no one can work it, and the headline in the same
write as the release. The arm's removal is `gctk bead disarm`, the pack's own
verb, since the arm is the pack's residual
([warrants.md](../../docs/warrants.md#deferred-dispatch-residual)).
