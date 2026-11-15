---
name: Design — the landing order reads every PR it owns in one GitHub request and acts only on what differs
description: The design for tk-1tfzr71.150, the design child of initiative tk-1tfzr71.149, read at main 65a86b0e7, at integration/tk-1tfzr71.132 as its label-writer rework leaves it, at integration/tk-1tfzr71.22 0ccee97bf, and against Gas City upstream main 294079d53f. Each pass of the landing order reads every PR the city owns in one GitHub request per repository, compares it with the store, and acts only where the two differ, its labels included, with nothing recording an act that failed. It settles what makes a PR changed, what runs the targeted work, the saved read, the label comparison's reach and the label's other callers, the order's interval and bound, the composition with the review-lanes effort, what tk-1tfzr71.21 waits on, and the units the implementation child files. Read it to approve the design at its gate, or to build one of its units.
---

# Design: the landing order reads every PR it owns in one GitHub request and acts only on what differs

This is the design record for tk-1tfzr71.150, the design child of the
initiative tk-1tfzr71.149. The pack was read at main 65a86b0e7, the commit
`integration/tk-1tfzr71.149` was cut from. The PR-status effort was read at
`integration/tk-1tfzr71.132` 348540443 with the warrant of 1db69633c, which is
that branch as its rework (tk-52ow8z9) leaves it: the rework takes out unit 3
(tk-1tfzr71.146) and its fix (tk-vnqn510), the commits after 348540443 other
than the warrant. The review-lanes effort was read at `integration/tk-1tfzr71.22`
0ccee97bf, with its rework (tk-n5ye5vf) in flight. Gas City is cited by symbol
at `gastownhall/gascity` main 294079d53f, Gas Town by path at
`gastownhall/gascity-packs` main 0f07496d2f, and bd at `gastownhall/beads`
v1.3.4. GitHub was measured in this repository and, in aggregate, in the city's
other repositories on 2026-11-15 ([section 14](#14-facts-this-design-rests-on)).
The search behind the surface the units add is
[gas-city-search.md](gas-city-search.md).

## What the operator approves

Today the landing order reads up to 20 pending PRs a run, one at a time, in at
least five GitHub queries and about seven seconds each, and rewrites each PR's
bead whether or not anything changed. So its cost follows the number of PRs, and
a busy rig waits several runs for a change to show. A PR's labels are written by
calls each path has to remember, and keys remember a call that failed.

Approving this design gives the landing order one pass every 2 minutes that
reads every PR the city owns in one GitHub request per repository, compares what
it finds with the store, and acts only where the two differ:

- It saves the facts that changed on the PR's bead, so every display is current
  within one pass. A base branch that moves and changes every PR's merge state
  costs no extra request.
- It reads a PR in full only when its feedback moved or it reads ready to merge,
  and that read is the merge's own fresh read.
- It lands a PR that merged, sends back one at a new head, and gates the
  exceptions, as today.
- It corrects every label that differs from the one the store derives, on every
  PR the city owns and on the closed PRs that still carry one. Nothing records a
  write that failed: the next pass finds the difference and makes it again.

A pass in which nothing changed makes one request per repository, about 4 of
the hour's 5,000 GitHub points and 4 seconds, and writes no PR's bead.

Decisions to check, each settled here unless you say otherwise:

1. **One order.** The acts run in the same pass, after the compare, and start
   no later than 90 seconds into a run. A second order would have to read GitHub
   again, since Gas City passes nothing from one order to another, and a
   condition order's check would run every 30-second lane pass with nothing
   passed to its run ([section 2](#2-what-runs-the-targeted-work)).
2. **Every 2 minutes,** about 480 of the hour's 5,000 points for the city at
   today's 33 open PRs. Every minute doubles that
   ([section 7](#7-the-interval-and-the-bound)).
3. **Labels on both paths.** The comparison corrects the labels of every PR the
   city owns, so on a rig still on the old path it works beside `pr-facts.sh`
   until tk-1tfzr71.21 retires that ([section 4](#4-the-label-comparisons-reach)).
4. **No age on the displays.** A landing order that stops still leaves every
   display on its last facts with nothing marking them old. This effort does not
   add that display ([section 6](#6-the-age-of-a-displays-facts)).
5. **Where this departs from the sitting's wording:** the one request reads the
   PRs the city owns, open or not, rather than every open PR, and a search finds
   the rest that carry a label. "The landing order makes no label call" becomes
   "its merge path makes none". `pr_last_checked_at` moves only when the order
   writes the record. The living doc that says so is
   `docs/refinery-merge-cadence.md`, not the merge design's spec
   ([section 12](#12-what-the-gate-holds)).

## 1. What makes a PR changed

The comparison reads GitHub's side through one request per repository, the
pass's read, and never through a PR's `updatedAt`. Measured on 2026-11-15, a
check that finishes does not move `updatedAt`: on 5 of the 9 open PRs here the
last check finished 31 to 37 minutes after it. On #1529 it stopped six seconds
short of the last review in a burst. It also moves on every label write the city
makes, so it would mark the city's own writes as changes.

The pass's read has one aliased `pullRequest(number: N)` field for each PR the
city owns in the repository ([section 4](#4-the-label-comparisons-reach) says
which). Each field reads:

- **The PR's state:** its URL, number, repository, head branch, base, head,
  state, draft flag and merge state, its merge-queue flags, and for a merged PR
  its merge commit and time.
- **Its required checks at the head:** the latest run of each check in each
  suite, through `isRequired(pullRequestNumber: N)` at the field's own number,
  the shape of gctk's checks query today.
- **What tells that its feedback moved:** the newest review's id and the number
  of reviews, the newest conversation comment's id, which review threads are
  unresolved, and the review decision.
- **Its labels.**

A PR is changed when the pass's read differs from the read saved on its bead in
any of the first three. Labels are compared apart, against what the store
derives, so a label write is not a change.

Of the saved read's fields (`pr_github_read`, services/gctk/pr/read.go), the
pass's read returns the identity, head, state, draft flag, merge state and
required checks itself. It cannot return the approvers and requesters, the newest
feedback in each id space, or the review threads waiting on the city's answer,
because the definition of feedback and the approval rule read the text and the
author of every post. For those it returns what tells that they moved:

- **A review or an inline comment.** Every inline comment on the 9 open PRs here
  belongs to a review the PR's reviews list holds, the newest one to the newest
  review, and on merged #1488 each reply in a thread carries a review of its own.
  So a review or an inline comment moves the newest review's id, or the number of
  reviews when its review was started before another and submitted after it.
  Such a review can sit behind the other in the list: a person's review here
  stays unsubmitted for up to 15 minutes, and the list's order for one was not
  observed.
- **A conversation comment.** The newest conversation comment's id moves.
- **A thread a person resolves or reopens.** The set of unresolved threads moves.
- **An approval dismissed.** The review decision moves.

An edit of a post's text moves none of them, as no receipt today keys on edits.
When any of them moved, the comparison takes the PR's whole read
([section 3](#3-the-saved-read)).

A PR whose checks or threads overflow the read's page, shown by `hasNextPage`,
counts as changed, and its whole read pages them.

## 2. What runs the targeted work

One order runs it: the landing order (`orders/pr-reconcile.toml`, `gctk pr
reconcile`). Each run reads, compares, then acts within a budget:

1. **Read the store in one listing** of every live bead
   (services/gctk/listing). It gives the PRs the city owns, the pending records,
   each record's store side and each owner's saved read. This rig's 877 live
   beads list in 0.45 s.
2. **Read GitHub once per repository,** the pass's read, with the label search
   as a second root field of the same request
   ([section 4](#4-the-label-comparisons-reach)).
3. **Compare in memory and write nothing.** For each record it computes the act
   the store and GitHub's side imply, the same decision a check makes today, with
   GitHub's side taken from the pass's read and the saved read.
4. **Act, one record at a time under the record lock,** each act guarded on the
   status and assignee read under it, as today. The order is store-only acts,
   then lands, requeues and exceptions, then the saved read's state where it
   differs, then whole reads and merge requests, then labels, over a second
   listing that sees those writes ([section 4](#4-the-label-comparisons-reach)).
   Within each kind the record least recently checked goes first. No act starts
   after 90 seconds. An act not reached stays a difference, and the next pass
   finds it.

Measured costs:

| Pass | GitHub | Writes to PRs' beads | Time |
|---|---|---|---|
| Nothing changed | 1 request per repository, about 4 points here | none | about 4 s |
| A base move changes N PRs' merge state | the same request | N saved reads, and a label write for each PR whose derived label changed | 4 s plus the writes |
| M PRs' feedback moved | the request, plus M whole reads of six calls and about 5 points each | M | about 4 s plus 4.4 s and a write each |
| Today, per run | up to 20 whole reads | up to 20 | up to about 140 s |

The other two candidates fail on facts of Gas City as shipped (gas-city-search.md,
"What runs the pass"):

- **A condition order whose check is the comparison.** Its check runs on every
  lane pass, about every 30 seconds, and `interval` is ignored, since the
  condition case calls `checkCondition` with no cooldown. The check's output goes
  to `io.Discard`, so the run would read GitHub again. The check is skipped while
  a run is open. Its timeout defaults to 10 seconds, and a slow check delays
  every order in the pass.
- **A second order.** Gas City has no queue a pack can hand mechanical work to,
  and no order starts another. A second order would read GitHub again to find
  its work, or read a second copy of GitHub's state stored for it, which
  tk-1tfzr71.21's done criteria rule out.

So the operator's asynchrony comes from the shape of one pass. The pass reads
before it acts and acts only on differences. Its acts are bounded, so the next
read is never more than one interval and one budget away. Work it leaves is a
difference, never a queue entry.

Gas City closes a run's tracking bead two minutes after it is made, whether or
not the run still works (`runOrderTrackingSweepWatchdog`, stale after
`orderTrackingSweepWatchdogStaleAfter`). A run past two minutes can therefore
overlap the next. That stays safe: each act is taken under the record lock and
decided again from the bead as the lock reads it, and an act that is already done
is no difference.

Gas Town's marker keeps its meaning. A record carrying `pr_reconcile_pending`
gets the merge's acts: the merge request, the landing, the requeue and the
exceptions. The order clears the marker when the record owes no further run, as
today. A PR whose record has lost the marker, such as one behind an exception's
gate or back with the refinery, still has its saved read refreshed and its labels
corrected, and gets none of the merge's acts.

`pr_last_checked_at` is written by each write the order makes to a record, and a
pass that changes nothing writes it nowhere. Gas Town's command writes it at
every check (`gastown/commands/pr-merge-reconcile/run.sh`), so here it says when
the order last wrote the record. It still orders the acts a pass owes, least
recently checked first.

## 3. The saved read

A changed PR's saved read is refreshed from the pass's read wherever that read
holds the field. Only a PR whose feedback moved, or that reads ready to merge,
takes the whole read it takes today (`observe`: the PR, its check suites,
reviews, login, review threads and conversation comments).

- **Every field the pass's read holds** is written from it when it differs: the
  identity, head, state, draft flag, merge state and required checks. A base move
  or a check that finishes is saved within the pass that sees it, at no extra
  request, however many PRs change.
- **The feedback part,** the approvers, requesters, newest feedback, threads
  waiting on the city and the provenance instant it applied, is written only by a
  whole read. The saved read keeps beside it what the pass's read showed of the
  feedback when that whole read was made, so the next pass can tell whether it
  moved.
- **`read_at` is the time of the read that last changed it.** A pass that finds
  nothing changed leaves the saved read as it is, so `read_at` no longer tells
  when GitHub was last looked at ([section 6](#6-the-age-of-a-displays-facts)).

The two parts stay one key with one writer, the landing order, in the write that
records each act. Each part is current as of the last pass: the state part was
read by it, and the feedback part is confirmed by the comparison of what tells
that it moved.

A required check is told from the others by aliasing one `pullRequest` field per
PR, each passing its own number to `isRequired`. Measured: one request read
11 PRs, 9 open and 2 merged, with each one's required checks, its labels and the
signs of moved feedback. It cost 3 points and took 2.7 to 3.2 seconds over three
runs. The repository's open-PR list cannot do this, because `isRequired` takes
the PR's number and a list passes no argument per node. The same request returns
a merged PR's merge commit and time. So a PR that left the open list needs no
read of its own to tell a merge from a close. That is the reason the landing
order reads each PR by its number today
([refinery-merge-cadence.md](../../docs/refinery-merge-cadence.md#the-landing-order)).

The merge still acts only on a fresh read made in its own run. A record whose
decision over the refreshed saved read reads ready, or whose feedback moved, gets
the whole read under the record lock (`Ready`, as `decide` makes it today). The
evaluator decides over that read, and the merge request is pinned to the head it
judged. A merge, a landing and a requeue decide from reads made in the same run,
never from a saved read alone.

Batching the whole read was measured too: one aliased request read 9 PRs whole,
reviews, threads and comments included, in 3.93 seconds for 18 points, against
4.36 seconds and about 5 points for one PR today. This design does not build it.
The whole read runs only on a change of feedback, which people make, or for a PR
that reads ready. At today's counts a pass's whole reads fit its budget.

## 4. The label comparison's reach

The comparison reaches every PR whose label can be wrong through the same
request:

- **The PRs the city owns,** through the pass's read. A PR is owned when a live
  bead names it as its own and is no other bead's child: its anchor, which names
  it in `pr_url` with a `merge_result`, or a bead the refinery sent back to the
  pool, which names it in `existing_pr`. This rig's 11 live beads that name a PR
  are its 9 anchors and 2 rework children. Each open PR has one anchor.
- **Every other PR that carries a `status:` or `held:` label,** through a search
  of the repository for either family in either state
  (`is:pr label:"status: working",...`). On 2026-11-15 it found 527 closed PRs
  here, all closed before 2026-10-30, and none closed since. It costs 1 point for
  a page of 100.

What the store derives for each:

| The PR | The labels |
|---|---|
| owned, open, its bead on the pending record | the status and `held:` values `gctk pr status` gives the bead, rendered over the evaluator's answer from the saved read and the store |
| owned, open, its bead on the old path | the values `gctk pr status` gives the bead from the facts its keys hold |
| owned, merged or closed | none: GitHub's own state takes over |
| owned by no live bead, open or closed | none: the city works no such PR |

The derivation is `prstatus`, the one `gctk pr status` runs for a single bead and
the rig board runs for all of them. It runs after the acts, over a second listing
of the store, so it sees what the pass wrote. The labels compared are those the
pass's read returned, which no write in the pass has changed.

Each difference is written through the label's one writer,
`assets/scripts/pr-status-label.sh`, with the verbs it has:

- `reconcile` for an owned open PR, passing the labels the pass read as
  `--current-labels`.
- `clear` for any other PR.

A PR found by the search is cleared without `--current-labels`, so the writer
reads its labels itself and a stale search index costs a read, never a wrong
write. A write that does not land is left as it is. The next pass derives and
compares again, and no key or marker records it.

The first pass over the closed PRs runs at a pace. A pass clears at most 10 PRs
the store does not own, so the 527 here clear in about 53 passes, an hour and
three quarters at 2 minutes. Each clear reads the PR's labels and then edits
them. If one `gh pr edit` makes about four GraphQL requests at a point each, the
300 clears an hour cost about 1,500 of the hour's 5,000 points, under a third of
the allowance. The edit's cost is gh's and is not measured here, so the unit
measures it on its first clear and sets the per-pass count to hold that share.
PRs the city owns have no cap: they are few, and their labels are what the
operator reads.

An open PR that no live bead owns loses the city's labels. One open between
`pr-open.sh`'s create and its record of `pr_url` can lose its first label for one
pass, and the next pass writes it back.

## 5. The label's other callers

Once the comparison corrects every label, each other call is a write the next
pass would make anyway. While it stands it shows a change at once, and the
comparison corrects what it misses or fails. Every one of them is in code a
scheduled bead retires, so none changes here (AGENTS.md, rule 1):

| Caller | Its calls | What becomes of it |
|---|---|---|
| `pr-facts.sh` | its full pass's `reconcile`, and its clear at a merge or a close with `status_label_clear_owed` | retires with tk-1tfzr71.21 (tools/deletion-plan.tsv) |
| `gctk merge` | its clear at a merge, with `status_label_clear_owed` | retires with tk-1tfzr71.70 (docs/built-once-target.md, lane A) |
| `pr-open.sh` | `reconcile` at its create, its adoption and its draft-to-ready arm | its create and its adoption, which each move an anchor from `pre_open_gate` to `pull_request` on the old path, retire with tk-1tfzr71.70 and that path's transition machine, and its arm with the merge cadence (tk-1tfzr71.21) |
| `signoff.sh` | `reconcile` after a verdict | retires with tk-1tfzr71.122 by the deletion plan on `integration/tk-1tfzr71.22` |

`status_label_clear_owed` retires with its two writers, and the comparison clears
what it would have retried. The landing order's merge path makes no label call.
The pass's comparison is the label's one caller once those retirements land.
`pr-status-label.sh` stays the labels' one writer, with their families, values,
colours and descriptions, and unit 2 rewrites its header's account of who calls
it.

## 6. The age of a display's facts

This effort does not carry it, for three reasons:

- No display or doctor check reads a saved read's age today. At
  `integration/tk-1tfzr71.132` 348540443 the only reader of a check's time is
  `due`'s ordering, and the rig board's `read_at` is the board's own read of the
  store. So `read_at` turning into the time of the last change, rather than of
  the last look, removes nothing a reader uses.
- The age a display needs is the landing order's last pass that read GitHub, and
  Gas City records every run already: a tracking bead per run with its outcome
  label, and `order.failed` with the tail of a failed run's output
  (gas-city-search.md, "What runs the pass"). Showing it is a board's change over
  those records, for every order the displays depend on, not this order's change.
- The operator gave no ruling on the work the sitting offered, and none of this
  design's acts needs it.

Until a display shows it, a landing order that stops, or whose read of GitHub
fails, leaves every PR display on its last saved read, as today. A failed read
exits non-zero, which Gas City records as `order.failed`. Funding the display is
the operator's call at this gate. It would be one board unit over Gas City's run
records, which the implementation child files only if the operator asks.

## 7. The interval and the bound

The order runs every 2 minutes (`interval = "2m"`), with its 300-second timeout.
No act starts after 90 seconds (`--budget 90s`), so a run normally ends before
Gas City's watchdog would let the next one start beside it.

The bound on records per run goes (`--count`). A run decides every record from
one listing and reads every owned PR in one request, so no record waits for a
later run to be looked at. The one count left is the 10 clears a pass of PRs the
store does not own ([section 4](#4-the-label-comparisons-reach)).

What the interval costs, at the city's six repositories and 33 open PRs measured
on 2026-11-15:

| Interval | Points an hour for the passes' reads | Tracking beads a day per rig |
|---|---|---|
| 1 minute | about 960 | 1,440 |
| 2 minutes | about 480 | 720 |
| 5 minutes, today's interval | about 190 | 288 |

The read costs about a quarter point per owned PR (3 points for 11). The search's
page adds about 1 point per repository, and a repository with no owned PR pays the
search alone. Gas City keeps a closed tracking bead 7 days by default
(`[beads.policies.order_tracking]`). Its cooldown index reads the newest 256 runs
per store, and an order whose last run falls outside that window pays one more
read, which the index then remembers (`orderTrackingHistoryIndexLimit`). So a
2-minute order costs the store rows, not other orders' timing. The interval is
tuned from city.toml (`[[orders.overrides]]`).

## 8. The review-lanes effort

tk-1tfzr71.22 (PR #1531, `integration/tk-1tfzr71.22`) rewrites the landing order's
check. At 0ccee97bf it reads the bead's blockers, withdrawals and review runs in
`one`, carries a withdrawal across a requeue, and pours a review run for a head
with no passed result. It marks a draft ready once a run has passed, and
dismisses an approval a material change withdraws. That touches
services/gctk/pr/landing.go, pr/record/record.go, pr/record/keys.go and
services/gctk/prstatus, and its rework (tk-n5ye5vf) is in flight under the brief
of conversation tk-9p5oh6j. That brief keeps the run's structure and features,
takes the prepare and record steps out of the review formula, and leaves the
record's final shape for the rework to name in its PR summary.

Each of those acts becomes one more case of the record's decision in
[section 2](#2-what-runs-the-targeted-work). The decision reads the store side
the effort adds (results, asks, runs and withdrawals) and GitHub's side from the
pass's read and the saved read. A record whose decision names one of the acts
gets it under the lock. Each act keeps its own GitHub write pinned to the head it
names, as that branch builds it: the ready mark, a dismissal, the compare a
withdrawal makes. So a review run's result, a filed ask or a withdrawal reaches
its act within one pass, with no change on GitHub needed to start it.

| Unit | Composes with tk-1tfzr71.22 | Waits on |
|---|---|---|
| 1, the pass | rewrites the functions that branch rewrites, so it is built on that branch as it lands on main, and its acts join the decision as above | tk-1tfzr71.22 and tk-1tfzr71.132 landing on main |
| 2, the labels | derives labels through `prstatus` as that branch leaves it, with the review run's state in the `review` condition and the failed machinery's `needs-attention` | unit 1, and tk-1tfzr71.132 while it is open |

Building unit 1 after both efforts land composes their code once, on main, rather
than in a merge of three branches that each rewrite `blocked` and `decide`.

## 9. What tk-1tfzr71.21 needs

tk-1tfzr71.21 waits on the whole effort, tk-1tfzr71.149, and not on one unit of
it. Its retirement of `pr-facts.sh` lands on main, and the label comparison
(unit 2) reaches main only with this effort's landing PR. An edge onto unit 2
would release the retirement while main still lacks the comparison. Its design
need not wait, since it is armed on mol-design-convoy.

The two efforts build one read of GitHub. This effort owns it: the pass's read of
every PR the city owns, and the saved read on each PR's bead. tk-1tfzr71.21's
intake reads from it. When the saved read shows feedback past what the bead's
receipts hold, intake routes the posts behind it, the act the merge design moves
into the landing order's run. Its own read of a post's text is then that act's
read. A review started before another and submitted after it can sit below the
newest id ([section 1](#1-what-makes-a-pr-changed)), so neither that test nor
the receipts can rest on the newest id alone.

This effort leaves to intake:

- routing feedback into work, with its receipts and watermarks;
- the red-check and conflict routing, which tk-1tfzr71.21's description gives to
  Gas City's PR monitor and its repair beads;
- the webhook.

Gas City's monitor lists open PRs with no labels, review decision or
`isRequired`, so it cannot stand for this read (gas-city-search.md, "The read of
GitHub").

## 10. The units

Each unit leaves the city working, and each waits on tk-1tfzr71.132 while that
bead is open.

| # | Unit | What it builds | Settles | Waits on |
|---|---|---|---|---|
| 1 | feat(gctk): have the landing order read every PR it owns in one request and act only on what differs | The pass's read in gctk's GitHub adapter (one aliased request per repository, with `isRequired` per PR and the label search as a second field). The saved read's state part written from it, and what tells that feedback moved kept beside the feedback part. The run reads the store once and GitHub once per repository, decides each record in memory, and acts under the lock only where the decision names an act, with the whole read only for moved feedback or a PR that reads ready. Every owned PR on the record is observed, marker or not. The order runs every 2 minutes with `--budget 90s` and no `--count`. `pr_last_checked_at` is written only by a write the order makes. The docs the behavior changes: refinery-merge-cadence.md's landing order, state-machine.md's pending record, gctk-architecture.md, services/gctk/README.md, the order's header, the saved read's warrant and key registry entry, and docs/architecture.md's Debt entry, narrowed to saying that the order writes no label. | questions 1, 2, 3 and 7 | tk-1tfzr71.132 and tk-1tfzr71.22 |
| 2 | feat(gctk): keep each PR's status labels equal to what the store derives | The comparison over every PR the city owns and every PR the search finds, written through `pr-status-label.sh`'s `reconcile` and `clear`, at most 10 clears a pass of PRs the store does not own, with nothing recording a write that failed. The landing order's merge path makes no label call. `pr-status-label.sh`'s header names the comparison as its caller. docs/architecture.md drops the Debt entry this design adds. | questions 4 and 5, tk-1tfzr71.91, and the label half of tk-1tfzr71.140 | unit 1, and tk-1tfzr71.132 while it is open |

Unit 1 changes no label, so between the two units the labels stand as they do on
main after tk-1tfzr71.132: the old path's writers keep theirs, and a PR on the
pending record keeps its last label at a merge, a close or an exception, as the
operator accepted for that effort.

## 11. Edges and notes the implementation child adds

- **Unit 1:** `blocks` edges onto tk-1tfzr71.132 and tk-1tfzr71.22.
- **Unit 2:** `blocks` edges onto unit 1 and onto tk-1tfzr71.132.
- **tk-1tfzr71.91** (a merged or closed PR keeps its label): move its `blocks`
  edge and its arm on mol-validate-close from tk-1tfzr71.149 onto unit 2. Append
  a close brief: once unit 2 lands, check that a PR the landing order records
  merged or closed ends with no `status:` or `held:` label, that the landing
  order's merge path makes no label call, and that a clear that failed is made by
  a later pass.
- **tk-1tfzr71.140** (a stood-down exception's PR stays open and labeled): move
  its `blocks` edge and its arm on mol-polecat-work from tk-1tfzr71.149 onto
  unit 2. Append a note: unit 2 takes the city's labels off an open PR whose bead
  has closed, since no live bead owns it, so the label half of its Done is
  settled there, and it builds only the other half: standing work down leaves no
  PR open behind the closed bead.
- **tk-1tfzr71.21:** no edge, so its design can start. Append a note: the unit
  that retires `pr-facts.sh` waits on tk-1tfzr71.149, the landing bead, by a
  `blocks` edge its implementation child adds. Its intake reads the pass's read
  and the saved read this effort lands ([section 9](#9-what-tk-1tfzr7121-needs)).

## 12. What the gate holds

The initiative's proposed done criteria, as this design holds them. Where the
wording moved, the reason follows.

1. For every PR the city owns, a change on GitHub to its state, head, draft flag,
   merge state, required checks or review decision reaches the saved read within
   one pass, however many PRs are open or change at once. A change to its
   feedback, a review, a comment or a thread's resolution, reaches it within one
   pass for as many PRs as one pass's budget reads, and the rest in the passes
   after. *(The feedback read is per PR, so its count, not the open count, can
   span passes.)*
2. A pass in which nothing changed makes one GitHub request per repository and
   writes no PR's bead. Gas City still writes its tracking bead for the run.
3. A PR's labels on GitHub are the ones the store derives, and a label that
   differs for any cause is corrected by a later pass, with nothing recording
   that it was owed.
4. The landing order's merge path makes no label call, and the pass writes a
   label only where it differs. *(The sitting's "the landing order makes no label
   call": the comparison is a step of the landing order's pass, which is the one
   read of GitHub it compares against.)*
5. The merge acts only on a fresh read made in its own run.
6. docs/architecture.md, docs/built-once-target.md and
   docs/refinery-merge-cadence.md say so. *(The sitting's "the merge design": a
   spec records one moment, so the living doc that owns the landing order's
   runtime says it. docs/architecture.md states only the responsibility the
   landing order takes on, that it observes every PR the city owns and
   maintains each one's labels. How the order carries it out belongs in the
   runtime doc.)*

## 13. Pages this design changes

This change states the target in two living pages, and the units bring the rest
current as they build:

- **docs/architecture.md:** a decision that the landing order observes every PR
  the city owns and maintains each one's labels, and a Debt entry for the
  landing order as built. Unit 1 narrows that entry and unit 2 drops it.
- **docs/built-once-target.md:** a difference from Gas Town under Merge, one read
  a pass for every PR, with its reason.

Both edits sit outside the hunks `integration/tk-1tfzr71.132` and
`integration/tk-1tfzr71.22` change in those pages, so either effort's landing
merges them without a conflict.

## 14. Facts this design rests on

Measured on 2026-11-15 with `gh api graphql` from the city's account. The query
texts are in the commands below.

- **The pass's read.** One request with one aliased `pullRequest(number: N)` per
  PR read 11 PRs, #1521 to #1532 less #1522 (9 open, 2 merged), with each one's
  state, required checks by `isRequired(pullRequestNumber: N)`, labels, newest
  review and conversation comment, unresolved threads and review decision, and
  the merged PRs' merge commits. Cost 3. Time 3.24, 2.91 and 2.71 seconds.
- **The number of reviews.** The same request with `totalCount` on each PR's
  reviews and `pageInfo` on its threads cost 3, with no errors, in 2.95, 2.72
  and 2.82 seconds. Over 552 reviews on 60 merged PRs here, a person's review
  was submitted up to 15 minutes after it was started, and no review sat out of
  the order of its id, its creation or its submission. So where the list puts a
  review started before another and submitted after it was not seen.
- **The open list.** `repository.pullRequests(states: OPEN, first: 100)` with
  labels, newest review and comment, threads and check contexts read 9 PRs in
  2.16 s for 6 points. Run against each of the city's six repositories it found
  33 open PRs, 0 to 15 each, in 0.6 to 4.3 s, at 6 points each.
- **The whole read, batched.** 9 PRs with reviews, threads and their comments,
  conversation comments and check suites with `isRequired`, in one aliased
  request: 3.93 s, 18 points, no errors.
- **The whole read today.** gctk's five queries (services/gctk/internal/gh/gh.go)
  and the REST login for #1531: 4.36 s.
- **`updatedAt`.** On #1524, #1525, #1527, #1528 and #1530 the last check
  finished 31 to 37 minutes after it. On #1529 it read 11:52:00Z, and the newest
  review was submitted at 11:52:06Z.
- **Inline comments.** On the 9 open PRs, every inline comment's review is in the
  PR's reviews list, and the newest inline comment's review is the newest review.
  On merged #1488, each reply in a thread carries a review of its own.
- **The search.** `search(type: ISSUE, query: "repo:<this repo> is:pr is:closed
  label:\"status: working\",...")` over the four `status:` and four `held:`
  values: 527, newest closed 2026-10-29T23:13:50Z. With `closed:>=2026-10-30`: 0.
  Cost 1, about 1 s.
- **The store.** `gc bd list --json --limit 0` listed this rig's 877 live beads
  in 0.45 s. Of them, 11 name a PR: 9 anchors with `merge_result=pull_request`
  and 2 rework children with `anchor_bead`. None is on the pending record, and
  none carries a saved read.
- **The allowance.** At 21:24:44Z the account had used 282 GraphQL points in an
  hour that resets at 22:16:27Z, and 826 REST calls in one that resets at
  22:13:02Z, of 5,000 each.

The read of the order, at `integration/tk-1tfzr71.132` 348540443:
`orders/pr-reconcile.toml` (5-minute cooldown, 300-second timeout), `Reconcile`,
`due`, `one`, `blocked`, `decide` and `observeAlone` in
services/gctk/pr/landing.go, `observe`, `decide` and `FromStore` in
services/gctk/pr/read.go, and `Listing.PRAnswers` in services/gctk/listing/pr.go.
Gas City's facts are in [gas-city-search.md](gas-city-search.md).

```bash
# The pass's read: one aliased field per PR the city owns.
#   p<N>: pullRequest(number:<N>){ number url state isDraft headRefName headRefOid
#     baseRefName mergeStateStatus isInMergeQueue isMergeQueueEnabled mergedAt
#     mergeCommit{oid} reviewDecision labels(first:20){nodes{name}}
#     reviews(last:1){totalCount nodes{fullDatabaseId}}
#     comments(last:1){nodes{fullDatabaseId}}
#     reviewThreads(first:100){pageInfo{hasNextPage} nodes{isResolved}}
#     commits(last:1){nodes{commit{oid checkSuites(first:20){pageInfo{hasNextPage}
#       nodes{checkRuns(first:50,filterBy:{checkType:LATEST}){pageInfo{hasNextPage}
#       nodes{name status conclusion isRequired(pullRequestNumber:<N>)}}}}}}} }
gh api graphql -F query=@state.graphql
# The allowance, at no cost.
gh api rate_limit --jq '.resources | {graphql, core}'
```
