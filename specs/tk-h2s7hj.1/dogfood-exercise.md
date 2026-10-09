---
name: Dogfood Exercise — Distilling the Review-Round-Count Goal
description: A worked run of the vision-to-goal distillation process against the first dogfood goal (tk-h2s7hj.2), producing its candidate contract and grading it with the document-goal oracle. Acceptance evidence for the distillation design.
---

# Dogfood Exercise: Distilling the Review-Round-Count Goal

This runs the process in vision-to-goal-distillation.md once, against the first
dogfood goal (tk-h2s7hj.2), to show it produces a crisp contract and to grade
that contract with the document-goal oracle. The operator picks are played here
for the demonstration; the real picks happen in the arming sitting. This
exercise authors the candidate contract as a worked artifact and does not arm
it: tk-h2s7hj.2 is blocked on the keeper (tk-tutb46) and its contract locks at
arming, so nothing here writes to that bead or routes it.

The exercise also shows the two-oracle separation directly. The distilled goal's
execution oracle is deterministic, a query over the bead store, exactly as the
dogfood was chosen to be. The readiness oracle that grades the contract below is
the rubric one. A deterministic goal still passes through a rubric reading
before it arms.

## Input: the vision slice

From the vision epic (tk-h2s7hj): gc-toolkit should converge on measured value,
and the audited cost of convergence is review round count. The convergence audit
(tk-nt5uda notes, 2026-09-20) measured the baseline: 51% of anchors need two or
more reviews, 48% of branches take two or more rework rounds, 724 reviews were
poured in the month, and each round costs three fresh sessions, eighteen step
beads, and three or more cadence ticks. The two-lane review pilot (tk-ehhpkh)
landed default-off with a standing instruction to measure the second-review rate
against the 51% baseline and widen or revert on the data.

## Step 1: one-liner gate

The vision slice yields one candidate one-liner:

> Cut the second-review rate in gc-toolkit, measured from the bead store,
> without pushing defects downstream.

The operator approves it as the one candidate worth expanding. A tempting second
one-liner, "make reviews faster," is cut: latency per review is not the audited
cost and would compete for the budget without moving the measured condition.

## Step 2: first reading, and a divergence

The distiller drafts a first contract from the one-liner alone, before
elicitation, and the two rubric lanes grade it.

Draft statement: "Reviews take too many rounds; cut the count."

| # | Item | Lane A | Lane B |
|---|---|---|---|
| B1 | Measurable end state | PARTIAL | FAIL |
| B2 | Non-worker oracle | PASS | PASS |
| R1 | Three-way budget | FAIL | FAIL |
| R2 | Kill criteria | FAIL | FAIL |
| R3 | Vision traceability | PASS | PASS |
| R4 | Slice discipline | PARTIAL | PARTIAL |
| R5 | MVP scope | PASS | PARTIAL |

The lanes diverge on B1: Lane A reads "cut the count" as an implied metric worth
a PARTIAL, Lane B fails it for naming no baseline and no target. That divergence
is the slop signal, and B1 is a blocker, so it routes to the operator lane. The
synthesizer's verdict is `not-yet`, with the reason drawn from the failing
items: no baseline or target (B1), no budget (R1), no kill criteria (R2).

## Step 3: one elicitation round

The distiller presents the menu for the failing items:

```
The candidate: "Reviews take too many rounds; cut the count."
Readiness: not-yet (B1 divergence + fail: no baseline or target;
                    R1 fail: no budget; R2 fail: no kill criteria).

  1. Name the metric: second-review rate, measured from the bead store.
  2. Set a baseline and target: from 51% (audit) to a target you set now.
  3. Add the three-way budget: iterations, tokens, wall-clock.
  4. State kill criteria: what makes this impossible or not worth continuing.
  5. Split: separate "fewer rounds" from "no quality regression."
  0. Accept as crisp and arm.
  9. Park: this is a vision, not yet a goal.
```

