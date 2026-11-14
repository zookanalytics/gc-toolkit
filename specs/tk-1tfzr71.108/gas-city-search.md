---
name: Gas City search for the review-loop design's surface
description: The Gas City, gascity-packs, bd and GitHub primitives searched for each piece of operational surface the review-loop design (tk-1tfzr71.108) asks its units to add or grow, what each search found at a named upstream commit, and what each unit composes or why the primitive does not cover the need. Read it when building or reviewing one of the design's units, or when the arch check asks for the search.
---

# Gas City search for the review-loop design's surface

Read on 2026-11-14 at `gastownhall/gascity` main 13bb101b8f and
`gastownhall/gascity-packs` main 0f07496d2f, from snapshots taken at those
commits. GitHub's behavior is cited from gh's manual as installed (`gh pr ready`).
Each section names the unit of [the design](design.md) that adds the surface.

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
  pass on the bead that owns a PR. **Not covered**: `gctk review record` writes
  `review_results`, the key the merge design's evaluator already reads.

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

Gas City gives a session a work directory and reports worktree events
(`bead.worktree.*` in `internal/events/events.go`), but a run's steps are claimed
by different sessions, so no session's directory holds the run. **Not covered**:
`review-workspace.sh` keys the directory by the run's root, and
`orders/review-workspace-reap.toml` stays as the backstop, keyed the same way.

## The cutover script (unit 5)

`review-cutover.sh` closes a moved bead's old review scaffolding at a rig's
cutover. bd closes beads, and the script composes `gc bd close` over the beads it
finds. It exists only for the cutover and goes with the old path's retirement.
