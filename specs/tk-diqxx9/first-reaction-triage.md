---
name: First reaction as first-level triage (tk-diqxx9)
description: Why mol-first-reaction's terminal step has three exits instead of one hardcoded visit, what each one writes, and the placement evidence carried over from tk-j81t84 — read before changing the disposition set or the proactive pool's placement.
---

# First reaction as first-level triage (tk-diqxx9)

## What changed

`mol-first-reaction`'s terminal step had one exit. Its title was "File the
visit, leave the bead open, and drain", and its body hardcoded a `gate-visit`
block routed to the converse pool, so every bead a reaction touched became a
request for the operator's attention whatever the bead actually needed.

It now has three, chosen from the `## Disposition` line the card ends with:

| Disposition | The exit | What it leaves behind |
|---|---|---|
| actionable | release the bead TO a pool | a routed, unassigned, open bead a worker claims |
| blocked | write the wait as a `blocks` edge | a bead held by a named bead, in the same store |
| ruling | file the visit | a held conversation the operator lands in |

`assets/scripts/first-reaction-dispose.sh` performs all three and records which
one and why on the bead (`gc.first_reaction`, `_reason`, `_target`, `_at`)
before it acts, so a wrong call is legible afterwards rather than silent. None
of the three closes the work bead.

## Why the exits are these three

They are the three states a bead can be in when someone competent has just
read it: it can be worked, it is waiting, or it needs an answer first. Two of
them already had a primitive in the pack and neither was reachable from this
formula.

**Actionable is a route, not a sling.** A routed, unassigned, open bead is
exactly what a pool's find-work offers, and the pool's own prompt supplies the
method — which is how a bead reaches the polecat pool with no molecule poured
on it at all. Slinging instead would pour a second workflow onto a bead that
already carries the reaction's, and a polecat counts two convoys on one bead as
a double dispatch and parks. So the exit stamps `gc.routed_to` and leaves the
card as the dispatch note.

**Blocked is an edge, because prose holds nothing.** A bead nobody has held is
still `ready`, still offered, and still claimed by the next worker who reads
it. `gc-helm.sh takeaway --waiting-on` already wrote that edge for converse
sittings; the blocked exit is the same writer reached from the reaction, plus
two things the sitting does by hand: it files the blocker when the wait is not
a bead yet (deduped by `--blocker-key`, so one recurring cause is one bead
rather than one bead per instance), and it can arm
`deferred-dispatch.sh` so the blocker closing is what routes the work.

The edge must name a bead in the same store. A `bd dep add` naming another
rig's bead answers `✓ Added dependency` and holds nothing, so the script
refuses a cross-store id and names the remedy (a demand bead in the subject's
own store) rather than writing an edge that reads as a hold and is not one.
This is component-model I1, in the shape that document specifies.

**Ruling stays exactly as it was.** The `gate-visit` block is unchanged and
still marked, so `gate-visit.test.sh` guards this copy with the others. What
changed is that it is now the minority case: a question whose answer changes
what gets built, rather than the only thing the formula could do.

## The one bead that is never triaged on its merits

A subject carrying `gc.origin=operator` was created by `gc-visit-open` from a
topic a human typed and is waiting to talk about. The dispose script refuses
the routing and holding exits on it. Answering a commissioned topic with a
dispatch would leave the operator with a topic that looks filed and is silently
forgotten, which is the outcome that intake path exists to prevent
(`docs/gascity-human-engagement.md`).

## What bounds the actionable exit

One `tools/gc-proactive.sh scan --sling` sweep is capped at
`GC_PROACTIVE_SLING_CAP` reactions, default 5 — the polecat pool's own
`max_active_sessions`, so a sweep never hands out more than the city can start
working in one cycle. What the cap skips is named on stderr and stays a
candidate: a bead leaves the scan only once a reaction has advanced it.

The other half is judgment, and it is in the formula text: a reaction routes
the ONE bead it reacted to, and where several beads share one cause the useful
filing is one bead naming the cause, not one bead per instance. That lesson is
the deacon visit backlog, where one doctor check produced eight rows.

`scan` itself is still operator-driven, with no order behind it. Scheduling it
is deliberately not part of this change: the exits land first, and what the
pool does with real beads is the evidence for turning the tap.

## `deliverable` is a branch again

`tools/gc-proactive.sh deliverable` answers "would a slung reaction actually be
picked up?" for `gc-visit-open.sh`, which files a bare visit when the answer is
no. It returned a constant yes, which is not a branch.

