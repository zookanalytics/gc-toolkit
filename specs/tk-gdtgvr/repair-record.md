---
name: Repair record — rework children stranded by the signoff.sh inverted-dependency defect
description: What tk-gdtgvr found, changed and left alone when repairing the bead-graph collateral of the signoff.sh inverted blocks edge (tk-xgm761, PR#479). Records the corrected city-wide blast radius, the ordering rule that keeps a survivor from being claimed mid-repair, and why the gc-toolkit victims went to a follow-up bead.
---

# Repair record: rework children stranded by the inverted blocks edge

## The defect being repaired

`signoff.sh` filed every request-changes rework child with
`dep add <child> <anchor> --type=blocks`, which records "child is blocked by
anchor". A `blocks` edge excludes the dependent from `bd ready`, so the child
that exists to unblock the anchor could never be claimed while the anchor was
open, and the anchor stayed open until the child landed.

tk-xgm761 (PR#479, merged `d5cd6fb9`) corrected the write. It repaired nothing
already filed. This record covers the repair of what was already filed.

## Corrected blast radius

tk-gdtgvr was filed naming 4 victims, all in gascity, and stating "All four are
in the gascity store, not this one." The city-wide sweep run at
2026-08-26T19:2xZ found 29:

| store | stranded children | anchors |
|---|---|---|
| gascity | 4 | 2 |
| gc-toolkit | 25 | 13 |
| signal-loom | 0 (repaired earlier, visit sl-pdyk5) | 1 |
| loomington | 0 | 0 |
| shutupandlisten | 0 | 0 |

This is the third successive undercount of the same defect. PR#479's evidence
section named 3 signal-loom beads and called PR#568 "the first casualty
city-wide". Its notes then added a gascity correction of 7, and an addendum
added 10 in gc-toolkit. The true gc-toolkit figure is 25.

The undercounts share one cause: each was measured with a filter written
against one command's JSON and run against another's. `bd list --json` emits
dependency edges as `{issue_id, depends_on_id, type}`; `bd show --json` emits
them as `{id, dependency_type}`. A filter written for one returns nothing
against the other, with no error. Every sweep of this defect should carry both
shapes or state which command it assumes.

The sweep predicate that holds:

```
gc bd --rig <rig> list --all --json --limit=0 | jq -r '.[]?
  | select(.status!="closed") | select((.title // "") | test("^Rework "))
  | ((.metadata.branch // "") | sub("^polecat/";"")) as $a
  | [ (.dependencies // [])[] | select(.type=="blocks") | .depends_on_id ] as $bl
  | select($a != "" and ($bl | index($a))) | .id'
```

Deriving the anchor from `metadata.branch` rather than "has any blocks edge"
matters after the repair: a repaired survivor still carries a blocks edge, to
its decision bead. The loose predicate reports it as still broken.

`BEADS_DIR` does not reach another rig's store. It fails with a project
identity mismatch, not an empty result. Cross-store reads go through
`gc bd --rig <name>`.

## What changed in gascity

Two anchors, two children each, one round per child against an unchanged head.

| anchor | survivor | duplicate closed | decision bead |
|---|---|---|---|
| gc-sc8a8 (PR#161) | gc-vzcaq (round 3) | gc-w8yqe (round 2) | gc-2d0zd |
| gc-dyjoe (pre-open) | gc-6kavc (round 3) | gc-21y2x (round 2) | gc-pca95 |

Each survivor's inverted edge was removed and each now depends on its decision
bead instead. Each was filed with an empty body, so the findings were
transcribed into it: from PR#161 review 5027453848 for gc-vzcaq, and from
review bead gc-aevay's notes for gc-6kavc, which is pre-open and has no PR.
Duplicates were closed with `bead-rehome.sh --kind duplicate`.

Neither duplicate carried a finding absent from its survivor. Both rounds on
each anchor reviewed the identical commit, `490191278a` for gc-sc8a8 and
`4b366f6fa` for gc-dyjoe, and reported the same P1. On gc-dyjoe the round-3
review is a strict superset: it repeats round 2's stale-module-set finding and
adds a second P1 at `internal/agentutil/route_target.go:99`.

### Ordering: block before unblock

A survivor is routed to a polecat pool. The instant its inverted edge is
removed it enters `bd ready` and the pool can claim it, which on a capped
anchor dispatches rework on a question nobody has answered. The decision bead
and its edge therefore go in FIRST, and the inverted edge comes out second. The
survivor is never simultaneously unblocked and routed.

The duplicate takes the mirror treatment for the same reason: clear its
`gc.routed_to` before removing its edge, because `bd close` refuses a blocked
issue, so it must be unblocked before it can be disposed of.

## What was left alone

The caps. gc-sc8a8 and gc-dyjoe keep `dispatch_count=3`, `gc.routed_to=human`,
`blocked_reason`, and `check.codex=exception@<oid>` exactly as found. Both are
waiting on a person. Un-capping them here would dispatch rework on unanswered
questions.

No `triage.hold` was set. gc-dyjoe already carries one from the operator dated
2026-08-22; it was not touched. A prose hold is a dispatch only a human can
resume, and a bead is either ready and moving or blocked on a named bead by an
edge.

gc-4jard, named in tk-gdtgvr as the third capped anchor, is no longer one. It
closed and merged at `4bdabc5e` with its cap reset by converse at
2026-08-26T18:39:13Z, and both its children are closed. It needed no decision
bead.

gc-yblin and gc-lhums were reported and not changed, as tk-gdtgvr directed.
Both predate the defect and use `parent-child`, not `blocks`. gc-yblin is a
child of gc-sc8a8 with an empty `gc.routed_to`, filed 2026-08-25. gc-lhums is a
child of gc-rdey6 routed to human, filed 2026-08-11, and holds the
decision brief that gc-dyjoe's own hold points at.

## Why gc-toolkit's 25 went to a follow-up

Filed as tk-htesrs, blocked by tk-s4fg87.

The repair is three steps and the third is not optional: remove the inverted
edge, deduplicate, then block the survivor on a decision bead. On a capped
anchor, performing the first two without the third is worse than doing nothing,
because it puts human-routed work into a pool.

tk-gdtgvr requires the decision bead be titled from the anchor's existing
`gc.takeaway` and forbids composing a new question. Ten of the thirteen
gc-toolkit anchors have no `gc.takeaway`. No sitting ever recorded what they
wait on, so the third step has no input and the first two must not run.

tk-s4fg87 owns the target model for representing work that is not moving and
names tk-gdtgvr as a bead to reconcile with. If it settles on a shape other
than decision-bead-plus-edge, tk-htesrs follows that shape.

## The shape this leaves behind

Each surviving rework child is blocked by a `decision` bead that states, in the
anchor's own recorded words, what a person owes. Closing the decision makes the
child ready and the pool claims it. Nothing has to be remembered and no field
has to be cleared by hand.
