---
name: Gas City search for the merge design's surface
description: The Gas City, Gas Town, bd and GitHub primitives searched for each piece of operational surface the merge design (tk-1tfzr71.66) asks its units to add or grow, what each search found at a named upstream commit, and what each unit composes or why the primitive does not cover the need. Read it when building or reviewing one of the design's units, or when the arch check asks for the search.
---

# Gas City search for the merge design's surface

Read on 2026-11-09 at `gastownhall/gascity` main 862ee37e4570,
`gastownhall/gascity-packs` main 3339ad104a88 and at 66897e7132c9, the gastown
release that gc 1.4.3 bundles (`PublicGastownPackVersion` in
`internal/config/public_packs.go`), and `gastownhall/beads` v1.3.4
(7ef2fd05eb0c). GitHub's behavior was read from its documentation the same day.
Each section names the unit of [the design](design.md) that adds the surface.

## The city's merge verdict on GitHub (unit 2)

The need: a merge that waits for the city's own conditions. The city must have
judged the PR's head, nothing it tracks may hold the PR, and the city must have
read every review and comment on the PR, the approval that releases it
included, before GitHub can merge. One verdict stands for every PR at a commit,
and two posts of it must not leave the older reading standing.

- **Gas City.** Nothing gates a merge on approval or on required checks. The PR
  monitor classes an open PR from its draft flag, its merge state and its failed
  or pending checks (`classifyPullRequest` in `internal/githubmonitor/monitor.go`),
  and records the class on a repair bead (`gc github pr backfill
  --create-repair-beads`, `cmd/gc/cmd_github.go`). It reads no review, no branch
  rule and no bead's waits, and it never merges. Its CLI reference names no lock
  a pack can take around a write to an outside service (`docs/reference/cli.md`).
  A drain's `member_access = "exclusive"` reserves a convoy's members for one
  drain (`docs/reference/specs/formula-spec-v2.md`), not a write.
- **Gas Town and the other packs.** `gastown/formulas/mol-refinery-patrol.toml`
  opens the PR and never merges it. No file in the packs repository names
  `reviewDecision`, `required_status_checks` or `merge_queue`. gstack's
  `land-and-deploy` skill tells an agent to run `gh pr merge --auto`, and
  pr-review's `mol-pr-merge-only` waits on `gh pr checks` and then runs
  `gh pr merge --squash`, with no review step. Neither waits on a bead.
- **bd.** A `gh:pr` gate resolves on the PR's state alone (`checkGHPRWithRunner`
  in `cmd/bd/gate.go`). It holds a bead until a merge, never a merge until a
  bead.
