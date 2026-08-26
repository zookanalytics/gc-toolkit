---
name: Placement determination for proactive/first-reaction (tk-j81t84)
description: Where proactive/first-reaction sits once the review triage gate exists — it is not that gate's front half, it is the work feeder's conversation disposition — with the evidence for the split and the constraints it hands the feeder design.
---

# Where proactive/first-reaction sits (tk-j81t84)

## The decision

Proactive/first-reaction sits on the **filing axis**, as the work feeder's
conversation disposition. It does not become the review triage gate's front
half.

Three claims follow, and the rest of this document is their evidence:

1. `check.triage` and `first-reaction` are two instances of one contract on
   two different axes. Neither becomes the other's half.
2. First-reaction is what performs the work feeder's "this is a conversation,
   not work" outcome. The feeder classifies; first-reaction is the disposition
   that advances a bead the classifier routes to a human.
3. The city gets one filing-side scanner, not two. The feeder's candidate
   query subsumes `tools/gc-proactive.sh scan`, which stays operator-driven
   and unscheduled until the feeder lands and replaces it.

The operator ratifies this at the merge gate like any other pack change.

## What the question was

`specs/2026-08-review-gates/scope.md`, "Costs and open questions":

> Open: where proactive/first-reaction sits in the workflow once triage
> exists — first-reaction is approximately triage-for-conversations, and may
> become the triage gate's front half. Decide during implementation.

The review-gates implementation (tk-xhwits) left it open on purpose, calling
it "a placement decision that outlives this work". The rewrite cutover runbook
filed it as step 9 item 3, which is this bead.

## Why it is not the triage gate's front half

The two mechanisms share a shape — a cheap, small-context, one-shot pass that
decides what happens next and records the decision on its subject. They share
nothing else. Every column below is a difference the merged design would have
to reconcile, and there is no reconciliation that leaves both jobs intact.

| | `check.triage` | `first-reaction` |
|---|---|---|
| Subject | a diff, pinned at `reviewed_oid` | a bead, plus its one-hop universe slice |
| Input | charter, review bead, diff | bead body, slice, optional PR/CI fetch |
| Output | `check_set` widening, `check.triage=green@<oid>` | a card in notes, a visit, `gc.takeaway`, `gc.proactive_reaction=1` |
| Who reads the output | `gate-ensure.sh` and `merge.sh` | a human, at a converse sitting or on the board |
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
merge until each named gate is green. First-reaction's card is not read back
by anything — `specs/2026-08-learning-system/internal-inventory.md` records
exactly this, that first-reaction "is a reaction loop, not a feedback loop —
nothing reads the cards back". Two stamps the reaction leaves are machine-read,
and both say the same thing: stop surfacing this. `assets/scripts/liveness-sweep.sh`
classifies a `gc.takeaway` stamp as held-by-design, and the scan drops any bead
carrying `gc.proactive_reaction`. Neither tells a downstream writer what to do,
which is the whole of what triage's output does.

**The failure modes want opposite handling.** A missed gate is a correctness
failure on the merge path and must fail closed. A missed first reaction is a
latency failure in the human's queue and must fail open, because holding a
merge for a conversation nobody is waiting on is worse than the latency.
Merging them puts human-latency work on the merge critical path and gives the
merge gate a second mandate. The pack has refused this shape before: the
liveness sweep was built as its own order rather than a witness-patrol step
because "different failure classes, different cadences" and "an 892-line
patrol should not grow a second mandate"
(`specs/2026-08-fresh-start/liveness-and-triage-spec.md` §2).

**The pools cannot be shared in either direction.** `agents/proactive/`
PROVENANCE gives the reason for the separate pool: "Routing proactive work
into the impl pool would starve real implementation (head-of-line blocking)."
The same argument applies to polecat-codex, which now serves both review
methods on the merge critical path. Running first reactions there contends
with review; running review on proactive's 2-slot cap throttles the merge
cadence.

## Where it does sit

The work feeder is the filing-side twin of the review triage gate. Its design
was written under tk-xhwits and is not implemented; it arrives at
`specs/2026-08-review-gates/work-feeder.md` when that branch lands, so the row
below is quoted rather than only cited. Its eligibility table has five tests,
and the first one already names first-reaction's job without naming
first-reaction:

> | Actionable | the bead states no done condition — it is a note, a question, or a link with no ask | escalate: it is a conversation, not work |

A bare `escalate.sh` visit performs that outcome only in the weakest sense: it
puts the bead in front of a human with no framing, which is the state the bead
was already in. A first reaction performs it properly. It reads the body and
the slice, writes the four-part card, files the visit on the subject, and
stamps the one-line takeaway the board renders as the row's NEEDS. The
operator arrives at a framed question instead of a backlog entry.

