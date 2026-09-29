---
name: Vision-to-Goal Distillation
description: How an epic's vision becomes crisp, epic-shaped goal contracts: the Senior-PM perspective, the document-goal rubric oracle, the refinement sitting, the sizing invariants, the change discipline, and the circulation contract between the vision and goal layers. The rubric-lane design the goal primitive spec defers here.
---

# Vision-to-Goal Distillation

A vision is a direction stated in prose. A goal is a measurable contract carried
by an epic, advanced until something other than the worker measures it met
(specs/tk-yaor8a/goal-primitive-spec.md). Distillation is the work between the
two: turning a vision into the crisp, epic-shaped goal contracts the goal layer
carries.

Distillation is itself a goal loop. Its end state is a crisp contract. Its
oracle grades a candidate contract for readiness rather than measuring the
world. Its human lane is a refinement sitting, and its budget is the operator's
attention, spent in cheap rounds. Epic decomposition and goal convergence are
the same loop at two oracle hardnesses: the vision layer runs the soft, rubric
end, the goal layer runs the hard, measured end, and a verdict trail
circulates between them. Naming that symmetry is the whole of this design: a PM
refining an epic is running a goal loop whose oracle is a graded reading of a
document, and everything below makes that loop concrete.

## Scope

**Mandate.** How a vision becomes epic-shaped goal contracts: the perspective that
judges a candidate, the rubric oracle that grades its readiness, the sitting
that refines it, the invariants that size the work it spawns, the discipline
that changes it, and the contract that circulates goals down and verdicts up.

**Boundaries.** The goal contract's shape, the independent judge, and the
verdict taxonomy belong to the goal primitive
(specs/tk-yaor8a/goal-primitive-spec.md); this design produces that contract
and consumes those verdicts, it does not redefine them. Carrying a goal in an
epic, advancing it in batches, and judging it at checkpoints belong there too.
Building the perspective skill, the oracle formula, and the sitting procedure is
follow-up named in Section 9, not done here.

## 1. Two oracles, two layers

A goal has two different questions asked of it, and each has its own oracle.

- The **execution oracle** asks whether the world now meets the goal. It is the
  goal primitive's checkpoint judgment: the measured criteria re-run against
  reality and the graded criteria read by a party other than the worker
  (goal-primitive-spec.md Section 3).
- The **readiness oracle** asks whether the contract is crisp enough to carry. It
  is a graded reading of the candidate contract: is the end state measurable, is
  the check judgeable by a non-worker, is the scope a slice. This is the rubric
  oracle the goal primitive spec defers here (goal-primitive-spec.md Section 1).

The two never merge. A goal whose measures are well-defined still passes
through the readiness oracle first, because "the metric is well-defined" and
"this is the right metric, bounded and traceable to the vision" are different
claims. The readiness oracle is soft by nature: whether a contract is crisp is a
judgment, not a measurement, so it carries a human lane and a slop detector. The
execution side is harder-edged: its measured criteria are numbers read from
reality, and its graded criteria are judged at a checkpoint by a party other
than the worker rather than argued out of a verdict.

Distillation is the readiness oracle's loop. Its output, a contract that grades
ready, is the execution oracle's input.

## 2. The Senior-PM perspective

The reader that grades a candidate goal is a perspective, not a role with
standing. It is realized as an agent-local skill a distillation agent composes:
a short identity and a set of operating principles that encode what a senior
product manager's judgment looks like to a model. The principles are stated as
rules the perspective applies, present tense.

- **Outcome over output.** A goal names a changed world condition, never a
  shipped artifact. "Cut the second-review rate" is a goal; "add a review lane"
  is a task that might serve one.
- **Ruthless MVP scope.** The smallest goal that moves the outcome. Anything
  that does not change the measured condition is cut, not deferred.
- **Root-cause the why.** A goal traces to the value the vision seeks. A goal
  that cannot name the vision outcome it serves is decoration and is not carried.
- **Champion the user.** The operator and the city are the users. A goal serves
  their leverage, not the worker's convenience.
- **Measurable, or say not-yet.** If the end state cannot be judged by something
  other than the worker, the contract is not crisp yet. The perspective says so
  plainly rather than dressing prose as a metric.
