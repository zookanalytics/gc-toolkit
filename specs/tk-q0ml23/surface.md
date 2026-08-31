---
name: The helm PR surface
description: What the helm board renders for a pull request and where those rows sit inside the operator's queue — the gather rule, the additive wire fields, the empty-state contract, and the scope of the implementation bead this design produces.
---

# The helm PR surface

Helm answers where a pull request stands. GitHub keeps the conversation, and
every row carries a link into it, because line-level commenting stays there.
The surface never reproduces a comment thread.

Read `state-model.md` first. This document spends its two axes and does not
re-derive them.

## The three questions

The operator's framing, from the ruling on tk-xns4d8, is the acceptance test.
At a glance the surface says which pull requests have work actively being
covered, which are waiting on the operator, and which are wedged.

That maps onto the model exactly. Covered is machine `progressing` or
conversation `covered`. Waiting on the operator is the owed rule in
`state-model.md`. Wedged is machine `wedged`, which is inside the owed set and
has to stay distinguishable within it, because a wedge does not become
tractable by being queued behind three comments.

## A PR row is an anchor row

There is no new object. `doctor/check-one-anchor-per-pr` asserts one open
gating anchor per pull request, so the anchor already is the PR's row, and the
PR facts attach to the tile it already produces.

The row is a MERGE ANCHOR's row, not a pull request's, and the distinction is
load-bearing. An anchor at `pre_open_gate` has a branch, a gate set and a
machine axis, and no PR number yet. Six of the seven wedged anchors measured in
`state-model.md` are in exactly that state, so a surface keyed on `pr_number`
would omit the majority of the condition it exists to show. `pr_number` is a
field on the row, absent before the PR opens, and never the selector.

This is what tk-lb3u4m's ruling requires in practice: PR rows belong inside the
board's default surface, not beside it. A separate PR list would need its own
ranking, its own empty state and its own partition, and the operator would have
two queues to reconcile.

The partition is already built. tk-lb3u4m puts `Tile.Owed` on the wire and
orders the board owed-first, oldest-owed first. A PR row participates by
setting `Owed` from the rule in `state-model.md`. Nothing about the ordering,
the sections or the empty state changes shape.

## Gather: read the bead, not GitHub

The board's source layer opens each rig's bead store directly and shells out to
`gc` for what beads cannot answer. It must not add a per-render GitHub read,
for three measured reasons.

Cost. Reading the conversation for the fourteen currently open pull requests
costs about twenty seconds against a 45-second cache TTL, so a cold render
would spend nearly half a cache generation inside `gh`.

Accuracy. A single `gh pr list` reports `mergeStateStatus=UNKNOWN` for nine of
those fourteen, because GitHub computes mergeability lazily. A surface deriving
its state from that field would render two thirds of its rows unknown on a cold
read and change its answer on the next one, with nothing having happened.

Duplication. Deriving the conversation axis from raw comments means
re-implementing the watermarks inside the board, across all three id spaces,
beside the copies tk-jus6e4 puts in `pr-facts.sh`. Two implementations of a
monotonicity rule is one more than can be kept honest.

So the rows render from `pr.machine`, `pr.conversation` and the existing merge
identity keys, all read from the anchor. A `gh pr list` is permitted as an
optional freshness cross-check, under one constraint: **it may only downgrade a
row to unknown, never upgrade one.** If it reports a PR merged or closed while
the anchor still claims `pull_request`, the row says the two disagree and defers
to `pr-facts.sh`, which owns that transition. It never repairs the bead from the
render path.

## Wire fields

Additive, in `board.Tile`, appended in declaration order per the contract note
in `model.go`. The TypeScript mirror in `contract.ts` follows.

| Field | Type | Meaning |
|---|---|---|
| `pr_number` | int, 0 when absent | the anchor's `pr_number` |
| `pr_url` | string | the anchor's `pr_url`; the operator's way into GitHub |
| `pr_machine` | string | `progressing`, `settled`, `wedged-exception`, `wedged-veto`, or `unknown` |
| `pr_conversation` | string | `quiet`, `outstanding`, `covered`, `asking`, `answered`, or `unknown` |
| `pr_approval` | string | `required`, `met`, `not_required`, or `unknown` |
| `pr_owed_since` | timestamp, zero when not owed | when the operator's turn began |

Six fields, and five of them are a value read off the bead. The board computes
nothing about a merge anchor that the cadence has not already decided. The
`pr.` prefix is the metadata key's, kept because `pr-facts.sh` and `merge.sh`
are the writers; `pr_machine` is present on a `pre_open_gate` anchor that has
no PR number yet.

`pr_approval` is the owed rule's approval clause on the wire, read from the
recorded posture. The mapping is total over the posture's value set, because a
partial one leaves the implementer to invent the rest:

