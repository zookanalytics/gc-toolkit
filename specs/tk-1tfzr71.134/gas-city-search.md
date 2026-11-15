---
name: Gas City search for the saved GitHub read and the label's writer
description: The Gas City, Gas Town, bd and GitHub primitives searched for the surface tk-1tfzr71.134's design adds, namely the GitHub read the landing order saves on each PR's bead, the condition a display names when that read is not of the PR's head, and the landing order's write of the PR's status label. It says what each search found at a named upstream commit and why none covers the need. Read it when building or reviewing one of the design's units, or when the arch check asks for the search.
---

# Gas City search for the saved GitHub read and the label's writer

Read on 2026-11-15 at `gastownhall/gascity` main a1eb65702f, at
`gastownhall/gascity-packs` main 0f07496d2f, and at `gastownhall/beads`
7ef2fd05eb0c, the v1.3.4 build the city runs beside gc 1.4.3. The sitting that
ruled the target searched at Gas City main cf33557276 (tk-1tfzr71.88's notes,
"Findings for the board's PR-state architecture"). The five commits since then
change none of the files cited here: `git diff cf33557276 a1eb65702f` over
`internal/githubmonitor`, `cmd/gc/cmd_github.go`, `internal/api/handler_webhook.go`,
`internal/webhooksink` and `internal/api/dashboardbff/exec.go` is empty. Each
section names the unit of [the design](design.md) that adds the surface.

## GitHub's facts about a PR, saved on the bead that owns it (unit 1)

The need: one writer brings GitHub's facts about each PR on Gas Town's pending
record into the store, at the cadence it already reads them, on the bead that
owns the PR, so that every display derives the PR's status from the store and
none reads GitHub. The facts are the ones the evaluator's rule reads: the PR's
identity, state, draft flag, head and merge state, the required check runs at
that head, the approvers and change-requesters among accounts that can push,
the highest feedback id in each comment space, and the review threads waiting
on the city's answer, each tied to the head and the time of the read.

- **Gas City's PR monitor.** `gc github pr backfill` is the one caller of
  `internal/githubmonitor`, and no order in the core pack runs it. Its query,
  `GasCityPRReadiness` (`pullRequestsQuery` in
  `internal/githubmonitor/client.go`), lists open PRs with their number, title,
  URL, author, `isDraft`, `mergeStateStatus`, base and head refs, `headRefOid`
  and the last commit's `statusCheckRollup`. It reads no review, no review
  thread, no comment, and no check's `isRequired`.
  `EvaluatePullRequestsWithAllowedAuthors` classifies each PR, and with
  `--create-repair-beads` the backfill files or refreshes one repair bead for
  each PR it finds actionable, writing `github.failure_kind`,
  `github.merge_state_status`, `github.state`, `github.failed_checks`,
  `github.pending_checks` and the PR's refs on that repair bead
  (`githubPRRepairVolatileMetadata` in `cmd/gc/cmd_github.go`). It is the
  closest primitive: it saves GitHub facts as bead metadata, but on its own
  repair beads, only for a PR it reads as broken, and without the reviews,
  threads and required checks the rule reads. Nothing it writes lands on the
  bead that owns a PR.
- **Gas Town's pending record.** `pr-merge-reconcile`
  (`gastown/commands/pr-merge-reconcile/run.sh` at 0f07496d2f) reads the PR's
  URL, number, state, head ref, head commit, base ref, merge time and merge
  commit through `gh pr view`, and writes only the record's own keys, such as
  `pr_state`, `pr_last_checked_at`, `pr_reconcile_error`, `merge_result` and
  `observed_pr_head_sha`. It holds no review, check, draft or merge-state fact.
- **bd.** `bd github sync` syncs beads with GitHub issues through the issues
  endpoints (`FetchIssues`, `CreateIssue`, `UpdateIssue`, `AddLabels` in
  `internal/github/client.go`), and reads no review, check or thread. A `gh:pr`
  gate reads `gh pr view <id> --json state,title` and resolves on `MERGED`
  (`checkGHPRWithRunner` in `cmd/bd/gate.go`). A bead's `external_ref` holds a
  reference, not state.
