---
name: Gas City search for the portfolio sync's read of what its epics closed and shifted
description: Use when you review `gctk epic unweighed`, the epic_shifted_at stamp the epic review's ruling write adds, or the epic_weighed_at mark the portfolio sync's note adds with the time the verb prints first, and need the bd and Gas City primitives they compose, the ones searched that do not cover the read or give it a time, why bd's audit history does not carry an epic's past rulings into every rig's store, and why the surface is one verb and two keys rather than a parse of note headings.
---

# Gas City search: what a rig's epics closed and shifted since a sync weighed each

A portfolio sync weighs each close and each shift of the rig's epics that no
sync has weighed yet, each epic by its own mark, and a shift still counts after
a later review continues the epic. The change adds one verb, `gctk epic
unweighed`, and two metadata keys: `epic_shifted_at`, which the epic review's
ruling write stamps on a shift, and `epic_weighed_at`, which the sync's note
stamps on each epic it weighs with the time the verb printed first, the time
it read the epics. bd citations are at bd v1.3.4
(`github.com/steveyegge/beads`), the version upstream `gastownhall/gascity` pins
in its `go.mod` at commit `b841cd14f9bc`, and Gas City citations are at that
commit.

## What it composes

- **bd's listing, as the whole read.** One
  `gc bd --db <store> list --type epic --all --json --limit 0` returns each of
  the rig's epics, closed ones included, with its status, close time and close
  reason, its metadata, and its parent-child edges. The verb reads nothing else
  from the store, through gctk's store adapter and ledger. `gc bd` hands the
  list to the bd binary for the store's scope (`cmd/gc/cmd_bd.go`, `doBd`), so
  the rows are the store's answer at the time of the read.
- **bd's metadata write, as both stamps.** Each key is one more
  `--set-metadata` on a write a skill already makes: the epic review's ruling
  write, and the sync's note on the epic. bd folds every `--set-metadata` of a
  write into the row's metadata in that write's transaction
  (`internal/storage/issueops/update.go`, `resolveMetadataMergeOps`), so a
  stamp lands with its ruling or note, or not at all.
- **`gc rig list --json`, as the rig's store.** `--rig <rig>` reads the store at
  the path the list names for the rig, the list gctk's store adapter already
  routes a bead's reads by.

## What was searched, and why it does not cover the read

- **bd's audit history, `bd history <id> --events`.** In a store bd writes
  directly, each update records, in its own transaction, the whole row it found
  and the fields it set, a metadata edit's whole resulting map among them
  (`internal/storage/issueops/update.go`, `updateIssueInTx` and
  `RecordFullEventInTable`). This rig's store holds every ruling that way: an
  epic's events show the continue a shift replaced. bd's proxied-server path
  records an update with neither value
  (`internal/storage/domain/db/issue.go`, `issueSQLRepositoryImpl.Update`, which
  records the event with its bead, type and actor alone). A scratch store that
  `bd init --proxied-server` made, the one gctk's store acceptance harness
  runs, recorded every update with an empty old and new value. Gas City gives a
  scope with no persisted Dolt identity, such as a rig added fresh, that proxied
  default (`cmd/gc/beads_provider_lifecycle.go`, `scopeUsesProxiedDoltMode`,
  "the fresh proxied-local default"), while this city's stores keep the direct
  server their metadata names. A read of the history would therefore find a
  shift a later ruling overwrote in this city's stores and nothing in a new
  rig's, with no sign of the difference. It also costs a history read per ruled
  epic: about 10 MB and 8 seconds for this rig's 35 ruled epics.
- **bd's commit snapshots, `bd history <id>`, and `bd diff`.** A snapshot's row
  carries no metadata, so it holds no ruling, and `bd diff` compares two
  commits of the whole store, with no tie to the time a sync weighed an epic.
- **bd's epic commands, `bd epic status` and `bd epic close-eligible`.** They
  answer whether an epic's children are complete, and close the epics whose
  children all are. Neither reads a ruling or a sync, and Gas City passes
  `bd epic` through unvetted (`cmd/gc/bd_split_allowlist.go`).
- **The epic's ruling keys, `epic_ruling` and `epic_ruling_at`.** They hold the
  latest ruling alone, since each ruling's write sets them again, so a continue
  after a shift leaves no shift there. They answer a shift that is the epic's
  latest ruling, which is how the verb reads one, and `epic_shifted_at` answers
  a shift a later ruling followed.
- **The notes the two skills write.** The epic review appends a dated
  `## Epic review` block with a `Ruling:` line, and the sync notes each epic
  under `Portfolio sync, po sitting <date>:`. A read of them parses text that a
  skill writes and the reader must match, with nothing that ties the two
  spellings together, and a drifted heading would list every change of every
  epic, or none. A key's value carries the same facts as recorded state.
- **Gas City's own records.** The supervisor API serves a bead's row, its
  update, close, reopen, assignment and edges
  (`internal/api`, the `/v0/city/{cityName}/bead/{id}` routes), and no bead
  history. The city's event log records best-effort and rotates
  (`internal/events/events.go`, its package comment and `EventsRotated`), so it
  keeps no history a read can count. No Gas City primitive models an epic's
  review or a portfolio sync.
- **A time or a store version that a read returns with its rows**, for the sync
  to mark each epic with, so that a change the read did not show stays on the
  next sync's list. bd's list answers with its rows alone: its JSON output is
  the page's items (`cmd/bd/list.go`, `runListCore`). `bd vc status --json`
  prints the store's current commit (`cmd/bd/vc.go`, `vcStatusCmd`), but it
  refuses in proxied-server mode, the default above for a rig added fresh.
  Where it answers, a commit read in a call of its own before the list bounds
  the read no better than a time taken there, and telling what changed on an
  epic since that commit takes a `bd show --as-of` read of each epic
  (`cmd/bd/show_children.go`, `showIssueAsOf`). bd's list filters
  `--updated-after` and `--closed-after` select rows by a time the caller
  already holds (`cmd/bd/list.go`, the flags its `init` declares), and return
  none. So the verb reads its own clock before it asks the store, and prints
  that time first.

## Why the surface is one verb and two keys

- **The verb** is the operator's ruling on this change: the read moves into one
  gctk command with Go tests, which the skill calls in one line. No native call
  answers which changes no sync has weighed, so the verb takes a fresh word,
  `unweighed`, where the sitting sketched `changes`, the word `bd diff` uses for
  the changes between two commits. It reads through the store adapter and the
  ledger, and its rules are tested in Go on the store's fake.
- **`epic_shifted_at`** is the one recorded state that keeps a shift past a
  later ruling in every store bd runs. The ruling's own write stamps it, so it
  lands with the shift or not at all.
- **`epic_weighed_at`** is the sync's mark as a value on the epic, stamped in
  the write of the sync's note, so the verb reads a time where it would
  otherwise scan the notes for a heading. Its value is the time the verb
  printed for the read the sync weighed from, which comes before the store
  answered, so a change made between that read and the note stays on the next
  sync's list.
- **Both keys stay shell's.** The skills write them through `gc bd update`, as
  they write the ruling's other keys, so `lifecycle/lifecycle.toml` registers
  them under `[metadata.epic_stewardship]` and the `epic` package declares them
  read-only.
