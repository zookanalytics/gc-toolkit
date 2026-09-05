---
name: Hold sweep
description: How a triage hold names the condition that would end it and what evaluates that condition, so a hold cannot outlive its premise. Read it when you are about to hide a bead from the liveness sweep, or when you want to know why a held bead is still held.
---

# Hold sweep

A hold hides a bead. `triage.hold` is what the liveness sweep reads to
classify a bead `held-by-design` (`assets/scripts/liveness-sweep.sh`), and
what the sweep's precheck drops from its survivor set
(`assets/scripts/liveness-sweep-precheck.sh`), so a held bead is absent from
the census that would otherwise report it as an unnamed wait. Non-empty is
the test: an empty `triage.hold` is a cleared hold.

That makes the condition which would end the hold load-bearing. Written only
as prose, it is a sentence nobody re-reads, and the bead stays hidden for as
long as the marker stands. So a hold records its condition as metadata, and a
pass evaluates it.

## Scope

**Mandate.** How a `triage.hold` records what would release it, what
evaluates that record, and what a release does and does not do.

**Boundaries.** This covers `triage.hold` only. `blocked_reason` is the
refinery cap's own conclusion and `gc.takeaway` answers itself through the
`settled_keys` pairing in `lifecycle/lifecycle.toml`; both are declared hold
markers, and neither is swept here. Whether released work should then be
routed is a separate decision this makes no claim on. What a hold owes the
dependency graph belongs to `doctor/check-wait-is-an-edge`, described under
[a condition is not an edge](#a-condition-is-not-an-edge).

## Hold it with a condition

```bash
"$PACK_DIR/assets/scripts/hold-sweep.sh" hold <bead> \
    --until merged-within:48h \
    --reason "held pending merge movement; not work-losing"
```

That writes the prose to `triage.hold`, the condition to
`triage.hold_until`, the actor and time to `triage.hold_by` and
`triage.hold_at`, and appends a note saying who held it and what would end
it. `lifecycle/lifecycle.toml` `[holds]` declares the condition key, and the
script reads it from there.

`--until` is required. A hold with no condition is one nothing can ever
evaluate, so the writer refuses to create one rather than leaving a bead
hidden behind a name no pass reads.

The target must be one the sweep can see. `hold` refuses a bead outside the
liveness-sweep census — a gate, an infra bead, a template or other
molecule/wisp row that a listing omits unless an `--include-*` flag names it.
The sweep never enumerates such a bead, so a hold on it would hide nothing, and
`reconcile` — which reads the same default scope — could never see its
condition to release it. The refusal is what keeps the writer's reach equal to
the census that must later find the hold.

Three conditions are evaluable:

| Condition | Fires when |
|---|---|
| `merged-within:<N>h` | a merge landed in this rig within the last N hours |
| `bead-closed:<id>[,<id>...]` | every named bead has closed |
| `date:<YYYY-MM-DD>` | that date has arrived, UTC |

`merged-within` reads the store, not GitHub: a merged anchor carries
`merge_result=merged`, and the close that recorded it is the merge time, so
`closed_at` on those beads is what the window is measured against. Only
`merge_result=merged` counts; the other `merge_result` values are open states.

`date:` is the review-by date. A wait no condition expresses still takes one,
which is what keeps every hold answerable — the date does not describe the
wait, it bounds how long the hold may stand without anyone looking at it.

## What evaluates it

`orders/hold-sweep.toml` — a `cooldown` exec order at `scope = "rig"`, hourly,
so each importing rig sweeps its own store against its own merges. Each pass
runs `hold-sweep.sh reconcile`, which reads every live bead carrying a
non-empty marker and, per hold:

- **releases** it when the condition has fired, emptying `triage.hold` and
  stamping `triage.hold_cleared_by` and `triage.hold_cleared_at`;
- **holds** it when the condition is well-formed and not yet true;
- **names** it, every pass, when it carries no condition at all;
- **names** it when the condition cannot be evaluated — malformed, or naming a
  bead this store cannot read.

Live means every non-closed status. `closed` is the only value that ends a
hold: a bead that has been claimed, parked or blocked still carries one, and
its hold hides it from the census just the same.

An unconditioned hold is never released. Somebody may have meant the silence
(a bead held because no reason was ever supplied is a disposition, not an
oversight), and a pass that guessed would overwrite it. Naming it in every
pass is what keeps it from being silent. Give it a condition, or a review-by
date, to end the report.

A condition that cannot be evaluated never releases either. An unreadable
probe is not evidence that a wait ended.

An unreadable listing exits non-zero and says so. It never prints a
zero-count summary: for a pass whose whole job is to end a silence, "I could
not read the board" and "nothing is held" must not read alike.

## Releasing is not closing and not dispatching

A release clears the marker. The bead returns to the liveness census, where
the sweep classifies it like any other open bead. Nothing is closed, nothing
is routed, and the assignee is untouched. Every write is
`--append-notes`: a held bead is exactly where rulings get recorded, and
`--notes` would replace them.

The record survives the release. `triage.hold_at`, `triage.hold_by` and
`triage.hold_until` stay in place, so the bead still says when it was held and
which condition ended it.

To end one by hand, or to see what is held:

```bash
hold-sweep.sh list                      # every live hold, its condition, its verdict
hold-sweep.sh release <bead> --reason "the premise died"
hold-sweep.sh reconcile --dry-run       # what the next pass would release
```

## A condition is not an edge

`doctor/check-wait-is-an-edge` asserts that a live bead carrying a hold marker
also carries a `blocks` edge to a live bead in the same store. That invariant
and this one answer different questions. The edge holds a bead out of
`bd ready`, so no pool offers it. The marker hides it from the triage census,
so no sweep reports it. A `bead-closed` hold usually wants both: the edge for
the readiness predicate, the condition so the marker is cleared when the edge
resolves. `hold-sweep.sh` writes no edges — it releases the marker and leaves
the graph to the writers the check names.
