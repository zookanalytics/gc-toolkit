---
title: Review engagement under conflict and human-hold
convoy: tk-x4oc74
status: design
author: gc-toolkit.mechanik
date: 2026-09-28
---

# Review engagement under conflict and human-hold

A PR under an owned-convoy integration branch received a human `CHANGES_REQUESTED`
review with nine inline comments and got no engagement — no reactions, no threaded
replies, no finding beads — while its tile read `status: working`. Three independent
defects produce that outcome. Each is fixed below; the fixes share one branch and
graduate together.

## Defect A — the conflict-gate suppresses review acknowledgment

The feedback pipeline (`assets/scripts/pr-facts.sh`, run by the `refinery-reconcile`
order) ends any anchor whose PR is `DIRTY`/`CONFLICTING` at `pr-facts.sh:1069-1074`
with a `continue`, before the feedback-routing arm at `:1305`. A conflicting PR
therefore files no findings and advances no watermarks, and the write-back sweep
that adds reactions and replies — gated on `pr_comment_disposition` at `:2119-2120` —
finds nothing to act on.

Acknowledging a review depends on nothing about mergeability. Only landing a rework
does.

## Defect B — a blocked child reads as "working"

The GitHub `status:` label is derived in `services/gctk/prstatus/prstatus.go`
`Derive`: `InFlightCount > 0` returns `working` (`:87-88`), and the in-flight query
includes `blocked` status (`services/gctk/internal/cli/prstatus.go:95`). A `blocked`
child counts as "the city holds the ball, no human input needed" (`:29-32`). The
derivation never asks whether the in-flight child is itself blocked, whether it is a
`visit`, whether it carries `gc.routed_to=human`, or what the review decision is.
There is no `needs-human` state in the taxonomy.

The web board's phase chip re-derives the same three values differently — it counts
only rework children in `{open,in_progress}` and excludes `blocked`
(`services/helm/internal/board/derive.go`, `services/helm/internal/source/beads.go:951-956`)
— so the label and the board disagree for the same PR, against the "one code path,
cannot disagree" claim at `prstatus.go:5-7`.

## Defect C — the visit route drops the comment link

When feedback routing picks a visit over a rework (`pr-facts.sh:1335-1338`) it records
no inline comment ids; the rework path records `finding.comment_id` at `:1698`.
`assets/scripts/pr-visit-comment.sh` posts a `<!-- gc:visit:tk-xxxx -->` marker only as
a top-level PR comment, never on an inline thread. So when specific comments are the
reason for a visit, nothing ties them to it.

## Design

### A — decouple acknowledgment from merge-state

Review acknowledgment — reactions, finding-bead capture with `finding.comment_id`, and
inline back-links — runs regardless of merge state, so a `DIRTY`/`CONFLICTING` PR still
routes its feedback. Only the rework *landing* stays gated on a mergeable base; the
refinery resolves the conflict at landing via the rework's `prepare_mode=merge`.

Identify what the conflict-gate legitimately guarded (candidate: dispatching a rework
onto an unmergeable branch) and keep that specific guard on the dispatch/landing step,
not on acknowledgment.

Acceptance: a conflicting PR carrying an unengaged human review gains reactions,
finding beads, and inline replies on the next reconcile tick; no rework merge is
attempted while the base conflicts; the guard the gate protected is preserved on the
landing path under test.

### B — a blocked-on-human frontier is never "working"; surface the attention type

The status derivation does not return `working` when the anchor's live frontier is
blocked, or blocked on a human item; it returns `needs-attention`. No new label value
is added — the three-value taxonomy stays generic. The GitHub label and the board
phase chip consume one shared derivation so they cannot disagree.

Separately from the label, the *reason* for attention is surfaced on a field the board
can render, distinguishing at least "a visit awaits engagement" from "a stalled or
blocked frontier" (alongside the existing cap-park, merge-hold, and rebase-hold
causes). The label stays coarse; the reason carries the specificity.

Acceptance: a convoy whose only in-flight child is blocked, and blocked on an open
`gc.routed_to=human` visit, derives `needs-attention` on both the label and the board
chip; the attention-reason distinguishes visit-engage from stall; a shared-derivation
test proves label and board agree.

### C — link comments to a visit only when analysis routes them there

The common path is unchanged: comments resolved by a mechanical rework already carry
`finding.comment_id` and receive reactions and replies. The new behavior applies only
when feedback analysis concludes that one or more comments need a visit — human
engagement rather than a mechanical fix. Then the visit bead records those comment ids
and each such inline thread receives a `↳ tracked as tk-<visit>` back-link, so the
human sees the connection on the comment they left.

Acceptance: when routing sends specific comments to a visit, the visit bead carries
their comment ids and each such thread gets a back-link reply; the rework path is
untouched.

## Sequencing

A and C both edit the `pr-facts.sh` feedback-routing region, and C builds on the
acknowledgment flow A introduces, so C lands after A. B is independent, in
`prstatus.go` and the board derivation.
