---
name: Gas City search for unit 2 of the gctk architecture (tk-ssm8qns.11)
description: The upstream primitives searched before unit 2 built `gctk bead holds` and the waits package, read on 2026-11-08 at gastownhall/gascity main c7a45437f and gastownhall/beads 7ef2fd05e, with what each covers and what it leaves to gctk, and the figures the verb took on the gc-toolkit store.
---

# Gas City search: unit 2 of the gctk architecture

Unit 2 adds the verb `gctk bead holds`, the `waits` package behind it, a
listing read in the store adapter (`gcbd.Client.Find`, one `gc bd list`), and a
find by a declared key in the ledger. It declares, read-only, the keys the verb
reads: the run link the runtime writes and the arm deferred dispatch writes.
None of them is a new key in a store. Three of the verb's answers read
something a platform could hold, and each was searched for on 2026-11-08.

## What holds a bead

- **Searched for.** One read that answers whether a bead is blocked and on
  what, by whose wait, and which of its own waits are pending.
- **What covers it.** Unit 1's search
  ([specs/tk-ssm8qns.3/gas-city-search.md](../tk-ssm8qns.3/gas-city-search.md#the-blocked-set))
  holds the answer: the supervisor serves no blocked route, and bd's listing is
  the store's answer for every bead it can judge. `waits` composes that
  listing, through the store adapter, and adds only the rule by where the work
  is (docs/gctk-architecture.md, "The `bead holds` contract").

## Which live workflow works a bead

The in-flight test needs it: a bead is in flight once a workflow poured for it
has passed load-context (docs/steering.md, In flight).

- **Searched for.** A Gas City read that names the live workflow runs that
  work a bead, and where each run stands.
- **The run routes.** The supervisor serves `/runs`, `/runs/{run_id}` and
  `/runs/{run_id}/steps`. A `Run` carries its id, formula, title, status,
  target and scope, and no bead it works. `RunsListInput` takes only a limit,
  and a `RunStep` carries its id, title, status, kind and assignee, and no step
  ref (`internal/api/huma_types_runs.go` at gascity c7a45437f). The routes are a
  projection of the city's event log, which reaches a write gc makes on its
  next poll, normally within about a second, and a write made outside gc at the
  supervisor's next store reconcile (`runProjectionFreshness` in
  `internal/api/huma_handlers_runs.go`).
- **The live-root lookup.** `sourceworkflow.ListLiveRoots`
  (`internal/sourceworkflow/sourceworkflow.go` at c7a45437f) lists a bead's
  live roots by `gc.source_bead_id`. `doStartGraphWorkflow` stamps that key only
  when it is handed a source bead, and the launch over an input convoy, the
  pack's dispatch path, hands it none (`internal/sling/sling_core.go`, the call
  at line 726, at c7a45437f). `gc convoy delete-source`'s preview walks the same
  lookup (`scanStore` in `cmd/gc/cmd_convoy_dispatch.go`), so it misses those
  runs too. The launch lock's own check, `checkLegacySourceWorkflowConflict`,
  reads the input convoy that tracks the bead, inside the sling, and serves no
  read of it.
- **What it leaves to gctk.** The link read, which `waits` copies from
  `assets/scripts/run-lib.sh`, the link's one definition, under a test that
  holds the copy to run-lib.fixture.json as the helm board's copy is held.
  Where a run stands is read from its open steps' `gc.step_ref`, which the
  runtime stamps at the pour. The docs' register of re-implementations carries
  the copy (docs/gctk-architecture.md, "The re-implementation register").

## A bead's wait edges into another store

- **Searched for.** A bd read of one bead's edges onto ids its store does not
  hold.
- **bd.** `bd show` returns a bead's edges joined to their far beads, and
  leaves out an edge whose far bead it does not fetch
  (`GetDependenciesWithMetadataInTx` in
  `internal/storage/issueops/dependencies.go` at beads 7ef2fd05e, which reads
  both dependency tables and keeps only the edges `GetIssuesByIDsInTx` finds a
  row for, in the issues or the wisps table). `bd list --json` prints each
  bead's dependency rows unjoined, the far bead's id and the edge's type. bd
  doctor's Orphaned Dependencies check (`CheckOrphanedDependencies` in
  `cmd/bd/doctor/validation.go`) is store-wide, reports a count in a doctor
  message, and opens the store from the beads directory, so it answers no one
  bead's edges as a read.
- **What it leaves to gctk.** Setting the listing's edges beside the show row's,
  and one read of the far beads the show row lacks, which names the ones the
  store does not hold. On the gc-toolkit store that read names `gc-vz6v0` on
  tk-nt5uda and `gc-8kwa5` on tk-7rea7j, as the census found.

## The figures

`gctk bead holds` on the gc-toolkit store, 2026-11-08, from the worktree, three
runs each, at a one-minute host load of 11 to 12:

| Read | Time |
|---|---|
| one bead its row shows in flight, which reads no run | 1.61 to 1.65 s |
| one bead its row does not settle, which reads the live runs | 2.15 to 2.44 s |
| eight beads in one call | 3.3 s |

The live runs read is two listings of the roots and one of the convoys they
name, whatever the number of beads named, with one more read of the open steps
of each live run that works a bead its row does not settle. Nine live roots
were open in the store when it was timed.
