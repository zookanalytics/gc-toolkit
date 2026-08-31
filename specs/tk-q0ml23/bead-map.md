---
name: How the PR round-trip design lands against the beads already in flight
description: For each bead the tk-xns4d8 initiative already carries, whether this design amends it, depends on it, or leaves it alone — so nobody rediscovers the overlap by building the same thing twice.
---

# Disposition of the beads already in flight

tk-xns4d8 maps the beads that each fix one leak in the operator's PR
round-trip. This document says what `state-model.md` and `surface.md` do to
each of them, and to the ones adjacent.

## Amended, in two narrow places

**tk-jus6e4** — PR review posture is read and discarded every pass. Not
superseded as a bead. It owns the writer and the watermarks, and the
conversation axis is unbuildable without it. Two of its clauses change.

The first is the **value set** in its direction, item 2: that `COMMENTED`
becomes one of the recorded values. `COMMENTED` is GitHub's vocabulary for what
a reviewer did, and it does not answer whose turn it is. Two `COMMENTED`
reviews on one pull request, one answered and one not, are the same value.
Record the conversation position from `state-model.md` instead: `quiet`,
`outstanding`, `covered`, `asking`, `answered`.

The second is the **set of id spaces**. tk-jus6e4 watermarks the two review
spaces, the inline comments on `pulls/N/comments` and the bodies of `COMMENTED`
reviews on `pulls/N/reviews`, and rules that a plain issue comment carries no
review and raises no posture. That is right for posture, which records what a
reviewer did. It is too narrow for the conversation axis, which records whether
the operator is waiting. Measured across the repository, 23 of the 447 issue
comments come from a non-city account, and every one of them sits on a pull
request. `SELF_LOGIN` classifies all 23 as human, and `pr-facts.sh` sees none
of them, because the endpoint they arrive on is not one it fetches. Under the
two-space set they fall outside `outstanding`, `covered` and `answered` while
remaining inside what `quiet` excludes, which leaves the state the bead calls
"operator commented, city has not yet noticed" with nowhere to be recorded. So
tk-jus6e4 watermarks `issues/N/comments` as a third space, on the same terms as
the other two and never merged with them. Whether an outstanding
issue comment also holds the merge, the way a recorded `commented` posture does,
stays tk-jus6e4's call.

Every other clause stands unchanged, including the `<value>@<oid>` shape, the
monotonicity requirement on each watermark, the routing requirement on an
outstanding comment, and both constraints — no ruleset change, no new scheduled
scanner. The third space adds one endpoint to a pass `pr-facts.sh` already
makes for every open anchor.

Whoever implements tk-jus6e4 should read `state-model.md` first and write the
position, not the posture. GitHub's `reviewDecision` remains an input to that
derivation; it stops being the thing stored.

Nothing else in the initiative is amended.

## Depended on

**tk-lb3u4m** — the operator's queue as the board's default view. The PR rows
render inside its `Tile.Owed` partition and its owed-first ordering, and they
extend its empty-state contract rather than adding a second one. Its phase 1 is
open on PR #498. The implementation bead cannot land before it without
inventing a second surface.

**tk-s4fg87** — the target model for work that is not moving. `asking` is its
hold primitive with nothing added: an open `blocks` edge from the anchor to a
demand bead in the same store. Its phase 1 makes that edge mandatory at the
writers, which is what makes `asking` assertable rather than optional.

Its phase 3 converts capped anchors into a decision bead plus an edge, fifteen
of them city-wide at the time it measured. Those anchors are the `wedged` cell.
After that conversion, `wedged` and `asking` are the same primitive read two
ways, and the bespoke wedge derivation in `state-model.md` becomes a
compatibility path for anchors the conversion has not reached. It does not become dead: the conversion repairs
existing wedges, and the cap will keep making new ones until something files
the demand bead at the moment it fires.

**tk-5r1a12** — the `check-wait-is-an-edge` doctor check, tk-s4fg87's phase 0.
Not a dependency, and worth naming anyway: it is one of the six anchors sitting
at `exception@<live head>`, which is the state it exists to make checkable.

## Unaffected

**tk-7k4862** — closed. Made the end of a sitting pass through the declared
state space, which added the `held` merge state.

One constraint falls out of it that the implementer needs. `held` is entered
only from `unanchored`, because `merge.sh`, `gate-ensure.sh` and `pr-facts.sh`
each enumerate anchors by their gating state, and moving an anchor to `held`
drops it from all three. So a PR anchor that is `asking` must **not** be moved
to `held`. The conversation is recorded by the edge and by `pr.conversation`,
and the anchor stays at `pull_request` where the cadence can still see it.

**tk-d6ixcw** — closed. Made converse's Prime step read the PR conversation
when its subject carries `pr_number`. Complementary rather than overlapping:
that step reads GitHub because a sitting needs the comment text, while this
surface reads the bead because a board needs a position. Once the watermarks
exist, both consume them, and a sitting can say which comments are outstanding
instead of counting them.

**tk-qs1j6, tk-t46nq, tk-w26b6** — closed. The 2x2 of an absent or stale codex
marker, pre-open and post-open. Their fixes are what make machine
`progressing` derivable from a marker that is absent or not bound to the live
head, which is the marker classification at `gate-ensure.sh:378-398`.

Their grid does not contain the wedge, and it is worth saying why so that the
next reader does not go looking. Every cell of that 2x2 is a marker the cadence
cannot see or cannot trust. `exception@<live head>` is a marker that is present,
current, trusted, and still ungreenable by any automated actor. It is settled by
construction, which is exactly why no pass raises it.

**tk-qz2vi, tk-m5jfj** — open. Both are spurious re-dispatch: a codex review
sent onto an already-green anchor, and a re-gate burned on an already-merged PR
under a degraded `gh`. They change how often machine `progressing` is entered,
not what it means, and the surface renders them faithfully as a PR that looks
busy when it is not. Neither blocks this work, and neither is helped by it.

**tk-edvlur** — open, armed behind tk-jus6e4. It resets the signoff round cap
when the anchor receives new operator feedback, on the ruling that a review is
new input rather than a failed round. Not a dependency, and it changes the
wedge's future: once it lands, an operator comment is itself a release path out
of `wedged-exception`, which today has none but a hand-edit. The derivation in
`state-model.md` does not change, because it reads the marker rather than
predicting who will clear it, and a released anchor simply stops matching.

**tk-01n5cc** — open, and itself wedged at `exception@<live head>`. GitHub
write-back: acknowledge a comment, reply when the work lands, resolve the
thread. Independent in both directions. It changes what GitHub shows and this
surface reads the bead, so neither waits on the other.

They meet at one place, and it is worth wiring deliberately when both exist.
The reaction tk-01n5cc posts when it files a bead from a comment is written at
the same moment the conversation axis moves to `covered`, from the same fact.
Whoever builds the second of the two should make one write drive both rather
than letting the acknowledgement in GitHub and the position on the bead drift
apart.