| `pr_posture` | `pr_approval` |
|---|---|
| `review_required` | `required` |
| `changes_requested` | `required` |
| `approved` | `met` |
| `commented` | `not_required` |
| `none` | `not_required` |
| absent, or pinned to a head that is no longer live | `unknown` |

`not_required` has to be reachable from an ordinary row. Most pull requests
carry no protection rule and no review, so if `none` fell through to `unknown`
the field would report a gap that is not there and the coverage sentence would
never clear. `commented` joins it because a comment-only review does not gate
the merge. That comment is the conversation axis's business, and this field
answers one question only, which is whether GitHub is withholding the merge for
an approval.

`changes_requested` maps to `required` because the requirement stands and is
unmet, and a blocked pull request must never render as one GitHub will let
through. It does not follow that the row is owed by the operator, and the owed
rule in `state-model.md` excludes it: a requested change is the city's move to
answer. When the city pushes, the head moves, the posture is re-derived at the
new head, and GitHub re-arms `review_required`, which is owed. This is not a
hypothetical corner. A human's rejecting review leaves the city's own gate
markers green, so `settled` and `changes_requested` is a pair a row can hold.

It is a separate field rather than a fourth machine-axis value because a PR can
need an approval while the cadence is still `progressing`, and folding the two
would make the axis pick again.

`pr_owed_since` is the one derived value, and it is what orders the queue.
tk-lb3u4m ranks the owed partition by how long a row has been owed, so the
clock has to start when the operator's turn began and hold still across every
reconcile pass in between. It is not `updated_at`: a wedged anchor is touched
by every pass, and ordering by that would sort the most neglected rows last.

The board does not decide the moment either. It takes the earliest timestamp
among the causes currently making the row owed, and `state-model.md` dates
every one of the five:

| Cause | Dated by | Phase |
|---|---|---|
| machine `wedged` | `pr.machine`'s `since` | 1 |
| approval `required` | `pr_posture`'s `since` | 1 |
| conversation `asking` | the demand bead's `created_at` | 1 |
| conversation `outstanding` | the oldest unacknowledged utterance's `created_at` | 2 |
| conversation `answered` | `pr.conversation`'s `since` | 2 |

Earliest rather than latest. A row wedged three days ago and commented on an
hour ago has been owed for three days, and the queue ranks it there. A row no
cause makes owed carries the zero timestamp, and so does a row whose only
candidate cause reads `unknown`: an unreadable input belongs in the coverage
sentence, not in a clock reporting the wait as new.

Splitting the moment across the causes is what makes it recordable at all. No
single stage of the cadence evaluates the whole owed rule, so no single writer
could keep one owed-since key honest, and each cause is instead dated by the
writer that already decides it. `state-model.md` carries the recorded half: the
`since` component, which of the five causes take it and which carry their own
instant, and the write rule that keeps a reconcile pass from restarting the
clock.

Both axes carry `unknown`, and it is a rendered value rather than a fallback to
the quiet end. This is the same choice `Anchor.WaitingUnknown` already makes for
an unreadable dependency query, and for the same reason: an unreadable axis and
a clear one are not interchangeable, and only the gather can tell them apart.

## What a row says

Six things, in one line, and nothing more:

- the PR number, linked, or the branch name when the PR is not open yet;
- the two axis values, which already name the wedge shape;
- `pr_approval` when it reads `required`, whether or not the row is owed. A
  `settled` and `quiet` row is in the owed partition for that reason alone, and
  without the word the operator sees a green pull request in their queue with
  nothing attached saying why;
- how long the current turn has been running;
- the demand, when there is one. For `asking` that is the demand bead's title,
  which is tk-s4fg87's authored headline;
- the count of unanswered human utterances, summed across the three id spaces,
  once the watermarks make that number real.

No comment bodies, no thread state, no reviewer avatars, no diff summary. The
link is how the operator gets to all of that, and it is one click from the row.

## The empty-state contract

tk-lb3u4m makes the owed section's empty state a contract rather than a test:
it renders its coverage or it renders the error, and never a blank. PR rows
extend that contract, because they add a way for it to go quietly wrong that
beads alone did not have.

- When no PR row is owed, the section states its PR coverage alongside its
  store coverage: how many open anchors carried a readable position, and how
  many did not.
- When `pr.machine` or `pr.conversation` is missing from an open gating anchor,
  the row renders `unknown` on that axis and counts against coverage. A missing
  key means the cadence has not written one yet, which is a fact about the city,
  not an all-clear.
- The sentence "nothing is owed by you" is never printed while any PR row's
  conversation axis reads `unknown`, or while any `settled` row's approval
  clause is unanswered. `Tile.Owed` is a boolean and cannot carry the third
  value the axes do, so an unread input has to surface as coverage rather than
  as a false negative on the row.

## Sequencing

The surface splits at the axis boundary, and the split is forced by what can be
asserted rather than by convenience.