- **Gas City's webhook receiver.** A verified delivery fires the order its rule
  names, with the fields the rule extracts as the order's args, and the event
  it records names the rule, the order and the body's size, never the body
  (`internal/api/handler_webhook.go`). A public webhook may fire a formula
  order only, never an exec order (`internal/webhooksink/sink.go`, its rule
  R4), and the landing order is an exec order. A webhook that has the landing
  order check one PR is later work, and the operator's call, as the
  initiative's description says.
- **Upstream's own display.** The dashboard runs its commands under `cleanEnv`,
  which forwards no `GITHUB_TOKEN` (`internal/api/dashboardbff/exec.go`), so
  upstream's display reads no GitHub either.
- **No upstream Go reads a PR's reviews.** `git grep -i -E
  'reviewDecision|reviewThreads|latestReviews|pullRequestReview'` over
  a1eb65702f's Go outside tests finds nothing.

What unit 1 composes: the reads the landing order already makes at each check,
through gctk's gh adapter and the feedback adapter, saved as one JSON value in
one key the pr domain declares, `pr_github_read`, through the ledger's JSON
codec as `review_results` is, in the same guarded write that records the check
(`record.Checked`). It adds no read of GitHub at a check of a PR open at its
validated head, no order and no second writer. The key sits in the pack's
`pr_` namespace, apart from the monitor's `github.*` keys, so no reader takes it
for the monitor's.

## The condition a display names when the saved read is not of the PR's head (unit 1)

The need: a display tells a PR whose GitHub read was taken at the head the city
holds for it from one whose read is older than that head, or about another PR,
or missing, without reading GitHub. The evaluator's answer then names that
GitHub's side is not read yet, and none of GitHub's conditions, while the
store's conditions stand as at any read.

- **Gas Town's record** holds the PR's head without GitHub: `pr_head_sha`, the
  head the refinery validated and published, and `observed_pr_head_sha`, the
  head the reconcile found when it sent a changed head back. The design reads
  both. Nothing in the record says how old a read of GitHub is.
- **Gas City** keeps no read of a PR's GitHub facts on any bead it does not
  file itself (above), so it has no notion of such a read's freshness.
- **No reader of readiness exists upstream** to carry the condition
  ([the merge design's search](../tk-1tfzr71.66/gas-city-search.md), "The
  decision to merge").

What unit 1 adds: one value, `github-unread`, in the evaluator's condition
kinds, which `gctk pr status` prints among the conditions not met, as it prints
every other kind.

## The landing order's write of the status label (unit 3)

The need: the PR's `status:` and `held:` labels keep a writer once
`pr-facts.sh` retires, from the same rule every display runs, and come off when
the landing order records the PR merged or closed.

- **Gas City** writes no label on a PR. Its Go's label writes are bead labels
  through bd (`--add-label` in `cmd/gc/cmd_bd_by_id.go` and
  `internal/bdflags`), and no core order or script edits a PR's labels.
- **Gas Town's github pack** ships `comment-issue`, `create-pr`, `import-app`,
  `map-repo`, `push-branch`, `release-workflow`, `status` and `sync-app`
  (`github/commands/` at 0f07496d2f), and `create-pr.sh`, `status.sh` and
  `comment-issue.sh` never mention a label.
- **bd** writes a bead's labels to the GitHub issue it is synced with, along
  with its title, body and state (`CreateIssue` and `UpdateIssue` in
  `internal/github/tracker.go`). Syncing the bead that owns a PR would write the
  bead's title and body over the PR's, and the sync carries no status of its
  own.
- **GitHub** keeps labels on an issue or a PR and runs no rule that sets one.

What unit 3 composes: the pack's one writer of those labels,
`assets/scripts/pr-status-label.sh`, which derives through `gctk pr status`
and writes only a label that differs, called by the landing order through
gctk's runtime adapter after each check, with the PR's labels from the check's
own read of the PR. The read gains one field, the PR's labels, and no call of
its own. The clear at a merge or a close is that script's `clear` verb, and its
retry rides the record's marker, which Gas Town's record already keeps while a
close's cleanup is owed (`pr_reconcile_pending`).
