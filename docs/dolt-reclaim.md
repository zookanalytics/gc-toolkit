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

A reclaim never starts while the data plane is unreachable or overloaded,
judged off the same `server.reachable` and 5000ms latency the deacon patrol's
Dolt-health step reads. A full GC is heavy, and piling one onto a server that
is already struggling is the amplifier this brake removes.

A budget (`GC_DOLT_RECLAIM_BUDGET`, default 1200s) stops the pass from starting
a new reclaim once it is spent, and the deferred stores are the next pass's to
take. A reclaim already running is never interrupted: a GC killed mid-rewrite
is what leaves a store quarantined, so the budget gates starts, not a running
GC. The order's `timeout` (1800s) sits a store's GC above the budget, so the
last reclaim the budget allowed to start still finishes before the hard kill.

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
`GC_DOLT_RECLAIM_HEALTH_TIMEOUT` (default 20s) bounds the pre-reclaim health
probe. Every run prints the size of every store, not only the ones reclaimed,
so a store climbing toward the line stays visible in the order log. The exit is
0 when a reclaim ran or nothing was over the line, 1 when a reclaim was
attempted and failed — a quarantined store, or one that needs an operator — and
2 when the pass could not run at all.

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
