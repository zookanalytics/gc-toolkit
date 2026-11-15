---
name: Design — a PR's status derived by one rule from the GitHub read the landing order saves
description: The design for tk-1tfzr71.134, the design child of initiative tk-1tfzr71.132, read at 7559e1bbd and against Gas City upstream main a1eb65702f, gascity-packs main 0f07496d2f and bd v1.3.4. It splits the pr evaluator's rule from its reads, has the landing order save its GitHub read of each PR on the PR's bead at every check, has the rig board, the label and gctk pr status run the one rule over that read and the store, keeps the merge on a fresh read, leaves the label's writer on the pending record to tk-1tfzr71.149, plans the merge with the review-lanes effort, and defines the units the implementation child files. Read it to approve the design at its gate, or to build one of its units.
---

# Design: a PR's status derived by one rule from the GitHub read the landing order saves

This is the design record for tk-1tfzr71.134, the design child of the
initiative tk-1tfzr71.132. The pack was read at 7559e1bbd, the commit
`integration/tk-1tfzr71.132` was cut from, which reads the same as main
9bf87b112 in every file cited here, and the review-lanes effort was read at
`integration/tk-1tfzr71.22` 412222905. Gas City is cited by symbol at
`gastownhall/gascity` main a1eb65702f, Gas Town by path at
`gastownhall/gascity-packs` main 0f07496d2f, and bd at `gastownhall/beads`
v1.3.4 (7ef2fd05eb0c), the build the city runs. The target is the one the
operator approved in conversation tk-63pl91v on 2026-11-15, which the
initiative's description records with the operator's words. The search behind
the surface the units add is [gas-city-search.md](gas-city-search.md).

## What the operator approves

Today the status label and `gctk pr status` read GitHub every time they derive
the status of a PR on Gas Town's pending record, at least five GraphQL queries
and one REST call each, and the rig board derives the same PR by another rule
from keys the old path writes, so the board and the label can disagree. You
ruled that
the board should not read GitHub: "It should use the state that is recorded and
the general process should keep those up to date at whatever cadence they do."
You then approved the target in which the label and `gctk pr status` do the
same: "Go as recommended."

Approving this design builds that target. Each time the landing order checks a
PR, it saves what it read of GitHub on the PR's bead: the PR's state, draft
flag, head and merge state, the required checks at that head, who approved or
asked for changes, the newest feedback in each comment space and the review
threads waiting on the city, with the head and the time of the read. The rig
board, the status label and `gctk pr status` derive the PR's status from that
read and the city's own records by the one rule the merge uses, so the three
give one answer.

- A change on GitHub, such as your approval, shows at the PR's next check, which
  comes within the landing order's cycle, the pace you accepted.
- A change in the city, such as a gate you answer or a hold you set, shows at
  once on the board and in `gctk pr status`.
- The label takes the same answer when one of its writers sets it: at once
  where the writer that made a change sets the label, as a review verdict does
  today, and otherwise when the old GitHub intake's full pass next reaches the
  PR (`pr-facts.sh`), which keeps reconciling an open PR's label until
  tk-1tfzr71.21 retires it.
- The merge still reads GitHub fresh in its own run, and never acts on what was
  saved.

**What it leaves open.** A PR the refinery publishes at a head the landing order
has not read, such as a new PR, reads `working`, with GitHub's side named as not
yet read, until the landing order's next check. The agents' board
(`helm-svc board`) keeps its own rule until the board member replaces its
reader. A PR still on the old path shows what the old path records, as today.
Every rig's move onto the pending record waits on this work, so the first PRs it
shows are the ones those moves bring.

