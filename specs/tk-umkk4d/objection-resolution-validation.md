---
name: Objection-resolution validation
description: Gives the objection-bead lifecycle's third act — validate that the objection was resolved, then close the bead — a structural owner in the merge cadence, reached regardless of how the fix landed, so a re-approved objection cannot stay open holding the merge.
---

# Objection-resolution validation

An objection bead closes when an owned step validates that the objection was
resolved, and that step runs every merge-cadence pass regardless of how the fix
arrived. A fix unit landing on the branch is one resolution signal; a human
re-approving the PR is another, and the close follows either.

## Scope

**Mandate.** The owner of the objection-resolution flow's third act —
validate-resolution-then-close — and the signals that reach it. It covers which
component runs the close, what evidence closes an objection bead, and why a
human's re-approval closes the objections that human raised.

**Boundaries.** How objections are opened and ruled is
[review-cycle-architecture.md](../tk-ztapg/review-cycle-architecture.md): the
finding primitive, the validator's must-fix/deferred/declined ruling, lane
state, and quiescence. This design adds one close path to that model and changes
nothing about how a finding is minted or ruled. Merge mechanics past the gate
predicate stay with [refinery-merge-cadence.md](../../docs/refinery-merge-cadence.md).

## The objection-resolution flow has three acts, and only two had an owner

An objection bead is a `finding` or a `rework` minted from a review that asks for
changes. The flow that resolves one has three acts:

1. **Open the objection.** Owned: the review arm files the finding (`finding.sh
   upsert`, from `signoff.sh` for a machine lane and `pr-facts.sh` for a human
   batch), and the validator rules it must-fix (`mol-validate` through
   `finding.sh set-disposition`).
2. **Do the work that resolves it.** Owned: the fix unit — a `rework` bead
   routed to the fix pool, which blocks the anchor and each finding it answers.
3. **Validate the work resolved the objection, then close the bead.** This act
   had no structural owner. Its close was inferred from one proxy:
   `finding.sh close-answered`, run per anchor by `gate-ensure.sh`, which closes
   a must-fix finding once every fix unit blocking it has closed.

