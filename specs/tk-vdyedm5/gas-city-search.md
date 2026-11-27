---
name: Gas City search for the converging review
description: The Gas City primitives searched for the review run's account of its rounds, its fresh look and its stop for a person's answer (tk-vdyedm5), what each search found at a named upstream commit and in this city's store, and what the change composes. Read it when building or reviewing how a review run's loop ends, or when the arch check asks for the search.
---

# Gas City search for the converging review

Read on 2026-11-27 at `gastownhall/gascity` upstream/main 6dce31bbb6, and at
210638e33c8b, the commit this city's gc (1.4.3, built 2026-11-26) is built from.

## Ending a checked loop before its bound

**The need.** A review run stops at the round where a fresh look puts the
review to a person, before its loop has spent its attempts.

**The check has no such exit.** formula-spec-v2.md, section 3.1: a check's exit
0 closes the step, 75 runs it again without spending an attempt, 78 holds the
step open, and any other exit is "not yet", which spawns the next iteration
while budget remains. Exhaustion closes the step failed.

**A member does.** The same section, "A hard failure ends the loop": when an
iteration closes `gc.outcome=fail` with `gc.failure_class=hard`, either the
iteration's own bead or, for a check step with children, a member whose hard
failure aborted the iteration's scope, the orchestrator closes the check step
failed in that iteration without running the check script. The step then
carries `gc.failure_class=hard`, the member's `gc.failure_reason` and
`gc.final_disposition=hard_fail`. The code is `evaluateRalphIteration` and
`ralphIterationHardFailure` in `internal/dispatch/control.go`. It landed in
#7583 (fa848a578a, 2026-10-11). Its body gives the reason. A loop whose member
failed hard used to run its whole body again up to `max_attempts` and then fail
anyway, and upstream's own adopt-pr review loop closes its apply-fixes step hard
with `needs_maintainer_decision` to stop for a maintainer's decision in one
pass. The city's gc carries it: `git merge-base --is-ancestor fa848a578a
210638e33c8b` holds.

**Tested against this city.** A step that a fan-out bonds is a member of its
iteration. In review run tk-py3sung (2026-11-26), the lane beads triage's
fan-out bonded in iteration 2 carry `gc.scope_ref` naming
`mol-pr-review.review-loop.iteration.2`, `gc.scope_role=member` and
`gc.on_fail=abort_scope`. The city's dispatcher stamps them: it prepares each
fragment a control of kind `fanout` bonds with `decorateDynamicFragmentRecipe`
(`cmd/gc/cmd_convoy_dispatch.go`), whose `propagateDynamicScopeMetadata` gives
each step the `gc.scope_ref`, `gc.on_fail` and `gc.attempt` of the step the
fan-out follows. That run's iteration-2 rule-and-repair still blocks on its
triage fan-out. So upstream issue #9339, a checked loop dropping the needs
between its children from iteration 2 on, does not bite this formula's shape
here.

**Measured on Gas City's own harness.** On 2026-11-27 the exit was run as well
as read. The run used the dispatch package's crash-injection harness at
210638e33c8b (`internal/dispatch/crash_injection_test.go` and
`ralph_hard_fail_test.go`), with the dispatcher's preparation of a fragment
copied into the run. It cooked this change's mol-pr-review, mol-pr-review-lane
and mol-pr-review-look into the harness's memory store and played each step. A
look that closed `gc.outcome=fail` with `gc.failure_class=hard` ended the loop
at its round, at round 1 and at round 3, a round the loop spawns at run time.
The loop closed failed with `gc.final_disposition=hard_fail` and the look's
`gc.failure_reason`, its check did not run at that round, and no next round was
spawned. A look that closed passed at round 3 let the loop's check run after it,
and the run went on. Without the preparation a bonded step carries no
`gc.scope_ref`, so a hard look only fails its iteration, and the loop runs to
its bound. The stop rests on that preparation, which the dispatcher makes for
every control of kind `fanout` it processes.

**Composed.** The look is a member that rule-and-repair's `on_complete` fan-out
bonds. A stop writes `gc.failure_class=hard` and `gc.failure_reason` on its own
step (`gctk review look --file`, through the ledger's `FailureRecord`). It then
closes with `gc.outcome=fail` (`claim-close.sh --outcome fail`). This is the
exit upstream's own review loop uses, so the change accommodates nothing, and
owes no fix upstream.

**What it means for the run's result.** A loop that a member's hard failure
ends runs no check, so the run records no `review_results` entry, as for any
hard failure (`services/gctk/review/ending.go`). The look's question gate holds
the bead that owns the PR, so the landing order pours no run until a person
answers. The landing order counts a run its look stopped as no failure of the
re-offer (`review.Ending.Asked`), and the PR's status reads the question, a
person's hold, and not the machine's fault.

## The loop's bound

formula-spec-v2.md, section 3.1: `max_attempts` is an integer of at least 1, or
one `"{{name}}"` var resolved at compile time, and a missing, non-integer or
smaller value fails compilation. Gas City has no unbounded check loop. The var's
default goes from 3 to 30, the bound Gas City requires. The run's account ends a
run long before it ([design.md](design.md#the-bound)).

## Reading a review's rounds

**The need.** Count each round's must-fix findings, follow a finding that came
back after a fix, and see when the counts stop falling.

**Searched.** The ralph control keeps an attempt log (`gc.attempt_log`,
`appendAttemptLogValue` in `internal/dispatch/control.go`): each attempt's
outcome and the check's stderr. It reads nothing a review's steps wrote, and
its attempt counts iterations only.

**Composed.** The pack's review domain already reads every step's output of a
run (`services/gctk/review/run.go`), so the account is computed there
(`services/gctk/review/converge.go`), from the outputs Gas City keeps as each
step's `gc.output_json`.

## The question to a person

**Composed.** Gas City's native human gate (`await_type=human`), filed through
`human-gate.sh` under a key of the review run's question family, which the
landing order and the PR's status already read as a ruling a person owes.
Nothing new is added to what a gate is.

## A session that is never the round's ruler

**Composed.** Gas City routes a step by its `gc.run_target`. The look's template
routes to the run's review pool and rule-and-repair to its repair pool, so no
session holds both. Gas City binds steps to one session through
`gc.session_affinity` and `gc.continuation_group`, and no step of review run
tk-py3sung carries either.
