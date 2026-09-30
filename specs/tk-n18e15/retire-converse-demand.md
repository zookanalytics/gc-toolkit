---
name: retire-converse-demand
description: The design record for tk-n18e15 — why a converse hold stops filing the cascading blocks-edge demand and relies on the finalize gate, how the resume trace is re-homed, and the I1 interaction that follows.
---

# A converse hold stops filing the demand

> **Bead:** tk-n18e15 · **Kind:** design + implementation record
> **Supersedes:** tk-g6xcwi's container-refusal approach (PR #915, retired)
> **Authoritative model:** `docs/finalize-gate.md` and `docs/gascity-human-engagement.md` (what is true now). This file records why.

## Problem

A converse hold recorded its wait by filing a demand gate with a `blocks`
edge onto the sitting's subject (`converse-hold.sh`; `converse-signoff.sh`
re-stated it on the cut-short path). When the subject is a roll-up container
(an epic), bd's `is_blocked` cascades that block down every parent-child leg,
so armed children drop out of `bd list --ready` carrying no blocker of their
own and the pool never offers them. That cascade is the disease finding
tk-g6xcwi named.

## Why the blocks edge is redundant

tk-p8svsz (PR #882, merged) added the track-only finalize gate
(`assets/scripts/finalize-gate.sh`), wired into `merge.sh`, `bead-rehome.sh`,
and `pr-facts.sh`. An open visit that TRACKS its subject already holds that
subject's merge and close, through a non-blocking `tracks` edge, with no
effect on the subject's children. The demand's `blocks` edge no longer
performs the gating; it only cascades. tk-p8svsz deliberately left the demand
in place and named its retirement as later work — this bead is that work.

## Change

- `converse-hold.sh` no longer files a demand or places any `blocks` edge, on
  a leaf or a container alike. It stamps the board takeaway (best-effort), the
  `gc.hold_demand` resume trace on the visit, and — for an unanchored item —
  the `held` transition, exactly as before minus the demand.
- `converse-signoff.sh` no longer re-states a demand on the `--ruled no`
  cut-short path. The hold persists as the still-open visit. Its `--ruled yes`
  arm still resolves an open demand it finds on the item, which now discharges
  only a demand another writer left (a hold from before this change, an
  operator's, or the triage sweep's).
- The doctrine prose that framed the hold as a demand — the converse prompt,
  the `converse-hold` skill, `docs/gascity-human-engagement.md`,
  `docs/finalize-gate.md`, `docs/authority-map.md`, and the `gc.hold_demand`
  entry in `lifecycle/lifecycle.toml` — now states that the hold is the open
  visit and the finalize gate holds it.

## Decisions

### The resume trace is re-homed, not removed

Step 1's `action=hold` arm (`converse-claim.sh`) reads `gc.hold_demand` off
the visit to tell a real hold from a claim that died before step 2. It tests
only that the key is PRESENT; it never parses the value. The value was the
demand bead's id, which no longer exists, so `converse-hold.sh` now stamps a
began-marker (`held@<ISO-8601 instant>`) instead: non-empty, attributable
because it lives on the visit rather than the shared item, and unmistakably
not a bead id, so no reader mistakes it for a demand to resolve. The
stamp-and-read-back gate that refuses to frame unless the trace persisted is
unchanged.

`converse-claim.sh` needs no code change. Its `gc.demand_for` recheck path
still fires for a demand left on the item by another writer, which is a valid
signal to re-check the premise rather than close.

### The takeaway and the held transition stay

This bead's scope is the demand's `blocks` edge. The item's `gc.takeaway`
headline (the board's NEEDS sentence) and the `held` transition (which drops
an unanchored item from the merge/gate/pr-facts enumerations) are separate
records and stay. `stall_root` is advisory and written by no script
(`visit-identity.sh`), so in practice `ITEM ≡ SUBJECT`, and the finalize
gate's subject-coverage lands on the same bead the old demand gated.

### No-writer now lands the hold rather than refusing it

Previously, a missing `gc-helm.sh` made the demand call fail and the hold
refuse. With the demand gone, the takeaway is best-effort and the hold's
enforcement is the finalize gate on the open visit, so a missing takeaway
writer no longer blocks the hold: it lands on the visit and the stamp, and
warns that the board carries no headline.

## The I1 interaction (surfaced, not resolved here)

`doctor/check-wait-is-an-edge` (invariant I1) reports a live bead that
carries a hold marker — `gc.takeaway`, or `gc.routed_to=human` — with no
live `blocks` edge. It counts only `blocks` edges by design; a `tracks` edge
does not satisfy it. Before this change the demand's `blocks` edge satisfied
I1 for a converse-held item's markers. With the demand gone, a converse-held
item carries those markers and no `blocks` edge, so I1 (currently
`hold_severity=warn`) reports it for the duration of the hold.

This is inherent to the operator's ruling that a hold is a non-blocking visit
rather than a `blocks` edge; the finalize gate holds through a `tracks` edge
that I1 cannot see. Reconciling the two — teaching I1 to treat a bead covered
by an open visit as edged, or dropping the item's hold markers in favor of the
visit alone — is tracked in **tk-klrbzn**. It is warn-level, so not
merge-blocking, but it adds to the marker-only-hold backlog and should not sit
indefinitely.

## Scope boundary

- **tk-klrbzn** — reconcile I1 with the visit/finalize-gate hold model. Not
  this bead.
- **tk-g9ncko** — the helm board's per-tile open-visit/hold signal. Not this
  bead.
- **tk-u4z8me** — a doctor check for a direct dep-add or gate-create that
  blocks a container. A different direction from tk-klrbzn. Not this bead.
- `gc-helm.sh`'s `demand` verb is unchanged: it remains the operator's and the
  triage sweep's way to file a human gate, and `converse-signoff.sh` still
  resolves one it finds.

## Tests

- `converse-hold.test.sh` — the hold files no demand and places no `blocks`
  edge on any item, stamps the began-trace, and lands even with no takeaway
  writer; the stamp gate still fails closed.
- `converse-signoff.test.sh` — the `--ruled no` path re-files no demand; the
  `--ruled yes` path still resolves an open demand it finds; the static
  contract pins the hold to no-demand and the signoff to resolve-not-re-file.
- `converse-fold-scope.test.sh` / `converse-claim.test.sh` — the BEGAN gate
  reads the began-marker as a real hold, and the legacy `gc.demand_for`
  recheck path still fires.
