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
