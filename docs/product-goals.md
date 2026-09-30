---
name: Product goals — what the operator watches
description: The user problems gc-toolkit exists to solve, who the operator is, the surfaces they watch, and what a change presented so the operator can judge it looks like. The reference the PM review check reads before it judges; the PM check stewards this file.
---

# Product goals

gc-toolkit is the pack that runs a Gas City: a crew of autonomous agents that
turn work into reviewed, mergeable changes. The **operator** is the human who
runs that city. This states what the city is for from the operator's side, and
what they watch to know it is working.

## The operator's problem

The operator wants trustworthy work out of the city without having to babysit it.
They want to:

- **spend attention only where a human is required** — a decision the machinery
  cannot make, an approval only they can give — not on work that has a proven
  remedy, and not on relaying queues the city already tracks;
- **act on what the city surfaces without looking anything up** — a decision
  stated with its options, a PR whose summary says what the whole change does, an
  escalation that names what would release it;
- **trust that a green change is a right change** — reviewed for whether it is
  correct, and for whether it solved the problem it was dispatched to solve
  rather than a proxy of it;
- **see the surfaces they watch reflect reality** — the board, the PRs, and the
  demos show what happened, not what was intended.

A change that adds toil, that makes the operator reconstruct a decision, or that
moves a proxy instead of the problem works against these goals even when its code
is correct.

## What the operator watches

- **The helm board** — the live state of work, PRs, and review lanes. The
  operator reads it to know what needs them and what is moving on its own.
- **PRs surfaced for a merge decision** — the `## Summary` is the merge-decision
  surface. It is where the operator decides yes or no, so it must account for the
  whole change and let them weigh it.
- **Visits and escalations** — the filed, routed record raised when an agent
  needs a human. The operator claims these; each names what it needs and what
  closes it.
- **Demos** — a narrated recording of an operator-watched surface doing the
  thing. When a change is one the operator would want to see run, the demo is how
  they see it without running it themselves.

## Meaningful presentation

A change is presented meaningfully when the operator can accept or reject it from
what the city put in front of them:

- the problem it solves is the one its bead stated, and the change moves that
  problem, not a substitute for it;
- the PR summary states what the whole diff does, in the operator's terms, not a
  restatement of the dispatch;
- the evidence discriminates — it tells the change working apart from the change
  merely running;
- a demo is present when the change is one the operator would want to watch, and
  absent without apology when it is not.

## Stewardship

The PM review check stewards this file. When the city changes what the operator
watches or what it promises them, this file moves with it; when a change under
review reveals that this file has drifted from reality, the PM files that as
maintenance. It stays a short statement of goals and surfaces, not a catalog of
features.
