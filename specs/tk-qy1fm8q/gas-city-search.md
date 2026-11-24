---
name: Gas City search for the first reaction's marks (tk-qy1fm8q)
description: The primitives searched in Gas City and bd for the surface this build adds, the `gctk reaction unmarked` list and `gctk bead place`'s refusal of a bead a live first reaction works, with what each covers and why each gap is gctk's. Read it when reviewing that surface, as AGENTS.md asks of a change that adds a command or grows one.
---

# Gas City search for the first reaction's marks

This build changes which beads take a first reaction: the sweep takes a bead by
a mark its filer wrote, and the check admits a held bead that carries no
headline. It adds one gctk verb, `gctk reaction unmarked`, and one refusal in
`gctk bead place`. It adds no order, no bead key, no bead kind and no lifecycle
state: `finding.scope` is a key `patrol-finding.sh` already writes, which gctk
now reads. Each need names the primitive searched, at `gastownhall/gascity`
main 9285cfb3ed (2026-11-24) and bd v1.3.4, the `github.com/steveyegge/beads`
version Gas City's go.mod requires.

## List the beads filed with no mark that nothing claims

The po's backlog refinement needs the open beads in a rig's store that carry no
mark a first reaction reads and that no owner, route, arm, hold, wait or run
claims.

**Covered in part: bd's ready read.** `bd ready` (cmd/bd/ready.go) answers
readiness, which is "no wait", and its `--unassigned` and `--exclude-type`
flags answer "no owner" and "no epic". The list is that read, the same one the
sweep makes, and gctk filters its rows.

**Not covered: the rest of the filter.** `bd ready` selects on a label's exact
text (`--exclude-label`) or on a key being set (`--has-metadata-key`,
`--metadata-field`), and on neither key's absence nor a label in any case. The
list needs a bead with no `hold:mayor` in any spelling Gas City's
`HasDispatchHold` (internal/beadmeta/hold_labels.go) reads as the hold, no
`finding.scope`, no route, no arm, no parent, and none of the keys machinery
carries. Gas City's `gc beads list` (cmd/gc/cmd_beads.go) filters by one exact
label, a status and an assignee, and has no absence filter either.

**Not covered: whether a live run works a bead, for a whole list.** Gas City
answers it per source bead: `sourceworkflow.ListLiveRoots`
(internal/sourceworkflow/sourceworkflow.go) lists the live workflow roots whose
`gc.source_bead_id` names one bead. No command lists every bead a live run
works. gctk's `waits.LiveRuns` already reads the store's live roots once for the
sweep, and the list reuses it.

So the list is a gctk verb over the sweep's read, in the reaction package that
holds the marks, and it starts no work, which a pack script could not keep in
one rule with the sweep.

## Keep a placement from lifting a hold while a first reaction runs

**Covered: Gas City's source-workflow singleton, which decides the conflict.**
`gc sling` refuses a graph workflow on a source bead that already has a live
workflow root, whatever that root's formula, with exit 3
(`ConflictError` in internal/sourceworkflow/sourceworkflow.go, raised by the
prelaunch check in internal/sling/sling_core.go, which lists the bead's live
roots through `ListLiveRoots` with no formula filter). `--force` closes the
live root first. So `gctk bead place`, which read a first reaction's run as no
dispatch and slung its formula, met that exit 3 while a reaction ran, read it
as a live run of its own formula and lifted the hold with nothing sent.

**Not used: `--force`.** It would close the reaction's run under a worker that
may still be writing its exit, and that exit's takeaway release ends every live
run beneath the bead that its own session does not hold, the placement's new
run among them.

So `place` reads the runs it already reads and refuses a held bead a live first
reaction works, with nothing written. Its refusal names the run and the
placement to run once that run has ended.
