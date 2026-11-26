---
name: Gas City search for the Dolt reclaim's live-session deferral (tk-0bxcur0)
description: The Gas City primitives searched for the Dolt reclaim pass's reading of compact's live-session skip, the reason Gas City gives for that skip tested against this city's stores, and the faults found at the source with their upstream findings. Read it when reviewing assets/scripts/dolt-reclaim.sh's deferral, or the window proposed in window.md, as AGENTS.md asks of a change that accommodates a behavior of Gas City.
---

# Gas City search for the Dolt reclaim's live-session deferral

The change makes the pack's daily Dolt reclaim pass,
`assets/scripts/dolt-reclaim.sh`, read Gas City's live-session skip as a
deferral and not a failure, and declare each store it defers to Gas City's
order runner. It adds no flag, mode, output key of its own or order: the pass
already defers a store when the data plane is degraded or its budget is spent,
this skip joins that count, and the declaration is the runner's own contract.
The change accommodates a behavior of Gas City, so this page shows the search,
Gas City's reason tested here, and the fault at the source. Every upstream
citation is at `gastownhall/gascity` main
44246e7f5afd47f55dc9732745aac331d4aab0ea, read on 2026-11-26.

## The behavior

`gc dolt compact` asks the server how many sessions are connected to a database
before every `CALL DOLT_GC`, `--gc-only` included, and skips the GC when there
is one or more (`examples/bd/dolt/commands/compact/help.md`, "Live-session
gate"; `gc_live_session_gate` and `run_full_gc` in
`examples/bd/dolt/commands/compact/run.sh`). #9204 added it, merged 2026-11-16.
A skipped full GC counts as a failed database. With `--gc-only --only-db <db>`
the run prints, on stderr:

```
compact: db=<db> <n> live session(s) connected — skipping DOLT_GC to protect dolt_ignore'd tables; re-run with --force to override
```

and then `compact: 1 database(s) failed gc-only reclaim`, and exits 1.
`--force` runs the GC anyway.

## The search

- **An exit or outcome that tells the skip from a failure.** None.
  `gc_only_database` returns `run_full_gc`'s 1, and `compact_each_database`
  counts it among the failed databases and exits 1, as it does for a GC that
  failed. The gate's line on stderr is the one place the skip shows, so the
  pass reads that line, for the store it named, and nothing else.
- **Machine-readable output from compact.** None. compact takes no `--json`,
  and the only event it emits for one database is `dolt.compact.quarantine`.
- **How an order reports a run that held work back.** Covered, and composed.
  Gas City's exec order runner hands each run a file in `GC_ORDER_OUTCOME_FILE`
  (`ExecOutcomeFileEnv` and `DecodeExecOutcome` in
  `internal/orders/exec_outcome.go`). A run that exits 0 declares there what
  did not run, "a safety gate that held a step back" among the cases core's
  `internal/bootstrap/packs/core/assets/scripts/order_outcome.sh` names. The
  controller records the run's `order.completed` and then an `order.skipped`
  event for the declaration (`recordOrderOutcome` in `cmd/gc/order_outcome.go`,
  called from `cmd/gc/order_dispatch.go`). The pass declares each store it held
  back there, for any of its reasons, so a run that reclaimed nothing is
  recorded with what it held back and why, not as a bare completion. compact
  declares its own disk holds the same way (`write_order_outcome` in its
  `run.sh`). With `--gc-only` it runs no disk pre-flight and exits before that
  write (`main` in its `run.sh`), so the compact the pass runs never writes the
  file it inherits, and the pass is the file's only writer. The doctor's
  repeated-failure check counts only `order.failed`, and a completion ends a
  streak (`consecutiveOrderFailures` in
  `internal/doctor/checks_order_outcome.go`), so a declared skip does not trip
  it.
- **A GC Gas City runs with the writers stopped, on a schedule.** None. The
  supervisor's store maintenance runs no `DOLT_GC` (observe-only,
  `engdocs/contributors/dolt-maintenance.md`). The bloat-recovery runbook's
  procedure, `gc stop`, an offline `dolt gc --full --archive-level=0`, then
  `gc start`, is an operator's by hand, and it says `--gc-only` against the
  live server "skips any database with a connected session ..., so quiesce
  writers first" (`docs/troubleshooting/dolt-bloat-recovery.md`). A suspended
  city gets no bd call from gc (`engdocs/design/beads-proxied-local-default.md`,
  "Suspension is quiescence"). Whether the supervisor's open Dolt connections
  close with it is not stated there and was not measured, so the window's
  build measures it first ([window.md](window.md)).

