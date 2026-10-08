---
name: Goal Primitive Spec
description: Retired as a separate primitive — the epic is the goal's home (docs/epics.md, "Direction: Features and Epic Checkpoints"). The goal contract carried at epic altitude: measured baselines and operator-graded qualities embedded in the epic body, advanced in batches and judged by an independent reader at evaluation checkpoints. Covers the verdict taxonomy, judge independence, and the tamper-evident contract. Read the retirement banner before citing any part of it.
---

# Goal Primitive

> **Retired as a separate primitive — read this before citing anything below.**
>
> A goal is not its own primitive. This spec already carried a goal at epic
> altitude, with no goal bead and no `goal.*` metadata, so the epic model is its
> home ([docs/epics.md](../../docs/epics.md), "Direction: Features and Epic
> Checkpoints"). The operator sitting tk-089mt7x (2026-10-07) folded four of its
> ideas into the epic contract: the checkpoint shape (Section 5), judge
> independence (Section 3), the measured and graded criteria (Section 2), and
> the backstop invariant (Sections 2 and 6). It unified the verdicts with the
> epic ruling: `not-yet` is continue, and `met`, `impossible`, `stalled`, and
> `exhausted` are each close, with the verdict recorded as the close's outcome
> (Section 4). The follow-on epic tk-wmwcdlc builds the consolidation. The rest
> of this document is a point-in-time record and is not rewritten.

A goal is a measurable condition about the world, carried at epic altitude as a
contract embedded in the epic's body. It generates work until the condition is
measured met by a reader other than the worker that did the work.

The city already converges on artifact approval: review loops iterate a diff
until reviewers approve it. A goal moves the convergence target from the delta
to the value. The judge asks whether reality now meets a stated condition, not
whether a reviewer likes a change.

Three properties separate a goal from an ordinary epic:

- **Durable.** The goal is standing state in the epic body, outliving any
  session or molecule.
- **World-measured.** The measures read reality: a count, a benchmark, or a
  doctor result, never the worker's account of its own work.
- **Convergent.** The goal drives batches of work until the measures read met,
  and presents the converged result rather than the first plausible attempt.

## Scope

**Mandate.** What a goal is, how its contract is stated, how it is judged, how
it terminates, and what it records, for goals carried at epic altitude.

**Boundaries.** This is the design record for tk-yaor8a. It fixes the shape of
the contract and how a goal is judged; it does not build tooling. The running
instance is goal-one (tk-y0abyu), under the goals experiment (tk-h2s7hj.4).
Distilling a vision into an epic-shaped contract is a separate design
(tk-h2s7hj.1). Automation is out of scope until the experiment harvests what is
mechanical (Section 7).

## 1. Carriage

The carrier is an epic. The contract is embedded in the epic's body: the
statement, the measured criteria, the graded criteria, the cadence, the met
condition, the oracle, and the backstop invariant. There is no dedicated goal
bead and no `goal.*` metadata; the epic text is the whole of the contract.

A goal spans many units of work and is sized by the condition it states. One
goal, shrinking an operating surface below a set of targets, drives a batch of
PRs, then a checkpoint, then the next batch, all read against the same measures.
goal-one (tk-y0abyu) is the running example: an epic whose body states its own
measured and graded criteria and its checkpoint cadence.

## 2. The contract

The contract is multi-criteria: numbers where reality has numbers, grades where
it does not.

| Part | Meaning |
|---|---|
| Statement | the world condition to change, in plain language; the agreement between operator and city |
| Measured criteria | conditions with a numeric baseline and a direction or target, read from reality; targets may be provisional and re-aimed at a checkpoint |
| Graded criteria | qualities a reader judges rather than measures, graded at each checkpoint |
| Cadence | the batch size and checkpoint rhythm: work advances in batches of roughly a few PRs, each batch closing with a checkpoint |
| Met condition | the measured targets hold and the graded criteria pass across two consecutive checkpoints |
| Oracle | how the measures are re-run: a re-runnable script where one exists, otherwise the census method recorded with the goal |
| Invariant | a backstop that must hold throughout, so a measure cannot be moved by breaking something |

The measured and graded split is the point. A surface count or a benchmark is a
measure; "one obvious way to do a thing" or "breakage trending down" is a grade.
Both are in the contract, and both are read at every checkpoint.

The oracle is itself part of the surface a goal measures, since a census script
is one more script, so the accounting counts it. The invariant is what keeps the
measures honest: no capability is deleted to move a number.

The contract lives in the epic body. Changing it is an edit to that body
(Section 6).

## 3. Judging

The governing rule: a model cannot judge its own homework. The worker of a batch
never renders the checkpoint verdict on it.

- **The judge reads reality, not the worker's summary.** It re-runs the measures
  itself and reads the branch, the artifacts, and the counts directly. A
  worker's account of its own success is not evidence: agents plant
  self-assessments and edit checks to pass.
- **The judge sits at a checkpoint.** Evaluation runs in a sitting on the epic,
  where the operator re-measures and grades. Whether any grading is later
  delegated to a reader other than the operator is decided from the experiment,
  not assumed now.
- **Measured and graded criteria are judged together.** The measures decide the
  countable criteria; the operator grades the qualities. A measured target met
  while a graded quality regressed is not the goal met.

## 4. Verdict taxonomy

At a checkpoint the judge renders one verdict on the goal.

| Verdict | Trigger | Action |
|---|---|---|
| `met` | measures hold and graded criteria pass, across two consecutive checkpoints | terminal: close the goal, present the converged result |
| `not-yet` | the goal is progressing but the criteria do not yet hold | non-terminal: record what is still short, aim the next batch at it |
| `impossible` | the goal cannot be met as stated: a contradiction, an unsatisfiable target, a hard external blocker | terminal: return to the operator with the reason |
| `stalled` | the measures stop moving across checkpoints, a repeating failure signature | terminal: return to the operator with the reason and the signature |
| `exhausted` | the goal runs past the cost it was worth while still progressing | terminal: return to the operator with what ran out and the closest approach |

`not-yet` is the only non-terminal verdict, and its reason is what the next batch
carries forward. The judge states what is still wrong, and that statement aims
the next batch. A `not-yet` with no actionable reason is treated as `stalled`.

`impossible`, `stalled`, and `exhausted` all return the goal to the operator to
reshape or retire, never a silent stop. Stalled and exhausted are distinct, and
the distinction is what makes a checkpoint useful. Stalled means the goal is not
moving and should stop early, before more batches burn. Exhausted means it was
moving but is no longer worth the remaining cost.

## 5. Advancing in batches

Work advances in batches, not in a single pass and not in an automated
per-iteration loop. A batch is a small set of changes, roughly a few PRs, aimed
at the current `not-yet` reason. When the batch lands, a checkpoint sitting
re-runs the measures, grades the qualities, records what the batch moved on the
experiment record (tk-h2s7hj.4), and aims the next batch. The rhythm is batch,
checkpoint, batch, and the goal is met only when two consecutive checkpoints
pass.

The operator decides at each checkpoint whether to continue. There is no control
bead, no standing watcher, and no engine loop; the motion is manual by design
(Section 7).

## 6. Integrity

The threat model is a cooperative-but-fallible worker, so integrity is
tamper-evident, not tamper-proof.

The contract lives in the open, in the epic body, so a change to the goalposts
is a visible edit in the epic's history. It is made to show, not walled off
behind a reference the worker cannot reach. This is the failing-test-first
discipline as prior art runs it: the definition of done is recorded so a change
to it shows rather than being prevented.

The judge re-runs the measures itself (Section 3), so a worker cannot move a
criterion by reporting a number it did not earn. The backstop invariant holds
the line the measures cannot: no capability is deleted to move a measure.

A live goal changes by editing the epic body, through a before-and-after the
operator approves (the change discipline lives in the distillation design,
tk-h2s7hj.1). The edit is the change and the epic's history is its record.

## 7. What is deliberately absent

There is no keeper, no `goal.*` metadata, no per-iteration loop, and no standing
watcher. A goal is run by hand: batches of work, a checkpoint sitting to
re-measure and grade, and a manual record of what each batch moved.

This absence is a decision, not a gap. The goals experiment (tk-h2s7hj.4) runs
goal-one (tk-y0abyu) this way, and at each checkpoint it records what was
mechanical, what needed judgment, and what the contract text wanted but lacked.
The minimal automation worth building is designed from that record once a couple
of checkpoints have run, rather than ahead of the evidence. It is plausibly no
more than re-measuring at a batch's close and posting the delta.

## Provenance

Design record for tk-yaor8a. The model was ruled at the tk-tutb46 sitting (visit
tk-fw8w1w), 2026-09-29: a goal carried at epic altitude with an embedded
contract, judged by hand at checkpoints, with machinery deferred until manual
cycles show what is mechanical. The running instance is goal-one (tk-y0abyu)
under the goals experiment (tk-h2s7hj.4). Distilling a vision into an
epic-shaped contract is the separate design tk-h2s7hj.1.