The ruled design states act 3 as a single move: "when the fix unit closes, the
findings it blocked become unblocked, and `gate-ensure.sh` ... closes each
finding whose blockers have all closed"
([review-cycle-architecture.md](../tk-ztapg/review-cycle-architecture.md), "The
fix unit"). That move reads exactly one signal — a fix unit landing on the
branch — and is silent when the fix arrives by any other route.

### Where the proxy goes silent

A fix can resolve an objection without a fix unit landing:

- **An out-of-band artifact.** The objection is answered by something that is
  not a branch commit, such as a demo clip captured and attached to the PR. No
  fix unit lands, so `close-answered` finds no blocker to have closed.
- **A human re-approval.** The human who requested changes re-reviews and
  approves. Their objection is resolved by that act, not by a commit.

In both cases `close-answered` is a no-op, and the objection beads — the human
finding and the `rework` fix unit that answers it — stay open. The finding holds
the merge through its `blocks` edge and quiescence clause (a); the rework holds
it through quiescence clause (b). Nothing watches for "an approved PR still
blocked by its own resolved objection," because no arm owns re-deriving
resolution.

This is the live wedge on anchor `tk-vd66j1.3` / PR#887: the demo objection was
resolved out of band and the operator re-approved, yet the finding `tk-kljbvk`
and the rework `tk-vsq605` sat open about thirteen hours past approval, holding
the merge, until they were closed by hand in visit `tk-026mkj`. The finding was
additionally wired to block behind an unrelated check-fix (`tk-hnfz6f`), so even
a landed fix unit of its own would not have closed it.

## The design: validate resolution in the merge cadence, keyed on the signal

Act 3 gets an owner that runs every cadence pass, so it is reached for every
anchor whatever route the fix took. The owner re-derives resolution from the
signals present now, rather than firing on one event.

### The owner is `gate-ensure.sh`, beside the existing close

`gate-ensure.sh` is arm 1 of the `refinery-reconcile` order. It already owns
finding closure for the fix-unit signal (`close-answered`), already derives lane
state, and already holds the per-rig lock that makes the cadence single-flight.
The second resolution signal is read in the same arm, one line below
`close-answered`, so both close paths share one owner and one pass. Keeping the
close in one authority is the same reason the ruled design gives `gate-ensure.sh`
quiescence and lane state: one computer of a fact cannot disagree with itself.

### The signal is the recorded approved posture, source-matched

`pr-facts.sh` records each open anchor's PR review state as `pr_posture`, dated
and pinned to a head, every pass. When `reviewDecision` is `APPROVED` it writes
`pr_posture=approved`, pinned to the head a current review approved — the latest
approving review per reviewer, the same current-head approval evidence `merge.sh`'s
gate reads — so the closer and the merge agree on when a head is approved.

`gate-ensure.sh` reads that recorded posture and, when it is `approved`, closes
the anchor's **human-source** objection beads through a new `finding.sh`
verb. The lag is at most one pass (`pr-facts.sh` records the posture in arm 2,
`gate-ensure.sh` reads last pass's value in arm 1), which is immaterial against
the thirteen-hour wedge it removes.

The close is gated on the head because `pr_posture`'s head is the head the
approval covers. `pr-facts.sh` pins an `approved` posture to the commit a current
review approved, not to whatever head is live when it runs, so a push landing
after an approval leaves `approved@<approved-head>` on the anchor — a head the
live branch no longer matches — until the raiser re-approves the new head.
`gate-ensure.sh` passes the branch's live head to `close-resolved`, which closes
only when the posture's pinned head matches it and closes nothing when either
head is unreadable. Without that pin a stale approval would validate a head no
reviewer approved and drop the blockers this step exists to preserve; with it, an
unread or moved head holds the merge one more pass, the safe direction.

The close is scoped to human-source beads, and that scope is load-bearing. A PR
carries two authorities: the machine lanes and the human. `reviewDecision` is a
statement of the human authority alone — a machine finding is a bead invisible to
it. A human approval must therefore close the human's own objections and must not
clear a machine correctness finding the human never addressed. Closing only
human-source beads preserves exactly the protection the merge gate gives today:
a human approval lifts `merge.sh`'s review veto, but a machine finding's `blocks`
edge still holds the merge until its own fix lands.

### What closes, and in what order

On an approved posture whose pinned head is the live head,
`finding.sh close-resolved --anchor <id> --expected-head <head>` closes:

- **Human findings** on the anchor — `finding.source` beginning `human:` — whose
  disposition is `unvalidated` or `must-fix`. A `deferred` finding holds nothing
  and is a tracked post-merge follow-up, so re-approval leaves it open; a
  `declined` finding is already closed.
- **The human fix unit** — the `rework` answering the human batch, identified the
  way `finding.sh` already identifies it: a live `blocks` child of the anchor
  carrying no `source_review_bead` (the human-batch shape; a machine rework
  carries one). It works on the anchor's own PR branch, so closing it strands no
  separate PR.

`bd` refuses to close a blocked issue, so the fix unit closes first (it blocks
the findings), then each finding closes. Before closing a finding, the verb
strips every inbound `blocks` edge from it. That strip is what makes the close
independent of an unrelated fix unit: the `tk-kljbvk` wedge, where a finding was
wired to block behind an unrelated check-fix, closes cleanly because the close no
longer waits on any blocker the objection does not own.

## The invariant this enforces

A resolved objection cannot stay open. Once the raising human has re-approved,
every cadence pass re-derives that fact and closes the human objection beads, so
the window between "resolved" and "closed" is one pass rather than open-ended.
The close is a required act of an owned step, not an assumption inferred from a
single event, which is what act 3 lacked.

## Bounds and trade-offs

- **The machine out-of-band case is narrower and stays with the existing
  paths.** A machine lane's objection is resolved by its fix unit landing
  (`close-answered`) or by a clean re-review closing its unvalidated findings
  (`close-unvalidated`, from the approve path). A machine must-fix finding whose
  fix landed with no fix-unit bead is the same shape as a human one, but a
  machine lane has no "re-approval" signal a human does; its resolution is a
  fresh approve review bead, which the lane-green derivation already reads. This
  design does not add a machine-specific close, to keep a human approval from
  ever standing in for a machine validation.
- **An open validation pass is left to its validator.** If the human approves
  while `mol-validate` is still ruling the batch, the validation pass stays open
  and holds the merge until the validator finalizes it. That is a transient,
  self-clearing state, not the wedge: the validator runs and finalizes within the
  cadence. `close-resolved` does not close a running workflow bead from outside
  it.
- **Only an open fix unit closes on re-approval; a live or held one is left.**
  The fix unit closes only when its status is `open` — routed but unclaimed, the
  shape left after an out-of-band fix, where closing it also spares a polecat a
  claim on work the approval mooted. An `in_progress` rework has a live worker
  whose hand-off closes it the normal way, and a `blocked` one is held for a
  reason; closing either from outside would strand live or intentionally-held
  work, so re-approval leaves both. The findings close regardless — their inbound
  blocks are stripped first — so the objection never stays open holding the merge.

## Alternatives considered

- **Close from `pr-facts.sh`, where the review state is read.** `pr-facts.sh`
  already reads `reviewDecision` and reconciles findings against reviews in the
  write-back sweep (findings-cleared dismisses the review). Adding the reverse
  there would co-locate the signal read, but it would split objection closure
  across two arms. The ruled design assigns finding closure to `gate-ensure.sh`;
  reading the recorded posture from there keeps one owner and costs no second PR
  read.
- **Close the finding when its lane derives green.** A GitHub approval greens
  every lane (an approval names no gate), so "lane green" cannot tell a human's
  approval from any approval, and using it would let a human approval close a
  machine finding. Keying on the human-source scope of the bead, not on lane
  green, is what keeps the machine protection intact.
- **Widen `close-unvalidated --lane human`.** That verb closes only
  `unvalidated` findings, so it would miss a human finding already ruled
  must-fix — the wedge's own shape — and would not close the fix unit. A verb for
  the resolution signal is distinct from the lane-clean-on-approve signal.
