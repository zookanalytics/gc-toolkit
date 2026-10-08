---
name: gc.outcome=recorded read as an approval — locate the detector, drop the inference
description: Why tk-nvtqdq removed the "no signoff_verdict + gc.outcome=recorded ⟹ approve" inference from the three readers that derived a review lane's green, and what the live evidence was.
---

# Decision: a close with no signoff_verdict backs no lane

`gc.outcome=recorded` is a bookkeeping stamp that a review's result was written
down. It names no verdict. `signoff.sh close_review` co-stamps it with
`signoff_verdict=<verdict>` on **every** close, approve and request-changes
alike, so `recorded` alone cannot tell an approve from a request-changes.

## The detector (the bead asked to locate it first)

Three readers derived a lane's green from the pre-`signoff_verdict` shape — a
closed review bead carrying `gc.outcome=recorded` and **no** `signoff_verdict`
— as if it were an approve:

- `assets/scripts/lane-state.sh` (the green derivation that `merge.sh`,
  `pr-open.sh` and `gate-ensure.sh` run; `merge.sh` gates the merge on it)
- `assets/scripts/review-outcome.sh` `backing_ids` (the idempotency guard that
  decides whether `back-lane` files a fresh approve bead)
- `doctor/check-gate-marker-provenance/run.sh` RESOLVE A (the auditor that is
  meant to catch exactly this class of unbacked green)

`review-outcome.sh` `superseding_review_ids` reads `gc.outcome=recorded` too,
but deliberately: a supersede must retire *every* recorded verdict, approve or
request-changes, so it stays broad. `gate-ensure.sh reviewed_at_head` reads
`recorded` as "a verdict exists at this exact head" for its per-head bar, which
is verdict-agnostic by design. Neither infers approve, so neither changed.

## Why the inference was never sound

Pre-`signoff_verdict` `close_review` (before #614, 2026-09-03) wrote
`gc.outcome=recorded` with no verdict stamp, and it was called for both approve
and request-changes. So a bead of that shape could carry either verdict; the
readers assumed approve.

Live proof in the gc-toolkit store at the time of the fix: of 34 open gating
anchors, two lanes were backed only by a no-`signoff_verdict` bead —
`tk-iunfnh/codex` (backing `tk-us88pf`) and `tk-wwmxpe/codex` (backing
`tk-soef8d`). Both backings were **request-changes** verdicts, and neither
anchor carried a green `check.codex` marker, yet `lane-state.sh green` returned
green for both. `merge.sh` would have landed those branches on a
request-changes.

## The fix

Drop the `($sv == "" and $oc == "recorded")` disjunct from all three readers. A
local backing is now a closed `signoff_verdict=approve` bead that is not
superseded. A close carrying no `signoff_verdict` backs no lane locally; its
green is corroborated only by an APPROVED GitHub review (`lane-state.sh`'s
`github_approved` fallback, the check's RESOLVE B) — the operator-approval path,
which is independent evidence. The two live request-changes-backed lanes flip to
not-green, which returns them to the re-review their verdict asked for.

Blast radius was those two lanes; every other open gating anchor carried a
modern `signoff_verdict=approve` backing or a GitHub approval, so no legitimate
green was withdrawn.

## The documented rule

Three documents still stated the removed inference: the `signoff_verdict` entry
in the registry (`lifecycle/lifecycle.toml`), the I7 invariant row in
`docs/component-model.md`, and the check's own description
(`doctor/check-gate-marker-provenance/doctor.toml`). The operator ruled (visit
tk-rc4qbm7) that the registry and the I7 text be amended in place before merge.
The check's description states the same I7 rule, so it was amended with them.
All three now state the rule the readers enforce. A close with no
`signoff_verdict` backs no lane locally, and only an APPROVED GitHub review
corroborates a lane resting on one.

Follows [[../tk-snb0di/decision.md]] (the two-arm repurpose of this check) and
the lane model in [[../tk-ztapg/review-cycle-architecture.md]].