**Phase 1, buildable now.** The machine axis and `asking`. Both are derivable
from beads today: `asking` is tk-s4fg87's edge, which the board's source already
reads as `WaitingOn`, and the machine axis needs `pr.machine` recorded by
`gate-ensure.sh` and `merge.sh` at the point each already reaches the verdict.
The conversation axis renders `unknown` throughout, and the coverage line says
why. This alone answers two of the operator's three questions.

The owed rule's approval clause is phase 1 as well, and it does not wait for
the conversation axis. It reads `pr_posture=review_required@<live head>`, which
is one field off the review decision `pr-facts.sh` already fetches for every
open anchor, and it needs none of the watermarks that block phase 2. Until it
is recorded, a `settled` row cannot say whether GitHub is holding the merge for
a human, and the coverage sentence counts it rather than the row reading
not-owed.

It is also what makes a wedge legible. The board already gathers
`gc.routed_to=human` beads, so the seven wedged anchors do reach it as
human-routed rows once tk-lb3u4m's gather fix lands. What no row says today is
that nothing will move them: routed to a person reads the same for an anchor
awaiting a ruling and for one frozen at `exception@<live head>` where the only
release is a head move nobody is going to make. The machine axis is that
sentence.

**Phase 2, blocked on tk-jus6e4 across all three id spaces.** The
conversation axis. `outstanding`, `covered` and `answered` all resolve to the
watermarks, and none of them can be inferred without them. tk-jus6e4 as written
covers the two review spaces, so phase 2 also needs `pr_issue_watermark` over
`issues/N/comments`, specified in `state-model.md` and dispositioned against
tk-jus6e4 in `bead-map.md`. Shipping on two spaces renders `quiet` for a pull
request the operator commented on in the conversation tab, which is the one
mistake this axis exists to prevent. Building any of it before the watermarks
land means guessing, and every failed guess resolves to `quiet`, which is the
one answer that tells the operator to stop looking.

Do not merge the two phases into one pull request. Phase 1 is honest about what
it does not know; phase 2 is what removes the not-knowing.

## The implementation bead

One bead comes out of this document, tk-nnx2gd, scoped to phase 1 and carrying
phase 2 as its stated follow-on. It is blocked on tk-lb3u4m by a `blocks` edge
and armed for the polecat pool through `deferred-dispatch.sh`, so it dispatches
itself when the partition it renders into lands. Its shape:

- Register `pr.machine` in `lifecycle/lifecycle.toml` and write it through
  `lifecycle.sh`, from the points in `gate-ensure.sh` and `merge.sh` that
  already reach the verdict. No new pass, no new GitHub read.
  `pr.conversation` and `pr_issue_watermark` are registered by phase 2,
  alongside the writer that fills them.
- Implement compare-and-preserve for the `since` component in `lifecycle.sh`,
  once, for every key that carries it. `lifecycle.sh` already reads the anchor
  before it writes and reads it back after, so the comparison costs no extra
  round trip, and putting it in one place is what keeps two writers from
  disagreeing about when a turn began.
- Record the posture from `pr-facts.sh`, on the read it already makes, and
  feed the owed rule's approval clause from it through the wire mapping above.
  If tk-jus6e4 has landed, this is its `pr_posture` key and phase 1 adds the
  `since` component; if it has not, phase 1 registers the key and tk-jus6e4
  extends the value set rather than introducing it.
- Derive `pr_owed_since` in the board's source layer as the earliest timestamp
  among the row's live causes, and leave it zero when there are none.
- Add the six `Tile` fields, the source gather that fills them from the
  anchor, and the `Owed` contribution. `pr_conversation` ships in phase 1 as a
  field that always reads `unknown`, so the wire contract does not change
  shape when phase 2 lands.
- Render the row and its link in the owed partition, and extend the coverage
  sentence.
- Cover the machine derivation with tests built from the live shapes in
  `state-model.md`: both wedges, `exception@<live head>` and a standing veto at
  the cap; an anchor whose only open blocker is a pool-routed rework child,
  which reads `progressing`; and an anchor whose only open blocker is a demand
  bead, which does not. The rework child is the shape a derivation keyed on
  `anchor_bead` gets wrong, and it is one of the two normal in-flight shapes.
- Cover the approval clause with a `settled` anchor at each posture value:
  `review_required` and `changes_requested` both render `required`, and only
  the first is owed; `approved` renders `met`; `commented` and `none` render
  `not_required`; an absent key and one pinned to a dead head render `unknown`.
- Cover the owed clock with a wedged anchor carried across two reconcile
  passes at an unchanged head, which must report the same `pr_owed_since` both
  times, and across a head move, which must restart it. Cover the earliest-wins
  rule with a row owed by a wedge and a demand bead at once.

It depends on tk-lb3u4m, which builds the partition it renders into, and on
tk-s4fg87's phase 1 for the demand edge that `asking` reads. It does not depend
on tk-01n5cc: the write-back changes what GitHub shows, and this surface reads
the bead.
