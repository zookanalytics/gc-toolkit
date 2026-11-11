---
name: Gas City search for the merge design's surface
description: The Gas City, Gas Town, bd and GitHub primitives searched for each piece of operational surface the merge design (tk-1tfzr71.66) asks its units to add or grow, what each search found at a named upstream commit, and what each unit composes or why the primitive does not cover the need. Read it when building or reviewing one of the design's units, or when the arch check asks for the search.
---

# Gas City search for the merge design's surface

Read on 2026-11-11 at `gastownhall/gascity` main 6bd609f5bfb4, which reads the
same as 862ee37e4570 for everything cited here except a formula check's attempt
count, at `gastownhall/gascity-packs` main 7f86098c04ea and at 66897e7132c9,
gastown 0.1.13, the release that Gas City main and the city's gc 1.4.3 bundle
(`PublicGastownPackVersion` in `internal/config/public_packs.go`), and at
`gastownhall/beads` v1.3.4 (7ef2fd05eb0c). GitHub's behavior was read from its
documentation, its GraphQL schema and the manual of gh 2.103.3 the same day.
Each section names the unit of [the design](design.md) that adds the surface.

## The work's record from publication to the verified merge (unit 3)

The need: the bead the work was filed as stays open from the PR's publication
until its merge is verified on the target, so the work that waits on it starts
only on code that has landed. A push someone else makes onto the PR reuses the
same bead and PR, and the city validates it before anything merges. A PR closed
without merging, merged at a head the city did not validate, or moved to
another base is not a delivery.

- **Gas Town.** `gc gastown pr-merge-reconcile`
  (`gastown/commands/pr-merge-reconcile/run.sh` at 7f86098c04ea) is that record.
  `record` leaves the bead `blocked` and assigned to the refinery with
  `merge_result=pull_request_pending`, the PR's identity and the validated head.
  Each reconcile reads one PR by its URL, requeues a changed head as
  `pull_request_head_changed`, and closes the bead as `mr_merged` only once the
  merge commit is on a freshly fetched target. Closed, contradictory and
  unvalidated ends block the bead and mail the mayor. The refinery runs the
  reconcile once per find-work, and the witness wakes the refinery when a
  pending check is due (`gastown/README.md`). No release carries it: gastown
  0.1.13, the last the packs registry lists, closes an `mr` bead at publication
  with `merge_result=pull_request`, and its `gastown/commands` holds only
  `status`. The city imports no gastown pack.
- **bd.** A `gh:pr` gate resolves when `gh pr view` reports MERGED, and on
  CLOSED it escalates through `gt escalate`, which the city does not have, and
  stays open (`checkGHPRWithRunner` in `cmd/bd/gate.go`). It holds a bead until
  a merge, and it neither checks the merged head nor finds the merge commit on
  the target.
- **Gas City.** Convoy progress counts closed members and reads no PR
  (`ConvoyProgress` in `internal/convoy/convoy.go`), so a convoy's completion is
  no merge check. A workflow's finalize closes the `gc.source_bead_id` chain on
  a pass and leaves it open on a failure or a cancel (`processWorkflowFinalize`
  in `internal/dispatch/runtime.go`).

What unit 3 composes: Gas Town's record, with its values and their meanings,
written by `gctk pr record` and `gctk pr reconcile`, because no release the
city can import carries the command. It adds no state beside the record. Its
differences are that the exceptions file a human gate in place of the mayor's
mail, and that no artifact cleanup follows the close, so the reconcile clears
`pr_reconcile_pending` at the close. The pack's work runs name no source bead,
so finalize closes none of the work's beads.

## The decision to merge (units 2 and 3)

The need: one decision, for each PR's current revision, that the city's
contract holds. Your approval stands, nothing the city tracks holds the PR, the
review results name the PR's current head and target, every review and comment
the city counts has been handled, and everything else the target requires is
met. Then the city merges exactly the head it judged, on the default branch and
on an integration branch alike, with no Merge from you and no permission that
outlives the decision.

