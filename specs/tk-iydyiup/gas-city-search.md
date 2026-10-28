---
name: Gas City search for the count of review threads waiting on the city's answer
description: The search the arch check asks for before the merge pass records pr.unanswered_threads, how many of a pull request's review threads wait on the city's answer, and pr-post.sh defines which threads do. What Gas City, bd, and the packs Gas City bundles and publishes ship near that need, read at named upstream commits, and why the pack keeps its own key. Read it when checking whether held: review can move onto a Gas City primitive.
---

# Gas City search for the count of review threads waiting on the city's answer

`held: review` names review feedback the city has not answered, on any base and
before an approval as well as after one. To name it, the merge pass reads the
review threads of every open pull request it visits and records on the anchor
how many of them wait on the city's answer, `pr.unanswered_threads`, pinned to
the head it read. Package `prstatus` reads the count, both for the `held:`
labels and for the helm board. `pr-post.sh` defines which threads wait,
`gc_thread_awaits_answer`, beside its definitions of which posts are feedback
and which are the city's own. The count is pack state kept on a bead, so the
arch check asks what Gas City already ships for it
([review-arch.md](../../docs/review-arch.md#the-checks), checks 1 and 2).

Gas City ships nothing that reads a pull request's review threads. Its pull
request readiness monitor reads a PR's draft flag, merge state, head and check
rollup, and records its class on a repair bead it files. A webhook rule hands
one verified event to an order or a conversation and records nothing itself.
bd's example pull request review formula asks the agent running it to look for
unresolved threads and keeps no record of them. No pack that Gas City bundles or
publishes reads whether a thread is resolved or answered. The
`compound-engineering` pack's comment resolver is an agent handed one thread to
fix or answer. So the pack keeps the count, and the warrant *Unanswered review
threads* in [warrants.md](../../docs/warrants.md) says why.

## The surface and the need

The change adds these pieces of surface:

- **`pr.unanswered_threads`, a key on the anchor.** Its value is
  `<count>@<head oid>`, and it is registered in the `[metadata.pr_round_trip]`
  table of `lifecycle/lifecycle.toml`. `gctk merge` writes it
  (`recordUnansweredThreads` in `services/gctk/internal/cli/merge.go`) for every
  open PR the pass visits, whenever the count or the head moves.
- **`gc_thread_awaits_answer`, a definition `pr-post.sh feedback-def` prints.**
  A review thread waits on the city's answer when it is unresolved and the
  newest of its posts that asks or answers is feedback. A post of the city's
  answers every post before it, so a thread the city answered and left open for
  the reviewer does not wait on the city. A post not for review neither asks nor
  answers, and neither does a post a dismissal retired, which the definition
  reads through `live_comments` in `review-dismissal.sh`, so
  `pr-post.sh feedback-def` prints that file's definitions ahead of it.
- **`held: review` reads the count.** `prstatus.Held` holds the PR on a count
  above zero at the head the posture was read at, while nothing is in flight on
  the anchor and no feedback waits for `pr-facts.sh` to route it. The labels
  read the key through `gctk pr-status derive`, and the helm board's phase facts
  read it off the same anchor.

The need is a fact kept on the bead whose pull request it is, pinned to a head,
that says whether the PR carries review feedback no answer of the city's follows,
on any base and whatever its approval. A derivation that does no I/O has to be
able to name it, and the label and the board have to read the one fact.

## Where the search looked

- `gastownhall/gascity` main 221b1476dc10, read 2026-10-28, and the `gastown`
  pack it bundles at 66c672b5ed00 (`PublicGastownPackVersion` in
  `internal/config/public_packs.go`).
- `gastownhall/gascity-packs` main dac12a4a802c.
- `gastownhall/beads` main 5011528b3ad5.
- The published references at docs.gascity.com: *GitHubPRMonitor* and
  *WebhookRule* in the configuration reference, and *gc github pr backfill* in
  the CLI reference.

The terms searched, over Go sources, documentation, formulas, prompts and
skills: `reviewThreads`, `isResolved`, `resolveReviewThread`, `review_thread`,
`pull_request_review`, `unresolved`, `reviewDecision` and `latestReviews`.

## What Gas City ships near the need

### The pull request readiness monitor

Gas City's pull request readiness monitor, in the `gc` binary, reads a city's
open pull requests. A city declares it as a `[[github.pr_monitor]]` entry
([GitHubPRMonitor](https://docs.gascity.com/reference/config#githubprmonitor)),
and [`gc github pr backfill`](https://docs.gascity.com/reference/cli#gc-github-pr-backfill)
runs it. Its query, `GasCityPRReadiness` (`pullRequestsQuery` in package
`githubmonitor`), reads each open PR's number, title, url, author, draft flag,
merge state, base and head refs, head oid, and its last commit's check rollup.
`classifyPullRequest` decides the PR's class from those alone. No Gas City
source under `cmd/`, `internal/` or `examples/`, tests aside, reads a pull
request's reviews, review threads or review comments: none names
`reviewThreads`, `pullRequestReview`, `reviewDecision`, `latestReviews`, or a
`pulls/<n>/reviews` or `pulls/<n>/comments` path. The monitor records its class
on a repair bead it files (`ensureGitHubPRRepairBead` in the `gc` command's
source), not on the bead whose pull request it is.

The monitor does not cover the need: it never reads a thread, so it cannot say
whether feedback waits on an answer.

### Webhook rules

A webhook rule "maps one verified provider event to a dispatch target"
([WebhookRule](https://docs.gascity.com/reference/config#webhookrule)). It
names the provider's event type, an exact-equality match over the payload, and
an order to dispatch with arguments projected from the payload, or a
conversation. The rule keeps no state. A pack could route GitHub's review
thread events to an order of its own, but that order would still keep the
thread's state on a key of its own. So a webhook would change when the count is
read, not where it is kept.

### bd

Outside its maintainers' guide and its code comments, bd mentions review
threads in one place, the example formula `gh-pr-review`
(`examples/formulas/gh-pr-review.formula.toml`). It tells the agent running it,
in prose, to check for unresolved review threads, and to treat substantive ones
as a reason to review the PR more deeply. The formula reads the PR's reviews
endpoint and records nothing about its threads.

### The published packs

No pack in `gastownhall/gascity-packs` main, or in the `gastown` pin Gas City
bundles, reads whether a review thread is resolved or answered. The
`compound-engineering` pack's `ce-pr-comment-resolver` agent is handed one
review thread, or one file's related threads, to fix or answer. It returns a
verdict and the reply text to the skill that spawned it, and keeps no record a
reader keys on.

## What the change does with it

The pack keeps the count. The merge pass records it because the pass already
reads review threads where a base requires their resolution, and already visits
every open pull request on the cadence. `pr-post.sh` defines which threads wait,
because it already owns the rule for which posts are feedback and which are the
city's own. The count is a key on the anchor beside the machine axis, read by
the one derivation the labels and the board share, so it carries the warrant
*Unanswered review threads*. That warrant retires when Gas City records a pull
request's review-thread state where a reader of the PR's own bead finds it, for
example once its readiness monitor reads review threads, or once a webhook
receiver keeps that state from GitHub's review thread events.
