---
name: Round-cap retirement and park migration
description: Record of retiring the signoff review-round cap (tk-p82tvo) — what was removed from signoff.sh, pr-facts.sh, and the docs; the live migration of the five parked anchors to merge_hold + a visit; the reader surface left to the marker-removal beads; and the wedged-veto follow-up. Implements the "What this retires" list in specs/tk-ztapg/review-cycle-architecture.md.
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

## Follow-up: wedged-veto reads the retired round fields

`merge.sh`'s `wedged-veto` arm reads `signoff_round_floor` /
`signoff_rounds_reset` / `GC_MAX_REVIEW_ROUNDS` to classify a standing non-city
`CHANGES_REQUESTED`. With the writers gone it degrades to counting raw rework
children from a floor of 0 against the default cap of 3 — it does not break, but
"rounds spent" is no longer a maintained concept. Filed as tk-3ydcmp so the
design owner rules whether `wedged-veto` retires too or re-bases on a raw count.
