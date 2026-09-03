---
name: Why lx accumulates orphaned wisp auxiliary rows, and what the repair is
description: Work record for tk-aqhtdp. The wisp delete paths were fixed upstream and are not the generator; lx is the one city store missing the four ON DELETE CASCADE foreign keys, its migration ledger records them as applied, and the repair has to follow the orphan purge.
---

# Orphaned wisp auxiliary rows on lx

Work record for bead tk-aqhtdp. The bead asked whether the fix belongs in a
cascade in the beads store or a sweep in `wisp-compact`. Measured against the
live city and against the running `bd` binary, it is neither: every delete
path already removes the auxiliary rows, and lx is the only store in the city
whose schema cannot enforce the constraint those paths were written around.

## What was measured

Every fact below was taken on 2026-09-03 from the running city, or from the
`bd` binary the city actually runs (`bd version 1.2.2`, commit `62d211937`).

### lx is the only store missing the cascade constraints

The wisp plane has four auxiliary tables. Three key on `issue_id`
(`wisp_labels`, `wisp_events`, `wisp_comments`) and one on `parent_id`
(`wisp_child_counters`). Each is supposed to carry a foreign key into
`wisps(id)` with `ON DELETE CASCADE`.

| database | rig | aux cascade FKs present | ignored-migration 4 recorded applied |
|---|---|---|---|
| lx | loomington (city) | **0 of 4** | 2026-05-24 02:27:41 |
| tk | gc-toolkit | 4 of 4 | 2026-05-19 00:13:27 |
| gc | gascity | 4 of 4 | 2026-05-19 00:12:52 |
| sl | signal-loom | 4 of 4 | 2026-05-19 00:12:06 |
| su | shutupandlisten | 4 of 4 | 2026-05-24 03:16:47 |

lx is also the only store with the orphan problem. The correlation is exact.

Two further facts make this a durable divergence rather than a version skew.
lx's `ignored_schema_migrations` ledger records version 4 — the migration that
adds all four constraints — as applied, so the migration will never be
retried. And a store initialised from scratch by the same `bd` binary comes up
with all four constraints present, so the migration works and something about
lx's own run of it did not.

### The one auxiliary table lx does not leak is the one whose FK survives

`wisp_dependencies` was measured at 0% orphaned while the other three ran
99–100%. It is the only auxiliary table whose foreign keys are declared in the
`CREATE TABLE` itself rather than added by the later migration, so it is the
only one lx still has. That is the discriminating evidence: the split follows
constraint presence exactly, not delete-path coverage.

### The constraint guards writes, not only deletes

Probed on a scratch store built by the same binary, with the four constraints
dropped to reproduce lx's shape:

- Inserting a `wisp_events` row naming a wisp with no row in `wisps` **succeeds**
  and is an orphan the moment it lands.
- With the constraint restored, the same insert is refused —
  `Error 1452 ... Foreign key violation on fk: fk_wisp_events_issue`.

So the constraint is load-bearing in both directions. On the four stores that
have it, a write naming a dead wisp cannot land at all.

### The delete paths are already fixed and are not the generator

Beads' server-backed store removes the auxiliary rows explicitly, in the same
transaction, via a shared `deleteWispAuxRowsInTx` helper reached from both
`deleteWisp` and `deleteWispBatchTx` (`internal/storage/dolt/wisps.go`). That
is present in the running binary's tree.

Exercised on the scratch store **with the constraints dropped**, so nothing but
the code could do the cleanup, all three delete surfaces left zero orphans:

| command | wisp row | orphaned events | orphaned labels |
|---|---|---|---|
| `bd delete <id> --force` | gone | 0 | 0 |
| `bd delete <id> --cascade --force` | gone | 0 | 0 |
| `bd mol burn <id> --force` | gone | 0 | 0 |

`wisp-compact` issues the first of these, so a sweep added to `wisp-compact`
would have nothing to sweep on the delete it performs. Neither option the bead
offered is the fix.

One delete path in beads does still depend entirely on the constraint:
`deleteIssueRowInTx` (`internal/storage/issueops/delete.go`) issues
`DELETE FROM wisps` plus the sync-plane dependency delete and touches no
auxiliary table. Its sibling `DeleteCascadeTables` says so outright — "for
issues the delete only issues `DELETE FROM issues WHERE id = ?` and everything
else goes through `ON DELETE CASCADE` foreign keys declared in the
migrations". Any caller reaching that path on lx leaks.

### The leak is live

Of the 914 distinct wisps with a `wisp_events` row written since 2026-09-01,
109 have no row in `wisps` at all. Sampled dead wisps carry a uniform
four-event trail — created, assigned, in_progress, one metadata update — from
molecule step wisps, with no close event.

## What was not established

Which writer produces the current orphans is not pinned down. Every delete
surface reachable through `bd` cleans up, which leaves rows written for a wisp
that is already gone as the shape most consistent with the residue. That
question does not change the remedy: the constraint closes both the
delete-cascade gap and the orphan-write gap, and it is what every other store
in the city already has.

## The repair, and why it is ordered

`ADD CONSTRAINT` validates existing rows and fails on the first violation.
Measured on the scratch store: adding `fk_wisp_events_issue` with a single
orphan present returns `Error 1452`, and the same statement succeeds once the
orphan is deleted. lx holds roughly 3.4M violating rows, so the constraints
cannot go back until the purge has run.

The order is therefore: purge lx's orphaned auxiliary rows, then add the four
constraints, then confirm `doctor/check-wisp-cascade-intact` reports OK.

Statement per table, on lx:

```sql
ALTER TABLE wisp_labels         ADD CONSTRAINT fk_wisp_labels_issue         FOREIGN KEY (issue_id)  REFERENCES wisps(id) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE wisp_events         ADD CONSTRAINT fk_wisp_events_issue         FOREIGN KEY (issue_id)  REFERENCES wisps(id) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE wisp_comments       ADD CONSTRAINT fk_wisp_comments_issue       FOREIGN KEY (issue_id)  REFERENCES wisps(id) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE wisp_child_counters ADD CONSTRAINT fk_wisp_child_counters_parent FOREIGN KEY (parent_id) REFERENCES wisps(id) ON DELETE CASCADE ON UPDATE CASCADE;
```

Dolt spells the inverse ``ALTER TABLE <t> DROP FOREIGN KEY `<name>` ``, with
the constraint name backquoted; unquoted it is a syntax error, which is worth
knowing before writing a rollback.

## What ships here, and what does not

This branch ships `doctor/check-wisp-cascade-intact`, which asserts the four
constraints on every store the city lists, one bounded `INFORMATION_SCHEMA`
query each. It reports lx and passes the four rigs, so it starts as a live
finding and becomes a regression gate once lx is repaired.

The check reports at warning while a store carries a standing backlog it
cannot take the constraint back over. `GC_DOCTOR_WISP_CASCADE_SEVERITY=error`
raises it, and the default should move to error once no store carries such a
backlog — at that point every finding is a fresh divergence repairable on
sight.

Two pieces are outside a gc-toolkit branch. Repairing lx's schema is a live
operation on the city store, sequenced behind the purge. And the migration
recording success while adding nothing is a beads defect: a migration that
cannot verify its own effect leaves exactly this divergence undetectable from
inside the store, which is why it survived three months and three
interventions that each removed rows without restoring the constraint.
