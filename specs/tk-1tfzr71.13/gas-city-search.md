---
name: Gas City search for recording a disposition in bd's own edges
description: What tk-1tfzr71.13 looked for in bd and Gas City before moving a bead's successor from the pack's gc.superseded_by and duplicate_of keys onto bd's duplicates and supersedes edges, why the pack composes bd's checked close and its dep add instead of calling bd duplicate or bd supersede, and why the duplicate sweep goes with no replacement. Read it when judging bead-rehome.sh's warrant, a reader of $DISPOSITION_JQ, or a proposal to call bd duplicate or bd supersede directly.
---

# Gas City search for recording a disposition in bd's own edges

bd was read at `gastownhall/beads` 7ef2fd05e (the v1.3.4 release merge, which
the city's `bd` reports as `1.3.4 (7ef2fd05e+patched)`). Gas City was read at
`gastownhall/gascity` main 70583dada. The live stores were read on 2026-11-06
between 23:20Z and 23:55Z.

## What was decided

| The bead's part | Outcome |
|---|---|
| The successor keys (`gc.superseded_by`, `gc.supersedes`, `duplicate_of`, each with its `_store`) | Retired. A disposed bead names its successor through one outgoing bd edge, `duplicates` onto its canonical or `supersedes` onto the bead that carries its work, or under not-needed onto the evidence. The keys stay registered as retired, so residue on a bead disposed before the edges reads as known. |
| `bead-rehome.sh` | Stays the one writer, with the same interface. It closes through bd's checked close and then records the edge, both described below. It drops the metadata stamp, its read-back and the back-pointer on the successor. |
| The readers | Read the edge through one jq definition, `$DISPOSITION_JQ` in `bd-lib.sh`, and `bd_disposed_to` where the successor may sit in another rig's store. |
| `duplicate-sweep.sh` and its cadence arm | Deleted, both passes. A polecat that finds its work bead duplicates another closes it at once through `bead-rehome.sh --kind duplicate`, which reverses "never close the work bead" for that one case, in the same change. |

## What bd provides, and where it stops

`bd duplicate <id> --of <canonical>` and `bd supersede <id> --with <new>` are the
primitives the bead names. Both are in `cmd/bd/duplicate.go` (`runDuplicate`,
`runSupersede`). Each adds the edge, `types.DepDuplicates` or
`types.DepSupersedes`, and then closes the bead through
`store.CloseIssue(ctx, id, "", actor, "")`. Three things keep the pack from
calling them as they stand:

- **The close is unchecked.** `CloseIssue`
  (`internal/storage/dolt/issues.go`) closes whatever blocks the bead. The
  checked close is `CloseIssueChecked` beside it, which refuses a live direct
  blocker and an open child in the same transaction. So `bd duplicate` would
  close a bead an open human gate still holds, or one with an open child. The
  pack's finalize precondition (`docs/finalize-gate.md`) forbids both.
- **The close records no reason.** The reason argument is `""`.
- **The far bead must be in the same store.** Both resolve it with
  `utils.ResolvePartialID` and `store.GetIssue` in the one store, and refuse
  otherwise (`canonical issue not found`, `replacement issue not found`). A
  re-home into another rig is a normal disposition here. Of the beads carrying
  the key on 2026-11-06, 23 of the gc-toolkit store's 814 and 92 of
  loomington's 93 name a bead in another rig.

Both also refuse in proxied-server mode (`usesProxiedServer`).

So the pack composes two of bd's primitives that do cover the need:

- **The checked close is `bd update --status=closed`.** Without `--force` it
  refuses open children and a live blocker. The flag's own help says so
  (`cmd/bd/update.go`, the `force` flag: "let -s/--status move the issue into
  closed ... despite open children or a live blocker (same as bd close
  --force)"). `--if-status` and `--if-assignee` make it a compare-and-set on
  what the writer judged, and a mismatch exits `ExitGuardMismatch` (13). So a
  second closer racing the first writes nothing. `bd update` cannot set a close
  reason, so the disposition's sentence rides the same write as an appended
  note.
- **The edge is `bd dep add <id> <successor> --type duplicates|supersedes`.**
  This is the same edge `bd duplicate` and `bd supersede` record. It accepts a
  far bead in another store and keeps it unverified in `depends_on_external`.
  `bd list --json` returns that edge in the row's `.dependencies` (`type`,
  `depends_on_id`), and `bd show --json` and `bd dep list` leave it out. This
  was seen live on tk-7b1g53j, whose edge names gc-7eevlv. So a reader that must
  follow a cross-store edge reads the list row (`bd_disposed_to`).

`bd close` applies three refusals that `bd update` does not:
`validateIssueClosable` (`cmd/bd/show_unit_helpers.go`) chains `NotTemplate`,
`NotPinned` and `AssigneeMatches`. The update path refuses a template itself.
`bead-rehome.sh` reads the pin and the assignee off the bead before it writes
anything (`close_guard`), so a close it starts is one `bd close` would also
allow.

The close and the edge are two writes, because bd offers no checked close that
records an edge in the same transaction. The close goes first. A close that is
held, refused or raced then leaves no edge, which a reader could take for a
disposition. A close whose edge then fails to write leaves the bead closed,
with its note naming the successor. The writer exits 4, and the same call run
again records the edge on the closed bead. `doctor/check-closed-implies-landed`
reports such a bead when it is an anchor.

## What Gas City provides, and where it stops

- **gc forwards every verb the writer uses.** On a split city `gc bd` is an
  allowlist (`cmd/gc/bd_split_allowlist.go`, `bdSplitAllowlist`). It forwards
  `update` (judged), `dep add` and `link` (`judgeBdEdgeVerb`: "every endpoint
  must be a work-store bead"), `dep remove`, `duplicate` and `supersede`. On a
  split city an edge onto another rig's bead is refused, so there a cross-rig
  disposition closes and then exits 4. Loomington is not a split city.
- **The work-record close gate counts this close.**
  `workRecordCloseTargets` (`cmd/gc/work_record_gate.go`) counts `close` and an
  `update` that moves the status to closed, and neither `duplicate` nor
  `supersede`. So the writer's close meets the same gate as any other close.
- **Nothing in Gas City reads a duplicate marker or closes duplicates later.**
  The pack's sweep was the only reader of `duplicate_of`.

## Why the sweep goes with no replacement

The marker pass closed a bead a polecat had marked `duplicate_of`, because a
polecat never closed its work bead. bd's own `duplicates` edge needs no later
pass: the bead closes when the duplicate is found. The cost is that a duplicate
of a canonical still open closes at once. The sweep waited for the canonical to
close or ship first. The canonical carries the work either way, so nothing that
was waiting is lost.

The rework-twin pass closed a never-dispatched second rework child of one
source, once a sibling had landed. The gc-toolkit store records eight such
closes. All eight twins were created between 2026-09-18 and 2026-09-22, and the
last was closed on 2026-10-09. #801 (2026-09-20) and #945 (2026-10-03) each
fixed a way the filer created a second rework child for one review. Since
then the filer adopts a live child of the same source instead of filing
another, so no twin has been filed since 2026-09-22. A twin can now come only
from a race between two filings of one source, and a person or a sitting
closes it as a duplicate through `bead-rehome.sh`.

The cut-over of the beads the keys already describe is in
[cut-over.md](cut-over.md).