- **Gas City.** No Go code merges a PR or reads a review decision (no
  `mergePullRequest`, `gh pr merge` or `reviewDecision` in its Go). The PR
  monitor (`gc github pr backfill`, `internal/githubmonitor`) reads each open
  PR's draft flag, merge state and first 100 check contexts, and no review or
  comment, and it lists open PRs only under one 45-second limit for the whole
  scan. `classifyPullRequest` marks a PR that GitHub reports `BLOCKED`
  actionable, one waiting on an approval included, and
  `--create-repair-beads` files a repair bead per PR head for such a PR. So
  the monitor is neither a decision to merge nor a record of the city's PRs.
- **Gas Town and the other packs.** `gastown/formulas/mol-refinery-patrol.toml`
  opens the PR and never merges it. gstack's `land-and-deploy` skill tells an
  agent to run `gh pr merge`, with `--auto` or `--squash`, and after any failed
  exit to read the PR's state rather than run the merge again. pr-review's
  `mol-pr-merge-only` has a polecat squash-merge with no review step. None of
  them waits on a bead or reads a review.
- **bd.** A `gh:pr` gate holds a bead until a merge, never a merge until a bead.
- **GitHub.** Rulesets require approving reviews, resolved threads and status
  checks on the branches they cover, and gc-toolkit's integration branches
  carry none of them ([Available rules for
  rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)).
  A review records whether its author can push to the repository
  (`authorCanPushToRepository`), the access GitHub requires of an approval it
  counts toward a required review ([Approving a pull request with required
  reviews](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/approving-a-pull-request-with-required-reviews)).
  A PR's merge state (`mergeStateStatus`) reports a conflict, a check that is
  not passing and the target's unmet rules. `mergePullRequest` merges only
  while the PR's head is the `expectedHeadOid` it names, which
  `gh pr merge --match-head-commit` sets, and `enqueuePullRequest` takes an
  expected head too. On a target that requires a merge queue, `gh pr merge`
  turns on auto-merge when the required checks have not passed (gh's manual).

**The alternative evaluated, and the one taken.** The design's earlier draft
let GitHub's auto-merge make the merge, held by a required commit status the
city posted at each head. That needed the status on every target's rules, a
verdict for every PR that shares a commit, a lock around each post, a pending
status before each push, a record and a wait for every post or push GitHub left
unanswered, and a bypass of the integration branches' rules for the city's own
pushes. A commit status belongs to a commit, not to a PR, and the status API
has no compare-and-set ([Commit
statuses](https://docs.github.com/en/rest/commits/statuses)), which is where
that machinery came from. The head-conditional merge request needs none of it:
the evaluator answers for one PR at a time, the request names the head it
judged, and GitHub refuses it once the head has moved. It costs the window
between the evaluator's read and GitHub's merge, which today's merge has too,
since `gctk merge` already merges with `--match-head-commit`
(`services/gctk/internal/cli/merge.go`), and it leaves a person's own Merge on
GitHub outside the city's holds.

What units 2 and 3 compose: GitHub's head-conditional merge, and its enqueue on
a target that requires a merge queue, driven by one evaluator of the pack's,
which reads the bead's waits through the `waits` package that `gctk bead holds`
answers from, the review results at the head, GitHub's reviews and merge state,
and the anchor's feedback receipts. The gap the primitives leave is the
approval on a branch with no rule, the bead's waits and the city's reading of
the feedback, which no rule reads. `gctk pr status` grows the conditions not
met in its output, so the board shows what the merge reads.

## The landing order (unit 3)

The need: every pending record is read on a schedule, so a PR that waits on
your approval or on its checks lands once it is ready, with no agent waiting on
it, no two runs at once, and a bound on how long any record waits to be read.

- **Gas City.** An exec order runs a command with no agent, on a cooldown that
  counts from a run's start, under a 300-second limit by default
  (`TimeoutOrDefault` in `internal/orders`). The dispatcher starts no run while
  the order's tracking bead or the work it started is open, and an order fails
  closed when those gates time out unless it is marked `idempotent`
  (`cmd/gc/order_dispatch.go`). An order that a webhook fires skips both gates
  (`memoryOrderDispatcher.Dispatch`), and the webhook intake drops a repeated
  delivery from an in-memory set for 30 minutes, with no serialization per PR.
  Nothing in Gas City runs the PR monitor on a schedule.
- **Gas Town.** The refinery reconciles one record per find-work, and its
  witness wakes it when a pending check is due, so the refinery's session waits
  on the merge.

What unit 3 composes: a rig-scoped cooldown exec order, `pr-reconcile`, that
runs `gctk pr reconcile` over a bounded number of records, the least recently
checked first, under the dispatcher's own gates. No webhook fires it, since a
webhook-fired order skips them.

## The requeue (unit 4)

The need: work the refinery cannot land goes back to the polecat pool.

- **Gas Town** writes `gc.routed_to` to the pool by hand (the rebase and
  handle-failures paths at 7f86098c04ea).
- **Gas City** dispatches through `gc sling`, which accepts the merge strategies
  `direct`, `mr` and `local` (`cmd/gc/cmd_sling.go`; `merge_strategy` in
  `internal/beadmeta/keys.go`).

What unit 4 composes: `gc sling` on `mol-polecat-work`, as the dispatch design
(tk-1tfzr71.54) requires for every pool dispatch.

## The refinery's selection of work (unit 4)

The need: the refinery prepares a branch only when nothing holds the bead and
no other open bead is working on the branch.

- **Gas Town's** find-work lists the beads assigned to the refinery, open or in
  progress, that carry a branch (`mol-refinery-patrol.toml` at 7f86098c04ea),
  and reads no wait.
- **Gas City** claims a bead and changes only the bead (`BdStore.Claim`), and
  nothing in it locks a branch.

What unit 4 composes: Gas Town's selection, then the bead's waits through
`gctk bead holds` and the open beads on the branch, with a rework child taken
before its anchor.

## The per-rig switch (unit 4)

The need: the refinery publishes onto the new record only on a rig that has
moved to it.

- **Gas City** gives a rig defaults for formula variables (`FormulaVars` on
  `Rig` in `internal/config/config.go`), which the rig's pours read.

What unit 4 composes: one rig formula variable, `pending_through_merge`, read
by the refinery's `mr` step alone. The record's value tells every other reader
which path a bead is on. The retirement bead deletes the variable.

## The refinery's long gate (unit 4)

The need: a rig gate that outlives the ten-minute cap on one tool call.

- **Gas Town's** run-tests step runs each configured command inline
  (`mol-refinery-patrol.toml` at 7f86098c04ea).
- **Gas City's** formula check runs a script in the orchestrator, outside the
  agent's session, up to its `max_attempts` (`[steps.check]` in
  `docs/reference/specs/formula-spec-v2.md`). It needs a materialized step bead,
  and the refinery's patrol is a root-only wisp whose steps are not
  materialized.

What stays: `detached-job.sh`, as named in the design's differences, until the
gate runs as a check script or an order.

## The PR's title and summary (unit 1)

The need: a PR titled with a conventional-commit type, and a summary of what the
finished diff does that stays current through reworks.

- **Gas Town** titles the PR with its bead's title and writes the body once, at
  `gh pr create` (merge-push at 7f86098c04ea).
- **Gas City's** PR concept has no managed region of a PR body.

What unit 1 builds: `gctk pr compose` and `gctk pr summary`, whose defense is in
[gctk-architecture.md](../../docs/gctk-architecture.md#the-surface). The change
deletes the shell it replaces (`pr-summary-region.sh`).

## The doctor's closed-bead check (unit 5)

The need: every closed bead that opened a PR either landed or carries a
disposition.

- **Gas City.** No check in `internal/doctor` or in core's pack names
  `merge_result`, `merged_sha` or `pr_number`. The doctor runs a pack's own
  checks from their `doctor.toml`.

What unit 5 grows: the pack's existing check (I5) to read every closed bead that
carries `pr_number`, with `mr_merged` and `merged` as landed.

## What the answers change on

- The city imports a gastown release that carries `pr-merge-reconcile`. The
  record and the close then become that command, and the pack keeps the
  readiness check and the merge request.
- Gas City or Gas Town ships a merge gate that reads a bead's waits and a PR's
  reviews. The evaluator then moves onto that primitive.
- GitHub can hold a merge on a rule that a branch without rulesets carries, or
  on a review's own message. The evaluator's approval and feedback conditions
  then move onto GitHub.
- Gas City's webhook dispatch keeps an order's gates. A webhook can then make
  the landing order's next run come sooner.
- Gas Town's find-work reads waits, Gas Town's refinery requeues through
  `gc sling`, keeps a branch that has a PR, or keys its pre-existing trackers.
  Each matching difference then ends.