So the pass composes compact and its gate. It never passes `--force`, and it
counts the gate's skip among its deferrals. The deferral holds only while the
line reads as it does at the commit above. If the line changes, the pass
reports the store as failed, as it did before this change.

## Gas City's reason, tested here

The reason, from the help: "`DOLT_GC` also collects `dolt_ignore`d tables
(mail, wisps) that no retention policy protects, so a GC that runs while a
session is writing can lose that data." The gate's comment in `run.sh` gives
the same reason. The test is whether this city's stores keep state in
`dolt_ignore`d tables, whether sessions write it while they are connected, and
whether a GC here meets them. All of it was counted on 2026-11-26.

- **What the stores ignore.** `SELECT pattern FROM dolt_ignore` on the HQ store
  and on this rig's store at 06:27Z. Both list `wisps`, `wisp_%`, `events`,
  `leases`, `bd_events_journal`, `bd_events_seq`, `local_metadata`,
  `repo_mtimes` and `ignored_schema_migrations`.
- **Writes to them.** On the HQ store's `wisps` table at 06:28:07Z: 10,753 rows,
  271 of them mail. 275 rows had their last update in the hour before and 5,029
  in the day before. On this rig's store: 82 rows, with 33 and 69.
- **Sessions connected.** `information_schema.processlist` grouped by database
  at 06:28:18Z: each of the city's seven stores had between 1 and 12
  connections. `lsof` on the server's port put 13 client connections on the
  supervisor (`gc supervisor run`), and the rest on convoy control dispatchers
  and short-lived gc and bd commands. The gate counts any connection, so no
  store would have passed it at that moment, and the compactor's failures below
  show the same every two hours.
- **A GC meeting sessions.** The Dolt server's log, from 2026-10-06, names no
  lost chunk. It records four GCs that Dolt stopped itself because a session
  reached for chunks being collected ("dangling references requested during
  GC. GC not successful"), the last two on 2026-11-23.
- **The skip here.** The pass failed on 2026-11-24 and 2026-11-25 with the
  gate's line for both stores over the line (the `order.failed` events of the
  `dolt-reclaim` order at about 20:55Z each day). Gas City's compactor order has
  failed every pass since 2026-11-24T03:38Z (tk-ascz5ab), and each of its
  failures read on 2026-11-25 names the gate's line for four stores.

**Result.** The reason holds in this city. Its stores keep mail and wisps in
`dolt_ignore`d tables, sessions write them all day while connected, and GCs
here have met sessions reaching for the chunks they collect. So the pass keeps
the skip and never forces past it.

## The fault at the source

The skip is right, but in a running city it never ends. The supervisor's own
connection pool keeps a session connected to every store, so no full GC runs
anywhere. The pending-GC markers Gas City's compactor leaves after a flatten
stand, four of them since 2026-11-24. The compactor order fails every pass, and
this rig's store grows about 0.76 GiB a day ([window.md](window.md)). The fix at
the source lets the GC run with the city's writers held. The supervisor owns
both the pool and the compactor order, so it can quiesce its own store work
around the GC, the way a suspended city is already quiescent, and the gate then
sees no session. That is a medium change to the supervisor's store loop and
compact. It is recorded as upstream finding tk-z17uh59.

Testing the reason turned up a second fault beside it. The managed Dolt
server's config, which Gas City writes, turns Dolt's auto-GC on by default
(`DoltConfig.EffectiveAutoGCEnabled` in `internal/config/config.go`). The
comment on that same block in `cmd/gc/cmd_dolt_config.go` says auto-GC can
destroy `dolt_ignore`d data, mail and wisps among it, and that a city keeping
state there should turn it off. This city runs it on, the default. It is
recorded as upstream finding tk-2h0yvep. The source fix is one line, but turning
auto-GC off is safe only once a GC that a running city can run exists, so the
fix as a whole is medium.

Until Gas City fixes the first fault, this city collects its stores in a window
with the writers stopped, as [window.md](window.md) proposes and tk-npkp7mk.2
builds.
