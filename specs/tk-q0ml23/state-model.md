---
name: The PR round-trip state model
description: Where a pull request sits in its round-trip with the operator, as two independent axes rather than one enum — what each value means, how it is derived, whether anything can assert it, and what has to start being recorded before a surface can render it honestly.
---

# The PR round-trip state model

A pull request in this city has two things going on at once, and they move
independently. The merge cadence is somewhere in its own machine loop:
dispatching a review, holding for a gate, or unable to act at all. Separately,
a conversation is running with the operator: they said something, or they did
not, and the city has answered it, or it has not.

This document defines both axes, gives the derivation for every value, and says
for each whether anything in the city can assert it or whether a reader has to
infer it. `surface.md` specifies what renders them. `bead-map.md` places this
against the beads that each already fix one leak in the same round-trip.

## What tk-s4fg87 covers, and where it stops

`specs/tk-s4fg87/proposal.md` owns the model for work that is not moving. Its
answer is one hold primitive and one demand primitive: a wait is a `blocks`
edge to an open bead in the same store, what a person owes is itself a bead,
and a bead that will ever block carries no `parent-child` children.

That model applies here unchanged wherever the city is waiting on a person, and
this document does not restate it. One cell of the round-trip — the city has a
question and is waiting on an answer — is exactly a hold, and its
representation is the edge tk-s4fg87 specifies, with no PR-specific vocabulary
at all.

It stops one step short of the rest. A hold has no direction and no currency.
An edge says that work is waiting and names what on; it cannot say whose turn
it is, and it cannot distinguish "they replied and we have not read it yet"
from "they replied and we answered." Both of those are edgeless: no bead is
blocked, nothing is held, and yet the round-trip is not finished. A `blocks`
edge appears in this model only at the moment the city owes an answer it has
already formulated as a question.

So the extension proposed here is exactly one thing: **a conversation axis,
with a watermark to give it currency.** Everything else is tk-s4fg87's
primitives applied to a pull request.

The extension pays back into tk-s4fg87's own migration. Its phase 3 converts
capped anchors into a decision bead plus an edge, fifteen of them city-wide at
the time it measured. Those anchors are the `wedged` cell below, and the
conversion is what turns `wedged` from a state that must be re-derived from two
scripts' predicates into an ordinary hold. A wedge is a hold nobody filed.

## The six states are not one enum

The bead behind this document lists six things the round-trip must
distinguish. Sorted by what they are actually about, five of them are
statements about the conversation and one is a statement about the machine:

| Stated | Axis | Value |
|---|---|---|
| open and never looked at by the operator | conversation | `quiet` |
| operator commented, city has not yet noticed | conversation | `outstanding` |
| city noticed and is working on the comment | conversation | `covered` |
| city has a question and is waiting on the operator | conversation | `asking` |
| city acted and the PR is ready for re-review | conversation | `answered` |
| blocked on a check that will not resolve without intervention | machine | `wedged` |

Collapsing them into one enum forces a lie whenever two are true at once, and
two are true often. PR #475 is in that shape right now. Its anchor tk-awa7hv
carries an open codex review bead, tk-7jyecv, pinned to the live head
dca48ae7, so the machine is busy. The operator's `CHANGES_REQUESTED` of
2026-08-27T21:35:09Z stands unanswered on the same PR, and the review in flight
is a gate on the branch, not a reply to them. One field has to pick, and either
pick is wrong: reporting the review dispatch hides the unanswered comment, and
reporting the comment hides that the machine is busy on something else. That is
the same failure tk-lb3u4m was filed for, one level down, with a true fact
standing in for the one that was wanted.

Two axes, rendered together, is the smallest shape that does not have to
choose.

## The machine axis

What the merge cadence can do with this anchor on its next pass. Three values.

**`progressing`** — some automated actor will act. Derived from either of: an
open bead carrying `anchor_bead=<this anchor>`, which is a review or rework
child in flight; or a `check.<g>` marker not bound to the branch's live head,
which is the condition `gate-ensure.sh` dispatches on.

**`settled`** — every declared gate reads `green@<live head>` and no child is
open. The cadence is done; the PR is waiting on approval, on the merge pass, or
on nothing.

**`wedged`** — no automated actor can move it, and none will try. Two shapes,
both measured live:

- `check.<g> = exception@<live head>`. The convergence cap stamped it
  (`signoff.sh:326-339`) and routed the anchor to `human`. `gate-ensure.sh`
  reads a marker bound to the live head as settled and dispatches nothing
  (`gate-ensure.sh:391-394`). `merge.sh` requires `green@<live head>` and holds
  (`merge.sh:87-94`). No pool claims the route `human`. The release is a head
  move, and every actor that could make one has been told not to.
- A standing `CHANGES_REQUESTED` from a non-city account with the signoff cap
  already spent. `merge.sh:300` vetoes the merge, correctly, and `signoff.sh`
  will file no further rework because the round count is at the cap. Nothing
  reads the review to decide whether it was addressed, because nothing records
  that it was.