- **Kill criteria first.** Every candidate states what would make it impossible
  or not worth continuing before any batch runs, so a bound trips into a
  reason rather than a silent stop.
- **Spend attention in cheap rounds.** The operator's attention is the scarce
  resource. The perspective asks for it in numbered, terminating rounds, never
  in open-ended review.

The perspective is the template for the rubric oracle's lanes: each lane grades
a candidate as this reader would. It is deliberately short, because a persona
that a model must page through is a persona it will not apply.

## 3. The document-goal oracle

The readiness oracle is a graded checklist rendered by more than one reader, the
rubric-lane construct the goal primitive spec defers here. It reuses the
two-lane quorum shape already in the resolved formula set
(formulas/mol-review-quorum-signoff.toml): two reviewer lanes on different
providers grade independently, and a synthesis step makes the one verdict from
their structured outputs.

### The checklist

Each item is answered per candidate as PASS, PARTIAL, or FAIL. Two items are
blockers: a FAIL on either makes the candidate not-yet-ready no matter how the
rest score, so the reader checks them first.

| # | Item | Grade asks |
|---|---|---|
| B1 | Measurable end state (blocker) | Does the statement name a world condition with a baseline and a target, as numbers wherever reality has numbers? |
| B2 | Non-worker oracle (blocker) | Can a party other than the worker check the goal, by a re-runnable measure or a grading rubric a non-worker applies? |
| R1 | Bounded cadence | Does the contract state its cadence and met condition: batch size, checkpoints, and when the goal is done? |
| R2 | Kill criteria | Is what makes the goal impossible or stalled stated, so a bound trips into a reason? |
| R3 | Vision traceability | Does the goal name the vision outcome it serves? |
| R4 | Slice discipline | Is the goal a vertical slice with no forward dependency, so each unit of work moves the measured value? |
| R5 | MVP scope | Is this the smallest goal that moves the outcome, with nothing added that does not change the measured condition? |
| R6 | Invariants | Where a regression is possible, is what must hold throughout stated? |
| R7 | Provenance | Is who set the goal, and why, recorded? |

Binary-per-item grading beats a single score: it says which part is not ready,
and that is the reason the refinement round carries forward. The blockers-first
order is the goal primitive's minimal contract (a measurable end state and a
check a non-worker can run) restated as a gate: without B1 and B2 there is no
goal to carry, only a wish.

### Cross-model divergence as the slop detector

The two lanes run on different providers on purpose. Agreement on an item, both
PASS or both FAIL, is a confident reading. Divergence on an item, one lane PASS
and the other FAIL, is the slop signal: the candidate is ambiguous enough that
two competent readers disagree about whether it is crisp, which is itself a
readiness failure. Divergence does not average into a middling score; it routes
that item to the operator lane. A vague sentence cannot be written past two
models that disagree on whether it says anything.

### The readiness verdict

The synthesizer renders one verdict, the vision-layer analogue of the goal
primitive's taxonomy.

| Verdict | Trigger | Action |
|---|---|---|
| `ready` | both blockers PASS and no readiness item FAILs | the contract flows down to be carried as an epic contract |
| `not-yet` | a blocker FAILs, the lanes diverge, or a readiness item FAILs | the failing items are the refinement reason, fed into the next sitting round |
| `impossible` | the candidate is not a goal at all, or the vision states two mutually exclusive outcomes | routes to the operator; the vision reshapes |

`not-yet` is the loop's only non-terminal verdict, exactly as it is a layer
down. Its reason, the specific failing items, is what the next elicitation round
acts on.

### The operator lane and its weight

The operator is the third lane, the senior judge. Operator weight scales with
the oracle's softness and thins as the rubric lanes earn trust. Concretely, the
operator is consulted in two cases: always when the two rubric lanes diverge,
and on a sampled fraction of agreeing verdicts that shrinks as the rubric's
record of agreeing with the operator grows. Early, when the rubric is unproven,
that fraction is one and the operator reads every verdict. As the lanes
accumulate agreement, the fraction thins toward a floor, and the operator's
attention is withdrawn from the readings the oracle has proven it can make. Any
operator override resets the confidence and re-widens the sample. The thinning
is driven by measured agreement, so it is a calibration loop, not a fixed gate
that decays on a timer.

