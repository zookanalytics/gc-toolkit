---
name: Orphaned wisp child rows — why lx regrew, and the verb that empties it
description: What made the lx store expensive (3.4M child rows pointing at wisps that no longer exist), why four months of reclaims never removed one of them, and how wisp-orphan-purge.sh deletes them safely against a live city. Read before treating lx growth as a compaction problem or before widening the purge to another table.
---

# Orphaned wisp child rows

## The defect

`wisp-compact` expires rows from `wisps` hourly and never touches their
children. `wisp_events`, `wisp_labels`, `wisp_comments` and
`wisp_dependencies` all key on `issue_id`, and nothing deletes a child when
its wisp goes, so the child rows accumulate without bound.

At filing, lx held 3,407,828 such rows against 1,319 live wisps: 2,094,721 of
2,117,323 `wisp_events` (99.0%) and 1,313,103 of 1,317,809 `wisp_labels`
(99.6%). `wisp_comments` held 4 rows, all orphaned. `wisp_dependencies` held
2, neither orphaned — it is covered by rule, not because it was dirty.

`wisp_child_counters` keys on `parent_id` rather than `issue_id` and was empty,
so it is out of the purge. A future non-empty one needs its own decision.

## Why every prior intervention failed

The 2026-05-13 dump+load, the 08-05 flatten and the 08-19 `--gc-only` reclaim
all repacked chunks, and a reclaim does not delete rows. The bead recorded
orphaned `wisp_events` by creation era at filing, and re-running that query
mid-purge reproduced the distribution on what remained:

| era | at filing | mid-purge remainder |
|---|---|---|
| before the 08-05 flatten | 1,659,404 | 1,459,116 |
| 08-05 .. the 08-19 reclaim | 412,635 | 363,981 |
| since the 08-19 reclaim | 22,285 | 21,628 |

2.07M of 2.09M rows survived both interventions. That is why lx returned to the
same size after each one, and why the footprint read as a compaction problem for
four months. Compaction is healthy; the rows are the problem. A reclaim is still
required *after* the delete, because a DELETE alone does not shrink the store
and briefly grows it — Dolt keeps deleted rows in history until a full GC
rewrites `oldgen`.

## The shape of the fix

`assets/scripts/wisp-orphan-purge.sh` censuses each child table, deletes in
bounded batches, commits each batch, and then runs
`gc dolt compact --gc-only --only-db <db>`.

**The predicate rides inside the DELETE.** `DELETE FROM <t> WHERE NOT EXISTS
(SELECT 1 FROM wisps w WHERE w.id = <t>.issue_id) LIMIT <n>` is evaluated per
batch against the `wisps` of that moment, so the run needs no id snapshot and is
race-free against a live city: a wisp that expires mid-run makes its children
orphans and they go, a wisp created mid-run protects its children.

**Batching is not optional.** One transaction over 3.4M rows against a live
server is the shape that reaps the connection. Each batch commits its own table
— `DOLT_ADD('<t>')`, never `-A`, which would sweep a concurrent writer's
in-flight change into the purge's commit. An interrupted run therefore leaves
committed work and a clean working set, and re-running resumes; this was
exercised for real when the first live run was stopped after 250,024 rows.

**Guards fail closed.** The load-bearing one refuses when `wisps` is empty or
unreadable, because that state satisfies the orphan predicate for *every* child
row and nothing downstream distinguishes it from a correct purge. A missing
table refuses. A batch that removes nothing ends the table rather than spinning.

## Two defects that only live data produced

**A census too large to render as an integer.** `SUM(CASE WHEN ... THEN 1 ELSE
0 END)` returns a float in Dolt, and past a million rows the server renders it
in scientific notation. The first live run read `2.094721e+06` and refused. The
hermetic fixtures count in the hundreds and can never produce the shape. The
count is now cast back to an integer in SQL, and a stub case feeds the float
rendering to prove the numeric guard refuses rather than doing arithmetic on it.

**A fail-safe that fired on a valid state.** The post-table guard first aborted
on any drop in a table's live-linked rows, reading it as the delete having
reached a row a wisp still points at. On a live store that is the ordinary case:
`wisp-compact` expires wisps hourly, a 3.4M-row purge runs for tens of minutes,
and each expiry moves its own children out of the live class. The live wisp
count fell 1319 → 1314 within eight minutes of the first run, so the guard would
have aborted a completely correct purge before its reclaim. A drop now accuses
the delete only when the wisp population did not itself shrink.

The delete's predicate is what keeps live rows safe. This guard is the backstop
against that predicate being wrong — a failure that would take the population
wholesale, not a few rows.

## Verification

Run against lx on 2026-09-03, in two passes: the first was stopped deliberately
after 250,024 rows to correct the live-row guard, and the second carried the
rest. Stopping mid-run is the resumability claim being exercised rather than
asserted — the working set was clean, HEAD matched the working copy, and the
re-run picked up from the committed state.

Orphan counts per table, first census to final:

| table | total before | orphans before | total after | orphans after |
|---|---|---|---|---|
| `wisp_events` | 2,117,323 | 2,094,721 | 22,593 | 0 |
| `wisp_labels` | 1,317,809 | 1,313,103 | 4,664 | 0 |
| `wisp_comments` | 4 | 4 | 0 | 0 |
| `wisp_dependencies` | 2 | 0 | 2 | 0 |

3,407,844 rows removed. Live-linked rows were preserved throughout: 22,602 →
22,593 on `wisp_events` and 4,706 → 4,664 on `wisp_labels`, both drops
accounted for by wisps expiring during the run, and both classes still fully
resolvable — the after-census finds zero orphans, so every remaining row points
at a live wisp. Live wisps moved 1,319 → 1,312 on their own cadence.

`.dolt` went 1.48 GiB → 941 MiB, having peaked at 4.3 GiB mid-delete before the
reclaim; `DOLT_GC('--full')` took 36s and the city stayed up throughout. Free
space on the volume returned to 21 GiB. The transient peak is the thing to
budget for: the store nearly triples before it shrinks.

`gc dolt health` reports `orphans: []`, `quarantine: []` and no zombie
processes. The lx backup manifest remains the newest file in `.dolt-backup/lx`,
which is the restorability invariant the deacon patrol's backup-manifest check
enforces.

The `dolt-noms-size` doctor warning is unaffected by design: it compares the sum
across all five databases against a hardcoded 2 GiB per-database constant and
cannot return OK on this city at any acceptable churn rate. That is tracked on
gascity `gc-3yz9y`, not here.

## What this does not fix

Orphans re-form as wisps expire. The baseline census counted 3,407,828 and the
purge removed 3,407,844, so at least 16 formed during the run itself; the
removal figures come from row-count deltas, which concurrent inserts make
conservative, so that is a floor rather than an exact count.
This recovers the standing backlog; stopping it re-forming is the cascade fix on
`tk-aqhtdp`. Until that lands, re-running this verb is the remedy, which is why
it is a verb.
