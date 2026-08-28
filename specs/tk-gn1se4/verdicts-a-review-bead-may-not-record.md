---
name: The two states in which signoff records no verdict, and the one this bead gave up
description: Why the live-head requirement this bead opened with was dropped when #510 landed the narrower replacement test, what survived instead (the closed-review-bead refusal and the read-back on the dead-pin clear), and the cost that is now accepted by design. Read before re-proposing a head-equality test in signoff, or when changing how a refusal clears reviewed_oid.
---

# The verdicts a review bead may not record (tk-gn1se4)

`signoff.sh` is the only writer that clears a gate marker, spends a round of
the rework cap, and mints a rework child. Each of those is destructive and
none is undone downstream, so the states in which it must write nothing are
part of its contract rather than defensive coding.

This bead opened against one such state and landed a different one. The
rebase onto `#510` is what changed the answer, and this record exists so the
question is not reopened from the original premise.

## What this bead opened with

A review dispatched at commit A stays claimable after the branch moves to B.
When its verdict lands, `signoff.sh` clears `check.<gate>` and files a rework
child carrying findings that the commits between A and B may already have
fixed. The child is routed and claimable, so a polecat pushes a rework commit
onto the branch and spends a round of the cap on a proven no-op.

The proposed guard: `request-changes` requires the reviewed oid to **be** the
branch's live head. `approve` stays exempt, because `green@<pin>` fails the
merge's live-head condition on its own and re-gates, while a cleared marker
and a spent round are not recovered by anything downstream.

## Why that guard was dropped

`#510` (tk-bpo8cj) landed first and answers the adjacent question with a
narrower test. Its `oid_on_branch` reports `on | gone | unknown`, and only
`gone` — the pinned commit removed by a rebase, amend or squash — refuses.
A branch that merely **grew** keeps the pin `on` and binds.

That is not an oversight in `#510`. It is stated three times in what landed:

- `specs/tk-bpo8cj/review-dispatched-into-a-rework.md` separates growth from
  replacement and calls growth "the documented design and is unchanged".
- `docs/state-machine.md` says the same in the review-dispatch paragraph.
- `formulas/mol-review.toml` tells reviewers "a branch that only grew does
  not refuse".

`#510` also carries a mutation control asserting it: a probe that refuses
growth fails its two ancestor-pin assertions.

A head-equality test is a strict superset of `gone` for `request-changes`,
and the delta is exactly the case `#510` documents as intended. Shipping it
would leave the narrower refusal unreachable for that verdict and silently
negate a decision that landed with its own spec. A superset guard is not a
safer guard, and re-adjudicating a landed design is not a rebase's to do.

## The cost that is now accepted

A `request-changes` verdict at a superseded-but-present pin still clears the
marker, spends a round, and files a rework child whose findings the newer
commits may already carry. Nothing downstream recovers the round or the
marker. `#510`'s position is that the findings still describe code that is
there; the case this bead measured is the one where they do not.

That gap is open and deliberate. `GC_MAX_REVIEW_DISPATCHES` (from `#493`)
bounds how often the loop can repeat, so it degrades into a counted cost
rather than an unbounded one. Reopening it is an operator's call and needs a
new bead; it is not reachable by widening this guard.

## What landed instead

Two states in which no verdict may be recorded, neither of which `#510`
covers.

**A closed review bead.** `signoff.sh` closes the review bead itself, last.
A bead that is already closed therefore had its verdict recorded, or was
retired unjudged by `review-sweep.sh` (`#520`). Either verdict against it is
refused before the anchor is resolved: no marker cleared, no marker stamped,
no rework child, no PR comment, exit 1.

**A dead pin that did not actually clear.** `#510`'s `gone` arm unsets the
review bead's `reviewed_oid` best-effort and then writes a note and a warning
both stating the pin as cleared. `mol-review`'s load-dispatch step reads that
pin before falling back to the live head, so a pin that survives the unset
sends every later claim back to the same departed commit — the refusal's own
recovery path failing silently. A denied write fails the call; a concurrent
re-stamp returns success and changes nothing. Only a read-back separates
either from a clear that worked. The arm now re-reads the bead and, when the
pin still stands, exits 2 (the script's existing "a write did not read back"
code) naming the surviving pin, the loop it causes, and the manual
`gc bd update <bead> --unset-metadata reviewed_oid` repair, instead of the
note that would claim the clear happened.

## Verification

`signoff.test.sh`: 125 assertions, 18 new, all green.

Against `origin/main`'s `signoff.sh` the new suite fails 12 — 6 per guard —
so neither is vacuous. Among them is `the bead is never told the pin was
cleared`, which fails on main's own `gone` arm: the read-back defect this
bead's second commit diagnosed is live in what landed, not only in the arm
this branch originally wrote.

Mutating each guard out in isolation fails exactly that guard's 6 assertions
and nothing else.

## Provenance

Anchor `tk-gn1se4`; the read-back half is `tk-okjk4g`. Rebased onto
`59d858f7` for `tk-lkiqee` after `#510` and `#520` landed under the open PR.
