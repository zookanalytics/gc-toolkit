---
name: Round-cap retirement and park migration
description: Record of retiring the signoff review-round cap (tk-p82tvo) — what was removed from signoff.sh, pr-facts.sh, and the docs; the live migration of the five parked anchors to merge_hold + a visit; the reader surface left to the marker-removal beads; and the retirement of merge.sh's wedged-veto machine value. Implements the "What this retires" list in specs/tk-ztapg/review-cycle-architecture.md.
---

# Round-cap retirement and park migration

Convergence is judged by the validator, so the round counter and the park it
wrote have nothing left to measure. This bead removes them and migrates the
anchors they had parked. It is one carve under epic tk-bw184o; the design is
`specs/tk-ztapg/review-cycle-architecture.md`.

## What the code change removes

**`assets/scripts/signoff.sh`.** The whole cap apparatus:
`GC_MAX_REVIEW_ROUNDS`, the rework-round count (`rework_children` /
`count_rework_children` and the `TOTAL`/`FLOOR`/`ROUNDS`/`CAP_ROUNDS`
arithmetic), `signoff_round_floor`, `signoff_rounds_reset`, `signoff_cap`, the
terminal park (`merge_hold=signoff_cap` + `gc.routed_to=human` +
`blocked_reason` + `gc.takeaway*` + the `gc-helm.sh demand` it filed), the
`signoff.sh reset` verb, and the demand helpers only the cap used
(`demand_gate_state`, `takeaway_is_holding`, `close_cap_demand`). The
approve-path `exception@` guard went with it: its only purpose was to protect
the cap's `exception@` park, which the cap's retirement removes. request-changes
now files exactly one rework child every round and bounds nothing.

**`assets/scripts/pr-facts.sh`.** The cap-retirement arm was already gone
(tk-aqsi24 / #800 re-pointed the feedback batch to open a validation pass). What
remained was dead cap *recognition*: `is_cap_park`, the CONFLICTING-arm carve-out
that let a cap park fall through to the feedback arm (it named the deleted
`signoff.sh reset`), and the `gc.takeaway_by != "signoff"` exclusion in
`demand_gate_state` / `anchor_foreign_blocker`. All removed; a conflicting anchor
under any `merge_hold` now simply holds.

**Docs.** `docs/authority-map.md` (the "Retire a signoff round cap" row and the
`exception@` verdict prohibition), `docs/state-machine.md` (the round-cap
section, trimmed to the still-current operator-feedback → validation-pass
behavior), `docs/refinery-merge-cadence.md`, and `lifecycle/lifecycle.toml`
comments (the cap metadata keys marked RETIRED-residue, following the
`dispatch_count` precedent).

## The live migration

Five anchors were parked by the cap at retirement time (enumerated by
`signoff_cap` presence plus the human route, per the tk-0iig96 census
correction — never by `check.<gate>=exception@`, which a later green pass
overwrites). Each was `merge_result=pre_open_gate` (capped before any PR
opened), `merge_hold=signoff_cap`, `gc.routed_to=human`, with a
`blocked_reason`/`gc.takeaway` composed by the cap and a `by=signoff` demand
gating it.

Each was migrated to `merge_hold=true` (a plain operator hold the cadence still
honours) plus a visit that carries the question the demand did not — the defect
tk-s2uy9h reports. The cap metadata (`signoff_cap`, `blocked_reason`,
`gc.takeaway`/`_at`/`_by`) and the human route were cleared, and the cap's
demand was closed. `merge_hold` is not an I1 marker_key, so the migrated anchors
owe no `blocks` edge; the visit tracks the anchor and holds nothing.

| Anchor | Visit filed | Cap demand closed |
|---|---|---|
| tk-f90c80 | tk-h97pim | tk-dasosb |
| tk-qulxvk | tk-a1fgtq | tk-oyvy99 |
| tk-1jnytx | tk-oqufpx | tk-ld2lv8 |
| tk-wx5ybh | tk-z76mqd | tk-co0jw8 |
| tk-wwmxpe | tk-shvbml | tk-a5n7mg |

Each visit (`task_kind=visit`, routed `human`, `escalation_key=convergence-stalled`)
asks the operator to rule the anchor's fate — continue, redesign, or abandon —
and points at the review beads under the anchor for the findings. To reverse a
migration: restore `merge_hold=signoff_cap` + `signoff_cap=codex` +
`gc.routed_to=human` on the anchor, reopen its demand, and close its visit.

The two census stragglers (tk-0iig96, tk-q0ml23) had already closed by the time
of this migration, so they were board rows no longer and needed nothing.

## What this bead deliberately leaves

The round cap's *readers* outside the two scripts are dead once no anchor
carries `signoff_cap`, but they belong to the marker-removal carves, not here:

- `merge.sh` and `gate-ensure.sh` still recognise `merge_hold=signoff_cap` and
  can still produce the `wedged-exception` machine value. No anchor triggers it
  now, so it is inert; retiring the value touches `lifecycle/lifecycle.toml`
  `[machine_axis]` and `services/helm` `derive.go` together (lifecycle.test.sh
  couples them).
- `assets/scripts/migrate-lane-states.sh` and the `exception@` marker grammar
  (`doctor/check-gate-integrity`) are the marker layer's to delete.

## Retiring the wedged-veto machine value

`merge.sh`'s veto arm classified a standing non-city `CHANGES_REQUESTED` by
counting `source_review_bead` rework children against `GC_MAX_REVIEW_ROUNDS`,
subtracting a floor read from `signoff_round_floor` / `signoff_rounds_reset`.
With the cap's writers gone the floor never advances, so the count degrades to a
raw child count against a default of 3 — the retired round-cap conclusion under
a new name, which the design's "no sixth state for a human"
(`specs/tk-ztapg/review-cycle-architecture.md`) rules out. So the value retires
with the count rather than re-basing on it (the question tk-3ydcmp raised).

The veto arm records `progressing`: the city answers a rejecting review by
filing rework every round without bound, so an automated actor will act until
the reviewer clears the review or a fix moves the head. The standing review is
carried on the posture axis (`pr_posture=changes_requested`), which `prOwed`
excludes from the operator's queue on purpose — answering it is the city's move.

Removed: `GC_MAX_REVIEW_ROUNDS` and the round arithmetic in `merge.sh`; the
`wedged-veto` value from `lifecycle/lifecycle.toml` `[machine_axis]`,
`services/helm` (`derive.go`, `model.go`, `web/src/contract.ts`), `docs/state-machine.md`
and `services/helm/README.md`; and the tests that pinned it. Only
`wedged-exception` remains, still produced by the `merge_hold=signoff_cap` reader
this bead leaves for the marker-removal carves.
