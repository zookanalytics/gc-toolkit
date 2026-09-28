---
name: Goal Primitive Spec
description: The measurable-goal contract, judge architecture, verdict taxonomy, loop mechanics, and telemetry for goal-centric work that iterates until reality measures the goal met. Design input for goal-keeper v1 (tk-tutb46).
---

# Goal Primitive

A goal is a measurable condition about the world, carried by a bead, that
generates work until the condition is measured met by something other than the
worker that did the work.

Today the city converges on artifact approval: review loops iterate a diff
until reviewers approve it. The goal primitive moves the convergence target
from the delta to the value. The judge asks whether reality now meets a stated
condition, not whether a reviewer likes a change. Almost everything the city
does is already a form of convergence; this primitive names the target as a
world condition and keeps generating work until that condition holds.

Three properties separate a goal from every construct surveyed for this design
(the surveys are recorded in tk-nt5uda's notes):

- **Durable.** The goal outlives any session or molecule. Claude Code's
  `/goal` is session-scoped and dies with the session; a goal here is standing
  state.
- **World-measured.** The oracle reads reality: a metric, a benchmark, a test
  exit code. Per-molecule check loops and Kiro's per-task criteria converge on
  an approved artifact; a goal converges on a measured condition.
- **Work-generating.** The goal spawns work one bounded iteration at a time
  until the oracle measures met, then presents the converged result rather
  than the first plausible attempt.

## Scope

**Mandate.** The goal primitive's contract, judge architecture, verdict
taxonomy, loop mechanics, and telemetry: what a goal is, how it is judged, how
it terminates, and what it records.

**Boundaries.** This is the design record for tk-yaor8a. It fixes the contract
and the architecture; it does not implement them. The implementation is
goal-keeper v1 (tk-tutb46), pack-level formulas and scripts, which reads this
spec as landed. The engine telemetry request is gc-vz6v0 in the gascity store.
Vendoring the unimported review-loop packs is a separate action item, out of
scope here.

## 1. The primitive

A goal is a contract plus a loop, carried by a bead. The carrier may be an
epic bead or a dedicated goal bead; the primitive is the contract and the loop,
not a new bead type. Whether goals enrich the existing epic type or get their
own type is an implementation choice and does not change this design.

A goal typically spans multiple units of work and is sized by the condition it
states; the carrier may be any bead. An epic may carry or distill goals; a
goal need not belong to an epic. One goal, cutting p99 latency below a
threshold, can spawn an implementation molecule, then a profiling molecule,
then a tuning molecule across days, each iteration a fresh unit of work, all
judged against the same oracle.

This spec is the middle layer. Above it, a vision layer: epics carry visions,
and a PM-shaped refinement loop distills measurable goal contracts from them
(separate design, tk-h2s7hj.1). Below it, goal-keeper v1 (tk-tutb46) executes
and judges. v1 judges deterministic oracles only. A goal stated only in prose,
because no measurable contract has been written for it yet, lives in the vision
layer until the refinement loop distills it to a measurable contract; not-yet
crisp is a legal state, not an exclusion. Rubric-lane judging, which is how
document-shaped goals such as a PRD meeting a graded checklist are measured,
belongs to that refinement design (tk-h2s7hj.1).

How it differs from what exists:

| Construct | What it is | What a goal adds |
|---|---|---|
| `epic` type (today) | an organizing container, excluded from the routed pool query | a threshold and a loop: an epic that measures and drives |
| per-molecule check loop | converges one molecule on artifact approval, inside one workflow | convergence across molecules on a world condition |
| session-scoped `/goal` | judges a transcript until the session ends | durable state independent of any session |

## 2. The goal contract

A minimal contract is three things: a measurable end state, a check, and a
budget.

| Field | Meaning |
|---|---|
| `statement` | the measurable end state in plain language; the agreement between operator and city |
| `oracle` | the machine-checkable definition of done: a command or a metric-and-threshold, judged by an exit code or a comparison |
| `budget.max_iterations` | cap on attempts |
| `budget.token_budget` | cumulative token cap across iterations |
| `budget.wall_clock` | a deadline, relative or absolute |

Optional, defaulted by the keeper where a goal does not state them:

| Field | Meaning |
|---|---|
| `invariants` | conditions that must hold on every iteration (the suite stays green, no public API breaks); a violated invariant fails the iteration even when the oracle passes |
| `bound_clause` | override for what happens when a bound trips; the keeper default is a routed handoff to the escalation target carrying the reason and the closest-approach evidence, never a silent stop |
| `escalation_target` | override for who receives impossible, stalled, and exhausted handoffs; the keeper default is a human |
| `owner` / `provenance` | who set the goal and why |

The budget is three-way on purpose. Iterations bound count, tokens bound cost,
and wall-clock bounds latency; a goal that would converge in twenty iterations
but blow the token budget at eight should stop at eight, and the operator sees
which bound tripped.

**Where the contract lives.** The contract lives on the goal bead. When the
keeper arms the goal it records a snapshot of the contract — the oracle, the
budget, and any invariants — and before each verdict the judge re-reads the
contract and compares it to that snapshot. A match means the goal is unchanged
and the verdict stands. A mismatch means the contract moved after arming, so the
keeper re-arms against the current contract with a fresh snapshot rather than
judging against goalposts that have moved, and records the change in the verdict
trail.

The threat model is a cooperative-but-fallible worker, so integrity is
tamper-evident, not tamper-proof. A contract change is made visible in the trail
and re-arms the goal; it is not prevented. This is the failing-test-first
discipline as prior art runs it: the definition of done is recorded so a change
to it shows, not walled off behind a reference the worker cannot reach.

**A live goal changes by editing the bead.** Changing the oracle, budget, or
invariants is an edit to the goal bead; the next verdict finds the snapshot
mismatch, re-arms against the new contract, and records the change with its
provenance. An operator who finds a goal incorrectly stated edits it the same
way. Editing the bead is the whole of it: the edit is the change and the trail
is its record.

The operational state — current iteration, verdict trail, budget consumed, the
last not-yet reason — lives on the goal bead and a repo trail file alongside the
contract. It is durable, so any iteration can crash and the next resumes from
it.

**Example.** Goal: p99 read-path latency under 200ms. `oracle` is a benchmark
command whose measured p99 is compared to 200ms, exit 0 only when under.
`budget`: 8 iterations, a token cap, 72 hours. An optional `invariant` keeps the
full suite green. On each iteration close the keeper runs the benchmark itself
and compares.

## 3. Judge architecture

The governing rule: a model cannot judge its own homework. The worker is never
the judge.

- **Separation is structural.** The worker of an iteration never renders that
  iteration's verdict. The keeper runs the oracle and gathers its own evidence,
  in a session separate from the worker's. Iterations are pool-routed so each
  runs in a fresh session with no carried context (docs/gascity-packs.md); a
  named-agent loop keeps one assignee and collapses worker and judge into a
  single conversation.
- **The oracle is deterministic.** v1 judges by a command or a metric
  threshold: binary pass/fail from an exit code or a comparison. No model
  judgment is introduced where a number decides, and a deterministic oracle
  cannot be talked out of its verdict. A goal whose end state has no
  deterministic measure is judged by rubric lanes, a separate design
  (tk-h2s7hj.1), and enters v1 once distilled to a deterministic contract.
- **The judge gathers its own evidence.** It re-runs the oracle and reads the
  branch, artifacts, and metrics directly. It never reads the worker's summary
  of its own success as evidence. Agents plant self-assessments and edit tests
  to pass; evidence the judge did not gather itself is not evidence.
- **The contract is tamper-evident.** Before each verdict the keeper compares
  the goal's current contract to the snapshot it recorded at arming (Section 2).
  A mismatch means the contract changed after arming: the keeper re-arms against
  the current contract and records the change, rather than judging against moved
  goalposts. The change is made visible, not prevented.

## 4. Verdict taxonomy

The judge renders one verdict on each iteration's close.

| Verdict | Trigger | Action |
|---|---|---|
| `met` | oracle passes and invariants hold | terminal: close the goal, present the converged result |
| `not-yet` | oracle fails and another iteration can help | non-terminal: append the reason to the verdict trail, decrement budget, spawn the next iteration with the reason fed forward |
| `impossible` | the goal cannot be met as stated (contradiction, unsatisfiable oracle, hard external blocker) | terminal: routed handoff to `escalation_target` with the reason |
| `stalled` | no progress across iterations (a repeating failure signature), before any budget bound trips | terminal: routed handoff with the reason and the repeating signature |
| `exhausted` | a budget bound (iterations, tokens, or wall-clock) trips while still progressing | terminal: routed handoff with the bound that tripped and the closest-approach evidence |

`not-yet` is the only non-terminal verdict. Its reason is what the loop carries
forward: the judge states what is still wrong, and that statement is input to
the next iteration. A `not-yet` with no actionable reason is treated as
`stalled`.

Stalled and exhausted are distinct, and the distinction is what makes a bound
useful. Stalled means the loop is not moving (the same failure every attempt)
and should park early, before the rest of the budget burns. Exhausted means the
loop was moving but ran out of room. Both are routed handoffs carrying reasons;
neither is a silent stop. Detecting stalled early turns a cap from "burn to the
limit, then give up" into "park with a reason the moment it stops paying."

## 5. Loop mechanics

The binding constraint is no new standing watcher unless proven necessary and
cheap. The goal loop is event-driven.

- The goal spawns one iteration: a pool-routed molecule, its work derived from
  the current `not-yet` reason.
- A control bead, one per goal, blocks-depends on that iteration. When the
  iteration closes, the control bead re-arms and the judge runs. The trigger is
  the close event, not a clock. This is the mechanism the engine's check loops
  already use: the control bead is a `gc.kind=ralph` bead that re-arms when its
  blocking iteration closes, and its clone for a pool target is assigned to no
  one, so the next iteration is a fresh session (docs/gascity-packs.md). The
  in-city sweep concluded this substrate covers the goal loop with no engine
  change. The control bead is the keeper's, assigned to no iteration worker;
  arming the goal, before the first iteration is spawned, is when the keeper
  records the contract snapshot (Section 2).
- On re-arm, the judge fires: the keeper runs the oracle, gathers evidence, and
  renders a verdict.
- The verdict drives the next action: `met` closes the goal, `not-yet` spawns
  the next iteration, and `impossible`, `stalled`, or `exhausted` route to the
  escalation target.

No process polls the goal. The keeper is a reaction wired to close events,
realized as a control bead rather than a daemon, which is what keeps it cheap.

The loop is not a static cycle. A graph cycle is rejected, and a
`[steps.loop] until=` clause is inert and runs exactly one iteration
(docs/gascity-packs.md). Iteration comes from the control bead re-arming on
close and growing the graph at runtime, not from a loop written into the
formula graph.

**Fresh context, durable state.** Each iteration runs in a fresh pool session
and does one task against the current reason, then closes. All loop state (the
iteration count, the verdict trail, the budget consumed, the last reason) lives
on the goal bead and in the repo, and each iteration writes
its artifacts as it goes. Nothing the loop needs lives only in a session's
context, so any iteration can crash and the next resumes from durable state.

**The narrow cadence exception.** Some goals measure a world variable that
changes independent of our work, such as an external latency that can drift or
a dependency that can regress upstream. An event-driven judge that fires only
on our own work's close can miss such a regression. A goal of that shape may
carry a bounded re-check cadence. This is the "necessary and cheap" exception:
the default is event-driven, any cadence is justified per goal and is itself
bounded, and a goal whose oracle depends only on our own artifacts never needs
one.

## 6. Telemetry

A per-attempt record, append-only on the goal bead and a repo trail, carries
for each iteration: the index, the verdict, the reason, an evidence reference
(a commit, a branch, a measured value), wall-clock, tokens, and a digest of the
oracle output. This trail is where the `not-yet` reason is drawn from and where
the operator reads how a goal is converging.

The wedge signal compares consecutive failure signatures; a repeat is the
`stalled` trigger. Tracking closest-approach, whether the measured value is
moving toward the threshold, separates progressing-but-slow from stalled, and
detecting the wedge early is what lets `stalled` park before `exhausted`.

First-class convergence telemetry (per-iteration timings and progress, wedge
detection) is requested of the engine as gc-vz6v0. The keeper is designed
against that interface. Until it lands, the keeper hand-rolls the trail, writing
and reading its own per-iteration record. The one live hand-rolled exemplar
today is the `iteration_timings` block in the upstream-rebase formula, which
records per attempt when the attempt was minted, when a session started it, when
its work closed, when the check ran, and the verdict with its reason. The
hand-rolled trail carries the same fields as the requested interface, so the
fallback is forward-compatible.

## 7. What this learns from existing constructs

Greenfield-first means these are studied to learn from, not to bound the
design. The full surveys are in tk-nt5uda's notes.

- **Check loops / ralph (engine primitive).** In-repo, the one authored
  adoption is the upstream-rebase formula in the gascity-keeper pack. Its
  control bead re-arms on iteration close, its clone for a pool target is
  unassigned so each attempt is a fresh session, and it caps churn at a
  max-attempts budget read off the control bead. Because nothing runs after that
  budget is exhausted, its check script performs the handback itself on the last
  failing attempt rather than relying on a step that never runs. A deterministic
  gate reads durable state and fail-closes when it cannot: the rebase check
  reads the control bead, while lane-state.sh derives a lane's green from the
  review-bead graph and treats an unreadable store as not green. Diverges: a
  check loop converges one molecule on artifact approval; a goal converges the
  world across molecules.
- **mol-review-quorum (engine-core, available by reference).** Teaches the
  two-lane shape with a per-lane provider and model and a synthesizer that makes
  the single call and treats an unknown lane verdict as a hard contract failure.
  The rubric oracle, deferred to tk-h2s7hj.1, reuses this shape.
- **Claude Code `/goal`.** Teaches the verdict taxonomy (met, not-yet with a
  reason, impossible) and the separate small judge model. Diverges: `/goal` is
  session-scoped and its judge runs no tools, judging only surfaced evidence,
  while this judge is durable and gathers its own evidence.
- **Kiro, Spec Kit, Factory.** Teaches spec-as-contract and failing-test-first.
  Factory commits the failing tests, so tampering shows in the diff: the
  discipline is visibility, not prevention. The tamper-evident contract is that
  discipline — the keeper snapshots the contract at arming and every verdict
  compares against it, so a change to the definition of done is visible in the
  trail and re-arms the goal.

No surveyed construct is a standing goal, stated as a measurable condition
about the world, that generates work until reality measures it met. That is
what this primitive is.

## 8. Handed to implementation and to the engine

To goal-keeper v1 (tk-tutb46), pack-level formulas and scripts, no engine
change:

- The contract on the goal bead, and the snapshot the keeper records at arming.
  The keeper snapshots the contract when it arms the goal and compares the
  current contract to that snapshot before each verdict; a mismatch re-arms the
  goal against the current contract and records the change in the trail. This
  spec fixes the required fields — a measurable end state, a deterministic
  oracle, a three-way budget — the optional fields, and that integrity is
  tamper-evident; it leaves the snapshot's storage and the trail format to the
  implementation.
- The spawn-on-not-yet wiring: which formula pours the next iteration, and how
  the reason is threaded into the next work bead's dispatch note.
- Session policy: iterations are pool-routed for fresh context; the iteration
  molecules must not set session affinity to require.

To the engine (gc-vz6v0): first-class convergence telemetry. The keeper carries
a hand-rolled trail until it lands.

## Provenance

Operator-approved slate item 5, sitting tk-nt5uda (visit tk-rfxy3e),
2026-09-20. The binding operator constraints and the three condensed surveys —
external landscape, in-city prior art, and the gc-toolkit convergence audit —
are recorded in tk-nt5uda's notes and are the input to this spec. Implementation
follow-up: tk-tutb46, which blocks on this bead. Engine telemetry request:
gc-vz6v0, gascity store.

The 2026-09-20 constraint that the oracle is locked before iterating was amended
by operator ruling 2026-09-28 (sitting tk-eywd7n): integrity is recorded and
tamper-evident, matching the Factory.ai prior art where committing the failing
tests makes tampering visible in the diff rather than preventing it. v1 scope is
deterministic oracles only; rubric-lane judging is deferred to tk-h2s7hj.1.
