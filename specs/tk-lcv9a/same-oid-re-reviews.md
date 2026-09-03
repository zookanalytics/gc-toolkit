---
name: Same-oid codex re-reviews — the measured population and the guard that closes it
description: What the 98 same-commit re-review pairs in the gc-toolkit store actually were, which dispatcher bought them, and why gate-ensure.sh now refuses a dispatch at a head a recorded verdict already judged. Read this before re-reporting review-loop cost, and before building a delta re-gate.
---

# Same-oid codex re-reviews

A re-review at an unmoved branch head reads a byte-identical commit. Whatever
the first verdict found is still there, and whatever it missed is still
missing, so the second review can only re-derive the first. `gate-ensure.sh`
bought 97 such reviews.

tk-lcv9a was filed as a review-economics bug report and had already been
narrowed twice before this work: two causal hypotheses (branch shape, and a
race between a landing commit and an in-flight review) were tested and
disproved, and the bead was re-routed to characterise the same-oid population
and close it. The disproved hypotheses are in the bead body and are not
re-argued here.

## The measurement

Every bead carrying `task_kind=review` in the gc-toolkit store, all statuses
(1261 rows), grouped by `(anchor_bead, check_name)` and ordered by
`created_at`. A *pair* is two reviews adjacent in one such group. A *same-oid
pair* is one whose two `reviewed_oid` values are equal and non-empty.

`reviewed_oid` is stamped at dispatch from the live branch head, so equality
across a pair means the branch head did not move between the two dispatches.

| | |
|---|---|
| anchors carrying at least one review | 456 |
| reviews under an anchor | 1066 |
| adjacent pairs | 610 |
| **same-oid pairs** | **98** |
| distinct `(anchor, gate, oid)` groups behind them | 72 |
| all-40-hex oids among the 98 | 98 |

The oid check matters: an abbreviated marker oid can never equal a live head
and would re-dispatch forever for an unrelated reason. That is not this
population.

## Which dispatcher bought them

Two arms of the merge cadence dispatch reviews, and their titles are
deterministic and distinct: `gate-ensure.sh` writes `Review branch <branch> ->
<target>: …`, `pr-facts.sh` writes `Review PR#<n>: re-review at live head`.

**97 of the 98 successors carry the `gate-ensure.sh` title. One is
`pr-facts.sh`'s.**

That split is not luck. `pr-facts.sh`'s stale-gate arm already dedups on the
head: it reads every review with `review_branch=<branch>` across *all*
statuses and refuses when one already names the live head. `gate-ensure.sh`
had no such check. Its only memory of a prior verdict was
`already_answered()`, and that function asks a narrower question.

## Why the existing guard did not fire

`already_answered()` refused a dispatch only when a closed review had judged
the head **and** an open rework child stamped `source_review_bead=<that
review>` still hung off the anchor. Its own comment says why: an open child is
proof that the round it opened has not been tried.

Classifying all 98 pairs by the state of that child at the moment of
re-dispatch:

| rework child at re-dispatch | pairs |
|---|---|
| open | **0** |
| closed | 41 |
| none filed at all | 57 |

The guard fired every time it could see. It never had anything to see. A
closed rework child at an *unmoved* head is the tell: had the rework pushed a
commit, the head would have moved and the oids would differ. So the round was
spent without changing the tree, and the next pass bought a review of the same
commit.

Meanwhile the predecessor had almost always answered:

| predecessor `gc.outcome` | pairs |
|---|---|
| `recorded` (signoff.sh's read-back-verified verdict stamp) | 93 |
| absent | 5 |

The median gap between the predecessor closing and the successor being created
was 105 seconds; 34 of 98 were under a minute. These are consecutive reconcile
passes, not a slow drift.

## The guard

`already_answered()` now answers on two grounds, in this order:

1. **A pending round** — a closed review judged this head and an open rework
   child names it. Unchanged, and still quiet: the branch is what moves next
   and the following pass dispatches on its own.
2. **A spent one** — a review carrying `gc.outcome=recorded` judged this exact
   head, and no round is pending. Refused, because the commit is unchanged.

`gc.outcome=recorded` is the discriminator, and it is signoff.sh's own stamp,
written and read back as it closes the review. A review closed *without* it
recorded no verdict — swept moot by `review-sweep.sh`, dead after claim, stood
down — and bars nothing on its own, so the 5 pairs above stay dispatchable.
That is correct: they left no answer to re-derive.

The second ground is a hold nothing in the cadence lifts. No round is open to
move the head, and no arm moves a branch. Held quietly that is an anchor
stranded with nothing on it saying why, which is the one failure this arm is
written not to leave silent, so it costs what the dispatch backstop costs: one
`escalate.sh` visit under the `review-answered-hold` key, plus
`answered_hold.<gate>=<head>` stamped on the anchor and a note. The stamp is
pinned to the head, so a moved head is a new situation and states itself
again, and the hold clears by itself the moment the branch moves.

The first ground is checked first on purpose. A converging anchor, with the
verdict recorded, the rework child open and the head not yet moved, is the
ordinary shape of the loop working, and it must stay silent and cost no visit.

`answered_hold.<g>` is declared in `lifecycle.toml [holds] marker_prefixes`
beside `dispatch_backstop.<g>`, because it records the same kind of thing: a
bead that is not moving, for a reason the graph cannot answer. That declaration
makes `doctor/check-wait-is-an-edge` report a held anchor as UNEDGED, since
`escalate.sh` attaches its visit with `tracks` rather than `blocks`. That is
the standing posture for every marker in the list — `hold_severity = "warn"` —
and the backstop sits in it too. Unlike the backstop's, this marker is retired
by its own writer: the pass that dispatches again unsets it first, so its
presence is a hold standing now and not one that once stood.

## The machine axis gained a fifth value

The helm board reads `pr.machine` to answer whose move a row is, and a row is
owed by the operator when that axis is wedged. An anchor held at a spent
verdict is exactly that: no automated actor will move it, and a person or a
new commit is what clears it. Left recording `progressing`, the new hold would
have parked anchors on a visit while telling the board they were still in the
cadence, which is the one reading that surface exists to prevent.

`lifecycle/lifecycle.toml [machine_axis]` already says a new wedge shape earns
its own value rather than borrowing one, because the shapes are released by
different things. So `wedged-answered` joins `wedged-exception` and
`wedged-veto` in `machines`, in `derive.go`'s constants and `isWedge`, and in
the board's needs line. `lifecycle.test.sh` compares the two lists in order and
fails on drift, so both sides move together or neither builds.

Where a gate reads `exception@<live head>` and another gate is held at its own
verdict, the exception is what gets recorded. Both are wedges; the exception is
the one the convergence cap already routed a person to.

## What this refusal gives up

Six of the 98 successors flipped their predecessor's `request-changes` to
`approve` on the identical commit (54 held request-changes, 1 went to an
unstated verdict, 30 pairs had verdicts stated only on the PR, 7 followed an
approve). Those six are the path by which a stuck anchor got un-stuck under
the old behaviour.

That path is not worth keeping. A second reviewer approving a commit a first
rejected, with nothing changed in between, is the gate contradicting itself —
it means the gate can be passed by re-rolling it. Removing the re-roll is the
point, not a side effect. What replaces it is the visit: the operator gets the
decision instead of the dice.

## What is not in scope

**Delta re-gate** — reviewing only the diff since the last verdict rather than
the whole change. Its population is the pairs whose oids *differ* but whose
content does not. Of the 470 different-oid adjacent pairs, 459 have both
commits still resolvable in this checkout, and **0 of those 459 are
tree-identical**. tk-lcv9a's routing reaction counted 4 under a looser
content-sameness measure. Either count is one to two orders of magnitude below
the 98 this record closes, and delta re-gate additionally owes a provenance
story for what a partial review may assume about the part it did not read.

**The re-gate dispatch gap** (tk-t46nq) — a rework hand-back on a pre-open
anchor not re-dispatching codex. Closed separately, merged as `ae3af05a`.

**Review exhaustiveness** — whether one pass should enumerate every blocking
finding at once instead of the one to four each round surfaced. tk-lcv9a's body
points at tk-z9qob for this; tk-z9qob is a different question (a reviewer
finding must not be overruled by an unverified claim in a review bead) and does
not carry it. Nothing tracks exhaustiveness today.
