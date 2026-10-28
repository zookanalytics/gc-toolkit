---
name: Gas City search for the beads that wait on a bead
description: The search the arch check asks for before bead-context.sh names the beads that wait on its subject, the edges.awaited_by list and its two counts. What bd, Gas City and the packs Gas City publishes ship for reading a bead's dependents, read at named upstream commits, and why the script takes the waiters from the dependents bd show returns and keeps its own order, bound and counts. Read it when checking whether that list can move onto a native read.
---

# Gas City search for the beads that wait on a bead

`bead-context.sh` rebuilds one bead's working context in one call, and its Edges
section prints on every read. This change adds the beads that wait on the
subject to that section: each bead with a `blocks` or an `until` edge to it, the
open ones first, at most ten named, with counts of all of them and of the open
ones. Its JSON gains `edges.awaited_by`, one `{id, title, status, edge}` per
named bead, and `edges.counts` gains `awaited_by` and `awaited_by_open`. The
text view gains one `awaited-by` line. That grows the script's surface with new
keys, so the arch check asks what Gas City already ships for them
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

bd ships the read. `bd show --include-dependents` returns every bead with an
edge to the shown one, each cut to its identity fields and the edge's type, and
the script's subject read is already a `bd show`. So the read passes the flag,
and the list keeps the dependents whose edge is `blocks` or `until`. Nothing in
bd or Gas City puts the open ones first, bounds the list or counts the waiters
by status, so the script does those three things itself. That projection is all
the change adds. It renders bd's own edges, writes nothing and adds no pack
noun.

## The need

- A read of a bead names the beads that wait on it, so a closed design's read
  names the build it released. A bead waits on another by a `blocks` edge, as
  the build waits on the design, or by an `until` edge, which the pack's waits
  skill files for a bead that is done or moot once the other lands.
- The list leaves out the beads that gather on a bead without waiting on it:
  the review, validation, rework and finding beads joined to it by `related`
  edges, its children, and the visits that track it. The Edges section shows
  those on lines of their own or not at all.
- The Edges section prints on every read, the converse opening's included, and
  a gate can hold more than a hundred parked beads. So the list is bounded, its
  counts say how many it left out, and the open ones come first, so the cap
  never cuts live work ahead of closed work.