## 4. The refinement sitting

Refinement runs in a converse sitting, the existing human-in-the-loop primitive,
not in a new standing watcher.

**One-liner gate before expansion.** A vision's candidate goals are first listed
as one-line statements, the goal sentence alone. The operator approves, cuts, or
merges the one-liners before any is expanded. Expansion into a full contract
costs elicitation rounds and oracle grading, so it runs only on an approved
one-liner. This is where a vision carrying five vague directions becomes one or
two real goals, cheaply, before the expensive work.

**Numbered elicitation menu.** When the oracle grades a candidate `not-yet`, the
distiller presents a numbered menu of concrete next moves on the current draft.
Each option either transforms the draft and re-grades, or terminates the round.
A menu for a candidate missing its metric and its bound reads:

```
The candidate: "Reviews take too many rounds; cut the count."
Readiness: not-yet (B1 fail: no baseline or target; R1 fail: no cadence).

  1. Name the metric: second-review rate, measured from the bead store.
  2. Set a baseline and target: from 51% (audit) to a target you set now.
  3. Set the cadence: batch size, checkpoints, and the met condition.
  4. State kill criteria: what makes this impossible or not worth continuing.
  5. Split: separate "fewer rounds" from "no quality regression."
  0. Accept as crisp and carry.
  9. Park: this is a vision, not yet a goal.
```

The operator picks one number. The pick is the round's oracle: a transform
re-drafts and re-grades, a `0` accepts it, a `9` returns the candidate to the vision.
One pick per round keeps the human cost to a number, not a paragraph.

**Right-sizing past the process.** The menu fires only when the oracle signals
`not-yet` or the lanes diverge. A candidate that grades `ready` on the first
reading is carried with no elicitation at all. Small, already-crisp work skips the
ceremony. Gating on the oracle's signal rather than on a fixed per-item schedule
is what keeps the rounds cheap and is the deliberate departure from fixed human
gating (Section 8).

## 5. Decomposition sizing invariants

These size the work a goal spawns. A goal spans many units of work, advanced
in batches; each unit is one focused change, and these invariants are
binary-checkable against it (goal-primitive-spec.md Section 5).

| Invariant | Binary check |
|---|---|
| Vertical slice | Closing this unit changes a measured value, rather than adding a layer that pays off only later. |
| No forward dependency | No open `blocks` blocker on the unit's work bead cites unstated prerequisite work. |
| One focused change | The `not-yet` reason names one task, not a program, so the unit fits a fresh session's context. |
| Observable increment | The unit writes an evidence reference (a commit, a measured value) to the verdict trail. |

A candidate whose slice cannot satisfy these is a candidate whose R4 grades
FAIL: it is not yet a goal, it is a program that must be split first. The sizing
invariants are therefore both a decomposition rule at distillation and the concrete
content of the R4 checklist item.

## 6. Change discipline

A live goal or vision changes by an explicit before-and-after proposal the
operator approves, never by silent drift.

The proposal states the current contract and the proposed contract side by side,
with the reason for the change. The operator approves it. The change is then
made by editing the epic body. Because the contract lives in the epic, the edit
is visible in its history, and the next checkpoint judges against the current
contract (goal-primitive-spec.md Section 6). Integrity is tamper-evident, not
tamper-proof: a change is made visible, it is not walled off behind a reference
the worker cannot reach.

The two halves compose. The before-and-after proposal is the deliberate,
human-facing half, so the operator sees exactly what moved and why before
approving. The epic body is the backstop: a change that skips the proposal still
cannot be silent, because it is an edit in the epic's history, and the next
checkpoint reads the current contract rather than judging against moved
goalposts. This is the document-level counterpart of the goal primitive's
tamper-evident contract. The vision and its goals change by an approved,
recorded edit, and no immutable lock stands between a goal and its correction.

## 7. The circulation contract

The vision and goal layers are one loop, and the contract is what moves between
them.

**Down: crisp goal contracts.** The vision layer hands the goal layer contracts
that grade `ready` and passed the one-liner gate. Nothing softer flows down; a
candidate still in refinement stays in the vision layer. The epic carries what
it receives, as its embedded contract.

