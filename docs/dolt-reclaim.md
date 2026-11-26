# Dolt reclaim

A managed Dolt store keeps the chunks of every reachable commit, so a store
that churns grows on disk even when its live rows do not. A store that deletes
and rewrites rows under batch mode holds the superseded chunks — across the
chunk journal, newgen archive tables, and oldgen — until a full garbage
collection rewrites the store, and `CALL DOLT_GC('--full')` is the only pass
that rewrites the whole store and frees them.

Scheduled `gc dolt compact` with no flags flattens a store only once it passes
a commit-count threshold (`GC_DOLT_COMPACT_THRESHOLD_COMMITS`, default 2000).
A store flattened once drops below that count, then keeps accumulating on-disk
chunk history from ongoing churn that the scheduled pass skips from then on. Its
footprint climbs while its commit count stays low, so a commit-count cadence
never reaches it. `gc dolt compact --gc-only` is the recovery: it runs the full
GC regardless of commit count and skips the flatten entirely.

## Scope

**Mandate.** The scheduled reclaim of a managed Dolt store's dead chunks:
which stores a pass selects, the garbage collection it runs, the brakes that
bound a pass, and how an operator runs it.

**Boundaries.** The flatten that rewrites a store's commit history stays an
operator action and is not covered here. The scheduled commit-count
compaction, the `gc dolt` commands, and the `dolt-noms-size` doctor check are
gascity's, and flagging commit bloat is the deacon patrol's. Disk outside the
bead stores is reclaimed by [scratch-reclaim.md](scratch-reclaim.md) and
[worktree-reclaim.md](worktree-reclaim.md).

## What the pass does

`orders/dolt-reclaim.toml` runs `assets/scripts/dolt-reclaim.sh` daily,
`scope = "city"`, no LLM and no agent. The pass reads each store's on-disk noms
SIZE — not its commit count — and runs `gc dolt compact --gc-only --only-db
<db>` on every store whose noms is at or over `GC_DOLT_RECLAIM_THRESHOLD_MIB`.

The default threshold is 2048 MiB, the 2 GiB per-database line the gascity
`dolt-noms-size` doctor check warns at, so a store is reclaimed when its own
footprint reaches the size that check flags as approaching the limit. Lower the
threshold to reclaim before the warning fires.

The order's interval is the only cooldown. The script holds no state, so a
store that stays over the line is reclaimed once per interval and no more; a
store whose size is live data rather than dead chunks is reclaimed, frees
little, and the measured before/after bytes say so.

## Only `--gc-only`

The bare flatten rewrites commit history, force-pushes a shared remote when one
is configured, and the bloat-recovery runbook names preconditions — stop
writers, take a backup. Auto-running it is the operator's call, so this cadence
runs only `--gc-only`, which keeps the managed server up and needs no stop. If
the deployed `gc dolt compact` has no `--gc-only` flag, the pass refuses and
exits rather than fall back to the flatten.

Gas City's compact runs that GC only on a store no session is connected to. A
GC can lose what sessions write meanwhile to the store's `dolt_ignore`d tables,
such as mail and wisps, so compact skips the store and counts the skip as a
failed database (`gc dolt compact --help`, "Live-session gate"). The pass reads
the line compact prints for that skip as a deferral, not a failure, and it never
passes `--force`. A store that a running city's processes keep a connection to
is deferred on every pass, so collecting it takes the writers stopped, as Gas
City's bloat-recovery runbook does.

A reclaim never starts while the data plane is unreachable or overloaded,
judged off the same `server.reachable` and 5000ms latency the deacon patrol's
Dolt-health step reads. A full GC is heavy, and piling one onto a server that
is already struggling is the amplifier this brake removes. The gate runs before
the pass and again before each store, because a full GC can slow the server it
just ran on.

The gate reads those two fields of the `gc dolt health --json` report and never
the time the report takes. That time follows host load and the `gc` calls the
report makes, while the report caps each Dolt call, so a server too slow to
answer its ping already reads as unreachable. The probe's bound
(`GC_DOLT_RECLAIM_HEALTH_TIMEOUT`, default 90s) only guards against a hang, and
it is long enough for the report on a server the probe cannot reach to finish.
A probe cut at the bound, a probe that fails, and an answer with no readable
latency prove nothing about Dolt. The reclaim goes ahead, and the log says the
health was unknown and why.

A budget (`GC_DOLT_RECLAIM_BUDGET`, default 1200s) stops the pass from starting
a new reclaim once it is spent, and the deferred stores are the next pass's to
take. A reclaim already running is never interrupted: a GC killed mid-rewrite
is what leaves a store quarantined, so the budget gates starts, not a running
GC. The budget does not count the health probe before the pass or the one
before the last reclaim. The order's `timeout` (1800s) sits those two probes
and a store's GC above the budget, so the last reclaim the budget allowed to
start still finishes before the hard kill.

## Resolving the city

A cooldown order's exec runs under a supervisor with a bare environment, so
`GC_CITY_PATH` is absent on a scheduled run and env-only resolution would find
no databases every tick. The script resolves the city from the environment
first, so an operator's hand run probes the city they meant, then falls back to
`gc service list`, which reads the running services and reports their city. It
fails loud if neither answers rather than reclaim nothing in silence. The
resolved path is exported as `GC_CITY_PATH` so every `gc dolt` leaf inherits it:
`compact` and `health` reject a `--city` flag, so the environment is the one
channel all of them honor.

## Operating it

```bash
assets/scripts/dolt-reclaim.sh --dry-run   # the plan: every store's size, and what would be reclaimed
assets/scripts/dolt-reclaim.sh             # reclaim, one line per store plus a summary
```

`GC_DOLT_RECLAIM_THRESHOLD_MIB` (default 2048) sets the per-database line,
`GC_DOLT_RECLAIM_BUDGET` (default 1200s, 0 disables) bounds the pass, and
`GC_DOLT_RECLAIM_HEALTH_TIMEOUT` (default 90s) bounds the health probe before
each reclaim. Every run prints the size of every store, not only the ones reclaimed,
so a store climbing toward the line stays visible in the order log. The exit is
0 when no reclaim failed, because each store over the line was reclaimed or
deferred or none was over it. It is 1 when a reclaim was attempted and failed,
such as on a quarantined store or one that needs an operator, and 2 when the
pass could not run at all.

A run that exits 0 reads as completed, so a run that deferred a store also
declares it to Gas City's order runner, in the file the runner names in
`GC_ORDER_OUTCOME_FILE` (the contract is core's
`assets/scripts/order_outcome.sh`). The runner records the run as an
`order.skipped` event naming each store held back and why. It is `skipped` when
no store was reclaimed and `partial` when some were. A hand run has no such file
and declares nothing.

`assets/scripts/dolt-reclaim.test.sh` is the regression suite, hermetic against
a stubbed `gc` and fixture stores in a tempdir — no city, no real Dolt. Its
load-bearing assertion is that a reclaim is only ever `--gc-only --only-db`, and
a bare flatten is never issued.

## What it does not touch

The flatten path stays an operator action, and commit bloat is the deacon
patrol's to flag on its own key. A store under the line is left alone. The
`dolt-noms-size` doctor check is defined in the gascity binary and is not
changed here; this pass is the automatic remedy for the size it warns about,
not a replacement for the warning.
