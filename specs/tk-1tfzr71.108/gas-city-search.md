---
name: Gas City search for the review-loop design's surface
description: The Gas City, gascity-packs, bd and GitHub primitives searched for each piece of operational surface the review-loop design (tk-1tfzr71.108) asks its units to add or grow, what each search found at a named upstream commit, and what each unit composes or why the primitive does not cover the need. Read it when building or reviewing one of the design's units, or when the arch check asks for the search.
---

# Gas City search for the review-loop design's surface

Read on 2026-11-14 at `gastownhall/gascity` main 13bb101b8f and
`gastownhall/gascity-packs` main 0f07496d2f, from snapshots taken at those
commits. GitHub's behavior is cited from gh's manual as installed (`gh pr ready`).
Each section names the unit of [the design](design.md) that adds the surface.
The sections on the check's record and on the run's workspace were read again
on 2026-11-15 at `gastownhall/gascity` main e9a628c500, from the city's
gascity checkout's upstream remote, and each symbol cited there is unchanged at
main 294079d53f.

## The run's formulas (unit 3)

The need: for one PR head, pick the checks the change needs, run each as a lane,
rule the lanes' findings, fix what must be fixed, and repeat on the fix's head
until the checks pass or a bound is reached.

- **Gas City's multi-lane review loop.** `docs/guides/understanding-formulas.md`,
  "Multi-Lane Review Loops", describes this loop: review lanes fan out, a
  synthesizer fans them in, a fix step applies the findings, and the subtree
  repeats under a `[template.check]` until the verdict check passes. The shipped
  example is `gascity/formulas/build-basic-review.formula.toml` in gascity-packs
  (a template step with `max_attempts = 6`, three fixed lanes, a synthesis child
  and an apply child). **Composed.** `mol-pr-review` is that shape. The city
  imports only core and bd from Gas City (`gc import list`), and
  `build-basic-review`'s lanes are three fixed roles that write
  `code_review.<lane>_verdict` keys and apply fixes in no pushed branch, so the
  pack composes the pattern with its own lanes rather than importing the formula.
- **Picking lanes at runtime.** `[steps.on_complete]` is "a runtime for-each
  fan-out over the step's structured output" that bonds an expansion formula per
  item (`docs/reference/specs/formula-spec-v2.md`; `internal/dispatch/fanout.go`;
  `internal/formula/fragment.go`), and on a child of a check step it is created
  again each iteration (`internal/dispatch/control.go`). **Composed**, behind the
  probe the design puts first in unit 3, because no shipped formula in either
  repository uses it. `condition` and `count` loops are fixed at compile time
  (formula-spec-v2.md), so they cannot read triage's output.
- **`[steps.drain]`**, which formula-spec-v2.md calls the canonical v2 fan-out
  (section 3.3), scatters the input convoy into one-member unit convoys and runs
  an item formula per member bead. The lanes are check names that triage writes,
  not beads in a convoy, so a drain would need a bead per lane, which is the
  review bead this design retires. **Not used.**
- **Core's `mol-review-quorum`** (`internal/bootstrap/packs/core/formulas/mol-review-quorum.toml`)
  runs two fixed lanes and an agent synthesis with no check loop, and its Go
  finalizer is not invoked yet. It covers a two-provider vote, not a loop whose
  lanes a triage picks.
- **gascity-packs' `fix-loop-base` and `build-from-review-base`** are placeholder
  contracts whose check validates a report's schema, not an approval
  (`gascity/formulas/fix-loop-base.formula.toml`).
- **`github-pr-review`** keys a review's artifacts and its one PR comment by head
  SHA (`gascity/formulas/github-pr-review.formula.toml`;
  `gascity/assets/workflows/github-pr-review/post-comment.md`), runs one lane with
  no loop, and never changes code. **Composed** for the comment: the run posts one
  comment per head, found again by its mark, as that adapter does by its marker.

## Pouring a run for each head (unit 4)

The need: each head the refinery validates on a PR gets one run, attached so the
PR's bead is held while it works, and a run that ends without a result is poured
again.