The operator picks 5. Splitting is the load-bearing move: it makes the
quality guard an invariant rather than an afterthought, so "cut rounds" cannot
be met by lowering the bar. The distiller applies the transform, folds in the
metric (1), the target (2, worked value 35% as the operator's stand-in), the
budget (3), and the kill criteria (4) the split implies, and re-drafts. One
round settles the candidate because the split reorganizes the rest.

## Step 4: the distilled contract

```
statement:  The second-review rate for gc-toolkit anchors is at or below 35%,
            measured over a trailing 30-day window from the bead store, with no
            rise in the post-merge fix rate over the same window.
oracle:     A store query the keeper runs: second-review rate = anchors closed
            in the window with two or more review beads, over anchors closed in
            the window. Exit 0 only when the rate is at or below the target AND
            the post-merge fix rate (fix beads referencing a merged anchor,
            over merged anchors) is at or below its window baseline.
budget:
  max_iterations: 8
  token_budget:   <keeper default cap>
  wall_clock:     30 days (a full measurement window for the metric to move)
invariants:
  - the full test suite stays green each iteration
  - the post-merge fix rate does not rise above its window baseline
kill_criteria:
  - stalled: the second-review rate does not move across three iterations
  - impossible: the rate falls only when the post-merge fix rate rises, so the
    goal and its quality invariant cannot both hold
bound_clause:       keeper default (routed handoff with the tripped bound and
                    the closest-approach rate)
escalation_target:  keeper default (the coordination sitting, tk-eywd7n)
provenance:         operator ruling, sitting tk-eywd7n, 2026-09-22; first armed
                    goal for keeper v1, dogfood 1
```

The target value 35% stands in for the operator's pick at lock. The exercise
carries a worked number so the contract is complete; the arming sitting confirms
or replaces it.

## Step 5: readiness grading of the distilled contract

The two lanes re-grade, and now agree.

| # | Item | Grade | Note |
|---|---|---|---|
| B1 | Measurable end state | PASS | rate, baseline 51%, target 35%, 30-day window |
| B2 | Non-worker oracle | PASS | a store query the keeper runs, not the worker |
| R1 | Three-way budget | PASS | 8 iterations, token cap, 30 days |
| R2 | Kill criteria | PASS | stalled and impossible both stated |
| R3 | Vision traceability | PASS | round count is the audited cost of convergence |
| R4 | Slice discipline | PASS | first iteration is a single vertical slice (below) |
| R5 | MVP scope | PASS | one metric, one lever; latency was cut at the gate |
| R6 | Invariants | PASS | suite green and the post-merge fix-rate guard |
| R7 | Provenance | PASS | operator ruling, dogfood 1 |

Verdict: `ready`. The contract flows down to the keeper to arm, once the keeper
exists.

## Step 6: sizing the first iteration

The armed goal spawns work one iteration at a time. The first iteration is
already known, because the pilot the audit named is the first lever:

> Turn the two-lane review pilot (tk-ehhpkh) on, and measure the second-review
> rate over the next window.

Against the sizing invariants:

| Invariant | Check on this iteration |
|---|---|
| Vertical slice | Flipping the pilot from default-off changes the measured second-review rate directly. |
| No forward dependency | The pilot landed already; nothing unstated blocks turning it on. |
| One focused session | The task is one configuration change plus the measurement note. |
| Observable increment | The next window's rate is the evidence written to the verdict trail. |

This is the fold-in the dogfood bead names: the pilot's on-or-off decision stops
being an orphan slate item and becomes a judged iteration of the goal. If the
first window's rate does not clear the target, the `not-yet` reason (which lanes,
which anchors still doubled) drives the second iteration, and so on until the
oracle measures the rate met or a bound trips.

## What the exercise establishes

The process turns a one-line vision into a contract the goal primitive can arm,
in one elicitation round, and the rubric oracle grades the result `ready`. The
divergence on the first reading (Step 2) is the slop detector doing its job: the
vague draft could not pass two lanes that disagreed about whether it named
anything. The contract's execution oracle is deterministic while its readiness
was graded by rubric, which is the two-oracle separation the design rests on.