It now reads this city's agent roster and answers **no** on a positive finding:
no agent registered at the pool target, the pool suspended, or the pool capped
at zero slots. A roster it cannot read answers **yes**, because absence of
evidence is not evidence the pool is gone, and a false no would retire the
framing city-wide.

## Placement: not the review triage gate's front half

This section is the surviving half of the tk-j81t84 determination, kept because
the argument is sound and uncontested. Its other half — deferring the work to a
"work feeder" component that exists nowhere in the tree — is what this bead
replaces.

`specs/2026-08-review-gates/scope.md` asked where proactive/first-reaction sits
once the review triage gate exists, and whether first-reaction becomes that
gate's front half. It does not. The two mechanisms share a shape — a cheap,
small-context, one-shot pass that decides what happens next and records the
decision on its subject — and they share nothing else. Every row below is a
difference a merged design would have to reconcile.

| | `check.triage` | `first-reaction` |
|---|---|---|
| Subject | a diff, pinned at `reviewed_oid` | a bead, plus its one-hop universe slice |
| Input | charter, review bead, diff | bead body, slice, optional PR/CI fetch |
| Output | `check_set` widening, `check.triage=green@<oid>` | a card, a disposition, `gc.takeaway`, `gc.proactive_reaction=1` |
| Who reads the output | `gate-ensure.sh` and `merge.sh` | a human, or the pool the disposition routed to |
| Failure if missed | an unreviewed change lands | a bead sits un-advanced |
| Where the failure lands | the merge critical path | the human's queue |
| Staleness model | re-stales when the head moves | a snapshot, with each fetched fact freshness-stamped |
| Pool | `polecat-codex`, shared with the dedicated reviewers | `proactive`, its own rig pool, cap 2, mr-only |

Four of those rows are load-bearing on their own.

**A bead has no diff.** At filing time there is no anchor, no `check_set`, no
commit to pin a verdict to. The whole vocabulary triage writes in —
`green@<oid>`, monotonic widening, waivers against a charter menu — has no
referent on a bead that has not been worked yet.

**The outputs have different readers.** Triage's output is machine-consumed:
gate-ensure dispatches what the widened set names, and merge.sh refuses to
merge until each named gate is green. A first reaction's output is read by a
human, or by the pool its disposition routed the bead to. The two stamps it
leaves that machines do read — `gc.takeaway`, which
`assets/scripts/liveness-sweep.sh` classifies as held-by-design, and
`gc.proactive_reaction`, which drops the bead from the scan — both say the same
thing: stop surfacing this.

**The failure modes want opposite handling.** A missed gate is a correctness
failure on the merge path and must fail closed. A missed first reaction is a
latency failure in the human's queue and must fail open, because holding a
merge for a conversation nobody is waiting on is worse than the latency.
Merging them puts human-latency work on the merge critical path and gives the
merge gate a second mandate. The pack has refused this shape before: the
liveness sweep was built as its own order rather than a witness-patrol step
because "different failure classes, different cadences"
(`specs/2026-08-fresh-start/liveness-and-triage-spec.md` §2).

**The pools cannot be shared in either direction.** `agents/proactive/`
PROVENANCE gives the reason for the separate pool: routing proactive work into
the impl pool would starve real implementation (head-of-line blocking). The
same argument applies to polecat-codex, which serves both review methods on the
merge critical path. Running first reactions there contends with review;
running review on proactive's 2-slot cap throttles the merge cadence.

## What this leaves open

**The candidate query.** `scan` decides which beads get looked at, and it is
run by hand. The runbook's work-feeder item
(`specs/2026-08-rewrite/cutover-runbook.md`, step 9 item 11) is that gap; a
first reaction now converts the bead in front of it, which is the disposition
half of what that item describes, not the discovery half.

**The blocked exit's filing may have a better owner.** A `gc-helm demand`
verb is in flight on the converse side (PR #473's sibling, PR #480): it files
what a person owes as a bead and blocks the work on it, which is the same
primitive as this exit's `--blocker`. If it lands, `first-reaction-dispose.sh`
should delegate that filing to it rather than keep its own create-and-block
pair. Nothing here depends on it, and it is not on main.

**Whether the classification is any good.** Nothing yet measures how often a
routed bead comes back or a visit turns out to have been work. The disposition
and its reason are on the bead precisely so that question can be asked from the
ledger later.
