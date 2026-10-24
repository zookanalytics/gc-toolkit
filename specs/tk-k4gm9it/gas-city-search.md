---
name: Gas City search for comments not for review
description: The search the arch check asks for before the pack adds surface of its own. What Gas City, the packs it publishes and bd ship for telling a pull request's informational comments from its feedback, read at named upstream commits, and why none of it covers the definitions, verb and rig file this change adds. Read it when checking whether the pack still needs its own rule.
---

# Gas City search for comments not for review

This change adds pack surface that decides which pull-request comments are
feedback, so the arch check asks what Gas City already ships for that need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1). Nothing Gas
City ships gives a script a rule for which of a pull request's comments are
feedback, and nothing lets a comment's author or a rig take an informational
comment out of feedback. Two published packs have a model weigh comments, each
inside a review of its own. The rule stays in the pack's own definition of
feedback, the one its readers already share.

## The surface and the need

- `feedback-def` in [`pr-post.sh`](../../assets/scripts/pr-post.sh) prints the
  definitions of the city's own post that `own-def` prints, with
  `gc_not_for_review` and `gc_feedback`. Every reader that asks whether a post
  is feedback asks `gc_feedback`.
- `pr-post.sh not-for-review` prints the no-review mark and each prefix the rig
  declares.
- `not-for-review.toml` at the root of a rig's repository declares how the
  comments of an integration the rig installs begin
  ([not-for-review.md](../../docs/not-for-review.md)).

The need is one answer, shared by every reader, to whether a review body, an
inline comment or a conversation comment asks anything of the city. A comment's
author says it does not by opening it with the mark. A rig says it for an
integration by declaring the text that integration's comments begin with.

## Where the search looked

All three were read on 2026-10-23:

- Gas City at main `ba3ed611de71`: its documentation, its engineering docs, the
  `core` pack it bundles, and its source.
- Every pack Gas City publishes, at `5a1c7004b250`. Each was searched for the
  terms below, and each part the search found was read.
- bd at main `ce8554ffb1bb`.

The search covered pull-request comments, reviews and review threads, comment
authors and bot accounts, markers and prefixes in a comment body, and GitHub's
comment and review events.

## What Gas City ships near the need

### The pull-request readiness monitor

