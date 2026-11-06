---
name: Gas City search for the one command that writes a bead and reads it back
description: What bd and Gas City offer for confirming that a bd write stayed written, why none of it covers the read the pack makes before an act that cannot be undone, and the shape of `gctk bead` that fills the gap. Read it when judging the "bd write durability" warrant, a change to `gctk bead` or gcbd's Verify, or a proposal to drop the command for a platform feature.
---

# Gas City search for the one command that writes a bead and reads it back

Read on 2026-11-06 at `gastownhall/beads` v1.3.4 (7ef2fd05e), the city's bd,
which reports `1.3.4 (7ef2fd05e+patched)`, and at `gastownhall/gascity` main
bb61aadbf.

## What was decided

| The need | Outcome |
|---|---|
| Confirm a bd write before an act that cannot be undone or run again | `gctk bead <verb> ... --verify` runs the write through `gc bd` and reads it back with one authoritative `gc bd list --id`. Every read-back this change moves goes through it, from shell, from formula steps, and from Go, where `gctk lifecycle` calls the same function (gcbd's `Verify`). |
| A read that does not mistake a later actor for a lost write | The read confirms the write's witness, not every field it wrote. An update's witness is the metadata keys it sets, else the other fields it writes, and `--verify-key` names the keys instead, as a release does, because a pool's claim right after it rewrites the status, the assignee and the session pins. |
| A refused write | Its exit is passed through: bd's 1, 13 and the others, and `gc bd`'s 4. |
| A write that exits 0 and does not read back | Exit 3, which neither bd nor `gc bd` uses. bd exits 1, 2 (a read past its row cap), 13 (`ExitGuardMismatch`), 14 (`ExitMigrationFrozen`), 75 (`LockHeldExitCode`) and 130, and `gc bd` adds 4 (`bdSilentFallbackExitCode`). gctk's own usage refusal is 2. |

## What bd provides, and where it stops

- **`verifiedUpdate`** (`internal/storage/dolt/issue_operations.go`) re-reads
  an update only when `updateClaimPostcondition` derives a postcondition: a
  claim, or a guarded update whose patch changes nothing but the assignee and
  the status. `hasNonCoordinationPatch` turns the re-read off for a patch that
  sets anything else, and `nonCoordinationPatchSignals` lists metadata sets and
  unsets, notes, priority and labels among those. Its comment says an ordinary
  update's exit status under a degraded server "is no more trustworthy" than a
  claim's.
- **`issueOperations.Close`** runs the close in one transaction and reads
  nothing back.
- **`bd update`'s flags** (`cmd/bd/update.go`, `init`) carry no option that
  asks for a re-read. `--if-assignee` and `--if-status` are compare-and-set
  guards that refuse with 13 before the write. They confirm nothing after it.
- **`bd update --json`** prints "the operation's own post-state snapshot"
  (`cmd/bd/update.go`), the row the same operation built, not a read after its
  commit. It comes from the write whose exit status the warrant distrusts.
- **`bd dep add`** stores an edge onto an id it cannot resolve, when the id
  carries another repository's prefix, as given and without finding it
  (`depAddCmd` in `cmd/bd/dep.go`). `bd dep list` leaves such an edge out of
  its listing and says so only on stderr (`warnDroppedDepEdges`), and a
  `bd list` row carries the bead's raw edges, that one included. So the command
  reads edges off a list row, as `gc-helm.sh` reads a conversation's reply.
- **`bd list --id`** still hides gates, templates, infra beads and wisp rows
  unless the call asks for them (`internal/workapi/list.go`), so the read asks
  for every kind of row.
- **`MetadataEditValue`** (`internal/storage/metadata.go`) stores a
  `--set-metadata` text of `null`, `true`, `false` or a JSON number as that JSON
  value and anything else as a string, so the read compares a value as its text.

## What Gas City provides, and where it stops

- **`gc bd`** (`cmd/gc/cmd_bd.go`) passes bd's exit status through and turns
  bd's silent fallback to the on-disk store into exit 4. It has no option that
  reads a write back. Its own reads after a write, such as
  `release-if-current`'s read of a skipped release, belong to those verbs.
- **`beads.UpdateAndReadBack`** (`internal/beads/update_reporting.go`) returns
  the row after an update, read by `BdStore.UpdateReporting` from the JSON
  `bd update --json` prints, and falls back to a `Get`. The JSON row is the
  operation's own snapshot, as above, so it shows what the write built, not
  that the store kept it. It is also a Go package inside Gas City's `internal`
  tree, which gctk cannot import, and no `gc` command reaches it.

Neither covers the need, so the command composes `gc bd` for the write and
`gc bd list` for the read, and holds only the comparison. It and the reads
scripts still make themselves are what to delete once bd re-reads an ordinary
update, the retirement trigger the warrant names.