- **`gc formula cook --attach`** expands a bead into a sub-workflow at runtime;
  on a v2 formula the bead gains a `blocks` dependency on the root, the root names
  no source bead and the steps route by their own `gc.run_target`
  (`docs/reference/cli.md`, `gc formula cook`; `ensureFormulaCookAttachDep`,
  `stampFormulaCookGraphV2Root` and `decorateFormulaCookGraphV2Recipe` in
  `cmd/gc/cmd_formula.go`; `internal/graphroute/graphroute.go`). **Composed**: it
  is the pour.
- **What decides when to pour.** Order triggers are cooldown, cron, condition,
  event, manual and webhook (`internal/orders/order.go`). An event trigger matches
  the event type only, and no event reports a metadata change such as a new
  validated head (`internal/events/events.go`), so no trigger fires on "a head
  with no result". Gas City's PR monitor files a repair bead per PR head, but
  reads no review, treats a draft as not actionable, and files only for CI and
  merge-state failures (`internal/githubmonitor/monitor.go`;
  `ensureGitHubPRRepairBead` in `cmd/gc/cmd_github.go`). Every PR on the new path
  is a draft while it is reviewed, so the monitor never sees it. **Not covered**:
  the landing order the merge design built already reads each pending record and
  its evaluator answer, and it grows the pour.
- **Re-offering.** Inside a run, Gas City returns a dead session's step to its
  pool and re-runs a check that exits 75 without spending an attempt
  (`maxCheckInfraRetries` in `internal/dispatch/ralph.go`). Nothing upstream pours
  a whole run again once its root closes without the result a pack defined.
  **Not covered**: the order reads the bead's closed run roots and pours again.

## The check script and the result (unit 1)

The need: decide after each iteration whether every check passed at the head,
and record the result for the head and the target the evaluator reads.

- **`[steps.check]`** runs a script after each iteration: exit 0 passes, exit 75
  re-runs it, any other exit iterates (formula-spec-v2.md). **Composed**:
  `gctk review passed` is that script. Gas City holds no review checks, so the
  pass rule over the lanes is the pack's, as `gctk-architecture.md` already
  records for this verb. It reads only the store, because the check's `PATH`
  carries no `gh` (`internal/convergence/condition.go`).
- **A result per head on a bead.** `github-pr-review` keeps a report directory per
  head SHA, and the PR monitor dedupes repair beads by head SHA. Neither records a
  pass on the bead that owns a PR. **Not covered**: the loop's check writes
  `review_results`, the key the merge design's evaluator already reads.
