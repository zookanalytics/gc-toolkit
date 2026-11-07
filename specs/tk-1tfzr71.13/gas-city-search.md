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
| `bead-rehome.sh` | Stays the one writer, with the same interface. It records the edge and then closes through bd's checked close, both described below. It drops the metadata stamp, its read-back and the back-pointer on the successor. |
| The readers | Read the edge through one jq definition, `$DISPOSITION_JQ` in `bd-lib.sh`, and `bd_exact_row` where the successor may sit in another rig's store. |
| `duplicate-sweep.sh` and its cadence arm | Deleted, both passes. A polecat that finds its work bead duplicates another closes it at once through `bead-rehome.sh --kind duplicate`, which reverses "never close the work bead" for that one case, in the same change. The beads the duplicate blocks come to wait on its canonical first (below). |

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
  the city store's 93 name a bead in another rig.

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
  was seen live on tk-7b1g53j, whose edge names a bead in another rig's store. So
  a reader that must follow a cross-store edge reads the list row
  (`bd_exact_row`). That read passes `--include-gates`, `--include-infra` and
  `--include-templates`, because bd hides those types from a listing whatever the
  `--id` names (`applyTypeSuppressions`, `internal/workapi/list.go`). `bd list` has
  no one flag for all three: only `bd human` sets `IncludeAllTypes`
  (`cmd/bd/human.go`).

`bd close` applies three refusals that `bd update` does not:
`validateIssueClosable` (`cmd/bd/show_unit_helpers.go`) chains `NotTemplate`,
`NotPinned` and `AssigneeMatches`. The update path refuses a template itself.
`bead-rehome.sh` reads the pin and the assignee off the bead before it writes
anything (`close_guard`), so a close it starts is one `bd close` would also
allow.

The close and the edge are two writes, because bd offers no guarded close that
records an edge in the same transaction. `bd batch` (`cmd/bd/batch.go`,
`runBatchOp`) comes closest: `dep add` and `update <id> status=closed` commit as
one, and that close refuses a live blocker and an open child, but its grammar
takes no `--if-status` or `--if-assignee`, so it cannot make the compare-and-set
that stops a claim or a second closer, and no notes.

The edge goes first, the order `runDuplicate` and `runSupersede` use. So a reader
finds the writer's close with its successor, and so does a second caller, which
would otherwise take a closed bead with no edge for one it may repair, and name
another successor. A reopened bead keeps its edge, so the same
holds after a reopen. bd enforces one edge per pair of beads and none per bead
(`AddDependencyInTx`, `internal/storage/issueops/dependencies.go`), so two callers
that read the bead before either wrote can each add an edge. The writer therefore
reads the edge back before it closes, and a caller that finds another disposition
edge beside its own takes its own back and exits 6. The later writer always reads
both edges, so at most one caller goes on to the close.

A close that is held by what the writer reads first writes nothing. A close bd
then refuses, or that a change since the read beats, takes the edge back, unless
a close naming the same successor is what beat it, since the edge is that close's
record too.

A run stopped between the edge and the close leaves the bead open and naming its
successor, the state main's key left, and the same call run again finishes it.
Readers take that state for a disposition in progress, except two that read a
live bead's `show` row, which leaves out an edge into another store. On such a
bead `converse-rework.sh` can still file a rework, whose blocks edge then refuses
the re-run's close, and the finalize gate's epic clause holds an epic for a
ruling. Each needs a run stopped in that moment with a successor in another store,
and each ends in a refusal, not a wrong close, so both keep their read.

One interleaving still closes a bead with no edge. bd's re-add of an edge is a
no-op, so two callers naming the same successor share one edge, and `bd dep add`
and `bd dep remove` take no compare-and-set. Say a caller has written the edge
when a holder claims the bead and runs the same call, which finds the edge standing
and writes none. The first caller's close then fails on the claim and takes the
edge back, and the holder's close lands just after. The bead is closed and its note
names the successor, but no edge does. This was reproduced against bd 1.3.4 on a
scratch store on 2026-11-07. The same call run again records the edge, and the
doctor reports such an anchor (I5). A read after the close would only narrow this,
since the first caller can still take the edge back after that read, so the writer
leaves it.

## What Gas City provides, and where it stops

- **gc forwards every verb the writer uses.** On a split city `gc bd` is an
  allowlist (`cmd/gc/bd_split_allowlist.go`, `bdSplitAllowlist`). It forwards
  `update` (judged), `dep add` and `link` (`judgeBdEdgeVerb`: "every endpoint
  must be a work-store bead"), `dep remove`, `duplicate` and `supersede`. On a
  split city an edge onto another rig's bead is refused, so there a cross-rig
  disposition exits 4 and closes nothing. The city these stores belong to is not
  split.
- **The work-record close gate counts this close.**
  `workRecordCloseTargets` (`cmd/gc/work_record_gate.go`) counts `close` and an
  `update` that moves the status to closed, and neither `duplicate` nor
  `supersede`. So the writer's close meets the same gate as any other close.
- **Nothing in Gas City reads a duplicate marker or closes duplicates later.**
  The pack's sweep was the only reader of `duplicate_of`.

## Why the sweep goes with no replacement

The marker pass closed a bead a polecat had marked `duplicate_of`, because a
polecat never closed its work bead. bd's own `duplicates` edge needs no later
pass: the bead closes when the duplicate is found. The sweep waited for the
canonical to close or ship first, and that wait also held every bead the
duplicate blocked. bd's ready rule, `AffectsReadyWork` in
`internal/types/types.go`, follows `blocks`, `parent-child`,
`conditional-blocks` and `waits-for` edges and never a `duplicates` edge, so a
duplicate that closes at once would release those beads before the work they
wait for exists. On 2026-11-07, 21 of the gc-toolkit store's closed duplicates
had beads blocked by them, 26 in all.

So `bead-rehome.sh` keeps those waits itself. Before a duplicate of a canonical
that has neither closed nor shipped closes, each open bead it blocks gains a
`blocks` edge onto the canonical, read back, and a waiter that cannot take one
refuses the close. Neither bd nor Gas City moves a bead's waiters:

- `bd duplicate` (`runDuplicate` in `cmd/bd/duplicate.go`) adds the edge and
  closes, and leaves the beads that depend on the duplicate as they are.
- `bd duplicates --auto-merge` (`performMerge` in `cmd/bd/duplicates.go`)
  re-parents only `parent-child` dependents onto the merge target before it
  closes a source, and acts only on groups of identical content it finds itself,
  never on a pair it is given.
- Gas City has no reader of the edge. At `gastownhall/gascity` main 6c9663d4c,
  `duplicates` appears only as the name of bd's verb in the split-city allowlist
  (`cmd/gc/bd_split_allowlist.go`).

`blocks` is the one wait to carry. On 2026-11-07 the city store and the four
live rig stores held no `conditional-blocks` or `waits-for` edge, and the checked
close refuses a duplicate with an open child, which covers `parent-child`. bd
refuses a `blocks` edge onto the bead itself, across a parent chain, into a
cycle, or onto a pair another edge type already joins
(`dependencyUseCaseImpl.add` in `internal/storage/domain/dependency.go`), so
each of those is a refusal the writer reports.

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
