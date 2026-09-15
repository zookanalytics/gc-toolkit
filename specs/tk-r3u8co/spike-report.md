---
name: dolt-noms-size — lx is genuinely over the line, and nothing reclaims it
description: Why the dolt-noms-size doctor warning is a real finding and not a measurement artifact — lx holds 2.4 GiB of retained Dolt chunk history against a few MB of live rows, the 2026-09-03 purge only flattened it, and no cadence re-runs the reclaim. Read before treating this warning as benign, and before assuming the remedy is another orphan purge.
---

# dolt-noms-size spike (tk-r3u8co)

## Verdict

The finding is real and actionable. lx alone is 2.4 GiB, past the 2 GiB
per-database doctor line without help from the other four stores. The cause is
retained Dolt chunk history from write churn, not orphaned rows and not a
measurement artifact. The durable fix is a scheduled reclaim cadence, filed as
tk-5rh0v2. The immediate reclaim is a manual operator action (Section E),
because the deacon patrol classifies compaction that way on purpose
(`formulas/mol-deacon-patrol.toml:244`) and the reclaim mutates the live
production data plane.

## The finding

`dolt-noms-size` (a gascity-binary doctor check, not defined in gc-toolkit)
reports "aggregate dolt data footprint is 2.72 GB across 5 databases —
approaching threshold", severity warning, and points its fix_hint at
`docs/troubleshooting/dolt-bloat-recovery.md`. The deacon-findings patrol
filed it under key `doctor-dolt-noms-size`; occurrences reached 3.

## What the store actually holds

Measured live 2026-09-15 ~08:25Z against the managed Dolt server (read-only):

| database | `.dolt` size |
|----------|--------------|
| lx       | 2.4 GiB      |
| tk       | 771 MiB      |
| gc       | 297 MiB      |
| sl       | 185 MiB      |
| su       | 92 MiB       |
| aggregate| 3.7 GiB      |

lx dominates. Its `noms/` is one 2.0 GiB table file plus a 352 MiB journal;
`oldgen/` is 25 MiB. Yet lx's live rows are small: 448,534 `events`, 42,076
`wisp_events`, 13,367 `labels`, 7,033 `issues`, 2,448 `wisps`. Orphaned wisp
child rows — the 3.4 M-row problem that made lx expensive before — are now
**zero** (`wisp_events` and `wisp_labels` with no matching `wisps.id`: 0 and 0).
lx carries 1,380 commits, oldest 2026-05-24.

So a few MB of live data sits inside 2.4 GiB of store. The gap is retained
chunk history: a store that commits under batch mode keeps the chunks of every
reachable commit, and lx has churned heavily (the 3.4 M orphans existed as real
rows until the 2026-09-03 purge, and wisp create/delete continues). A
`CALL DOLT_GC('--full')` rewrites the store and frees what the current root no
longer needs; an ordinary reclaim or the incremental auto-GC (enabled here,
which only bounds the journal) does not.

## Why "benign by design" no longer holds

The tk-iy430k spec argued this warning is unavoidable-by-design because the
check "compares the sum across all five databases against a hardcoded 2 GiB
per-database constant" and so "cannot return OK on this city at any acceptable
churn rate", and it said the concern is "tracked on gascity gc-3yz9y". Fresh
derivation breaks that framing on three points:

1. It is not only a sum-versus-per-db mismatch. lx breaches the 2 GiB per-db
   line on its own (2.4 GiB), so a single database is genuinely over, whether
   the check sums or reads the largest.
2. gc-3yz9y does not cover this check. Its three findings are
   stale-routed-config, bd-backup-freshness, and
   check-finalized-molecule-step-reoffer. The "tracked on gc-3yz9y"
   cross-reference in the tk-iy430k spec is stale.
3. tk-iy430k itself anticipated regrowth ("re-running this verb is the remedy,
   which is why it is a verb") but no cadence re-runs anything. The 2026-09-03
   purge brought lx to 941 MiB; it has regrown ~1.5 GiB in the 12 days since.

The routing note on this bead said the check "reads the largest single db".
The check's own message says "aggregate ... across 5 databases", and the
tk-iy430k spec reads it as a sum. The routing note's mechanism is likely
imprecise, but its conclusion (real, actionable) is correct, because lx is over
the per-db line by itself.

## Why the existing guards miss it

- Scheduled `gc dolt compact` (no flags) skips any database below the
  2000-commit flatten threshold (`GC_DOLT_COMPACT_THRESHOLD_COMMITS`). lx has
  1,380 commits, so a scheduled flatten would skip it. This is exactly the
  "stranded below the flatten threshold with orphaned oldgen" case the
  `--gc-only` flag documents.
- The deacon patrol flags commit bloat only above 50,000 commits
  (`formulas/mol-deacon-patrol.toml:244`), a commit-count heuristic. lx sits
  far below it while being size-bloated, so the deacon's own check stays quiet.
- `wisp-orphan-purge.sh` would delete nothing here: orphan count is 0. The
  remedy for this state is the reclaim, not another purge.

The orphan-creation source is separately handled: the delete paths cascade
(`specs/tk-aqhtdp/wisp-aux-cascade.md`), and lx's missing FK constraints (0 of
4) are tracked on tk-fgr3xi. This spike does not re-open that.

## The missing doc

Both the finding's fix_hint and `gc dolt compact --help` name
`docs/troubleshooting/dolt-bloat-recovery.md`. No such file exists in
gc-toolkit; the canonical runbook is a gascity-product doc, listed as a URL at
`docs/gascity-reference.md:110`
(https://docs.gascity.com/troubleshooting/dolt-bloat-recovery). The fix_hint is
emitted by the gascity binary and resolves against product docs, not this repo,
so there is nothing to add here.

## Remedy

- Durable fix (tk-5rh0v2): a scheduled reclaim cadence triggered on oldgen/noms
  size, not commit count, with a `--gc-only` pass for stores that are
  size-bloated but below the flatten commit-threshold. It carries the operator
  policy question — auto-running a full GC against the live store needs a
  decision on safety and timing — which is why the deacon left compaction
  manual.
- Immediate reclaim (Section E): `gc dolt compact --gc-only --only-db lx`. This
  is the operator's to run; a polecat does not compact the live production store.

## Section E — operator checklist (immediate reclaim)

Run from a shell on the city host. `--gc-only` keeps the managed Dolt server up
(`assets/scripts/wisp-orphan-purge.sh:24`), but it is still a full GC against
live production state, so preview first.

```bash
# 1. Preview what the reclaim would touch (no mutation).
gc dolt compact --gc-only --dry-run --only-db lx

# 2. Reclaim lx.
gc dolt compact --gc-only --only-db lx

# 3. Confirm the drop and clear the warning.
du -sh /home/zook/loomington/.beads/dolt/lx/.dolt
gc doctor 2>&1 | grep -i dolt-noms-size
```

Until step 2 runs, the doctor warning recurs each patrol cycle; that recurrence
is the correct signal that the reclaim is still owed, and it now settles on
tk-5rh0v2 (stamped `doctor_check=dolt-noms-size`) rather than routing a fresh
spike.
