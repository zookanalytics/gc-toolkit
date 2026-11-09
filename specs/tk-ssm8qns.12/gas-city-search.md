---
name: Gas City search for unit 3's surface
description: The Gas City and bd primitives searched for before unit 3 of the gctk effort grew operational surface, cited by symbol at a named upstream commit, and why each one does or does not cover the need. Read it when you review or change gctk bead holds' store flag or the callers' reads of it.
---

# Gas City search for unit 3's surface

Unit 3 moves every caller that decides "is this blocked?" onto
`gctk bead holds`. The search for the verb itself, for what holds a bead, a
run's link to its bead and a bead's edges into another store, is unit 2's
([specs/tk-ssm8qns.11/gas-city-search.md](../tk-ssm8qns.11/gas-city-search.md)).
This record covers the surface unit 3 adds on top of it.

## `gctk bead holds --db <path>`

**The need.** A caller that pins its reads to one store has to get the answer
for that store. `deferred-dispatch.sh` names its rig's store on every read
(`BD_DB`, the order's `GC_RIG_ROOT/.beads`, or the store an `arm --db` names),
and the helm board reads each rig's store in turn. An answer read from the
store gc resolves from the working directory could be another store's.

**The primitive.** bd's own root flag `--db`, which names the store any verb
reads (beads 7ef2fd05e, the bd the city runs, `cmd/bd/main.go:895`,
`rootCmd.PersistentFlags().StringVar(&dbPath, "db", ...)`). `gc bd` carries it
ahead of the verb to bd (gascity e03752646,
`cmd/gc/cmd_bd_show_watch_test.go`, where `--db /x show mp-1` reaches bd with
the flag in place).

**Why it covers the need, and what the flag adds.** The primitive is the whole
pin. The flag only passes it on: the store adapter names the store on every
`gc bd` call it makes, the listing, the rows, the blocked listing and the marks
read alike. A pinned adapter also stops reading the supervisor API, because the
supervisor's bead route (`GET /v0/city/{city}/bead/{id}`, gascity e03752646,
`internal/api/client.go:1124`) finds a bead by the city and its id rather than
in a store the caller names. Nothing in Gas City answers what holds a bead, in
a named store or any other, as unit 2's search records.

### The store a read names when its caller names none

**The need.** gc routes a read that names a bead and no store to the store
that holds the bead (`gc bd list --id gc-wdqisl`, run unpinned from the
gc-toolkit rig, answers with gascity's row, and the same read with
`--db <gc-toolkit>/.beads` answers none). So an unpinned bead read mixes
stores: its read of a far bead finds a bead in another rig and calls the edge
onto it an edge its store holds, while its blocked listing, which names no
bead, answers from the rig gc resolves.

**The primitive.** `bd where --json`, which names the active beads location
(bd 1.3.4 at 7ef2fd05e, `bd help`: "where  Show active beads location"), run
as `gc bd where --json`, which answers from the store gc resolves for the
working directory and the environment and prints its `.beads` path.

**Why it covers the need.** The store adapter asks it once when the caller
names no store and pins every later read to the path it prints, so the answer
is one store's. Nothing else names the store gc resolves.

## Each wait's `title`

**The need.** The callers that move name what holds a bead to a person:
deferred dispatch's `list` and its arm note say which blocker holds an arm and
what it is, and a park's gate is titled with why the work is parked and what
releases it. The record named a wait by its id, type and status alone.

**The primitive.** bd's show row, which carries each far bead's fields beside
the edge's type, its title among them (beads 7ef2fd05e,
`internal/storage/issueops/dependencies.go:1189`,
`GetDependenciesWithMetadataInTx`, which returns each far bead's issue row with
the edge's type). The store adapter already reads that row for the far bead's
status and close time.

**Why it covers the need.** The title is the far bead's own field, read in the
same row the record's status comes from, so the key costs no read and holds no
rule. Gas City names no bead's waits at all, as unit 2's search records.

## check-armed-dispatch-owed's note on an unjudged arm

**The need.** An arm whose bead has a `waits-for` edge of its own is held as
unjudged, so reconcile never slings it until the bd the city runs judges the
gate. The check counted such an arm free or held by hold-lib.sh's rule, which
read no `waits-for` edge, so nothing would say why the arm waits.

**The primitive.** bd's own reads of the edge: `bd blocked` judges it by its
spawner's status rather than its gate, and `bd show` and `bd ready` carry no
gate (blocked-census.md, "The store's rules", read at beads 9b65b9e19, and the
same at 7ef2fd05e). Gas City's doctor checks read no bead's waits.

**Why it does not cover the need.** None of them says that the store cannot
judge the edge. The bead read does, as its `unjudged` status, so the check
prints that status as a note beside the arm, and the note goes once
tk-ssm8qns.6 drops the status.

## Each wait's `issue_type` and `await_type`

**The need.** gc-helm's takeaway refuses to route or assign a bead whose own
work sits on a pending wait, except a wait on a human gate, whose answer is
what makes the bead the work. The board's disposition reads the waits a bead
records less its human gates. Both tell a gate a person answers from work by
the far bead's type and await type (`prstatus.IsHumanGate`), and the record
named neither.

**The primitive.** The far bead's own `issue_type` and `await_type` fields, on
its row in bd's listing (beads 7ef2fd05e; `bd list --json` carries both on
each row, the fields bd-lib.sh's `$HUMAN_GATE_JQ` reads).

**Why it covers the need.** The snapshot already reads that row for the far
bead's status, so the keys cost no read and hold no rule: the reader applies
its own test, `$HUMAN_GATE_JQ`'s `human_gate` among them, to the wait.