`[[github.pr_monitor]]`
([configuration reference, GitHubPRMonitor](https://docs.gascity.com/reference/config#githubprmonitor))
names a repository and the base branches to watch.
[`gc github pr backfill`](https://docs.gascity.com/reference/cli#gc-github-pr-backfill)
reports the open pull requests that need repair: failed checks, merge
conflicts, blocked mergeability, or a branch behind its base. The
`githubmonitor` package's `pullRequestsQuery` reads each open pull request's
number, title, URL, author, draft flag, merge state, branches, head commit and
the checks on its last commit. It reads no review and no comment. Its `authors`
field is an allow-list of pull-request authors, not of comment authors. The
monitor never sees feedback, so it has nothing to classify a comment with.

### Inbound webhooks

`[[webhook]]` and its rules
([configuration reference, WebhookRule](https://docs.gascity.com/reference/config#webhookrule))
map one verified provider event to an order or a conversation. A rule's `match`
compares dotted paths in the payload. The configuration reference calls it an
exact-equality predicate, and the source matches more: the `webhookmatch`
package's `valueMatches` takes `*` as presence, a trailing `*` as a literal
prefix, and any other value as exact equality. So a rule can select an
`issue_comment` delivery whose body begins with a given text.

That decides what one delivery dispatches. It is not an answer a reader can ask
for. The pack reads a pull request's reviews, inline comments and conversation
comments through GitHub's API on each pass, and each reader asks of every one
whether it is feedback. The readers are pr-facts.sh, approval-withdraw.sh and
feedback-miner.sh, and the review-dismissal.sh and review-answer.sh rules
sourced into them. No webhook delivery reaches any of them. A rule's prefix is
also compared from the body's first character, while the mark counts anywhere
among the HTML comments a body opens with. A report that opens with its own
marker comment and carries the mark on the next line, the form
not-for-review.md shows, is not a body that begins with the mark.

### A value set for one rig

Three places in Gas City's configuration can carry a value for one rig. A rig's
`formula_vars` ([Rig](https://docs.gascity.com/reference/config#rig)) give a
formula's declared vars their defaults when the formula runs in that rig. The
`env` of a rig's agent `patches`
([AgentOverride](https://docs.gascity.com/reference/config#agentoverride))
reaches that agent's sessions. The `env` of an order override scoped to the rig
([OrderOverride](https://docs.gascity.com/reference/config#orderoverride))
reaches that exec order's script, which runs with no agent
([Tutorial 07, formula orders vs. exec orders](https://docs.gascity.com/tutorials/07-orders#formula-orders-vs-exec-orders)).

Each place reaches only its own callers, and the readers have callers of more
than one kind. pr-facts.sh runs in the `refinery-reconcile` exec order, where
no agent and no formula runs. approval-withdraw.sh and feedback-miner.sh run in
formula steps, `mol-validate`'s and `mol-feedback-miner`'s, in the sessions of
the agents that claim them. A declaration in the city's configuration would be
written for each kind of caller and kept equal by hand. A caller without it
would read the rig as declaring nothing, and no error would say so. That is the
drift a single definition in `pr-post.sh` exists to prevent. These values also
belong to the city's configuration, while the integration belongs to the rig's
repository. pr-post.sh reads not-for-review.toml itself whenever a reader asks
for `feedback-def`, so no caller has to carry the prefixes.

### The packs Gas City publishes

- `github` takes GitHub App webhooks for comments addressed to an agent and for
  `/gc fix` commands on issues. Its intake service drops an addressed comment
  that the app itself, an account whose `user.type` is Bot, or a login ending
  in `[bot]` wrote (`comment_from_bot`). Its event rules (`rule_matches`)
  compare payload paths by exact equality. The filter answers whether a comment
  is a command for the city, by who wrote it. The need here turns on what the
  comment says, because a review bot's comment can be real feedback. That is why
  the operator chose, on 2026-10-23, a mark the comment's author writes over an
  author filter. The pack has no such mark and no prefix a rig declares.
- `pr-review`'s `mol-pr-iterate` acts on one feedback source its caller names:
  a coverage report, Copilot's review comments picked by login, one review
  comment by id, or text. It never decides which of a pull request's comments
  are feedback.
- `pr-pipeline` plans a change, maps its blast radius, scores an outgoing pull
  request and gates the push. It reads an issue's comments only as context.
- `gastown` reads a pull request's state, branches and merge commit with
  `gh pr view`, in its refinery patrol and its merge reconcile, and reads no
  comment.
- `gascity`, the base pack the methodology packs build on, carries GitHub
  workflows that triage an issue, fix one and review a pull request. Its
  snapshot (`pr_snapshot`) reads a pull request's own fields, such as its
  title, body, author, head and base, and no comment. Each workflow posts one
  comment of its own, opened by a hidden HTML comment that names the workflow,
  such as `<!-- gc:github-pr-review head_sha=<sha> outcome=<outcome> -->`
  (`render_pr_review_comment`). It keeps that comment's id in the workflow's
  metadata to update it, and nothing in the pack reads such a marker back.
- `compound-engineering`'s `compound-code-review` adds a previous-comments lane
  when a pull request already has reviews or comments. Its persona,
  `ce-previous-comments-reviewer`, fetches them, and a model judges which asked
  for a change the diff has not made. It passes over questions and
  acknowledgments, comments on code since removed, the author's notes to
  themselves, and nits the author chose not to take. The pack's
  `ce-pr-comment-resolver` judges each review thread it is handed on its
  merits, whether a person or a review bot wrote it.
- `gstack`'s `review` skill has a model classify the review comments of one
  bot, Greptile, as actionable, already fixed, false positive or suppressed. It
  follows a triage file that it expects among the installed Claude skills and
  that the pack does not ship.
- `superpowers`' `receiving-code-review` skill and `contributing-to-gascity`'s
  `fine-tune` skill tell an agent how to weigh review feedback once it arrives.
  Neither picks which comments are feedback. `bmad`'s code review resolves a
  pull request to its branch and reads no comment.
- The bundled `core` pack handles no pull-request comment. Its
  `mol-review-quorum` reviews a diff in read-only lanes.

Two of these weigh a pull request's comments: compound-engineering's
previous-comments lane and gstack's review skill. Each is a model's judgment,
written as a prompt and made inside one review for that review's own findings.
The pack's readers are scripts that need one answer they all share, and no
script can ask a prompt for it. Neither pack offers a mark a comment's author
writes or a prefix a rig declares.

### bd

`bd github` syncs issues between beads and GitHub, and skips pull requests. The
`gh:pr` gate (`checkGHPRWithRunner`) reads a pull request's state and title.
Neither reads a pull request's comments.

## Result

Nothing in Gas City, the packs it publishes or bd gives a script a rule for
which of a pull request's comments are feedback. The two packs that weigh
comments do it by a model's judgment inside a review of their own. None of
them offers a mark that takes a comment out of feedback, or a place for a rig to
declare one. The pack's feedback readers are its own, and this change extends
the one definition they share in `pr-post.sh` rather than adding a second. The
change adds no pack noun and no converter. If Gas City ships a reader of
pull-request feedback, the rule belongs in that reader, and the pack's
definition moves onto it.