Both are decidable from the anchor's metadata plus one `git ls-remote` for the
head. Neither is recorded anywhere, so today they are decidable only by a
reader that re-implements two scripts' predicates.

## The conversation axis

Where the exchange with the operator stands. Five values. "Human" throughout
means an account that is not the city's own GitHub identity, which
`pr-facts.sh` already resolves as `SELF_LOGIN`.

An utterance is anything a human account said on the pull request, and GitHub
puts those in three id spaces that share no counter: inline review comments on
`pulls/N/comments`, the bodies of `COMMENTED` reviews on `pulls/N/reviews`, and
plain conversation comments on `issues/N/comments`. The axis covers all three.
tk-jus6e4 watermarks the first two and rules that an issue comment raises no
posture, so the third space is an addition this design makes to it.

**`quiet`** — no human utterance in any of the three spaces.

The bead's phrasing for this cell is "open and never looked at by the
operator", and that is not derivable. GitHub exposes no read receipt, so an
operator who read the PR and had nothing to say is indistinguishable from one
who never opened it. The honest name is that nothing has been said, and the
surface must say that rather than the stronger claim.

**`outstanding`** — a human utterance sits above the acknowledgement watermark
for its own space. A watermark is the highest id the city has dispositioned in
one space, monotonic by construction, so anything above it is unanswered and
anything below it is answered. There is one per space and they are never
merged: a reply can land on an old review, and the three counters are unrelated
to begin with. tk-jus6e4 owns two of them, and this design adds the third.

**`covered`** — outstanding, and an open bead is on it. The link must be
recorded when the bead is filed, not guessed afterwards. An open review child
is not evidence on its own: PR #475 has one, and it is a codex gate on the
branch rather than an answer to anything the operator said.

**`asking`** — the city has formed a question and is waiting on the answer.
This is tk-s4fg87's hold, with no additions: the anchor carries an open
`blocks` edge to a demand bead in the same store, and closing that bead is what
ends the state.

**`answered`** — every watermark stands at the high water of its own space and
the branch head has moved since the last utterance. Both halves are needed. The
watermarks alone say the city dispositioned the comments; the head move is what
says the disposition produced something for the operator to look at.

## Whose move it is

The two axes decide one derived boolean, which is the only thing the board's
existing partition needs. A row is **owed by the operator** when any of:

- machine is `wedged`;
- conversation is `asking`, `outstanding` with nothing covering it, or
  `answered`;
- machine is `settled`, the gate set includes `approval`, and no approving
  review stands at the live head.

Everything else is the city's move, including `covered`: the operator
commented, the city filed work for it, and the next thing that happens is the
city's.

Note the asymmetry, because it is the whole point. Machine `progressing` does
not clear conversation `outstanding`. A row can be busy and owed at the same
time, and PR #475 is.

## Asserted, inferred, and the third value

Two ways a reader can learn a state.

**Asserted** — a writer recorded it at a named moment, pinned to the evidence
it was true of, in the `<value>@<oid>` shape the gate markers already use. A
reader reads it back and calls nothing.

**Inferred** — recomputed on every read from facts held elsewhere. Correct only
while the read succeeds and the derivation stays in step with the rule it
copies.

| Value | Derived from | Today |
|---|---|---|
| machine `progressing` | open `anchor_bead` children; marker versus live head | inferred |
| machine `settled` | every gate `green@<live head>`, no open child | inferred |
| machine `wedged` | `exception@<live head>`, or standing veto at cap | inferred, by re-implementing two scripts |
| conversation `quiet` | no human utterance in any space | inferred, from complete bounded lists |
| conversation `outstanding` | utterance id above its space's watermark | **not derivable** — no watermark exists |
| conversation `covered` | utterance linked to an open bead | **not derivable** — no link is recorded |
| conversation `asking` | open `blocks` edge to a demand bead | **asserted** |
| conversation `answered` | every watermark at high water, head moved since | **not derivable** |

One of the eight is asserted today, and it is the one tk-s4fg87 already
specifies. Three cannot be derived at all: they depend on the watermarks and a
comment-to-bead link that do not exist yet, which are tk-jus6e4's and
tk-01n5cc's deliverables.

That is the sequencing answer this document owes. The machine axis can be
rendered honestly now. The conversation axis cannot be rendered at all until
the watermarks land, and a surface that guesses it will be wrong in the
direction that matters: it will report `quiet` for a PR the operator commented
on, because silence is what every failed derivation looks like.

So the rule, which the board's own model already applies to dependency edges as
`WaitingUnknown`:

> Every inferred value has a third state for "could not read", and the surface
> renders it. An unreadable axis is never collapsed into its quiet value.

A gather that cannot reach GitHub, a branch whose head will not resolve, a
store that times out: each yields `unknown` on the axis it touched, and the
row says so. This is the difference between a board that is narrow and a board
that is wrong.

## What has to start being recorded

The reason none of this is readable is not that the city fails to compute it.
Every stage computes it once per pass and prints it to a log.

