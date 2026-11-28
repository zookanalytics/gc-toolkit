---
name: Gas City search for the ledger's reading of a key with no value (tk-jqn0xqv)
description: Why gctk's ledger reads a key as holding no value when it is absent, a null, a blank text or a String key's false, and why every selection by key narrows bd's answer to that reading. It cites the bd and Gas City behavior the reading accommodates, at named commits, the city's census of stored values, and why upstream owes no fix. Read it when reviewing the ledger's key read or a selection by key, as AGENTS.md asks of a change that accommodates a behavior of Gas City.
---

# Gas City search for the ledger's reading of a key with no value

The ledger reads a key as holding no value when the row lacks it, holds it as a
JSON null or a blank text, or holds a `String` key as a JSON false, and every
selection by key keeps only the rows that reading holds. That reading
accommodates two upstream behaviors: bd stores a metadata value typed by its
spelling and selects rows by bd's own test of a key, and Gas City clears a key
by writing an empty text and reads a blank one as unset. Everything below was
read on 2026-11-27 and 2026-11-28 UTC at `gastownhall/beads` v1.3.4
(7ef2fd05eb0c, the bd the city runs, `bd version 1.3.4 (7ef2fd05e+patched)`)
and `gastownhall/gascity` main 6dce31bbb68e.

## What bd does, and the reason it gives

- `bd update --set-metadata k=v` types the value by its spelling:
  `MetadataEditValue` in `internal/storage/metadata.go` stores `null` as a JSON
  null, `true` and `false` as booleans, a spelling that is a valid JSON number
  as that number, and anything else as a string.
- bd's listing selects a key's presence with `JSON_EXTRACT(metadata, ?) IS NOT
  NULL` and a key's value with `JSON_UNQUOTE(JSON_EXTRACT(metadata, ?)) = ?`
  (`AppendMetadataClauses` in `internal/storage/sqlbuild/filter.go`). On the
  city's own engine, `gc bd sql` on literal JSON unquotes a false as `false`
  and a null as `null`, not as SQL NULL (2026-11-28T01:2xZ). So bd selects a
  key stored as a false or a null as present, and `k=false` matches a stored
  false.
- The reason is bd's stated contract. PR #6053 (merged 2026-08-29, "JSON
  contract fixes before 1.3.0 freezes them") restored the typing on purpose and
  says: "Metadata is schemaless `json.RawMessage` and nothing in bd compares
  these values typed; consumers that care should coerce on read." Its escape
  hatch for a forced string is the typed routes, `--metadata` and
  `--metadata-json` (`MergeMetadataJSON`), which write a value and read none.

## What Gas City does

- It clears a key by writing an empty text: the sling's reassignment writes
  `gc.routed_to` and `gc.run_target` as `""` (`internal/sling/sling_core.go`
  1235-1236), and it clears `gc.execution_routed_to` the same way (1260).
- It reads a blank text as unset: `strings.TrimSpace(b.Metadata[k]) != ""` in
  `cmd/gc/work_routing_metadata.go` (lines 14, 21 and 28) and
  `cmd/gc/route_recovery.go` (lines 42-43, 63 and 66).

So in Gas City a key cleared to `""`, or holding only spaces, holds no value.
The pack's scripts read a key as `(.metadata[k] // "")` and compare it with
`""`, so they read an absent key, a null, a false and an empty text as no value,
and a text of spaces as a value. The ledger takes Gas City's test, since that is
the runtime whose clears the city's stores carry.

## The city's data

Counted at 2026-11-28T01:33:57Z, over every open, in-progress and blocked bead
in the city's seven stores, read with `gc bd --db <root>/.beads list --status
open,in_progress,blocked --include-gates --json --limit 0` and a jq count of
metadata values by JSON type:

- No open bead in any store holds a key as a JSON false or a null.
- 342 of 1,453 open beads hold some key as an empty text: 200 of 889 in
  gc-toolkit, 39 of 142 in growth-factor, 29 of 228 in gascity, 26 of 31 in the
  city's own store, 23 of 76 in sprintshow, 16 of 55 in signal-loom and 9 of 32
  in shutupandlisten. In gc-toolkit's store the keys most held empty are
  `gc.routed_to` (157) and `gc.run_target` (89), Gas City's clears, then
  `gc.takeaway_settled` (49) and `gc.deferred_type` (25).
- No open bead holds a key as a text of spaces alone.

Of the keys held empty, gctk declares two. `gc.routed_to`'s readers
(`services/gctk/pr/beads.go`, `services/gctk/reaction/refusal.go`) compare its
value with `""` and ignore whether it is held, and `gc.takeaway_settled` has
only its writer in gctk. So the stored data reads in gctk as it did, and the
change is felt where a blank text met a reader of presence: the dispatch key,
whose blank target the arm record read as a malformed arm.

## What upstream owes

Nothing. bd states that typing as its contract and asks consumers to coerce on
read, and Gas City's own code reads a blank key as unset, so neither behavior
is a fault and no bead is filed upstream. Neither offers a primitive that reads
a key the way gctk needs: bd's typed routes write and do not read, its presence
test counts a false and a null, and Gas City's tests are internal to its
binary. The ledger's key read is where the coercion belongs, once for every
declared key.