- A named bead carries its id, title, status and edge and no body, since the
  tool returns no listed bead's free text
  ([bead-store-resolution.md](../../docs/bead-store-resolution.md#what-it-returns-and-what-it-leaves-out)).

## Where the search looked

Each source was read on 2026-10-28 (UTC):

- bd (`gastownhall/beads`) at main `5011528b3ad5`: the `show`, `dep list`,
  `dep tree` and `graph` commands, the issue-detail view behind `show`, the
  Relations and TreeWalker read roles, the dependency types and counts, and
  bd's documentation, published at beads.gascity.com.
- Gas City (`gastownhall/gascity`) at main `80d08c647e95`: its documentation and
  engineering docs, the `core` pack it bundles, and the source of `gc bd`'s
  by-id routing, `gc graph`, `gc beads show`, the supervisor API's bead routes,
  the bead store's dependency read, readiness and formula compilation.
- The packs Gas City publishes (`gastownhall/gascity-packs`) at main
  `dac12a4a802c`, and at `66c672b5ed00`, the commit Gas City's `go.mod` at
  `80d08c647e95` bundles. Every pack directory, and the repository's `tests/` and
  `scripts/`, was searched for a read of a bead's dependents (`--direction=up`,
  `dep list`, `dep tree`, `dependents`, `include-dependents`) and for
  `waits-for`, `conditional-blocks` and `waits_for`, and each hit was read.

The city runs bd 1.3.2 with patches of its own, built on `9b65b9e198ac`,
upstream's v1.3.2 release commit. That commit sits on a release branch and is
not an ancestor of upstream main, so this record cites upstream main. The
city's build has both flags the script passes to `bd show`. The timings below
were taken through it on 2026-10-28, read-only, three runs of each read at a
load of about 8.

## What bd ships near the need

### bd show and its dependents

`bd show --json` answers with a bead's own fields and its outbound edges. It
counts the inbound ones in `dependent_count`, one number over every edge type
(`CountDependents` in package `dolt` counts every dependency row that names the
bead). `--include-dependents` adds the dependents themselves
([bd show](https://beads.gascity.com/cli-reference/show)). The issue-detail view
(`DetailOptions` and `collectDependents` in package `workapi`,
`internal/workapi/detail.go`) streams every bead with an edge to the shown one,
of every edge type, through `shallowDep`. That keeps the bead's id, title,
status, type, priority and close reason and the edge's type, and drops its
description, metadata and every other free-text field. The flag's help says it
streams "full dependent issues", but the rows are these shallow ones. bd
streams them oldest first (`IterDependentsWithMetadata` in package `dolt`
orders by `created_at`), all of them, and the command has no flag that filters,
orders or bounds them. bd added the flag in `cfcc95799`, before `--brief-deps`
(`4a76685f9`), which trims only the outbound `dependencies` rows and which the
script already passes.

This is the read the need is made of, and the script composes it. The flag added
0.21 to 0.26 s to the subject read of a bead with eight dependents, and 0.16 to
0.22 s and about 55 KB to the read of a gate about 150 beads wait on.

### bd dep list

`depListCmd` (`cmd/bd/dep.go`) lists a bead's dependents with `--direction=up`
([bd dep list](https://beads.gascity.com/cli-reference/dep#bd-dep-list), and
"What depends on this?" on the
[Dependencies and Gates](https://beads.gascity.com/core-concepts/dependencies#dependency-list)
page). Its `--type` flag becomes a one-element type list
(`request.Types = []types.DependencyType{types.DependencyType(typeFilter)}`, the
same on the proxied-server route in `cmd/bd/dep_proxied_server.go`), so
`--type blocks,until` asks for one type by that name and matches nothing, and
two edge types take two reads. The Relations role behind it (`Relations` and
`RelatedRequest` in package `issueops`) accepts several types in one request,
but the command passes one. Each row is a whole bead (`RelatedIssue` is
`types.IssueWithDependencyMetadata`, the bead plus its edge's type), its
description and metadata included, and the role pins the order to ascending
neighbor id. The command has no status, order or limit flag and returns no
count.

The branch's first build composed this read, once for `blocks` and once for
`until`. The two reads took 0.39 to 0.55 s together on the eight-dependent bead
and 0.36 to 0.41 s on the gate, where the `blocks` read alone returned 1.28 MB
of bodies for the script to drop. `bd show --include-dependents` returns the
same waiters: on both beads, and on a third, its dependents whose edge is
`blocks` or `until` were exactly the ids the two typed reads returned. So the
script takes them from the read it already makes.

### bd dep tree and bd graph

`bd dep tree --direction=up` walks the dependents transitively, to a depth of 50
by default, and filters on one `--status`, never on edge type. Its walker
(`TreeWalker` in package `issueops`) follows every edge type but `relates-to`,
so the `related` review and rework beads and their own dependents come with it.
Its `--max-rows` cap is checked after the whole tree is built, and an answer
past it is an error, not a shorter tree (`handleMaxRowsError`). `bd graph <id>`
draws a bead's whole connected component, walked through its dependents and its
dependencies by every edge type (`loadGraphSubgraph` in `cmd/bd/graph.go`).
Neither returns a list of the beads that wait on one bead.

bd's storage layer can count a bead's dependents in one status
(`CountDependentsByStatus`), over every edge type, and no command calls it.

### The store a read sees

Every one of these reads answers from one database. `RelatedIssue`'s doc
comment says an edge whose far end has no row in the database is left out, and
a comment in `depListCmd` says the up direction has that gap with nothing to
detect it.
An edge from a bead in another rig's store is stored with that bead, so the
subject's store has no row for it. The
[Cross-Repo Dependencies](https://beads.gascity.com/core-concepts/dependencies#cross-repo-dependencies)
section resolves an `external:` dependency for `bd ready`, `bd blocked` and
`bd dep tree`, from the waiting side.

## What Gas City ships near the need

**Gas City reads dependents only to act on them, through bd's list.** The
`core` pack's `cascade-nudge-on-blocker-close` order reads each closed
blocker's waiters with
`gc bd dep list <blocker> --rig <its rig> --direction=up --type=blocks --json`,
and keeps in jq only the open or deferred ones' id, assignee and route, which it
nudges. Its `cross-rig-deps` order makes the same typed read to find the
`external:` waiters it converts. In Go, the bead store's `DepList` (package
`beads`) runs `bd dep list --json`, adding `--direction=up` for dependents. Each
reads one edge type per call and keeps what it needs in its own code, as the
script keeps what it needs from `bd show`.

**`gc bd dep list` is bd's read.** `gc bd` hands `dep list` to bd. For a bead of
a class Gas City serves from a relocated store, it answers in process from that
store (`doBdByIDDepList` in `cmd/gc/cmd_bd_by_id.go`), with the same one-type
filter and whole beads, and adds no bound, order or count. Either way one store
answers.

**No `gc` command lists a bead's waiters.** `gc graph`
([reference](https://docs.gascity.com/reference/cli#gc-graph)) prints each bead
of a set or a convoy with what blocks it, from each bead's downward read
(`DepList(id, "down")` in `cmd/gc/cmd_graph.go`), so it names blockers, never
waiters. `gc beads show` prints one `beads.Bead`, which carries its own
dependencies and no dependents. The supervisor API's bead deps route
(`humaHandleBeadDeps`, `GET /v0/city/{cityName}/bead/{id}/deps`) returns a
bead's children only.

**Which edges hold a bead.** Gas City keeps a bead out of Ready while a
`blocks`, `waits-for` or `conditional-blocks` edge holds it
(`IsReadyBlockingDependencyType` in package `beads`). It writes `waits-for`
only between the steps of a formula whose step declares `waits_for`
(`collectRecipeDeps` in package `formula`), and no formula in the core pack, in
the published packs at either commit or in this pack declares one. None of those
sources writes a `conditional-blocks` edge. So a bead in this pack's stores
waits on another by `blocks`, or by `until` when it closes once the other lands.

## What the packs Gas City publishes ship near the need

The Gas Town pack's deacon prompt gives
`gc bd dep list <id> --direction=up --type=blocks --json` as the command that
finds cross-rig deps, the same typed read. The build pack's task import checks
for an edge in the waiting bead's own downward list, and its tests assert that
it makes no `--direction=up` read. The profiler pack collects a run's beads by a
closure over every edge and link key in a whole-store listing. The Gas Town
pack's review checks read a bead's own metadata (`load_bead_context`). None lists
the beads that wait on a bead for a reader.

## What the change composes

The script passes `--include-dependents` on the read it already makes of the
subject, and keeps the dependents whose edge is `blocks` or `until`, each as
`{id, title, status, edge}`. That costs less than the typed reads, returns no
bodies to drop, and needs no read per edge type. The rest is the projection the
Edges section needs on every read and nothing upstream returns: the open ones
first, then by id, at most ten named, with counts of all of them and of the open
ones. bd returns every dependent oldest first, of every edge type, and its one
count covers every edge type and status.

The change adds no pack noun. The list renders bd's own edges and statuses, read
and never written, so it holds no state of its own, keeps nothing in step with
anything, and needs no warrant, as the arch review found.

The list's name is the pack's. bd's `show` heads the inbound side of a `blocks`
edge BLOCKS and of an `until` edge KEEPS ACTIVE, and keeps AWAITED BY for
`waits-for` edges (`depRelations` in `cmd/bd/dep_relation.go`). The pack's
`awaited-by` names what its members do, since each waits on the subject, and
each named bead carries its edge type, so a reader sees `blocks` or `until`
beside it. A `waits-for` or `conditional-blocks` waiter is not listed, since
nothing searched here files one onto a work bead.

The tracked-by line still makes its own reverse read,
`dep list --direction=up --type tracks`, and lists every tracker. The trackers
arrive among the same dependents. tk-zjksy9y, which bounds that line and waits
on this change, can take them from there and drop the read.

## What would change the answer

- bd ordering, bounding or counting a bead's dependents by status and edge
  type, which would replace the script's projection.
- bd's `show` filtering its dependents by edge type, which would cut the read to
  the two types the list keeps.
- A writer filing `waits-for` or `conditional-blocks` edges onto the beads the
  tool reads, which would add those types to the list.
- bd or Gas City reading the beads in other stores that wait on a bead, which
  the doc names as a gap today.
