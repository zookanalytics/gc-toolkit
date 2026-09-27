---
name: Legacy visit-outcome backfill — decision and runbook
description: Why doctor/check-visit-outcome-recorded's 326 legacy outcome-less closed visits are backfilled with gc.outcome=unrecorded, the evidence the guard is complete so a one-time backfill holds, and how to run and re-run assets/scripts/backfill-visit-outcomes.sh.
---

# Legacy visit-outcome backfill

`doctor/check-visit-outcome-recorded` flags every closed `task_kind=visit` bead
whose `gc.outcome` is empty. The board projects `gc.outcome` as a sitting's
OUTCOME and `gc.outcome_reason` as its HEADLINE, so an outcome-less closed visit
is a finished sitting the board cannot report — a correct dedup close reads the
same as a dropped need.

The going-forward leak is already closed: every path that closes a visit stamps
the outcome first (`visit-close.sh`, the `gc-helm` dismiss inline copy, and
`pr-facts.sh`'s atomic retire-close). What remains is the standing legacy
backlog, which the operator ruled to drain and let the check go quiet (visit
tk-baltss, recorded on tk-lnrrji). `assets/scripts/backfill-visit-outcomes.sh`
drains it.

## The backlog is static, and the guard is complete

Two claims must hold for a one-time backfill to be the right remedy rather than
a treadmill. Both were checked at implementation, 2026-09-27.

**No visit has closed outcome-less since the guard landed.** The guard commit is
2026-09-26 18:38 -0700. Across all five stores the newest outcome-less close is
2026-09-22, four days earlier, and closes are actively stamped (gc-toolkit's
most recent stamped close was 2026-09-27 00:03, one of 609 stamped there with a
full vocabulary — moot, benign, routed, dismissed, folded, and the rest).

**Every close path that can close a visit stamps `gc.outcome` first.** An audit
of every close site in `assets/scripts/` and `services/` found five paths that
close a `task_kind=visit` bead — `visit-close.sh`, `gc-helm.sh` dismiss,
`converse-close-out.sh` (delegates to `visit-close.sh`), and the two
`pr-facts.sh` retire-closes — and each guarantees `gc.outcome` is present on the
closed visit. `converse-claim.sh`'s stranded-recovery close only runs on a visit
already carrying the stamp. No path leaves a closed visit outcome-less.

The count is 326: loomington 203, gc-toolkit 111, signal-loom 6, gascity 5,
shutupandlisten 1. loomington holds most of it and is nearly all automated
dedup and patrol closes (duplicate patrol escalations from before the
`escalate.sh` dedup fix, and a 2026-09-02 operator-ruling cleanup batch), which
historically did not stamp; those mechanisms are one-time, not a live stream.

## The outcome word

Each stamp sets two keys:

- `gc.outcome = unrecorded`. These closes never recorded a disposition, so the
  word states that, rather than inventing `moot`/`benign`/`folded` per visit. A
  blanket `benign` would fabricate a disposition and is the one option rejected.
- `gc.outcome_reason = ` the bead's own `close_reason`, verbatim. The closer
  already wrote the real disposition there ("duplicate of …", "folded into …",
  "Moot: subject …"), and the board renders it as the HEADLINE, so the true
  disposition survives on the board even though the class word is `unrecorded`. A
  visit whose `close_reason` is empty gets the factual fallback "closed with no
  recorded close_reason".

`unrecorded` is honest and distinguishable — a reviewer can tell a backfilled
sitting from one closed under the live guard. Inferring the class word from the
`close_reason` was considered and set aside: the reason already carries the
disposition, so inference would only change the OUTCOME column while adding the
risk of misclassifying a close nobody classified at the time.

## Running it

Default is dry-run. `--apply` writes both keys, reads them back per visit, and
converges: it selects a visit with no `gc.outcome`, or one carrying this run's
`gc.outcome` whose `gc.outcome_reason` does not yet match the reason derived from
`close_reason`, and skips any visit already holding that final pair. The second
case is the repair path — a metadata write can land `gc.outcome` while
`gc.outcome_reason` drops, and an empty-`gc.outcome` filter would never see that
half-stamped visit again — so re-running drives every in-scope visit to its final
`(outcome, reason)` pair, and a run over a settled store finds none.

```bash
# Report, per store, what would be stamped (read-only):
assets/scripts/backfill-visit-outcomes.sh
# Write it, every store:
assets/scripts/backfill-visit-outcomes.sh --apply
# One store, or a different word:
assets/scripts/backfill-visit-outcomes.sh --apply --rig gc-toolkit
assets/scripts/backfill-visit-outcomes.sh --apply --outcome <word>
```

To confirm it landed, `doctor/check-visit-outcome-recorded/run.sh` returns
exit 0 once every store reads clean.

Re-running with a different `--outcome` will NOT re-stamp visits already carrying
`unrecorded`: the selector re-picks a stamped visit only when its `gc.outcome`
equals THIS run's word, so a run with a new word leaves the old-word visits
untouched. To change the word after the fact, re-select by the old word — for
each store, `gc bd list --db <store>/.beads … | jq` the visits whose `gc.outcome`
is `unrecorded`, and `gc bd update --set-metadata gc.outcome=<new>` them.

## Disposal

This script, its test, and this directory are disposable. Delete them once every
store reads clean and the operator has ratified the word.
