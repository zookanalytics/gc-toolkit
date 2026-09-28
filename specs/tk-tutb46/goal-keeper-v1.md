---
name: Goal-keeper v1 — implementation record
description: What tk-tutb46 built for the goal primitive, the design decisions behind it, the dogfood contract, and the deferred live arming.
---

# Goal-keeper v1 (tk-tutb46)

Implements the goal primitive from `specs/tk-yaor8a/goal-primitive-spec.md` (as
landed, including the detach rework tk-h1647p), pack-level, no engine change.
The authoritative how-it-works is `docs/goal-keeper.md`; this file records what
was built, why, and what is deferred.

## What shipped

| Artifact | Role |
|---|---|
| `formulas/mol-goal-keeper.toml` | the loop: a pool-routed `[steps.check]` iteration whose exit condition is the judge |
| `assets/scripts/goal-arm.sh` | validate the contract, record the snapshot, pour the loop |
| `assets/scripts/goal-judge.sh` | the judge: run the oracle, render met/not-yet/impossible/stalled/exhausted, drive the loop |
| `assets/scripts/goal-canonical.sh` | canonical contract serialization, shared by arm and judge |
| `assets/scripts/oracle-review-rounds.sh` | the dogfood oracle: second-review rate from the bead store |
| `assets/scripts/*.test.sh` (4) | hermetic tests: 57 assertions across canonical, judge, arm, oracle |
| `docs/goal-keeper.md` | how a goal is contracted, armed, judged, and read |

## Design decisions

**Rig-local, not a sub-pack.** The keeper runs on gc-toolkit itself (the dogfood
goal), so its formula and scripts live in the gc-toolkit pack's own `formulas/`
and `assets/scripts/`, auto-discovered with the pack. A sub-pack would need a
`city.toml` import in the town repo — a cross-repo change for machinery that has
no second consumer in v1.

**No new standing watcher.** The spec's binding constraint. The keeper is not a
daemon: arming is a script an operator or sitting invokes, the judge is the
`[steps.check]` control bead's exit condition (event-driven on each iteration's
close), and iterations run on the existing polecat pool. Nothing polls.

**The judge runs the oracle; the worker never judges.** The iteration worker does
the work and closes its bead; the judge (a separate exec, in a separate context)
runs the oracle against reality and renders the verdict. v1 oracles are
deterministic, so the judge reaches a binary verdict with no model judgment. The
oracle runs inline in the control dispatcher, so it must be cheap — a bead-store
query or a quick metric.

**The judge enforces the three-way budget from the editable contract.** The
formula's `max_attempts` is a hard ceiling, not the budget. The real budget is
`goal.budget.*` on the goal bead, which an operator edits; the judge reads all
three bounds at each verdict and parks on the first that trips. Iterations and
wall-clock are enforced; the token budget is recorded but not enforced, because
the condition environment carries no per-iteration token count (it waits on the
engine convergence-telemetry request, gc-vz6v0).

**Verdict maps to the loop's exit code.** `met` and every park exit 0 (the loop
is terminally resolved; the goal bead's status and assignee say which); `not-yet`
exits 1 so the loop appends the next iteration. A ceiling backstop and a
fail-closed error path (a broken oracle is never `met`) mirror the exhaustion
handback the other check loops in this repo carry, so a goal never strands.

**Tamper-evidence, not tamper-proofing.** Arming snapshots the canonical
contract; the judge re-derives it each verdict and re-arms on a mismatch,
recording the change in the trail. The threat model is a cooperative-but-fallible
worker, matching the failing-test-first prior art: a change to the definition of
done is made visible, not prevented.

## The dogfood oracle

`oracle-review-rounds.sh` computes the second-review rate: of the work anchors
that reached a terminal state (`merge_result ∈ {merged, abandoned, duplicate}`,
closed) in a trailing window, the fraction that took two or more **decided**
review rounds. A decided round is a `task_kind=review` bead pointing at the
anchor that carries both `review_branch` and a `signoff_verdict`. Requiring both
drops two things that are not rounds: validator approve-outcome beads (no
`review_branch`) and pre-redesign commit-churn re-reads (no `signoff_verdict`) —
the churn that made a raw review-bead count unreliable
(`specs/tk-ztapg/review-cycle-architecture.md`).

This is a MEASUREMENT. The per-anchor review-round cap was retired as a gate
(`specs/tk-p82tvo/round-cap-retirement.md`); convergence is judged, not capped.
This oracle only counts, so a goal can measure whether the rate is falling — it
caps nothing and blocks no merge.

Measured at implementation: **34.7%** over a 30-day window (116 of 334 terminal
anchors took two or more decided rounds). Lower than the 51% raw baseline in
tk-h2s7hj.2's body because the decided-round definition excludes churn and
validator beads.

## The dogfood contract (locked from the tk-h2s7hj.2 candidate)

tk-h2s7hj.2's candidate contract left the target, budget, invariants, and bound
clause to be set at contract lock. Locked here:

- statement: cut the second-review rate (decided rounds, trailing 30-day window).
- oracle: metric, `oracle-review-rounds.sh --window-days 30`, `le`, threshold **30**
  (a reduction from the measured 34.7%).
- budget: `max_iterations=6`, `wall_clock=45d`. token_budget unset (not enforced in v1).
- invariants: none set; an operator may add one (each is checked inline by the
  judge, so it must be cheap).
- escalation_target: human.

Arm command (run once the machinery is on main — see below):

```bash
assets/scripts/goal-arm.sh tk-h2s7hj.2 \
  --statement "In gc-toolkit, cut the second-review rate — the share of terminal work anchors that take two or more decided review rounds — over a trailing 30-day window." \
  --oracle-kind metric \
  --oracle-command '"$GOAL_SCRIPTS_DIR/oracle-review-rounds.sh" --window-days 30' \
  --compare le --threshold 30 \
  --max-iterations 6 --wall-clock 45d \
  --escalation-target human \
  --iteration-target gc-toolkit/gc-toolkit.polecat
```

The threshold is a judgment locked without the vision-to-goal distillation loop
(tk-h2s7hj.1, not v1 scope). It is a starting target; the contract is editable,
and the judge re-arms on a change, so an operator can retune it.

## Deferred: the live arming

Arming the live dogfood goal spawns a pool-routed iteration loop, and the formula
is not resolvable in the live city until this change lands (directory imports
read the rig checkout on main, not a branch). So the live arm is a post-land
action, tracked as follow-up bead **tk-bp2oqz** (blocked by tk-tutb46) rather
than performed from this session. The `--dry-run` above was validated green
against the live tk-h2s7hj.2. tk-bp2oqz carries the exact command.

## Provenance

Operator-approved slate item 6, sitting tk-nt5uda (visit tk-rfxy3e), 2026-09-20;
detach redirect and dogfood ruling, sitting tk-eywd7n (subject tk-yaor8a),
2026-09-22. Design input: `specs/tk-yaor8a/goal-primitive-spec.md`. Vision epic:
tk-h2s7hj. Engine telemetry request: gc-vz6v0 (gascity store).
