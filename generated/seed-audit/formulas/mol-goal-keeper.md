Formula: mol-goal-keeper
Description: Drive a measurable goal to met, one bounded iteration at a time, judged by an
oracle the worker never runs. The goal is a contract carried by a bead
(docs/goal-keeper.md): a measurable statement, a deterministic oracle, and a
three-way budget of iterations, tokens, and wall-clock. This formula is the
loop that converges the goal; `assets/scripts/goal-arm.sh` records the contract
snapshot and pours it, and `assets/scripts/goal-judge.sh` is the judge.

The loop is a check loop (`[steps.check]`, formulas v2). Each iteration is one
pool-routed session that reads the goal's current `not_yet` reason and does one
bounded unit of work toward the statement, then closes its own bead. Closing
runs the judge: it re-reads the contract, re-runs the oracle against reality,
and renders one verdict — met, not-yet, impossible, stalled, or exhausted. A
not-yet fails the exit condition and the loop appends the next iteration with
the reason threaded forward; every other verdict is terminal and stops the loop.

The judge is separate from the worker on purpose: a model cannot judge its own
homework. The iteration session that does the work never renders the verdict,
the judge runs the oracle itself and reads reality rather than the worker's
summary, and each iteration runs in a fresh pool session with none of the
previous one's context.

**Iterations must be pool-routed.** Sling this formula at a pool, never a named
agent — a check loop only recycles the worker session and clears context when
the attempt target is a pool (docs/gascity-packs.md §6). The step declares no
assignee, which `[steps.check]` forbids anyway.

**Budget lives on the goal, not here.** `max_attempts` below is a hard ceiling
that bounds pathological churn. The real budget is `goal.budget.*` on the goal
bead, which an operator edits, and the judge enforces all three bounds at every
verdict: it renders `exhausted` and parks the goal the moment the iteration
count, the wall-clock deadline, or (once engine token telemetry lands) the token
budget trips. On the ceiling's last attempt the judge parks the goal itself,
because the orchestrator closes the control bead and nothing runs after it — the
same exhaustion handback the other check loops in this repo carry.

Never close the goal bead from an iteration: the judge closes it on `met` and
reassigns it to the escalation target on a park. An iteration closes only its
own iteration bead.


Steps (4):
  ├── mol-goal-keeper.iterate.spec: Step spec for One bounded iteration toward the goal, then let the judge measure (spec)
  ├── mol-goal-keeper.iterate.iteration.1: One bounded iteration toward the goal, then let the judge measure
  ├── mol-goal-keeper.iterate: One bounded iteration toward the goal, then let the judge measure [needs: mol-goal-keeper.iterate.iteration.1]
  └── mol-goal-keeper.workflow-finalize: Finalize workflow [needs: mol-goal-keeper.iterate]
