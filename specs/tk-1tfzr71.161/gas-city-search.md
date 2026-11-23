---
name: Gas City search for the GitHub intake on the one-PR update's read
description: The Gas City, Gas Town, gascity-packs and GitHub primitives searched for the surface tk-1tfzr71.21's design adds, namely the city's taken mark in the definition of feedback, the landing order's act that takes each person's post as an ask from the PR's saved read, the saved read's list of untaken posts, the conversion of the old path's receipts on a moved bead, the review run's answers on GitHub with the dismissal of a request for changes, triage's answer, the run poured behind its own question gates, and the red-check and conflict acts with their gates. It says what each search found at a named upstream commit and why none covers the need. Read it when building or reviewing one of the design's units, or when the arch check asks for the search.
---

# Gas City search for the GitHub intake on the one-PR update's read

Read on 2026-11-16 in a checkout of `gastownhall/gascity` at main 994008c628
(2026-11-16T20:35:45Z), of `gastownhall/gascity-packs` at main 0f07496d2f
(2026-11-13T23:13:29Z), and of `gastownhall/beads` at tag v1.3.4 (7ef2fd05eb),
the bd the city runs (`gc bd version`). The initiative's leads were read at Gas
City main e9a628c500 and 294079d53f, and none of the files cited below changed
between 294079d53f and 994008c628 (`git diff --stat` over
`internal/githubmonitor`, `internal/webhooksink`,
`internal/api/handler_webhook.go`, `cmd/gc/cmd_github.go`, `internal/config`
and `internal/convergence/condition.go`). Each section names the unit of
[the design](design.md) that adds the surface. The landing-order design these
units build on, the cheap question, the one-PR update that alone writes a PR's
saved read and the landing order that acts from the beads, has its own search
in [tk-1tfzr71.149's record](../tk-1tfzr71.149/gas-city-search.md), as PR #1533
merged it at bc181140b.

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

The need: for each PR the city owns, take every post a person made that the
city has not taken, as one piece of work on the PR's branch that blocks the
bead owning the PR and that the PR's review run works, decided from the PR's
saved read, under the record lock, and retried by the next run when a write
does not land.

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

So the take is an act of the landing order, in gctk's pr domain, decided from
the saved read the one-PR update writes, as the landing-order design puts the
routing of a person's posts
([its section 12](../tk-1tfzr71.149/design.md#12-the-github-intakes-finish-line)).
The work is an ask (`gctk review ask`), the form the review-lanes effort settled
for work on a PR's branch, whose own search is in
[tk-1tfzr71.108's record](../tk-1tfzr71.108/gas-city-search.md). Once its marks
land, the take runs the one-PR update for the PR, the call a webhook rule makes
in that design. No bead kind, key or order is added.

## The saved read's untaken posts (unit 2)

The need: a display, which reads no GitHub, tells from the PR's bead alone
whether a post waits for the city to take it, and the landing order decides the
take from the bead.

`pr_github_read`'s warrant ("Saved GitHub read" in `docs/warrants.md`) records
that Gas City saves no PR read on a bead. Unit 2 changes what the key's
conversation part holds, the posts the update read with neither of the city's
marks, each with what its ask's reason names, in place of the newest feedback
id in each id space, and re-verifies that warrant against the same upstream
sources when it touches the key.

## The conversion of the old receipts (unit 3)

Read on 2026-11-22 at `gastownhall/gascity` main 7b8d498424
(2026-11-22T19:44:55Z) and in `steveyegge/beads` v1.3.4, the bd the city runs
(`gc bd version` reads 1.3.4, 7ef2fd05e).

The need: on a bead `pr-facts.sh` served, turn its receipts, the watermarks,
answered marks and batch ledgers in the bead's metadata, into the city's marks
on the PR's posts, resolve the old path's machine-finding threads, file the post
of each open human finding as its ask and close the finding onto that ask, and
unset the receipts, before the landing order takes any post on the bead.

- **Gas City** reads none of the pack's keys and keeps no migration of bead
  metadata. Its `migrate` commands move a store's backing data
  (`cmd/gc/cmd_beads_city_migrate_proxied.go` moves a city's store onto the
  proxied server), and `git grep` for `resolveReviewThread`, `addReaction`,
  `dismissPullRequestReview` and `requestReviews` over `cmd`, `internal`,
  `docs` and `engdocs` at 7b8d498424 still finds no file. Not covered.
- **bd's `supersede`** (`cmd/bd/duplicate.go`) records a successor the way the
  conversion needs one recorded: a `supersedes` edge from the old bead onto its
  replacement, then a close. It closes unchecked, guarded on no status or
  assignee, and records no reason. A finding can be ruled by a review run while
  the conversion works, so its close must hold to the status and assignee the
  landing order read under the record lock. The pack's disposition writer,
  `bead-rehome.sh`, composes the same edge with bd's checked close and those
  guards, and the landing order already closes a retired PR's bead through it,
  so the conversion closes each finding through it under `--kind re-homed`,
  with no ruling to check.
- **GitHub's `resolveReviewThread`** is the resolution, which no Gas City or
  gascity-packs code makes ([The answers on GitHub](#the-answers-on-github-unit-4)).
  The conversion adds it to gctk's GitHub adapter beside `addReaction`, which
  the take added.

So the conversion is a landing-order act in gctk's pr domain, decided from the
bead, which files asks through `gctk review ask`'s filing as the take does. The
pr domain declares the receipts it unsets, which `pr-facts.sh` still writes
until the effort's retirement unit deletes it. No bead kind, order or state is
added, and the conversion's removal (tk-1tfzr71.201) deletes it once no open
bead carries the receipts.

## The answers on GitHub (unit 4)

The need: once the review run rules a post's ask, a reply in an inline
comment's thread with the ruling's answer and the thread resolved, a reply
comment that links a post with no thread where words are owed, a 👍 on a post
owed nothing more, a reply naming the gate for a question, and the dismissal of
a person's request for changes once every point it raised is answered, with a
request for that person's review, each found again so a retry posts nothing
twice.

- **Gas City** has no command, order or doc that resolves a review thread,
  reacts to a post, requests a review or dismisses one:
  `git grep -l -i -F` for `resolveReviewThread`, `addReaction`,
  `requestReviews` and `dismissPullRequestReview` over `cmd`, `internal`, `docs`
  and `engdocs` at 994008c628 finds no file.
- **gascity-packs.** The github pack's commands are `comment-issue`, `create-pr`,
  `import-app`, `map-repo`, `push-branch`, `release-workflow`, `status` and
  `sync-app`, none of which answers in a review thread. `mol-pr-iterate`'s step
  text has an agent reply to the one comment it was slung for, with `gh api`
  and `in_reply_to` (lines 554 and 563), and resolves nothing. No pack resolves
  a thread, reacts on GitHub, requests a review or dismisses one: the same
  greps over the repository find `addReaction` only in the Slack adapter.

So the post that answers a round makes them, in `review-run.sh post`, the verb
that already answers the round's rulings in the head's comment. It composes
`pr-post.sh reply`, the pack's one writer of the city's posts, and adds
GitHub's `resolveReviewThread`, `addReaction` and `requestReviews` mutations to
gctk's GitHub adapter beside the mutations it holds
(`markPullRequestReadyForReview`, `convertPullRequestToDraft`, the review
dismissal). The review loop's check cannot hold them. Gas City runs a check
with HOME set to the city's directory and only a whitelist of variables, none
of them a GitHub token (`ConditionEnv.Environ` in
`internal/convergence/condition.go`), so gh has no login there.

## Triage's answer (unit 6)

The need: a round in which triage answers a post that needs only an answer, or
nothing, and closes its ask, with no ruling session working it.

- **Gas City's formulas.** A step bonds one formula from its output: a step
  carries one `OnCompleteSpec`, with one `for_each` and one `bond`
  (`internal/formula` at 994008c628), and the review run's triage bonds its
  lanes with it. A round's steps are made when the round is made, and no step
  is skipped at run time. So the ruling step cannot be bonded from triage's
  output beside the lanes, and it stays in the round, closing at once when
  triage leaves it nothing. Not covered.
- **The pr-review pack** (`gascity-packs/pr-review/formulas`): `mol-adopt-pr`,
  `mol-pr-ci-diagnose`, `mol-pr-iterate`, `mol-pr-merge-only` and
  `mol-pr-revert`. None triages a comment or answers one without working it:
  `mol-pr-iterate` addresses the one comment it is slung for, and
  `mol-pr-ci-diagnose` writes a verdict on CI to its root bead. Not covered.

So triage's output carries a ruling for each ask it answers, read by the pass
rule, the result writer and the head's comment beside the ruling step's, and
triage posts those answers through `review-run.sh post`. No step, formula, bead
kind or key is added: the output gains rulings, the shape the ruling step's
output already has.

## A run behind its own question gates (unit 4)

The need: a person's comment made while a question a review run put to a
person is open reaches a run, which rules it and, when it settles the question,
resolves the gate with the comment as its answer.

A human gate holds the bead it is filed on until it is resolved, and Gas City
reads no PR comment as a gate's answer: no source under `cmd` or `internal` at
76a06b2327 reads a GitHub comment except the webhook receiver, which hands an
order only the rule's arguments. So the landing order, which already decides
when a run pours, pours one behind gates of the run's own question key
(`review-question-<slug>`, filed by `review-run.sh question`) when an ask for a
person's post was filed after them, and the run resolves a gate that post
settles. The person answers a question on the board, as at any other gate. No
gate kind or key is added.

## Red checks (unit 5)

The need: from the saved read, an ask for a required check that failed for a
code cause, one re-run of the failed jobs of a check that failed for another
cause, a gate where the city cannot go on, the gate withdrawn once the checks
pass, and a restart of a required check that never reported.

- **Gas City's PR monitor** cannot tell a required check from the rest, since
  its query reads no `isRequired` (`pullRequestsQuery`). It counts a cancelled
  check as pending: `checkFailed` in `internal/githubmonitor/monitor.go` lists
  `CANCELED`, GitHub's `CheckConclusionState` spells `CANCELLED`, and
  `checkPending` returns true for any other conclusion that is not a success,
  neutral or skip. It marks every PR that GitHub reads BLOCKED actionable with
  the failure kind `blocked` (`classifyPullRequest`), which includes every PR
  waiting on a review. Its repair bead is a writer of its own (above), and it
  copies GitHub's facts onto that bead in `github.*` keys
  (`githubPRRepairVolatileMetadata` in `cmd/gc/cmd_github.go`). Its
  `poll_interval`, `webhook_secret_env`, `webhook_secret_key` and `merge_queue`
  are read only by validation and patches: the readers of each field at
  76a06b2327 are `ValidateGitHubPRMonitors`, `validate_durations.go` and
  `patch.go`, and `WebhookSecretKeyOrDefault` has no caller. Not covered. The
  design's section 4 names each of the three differences, its reason and what
  would end it.
- **A re-run of a workflow's failed jobs.** No source or doc at 994008c628
  re-runs a GitHub Actions run (`rerun-failed-jobs`, `actions/runs/.../rerun`
  and `gh run rerun` find no file). Not covered.
- **bd's GitHub gates,** which core's `gate-sweep` order checks every thirty
  seconds (`internal/bootstrap/packs/core/orders/gate-sweep.toml`). At
  `gastownhall/beads` v1.3.4 (7ef2fd05eb), a `gh:run` gate waits on one
  workflow run, resolving when it completes with success and escalating when it
  completes failed or cancelled, and a `gh:pr` gate waits for a PR to merge
  (`bd gate check`'s help in `cmd/bd/gate.go`). The acts here decide over every
  required check at the PR's head, re-run a non-code failure once, and ask a
  person only for an approved PR, and the saved read holds those checks after
  every move. A `gh:run` gate would hold the PR's bead on one run and escalate
  a failure on any PR, approved or not, so it covers none of the three rules,
  and a `gh:pr` gate waits for what the landing order itself does. Not
  covered.
- **The pr-review pack's `mol-pr-ci-diagnose`** reads a PR's check runs and
  writes a verdict to its root bead's notes, slung by hand for one PR, with no
  re-run and no work filed. Not covered.
- **Moving a PR between draft and ready.** Nothing at 994008c628 converts a PR
  to draft or marks it ready (`convertPullRequestToDraft`,
  `markPullRequestReadyForReview` and `gh pr ready` find no file), as the
  review-lanes search found at 13bb101b8f
  ([its draft cycle](../tk-1tfzr71.108/gas-city-search.md#the-draft-cycle-and-the-withdrawal-unit-2)).
  The restart reuses gctk's `gctk pr draft` mutations. Not covered.

The gates are Gas City's human gates, filed and withdrawn under a situation key
as the landing order's exceptions are, with the keys today's red-check gates
carry and one more for a check that never reports (`pr-check-unreported.<n>`).
The one-PR update's checks read gains each check suite's status, its creation
time and its Actions run's attempt, fields on nodes that read already returns,
so no request is added.

## Conflicts (unit 5)

The need: an ask to merge the target into an approved PR that GitHub reads
conflicting, filed only while no hold set by hand or human gate holds the bead.

- **Gas City's PR monitor** files a repair bead of the failure kind
  `merge_conflict` for a PR GitHub reads DIRTY, routed and poured as above, for
  an approved PR and an unapproved one alike, since it reads no review. Not
  covered.
- **Gas Town's refinery** brings a branch current in its own prep, for a work
  bead it holds (`gastown/formulas/mol-refinery-patrol.toml`), and the merge
  design kept that flow. A PR on the new merge path at its validated head is
  the landing order's, and the review run is its branch's one writer
  ([the review-lanes design, section 1](../tk-1tfzr71.108/design.md#what-pours-it)).
  Not covered.

So a conflict is an ask, as the refinery's own conflict on a bead that owns an
open PR is since the review-lanes effort.

## The webhook (not built)

Nothing is built for it. The route a webhook would take is the github pack's
webhook service (`github/scripts/github_intake_service.py`), whose rule for an
event that names a PR runs `gctk pr refresh` for that PR and then the landing
order, as [tk-1tfzr71.149's search](../tk-1tfzr71.149/gas-city-search.md#the-webhook-a-later-effort-adopts-no-unit)
records. The one-PR update saves a PR's untaken posts with the rest of its
read, so a delivery reaches the take with no change to the intake. Gas City's
own receiver does not fit: a public hook may fire only a formula order, never
an exec order (`routeOrder` in `internal/webhooksink/sink.go`), so each
delivery would wake an agent, and a private or tenant hook answers only a
request from the loopback or one carrying `X-GC-Request`
(`webhookRequestAllowed` in `internal/api/handler_webhook.go`), which GitHub's
delivery does not carry. The design gives a webhook to the operator as an
optimization to take when they decide to
([design, section 5](design.md#5-the-webhook)).

## The owner hop (dropped)

`docs/gctk-architecture.md` lists `gctk pr owner <pr>` for "a GitHub event on an
open PR" taken to the bead that owns it. `gctk pr refresh` finds the bead that
owns the PR it reads
([the landing-order design's section 4](../tk-1tfzr71.149/design.md#4-the-one-pr-updates-read)),
and a webhook's rule calls it, so the verb would have no caller, and the
retirement unit removes its row.
