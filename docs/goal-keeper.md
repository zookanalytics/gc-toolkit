# Goal-keeper

A goal is a measurable condition about the world, carried by a bead, that
generates work until an oracle measures the condition met. The keeper converges
the goal one bounded iteration at a time; the worker that does an iteration never
judges it. Goal-keeper v1 judges deterministic oracles: a command's exit code, or
a metric compared to a threshold.

The design record is `specs/tk-yaor8a/goal-primitive-spec.md`. This document is
how the shipped machinery works.

## The pieces

| Piece | What it is |
|---|---|
| the goal bead | carries the contract and all loop state in `goal.*` metadata |
| `assets/scripts/goal-arm.sh` | records the contract snapshot and pours the loop |
| `formulas/mol-goal-keeper.toml` | the loop: a pool-routed check loop, one iteration per unit of work |
| `assets/scripts/goal-judge.sh` | the judge: runs the oracle, renders a verdict, drives the loop |
| `assets/scripts/goal-canonical.sh` | canonical contract serialization, shared by arm and judge |

No standing process polls a goal. The judge is a reaction wired to the close of
each iteration, realized as the check loop's control bead rather than a daemon.

## The contract

The contract lives on the goal bead as metadata. An operator sets it, and an
operator changes a live goal by editing these keys.

| Key | Meaning |
|---|---|
| `goal.statement` | the measurable end state, in plain language |
| `goal.oracle.kind` | `metric` or `command` |
| `goal.oracle.command` | the command the judge runs; may reference pack scripts via `$GOAL_SCRIPTS_DIR/<name>.sh` |
| `goal.oracle.compare` | `metric` only: `lt` `le` `gt` `ge`; met when `value <op> threshold` |
| `goal.oracle.threshold` | `metric` only: the number compared against |
| `goal.budget.max_iterations` | iteration cap (required) |
| `goal.budget.wall_clock` | a duration (`72h`, `30d`, `3600s`) or an absolute ISO deadline |
| `goal.budget.token_budget` | recorded; enforcement waits on engine convergence telemetry |
| `goal.invariants` | JSON array of commands that must each exit 0 every iteration |
| `goal.escalation_target` | who receives a park (default `human`) |
| `goal.owner`, `goal.provenance` | who set the goal and why |

The budget is three-way on purpose: iterations bound count, wall-clock bounds
latency, tokens bound cost. The judge reads every bound at each verdict and
parks the goal the moment one trips, naming which one.

## Arming

`goal-arm.sh <goal-bead> [contract flags]` writes any contract fields passed as
flags, validates that the contract is complete, records the tamper-evident
snapshot, and pours the loop at a pool:

```bash
goal-arm.sh <goal-bead> \
  --statement "p99 read latency under 200ms" \
  --oracle-kind metric \
  --oracle-command '"$GOAL_SCRIPTS_DIR/oracle-latency.sh" --p99' \
  --compare lt --threshold 200 \
  --max-iterations 8 --wall-clock 72h \
  --invariant 'make test' \
  --iteration-target gc-toolkit/gc-toolkit.polecat
```

`--dry-run` validates and prints the snapshot and the sling command without
writing or pouring. Arming is idempotent in its effect on the contract, but it
re-stamps `goal.armed_at`; to re-pour a loop whose snapshot is already recorded,
run the printed `gc sling` line directly.

## The loop

`mol-goal-keeper` is a check loop (`[steps.check]`, formulas v2). Its one step,
`iterate`, runs once per attempt in a fresh pool session:

1. The iteration reads `goal.statement` and `goal.not_yet_reason` — the judge's
   last word on what is still wrong — and does one bounded unit of work toward
   the statement, against that reason.
2. It records its evidence (a commit, a bead id, a measured value) on the goal
   bead and closes its own iteration bead.
3. Closing runs the judge.

Iterations are pool-routed so each starts in a fresh context; a named-agent
target would carry the previous iteration's context forward and defeat the point
(docs/gascity-packs.md §6). The loop's `max_attempts` is a hard ceiling, not the
budget — the goal's own `goal.budget.*` is the budget, and the judge enforces it.

## The judge and the verdict

`goal-judge.sh` runs when an iteration closes. It re-reads the contract, compares
it to the arming snapshot, runs the oracle against reality, checks the
invariants, reads the budget, and renders one verdict:

| Verdict | Trigger | Action |
|---|---|---|
| `met` | oracle passes and invariants hold | close the goal, record the converged result |
| `not-yet` | oracle fails, the reason is actionable, a bound remains | thread the reason forward, append the next iteration |
| `impossible` | the oracle reports the goal unsatisfiable as stated (a `command` oracle exits 3) | park to the escalation target |
| `stalled` | the same failure signature as the previous attempt with no closest-approach improvement, or a not-yet with no actionable reason | park to the escalation target |
| `exhausted` | an iteration or wall-clock bound trips | park with the bound named and the closest approach |

`not-yet` is the only non-terminal verdict; every other verdict stops the loop.
A park reassigns the goal to its escalation target with the reason in the notes
and leaves it open for a human to dispose. A goal never stops silently: if the
oracle itself breaks, the judge treats the iteration as not-yet (never met) and
the loop parks the goal on `exhausted` once a bound trips, with the error in the
trail.

Separation is structural: the session that does an iteration's work never
renders that iteration's verdict, and the judge runs the oracle itself rather
than reading the worker's account of its own success.

## Tamper-evidence

At arming the keeper snapshots the contract — statement, oracle, budget,
invariants — into `goal.snapshot`. Before each verdict the judge recomputes the
canonical contract and compares it. A mismatch means the contract changed after
arming: the judge re-arms against the current contract and records the change in
the trail, rather than judging against goalposts that moved. The change is made
visible, not prevented — the threat model is a cooperative-but-fallible worker.

## The trail

`goal.trail` is an append-only JSON array on the goal bead, one entry per
attempt: the attempt index, the verdict, the reason, the measured value, a
timestamp, and the iteration bead. It is where the `not-yet` reason is drawn from
and where a goal's convergence is read. First-class convergence telemetry is a
request of the engine; until it lands the keeper hand-rolls this trail.

## Writing an oracle

An oracle is a fast, deterministic measurement. The judge runs it inline in the
control dispatcher on a sandboxed PATH (`bd`, `gc`, `jq`), bounded by the step's
`check.timeout`, so the oracle must be a bead-store query or a quick metric —
never a long build or benchmark. A `metric` oracle prints its measured value as
its last line and the judge compares it to the threshold. A `command` oracle
signals met with exit 0, unsatisfiable with exit 3, and not-met with any other
code. Oracles that read the bead store use raw `bd` (not `gc bd`), whose config
load can be cold in that environment.

## Limits

- v1 judges deterministic oracles only. A goal with no deterministic measure
  stays in the vision layer until it is distilled to one.
- `goal.budget.token_budget` is recorded but not enforced: the condition
  environment carries no per-iteration token count. Iterations and wall-clock
  are enforced.
- The wall-clock bound is enforced at each iteration's close. A per-iteration
  hard deadline that terminates a wedged, never-closing iteration needs engine
  support; the session lease is the current backstop for that case.