**The label's writer on the pending record is tk-1tfzr71.149's.** This work
changes no writer of the label (section 5). When a PR on the pending record
merges or closes, or its bead meets an exception and waits on a person, nothing
writes the PR's labels, so it keeps the ones it had, such as
`status: merging`, until tk-1tfzr71.149's label step lands. Its target corrects
a PR's labels by comparing what GitHub shows with what the store derives, so
the landing order makes no label call and nothing records one that failed. You
chose that approach in conversation tk-y9h5lbd. As it was put to you: "Until
its label step lands, a PR on the new path that merges, closes or goes to a
person keeps its last label, and that step then corrects it." (the ruling's
note on tk-1tfzr71.132)

## 1. The rule and its reads

`pr.Ready` (`services/gctk/pr/pr.go`) reads the store and GitHub and decides in
one function. Its parts, by what each reads:

| Part | Reads | Kind of work |
|---|---|---|
| what the record lacks (`recordGaps`) | the store | pure |
| the holds set by hand | the store | pure |
| the bead's own waits (`ownWaits`) and the beads anchored to it (`anchoredTo`) | the store, through `waits` and the ledger | a read, then a mapping |
| identity, state, draft, head and merge state (`identityGaps` and the checks beside it) | GitHub's PR, against the record | pure over the read |
| the required checks (`checks`) | GitHub's check suites at the head | pure over the read |
| the approval (`approval`) | GitHub's reviews | pure over the read |
| the review result (`passedAt`) | the store's results, at GitHub's head and base | pure |
| feedback the intake has not handled (`unhandled`) | GitHub's reviews, threads and comments, the definition of feedback, the store's receipts | the definition through the shell, then a compare |
| threads waiting on the city (`awaiting`) | GitHub's threads, the definition of feedback | the definition through the shell |

The design splits these into two reads and one rule.

- **The bead's side** is what the store holds about the bead at the read: the
  record, the branch, the holds, the feedback receipts, the provenance instant,
  the review results, and the conditions of its own waits and of the beads
  anchored to it. It is read through a ledger pass, as `Ready` reads it today.
- **The GitHub read** (`GitHubRead`) is GitHub's side of the PR at one head,
  reduced to what the rule reads (section 2). `observe` makes it live, through
  `pr.GitHub` and the definition of feedback, with the reads `Ready` makes
  today and in their order.
- **The rule** is `decide(bead, read)`, which returns the `Answer` and reads
  nothing. Its helpers are today's: `recordGaps`, `identityGaps`, `checks`,
  `passedAt`, and the compare of the newest feedback with the receipts that
  `unhandled` makes through `newest`. When the read is absent or not current
  (section 2), `decide` names one condition of kind `github-unread` in place of
  every condition of GitHub's.

Two functions compose them, and every caller asks one of the two:

- **`pr.Ready(src, bead)`** reads the bead's side, observes GitHub live and
  decides, and returns the answer with the GitHub read it made. It is the
  merge's question, and only the landing order asks it: at a check of a PR open
  at its validated head, it saves the read and acts on the answer (section 6).
  At a check of a PR already in its base's merge queue, and at a requeue, where
  it decides nothing, it observes alone.
- **`pr.FromStore(l, bead)`** reads the bead's side and the GitHub read the
  landing order saved, and decides. It is every display's question. It reads no
  GitHub and loads no definition of feedback.

So the merge and every display run one `decide`, and their answers list the
same conditions in the same order. A bead whose record lacks a part gets the
store's conditions alone from both, as it does from `Ready` today, which reads
no GitHub for it.

Two of today's helpers run at the read, which keeps what they find, and a third
takes the read's form of its input:

- **The definition of feedback** runs through `pr-post.sh feedback-def` and jq
  (the feedback adapter, [gctk-architecture.md](../../docs/gctk-architecture.md#debt)),
  and reads the text of every post, which the saved read does not keep, so no
  display can run it. `observe` applies it, as `Ready` does today, and the read
  keeps what it found: the highest feedback id in each id space, a review
  counted only as the intake counts it (a commenting or changes-requesting
  review with a message), and the ids of the threads waiting on the city's
  answer. The compare with the receipts
  stays in `decide`, because the receipts are the store's and move when the
  intake routes feedback. `newest(ids, floor, only)` returns the highest id that
  `only` admits when that id is above `floor`, and 0 otherwise, so a compare of
  the saved highest with the floor names the same condition with the same id.
- **`approval`** reads GitHub's reviews alone, so its result is GitHub's, and
  the read keeps the approvers and the change-requesters it finds in place of
  every review.
- **`checks`** keeps running in `decide`, over the required check runs the read
  keeps. It reads each suite only to collect each required run's results by its
  name, so a list of the required runs at the head gives the same conditions.

The test that holds the rule to one is the evaluator's own suite run twice.
Every case of `ready_test.go` that answers asks `Ready` over the fake GitHub,
saves the read `Ready` returns on the bead, asks `FromStore`, and requires the
same answer.

## 2. The GitHub read, saved on the PR's bead

**Where it lives.** One key, `pr_github_read`, on the bead that owns the PR,
the bead that carries the pending record. It holds one JSON object, declared
by the pr domain through the ledger's JSON codec, as `review_results` is. Its
one writer is the landing order (section 3).

| Field | What it holds |
|---|---|
| `read_at` | when the check read GitHub, RFC 3339 UTC to the second, the stamp the record's writes take |
| `since` | the provenance instant the definition of feedback was applied with, `pr_provenance_since` as the check read it |
| `url`, `number`, `repository`, `head_branch`, `base` | the PR's identity as GitHub reports it |
| `head` | the PR's head commit (`headRefOid`) |
| `state`, `draft`, `merge_state` | `state`, `isDraft` and `mergeStateStatus` |
| `checks` | each required check run at `head`, as `{name, status, conclusion}`, from each suite's latest results |
| `approvers`, `requesters` | the accounts that can push whose approval, or whose request for changes, stands |
| `feedback` | `{review, inline, conversation}`, the highest feedback id in each space, 0 where there is none |
| `awaiting` | the ids of the review threads waiting on the city's answer |

It holds no answer, no condition and no readiness. The record keeps its own
keys, `pr_state` and `pr_last_checked_at` among them.

**When a read is current.** A reader takes the saved read as current for the
bead when all three hold:

1. It names the PR the record names: its repository, compared without case,
   and its number are the record's `pr_repo` and `pr_number`.
2. Its head is the head the store holds for the PR: `observed_pr_head_sha` when
   the record reads `pull_request_head_changed`, and `pr_head_sha` otherwise.
3. Its `since` is the bead's `pr_provenance_since`.

The second test is where a reader learns the PR's own head without reading
GitHub. Both keys are Gas Town's record. The refinery's publication writes
`pr_head_sha`, the head it validated and pushed, and clears
`observed_pr_head_sha`. The landing order's requeue writes
`observed_pr_head_sha`, the head it found. So a head the refinery publishes
makes the saved read older than the PR's head until the next check, unless the
landing order's requeue read the PR at that head. A head the landing order found
open stays the PR's head until the refinery publishes again. The third test
covers the instant `pr-facts.sh` stamps once, the first time it reads a PR,
which a read made before the stamp did not apply.

**A read that is not current, or none.** `decide` then names one condition,
`github-unread`, saying that the landing order has not read the PR on GitHub at
the head the store holds, and no condition of GitHub's. The store's conditions
stand as at any read: a gate, a hold, a wait, a bead anchored to it, or a record
that lacks a part. Its `Head` and `Target` are empty, because it judged no head
of GitHub's. Section 4 says what each display shows for it.

## 3. The writer: the landing order's check

At each check that finds the PR open, the landing order reads GitHub's side
whole, through `Ready` at the validated head, and through `observe` alone for a
PR in its base's merge queue and at a requeue. It saves the read in the same
guarded write that records the check, so one act stays one write:

| The check finds | It writes |
|---|---|
| the PR open at the validated head, not ready | `record.Checked` and the read |
| the PR ready | the merge or enqueue request on the answer `Ready` gave over the read it just made (section 6), then `record.Checked` and the read |
| the PR ready, and GitHub refuses the request or does not answer it | `record.Retry` with why, and the read |
| the PR in its base's merge queue | `record.Checked` and the read, and no request |
| the PR open at another head | the requeue and the read made at the head it found |

The order of the reads is today's. The run's read of the PR comes first, then
the check suites at the PR's head, the reviews, the city's login (once for each
host in a run), the review threads and the conversation comments, with the
definition of feedback loaded once in a run. A check of a PR open at its
validated head and outside the merge queue makes the reads it makes today. A
check of a PR in the queue and a requeue also read the rest of GitHub's side,
where today each reads only the PR, so the board shows the rule over a queued
PR's facts and at the head the refinery has yet to validate.

**A read that fails partway.** The read is saved whole or not at all, so
`decide` never runs on part of the facts, and no reader finds a read with a
field missing. A read that fails after the PR's own read writes the retry as
today (`record.Retry`: `pr_state`, `pr_last_checked_at` and
`pr_reconcile_error`) and leaves `pr_github_read` as the last whole check left
it. A reader then derives from that read for as long as it is current by
section 2's test. The read carries its `read_at`, and `pr_reconcile_error` says
why the last check did not finish. A failed read of the PR itself leaves both
in the same way.

**What saves no read.** A PR that merged or closed, an exception, a released
bead and a record that lacks a part save none, because the bead leaves the
record or the run reads no PR. A read left on a bead that leaves the record is
read by nobody, since the rule runs only for a bead on the record, and the next
round's first check replaces it. The publication clears nothing of it, because
section 2's test already reads it as older than the new head.

## 4. The readers

Each display runs `pr.FromStore` for a bead whose `merge_result` is on the
record (`pr.OnRecord`), and renders its answer through `prstatus`:

- **`gctk pr status <bead>`** (`services/gctk/internal/cli/prstatus.go`) asks
  `pr.FromStore` over the ledger in place of `pr.Ready`, so it needs neither gh
  nor the definition of feedback. It prints `prstatus.Render` over the answer
  and the facts `prstatus.Read` gathers, with each condition not met, as today.
  Its `--json` keeps its keys, with `head` and `target` the saved read's when it
  is current. Its exit 2 stays for a read of the store that did not resolve.
- **The status label** (`assets/scripts/pr-status-label.sh`) is unchanged. Its
  `reconcile` derives through `gctk pr status --json`, so it shows the answer
  `gctk pr status` gives.
- **The rig board** (`services/helm/internal/rigboard`) asks the listing for the
  answer of each anchor on the record. `Listing.PRAnswers(ids)` runs
  `pr.FromStore` over the listing's own pass, so the board reads no row twice and
  nothing outside the store. An anchor whose answer did not read, because a read
  of the store failed, reads unread, as an anchor `prstatus.Read` cannot answer
  for does today.

The board takes the two pieces carried from PR #1509, whose head GitHub keeps
at `refs/pull/1509/head` (8b5f3f3e8413):

- **`prFacts`** (`gather.go` on that branch) renders a row's state, held values
  and reasons through `prstatus.Render`, `RenderHeld` and `RenderReasons` when
  the row has the evaluator's answer, and through `Derive`, `Held` and
  `Reasons` otherwise. `table.go`'s row 6, `askOf`, `pullRequestOf` and
  `reasonsOf` read them through it. Its answer comes from `PRAnswers`, in place
  of the branch's `listing.Ready`, which read GitHub through gh's cache at up to
  five minutes old (`gitHubMaxAge`).
- **`table.go`'s row 5** reads the `blocked` status the record writes on a bead
  it holds as the record's own, which holds nothing, so such a PR reads "Pull
  request #n" with where it stands, in the work queue.

Nothing else of #1509 is carried. `listing.Ready`, `gitHubMaxAge`, the gh
adapter's `Cached` and `NewContext`, and the feedback adapter's context-bound
loads served a board that reads GitHub, and this board reads neither GitHub nor
the definition of feedback.

**What `prstatus.Render` reads in a `github-unread` condition.** It gains one
case: a `github-unread` condition reads `working` unless something only a person
clears holds the PR, which reads `needs-attention` as today. The next move is
the landing order's check, and no approval is known. Without the case, an
answer with no condition of GitHub's would fall to Render's arm for a PR with
no approval condition and read `merging`. `RenderReasons` needs no change: an
unread side names no thread.

**A change in the city shows at once.** Each read runs `FromStore` over the
store as it is then, so a gate the operator answers, a hold set or lifted, a
review result recorded, feedback the intake routes, and a rework's new head all
show at the next render of the board and the next call of `gctk pr status`.

## 5. The label's writers

This work changes no writer of the `status:` and `held:` labels, and the
landing order writes none. `pr-open.sh` and `signoff.sh` keep setting the
labels when they change one of their inputs. `pr-facts.sh`'s full pass keeps
reconciling each open PR's labels, a PR on the pending record among them, until
tk-1tfzr71.21 retires the script, and `gctk merge` keeps clearing them on the
old path until tk-1tfzr71.70 retires it. Each derives through
`gctk pr status`, so for a PR on the pending record each writes what the rule
gives over the saved read and the store (section 4).

Nothing writes the labels of a PR on the pending record when it merges or
closes, or when its bead meets an exception. `pr-facts.sh` leaves a merged or
closed PR on the record to the landing order, and its walk reaches no bead an
exception holds, since on the record it lists only `pull_request_pending` and
`pull_request_head_changed`. Such a PR keeps the labels it had until
tk-1tfzr71.149's label step lands. The bead for the labels a merged or closed
PR keeps (tk-1tfzr71.91) and the one for the PR of work a person stands down at
an exception (tk-1tfzr71.140) wait on tk-1tfzr71.149.

## 6. The merge acts only on a fresh read

- **The answer it acts on is made in its own run.** The landing order's
  decision asks `Ready` about the PR it read in that run, and asks GitHub to
  merge, or to enqueue, pinned to the head that answer judged (`expectedHeadOid`
  of `mergePullRequest` and `enqueuePullRequest`, `mergeMutation` in
  `services/gctk/internal/gh/gh.go`). It reads the bead once more just before
  the request, as today.
- **Nothing in the merge's path reads the saved read.** The read is written
  after the request, in the check's write, and no code in the landing order
  calls `FromStore`. Unit 1's tests hold it: a bead whose saved read is ready
  while GitHub's live facts hold the PR gets no request, and one whose saved read
  holds the PR while the live facts are ready gets the request.
- **The saved read grants nothing.** Every reader of it displays it. A
  display's `merging` authorizes nothing, as the merge design's section 4 says.
  The readiness answer is computed at each read and stored nowhere, and what is
  stored is GitHub's facts, which no reader acts on.

## 7. What the design restates

This change restates the text in the files at its base:

- **`docs/architecture.md`.** The decision that the board and the merge read the
  evaluator's answer, computed at each read and stored nowhere, becomes two:
  no display reads GitHub, and only the merge acts on a fresh read, with the
  saved read granting nothing. The boundary's diagram shows the landing order
  writing the saved read, and its legend names the order as the saved read's
  one writer. Debt drops the cutover's wait on the board's phase by
  the evaluator's answer (tk-1tfzr71.88, retired), and names the agents' board,
  which keeps its own rule until tk-1tfzr71.24.
- **`docs/built-once-target.md`.** The merge section's sentence on the one
  evaluator that the board and the merge read says the merge runs it on a fresh
  read and every display on the saved read.
- **The merge design (`specs/tk-1tfzr71.66/design.md`).** Section 4's paragraph
  on what the label and the board render, and section 6's rows for the board and
  the status label and for the PR-finishing rank. "Stored nowhere" stays for the
  readiness answer, and the text adds that what is saved is GitHub's facts,
  which grant nothing.

Other work carries the rest:

- **tk-1tfzr71.21's Done** reads: "Review feedback, red checks and conflicts
  reach work through native intake. One writer, the landing order, saves one
  GitHub read per PR, and nothing else mirrors GitHub state into bead metadata."
  The sitting's note on tk-1tfzr71.21 already states the change, and the
  implementation child writes it into the description (section 12).
- **The review-lanes design** (`specs/tk-1tfzr71.108/design.md` on
  `integration/tk-1tfzr71.22`), section 9's rows for `prstatus` and the status
  label and for the board, read: the evaluator's rule over the GitHub read the
  landing order saves and the store, with the run's state in the `review`
  condition. The file reaches this branch only once that effort lands on main,
  so whichever of the two lands second edits the rows (section 8).
- **`docs/gctk-architecture.md`'s rows** for `gctk pr status` and
  `gctk pr reconcile`, and `services/gctk/README.md`, state each verb as built,
  so the unit that changes the verb restates its row (section 11). The page's
  paragraph on what the pr noun owns gains the saved read, in unit 1.

## 8. The overlap with the review-lanes effort

`integration/tk-1tfzr71.22` at 412222905 changes these of this work's files:

- `pr.go` reads the review results through `review.Results` and the branch
  through `record.Branch`, and `ready_keys.go` gives up both declarations.
- `feedback.go` gains `unrouted`, the withdrawal's reading of the inline
  comments that the reviews it dismisses carry.
- `landing.go`'s `state` gains the bead's row, its open withdrawals and the
  review runs attached to it. `open` and `blocked` carry a withdrawal out before
  they requeue or decide, and `decide` marks a draft ready when a passed result
  names its head, and carries the withdrawal's note on every outcome.
- `record.Requeue` keeps the marker while a withdrawal is open, and the record
  gains `Mark` and `Branch`.
- `gh.go` gains the draft transitions, the compare and the review dismissal.
- The cli's `prland.go` and `prstatus.go`, and `docs/architecture.md`'s
  boundary, flow step 7 and review table.
- The `gctk pr reconcile` rows of `docs/gctk-architecture.md` and
  `services/gctk/README.md`, and that page's paragraph on what the pr noun
  owns, which gains the branch and the withdrawal. `key-registry.json`, which
  is generated from the declarations, gains that effort's keys.

Its unit 4 (tk-1tfzr71.128, in flight at this reading, with its branch not yet
on origin) has the landing order pour the review run, and has `prstatus` render
the run's state in the `review` condition.

Each unit of this work builds on `integration/tk-1tfzr71.132` brought current
with main as main stands when the unit starts. When the review-lanes effort has
landed by then, the unit builds on its lines. Otherwise the unit builds beside
them, and whichever lands second composes the two as follows:

- **A check's order in `blocked` and `decide`.** The review-lanes acts come
  first: the withdrawal's carry, which can dismiss approvals, so GitHub's side
  is read after it and the read keeps only the approvals that still stand; then
  the pour of a review run. The read of GitHub's side comes before the draft's
  ready transition, and every write those paths make (checked, readied,
  requested, a refused request's retry, requeued) carries the read. A draft the
  landing order marks ready is saved as a draft until its next check.
- **The bead's side** reads the results and the branch through
  `review.Results` and `record.Branch` once that effort is in.
- **`feedback.go`.** That effort's `unrouted` reads the live threads in the
  withdrawal's carry and stays as it is, beside this work's split of
  `unhandled`.
- **`gh.go`.** Both add to the queries and the mutations beside `pullQuery`, and
  each keeps the other's.
- **`prstatus/render.go`.** That effort's unit 4 adds the run's state to the
  `review` condition, and this work adds the `github-unread` case. Both stand,
  since an unread side names no `review` condition.
- **`docs/architecture.md`.** The diagram keeps that effort's edge from the
  landing order to the review run, and its edge to the PR, "ready, merge
  request". Its edge to the ledger reads "record, GitHub read, then close".
  The legend keeps both additions: the saved read beside the landing order's
  merges, and a PR's review run as the writer of the PR's review result.
- **`docs/gctk-architecture.md`, `services/gctk/README.md` and
  `key-registry.json`.** The `gctk pr reconcile` rows name both efforts' acts,
  the pr noun's paragraph names the branch, the withdrawal and the saved read,
  and the registry is generated again from both efforts' declarations.
- **`specs/tk-1tfzr71.108/design.md`.** Its section 9 rows take section 7's
  text, in whichever effort lands second.

## 9. The PRs not on the pending record

A PR on the old path, whose bead reads `merge_result=pull_request`, shows as
today on the rig board, on its label and in `gctk pr status`: `prstatus.Derive`
over the keys `pr-facts.sh` and `gctk merge` write, `pr_posture`, `pr.machine`
with its cause and sentence, `pr.unanswered_threads`, and the draft markers.
Those keys are recorded state, so no display reads GitHub for such a PR either.
This work changes neither script and no key they write, under AGENTS.md's rule
for code the deletion plan retires: `pr-facts.sh` is tk-1tfzr71.21's to retire,
and `gctk merge` is tk-1tfzr71.70's. A rig's PRs move onto the rule when its
move onto the pending record lands (tk-1tfzr71.78 and .80 to .84), and each of
those moves waits on this work. One bead is never read both ways, because the
rule runs only for a value `pr.OnRecord` names.

## 10. The Gas City search

The surface this work adds is the key `pr_github_read` and the condition kind
`github-unread` in `gctk pr status`'s output.
[gas-city-search.md](gas-city-search.md) records the search at a1eb65702f.
Gas City's PR monitor saves GitHub facts only on the repair beads it files for
a PR it reads as broken, and reads no review, thread or required check. Gas
Town's record holds no review or check state. bd's GitHub sync writes issues.
Upstream's own dashboard reads no GitHub.

## 11. The units

Each unit lands on `integration/tk-1tfzr71.132`, keeps the suite green and
leaves the city working.

| Unit | What it does | Files | Tests | Waits on |
|---|---|---|---|---|
| 1. The rule split from its reads, and the read saved | `GitHubRead` and its key; `observe`, `decide` and `FromStore`; `Ready` composed of the bead's side, `observe` and `decide`, returning the read it made; `github-unread` and section 2's test of a current read; the landing order reads GitHub's side once per check, saves it in each check's write, a queued PR's, a refused request's and a requeue's included, and leaves the last read on a read that fails partway; the pr noun's paragraph in `docs/gctk-architecture.md` | `services/gctk/pr/pr.go`, `rules.go`, `feedback.go`, a new `read.go`, `landing.go`, `services/gctk/key-registry.json`, `docs/gctk-architecture.md` | every `ready_test.go` case that answers gives one answer live and over the read it saves; section 2's test for another head, another PR, another provenance instant, no read saved, and a changed head's observed head; the landing order saves the read on a check, a request, a refused request, the queue and a requeue, and keeps the last read on a failure after the PR's read; the merge path's two cases of section 6 | nothing |
| 2. Every display over the saved read | `gctk pr status` over `FromStore`, with no gh and no definition of feedback; `prstatus.Render`'s `github-unread` case and the package's header; `Listing.PRAnswers`; the rig board's `prFacts` and row 5, carried from #1509; `gctk pr status`'s row in `docs/gctk-architecture.md` and the README | `services/gctk/internal/cli/prstatus.go`, `services/gctk/prstatus/render.go`, `prstatus.go`, `services/gctk/listing`, `services/helm/internal/rigboard` (`gather.go`, `build.go`, `table.go`, `document.go`), `services/helm/web/src/rigboard/document.gen.ts`, generated from `document.go`, `docs/gctk-architecture.md`, `services/gctk/README.md`, `services/helm/README.md` | `gctk pr status` gives each status over a saved read with a gh stub that fails the test when it is called; `github-unread` reads `working`, and `needs-attention` beside a gate; `PRAnswers` over a pass; #1509's `pending_test.go`, read from the saved read in place of a live one, so four of its six cases fail if the board falls back to the posture; row 5 for a bead the record holds blocked | unit 1 |

No unit writes the label. Its writer on the pending record is tk-1tfzr71.149's
(section 5).

## 12. Edges and notes the implementation child adds

- The units are filed under the epic (tk-1tfzr71), with
  `target=integration/tk-1tfzr71.132` in each create. tk-1tfzr71.132 and the
  summary task tk-1tfzr71.136 each wait on every unit through a `blocks` edge.
  Unit 2 waits on unit 1, armed to dispatch on `mol-polecat-work` when its wait
  closes. The child builds no unit.
- tk-1tfzr71.21's description takes the Done of section 7 in place of its Done
  paragraph, in one write that keeps every other line. A note there says that a
  PR still on the old path shows by `pr-facts.sh`'s keys, so the script's
  retirement comes after the rig moves, or gives such a PR another source.
- tk-1tfzr71.24 gets a note naming `Listing.PRAnswers` as the call its
  replacement reader makes for the rule its notes already name, once unit 2
  lands.
- tk-1tfzr71.22 gets a note naming section 8's plan and section 7's rows of
  `specs/tk-1tfzr71.108/design.md`, so whichever effort lands second carries
  them.
- Before filing, the child surveys the open branches against each unit's files
  again, since they move. At this reading `integration/tk-1tfzr71.22` touches
  them. PR #1514 touches the epic noun's lines of `docs/gctk-architecture.md`
  and `services/gctk/README.md`, and the generated `key-registry.json`.
  `integration/tk-1tfzr71.17` touches `docs/built-once-target.md` outside its
  merge section.

## 13. Facts this design rests on

- `pr.Ready`'s reads and their order, `Sources`, `recordGaps`, `identityGaps`,
  `passedAt`, `ownWaits` and `anchoredTo` in `services/gctk/pr/pr.go`;
  `approval` and `checks` in `rules.go`; `unhandled`, `newest` and `awaiting`
  in `feedback.go`, all at 7559e1bbd.
- The landing order's paths in `services/gctk/pr/landing.go` (`blocked`,
  `decide`, `merged`, `except`, `gate`, `closed`, `audit`), and the record's
  writes in `services/gctk/pr/record/record.go`: `Checked` writes `pr_state` and
  `pr_last_checked_at` and clears `pr_reconcile_error`, `Retry` writes the
  three, `Requeue` writes `observed_pr_head_sha`, and `Publish` clears it.
- `gctk pr status` evaluates `pr.Ready` for a bead on the record and
  `prstatus.Derive` otherwise (`services/gctk/internal/cli/prstatus.go`). The
  rig board on main derives every PR with `prstatus.Derive` (`table.go`'s row
  6, `askOf`, `pullRequestOf` and `reasonsOf`), so for an unapproved PR on the
  record the board reads `needs-review` from the posture while the label reads
  `working`, which is how `Render` reads the review condition while nothing on
  main writes `review_results`.
- `pr-status-label.sh` derives through `gctk pr status --json` and writes only a
  label that differs. At main 65a86b0e7, `pr-facts.sh`'s full pass calls its
  `reconcile` for each anchor its walk reaches (`reconcile_status_label`), and
  the walk lists `pull_request` on an open bead, `pull_request_pending` on a
  blocked one and `pull_request_head_changed` on an open one
  (`OPEN_PR_ANCHORS_JQ`). It records no merge or close of a PR on the record and
  clears none of its labels, leaving the record to the landing order.
- No bead in gc-toolkit's store carried `pull_request_pending` or
  `pull_request_head_changed` on 2026-11-15, read with
  `gc bd list --metadata-field merge_result=<value>`.
- The Gas City, Gas Town and bd facts are in
  [gas-city-search.md](gas-city-search.md), each at its commit.
