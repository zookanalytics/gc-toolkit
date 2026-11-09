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
ahead of the verb to bd (gastownhall/gascity main 9ba215cb592b,
`cmd/gc/cmd_bd_show_watch_test.go:65-69`, where `--db /x show mp-1` reaches bd
with the flag in place).

**Why it covers the need, and what the flag adds.** The primitive is the whole
pin. The flag only passes it on: the store adapter names the store on every
`gc bd` call it makes, the listing, the rows, the blocked listing and the marks
read alike. A pinned adapter also stops reading the supervisor API, because the
supervisor's bead route (`GET /v0/city/{cityName}/bead/{id}`, `GetBead` in
`internal/api/client.go:1333` at gastownhall/gascity main 9ba215cb592b) finds a
bead by the city and its id rather than in a store the caller names. Nothing in Gas City answers what holds a bead, in
a named store or any other, as unit 2's search records.

### The store a read names when its caller names none

**The need.** gc routes a read that names a bead and no store to the store
that holds the bead (`gc bd list --id gc-wdqisl`, run unpinned from the
gc-toolkit rig, answers with gascity's row, and the same read with
`--db <gc-toolkit>/.beads` answers none). So an unpinned bead read mixes
stores: its read of a far bead finds a bead in another rig and calls the edge
onto it an edge its store holds, while its blocked listing, which names no
bead, answers from the rig gc resolves.

A caller that names no store is often not in the bead's store at all. A
converse sitting is city-scoped, so `gc bd show tk-…` from it answers from the
gc-toolkit store by the id's prefix, while the store it resolves is the city's
(`gc bd where --json` there prints the city's own `<city>/.beads`, at the
city's prefix). Pinned to the store it resolves, its read of a rig bead finds
no row.

**The primitives.**

- gc's own routing of a read that names a bead and no store: by the prefix of
  the id (`bdSubjectPrefixTarget`, defined in `cmd/gc/bd_subject_route.go:27`
  and called at `cmd/gc/cmd_bd.go:1172` at gastownhall/gascity main
  9ba215cb592b, "a by-id read or write routes by its subjects' prefix"), the
  longest configured prefix when several begin it (`beadPrefix` in
  `cmd/gc/cmd_sling.go:630`, through `sling.BeadPrefixForCity` in
  `internal/sling/sling.go:669`, "preferring the longest match").
- `gc rig list --json`, which names each store the city binds, the city's own
  among them (`"hq": true`), with its prefix and its path.
- `bd where --json`, which names the active beads location and its prefix
  (bd 1.3.4 at 7ef2fd05e, `bd help`: "where  Show active beads location"),
  run as `gc bd where --json`, which answers from the store gc resolves for
  the working directory and the environment.

**Why they cover the need.** The store adapter asks `gc bd where` once when
the caller names no store. It pins every later read to that store when the
store's prefix begins the first bead's id, which is every rig-scoped caller.
Otherwise it asks `gc rig list` for the store whose prefix begins the id, the
longest such, as gc's routing does, and pins to it. It keeps the resolved store
when no store's prefix begins the id, or when the listing fails, since a read
there can only find the beads that store holds. So the answer is one store's,
the one gc would read the bead from. The listing costs 0.6 to 1.5 s against
0.2 s for `where`, and only a read about a bead outside the resolved store pays
it. Nothing in Gas City names the store a bead id routes to as a read of its
own: `gc bd where` takes no id.

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

## check-wait-is-an-edge's FOREIGN section and its unjudged note

**The need.** A live bead's wait edge onto a bead in another store holds
nothing. `bd dep add` accepts the foreign id and reports success, and the
store's blocked rule reads only the beads it holds, so the bead runs ahead of
what it names. The census found three on the gc-toolkit store
([census-reread.md](census-reread.md)). The check named such an edge only on a
marked bead whose every other blocker had closed. An unmarked bead's foreign
edge went unreported, and so did one beside a live blocker.

**The primitive.** bd doctor's Orphaned Dependencies check, check 21 of a plain
`bd doctor` (`CheckOrphanedDependencies` in `cmd/bd/doctor/validation.go` at
beads 7ef2fd05e). It lists every dependency row, in both dependency tables,
whose far id neither the issues nor the wisps table holds, and it leaves out
`external:` refs.

**Why it does not cover the need.** It is store-wide and does not look at the
edge type. Its query was run read-only through `gc bd sql` on the gc-toolkit
store at 2026-11-09T04:04Z, and it finds 41 such edges:

- the three live wait edges;
- 38 edges on closed beads, which hold nothing live. Among them are 19
  `supersedes` edges, which record a closed bead's successor in another store
  on purpose.

Its detail is cut at 200 characters, so the three live edges need not show.
Its fix, `bd doctor --fix`, deletes every one of the 41, the successor records
with them. Where the wait belongs is in the bead's own store, and nothing in
that fix records it there. Nor does the city's doctor run the check: Gas City
names `bd doctor` only as a repair step in its preflight
(`internal/beads/contract/preflight_checker.go:868` and `:877` at
gastownhall/gascity main 9ba215cb592b). The section prints the bead read's `foreign` key, which carries
wait edges only and is read for live beads only, and it names that remedy.

The unjudged note is the note check-armed-dispatch-owed prints, for the reason
its section above gives. The check now prints it for every live bead, marked
or not, and the note goes once tk-ssm8qns.6 drops the status.

## The board's read of pending waits

**The need.** The helm board stands a ruled human-gated row down, holds a
ruled row whose work is in flight, and promotes a parked row whose waits have
landed. Each turns on which of the bead's recorded waits have landed, and the
board decided that by its own rule: a `blocks` edge onto a bead whose status
is not closed (the census's D25). The board reads each rig's store through the
beads Go library, not through `gc bd`.

**The primitive.** The library's `BlockedQuerier`, which the board's store
handle offers (`beads.go:156` at steveyegge/beads
v1.2.2-0.20260825072917-62d211937bd3, the version helm's go.mod pins).
`IsBlocked` returns the store's denormalized `is_blocked` flag and the bead's
open direct blockers, and `IsBlockedBatch` returns the flag for many beads.

**Why it does not cover the need.** It answers with the store's mark alone.
The bd the city runs judges a `waits-for` edge by its spawner's status rather
than its gate ([blocked-census.md](../tk-ssm8qns.2/blocked-census.md), "The
store's rules"), and the waits package holds such a bead as unjudged until
tk-ssm8qns.5. A board reading the mark would be the one reader with another
answer for that edge. So the board asks `gctk`'s `waits` package, the one
rule, for each rig's anchors that record a wait. That is one snapshot of the
store per rig per render, started as soon as the rig's anchors are gathered
so it runs beside the rest of the gather. A rig whose read fails reads its
anchors' waits as unknown and adds a `waits@<rig>` note to the partial
gather, the board's existing channel for a read that failed.
