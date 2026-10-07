---
name: check-gate-marker-provenance — retire or repurpose
description: Why tk-snb0di repurposed the I7 depth check onto the review-outcome graph while keeping, during the marker transition, an audit of the green markers gate-ensure.sh still reads.
---

# Decision: REPURPOSE (two arms during the marker transition)

`doctor/check-gate-marker-provenance` audited a stored `check.<lane>=green`
marker: every green marker on an open gating anchor had to name a recorded
approve verdict. Green is derived from the review-outcome graph now —
`merge.sh` and `pr-open.sh` both decide a lane green through `lane-state.sh`,
which stands a lane on a closed `task_kind=review` bead's
`signoff_verdict`/`gc.outcome`, never on the marker. tk-snb0di decides between
retiring the check and repurposing it. **It repurposes it** onto the outcome
graph, and keeps a scoped marker audit for as long as a marker consumer remains.

## Why not retire

The failure mode the check existed for did not go away; it moved. The check
protects against a merge landing on a lane no genuine approve backs. Before,
`merge.sh` trusted the marker and the check audited the marker. Now `merge.sh`
trusts the outcome bead (through `lane-state.sh`) and nothing else sweeps the
store to prove those beads coherent — `lane-state.sh` reads the stamp and
believes it, `review-outcome.sh` reads back only its own writes, and neither
sweeps for a pre-existing malformed backing. Retiring the check would leave the
beads the merge path now trusts unaudited. So the audit follows the merge path's
trust: from the marker to the outcome bead.

## Two consumers read a lane's green two ways, so the check has two arms

**Outcome arm (markerless, permanent).** Per store, for every OPEN gating anchor
(`merge_result` = `pre_open_gate` | `pull_request`), every closed
`task_kind=review` bead backing a lane — `signoff_verdict=approve` carrying a
non-empty `reviewed_oid`, the local backing `lane-state.sh` derives green from —
must record `gc.outcome=recorded` (a live backing) or `gc.outcome=superseded`
(retired). `lane-state.sh` excludes only `superseded`, so an approve carrying any
other outcome (none at all, or a value no writer produces) still derives the lane
green while standing on a verdict no writer recorded. That is the finding. The
`reviewed_oid` clause matches `lane-state.sh`'s local-backing predicate: a
backing with no `reviewed_oid` derives no green there, so it is no green risk to
audit here.

**Marker arm (transition).** `lane-state.sh` is not the only reader of a lane's
state: `gate-ensure.sh` still reads `check.<lane>` off the anchor and treats
`green` as settled, skipping a fresh dispatch. So a green marker with no backing
wedges the anchor — gate-ensure raises no review while `lane-state.sh` holds the
merge — and the outcome arm, which starts from outcome beads, never sees a green
marker that has no bead behind it at all. The marker arm keeps the original
missing-backing audit: every `check.<lane>=green` on an open gating anchor must
resolve to a backing, locally (a closed approve, or legacy `gc.outcome=recorded`
with no `signoff_verdict`, review bead naming the anchor and lane, carrying
`reviewed_oid`) or against an APPROVED GitHub review on the anchor's `pr_number`;
nothing found is an error, and a local miss whose GitHub fallback could not run
is an undetermined warning. It asks only that some backing exists — the outcome
arm rules on that backing's coherence — so the two never double-report.

## What each arm owns, and what dies when

The two arms split the old check's two halves and add the outcome dimension:

- A green lane whose backing is *missing* is the marker arm's finding; the
  outcome arm cannot see it, because a marker with no bead leaves no outcome bead
  to audit.
- A green lane whose backing is *present but malformed* is the outcome arm's
  finding; the marker arm sees a backing exists and stays silent.
- A malformed backing with *no marker at all* — the shape of the markerless
  future, once the marker writer is gone — is caught by the outcome arm alone.

The marker arm exists only while a marker consumer does. When the last consumer
reads `lane-state.sh` instead, the marker arm is removed and the outcome arm is
the whole check. Removing it before then would reopen the wedge `gate-ensure.sh`
can still fall into.

Well-formed and passing both arms: a legacy no-verdict `gc.outcome=recorded` bead
(it carries no `signoff_verdict`, so the outcome arm never fetches it, and it
backs a green marker for the marker arm), a request-changes bead, a superseded
backing, and an operator's APPROVED GitHub review (which backs a lane with no
local bead to be malformed).

## Name kept, not renamed

The directory stays `check-gate-marker-provenance`. It is the check's stable I7
identity across `docs/` and `specs/`, the review-cycle epic (tk-bw184o) is
mid-flight, and a rename risks a gascity-side doctor runner or dashboard keyed
on the name that this pack cannot see. The header, messages, and behaviour are
made honest instead.

## Scope boundary

This bead adds the outcome arm and keeps the marker arm; it does not migrate the
remaining marker consumer (`gate-ensure.sh`) off `check.<lane>`. The done-when
goal "no doctor check reads `check.<lane>`" is therefore not met by this bead
alone — the marker arm reads the marker on purpose, until the last consumer no
longer does. That completes jointly with `check-gate-integrity`'s
marker-grammar-clause retirement, a sibling that lands with the marker-writer
removal from `signoff.sh`. Both the marker writer (`signoff.sh` still stamps
`check.<lane>=green`) and the grammar clause are left untouched here, on purpose.
