---
name: Product goals — what the city is for, and how the operator judges it
description: The problems gc-toolkit solves for the operator, and how the operator judges a change is the right one — the product-level reading of docs/foundation.md. The reference the PM review check reads before it judges; the PM check stewards this file.
---

# Product goals

`docs/foundation.md` states what gc-toolkit believes: the operator's attention is
the budget, agents earn every interaction, and agents make their edges visible.
This file reads those beliefs out as product goals — what the city is for from the
operator's side — so the PM review check has a concrete reference to judge a change
against. The foundation also names the goals this serves: fewer, higher-value
escalations (G1), equipping the human to make the best decision (G2), and decisions
that hold across handoffs (G3).

gc-toolkit is the pack that runs a Gas City: a crew of autonomous agents that turn
work into reviewed, mergeable changes. The **operator** is the human who runs that
city, and here also the person it serves: gc-toolkit's product is the city's
trustworthy output, and its user is the operator. Where another rig's product
serves users the operator never meets, in gc-toolkit the two are one person — which
is why this file reads the product's value as value to the operator. Where the
generic PM review method asks who the product serves, in this rig the answer is the
operator.

## The operator's problem

The operator wants trustworthy work out of the city without having to babysit it.
They want to:

- **get the right thing, not just a built thing** — a change that moves the
  problem it was dispatched to solve, the real outcome, not a proxy that was
  easier to ship;
- **spend attention only where a human is required** — a decision the machinery
  cannot make, an approval only they can give — not on work that has a proven
  remedy, and not on relaying queues the city already tracks;
- **act on what the city surfaces without looking anything up** — a decision
  stated with its options, a PR whose summary says what the whole change does, an
  escalation that names what would release it;
- **trust that a green change is a right change** — reviewed for whether it is
  correct, and for whether it solved the problem it was dispatched to solve rather
  than a proxy of it;
- **see the surfaces they watch reflect reality** — the board, the PRs, and the
  demos show what happened, not what was intended.

A change that adds toil, that makes the operator reconstruct a decision, or that
moves a proxy instead of the problem works against these goals even when its code
is correct.

## Is it the right thing

The weight of the PM check. A change is the right thing when it moves the
operator's actual problem: the problem its bead stated is the right problem to
solve, and the change delivers the outcome the operator wanted rather than an
output that stands in for one. Where the anchor took a rough brief at its word,
the right thing is what the operator needed, not only the words they used.

## What the operator watches

The surfaces a change presents itself through, where the operator judges it:

- **The helm board** — the live state of work, PRs, and review lanes. The operator
  reads it to know what needs them and what is moving on its own.
- **PRs surfaced for a merge decision** — the `## Summary` is the merge-decision
  surface. It is where the operator decides yes or no, so it must account for the
  whole change and let them weigh it.
- **Visits and escalations** — the filed, routed record raised when an agent needs
  a human. The operator claims these; each names what it needs and what closes it.
- **Demos** — a narrated recording of an operator-watched surface doing the thing.
  One strong way a change shows its value when the operator would want to see it
  run, not the only way.

## Can the operator decide

A change presents itself meaningfully when the operator can accept or reject it
from what the city put in front of them, without reconstructing the case:

- the PR summary states what the whole diff does, in the operator's terms, not a
  restatement of the dispatch;
- the evidence discriminates — it tells the change working apart from the change
  merely running;
- the value is shown in the mode that fits the change — a worked example, a
  before-and-after narrative, a discriminating number, or a demo to watch.

## Stewardship

The PM review check stewards this file. When the city changes what it is for or
what it promises the operator, this file moves with it; when a change under review
reveals that this file has drifted from reality, the PM files that as maintenance.
It stays a short statement of goals and surfaces, not a catalog of features.