- **GitHub.** Rulesets require approving reviews, resolved threads and status
  checks ([Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)).
  A required check can be a commit status, and with no `integration_id` any
  account with write access can post it ([Repository rules](https://docs.github.com/en/rest/repos/rules)).
  A required check counts only on the latest commit ([Troubleshooting required
  status checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)).
  A commit status belongs to the repository and the commit, every PR at that
  commit shows it, and the latest status in a context counts, with no
  compare-and-set, so the latest post wins ([Commit
  statuses](https://docs.github.com/en/rest/commits/statuses)). GitHub lists
  a repository's open PRs, each with its head commit
  (`GET /repos/{owner}/{repo}/pulls?state=open`,
  [Pulls](https://docs.github.com/en/rest/pulls/pulls)). Its list of the PRs
  associated with a commit returns only the merged one for a commit on the
  default branch (`GET /repos/{owner}/{repo}/commits/{commit_sha}/pulls`,
  [Commits](https://docs.github.com/en/rest/commits/commits)), so it cannot
  name every open PR at a head.
  Auto-merge merges once every requirement passes, and turns off only when
  someone without write access pushes or the base branch changes, so a review
  that arrives after it is on leaves it on ([Automatically merging a pull
  request](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/automatically-merging-a-pull-request)).
  A review that requests changes from an account with write access holds the
  merge until its author approves or someone with write access dismisses it
  ([Approving a pull request with required
  reviews](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/approving-a-pull-request-with-required-reviews)).

What unit 2 composes: GitHub's required status check and auto-merge, driven by
the pack's one definition of what holds a PR (`prstatus`), which takes the
anchor's waits from the store's own blocked set through the `waits` package,
the one `gctk bead holds` answers from. The gap the primitives leave is the
city's waits and its reading of the reviews and comments, which no rule reads.
A commit status carries the waits and that reading. It passes last, once every other requirement is
met and no feedback on the PR is newer than the anchor's watermarks, so a
review the intake counts is read before the merge, even one that arrives after
auto-merge is on. One status
covers every open PR at its commit, and a `flock` per repository serializes the
posts, because the latest post wins. Auto-merge makes the merge GitHub's once
the status passes, and the projection keeps it on only while the city reads the
PR approved. The warrant *The city's merge status* records it.
`blocker-holder.sh`'s new class composes core's gate sweep: a gate it resolves
is held by an automated actor.

## The bead's wait for its PR's merge, and its close (unit 3)

The need: the bead stays open while its PR is open, and closes once GitHub has
merged it onto the target.

- **Gas Town.** `gc gastown pr-merge-reconcile`
  (`gastown/commands/pr-merge-reconcile/run.sh` at 3339ad104a88) keeps the bead
  blocked until GitHub reports the PR merged and the merge commit is on the
  target. It is not in the bundled release, whose `gastown/commands` holds only
  `status` and whose merge-push closes an `mr` bead at publication. The city
  imports no gastown pack.
- **bd and Gas City.** A `gh:pr` gate resolves when `gh pr view` reports MERGED
  (`checkGHPRWithRunner`, `cmd/bd/gate.go` at v1.3.4). Core's `gate-sweep`
  order checks the gates of the city store and of every rig store that is not
  suspended, every 30s (`internal/bootstrap/packs/core/orders/gate-sweep.toml`,
  `assets/scripts/gate-sweep.sh`).

What unit 3 composes: a `gh:pr` gate on the bead, which core's sweep resolves,
and a close step that makes pr-merge-reconcile's merged checks. The command
itself is out of reach until the city takes a gastown release that carries it.

## The requeue (unit 3)

The need: work the refinery cannot land goes back to the polecat pool.

- **Gas Town** writes `gc.routed_to` to the pool by hand (merge-push's rebase and
  handle-failures paths at 3339ad104a88).
- **Gas City** dispatches through `gc sling`, which accepts the merge strategies
  `direct`, `mr` and `local` (`cmd/gc/cmd_sling.go`; `merge_strategy` in
  `internal/beadmeta/keys.go`).

What unit 3 composes: `gc sling` on `mol-polecat-work`, as the dispatch design
(tk-1tfzr71.54) requires for every pool dispatch.

## The per-rig switch (unit 3)

The need: the refinery opens PRs on the new path only for a rig whose GitHub
rules are in place.

- **Gas City** gives a rig defaults for formula variables (`FormulaVars` on
  `Rig` in `internal/config/config.go`), which the rig's pours read.

What unit 3 composes: one rig formula variable, `github_merge_rules`, read by the
refinery's `mr` step alone. The bead's merge gate tells every other reader which
path the bead is on. The retirement bead deletes the variable.

## The refinery's long gate (unit 3)

The need: a rig gate that outlives the ten-minute cap on one tool call.

- **Gas Town's** run-tests step runs each configured command inline
  (`mol-refinery-patrol.toml` at 3339ad104a88).
- **Gas City's** formula check runs a script in the orchestrator, outside the
  agent's session, bounded by its own timeout (`[steps.check]` in
  `docs/reference/specs/formula-spec-v2.md`). It needs a materialized step bead,
  and the refinery's patrol is a root-only wisp whose steps are not
  materialized.

What stays: `detached-job.sh`, as named in the design's differences, until the
gate runs as a check script or an order.

## The PR's title and summary (unit 1)

The need: a PR titled with a conventional-commit type, and a summary of what the
finished diff does that stays current through reworks.

- **Gas Town** titles the PR with its bead's title and writes the body once, at
  `gh pr create` (merge-push at 3339ad104a88).
- **Gas City's** PR concept has no managed region of a PR body.

What unit 1 builds: `gctk pr compose` and `gctk pr summary`, whose defense is in
[gctk-architecture.md](../../docs/gctk-architecture.md#the-surface). The change
deletes the shell it replaces (`pr-summary-region.sh`).

## The doctor's closed-bead check (unit 4)

The need: every closed bead that opened a PR either landed or carries a
disposition.

- **Gas City.** No check in `internal/doctor` or in core's pack names
  `merge_result`, `merged_sha` or `pr_number` at 862ee37e4570. The doctor runs a
  pack's own checks from their `doctor.toml`.

What unit 4 grows: the pack's existing check (I5) to read every closed bead that
carries `pr_number`. The landing record it reads is the pack's, under the merge
flow the design keeps.

## What the answers change on

- Gas City ships a merge gate that reads a bead's waits, or GitHub can hold a
  merge on a review's own message. The city's status and the auto-merge toggle
  then move onto that primitive.
- GitHub's status API takes an expected prior status, or Gas City ships a lock
  a pack can take around a write to an outside service. The status writer's
  lock then moves onto it.
- The city imports a gastown release that carries `pr-merge-reconcile`. The close
  step then becomes that command.
- Gas Town's refinery requeues through `gc sling`, keeps a branch that has a PR,
  or keys its pre-existing trackers. Each matching difference then ends.