So the placement is: **the feeder classifies a candidate; when the verdict is
"conversation, not work", the disposition is a first reaction.** First-reaction
is not the classifier and does not become one. It is one of the four things the
classifier can decide to do.

This is also what the two live operator doors already are, so nothing about
them changes. `gc-helm.sh react <bead>` is the operator making that same
disposition by hand from the board. `gc-visit-open.sh` is the operator making
it for a topic that has no bead yet — it creates the subject and slings the
reaction, and the reaction files the visit. Both are the manual form of the
feeder's automatic one, which is the ordinary relationship between an operator
verb and the mechanism that later automates it.

## One scanner, not two

`tools/gc-proactive.sh scan` finds open, ready, unassigned, non-epic beads
that carry no `gc.routed_to` and no `gc.proactive_reaction`, with a non-empty
description. That is the feeder's mechanical candidate predicate, minus the
feeder's exclusions for anchors, step beads, convoys, visits, warrants, and
observations. Two scanners over the same population, disagreeing on
exclusions, is the drift the component model rejects.

The resolution is that the feeder owns the scan. Until the feeder lands,
`scan` stays what it is now: an operator-driven sweep with no order behind it.
Nothing in `orders/` or `doctor/` calls it, and that is deliberate rather than
an omission — wiring it on a cadence would re-litigate the P3 batching
resolution, which settled that "N idle beads cost one conversation, not N"
(`liveness-and-triage-spec.md`, sweep addendum 2026-08-08). A scheduled
per-bead `scan --sling` files N visits for N beads, which is the design that
resolution rejected. The runbook's own framing of the status quo — "nothing
routes beads to it on a schedule" — is therefore kept, and now has a reason
recorded against it.

The filing-side scan the city does run is the liveness sweep, which is exec
only, batches its findings into one visit per rig per pass, and reports the
delta rather than the population. Its interlock with first-reaction already
works and needs no change: `gc-helm.sh takeaway --release` stamps
`gc.takeaway` and `gc.proactive_reaction=1` in one write, which makes the bead
held-by-design to the sweep and already-reacted to the scan.

## What this constrains for the feeder

Three things the feeder's implementation inherits from this decision. Its own
"Open at implementation" list should read them as answers to two of its
questions and as one new caution.

**Which pool classifies: not proactive.** The feeder's classifier reads a
batch of candidates against a declared table and records one line per bead.
That is a batched classification, and proactive is a per-bead advance with a
2-slot cap and a fresh session per bead. The classifier belongs on a review or
dedicated pool per the feeder's own trade-off; proactive is the destination of
one of its outcomes, not the actor that produces them.

**Retirement authority: the conversation disposition is the reversible one.**
The feeder lists retirement authority as its riskiest open question, because
closing another agent's filed bead is the decision most likely to be wrong. A
first reaction is the safe default for anything the classifier is unsure about.
It closes nothing, leaves the bead open and unassigned, and puts a framed
question in front of a human. Routing an uncertain retire to a first reaction
costs one small session and is fully reversible.

**Stamping a route to proactive works, but only by accident of the prompt.**
The feeder's rule is to stamp `gc.routed_to` rather than sling, and for the
proactive pool that currently lands correctly: a bare stamp pours no formula,
the proactive worker claims it, and `agents/proactive/prompt.template.md`
carries the first-reaction method inline. It is fragile in one specific way.
`tools/gc-proactive.sh sling` passes `--on mol-first-reaction` and warns that
the flag is load-bearing, because a sling without it inherits the city's
`default_sling_formula = "mol-polecat-work"` and pours the wrong formula. If
the proactive pool ever gains a `default_sling_formula`, or the prompt stops
carrying the method inline, a bare route stamp starts silently running
implementation on a bead meant for a conversation. A feeder that dispatches to
proactive should either sling with the explicit `--on` or pin this expectation
with a test.

## Live-state note, outside this bead

The city's `[[rigs.overrides]] agent = "proactive"` stanza still exports
`GC_PROACTIVE_ENABLED` and `GC_PROACTIVE_CITY_CAP`. Neither is read any more:
the enable gate and the city-wide shed clamp were removed at operator
direction during the rewrite review, and
`tools/proactive-first-reaction-fixture.sh` now asserts their absence from the
tool, the `work_query`, and the `scale_check`. The stanza is inert, and it
reads as an enablement gate to anyone auditing why proactive does or does not
fire. Filed as tk-m3oqyr; city.toml is not pack content and the fix is an
operator config edit.