**Up: verdict trails.** The goal layer's verdict trail flows back, and two of
its verdicts are elicitation input, not only terminal handoffs to a human. An
`impossible` verdict means the vision named a goal reality cannot meet as
stated; its reason becomes a menu item in the next refinement round. A `stalled`
verdict means the approach wedged; the vision may re-slice the goal into a
different attempt. A goal that keeps returning `not-yet` across many checkpoints
is a signal it was mis-distilled, and it returns to refinement rather than
spending more batches quietly.

**The legal vision-layer verdict.** "No crisp goal yet, keep refining" is a
first-class verdict, not a failure. A vision that has produced no crisp goal is
in refinement. Goals are opt-in per vision, so a vision may carry none and still
be doing its job. This is the goal primitive's "not-yet crisp is a legal state,
not an exclusion" made into a verdict the distillation loop renders and records.

## 8. What runs when, and what this learns from BMAD

**No new standing watcher.** Nothing polls a vision. Refinement runs in a
sitting, on operator initiative or when a checkpoint flows an `impossible` or
`stalled` up from a goal this vision distilled. The oracle grades on demand,
when a candidate is drafted or edited. This honors the binding constraint that
the vision loop runs in sittings, with no standing watcher.

**BMAD is input, not boundary.** The senior-PM persona plus a graded checklist,
the numbered elicitation menu, the one-liner-list gate before expansion, the
sizing invariants, and the before-and-after change proposal are shapes learned
from BMAD's PM role and recast in Gas City primitives: a sitting, beads, the
quorum lane shape, and the goal contract. The one failure BMAD measured in
itself is fixed per-item human gating, which fatigues, and which its own later
version cut by right-sizing small work past the process. This design avoids that
failure by gating the human round on the oracle's signal rather than on a fixed
schedule: a crisp candidate is carried with no round at all, and the operator lane
thins as the rubric earns trust. The point of copying BMAD's shapes is to inherit
its evidence, including the evidence for what to leave out.

## 9. Handed to implementation

This design is a record; the build is follow-up bead tk-h2s7hj.3, filed from
this design and blocked on it. That bead owns three pieces:

- **The perspective skill.** An agent-local skill carrying the identity and
  principles of Section 2, composed by the distillation agent.
- **The document-goal oracle.** A formula reusing the two-lane quorum shape
  (formulas/mol-review-quorum-signoff.toml), with the Section 3 checklist as the
  lanes' rubric and a synthesizer that renders the readiness verdict, plus the
  operator lane and its weight-scaling calibration.
- **The refinement sitting and up-circulation.** The converse procedure of
  Section 4 (one-liner gate, numbered menu) and the up-circulation that re-opens
  refinement on an `impossible` or `stalled` verdict from a distilled goal.

**The cost of waiting.** Until this is built, the vision layer's refinement is
entirely manual, run by the operator in a sitting with no oracle assist and no
slop detection. A goal can still be distilled by hand and carried as an epic
contract, as goal-one is (tk-y0abyu), but its contract is graded by a person
rather than by two lanes that disagree. The cost is operator time per vision and
no automated catch on a vague hand-written contract.

## Provenance

Design bead tk-h2s7hj.1, child of the vision epic tk-h2s7hj, developed behind the
goal primitive spec (tk-yaor8a) and worked on operator ruling `go`, sitting
tk-eywd7n (subject tk-yaor8a), 2026-09-22. Primary inputs: the goal primitive
spec as landed (specs/tk-yaor8a/goal-primitive-spec.md), the BMAD PM-role
condensate and sitting record in tk-yaor8a's notes, and the three surveys
(external landscape, in-city prior art, gc-toolkit convergence audit) in
tk-nt5uda's notes. The binding operator constraints, greenfield-first and no new
standing watcher, are from the sittings of 2026-09-20 and 2026-09-22. The
rubric-lane deferral this design fills, and the tamper-evident amendment its
change discipline rests on, are the operator rulings of 2026-09-28 recorded in
tk-yaor8a's notes. Implementation follow-up: tk-h2s7hj.3. Acceptance exercise:
dogfood-exercise.md, against tk-h2s7hj.2.
