---
name: Gas City search for the GitHub intake on the landing order's read
description: The Gas City, Gas Town, gascity-packs and GitHub primitives searched for the surface tk-1tfzr71.21's design adds, namely the city's taken mark in the definition of feedback, the landing order's act that takes each person's post as an ask, the saved read's list of untaken posts, the review run's answers on GitHub, the run poured behind its own question gates, and the red-check and conflict acts with their gates. It says what each search found at a named upstream commit and why none covers the need. Read it when building or reviewing one of the design's units, or when the arch check asks for the search.
---

# Gas City search for the GitHub intake on the landing order's read

Read on 2026-11-16 in a checkout of `gastownhall/gascity` at main 76a06b2327
(2026-11-16T03:05:19Z), of `gastownhall/gascity-packs` at main 0f07496d2f
(2026-11-13T23:13:29Z), and of `gastownhall/beads` at tag v1.3.4 (7ef2fd05eb),
the bd the city runs beside gc 1.4.3 (`gc bd version`). The initiative's leads were read at Gas City main
e9a628c500 and 294079d53f, and none of the files cited below changed between
294079d53f and 76a06b2327 (`git diff --stat` over `internal/githubmonitor`,
`internal/webhooksink`, `internal/api/handler_webhook.go`, `cmd/gc/cmd_github.go`
and `internal/config`). Each section names the unit of [the design](design.md)
that adds the surface. The landing order's one read per pass, which every unit
here builds on, has its own search in
[tk-1tfzr71.149's record](../tk-1tfzr71.149/gas-city-search.md), at the head of
PR #1533.

## Which posts the city has taken (units 1 and 2)

The need: for each review, inline comment and conversation comment a person
makes on a city PR, a record of whether the city has taken it into work, which
holds for a post that arrives with an id older than one the city has already
taken, and which a display can read from the one saved read.

- **Gas City's PR monitor** reads no review, comment or reaction. Its
  `pullRequestsQuery` (`internal/githubmonitor/client.go`) lists open PRs with
  their number, title, URL, author, draft flag, merge state, refs, head and the
  last commit's check contexts. Not covered.
- **Gas City's webhook receiver** hands an order the rule's extracted arguments,
  never the payload (`routeOrder` in `internal/webhooksink/sink.go` passes
  `match.Vars`), and keeps no record of which deliveries became work beyond its
  dedup of a body hash. Not covered.
- **Gas Town's reconcile** reads a record's PR with `gh pr view --json
  url,number,state,headRefName,headRefOid,baseRefName,mergedAt,mergeCommit`
  (`gastown/commands/pr-merge-reconcile/run.sh`, line 180), no review or
  comment. Not covered.
- **The github pack** (`gascity-packs/github`). Its command path returns nothing
  for a comment on a PR (`extract_issue_comment_request` in
  `github/scripts/github_intake_common.py` returns `None` when the issue carries
  `pull_request`). Its addressed path (`extract_addressed_comment_requests`)
  takes a conversation comment that carries a configured address from an
  authorized user, PRs included, and files a source bead of its own for it. It
  reads no review and no inline comment, ignores a comment that names no
  address, and links the comment to no bead that owns the PR. Not covered.
- **bd** keeps no record per GitHub post. A key on the PR's bead listing the
  posts the city took would be a second record of GitHub's posts in bead
  metadata, which tk-1tfzr71.21's Done rules out.

So the record is the city's own reaction on the post, which GitHub keeps on the
post: 👀 once the city has taken it, 👍 once it owes it nothing more. A reader
asks it as `reactionGroups { content viewerHasReacted }`, GitHub's own field for
the reader's reaction, so it needs no login of its own. `gc_city_handled` in
`assets/scripts/pr-post.sh` reads the 👍 that way today.

Unit 1 adds `gc_city_taken` to `pr-post.sh feedback-def`, a new definition in a
script's output. gctk cannot hold it yet: the definition of feedback has one
copy, in `pr-post.sh`, and the pr domain reads it through its feedback adapter
until tk-ssm8qns.8 moves the city's PR posts into gctk whole
([gctk-architecture.md's debt](../../docs/gctk-architecture.md#debt)).
`pr-post.test.sh` fails a second copy of the rule in any file.

## The act that takes each post (unit 2)

The need: on each pass, for each PR the city owns, take every post a person
made that the city has not taken, as one piece of work on the PR's branch that
blocks the bead owning the PR and that the PR's review run works, in the run
that reads the post, under the record lock, and retried by the next pass when a
write does not land.

- **Gas City's PR monitor with repair beads** files one repair bead per PR head
  for a PR it reads as needing action (`ensureGitHubPRRepairBead` in
  `cmd/gc/cmd_github.go`, deduped on owner, repository, number and head). A
  post is not among its inputs. The bead is routed to the monitor's
  `repair_route`, which validation requires (`repair_route is required` in
  `internal/config/github_pr_monitor.go`), and poured with its
  `repair_workflow`, so it is a writer of its own. Not covered.
- **Gas City's orders.** No order in core's `internal/bootstrap/packs/core/orders`
  reads a PR, and no command in `cmd/gc` reads a PR's reviews or comments: the
  backfill is the only caller of the monitor's query. Not covered.
- **The pr-review pack's `mol-pr-iterate`** (`gascity-packs/pr-review/formulas/mol-pr-iterate.formula.toml`)
  addresses one piece of feedback that a caller names when it slings the
  formula (`--var feedback_source`, `--var feedback_ref`), commits to the local
  branch, replies to that review comment and does not push. It notices no
  feedback, so it is a worker a caller starts by hand, which the review run
  already is here. Not covered.
- **The github pack's addressed router** files a source bead per addressed
  conversation comment and wakes a handling session for it. Not covered, for
  the reasons in the section above.

So the act is the landing order's, in gctk's pr domain, and the work is an ask
(`gctk review ask`), the form the review-lanes effort settled for work on a PR's
branch, whose own search is in
[tk-1tfzr71.108's record](../tk-1tfzr71.108/gas-city-search.md). No bead kind,
key or order is added.

## The saved read's untaken posts (unit 2)

The need: a display, which reads no GitHub, tells from the PR's bead alone
whether a post waits for the city to take it, and the next pass gives that PR a
whole read.

`pr_github_read`'s warrant ("Saved GitHub read" in `docs/warrants.md`) records
that Gas City saves no PR read on a bead. Unit 2 changes what the key's
feedback part holds, the ids of the posts the act left untaken in place of the
newest feedback id in each id space, and re-verifies that warrant against the
same upstream sources when it touches the key.

## The answers on GitHub (unit 4)

The need: once the review run rules a post's ask, a reply in an inline
comment's thread with the ruling's answer and the thread resolved, a 👍 on a
post owed nothing more, a reply naming the gate for a question, and a request
for the person's review once every ask from the reviews of a person whose
request for changes stands is answered, each found again so a retry posts
nothing twice.

- **Gas City** has no command, order or doc that resolves a review thread,
  reacts to a post, requests a review or dismisses one:
  `git grep -l -i -F` for `resolveReviewThread`, `addReaction`,
  `requestReviews` and `dismissPullRequestReview` over `cmd`, `internal`, `docs`
  and `engdocs` at 76a06b2327 finds no file.
- **gascity-packs.** The github pack's commands are `comment-issue`, `create-pr`,
  `import-app`, `map-repo`, `push-branch`, `release-workflow`, `status` and
  `sync-app`, none of which answers in a review thread. `mol-pr-iterate`'s step
  text has an agent reply to the one comment it was slung for, with `gh api`
  and `in_reply_to` (lines 554 and 563), and resolves nothing. No pack resolves
  a thread, reacts on GitHub or requests a review: the same greps over the
  repository find `addReaction` only in the Slack adapter.

So the review run's rule-and-repair step makes them, in `review-run.sh post`,
the verb that already answers the round's rulings in the head's comment. It
composes `pr-post.sh reply`, the pack's one writer of the city's posts, and adds
GitHub's `resolveReviewThread`, `addReaction` and `requestReviews` mutations to
gctk's GitHub adapter beside the mutations it holds
(`markPullRequestReadyForReview`, `convertPullRequestToDraft`, the review
dismissal). The review loop's check cannot hold them. Gas City runs a check
with HOME set to the city's directory and only a whitelist of variables, none
of them a GitHub token (`ConditionEnv.Environ` in
`internal/convergence/condition.go` at 76a06b2327), so gh has no login there.

## A run behind its own question gates (unit 4)

The need: a person's comment that answers a question a review run put to a
person reaches a run while that question's gate is open.

A human gate holds the bead it is filed on until a person clears it, and Gas
City reads no PR comment as a gate's answer: no source under `cmd` or
`internal` at 76a06b2327 reads a GitHub comment except the webhook receiver,
which hands an order only the rule's arguments. So the landing order, which
already decides when a run pours, pours one behind gates of the run's own
question key (`review-question-<slug>`, filed by `review-run.sh question`) when
a post was taken after them. No gate kind or key is added.

## Red checks (unit 5)

The need: from the landing order's read, an ask for a required check that
failed for a code cause, one re-run of the failed jobs of a check that failed
for another cause, a gate where the city cannot go on, the gate withdrawn once
the checks pass, and a restart of a required check that never reported.

- **Gas City's PR monitor** cannot tell a required check from the rest, since
  its query reads no `isRequired` (`pullRequestsQuery`). It counts a cancelled
  check as pending: `checkFailed` in `internal/githubmonitor/monitor.go` lists
  `CANCELED`, GitHub's `CheckConclusionState` spells `CANCELLED`, and
  `checkPending` returns true for any other conclusion that is not a success,
  neutral or skip. It marks every PR that GitHub reads BLOCKED actionable with
  the failure kind `blocked` (`classifyPullRequest`), which includes every PR
  waiting on a review. Its repair bead is a writer of its own (above). Its
  `poll_interval`, `webhook_secret_env`, `webhook_secret_key` and `merge_queue`
  are read only by validation and patches: the readers of each field at
  76a06b2327 are `ValidateGitHubPRMonitors`, `validate_durations.go` and
  `patch.go`, and `WebhookSecretKeyOrDefault` has no caller. Not covered.
- **A re-run of a workflow's failed jobs.** No source or doc at 76a06b2327
  re-runs a GitHub Actions run (`rerun-failed-jobs`, `actions/runs/.../rerun`
  and `gh run rerun` find no file). Not covered.
- **bd's GitHub gates,** which core's `gate-sweep` order checks every thirty
  seconds (`internal/bootstrap/packs/core/orders/gate-sweep.toml`). At
  `gastownhall/beads` v1.3.4 (7ef2fd05eb), a `gh:run` gate waits on one
  workflow run, resolving when it completes with success and escalating when it
  completes failed or cancelled, and a `gh:pr` gate waits for a PR to merge
  (`bd gate check`'s help in `cmd/bd/gate.go`). The acts here decide over every
  required check at the PR's head, re-run a non-code failure once, and ask a
  person only for an approved PR, and the pass reads those checks at every
  interval already. A `gh:run` gate would hold the PR's bead on one run and
  escalate a failure on any PR, approved or not, so it covers none of the three
  rules, and a `gh:pr` gate waits for what the landing order itself does. Not
  covered.
- **The pr-review pack's `mol-pr-ci-diagnose`** reads a PR's check runs and
  writes a verdict to its root bead's notes, slung by hand for one PR, with no
  re-run and no work filed. Not covered.
- **Moving a PR between draft and ready.** Nothing at 76a06b2327 converts a PR
  to draft or marks it ready (`convertPullRequestToDraft`,
  `markPullRequestReadyForReview` and `gh pr ready` find no file), as the
  review-lanes search found at 13bb101b8f
  ([its draft cycle](../tk-1tfzr71.108/gas-city-search.md#the-draft-cycle-and-the-withdrawal-unit-2)).
  The restart reuses gctk's `gctk pr draft` mutations. Not covered.

The gates are Gas City's human gates, filed and withdrawn under a situation key
as the landing order's exceptions are, with the keys today's red-check gates
carry and one more for a check that never reports (`pr-check-unreported.<n>`).
The pass's read gains each check suite's status and creation time, two fields
on nodes tk-1tfzr71.149's request already reads, so no request is added.

## Conflicts (unit 5)

The need: an ask to merge the target into an approved PR that GitHub reads
conflicting, filed only while nothing holds the bead.

- **Gas City's PR monitor** files a repair bead of the failure kind
  `merge_conflict` for a PR GitHub reads DIRTY, routed and poured as above, for
  an approved PR and an unapproved one alike, since it reads no review. Not
  covered.
- **Gas Town's refinery** brings a branch current in its own prep, for a work
  bead it holds (`gastown/formulas/mol-refinery-patrol.toml`), and the merge
  design kept that flow. A PR on the pending record at its validated head is
  the landing order's, and the review run is its branch's one writer
  ([the review-lanes design, section 1](../tk-1tfzr71.108/design.md#what-pours-it)).
  Not covered.

So a conflict is an ask, as the refinery's own conflict on a bead that owns an
open PR is since the review-lanes effort.

## The webhook (not built)

GitHub delivers only to a public hook, since a private or tenant hook answers
404 to a request that comes from neither loopback nor an internal proxy
(`webhookRequestAllowed` in `internal/api/handler_webhook.go`). A public hook
may fire only a formula order, never an exec order (`routeOrder` in
`internal/webhooksink/sink.go`), so each delivery would pour work an agent runs,
and the order gets the rule's arguments, never the payload. The design builds
none, and gives a public route to the operator as an option
([design, section 5](design.md#5-the-webhook)).

## The owner hop (dropped)

`docs/gctk-architecture.md` lists `gctk pr owner <pr>` for "a GitHub event on an
open PR" taken to the bead that owns it. With no webhook and no monitor, no
event arrives, and the landing order reads each PR from the bead that owns it
through its listing (`Listing.PRAnswers` in `services/gctk/listing/pr.go`). The
verb would have no caller, so unit 6 removes its row.