- **Where the record runs.** A formula has no script step: agents execute only
  plain work beads, the orchestrator executes only control beads (`retry`,
  `ralph`, `check`, `retry-eval`, `fanout`, `drain`, `scope-check`,
  `workflow-finalize`), and the one author-supplied script the runtime runs is a
  step's check, run again without spending an attempt on exit 75
  (formula-spec-v2.md at e9a628c500, section 0.2, the step keys of section 1.3
  and section 3.1). A step that only records is still an agent's session, and a
  teardown step (`gc.scope_role = teardown`, which a run cancel spares through
  `TeardownTailExclusionFromMembers` in `internal/molecule/cleanup.go`) is a
  plain work bead too. **Composed**: the record runs in the loop's check, the
  one script the runtime runs at the loop's end, through `gctk review passed
  --record`. The check's script gets the store's connection env, `BEADS_DIR`
  with the Dolt and credentials env (`ConditionEnv.Environ` in
  `internal/convergence/condition.go`), and `gc` and `bd` on its `PATH`, so it
  can write the store as well as read it. It gets no bound on the loop's
  attempts: `runRalphCheck` in `internal/dispatch/ralph.go` sets no
  `MaxIterations` in the script's `ConditionEnv`, and the bound lives on the
  check's control bead (`gc.max_attempts`, which `processRalphCheck` reads),
  which the script is not named. So the check reads the run's `max_attempts`
  var on the root, the value the compiler substitutes into the loop's
  `[steps.check] max_attempts` (formula-spec-v2.md, section 3.1), and knows the
  iteration at that bound is the last, which the runtime closes as exhausted
  when it does not pass (`attempt >= maxAttempts` in `processRalphCheck`).
- **The probe of the record.** On 2026-11-15, a scratch city on the city's gc
  1.4.3 cooked a formula whose checked loop ran a check script that took an
  exclusive lock on `pr-record.lock` in `$BEADS_DIR`, wrote a `review_results`
  value on one bead through `gc bd update` and closed another with
  `gc.work_outcome=no-op` and a note, all from the control dispatcher
  (`gc convoy control`). At a pass the script exited 0 and the loop and the
  workflow closed passed. In a loop of two attempts the script exited 1 at the
  first, and at the second wrote the same way and exited 1, and the loop closed
  `gc.outcome = fail` with `gc.failed_attempt = 2` and no
  `gc.final_disposition`, its writes standing. The root carried
  `gc.var.max_attempts` equal to the loop's `gc.max_attempts`, the script read
  `GC_MAX_ITERATIONS=0`, and `GC_BEAD_ID` named the iteration's scope bead. The
  same city then cooked the pack's own `mol-pr-review`, with its check script
  and gctk built from the change, and the steps played: a passing round
  recorded `passed: true` and closed the ask it declined with
  `gc.work_outcome=no-op`, and a loop of two attempts that never passed
  recorded `passed: false` at its last judged head and filed the
  `review-loop-exhausted` gate on the PR's bead before the loop closed failed.
- **Whether a closed run's record landed.** Read at `gastownhall/gascity` main
  d2254b579682: the loop's control bead keeps `gc.attempt_log`, one entry per
  graded attempt holding the check's outcome and its stderr
  (`appendAttemptLogValue` in `internal/dispatch/control.go`), and
  `gc.check_infra_retry`, the count of re-runs that spent no attempt
  (`spendCheckInfraRetry` in `internal/dispatch/ralph.go`). Once that count
  reaches `maxCheckInfraRetries`, `evaluateRalphIteration` grades the next
  blind read an ordinary failure, so a loop whose record never landed closes
  `gc.outcome = fail` with no `gc.final_disposition`, as a loop whose check
  recorded and exited 1 does, and neither key says whether the check's write
  landed. **Not covered**: each `review_results` entry names the root of the
  run that recorded it (`run`), and the landing order counts a closed run as
  one with a result only while the entry for its last head and target names
  it.
- **The landing order's pass**, which the sitting proposed for an exhausted
  loop, already reads how each run ended. It would record an exhausted run only
  after the run closed, and would have to keep which exhausted runs it had
  recorded and gated, so that a cleared gate is not filed again. **Not used**:
  the check knows its last attempt and records then, in the same act as its
  verdict.

## The check index (unit 1)

`gctk review checks` and `gctk review guidance` port `review-checks.sh`. No Gas
City or gascity-packs file declares review checks or resolves a rig's overlay at a
commit (searched `docs`, `internal` and every `formulas` directory for
`review-checks` and `check index`, 2026-11-14), as the arch review of #1321 found
at ac4a392e9. **Not covered**: the port moves existing surface into gctk and
deletes the shell.

## Asks (unit 1, unit 4)

The need: a request for a change on a PR's branch, or for a check at its next
head, that holds the PR's bead and is worked by the review run, never by a
writer of its own.

- **bd's create with `--deps blocks:<bead>`** files the bead and its edge in one
  write. **Composed**: an ask is a task bead that holds the PR's bead by its own
  edge, with the existing `branch` key, and no new bead kind.
- **The PR monitor's repair bead** (`ensureGitHubPRRepairBead`) is routed and
  poured with the monitor's `repair_workflow` when it is filed, so it is a writer
  of its own. **Not covered** for an ask, which must stay unrouted so the run is
  the branch's one writer. tk-1tfzr71.21's join can file the monitor's repair work
  in the ask's shape.
- **Telling an ask from a writer on the branch.** Read at `gastownhall/gascity`
  main d2254b579682: `restampWorkBeadRouting` in `internal/sling/sling_core.go`
  stamps `gc.execution_routed_to` on a work bead whose graph workflow the sling
  started and clears its `gc.routed_to` and `gc.run_target`, and the work bead
  stays unassigned while the workflow's steps are claimed, so a fix unit on the
  branch carries no `gc.routed_to` and no assignee. **Composed**: an ask
  carries neither route, no assignee and no `task_kind`, the role a rework child
  carries, one rule `isAsk` in `services/gctk/review/ask.go` and `refinery_ask`
  in `assets/scripts/refinery-lib.sh` both apply.
- **`review_checks`**, the checks an ask sends back, is a new metadata key. Nothing
  upstream records on a bead which checks a later run must run.

## The draft cycle and the withdrawal (unit 2)

- **Draft and ready.** Nothing in Gas City or gascity-packs moves an open PR
  between draft and ready: the only draft control is `--draft` at creation
  (`gascity/assets/scripts/github_api.py`), and the PR monitor skips drafts
  (searched both for `gh pr ready`, `markPullRequestReadyForReview` and
  `convertPullRequestToDraft`). gh does it: `gh pr ready <pr>` marks a PR ready and
  `--undo` converts it to draft. **Composed**: `gctk pr draft` and the order's ready
  transition call GitHub through gctk's gh adapter after reading the flag.
- **Dismissing an approval.** Nothing in either repository dismisses a GitHub
  review (searched for `dismissals` and `dismiss`). **Not covered**: the landing
  order dismisses through GitHub's review dismissal, as `approval-withdraw.sh`
  does today, and `withdraw_head` is the new key that names the head the
  withdrawal was filed for. **Composed** for which approvals it dismisses:
  GitHub's compare of that head with a review's `commit_id`
  (`compare/<withdraw_head>...<commit_id>`) says whether the approved commit
  contains the head, so the order walks no history of its own.

## The run's workspace and its reap (unit 3)

The need: one directory for the run, outliving each step's session, that holds
a detached git worktree of the rig's checkout for triage, each lane and the
repair, and that goes once the run ends, however it ends.

- **A session's work directory and worktree events.** Gas City gives a session a
  work directory and reports worktree events (`bead.worktree.*` in
  `internal/events/events.go`), but a run's steps are claimed by different
  sessions, so no session's directory holds the run.
- **Molecule-scoped working storage.** Gas City keeps
  `<city>/.gc/molecules/<root>/`, with `artifacts/<bead>/` under it, as storage
  that outlives any worker (`internal/molecule/artifact.go`, since 46a1425717).
  Three things keep it from covering the need. A pool step's shell is not
  given its path: `GC_ARTIFACT_DIR` reaches the route env of a bead `gc sling`
  slings (`ResolveSlingEnvForBead` in `internal/sling/sling.go`) and a check's
  script (`resolveRalphCheckMoleculePaths` in `internal/dispatch/ralph.go`),
  and a run's steps are routed at the cook and claimed through `gc hook --claim`
  by sessions already running, so a step would have to rebuild the path from
  the package's layout, which no page documents beyond naming the directory
  (`docs/reference/exec-session-provider.md`). Only the workflow's finalizer
  removes it, with `os.RemoveAll` (`molecule.RemoveDir` in
  `processWorkflowFinalize`, `internal/dispatch/runtime.go`), and a run cancel
  closes the finalizer unrun, because it spares only teardown members and the
  finalizer carries no teardown role (`cancelWorkflowRoot` in
  `internal/api/huma_handlers_runs.go`; the `workflow-finalize` step in
  `internal/formula/graph.go`), so a cancelled run's directory stays, and
  nothing else sweeps `.gc/molecules`. A run that must stop ends by exactly that
  cancel. And `os.RemoveAll` removes a git worktree's directory and leaves its
  registration in the rig's checkout, which only `git worktree prune` clears,
  repository-wide, the call `review-workspace.sh` refuses to make
  (`docs/worktree-reclaim.md`). The probe above saw the directory of a run that
  passed removed at its finalize.
- **Not covered**: `review-workspace.sh` keys the directory by the run's root,
  and `orders/review-workspace-reap.toml`, keyed the same way, removes it once
  the root closes, however the run ended, each worktree first through
  `git worktree remove`.

## The cutover script (unit 5)

`review-cutover.sh` closes a moved bead's old review scaffolding at a rig's
cutover. bd closes beads, and the script composes bd's checked close over the
beads it finds. It closes through `gc bd update --status=closed`, the form that
carries `gc.outcome=superseded`, the note and the runtime's work record in the
same write, since `gc bd close` sets no metadata. Gas City's work-record gate
checks that form beside `gc bd close`, and it wants `gc.work_outcome` on a plain
task bead's close (the package comment and `Gated` in
`internal/workrecord/gate.go`), so each close records `no-op`. bd refuses the
close of a bead an open blocker holds, so a must-fix machine finding whose fix
unit is still open stays open, and `finding.sh close-answered` closes it once
that unit lands. The script exists only for the cutover and goes with the old
path's retirement.