`merge.sh:238` prints `check 'codex' not green at live head (have '…', want
'green@…'); merge held`. That line is the machine axis, computed correctly,
written nowhere. `merge.sh:300` prints the standing-veto hold. `gate-ensure.sh`
classifies every gate into settled or needs-raising and keeps the answer for
the length of one loop iteration. `pr-facts.sh:117` fetches `mergeStateStatus`,
`mergeable` and `reviewDecision` every pass and discards all three, which is
tk-jus6e4's finding.

The recording therefore adds no scanner and no new read. Each stage records the
verdict it already reached, through `lifecycle.sh`, which is the pack's
declared single writer for anchor transitions and already applies state, route
and close as one atomic write.

Three keys, registered in `lifecycle/lifecycle.toml` like every other key the
pack writes:

- `pr.machine = <progressing|settled|wedged-exception|wedged-veto>@<head-oid>`
  — written by whichever of `gate-ensure.sh` or `merge.sh` reached the verdict
  this pass. The wedge shape is part of the value, so a reader never has to
  re-derive which of the two it is. Head-pinned for the same reason the gate
  markers are: a head move invalidates it, so a stale value can never read as
  current. It is stamped from `pre_open_gate` onward, before a PR number
  exists, because a pre-open anchor wedges the same way.
- `pr.conversation = <quiet|outstanding|covered|asking|answered>@<head-oid>` —
  written by `pr-facts.sh`, which is already the stage that reads the PR
  conversation.
- The acknowledgement watermarks, one per id space, never merged. tk-jus6e4
  specifies two of the three, `pr_comment_watermark` over `pulls/N/comments`
  and `pr_review_watermark` over `pulls/N/reviews`, and this document does not
  restate them. The third is `pr_issue_watermark` over `issues/N/comments`, on
  the same monotonic construction and registered beside the other two. Its
  writer is `pr-facts.sh`, which already reads the two review endpoints for
  every open anchor, so it is one more read on a pass that is already
  happening. Whether an outstanding issue comment also holds the merge, the way
  a recorded `commented` posture does, stays tk-jus6e4's call; the axis renders
  the utterance either way.

`asking` needs no key of its own. It is the presence of the edge, and the
derivation reads the graph.

Two constraints carried from tk-jus6e4, which owns the recording half and
should be read before any of this is built: do not loosen the repository
ruleset, and add no scheduled scanner whose only job is to look for this
condition.

## Measurements

Live gc-toolkit, 2026-08-28.

Fourteen open pull requests. Fourteen open anchors at
`merge_result=pull_request`, one per PR, which is the invariant
`doctor/check-one-anchor-per-pr` asserts. Seven more open anchors at
`pre_open_gate`.

Thirteen of the fourteen open PRs carry at least one review from a human
account. On five of those thirteen, no city review follows the human's, which
is the closest thing to an outstanding-comment count that today's signals
support. It is a poor proxy and it is offered as evidence of the gap rather
than as a number to build on: a city review is a codex signoff, not a reply, so
its presence after a comment says nothing about whether the comment was
answered. Establishing that is precisely what the watermarks are for.

Seven anchors are wedged, and six of them have no pull request at all. Those
six are the `pre_open_gate` anchors, sitting at
`check.codex=exception@<live head>` with `gc.routed_to=human` and a
`blocked_reason` naming the cap: tk-01n5cc, tk-5r1a12, tk-dchq5, tk-utjreo,
tk-xgfhj3 and tk-xhwits. Each was verified against `git ls-remote` for its
recorded branch, and in every case the exception oid equals the live head,
which is the frozen condition. The seventh, tk-65dyok on PR #513, reads
`green@<live head>` with a standing human `CHANGES_REQUESTED`,
`gc.routed_to=human`, and the cap spent. tk-01n5cc is the GitHub write-back
bead, so the initiative's own sibling is sitting in the state this document
exists to make visible.

One anchor, tk-e2tot6 on PR #532, is `green@<live head>` and routed to `human`
with no `blocked_reason` at all. That is tk-lb3u4m's "parked for you, no
question recorded": whoever parked it did not finish, and the surface should
say so rather than inventing a reason.

Six of the fourteen open PRs have an open review child, which is machine
`progressing`.

The issue-comment space, measured 2026-08-31 across the repository rather than
across the open set. `issues/comments` returns 447 comments, 424 from the city's
own account and 23 from a non-city account, which is what `SELF_LOGIN`
classifies as human. All 23 sit on pull requests, spread over 21 of them. None
of the eleven pull requests open on that date carries one, so a snapshot of the
open set reads the space as unused, and the count was taken across the
repository for that reason.

A single `gh pr list` returning the list-level fields takes about two seconds
and reports `mergeStateStatus=UNKNOWN` for nine of the fourteen rows, because
GitHub computes mergeability lazily and a cold read gets whatever is cached. A
per-PR `gh pr view` carrying reviews and comments takes about a second and a
half, so reading the conversation for fourteen PRs costs roughly twenty
seconds. The board's cache TTL is 45 seconds. Those three numbers are the
argument in `surface.md` for reading the bead rather than GitHub.
