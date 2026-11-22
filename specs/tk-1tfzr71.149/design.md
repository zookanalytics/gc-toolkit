---
name: Design — ask GitHub cheaply whether each PR moved, read only a PR that did, and act from the beads
description: The design for tk-1tfzr71.150, the design child of initiative tk-1tfzr71.149, read at main 8b9c4caf3 and against Gas City upstream main 9a4b1e718. A cheap question asks GitHub every 2 minutes whether each PR the city owns moved, a one-PR update reads and saves only a PR that did, the landing order acts from the beads every minute, and a full comparison every 10 minutes is the net for what no cheap sign catches. Read it to approve the design at its gate, or to build or review one of its units.
---

# Design: ask GitHub cheaply whether each PR moved, read only a PR that did, and act from the beads

This is the design record for tk-1tfzr71.150, the design child of the
initiative tk-1tfzr71.149, under the brief of conversation tk-trcyz2l. The pack
was read at main 8b9c4caf3, which carries the review-lanes effort
(tk-1tfzr71.22, #1531) and the PR-status effort (tk-1tfzr71.132, #1532).
`integration/tk-1tfzr71.149` was cut from main at 65a86b0e7 and carries
neither. Gas City is cited by symbol at `gastownhall/gascity` main 9a4b1e718,
Gas Town and the github pack by path at `gastownhall/gascity-packs` main
0f07496d2f, and bd at `gastownhall/beads` v1.3.4. GitHub was measured from the
city's account on 2026-11-16 ([section 16](#16-facts-this-design-rests-on)).
Repositories other than this one are lettered. The search behind the surface
the units add is [gas-city-search.md](gas-city-search.md).

## What the operator approves

The landing order is the order that merges the city's PRs and closes their
beads. Approving this design splits its work into reading GitHub and acting:

- **A cheap question every 2 minutes.** One light GitHub request per repository
  asks, for every PR the city owns, whether anything moved. It reads signs, such
  as a PR's head, its comment and review counts, its labels and its checks
  counted by state, and no details. A pass in which nothing moved writes no bead.
- **A one-PR update.** A PR whose sign moved is read alone, only on the side
  that moved, and saved on its bead. It is the only way GitHub's side reaches a
  bead, and it is the call a webhook makes later for the PR an event names.
- **The landing order acts from the beads every minute.** It merges after its
  own fresh read of the one PR, lands a merged PR, sends back one at a new head,
  gates the exceptions, and writes a label where the labels GitHub shows differ
  from what the store derives. Nothing records an act that failed: the
  difference stays, and the next run acts on it.
- **A full comparison every 10 minutes is the net** for the changes no cheap
  sign catches, such as a review thread a person resolves, or an edit to a
  comment or a review that left the PR's change time as it was.
- **The board shows when GitHub was last asked,** for each rig.

A pass in which nothing moved costs 1 GitHub point per repository and about a
second and a half. At today's 28 open PRs in five repositories, the city's
reading costs about 230 of the hour's 5,000 points, and 1 or 2 more for each PR
that moved.

**Where this departs from the operator's words:**

1. "The whole polling ever PR for lots of details, to see things like a
   resolved comment or re-checking a check over and over again, feels well
   overkill." The cheap question reads no thread and no check's details. But a
   thread resolved or reopened moved no cheap sign when tested on this PR, and
   an edit to a comment or a review does not always move one, so the net reads
   every owned PR's threads, its required checks and the time each comment and
   review last changed every 10 minutes, at 2 points for each 10 PRs. It reads
   no comment's text ([section 2](#2-the-net)).
2. "I thought we talked about one order reads, while another acts." The net, a
   reading order, also takes the city's labels off a PR no bead owns, because
   no bead holds that work for the landing order to find
   ([section 9](#9-labels)). The landing order reads GitHub only for the
   merge's own fresh read, as the spine has it.
3. "The not writing beads all the time is great, I'm a huge fan of that." No
   PR's bead is written unless GitHub moved. Gas City still writes a run record
   for each run of each order, about 96 an hour for each rig, which this city
   deletes 30 minutes after each one closes.

**Decisions to check,** each settled here unless the operator says otherwise:

1. **The cadence.** The cheap question runs every 2 minutes, the landing order
   every minute and the net every 10 minutes. A change a cheap sign shows
   reaches its act within about 4 minutes, and one only the net sees within
   about 12 ([section 6](#6-the-orders-and-their-cadence)).
2. **The landing order runs on its own clock,** not on an event the update
   emits, so a change on the store's side that no writer announces, such as a
   gate a person clears, reaches it within a minute. A webhook rule starts it at
   once after its update ([section 5](#5-how-the-landing-order-starts)).
3. **The intake's finish line, read for this shape.** It says "One writer, the
   landing order, saves one GitHub read per PR". Here that writer is the one-PR
   update, which the cheap question, the net and a later webhook call. The
   landing order reads that read and saves none of it
   ([section 12](#12-the-github-intakes-finish-line)).
4. **`pr_last_checked_at`** says when the one-PR update last read the PR and
   saved what it read. When GitHub was last asked about every PR is the board's
   age line ([section 11](#11-what-pr_last_checked_at-means)).
5. **Labels on PRs no bead owns** are cleared by the net, at most 20 a pass in
   each repository, so the 527 closed PRs here that still carry a city label
   clear in about four and a half hours ([section 9](#9-labels)).

## 1. The cheap signs

The cheap question is one GraphQL request per repository, with one aliased
`pullRequest(number: N)` field for each PR the city owns there. A PR is owned
when a live bead names it as its own and is no other bead's child: its anchor,
which names it in `pr_url` with a `merge_result`, or a bead the refinery sent
back to the pool, which names it in `existing_pr`. Every owned PR is asked
about, on the pending record or not.

Each field reads these signs and no detail:

| Sign | Field |
|---|---|
| The PR's state and draft flag | `state`, `isDraft` |
| Its head | `headRefOid` |
| Its base and the base's tip | `baseRefName`, `baseRef { target { oid } }` |
| When GitHub last changed the PR | `updatedAt` |
| Its comments, conversation and inline together | `totalCommentsCount` |
| Its reviews, and the dismissed among them | `reviews { totalCount }`, `reviews(states: [DISMISSED]) { totalCount }` |
| Its labels, every one | `labels(first: 100) { nodes { name } pageInfo { hasNextPage endCursor } }`, paged |
| Its checks at the head, counted by state | the head commit's `statusCheckRollup { state contexts { totalCount checkRunCountsByState { state count } statusContextCountsByState { state count } } }` |

`baseRefOid` is not the base's tip. On #1539 it read 6dd9d13ee, the base it was
opened on, while main's tip was 8b9c4caf3. So the request reads the base ref's
target.

The labels are read whole. A PR with more than 100 is read on from where its
first page ended until its labels end, and a page that fails is a failed read
for that PR. The labels' writer takes off only a label the saved labels hold,
and adds one they lack ([section 9](#9-labels)). So a stale label past an
unread page would never come off, and a derived label there would be added
again at every run. Reading 100 labels costs a request no more than reading 20:
1 point at 50 PRs either way.

What each kind of change moves, and how it was shown:

| Change | The sign that moves | Shown by |
|---|---|---|
| A pushed commit | the head | the field is the head; `updatedAt` also moved at every push the sitting's watch saw, 4 of 4 |
| A conversation comment | the comment count | the watch: `updatedAt` and the count moved at 8 of 8 |
| An inline comment | the comment count and the review count | the watch: the count less the conversation comments moved at 3 of 3; on #1533 the count is 10, its 6 conversation comments and 4 inline ones; each inline comment rides on a review |
| A review | the review count | the watch: `updatedAt` and the count moved at 6 of 6 |
| A dismissed review | the dismissed count | a dismissal sets that review's state to dismissed, which the count counts; the watch saw the count move at the one dismissal it caught, with label changes at the same moment |
| A label | the labels | the field is the labels; the watch: `updatedAt` moved at 9 of 9 |
| A finished check | the count of check runs by state | the watch's reads, compared again here: the counts moved at 32 of 32 check changes at one head, where the rollup's state moved at 5; GitHub's counts equal the counts of the check nodes on 15 of 15 open PRs; the sitting read `updatedAt` as moving for no check alone |
| A commit status | the count of statuses by state and the contexts' total | tested on #1533: a pending status and then a successful one moved them both times, and `updatedAt` neither time |
| A base branch that moved | the base's tip | the field is the tip; the watch: `updatedAt` moved at 1 of 45 |
| A merge or a close | the state | the field is the state; the watch: `updatedAt` moved at 2 of 2 changes of state or draft flag |
| An edit to a post's text: a conversation comment, a review or an inline comment | `updatedAt`, mostly | an edit moves the post's own `updatedAt`; the PR's moved to a conversation comment's edit on #1497 and #1524, each made after the PR's last other change, and to a review's edit within a second on a public PR; on another, a review edited 3 seconds after the PR's last change left `updatedAt` unmoved 8 minutes later, so the net reads each post's time ([section 2](#2-the-net)) |
| A thread resolved or reopened | none | tested on #1533: a thread reopened and then resolved moved no sign, no `updatedAt` and no ETag; the net reads it ([section 2](#2-the-net)) |
| The city's reaction on an inline comment, which answers its thread with no reply, as on a point declined | none shown | on #1542, inline comment 4591186925 kept its `updatedAt` of 20:34:23Z when the city's THUMBS_UP landed at 20:53:46Z, and no count counts a reaction; whether the PR's `updatedAt` moved was not read then, so the net reads the reactions the city's account left on each inline comment ([section 2](#2-the-net)) |

Whether a post is feedback is read from its text (`gc_not_for_review` and
`gc_feedback` in assets/scripts/pr-post.sh). So an edit that takes out the mark
or the prefix saying a post is not for review turns it into feedback, and moves
no count.

Every kind no cheap sign is shown to catch goes to the net: a thread resolved
or reopened, the city's reaction on an inline comment, an edit to a post that
left `updatedAt` as it was, a change of the
repository's rules that moves the review decision, a check's required flag or
the merge state while no review or check moves, and two checks that trade
states between passes so every count stays the same, which no change the watch
saw did.

A PR counts as moved when any sign differs from the signs saved on its bead,
when its bead holds no saved read, or when the saved read is not current for
the bead: another head than the store holds, or another provenance instant, as
the evaluator's currency test (`unread` in services/gctk/pr/read.go) defines
it. So a new publication at a new head is read at the next pass.

A request reads at most 50 PRs, and a repository with more takes more requests.
In this repository the light read took 1.1 to 1.4 seconds at 10 PRs, 1.7 to 2.0
at 25 and 2.4 to 4.2 at 50, for 1 point each, and 5.1 to 5.6 seconds at 100 for
2 points. GitHub ends a request at 10 seconds. A response that carries errors is
a failed read for the PRs its errors name. Those PRs keep their saved signs and
are asked about again at the next pass, and the run exits non-zero, so Gas City
records it as failed.

Two cheaper-looking signs fail. A PR's REST ETag moves at any push anywhere in
its repository, because the body embeds the repository, and the watch saw 8 of
its 20 moves in the city come from that alone. The ETag of the check runs at a
PR's head missed the commit status tested on #1533. Each also takes one REST
request for each PR at every pass, where the cheap question asks about 50 PRs
in one request.

## 2. The net

The net is its own order, `pr-compare`, every 10 minutes. It reads each owned
PR's state, draft flag, head, base and the base's tip, merge state, review
decision, merge-queue flags, every label, dismissed count, every review
thread's resolution, the time each post last changed, the reactions the city's
account left on each inline comment, and the required checks at the head
through the rollup's contexts, each with `isRequired(pullRequestNumber: N)` at
the PR's own number. A post's time is its `updatedAt`, read on each
conversation comment, each review and each inline comment, the inline ones
through the review threads, 10 threads a page. The net reads no post's text.
GitHub counts a list nested in another once for each item that could hold it,
so the inline comments of 100 threads a PR would cost a request of 10 PRs 10
points, where 10 threads a PR cost it 2. A request reads at most 10 PRs. On the
15 open PRs of the city's busiest repository the read took 2.0 to 3.0 seconds
at 5 PRs for 1 point, and 2.8 to 3.5 at 10 and 3.5 to 5.0 at 15 for 2 points,
with no errors. Each inline comment's reactions are GitHub's reaction groups
with whether the reading account reacted, which is no paged list: with them a
request of 9 of this repository's PRs still cost 1 point and one of 10 cost 2,
and a read of 10 took 1.9 to 2.0 seconds. A PR whose labels, comments, reviews,
threads, a thread's comments or checks pass the first page is paged until that
connection ends, and a response that carries errors is a failed read for the
PRs it names.

The net compares what it read with each PR's saved read, and runs the one-PR
update over every part of each PR that differs. The saved read holds what the
net compares, the unresolved threads, the newest post time and the city's
reactions among it ([section 3](#3-where-the-signs-are-kept)). When a PR's
newest post time differs from the one saved, the update reads its conversation
again, so an edit no cheap sign showed is saved within one pass of the net. A
change no cheap sign shows goes unseen for at most the net's 10 minutes, plus
up to 30 seconds before Gas City's next lane pass starts the run, plus the run
itself.

The net also runs the search for labels on PRs no bead owns
([section 9](#9-labels)).

## 3. Where the signs are kept

The signs last seen are kept in the saved read, `pr_github_read`, on the bead
that owns the PR, beside the facts they describe. The saved read holds GitHub's
side in four parts. Each part keeps the instant its read was sent and the signs
read with it, never later than its facts:

| Part | Its facts | The signs kept with it |
|---|---|---|
| The PR | URL, number, repository, head branch, base, head, state, draft flag, merge state and merge-queue flags | state, draft flag, head, base, the base's tip, `updatedAt` |
| The checks | the required check runs and commit statuses at the head, with their results | head, the rollup's state, the contexts' total, the counts by state |
| The conversation | the approvers and requesters, the newest feedback in each id space, the threads waiting on the city's answer, the unresolved threads, the review decision, and the provenance instant the definition of feedback was applied from | comment count, review count, dismissed count, `updatedAt`, the newest post time, the city's reactions |
| The labels | the label names | the names themselves |

The newest post time is the latest `updatedAt` among the PR's conversation
comments, reviews and inline comments. The update's read of the conversation
takes it with their text, and the net reads it to compare. The city's reactions
are each reaction the city's account left on an inline comment, by the
comment's id, which the definition of feedback reads as an answer to the
comment's thread (`gc_thread_awaits_answer` in assets/scripts/pr-post.sh): the
update's read takes them with the threads, and the net reads them to compare.
The PR part and the conversation part each keep `updatedAt`, so a move of it
reads both.

The one-PR update is the only writer of the saved read and its signs. It also
writes Gas Town's `pr_state` and `pr_last_checked_at` on a record on the pending
record. The cheap question and the net write nothing to a bead, and the landing
order reads the saved read and writes none of it.

## 4. The one-PR update's read

The one-PR update is `gctk pr refresh --pr <url>`. The verb is `refresh`
because `gctk pr` names a verb by what it does to the city's record of the PR,
and "update" would read as a write to the PR on GitHub.

1. **Find the bead that owns the PR** in the store. A PR no live bead owns has
   nothing to save, and the update says so and exits 0.
2. **Take the signs.** The cheap question and the net hand it the signs they
   read. Called alone, as by a webhook rule, it reads the one PR's signs itself,
   for 1 point in about a second.
3. **Read only what moved.** Each sign that moved adds its row's reads, so a
   push and an edit in one pass read both the checks and the conversation:

   | What moved | What it reads |
   |---|---|
   | the labels | nothing more, since the signs are the labels |
   | the base's tip | the PR part, whose merge state the base moves |
   | `updatedAt` | the PR part, and the conversation part, since an edit to a post can move `updatedAt` and moves no count |
   | the head, or the checks' state, total or counts | the PR part and the required checks at the head, in one request |
   | the comment, review or dismissed count | the conversation part, in one request, and the PR part, whose merge state reviews move |
   | the newest post time, which only the net reads | the conversation part |
   | no saved read, or one not current for the bead | every part |

   The PR part with the required checks took 0.9 to 1.8 seconds for 1 point, and
   the conversation part 0.8 to 1.1 seconds for 1 point, on #1533 and on the
   most discussed open PR of the city's busiest repository (16 comments, 14
   reviews, 4 threads). The conversation read applies the definition of
   feedback from the bead's provenance instant, with the login the city's
   account acts as, which a caller reads once a run. It reads each post's
   `updatedAt` with its text and keeps the newest as the post time.
4. **A merge state read as unknown.** GitHub computes a merge state lazily after
   a push or a base move. The update saves the PR part with its merge state
   unknown and keeps that part's earlier signs, so the next pass finds the PR
   moved and reads it again. Nothing else records it.
5. **Write only what differs.** Under the record lock, the update reads the
   bead and writes the saved read once, guarded on the status and assignee that
   read shows, with each part whose read is newer than the saved one
   ([section 7](#7-an-older-read-never-replaces-a-newer-one)) and whose facts or
   signs differ, and the instant alone of a newer read whose facts and signs are
   the same. The read of the bead and the guarded write took about half a
   second together.

## 5. How the landing order starts

Gas City offers three ways to start an order that matter here, all in
`gastownhall/gascity` 9a4b1e718:

- **A cooldown.** `checkCooldown` (internal/orders/triggers.go) makes an order
  due once the time since its last run's start reaches `interval`.
- **An event the pack emits.** `gc event emit <type>` records an event of any
  type, best-effort (cmd/gc/cmd_event_emit.go). `checkEvent` makes an event
  order due when an event of its `on` type follows its cursor, and
  `dispatchExec` (cmd/gc/order_dispatch.go) sets the cursor to the event log's
  head before the command runs, so an event recorded during a run starts the
  next run.
- **A run on demand.** `gc order run <name>` (`cmdOrderRun` and
  `doOrderRunExecTracked` in cmd/gc/cmd_order.go) runs an exec order's command
  in the caller and writes a run record, from which the cooldown then counts. It
  does not wait for a run that is open.

The landing order runs on a cooldown of 1 minute, and a webhook rule starts it
on demand after its update ([section 8](#8-the-webhook)). An event would start
it about 30 seconds after an update, but every writer of a store change it acts
on would have to emit one: a review run's result, an ask, a withdrawal, a person
clearing a gate. A change no writer announced would wait for whatever runs it
next. A condition order (`checkCondition`) would run its check at every lane
pass, about every 30 seconds, with the lane waiting on it, and an act that keeps
failing would run again at each pass.

A run of the landing order reads the store in one listing and decides every
record from its saved read and the store, by the evaluator's rule as
`FromStore` composes it today. It acts under the record lock, each act guarded
on the status and assignee read under it. Only the merge reads GitHub: it takes
the whole read in its own run and pins its request to the head it judged, as
today. Every other act decides from the saved read and the store, such as a
landing, a send-back, an exception's gate, marking a draft ready, dismissing a
withdrawn approval and a label write. The landing fetches the target to find the
merge commit, as today. An act made from a saved read that a later refresh
shows to be stale is decided again from the newer read at the next run.

No act starts more than 45 seconds into a run, and each act stops at 30
seconds, with whatever GitHub call or fetch it is making. So a run whose first
act is slow still starts the next one. Neither has a limit of its own today:
gctk's GitHub adapter (services/gctk/internal/gh/gh.go) and the landing's fetch
(`FetchBranch` in services/gctk/internal/git/git.go) wait for the call to end.
A fetch is stopped as `gitIn` (services/gctk/internal/cli/lifecycle.go) stops
one today: a SIGTERM to git's process group, and a kill only if git still runs
5 seconds later. Git removes the lock files a fetch holds in the rig checkout on
SIGTERM and cannot on SIGKILL, and a lock left behind fails every later fetch of
that branch there until a person deletes it.

A run takes the records that have an act in an order it shuffles. So a record
whose act is slow or keeps failing comes first in about one run in n, where n
records have an act, and its act holds no other record back. A stopped or
failed act leaves its difference, which a later run acts on, and nothing
records it. The landing order reads no record's PR to decide, so it needs no
bound on records per run (`--count`).

## 6. The orders and their cadence

| Order | Trigger | What a run does | GitHub points a pass |
|---|---|---|---|
| `pr-poll`, the cheap question | every 2 minutes | lists the owned PRs, asks GitHub about them, and runs the one-PR update for each that moved, starting none more than 90 seconds in | 1 per 50 owned PRs in the rig's repository, none when it owns none |
| `pr-compare`, the net | every 10 minutes | reads every owned PR's comparable facts, runs the one-PR update for each that differs, and searches for labels on PRs no bead owns | 1 for a request of up to 9 owned PRs and 2 for one of 10, and 1 for each page of the search, which is 1 here |
| `pr-reconcile`, the landing order | every minute | acts from the beads | none to decide; the merge's own read when it merges |

Each order is rig-scoped, as the landing order is, and reads its rig's
repository. At today's 28 open PRs in five of the six rigs' repositories:

| Cadence of the cheap question | Points an hour for the city | Run records an hour per rig |
|---|---|---|
| 1 minute | about 300 | 60 |
| 2 minutes | about 150 | 30 |
| 5 minutes | about 60 | 12 |

| Cadence of the net | Points an hour for the city | Run records an hour per rig |
|---|---|---|
| 5 minutes | about 156 | 12 |
| 10 minutes | about 78 | 6 |
| 30 minutes | about 26 | 2 |

A pass of the net costs about 13 points: 1 to read each of four repositories,
3 to read the busiest, whose 15 PRs take a request of 10 and one of 5, and 6
for the searches, one in each repository.

The landing order every minute adds 60 run records an hour per rig, and every
2 minutes 30. The one-PR updates add 1 or 2 points for each PR that moved. Gas
City deletes a closed run record after `[beads.policies.order_tracking]
delete_after_close`, which this city sets to 30 minutes. Every interval is tuned
from city.toml with `[[orders.overrides]]`.

A change a cheap sign shows reaches its act within the cheap question's 2
minutes, its update's few seconds and the landing order's minute, each run
starting up to 30 seconds late at the next lane pass: about 4 minutes at the
most, and about 2 on average. A change only the net sees reaches its act within
about 12 minutes.

## 7. An older read never replaces a newer one

Two updates of one PR can cross: a webhook's and the cheap question's, the
net's and the cheap question's, or two runs that overlap, since Gas City closes
a run record two minutes after it is made whether or not the run still works
(`runOrderTrackingSweepWatchdog`).

Each part of the saved read keeps the instant its read was sent. Under the
record lock, the update writes a part only when its own read of that part was
sent after the saved part's instant, and a newer read that finds the facts and
signs the part holds writes the part's instant, so a read sent before it and
still in flight is not saved after it. A part and its signs are written together,
and the signs were read no later than the facts beside them. So an older read
never replaces a newer part, and saved signs never claim a state newer than the
saved facts. When the signs a caller hands the update were read some seconds
before the update read the facts, the worst that follows is one more read of
the PR at the next pass, and no change is hidden.

## 8. The webhook

None of it is built here. The upstream route that fits is the webhook service of
the github pack, `github/scripts/github_intake_service.py` in
`gastownhall/gascity-packs` 0f07496d2f. It accepts a delivery and runs the rules
that match on a thread of its own (`enqueue_event_rules`), so GitHub's 10
seconds for an answer are never spent on them. It runs each rule's actions in
order and stops at the first that fails (`process_event_rules`). An `order`
action runs `gc order run <name> --rig <rig>`, and a `command` action runs its
argument list with each `{{path}}` filled from that path in the delivery's
payload, and with the PR's number in `GC_GITHUB_PR_NUMBER`
(`execute_rule_action`, `render_template`, `github_event_env`). The
rules live in the city's `config/github-intake/rules.toml`. The call a rule
makes for one PR, a review here:

```toml
version = 1

[[rule]]
id = "pr-review-refresh"
event = "pull_request_review"
match = { "repository.full_name" = "zookanalytics/gc-toolkit" }

[[rule.action]]
type = "command"
command = [".gc/services/gctk/bin/gctk", "pr", "refresh", "--pr", "{{pull_request.html_url}}"]

[[rule.action]]
type = "order"
name = "pr-reconcile"
rig = "gc-toolkit"
```

A rule like it serves each event that names its PR in the payload: a PR's own
change, a review, an inline comment, a thread resolved or reopened, and a
conversation comment on a PR. An event that names no PR on such a path, such as
a check run, whose PRs come in a list, a commit status or a push to a base,
leaves its change to the next pass.

Gas City's own receiver does not fit. A public hook may fire only a formula
order, never an exec order (`routeOrder` in internal/webhooksink/sink.go). A
tenant or private hook answers only a request from the loopback or one carrying
`X-GC-Request` (`webhookRequestAllowed` in internal/api/handler_webhook.go),
which GitHub's delivery does not.

A delivery is a hint to read, never the facts. GitHub does not redeliver a
delivery that failed, so the one-PR update reads GitHub itself, and the cheap
question's next pass covers any delivery that never arrived.

## 9. Labels

The labels GitHub shows on a PR are among its saved facts, saved by the one-PR
update whenever they move. The landing order derives what the store says the
labels should be, by `prstatus`, the derivation `gctk pr status` runs for one
bead and the rig board runs for all of them. It writes a label only where the
saved labels differ, through the labels' one writer,
`assets/scripts/pr-status-label.sh`, with the verbs it has: `reconcile` for an
owned open PR and `clear` for an owned PR that merged or closed. It passes the
saved labels, which are the whole set ([section 1](#1-the-cheap-signs)), as the
labels GitHub shows (`--current-labels`), so the writer edits only what differs
from them. It reads the PR's labels itself only when the saved labels are
empty, and a write that adds a label first lists the repository's labels to
create any it lacks (`ensure_labels`). A write repeated before the next refresh
saves the labels it made asks GitHub to add a label already there or take off
one already gone, which changes nothing. A write that does not land leaves the
difference on the bead, and the next run writes it again. No key records it.

| The PR | The labels the store derives |
|---|---|
| owned and open, on the pending record | the `status:` and `held:` values `gctk pr status` gives the bead |
| owned and open, on the old path | the values `gctk pr status` gives the bead from the facts its keys hold |
| owned, merged or closed | none, since GitHub's own state takes over |
| owned by no live bead | none, since the city works no such PR |

The PRs no bead owns are found by a search the net runs once a pass in each
repository, `search(type: ISSUE, query: "repo:<repository> is:pr
label:\"status: working\",...")` over every `status:` and `held:` value the
labels' writer names, 100 PRs a page for 1 point. The net reads on, a page at a
time, until it has found 20 PRs that no live bead owns or the results end, and
gives each of them `clear`, so at most 20 a pass in each repository. A page
that holds only owned PRs, whose labels are right, never hides the PRs behind
it. On 2026-11-16 the search found 533 PRs here, newest first: the 6 open ones,
which beads own, and 527 closed ones that still carry a label, all closed before
2026-10-30. Its first page held the 6 and 94 to clear, so a pass reads one page
for 1 point, and the 527 clear in 27 passes, about four and a half hours. A pass
reads a second page only where more than 80 owned PRs come before the twentieth
PR to clear. A clear that does not land is found by the next pass's search.

Every other caller of the labels' writer is code a scheduled bead retires, so
none changes here (AGENTS.md, the rule that retiring code gets no new work):

| Caller | Its calls | It retires with |
|---|---|---|
| `pr-facts.sh` | its full pass's `reconcile`, and its clear at a merge or a close with `status_label_clear_owed` | tk-1tfzr71.21 (tools/deletion-plan.tsv) |
| `gctk merge` | its clear at a merge, with `status_label_clear_owed` | tk-1tfzr71.70 (docs/built-once-target.md, lane A) |
| `pr-open.sh` | `reconcile` at its create, its adoption and its draft-to-ready arm | its create with tk-1tfzr71.70, and its adoption and its arm with the merge cadence that runs them (tk-1tfzr71.21) |
| `signoff.sh` | `reconcile` after a verdict | tk-1tfzr71.122 (tools/deletion-plan.tsv) |

Once they retire, the landing order and the net are the only callers.
`status_label_clear_owed` retires with its two writers, and the comparison
makes the writes it would have retried.

## 10. The age line

The board shows, for each rig, when GitHub was last asked: the start of the
newest run of that rig's `pr-poll` that exited 0. It reads them from Gas City's
run history, `GET /v0/city/{city}/orders/history?scoped_name=pr-poll:rig:<rig>`
(`humaHandleOrderHistory` in internal/api/huma_handlers_orders.go), whose
entries carry each run's `created_at` and `exit_code`. A run that could not read
a repository exits non-zero, so a failing question leaves the line at the last
pass that read every owned PR. The line reads stale once that pass is older than
three intervals, 6 minutes. This city deletes a run record 30 minutes after it
closes, so with no successful run in the history the line reads "not asked in
the last 30 minutes". It is a unit of its own.

## 11. What `pr_last_checked_at` means

Gas Town's command stamps `pr_last_checked_at` on a record at every check, and
its `reconcile_one` takes the least recently checked record first
(`gastown/commands/pr-merge-reconcile/run.sh`), so there the stamp rotates the
queue and says when the command last looked at the PR.

Here the cheap question asks about every owned PR at every pass and writes
nothing, so nothing rotates. The one-PR update stamps `pr_last_checked_at` with
each write it makes to a record on the pending record, so the key says when
GitHub's side of that PR was last read and saved. When GitHub was last asked
about it is the board's age line. Gas Town's command also records a check that
could not decide in `pr_reconcile_error`. Here nothing records a read or an act
that failed: a read that fails leaves the PR's signs as they were, an act that
fails leaves its difference on the bead, and Gas City's run record holds the
failure. docs/built-once-target.md names both as one difference.

## 12. The GitHub intake's finish line

The intake effort's done (tk-1tfzr71.21) reads: "One writer, the landing order,
saves one GitHub read per PR, and nothing else mirrors GitHub state into bead
metadata." Under this shape the one writer is the one-PR update, which the
cheap question, the net and a later webhook call. It saves one GitHub read per
PR, the saved read with Gas Town's `pr_state` and `pr_last_checked_at`, and
nothing else mirrors GitHub state into bead metadata. The landing order reads
that read and saves none of it. The reading this design puts to the operator at
the PR: the line holds with "the one-PR update" in the place of "the landing
order".

The intake reads its feedback from that saved read. When the conversation part
shows feedback past what the bead's receipts hold, routing the posts behind it
is an act of the landing order, taken from the bead like every other act. Its
own read of a post's text is that act's read. The intake's design
(tk-1tfzr71.161, #1536) names the read the landing order saves, so under this
shape it reads the one the one-PR update saves.

## 13. The units and their waits

The review-lanes effort and the PR-status effort have landed on main, so no
unit waits on either bead. The first four units rewrite code those efforts
changed, so the effort's branch is first brought current with main at or past
8b9c4caf3, and unit 1 is built on it.

| # | Unit | What it builds | Waits on |
|---|---|---|---|
| 1 | feat(gctk): read a PR only when GitHub shows it moved | The cheap question in gctk's GitHub adapter. `gctk pr refresh`, the one-PR update, with the saved read in four parts, each with its read instant and signs, and Gas Town's `pr_state` and `pr_last_checked_at` moved to it. `gctk pr poll` and its order, `orders/pr-poll.toml`, every 2 minutes. The landing order stops writing the saved read and those two keys, and keeps its own read until unit 2. | the branch brought current with main |
| 2 | feat(gctk): have the landing order act from the beads | The landing order decides every record from the saved read and the store, reads GitHub only for the merge's own read, runs every minute with no `--count`, takes its acts in a shuffled order, starts none past 45 seconds and stops each at 30, a fetch as `gitIn` stops one, and writes no `pr_reconcile_error` | unit 1 |
| 3 | feat(gctk): compare every owned PR in full every 10 minutes | `gctk pr compare` and its order, `orders/pr-compare.toml`: the full read in requests of at most 10 PRs, with each post's time, paged, and the one-PR update for each PR that differs | unit 1 |
| 4 | feat(gctk): keep each PR's status labels equal to what the store derives | The landing order's label writes by comparison, the net's search, paged until it has found 20 PRs no bead owns, and its clears of them, and the labels' writer's header naming its callers | units 2 and 3 |
| 5 | feat(board): show when GitHub was last asked | The age line on the board, from `pr-poll`'s run history | unit 1 |

Each unit's change carries the docs its behavior changes:
refinery-merge-cadence.md's landing order, state-machine.md's pending record,
gctk-architecture.md, services/gctk/README.md, the orders' headers, the saved
read's warrant and key registry entries, and docs/architecture.md. That page's
decision that no display reads GitHub names the read the landing order saved,
and unit 1 names the one the one-PR update saves instead.

Code a scheduled bead retires gets no change from any unit: `pr-facts.sh`, the
merge cadence's arms and `refinery-reconcile.sh` (tk-1tfzr71.21), `gctk merge`
and `pr-open.sh`'s create (tk-1tfzr71.70), and `signoff.sh` and the
review path (tk-1tfzr71.122). The units add no verb to `pr-status-label.sh`.

Edges and notes the implementation child adds:

- **Units:** `blocks` edges as the table gives them.
- **tk-1tfzr71.91** (a merged or closed PR keeps its label): move its `blocks`
  edge and its arm on mol-validate-close from tk-1tfzr71.149 onto unit 4, and
  append a close brief: once unit 4 lands, check that a PR the landing order
  records merged or closed ends with no `status:` or `held:` label, and that a
  clear that failed is made by a later run.
- **tk-1tfzr71.140** (a stood-down exception's PR stays open and labeled): move
  its `blocks` edge and its arm on mol-polecat-work onto unit 4, and append a
  note: unit 4 takes the city's labels off an open PR whose bead has closed, so
  the label half of its done is settled there, and it builds only the other
  half, that standing work down leaves no PR open behind the closed bead.
- **tk-1tfzr71.21 and its design, tk-1tfzr71.161:** append a note that the
  saved read is the one-PR update's ([section 12](#12-the-github-intakes-finish-line)).
  The unit that retires `pr-facts.sh` waits on tk-1tfzr71.149, the landing
  bead, by a `blocks` edge its implementation child adds.

## 14. What the gate holds

The initiative's proposed done criteria, as this design holds them. Where the
wording moved, the reason follows in italics.

1. For every PR the city owns, a change a cheap sign shows reaches the saved
   read within one pass of the cheap question, for as many moved PRs as the
   pass's 90 seconds refresh, about 60, and the rest in the passes after. Any
   other change reaches it within one pass of the net. *(The initiative said
   "within one pass, however many PRs are open". A thread resolved or reopened
   moves no cheap sign, and an edit to a post does not always move one, so only
   the net's read sees them, and the refreshes a pass starts are bounded so
   that the next pass starts on time.)*
2. A pass of the cheap question in which nothing moved writes no bead, and
   makes one GitHub request for each 50 owned PRs in a repository, plus one for
   each PR with more than 100 labels. Gas City still writes its run record.
   *(The initiative said "one GitHub call per repository". GitHub ends a request
   at 10 seconds, and the light read took about 5 seconds at 100 PRs.)*
3. The one-PR update is the only writer of GitHub's side on a bead, and it
   writes only what differs, never an older read over a newer one.
4. A PR's labels on GitHub are the ones the store derives, and a label that
   differs for any cause is corrected by a later run, with nothing recording
   that it was owed.
5. The landing order acts from the beads and writes a label only where the
   saved labels differ from what the store derives. *(The initiative said "The
   landing order makes no label call". The spine the operator accepted gives
   the label writes to the work order, which is the landing order.)*
6. The merge acts only on a fresh read made in its own run.
7. The board shows, for each rig, when GitHub was last asked.
8. docs/architecture.md, docs/built-once-target.md and
   docs/refinery-merge-cadence.md say so. *(The initiative said "the merge
   design". A spec records one moment, so the living doc that owns the landing
   order's runtime says it.)*

## 15. Pages this design changes

This change states the target in two living pages, and the units bring the
rest current as they build:

- **docs/architecture.md:** a decision that the one-PR update is the only way
  GitHub's side of a PR reaches its bead and that the landing order acts from
  the beads, and a Debt entry for what is built today, which the units retire.
- **docs/built-once-target.md:** a difference from Gas Town under Merge: a cheap
  question watches every PR and an update reads one, so `pr_last_checked_at`
  says when the PR was last read and nothing records a read that failed.

## 16. Facts this design rests on

Measured on 2026-11-16 with `gh api graphql` from the city's account, read-only
except the tests on this PR. Gas City's facts are in
[gas-city-search.md](gas-city-search.md).

- **The cheap question.** In this repository, one aliased field per PR over
  #1437 to #1536, three runs at each size: 1.06 to 1.35 seconds at 10 PRs, 1.68
  to 1.99 at 25 and 2.35 to 4.21 at 50, for 1 point each, and 5.09 to 5.55
  seconds at 100 for 2 points, with no errors. Without the dismissed count and
  the base's tip, 100 PRs took 3.35 to 4.27 seconds. Over each rig repository's
  open PRs, one request each: 6 PRs here, 15, 1, 1 and 5 in four others, 0.62 to
  1.70 seconds and 1 point each. The sixth rig's repository had none. In a dry
  run at 50 PRs, reading `labels(first: 100)` in place of `labels(first: 20)`
  left the request at 1 point.
- **The base's tip.** On this repository's six open PRs, `baseRefOid` equalled
  `baseRef.target.oid` on the five whose base had not moved, and on #1539 read
  6dd9d13ee while main's tip was 8b9c4caf3.
- **Counts by state.** On the busiest repository's 15 open PRs, GitHub's
  `checkRunCountsByState` and `statusContextCountsByState` equalled the counts
  of the check nodes on every PR.
- **The sitting's watch,** 40 minutes on the city's 25 open PRs and 12 minutes
  on 60 PRs of three public repositories (conversation tk-trcyz2l's notes,
  2026-11-16T07:13:22Z): which changes moved `updatedAt` and the REST ETags.
  Its reads of every PR at every tick were compared again here: the counts of
  check nodes by state moved at 32 of the 32 changes of a PR's checks at one
  head, 1 in the city and 31 in public repositories, where the rollup's state
  moved at 5.
- **Tests on this PR,** 15:48:48Z to 15:51:06Z, each read 8 seconds and about
  30 seconds after the act:
  - A thread reopened (`unresolveReviewThread` on PRRT_kwDOR_nG-c63vJ31): only
    the set of unresolved threads moved. `updatedAt` stayed 15:37:59Z, every
    sign stayed, and the PR's, the check runs' and the combined status's ETags
    answered 304.
  - The same thread resolved with no reply: the same.
  - A commit status, pending and then successful, on the head 4d796d181: the
    statuses' counts by state moved (pending 0 to 1, then to successful 1), the
    contexts' total 1 to 2, the rollup's state to pending and back, and the
    merge state from clean to unstable and back. `updatedAt` did not move, the
    check runs' ETag answered 304, and the PR's and the combined status's ETags
    moved. The thread ends resolved, as it was, and the status successful.
- **Edits,** read from the times GitHub keeps, 17:00Z to 17:30Z. A post's
  `updatedAt` moved with each edit read: to the edit's second on conversation
  comments, reviews and inline comments, and 5 seconds later on one review. On
  #1497 and #1524, a conversation comment edited after the PR's last other
  change (04:40:17Z after 04:38:43Z, and 23:14:18Z after 22:49:45Z) set the
  PR's `updatedAt` to the edit's second. Of 529 edited posts read on the 40
  most recently updated PRs here and the 30 or 40 most recently updated in each
  of seven public repositories, 4 were later than their PR's `updatedAt` when
  read, all in one public repository. A review edited at 17:08:20Z, 3 seconds
  after its PR's last change, left `updatedAt` at 17:08:17Z, read again at
  17:16:38Z. A conversation comment edited 1 second after its PR's last change
  had not moved it a minute later, when a review's edit at 17:10:02Z moved it to
  17:10:03Z. The fourth was read seconds after its edit and edited again before
  a second read.
- **The net's read.** On the busiest repository's open PRs, three runs at each
  size, with each post's time and the threads 10 a page: 1.97 to 3.00 seconds at
  5 for 1 point, and 2.81 to 3.48 at 10 and 3.53 to 5.00 at 15 for 2 points, no
  errors. One PR of the 15 has 13 threads, so its threads take a second page.
  Without the post times, the read took 1.75 to 2.18 seconds at 5, 2.41 to 2.70
  at 10 and 2.82 to 5.08 at 15, 1 point each. In dry runs at 10 PRs here, the
  conversation comments' and reviews' times left the request at 1 point, and
  the inline comments made it 10 under `reviewThreads(first: 100)` and 2 under
  `reviewThreads(first: 10)`. Dry runs of the whole read here cost 1 point at 1
  to 9 PRs, 2 at 10 and at 15, and 3 at 20.
- **The one-PR update's reads.** The PR part with the required checks: 0.90 to
  1.01 seconds on #1533 and 0.95 to 1.81 on the busiest repository's most
  discussed open PR, 1 point each. The conversation part: 0.76 to 0.89 and 0.98
  to 1.05 seconds, 1 point each.
- **The search.** 527 closed and 6 open PRs here carry a `status:` or `held:`
  label. None closed since 2026-10-30 carries one. The search lists them newest
  first, and its first page held the 6 open ones and 94 closed. 1 point and 0.98
  to 1.09 seconds a page.
- **The landing order's calls.** At main 8b9c4caf3, gctk's GitHub adapter runs
  `gh` with no time limit (`exec.Command` in services/gctk/internal/gh/gh.go),
  and so does the landing's fetch (`FetchBranch` and `Output` in
  services/gctk/internal/git/git.go). A fetch of this repository's main into its
  checkout took 2.0 and 2.2 seconds. The fetch a `merged` transition makes stops
  at 60 seconds by a SIGTERM to git's process group, and kills git only if it
  still runs 5 seconds later (`gitIn`, `landingFetchTimeout` and
  `landingStopGrace` in services/gctk/internal/cli/lifecycle.go).
- **The store.** `gc bd list --json --limit 0` listed this rig's 857 live beads
  in 0.43 to 0.45 seconds. A read of one bead by its id took 0.15 to 0.19
  seconds and a metadata write guarded on its status 0.32 to 0.34, at a load
  average of 4.5.
- **The allowance.** At 15:47Z the account had used 551 GraphQL points in an
  hour that reset at 16:17:35Z, and 2,537 REST requests, of 5,000 each.

```bash
# The cheap question: one aliased field per owned PR.
#   p<N>: pullRequest(number:<N>){ number state isDraft headRefOid baseRefName
#     baseRef{target{oid}} updatedAt totalCommentsCount reviews{totalCount}
#     dismissed: reviews(states:[DISMISSED]){totalCount}
#     labels(first:100){pageInfo{hasNextPage endCursor} nodes{name}}
#     commits(last:1){nodes{commit{statusCheckRollup{state contexts{totalCount
#       checkRunCountsByState{state count} statusContextCountsByState{state count}}}}}} }
# The net: the same less updatedAt and the comment, review and check counts, plus
#     mergeStateStatus reviewDecision isInMergeQueue
#     comments(first:100){pageInfo{hasNextPage endCursor} nodes{updatedAt}}
#     reviews(first:100){pageInfo{hasNextPage endCursor} nodes{updatedAt}}
#     reviewThreads(first:10){totalCount pageInfo{hasNextPage endCursor} nodes{isResolved
#       comments(first:100){pageInfo{hasNextPage endCursor} nodes{updatedAt}}}}
#     commits(last:1){nodes{commit{statusCheckRollup{state contexts(first:100){
#       pageInfo{hasNextPage} nodes{... on CheckRun{name status conclusion
#       isRequired(pullRequestNumber:<N>)} ... on StatusContext{context state
#       isRequired(pullRequestNumber:<N>)}}}}}}}
# A later page of one PR's list, such as its labels:
#   pullRequest(number:<N>){ labels(first:100, after:"<endCursor>"){
#     pageInfo{hasNextPage endCursor} nodes{name}} }
# The one-PR update's conversation part, each post with its updatedAt:
#     reviews(first:100){...} reviewThreads(first:100){... comments(first:100){...}}
#     comments(first:100){...}
# The search for labels on PRs no bead owns, a page of 100, then on from endCursor:
#   search(type:ISSUE, first:100, query:"repo:<owner>/<name> is:pr label:\"status: working\",...")
#     { issueCount pageInfo{hasNextPage endCursor} nodes{... on PullRequest{number state}} }
gh api graphql -f query=@read.graphql
# The cost of a query before running it.
#   query{ rateLimit(dryRun:true){cost} ... }
gh api rate_limit --jq '.resources | {graphql, core}'
```
