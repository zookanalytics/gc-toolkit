---
name: Pre-open codex-gate stalls — why they accrete and the visit-coverage fix (tk-w73r2q)
description: Characterizes the 17 anchors parked at merge_result=pre_open_gate on 2026-09-14, finds the silent-stall class is a human-gate park whose converse visit was never filed, and records the gate-visit-sweep fix plus the disposition of each instance.
---

# Pre-open codex-gate stalls (tk-w73r2q)

The bead asked why anchors sit at `merge_result=pre_open_gate` after review and
never advance, and to fix the mechanism that lets them accrete silently. Its
evidence was sampled 2026-09-12; work started 2026-09-14, and the picture had
moved. This records what the stalls actually are now, the one mechanism defect
behind the silent ones, the fix, and the disposition of each of the 17.

## The premise moved between filing and work

The bead names four classes: findings never routed to rework, reviews closed
but no PR opened, anchors never reviewed, and a missing codex pool. Two days
later none of those is the live cause:

- **Findings routed.** tk-9ntg93's findings are now a live fix unit (tk-7nwg8a);
  gate-ensure holds its lane on quiescence, which is correct.
- **The "never reviewed" sample advanced out of the open set.** tk-or0ha2 is now
  `in_progress`, so it is invisible to gate-ensure/pr-open/merge, which all
  enumerate `--status=open`. It carries a visit (tk-5g1wrq). A pool claim
  flipping a detached anchor to `in_progress` and hiding it from the cadence is
  a real adjacent hazard, noted below, not this bead's stall.
- **The codex pool is scale-from-zero at rest, not missing.**
  `gc-toolkit/gc-toolkit.polecat-codex` is registered `min=0 max=2`. Zero
  sessions is the correct resting state when no review is owed. Over 32 logged
  reconcile passes gate-ensure dispatched zero reviews every pass, because every
  gating anchor was already green-and-capped, quiesced, or operator-held. There
  was nothing to dispatch, so the empty pool caused no stall and the
  "does dispatch reach a claim" question has no live evidence either way.

## What the 17 actually are (2026-09-14)

All 17 open `pre_open_gate` anchors are held, in four shapes:

| Shape | Count | State | Visit? |
|---|---|---|---|
| Cap park, current-model gate | 5 | `merge_hold=signoff_cap`, `route=human`, `issue_type=gate`/`await_type=human` demand | yes |
| Cap park, legacy `decision` demand (**gap A1**) | 5 | same park, demand is `issue_type=decision`/`await_type` unset | **no** |
| Cap park, no demand (**gap A2**) | 5 | same park, every `blocks` blocker closed, no demand at all | **no** |
| Operator freeze / active rework | 2 | tk-iunfnh `merge_hold=true`; tk-9ntg93 fix unit in flight | yes |

The park itself is not the defect. `signoff.sh`'s review-round cap parks an
anchor `merge_hold=signoff_cap` + `signoff_cap=<gate>` + `route=human` and files
a human-gate demand (`gc-helm.sh demand ... --by signoff --kind decision`,
signoff.sh line ~609). `route=human` keeps the pool from re-offering it and
renders it on the helm board; the demand is the graph edge that makes the hold
real; `gate-visit-sweep` files the converse visit that asks a person to rule.
For the five current-model parks that whole chain works.

## The silent-stall class: a human-gate park with no visit

`gate-visit-sweep.sh` (order `gate-visit-sweep.toml`, 2m) is the one place a
human gate becomes a converse visit. It enumerates
`--include-gates --has-metadata-key gc.demand_for`, then keeps only
`select(.await_type=="human")`. That last clause is the defect:

- **A1 (5 anchors: tk-f90c80, tk-wx5ybh, tk-wwmxpe, tk-a7bp7i, tk-ww19bz).**
  Their demand is a legacy `issue_type=decision` bead with `await_type` unset,
  made by an older `gc-helm.sh demand`. The sweep's `await_type=="human"` filter
  drops it, so `gc.gate_visit` is never stamped and no visit is filed. The
  demands are unsettled (`gc.takeaway_settled` empty) and still block their
  anchors, so the anchor is edged and I1-clean; only the visit is missing.
- **A2 (5 anchors: tk-qf055w, tk-5g85ft, tk-i0c9f, tk-puh9d, tk-zz1yy).** No
  demand exists at all and every `blocks` blocker has closed. The park rests on
  markers alone. These were parked by a producer that predates the durable-demand
  model (an old cap, or `migrate-lane-states.sh`, a manual one-shot that files a
  transient visit rather than a demand); once that visit closed there was nothing
  to re-offer.

The population that decides whether loosening the filter is safe: across the
whole store there are exactly two shapes of open, unassigned `gc.demand_for`
bead — 7 `gate`/`human` (all carry a visit) and 6 `decision`/unset (none do).
All six are genuine human gates (5 from the signoff cap, 1 from converse). An
unassigned `gc.demand_for` bead is a human gate by construction: assigned
demands are work a named person owns and are excluded by `assignee==""`. So the
type discriminator only ever drops legacy human gates; nothing that should be
left alone rides on it, except an *explicit* non-human `await_type` (a timer
gate, `await_type="timer"`), which must still be skipped.

## The fix

`gate-visit-sweep.sh` accepts a demand as a human gate when it is unassigned and
awaits a human **or does not record what it awaits** (the legacy shape), and
still skips a demand that explicitly awaits something non-human. One predicate
change, from `await_type == "human"` to `await_type is "human" or empty`. This
files the visits for A1 within one sweep and closes the orphan class: no future
legacy-shaped human gate can escape the visit sweep on the strength of a missing
`await_type`.

A2 has no demand for the sweep to act on, so it is dispositioned per instance
(below) by re-materialising the durable demand its park always needed.

## Recurrence is already guarded

The invariant "a hold is a graph edge, not a marker" is
`doctor/check-wait-is-an-edge` (I1). It already flags all five A2 anchors as
STALE holds — `route=human` + `blocked_reason` + `gc.takeaway` with every
`blocks` blocker closed — among a standing backlog it reports at `warn` while
that backlog is converted (`lifecycle/lifecycle.toml hold_severity`). So the
structural detector for a park that lost its edge exists; advancing it to
`error` is the operator's call once the backlog is drained, and is out of scope
here. The live park producer, `signoff.sh`, already files a durable
`gate`/`human` demand, so the A2 shape does not recur from current code — it is
bounded legacy debt.

## Disposition of the 17

- **5 current-model parks** (tk-8u81bo, tk-epi4kx, tk-idaym8, tk-0mhde5,
  tk-aqsi24): already dispositioned, converse visit open. No action.
- **5 A1 parks**: the sweep fix files their visits on the next order tick after
  it lands. They are on the helm board (`route=human`) meanwhile.
- **5 A2 parks**: re-materialised the durable human-gate demand each park needs
  (`gc-helm.sh demand <anchor> "<cap headline>" --by signoff --kind decision`).
  This restores the graph edge (clears the I1 STALE finding) and lets the
  unmodified sweep file the visit. The anchor stays parked; a person still rules.
- **tk-iunfnh** (operator `merge_hold=true`) and **tk-9ntg93** (fix unit
  tk-7nwg8a in flight): correctly held, each with a visit. No action.

## Adjacent hazard, not fixed here

A detached `pre_open_gate` anchor that a pool claim flips to `in_progress`
(tk-or0ha2) drops out of every `--status=open` cadence reader until the claim
resolves. That is a distinct mechanism from the visit-coverage gap and is left
for its own bead.
