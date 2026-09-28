---
name: Helm board live-state derivation model
description: The model by which a helm-board tile derives its kind, section, and state from live execution signals rather than static metadata-key presence; the audit of the presence rules it supersedes; and the slice of it that lands with this bead. Read when changing how the board classifies a tile.
---

# Helm board live-state derivation model

## Principle

A tile's kind, section, and state derive from LIVE truth — an in-progress
molecule, a claimed live worker, real dependency edges — and a static metadata
key is an input to "who must act next", never the classifier itself. When the
city is acting on a bead, the bead is working, whatever stamp it also carries.

This is the first story of epic tk-ikpyzn. The shared tri-state core it consumes
is `services/gctk/prstatus` (`prstatus.Derive`), extracted by tk-ikpyzn.2 so the
helm board and the GitHub PR `status:` label derive one vocabulary from one code
path.

## The vocabulary: one tri-state, one core

Per-bead liveness is the three-value state `prstatus.Derive` returns, precedence
`needs-attention > working > needs-review`:

- **working** — the city holds the ball. Live work is anchored to the bead (a
  molecule, a claimed worker, an open routed child), or an approved PR is
  merging. No human input is needed now.
- **needs-review** — settled at the head; the only thing left is a human's review
  verdict.
- **needs-attention** — stopped without settling: a merge or rebase hold, the
  signoff-cap park, or an approved PR wedged at merge-state BLOCKED with nothing
  in flight. A human must unstick it.

`prstatus.Derive` is pure: it takes `prstatus.Facts` (the holds, the dated
posture and merge-state, and an in-flight COUNT) and returns the state. The
caller gathers the facts; the board gathers them from the bead it already holds,
the label path from `gc bd`. The rule lives in one place, so a bead's board
liveness and its PR label cannot disagree about the logic.

## Live signals the board observes

| Signal | Source | Meaning |
|---|---|---|
| live workflow over a bead | `Facts.Inflight` + `Facts.wfLive` | a graph.v2 molecule whose session is live stands over the bead |
| live claimed worker | child `status==in_progress` + `Facts.ownerLive` | a child claimed by a session still in `gc session list` |
| session liveness | `Facts.OwnerState` (`gc session list --state all`) | ground truth under the two signals above |
| held (visit present) | `Facts.Visits` | a converse sitting is holding the anchor |
| real dependency edges | `Anchor.WaitingOn` / `WaitingOnClosed` (`blocks`) | which routed work a ruling or park is still waiting on |

Liveness is always re-derived against `Facts.OwnerState` at render time
(`wfLive`, `ownerLive`), never trusted from the gather: a molecule that has
drained since the gather stops counting at once, so a fixed false "stranded" is
never traded for the worse false "in flight".

**Known gap — recent branch commits.** The render path makes no git or GitHub
call, so "the branch moved" is not an observed signal; the merge cadence records
branch-head position as the dated `pr.machine` / `pr_posture` markers the board
reads back. A first-class branch-commit signal is future work (see Successors).

## The presence rules this model supersedes

A census of every place the classifier branches on the mere PRESENCE or VALUE of
a static metadata key rather than on a live signal. Kind is decided once in the
sources and never re-derived; `internal/board/derive.go` branches on
`Anchor.Source`.

**Kind selection — `internal/source/beads.go` (`metadataAnchors`, and the mirror
`internal/source/supervisor.go`):**

- `gc.takeaway` present → kind `parked`. The anchoring instance: recording a
  ruling parks an actively-worked bead.
- `gc.routed_to == "human"` → kind `human`.
- `merge_result` present → kind `merge` (the PR round-trip).
- `task_kind ∈ {review, rework}` with `anchor_bead` present → the review/rework
  leaf kinds.
- convoy `owned` LABEL absent → kind `unowned` (`applyConvoyOwnership`).

**State predicates keyed on a static stamp — `internal/board/derive.go`:**

- `humanGated` — `Source ∈ {decision, human}` or `gc.routed_to == "human"` →
  ELEVATED / gate / owed.
- `isDemand` — `gc.demand_for` present → forces owed, excluded from stand-down.
- `hasOwnRow` — `gc.routed_to == "human"` or `gc.takeaway` present → the child
  carries its own row (counted as parked, not idle).
- `isMergeAnchor` — `merge_result` present → the PR axes and `SectionReview`.
- `prPhase` — the holds / posture / merge-state truthiness for the tri-state.

The model's direction: each of these is a candidate to be gated behind, or
demoted below, a live signal — as the parked axis already is, and as this slice
routes through the shared core.

## What lands with this bead (the first slice: active/parked via the core)

The active/parked axis, expressed in the tri-state vocabulary, consuming
`prstatus`:

1. **The board consumes the shared core.** `prPhase` delegates to
   `prstatus.Derive`; the `Phase*` constants are defined from `prstatus.Working`
   / `NeedsReview` / `NeedsAttention`; the board's own copies of the hold
   truthiness and the cap-park and the `@`-split (`isHoldSet`, `isCapPark`,
   `beforeAt`) are deleted. The board no longer re-implements the tri-state — it
   is structurally impossible for the board's and the label's LOGIC to diverge,
   because there is one function.

2. **The parked active/parked axis derives through the core.** A parked subject
   with live work over it reads `working` — banded active, frontier "parked —
   work in flight" — from `prstatus.Derive`, keyed on `anchorInFlight` (the
   `wfLive` join) rather than on the `gc.takeaway` key. This generalizes the
   tk-ygeufl fix into the shared vocabulary: liveness is read from the live
   signal and phrased in the tri-state, so the classification cites what it
   observed, not the stamp.

This slice is behavior-preserving for the cases the board already derived from
live signals (the tk-ygeufl parked-in-flight arm, and the merge-anchor phase);
its deliverable is that both now flow through the single shared core, and the
model above is the design the remaining slices build to.

## Successors (deferred, tracked)

The model is larger than this slice. Each remaining piece is its own bead so no
part of this spec is unimplemented-and-unowned:

- **Whole in-flight set for the phase** (tk-ikpyzn.4). `prPhase` feeds the count
  of open review/rework children the board gathers; the label counts the anchor's
  whole `anchor_bead` set (validation passes and findings too). The board must
  gather and feed the same set so the two AGREE, not merely share the rule.
- **Human-routed / demand generalization** (tk-ikpyzn.5). A human-gated bead, or
  a demand, whose work is in flight must read working rather than as an operator
  ask — the 2026-09-27 evidence on this epic (a held item whose demand carried no
  open decision rendered as a gate). Touches `owed`, section, and the demand fold.
- **Aggregation up the parent chain** (tk-ikpyzn.6). A parent's tri-state is the
  frontier of its children's states; an epic with children working is working,
  one whose children all need attention is unable to move.
- **Frontier = tri-state, and a per-bead phase on the wire** (tk-ikpyzn.7). The
  tri-state becomes a first-class field on every tile (today `pr_phase` is empty
  on a non-merge row) and the frontier speaks it, so the board's primary
  vocabulary is the liveness state.
- **A branch-commit liveness signal** (unfiled; contingent), if the render path
  is ever allowed the read, to close the "recent branch commits" gap named above.
