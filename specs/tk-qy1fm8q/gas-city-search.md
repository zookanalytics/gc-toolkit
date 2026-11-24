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

## Keep a first reaction's exit from undoing a placement

**Searched: Gas City's per-bead launch lock and its duplicate guard.**
`gc sling <bead> --on <formula>` launches under a per-bead lock
(`withGraphV2SourceWorkflowLock` in internal/sling/sling_core.go, over
`sourceworkflow.WithLock` in internal/sourceworkflow/sourceworkflow.go) and
refuses only a second live root of the same formula
(`checkLegacySourceWorkflowConflict` there: "distinct formulas concurrently
targeting one bead are legitimate", #5432). It passes over a live workflow
attachment (`checkNoMoleculeChildren` in internal/sling/sling_attachment.go).
That is `gastownhall/gascity` main d6d5784f9c, and the city's gc build,
03d08fa593, carries #5432. So a live first reaction never stops a placement's
build, and the lock is released when the launch returns.

**Not covered: a decision of several writes.** A placement writes from its
read to its hold's lift, and a first reaction's exit from its read to its
release, which ends every run under the bead, removes its arm and parks it. An
exit that read the bead before a placement sent it on would undo that
placement, and Gas City's lock covers neither sequence.

So a placement and an exit hold the bead's acceptance lock, the one
`gctk reaction accept` holds (docs/warrants.md, "Accept's lock"), each from
its read to its last write. An exit that finds a dispatch it did not make, a
live run of another formula, a route, an arm or an assignee, lands its
headline alone. A placement goes out whether or not a reaction runs.
