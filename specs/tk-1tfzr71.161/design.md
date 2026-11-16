---
name: Design — GitHub intake moves into the landing order's one read, and pr-facts.sh retires
description: The design for tk-1tfzr71.161, the design child of initiative tk-1tfzr71.21, read at main 713e3a733, at the landing-order design in PR #1533's head 4d796d181, and against Gas City upstream main 76a06b2327 and gascity-packs main 0f07496d2f. A person's review, inline comment or conversation comment on a city PR becomes one ask on the PR's bead in the landing order's pass that reads it, the city's marks on GitHub are the receipts, the review run's round that rules each post answers it where it was made, and red checks and conflicts are acts of the same pass. It settles the read the intake works from, the receipts, the form of a person's comment, red checks and conflicts, the webhook, the write-back, the old path, the cadence's arms, the keys pr-facts.sh writes, what each held note and bead becomes, the comparison before the retirement, and the units the implementation child files. Read it to approve the design at its gate, or to build one of its units.
---

# Design: GitHub intake moves into the landing order's one read, and pr-facts.sh retires

This is the design record for tk-1tfzr71.161, the design child of the
initiative tk-1tfzr71.21. The pack was read at main 713e3a733, which is the
commit `integration/tk-1tfzr71.21` points at. The landing order's one pass per
interval was read in its design, `specs/tk-1tfzr71.149/design.md` at the head of
PR #1533 (4d796d181), which awaits the operator: this design builds on that pass
and changes with it if the operator's ruling changes it. Its files sit on that
PR's branch until it lands, so the links to them here resolve once it does. Gas City is cited by
symbol at `gastownhall/gascity` main 76a06b2327 (2026-11-16T03:05:19Z), the
packs by path at `gastownhall/gascity-packs` main 0f07496d2f, and the city's
stores and repositories were read on 2026-11-16
([section 15](#15-facts-this-design-rests-on)). The search behind the surface
the units add is [gas-city-search.md](gas-city-search.md).

## What the operator approves

Today one script (`pr-facts.sh`, 5,780 lines with an 8,188-line test) runs
three times in every one-minute pass of the merge cadence. It reads every open
PR's reviews and comments, copies what it finds onto each PR's bead in keys
only the pack's scripts parse, routes comments into rework children, findings
and validation passes, and answers on GitHub in a separate sweep. Approving
this design replaces it for every PR on Gas Town's pending record:

- **Each comment a person leaves becomes one ask on the PR's bead,** filed in
  the landing order's pass that first reads it, and the city marks the comment
  👀 on GitHub. The review run rules it as it rules any ask: it fixes it,
  declines or defers it with a reason, answers it, or asks you through a gate.
  The round that rules it answers the comment where it was made, with a reply
  in an inline comment's thread and the thread resolved, or a 👍 where nothing
  more is owed. A question stays open until you answer it, and a later comment
  that answers it closes its gate.
- **The city's marks on GitHub are the receipts.** A comment is taken once it
  carries the city's 👀 or 👍. No counter or ledger on the bead decides what
  was routed, so a review you submit after starting it, which GitHub gives an
  older id than a newer post, is still taken.
- **An approval's own message is read like any comment,** so "approved, but
  rename X" is fixed before the merge.
- **A PR whose comments the city is working reads working,** approved or not.
  Today an approved one reads merging.
- **A red check and a conflict are acts of the same pass,** from the read it
  already makes of each PR's merge state and required checks: an ask to fix a
  check that failed, one re-run of a check that failed for a cause no code
  fixes, an ask to merge the target into an approved PR that conflicts, and a
  gate only where the city cannot go on. A red-check gate is withdrawn once the
  checks pass.
- `pr-facts.sh`, `review-answer.sh`, three arms of the merge cadence and a
  doctor check are deleted once every rig has moved onto the pending record,
  by a retirement bead of their own.

Decisions to check, each settled here unless you say otherwise:

1. **No Gas City PR monitor and no repair beads.** The landing order's read
   already holds each PR's merge state and which of its checks are required,
   which the monitor cannot tell. The monitor would read every open PR a
   second time and file a repair bead that a pool claims, so a second writer on
   the branch, for every PR GitHub reads BLOCKED, one waiting on your approval
   included ([section 4](#4-red-checks-and-conflicts)).
2. **No webhook.** GitHub can reach the city only through a public route, and a
   public hook may start only a formula order, which wakes an agent. It would
   save at most the two minutes between passes. Opening one is your call: it
   exposes the hook's path on the city's API to the internet, guarded by
   GitHub's signature, and needs a secret in your environment
   ([section 5](#5-the-webhook)).
3. **One ask per comment,** rather than one per batch, so each comment has its
   own answer and its own close, and triage can later answer one alone
   (tk-ileeqzz, held for your placement). A review with ten inline comments
   files ten asks, worked in one run. Until triage can answer a comment by
   itself, a comment that asks for nothing still costs a review run, as it does
   today, and so now does an approval that carries a message, such as "looks
   good", which today's intake never reads.
4. **The city stops dismissing your request for changes.** Today it dismisses
   it once every point you raised is answered, and asks for your review again.
   Your request now stands until you approve or dismiss it, as the merge
   design's approval rule says, and the city still asks for your review again.
5. **The retirement comes last.** It waits on every rig's move onto the
   record, on the landing-order effort (tk-1tfzr71.149) and on the old merge
   path's retirement (tk-1tfzr71.70). The merge cadence's driver, its pacing
   and the review-dismissal helper keep serving the old review path, so their
   deletion moves to that path's retirement (tk-1tfzr71.122)
   ([section 8](#8-the-cadence-and-its-order)).
6. **Where this departs from the bead's description:** it names Gas City's PR
   monitor, its repair beads and the webhook receiver as the intake, and this
   design builds the intake on the landing order's one read instead, for the
   reasons in decisions 1 and 2. It compares the two paths once over every open
   PR's whole history in every rig, rather than side by side on one rig over a
   window ([section 11](#11-the-comparison-before-pr-factssh-retires)).

## 1. The read the intake works from

The intake reads GitHub only through the landing order's pass, which
tk-1tfzr71.149 builds: one request per repository that reads every PR the city
owns, and a whole read of a PR only when what it found there moved
([that design's sections 1 to 3](../tk-1tfzr71.149/design.md#1-what-makes-a-pr-changed)).
It adds no request to the pass: its other GitHub calls are its acts, each made
only where an act is due.

- **The pass's read** holds, for each owned PR, its state, its required checks
  at the head, its labels, and the signs that its feedback moved: the newest
  review's id, the number of reviews and of dismissed reviews, the newest
  conversation comment's id, the unresolved threads and the review decision.
  The intake adds each check suite's status and creation time at the head, two
  fields on nodes the read already returns, for the check that never reports
  ([section 4](#4-red-checks-and-conflicts)).
- **The whole read** (`observe` in `services/gctk/pr/read.go`) reads the PR,
  its check suites, its reviews, the city's login, its review threads and its
  conversation comments. The intake adds the city's reactions on each review
  and each conversation comment (`reactionGroups { content viewerHasReacted }`),
  which it reads on inline comments already (`commentFields` in
  `services/gctk/internal/gh/gh.go`).
- **When the whole read runs.** It runs where tk-1tfzr71.149 runs it, for a PR
  whose signs moved or that reads ready to merge, and also for a PR whose saved
  read lists feedback the city has not taken
  ([section 2](#2-the-receipts)). The second case is how a take that did not
  land is retried.
- **The intake's act** runs in the same run, under the record lock the run
  already holds for the record, on the whole read it just made and before the
  merge decision. It takes each feedback post the read shows untaken
  ([section 3](#3-a-persons-post)), then writes the saved read with the posts
  it left untaken. The merge decision counts both the untaken posts and the
  asks just filed, which block the bead, so no run merges over a post it has
  not taken.
- **Budget.** The takes are acts under tk-1tfzr71.149's 90-second budget. A
  post a run does not reach stays untaken in the saved read, and the next pass
  takes it. Work left is a difference, never a queue entry.

**A review that sits below the newest id.** A person can start a review, see
another post land, and submit the review afterwards. GitHub gives the review
and its inline comments ids from when they were started, so they can sit below
the newest id. The pass's read counts the PR's reviews, and the late review
raises the count without moving the newest id, so the PR reads as changed and
takes the whole read ([tk-1tfzr71.149's section 1](../tk-1tfzr71.149/design.md#1-what-makes-a-pr-changed)).
There the review and its comments carry no mark of the city's, whatever their
ids, so the intake takes them. No receipt is a high-water mark, so nothing can
fall below one.

**The pass alone loses no feedback.** Each pass compares what GitHub shows now
with what the store last saved, so an event the city never received costs
nothing: the next pass reads its result. A post the city did not take stays
listed in the saved read until its mark lands. A read that fails changes
nothing, and the next pass reads again. What no pass reads is an edit of a
post's text, as today: a person who adds a request by editing an old comment
is not re-read, and a new comment is.

## 2. The receipts

A post is taken when it carries one of the city's two marks, which the
definition of feedback reads:

| Mark | Put by | Says |
|---|---|---|
| 👀 (`EYES`) | the intake, once the post's ask is filed | the city has the post and owes it an answer |
| 👍 (`THUMBS_UP`) | the review run's rule-and-repair step, in the post that answers its round, once it rules the post's ask with nothing more owed | the city owes the post nothing more |

A feedback post that carries neither is **untaken**. The definition stays one
copy, in `assets/scripts/pr-post.sh`, which gctk reads through its feedback
adapter. `gc_city_handled` already reads the 👍 there, and unit 1 adds
`gc_city_taken` beside it for the 👀. A mark is the reader's own reaction
(`viewerHasReacted`), so it reads the city's account without a login read of
its own.

What reads the receipts:

- **The evaluator.** The saved read's feedback part keeps `untaken`, the ids of
  the feedback posts the act left with no mark, in each id space, in place of
  the newest feedback id in each. The evaluator's feedback condition
  (`unhandled` in `services/gctk/pr/feedback.go`) becomes one condition for
  each untaken post, and the pass gives a PR whose saved read lists any a whole
  read. The review threads waiting on the city's answer stay as they are
  (`awaiting`, through `gc_thread_awaits_answer`).
- **The approval withdrawal.** `unrouted` (`services/gctk/pr/feedback.go`,
  through `services/gctk/pr/withdraw.go`) becomes the inline comments carried
  by the approvals the withdrawal would dismiss that are feedback and untaken,
  read in the withdrawal's own read. So a withdrawal still waits until the
  intake has taken every comment a dismissal would retire.
- **The approving review's message.** `countedReviewStates` gains `APPROVED`,
  so an approval that carries text is a post like any review's
  ([the merge design's section 3, case 1](../tk-1tfzr71.66/design.md#3-how-an-approval-behaves-when-the-pr-changes)).

**Why marks on GitHub, not keys on the bead.** The mark is the city's own act
on the post, read in the same read as the post, so the receipt and what it
receipts cannot drift apart, and the operator sees on the PR which comments the
city has. A key on the bead that listed the posts the city took would keep a
second record of the PR's posts in bead metadata, which this initiative's Done
rules out. A watermark cannot record a post that arrives below it, which is the
late review's case. The ask names its post too, and finding it again by its
reason is the backstop when a mark did not land
([section 3](#3-a-persons-post)). The ask is not the receipt, because a display
decides over the saved read alone
([tk-1tfzr71.134's design](../tk-1tfzr71.134/design.md)), and the mark is on
the post that read holds.

**The provenance instant stays.** `pr_provenance_since` is the instant before
which an unmarked post under the city's login is the city's own: posts made
before the city marked its posts. It records when the city first read the PR,
an act of the city's that GitHub holds nowhere. Its writer moves from
`pr-facts.sh` to the landing order, which stamps it in the write that saves its
first whole read of a PR whose bead lacks it. While the city's login does not
resolve, the whole read fails and nothing is taken (`Login` in
`services/gctk/internal/gh/gh.go` refuses an answer with no login), so no post
is read as the city's own on a misread.

**The receipts a rig's move brings.** A bead the old path routed carries
`pr-facts.sh`'s receipts: the watermarks, the answered marks and the batch
ledgers. Its first whole read on the record converts them. The intake puts the
city's 👀 on every feedback post at or below those marks, resolves each
unresolved thread that holds only the city's own posts (the old path's machine
findings, which the cutover closed), files the post of each open human finding
as its ask and closes the finding as superseded by it, and unsets the old keys
in the write that saves the read (unit 3). This runs for every bead a rig's cutover
moves, since the old path's routing leaves its keys on each. The retirement
bead removes the conversion once no open bead carries the keys
([section 12](#12-the-units)).

## 3. A person's post

**The form.** Each post a person makes is one ask on the bead that owns the PR
(`gctk review ask`, `FileAsk` in `services/gctk/review/ask.go`): a review that
carries a message, an inline comment, or a conversation comment. The ask's
reason is one line naming the post: its kind, its author, the PR, an inline
comment's file and the line it was made on (`originalLine`, which a later push
does not move), and its URL. It is the ask the review-lanes design
gives work on a PR's branch
([its section 1](../tk-1tfzr71.108/design.md#asks-work-on-the-prs-branch)), so
no bead kind comes with it.

The intake files it, then marks the post 👀. `FileAsk` finds an ask with the
same reason, open or closed, and files none, so a post whose mark did not land
is not filed twice on the retry, and an edit of the post's text changes
nothing the reason holds. The text stays on GitHub, where the run reads it at
the post's URL, so the run rules the post as it stands, and the head's comment,
which shows an ask by its reason on one line, names the post without repeating
it.

**How the run rules it.** The review run takes a post's ask as it takes any
ask, and the review-ruling skill's rule for a person's comment applies to it
unchanged: graded on the correctness method's scale, a P0 or P1 fixed, a P2
fixed when low-risk and net-positive and otherwise declined, a nit answered and
not fixed. The ruling is recorded in the round's output, which the head's
comment renders. What changes:

- The skill's batch paragraph, which has each comment of a batch ruled on its
  human finding through `review-run.sh finding`, is replaced by one saying that
  each comment is its own ask, read at the URL its reason names and ruled as
  above.
- `review-run.sh finding` goes, and so does the prepare read's listing of human
  findings under their asks. No human finding reaches the record once the
  intake files asks and the conversion supersedes any that a moved bead
  carries.
- The loop's record (`recorder.record` in `services/gctk/internal/cli/review.go`)
  no longer runs `finding.sh close-answered`, for the same reason. `finding.sh`
  itself stays for the old path until tk-1tfzr71.122 deletes it.
- A deferral's follow-up is filed by `review-run.sh defer`, which takes the
  PR's target as its own already. `review-run.test.sh` gives its defer case a
  fixture target other than `main`, as the validating close of tk-grjsnf6
  asks, since the finding verb's case goes with the verb.
- A comment that answers a question the run put to a person, or makes it moot,
  closes that question's gate, with the comment named as its answer. Today the
  landing order pours no run while a human gate holds the bead
  ([the review-lanes design's section 1](../tk-1tfzr71.108/design.md#what-pours-it)),
  so such a comment would wait behind the gate it answers. Unit 4 lets the order
  pour a run while the only gates holding the bead are questions a review run
  put to a person (`review-question-<slug>`, filed by `review-run.sh question`)
  and a person's post was taken after the newest of them. That
  run rules the new posts. When one answers a question, it closes that gate;
  otherwise the gate stays, and the run records no passed result while it is
  open.

**The operator's three ends.** In conversation tk-2m30oko (2026-11-13) the
operator said the city owns every comment: "If a comment shows up, its job is
to evaluate the comment, act on that comment, and do one of, I think, three
things", which are to fix it and mark it resolved, to rule on it, decline it
and resolve it, or to say "I need to talk to a human" and use a human gate.
Each maps onto a ruling of the post's ask:

| The operator's end | The ruling | What the PR shows |
|---|---|---|
| Act on it: fix it and mark it resolved | must-fix, with the commit that fixes it | the head's comment names the commit, and the round that rules it answered at a head carrying the fix replies in the thread and resolves it |
| Rule on it: ignore or decline it, and resolve it | declined, deferred or answered | the head's comment gives the reason, and the round's post replies and resolves, or puts 👍 where nothing was asked |
| Talk to a human | question, with its gate | the gate asks you, the round's post replies naming it, and the thread stays open until you answer |

The same words say "a PR with new comments added, goes from whatever state it's
in to working". On the record `prstatus.Render` reads an approved PR whose only
conditions are the city's work as merging (`services/gctk/prstatus/render.go`).
Unit 2 has it read a PR with an untaken post, or an open ask that carries a
person's post, as working ahead of merging. "If it can't resolve all the
comments, then it goes to needs-attention": an open gate already reads
needs-attention there.

**Room for tk-ileeqzz.** That bead asks triage to answer a comment that needs
only an answer, with no ruling step. With one ask per comment, triage can rule
one ask alone and leave the rest to the ruling step. What tk-ileeqzz still
needs is its own: triage's ruling in its output, the pass rule and the result
writer reading it, a round that ends without the ruling step, and triage's post
of that answer, since the step that rules a post answers it
([section 6](#6-the-write-back)) and triage posts nothing today.

## 4. Red checks and conflicts

**Repair beads earn no second read.** Gas City's PR monitor reads each open PR
with no labels, review decision, review or comment, and no check's
`isRequired`, so it cannot tell a required check from the rest
(`pullRequestsQuery` in `internal/githubmonitor/client.go`). It counts a
cancelled check as pending, because `checkFailed` lists `CANCELED` and GitHub
spells the conclusion `CANCELLED` (`internal/githubmonitor/monitor.go`). It
marks every PR GitHub reads BLOCKED actionable (`classifyPullRequest`), which is
every PR waiting on your approval or on its checks. A repair bead is routed to
the monitor's `repair_route`, which validation requires, poured with its
`repair_workflow` and keyed by head (`ensureGitHubPRRepairBead` in
`cmd/gc/cmd_github.go`), so it is a writer of its own, and the monitor closes
none. The landing order's pass already
reads each owned PR's merge state and its required checks by `isRequired` at
the PR's own number. So the city declares no `[[github.pr_monitor]]`, the join
the merge design's section 11 describes is not built, and nothing of the
monitor's `blocked` class needs tying. The city's config declares no monitor
and no webhook today.

**The acts.** Each is decided from the pass's read and the store and taken
under the record lock within the budget. An act that files work, re-runs a
check or files a gate is skipped while a hold set by hand (`merge_hold`,
`rebase_hold`) or a human gate holds the bead, a conversation's gate included,
as `pr-facts.sh`'s red-check arm stands down today, since bringing the branch
current or sending a fixer performs one horn of what a person may be deciding.
The withdrawal of a red-check gate is never skipped:

- **A code failure.** A required check whose latest result at the head is
  `FAILURE`, and whose name is not a deploy's, gets an ask naming the PR, the
  head, the failing checks with their run logs and the branch to fix, the
  reason `pr-facts.sh` gives its record-path ask today, one per head. Two
  bounds read the bead's red-check asks, open or closed, each of which names
  its head: a closed ask at this head with the PR still red there files a gate
  (`pr-fix-unmoved.<n>`) in place of a second ask, and a red head after three
  earlier heads each drew an ask files a gate (`pr-fix-capped.<n>`) in place of
  a fourth, as `pr-facts.sh`'s cap of three does today. A deploy's failure
  files a gate.
- **A non-code failure,** one that timed out, was cancelled, failed to start or
  wants an action. The order re-runs the failed jobs of its GitHub Actions run
  once per head, and only once that run has finished, which its check suite's
  status in the pass's read shows, since GitHub re-runs a run's failed jobs
  only once the whole run has finished. The run's attempt number
  (`run_attempt`, which the act reads from the run before it re-runs) says
  whether it was re-run already, so no key records it. A failure after the
  re-run files a gate (`pr-fix-noncode.<n>`) only on an approved PR, and an
  unapproved one waits for its review.
- **The gates withdrawn.** Each red-check gate on the bead closes as moot once
  the read shows every required check passing at the PR's head. The gate is
  named under its key by the order `human-gate.sh`'s dedup uses (created, then
  id), as tk-1tfzr71.21's note of 2026-10-30 asks.
- **A required check that never reports.** At an approved PR whose review
  result passed at its head, GitHub reads BLOCKED, the read lists no required
  run at the head, and a check suite there has stayed queued with no runs for
  ten minutes. The order returns the PR to draft and marks it ready again,
  which sends the `pull_request` event that restarts the workflow, with the
  draft verbs the review-lanes effort built. The notes of 2026-11-12 found a
  re-run of the stuck run refused and a dispatched run's checks not counted. It
  does this once per head beyond the draft cycle's own transition, counted from
  the PR's timeline, and files a gate (`pr-check-unreported.<n>`) after that.
- **A conflict.** GitHub reads the PR `DIRTY`, or `BEHIND` on a target that
  requires a current branch, and the PR is approved. The order files an ask
  naming the PR, its base and head, and the merge of the base that brings the
  branch current, the reason `pr-facts.sh` gives today. An unapproved PR gets
  nothing, as today, and its label shows the conflict. No conflict ask is filed
  while an open bead other than an ask names the branch, such as a rework child
  the refinery parked, which keeps the branch.

The run answers a conflict ask by merging the target and writing the merge
commit's account, as the review-ruling skill says. Unit 5 adds the rule
`branch-supersession.sh` owed, from tk-1tfzr71.21's note of 2026-11-15: put the
conflict to a person, through `review-run.sh question`, only when the target
deleted code the branch edits or defines a name the branch also adds. A rewrite
of that code is resolved with the account.

The notes of 2026-11-06 hold three rules for the re-run, and each is kept: a
non-code failure is re-run once per head before a person is asked, it goes to a
person only on an approved PR, and its park lifts once the PR reads mergeable.
On the record the park is only the gate, which is withdrawn once the checks
pass.

## 5. The webhook

**The facts.** GitHub can deliver only to a public hook: a private or tenant
hook answers 404 to a request that comes from neither loopback nor an internal
proxy (`webhookRequestAllowed` in `internal/api/handler_webhook.go`). A public
hook may fire only a formula order and never an exec order (`routeOrder` in
`internal/webhooksink/sink.go`), and an order gets the rule's extracted
arguments, never the payload. The city's API is served on the tailnet only
(`tailscale serve status` and `tailscale funnel status`, read 2026-11-16). The
PR monitor's `webhook_secret_env` and `poll_interval` are read only by
validation (`ValidateGitHubPRMonitors` in `internal/config/github_pr_monitor.go`).

**The option, which is the operator's.** A public route, such as a Funnel on
the hook's path, with a public `[[webhook]]` that verifies GitHub's signature
and the root config's grant for a public hook.

- **What it exposes:** the hook's path on the city's API to the internet,
  guarded only by the signature check, and a secret kept in the operator's
  environment. The tailnet proxy delivers from loopback, so a public route
  must name only the hook's path, or the private hooks behind the same proxy
  are reachable too.
- **What it buys:** a comment reaches its pass up to two minutes sooner. A
  public hook can only pour a formula, which wakes an agent to start the pass
  that would have run anyway, so each delivery costs a session.

The design builds no webhook. The pass alone loses no feedback
([section 1](#1-the-read-the-intake-works-from)), so a webhook could only make
it sooner. If the operator wants one, it is a bead of its own, outside this
effort.

## 6. The write-back

The intake keeps one act on GitHub, the 👀 that takes a post. The review run's
rule-and-repair step makes the answers, in the post that already answers its
round in the head's comment (`review-run.sh post`, part 6 of the step in
`formulas/mol-pr-review.toml`), because it is the step of the work that rules
what the round fixed, declined, deferred or asked. The loop's check, which
records the run's result, cannot make them: Gas City runs it with HOME set to
the city's directory and a whitelist of variables that carries no GitHub token
(`ConditionEnv.Environ` in `internal/convergence/condition.go`), so gh has no
login there, and `gctk review passed` reads only the store. The rest goes.

| Act today | What becomes of it |
|---|---|
| 👀 on each routed post (`pr-facts.sh`'s sweep) | the intake, right after the post's ask is filed |
| A reply in an inline comment's thread with its answer | the round's post, for each post's ask the round ruled declined, deferred or answered, or put to a person |
| Resolving the thread | the round's post, behind the reply its own read shows, for an ask the round ruled; a question's thread stays open |
| 👍 where nothing more is owed | the round's post, on a post whose ask it ruled with nothing asked, and on each review message and conversation comment whose ask it ruled, whose answer is the head's comment |
| One living answer per review (`review-answer.sh`) | goes: the head's comment (`gctk review comment`) shows each ask's ruling |
| Dismissing a person's request for changes once every point is answered | goes, and the round's post asks for the person's review again once the round has answered every ask from their reviews while their request for changes stands |
| Dismissing the city's own superseded request for changes | goes: no open PR carries one (0 of 27 in the city's six repositories, 2026-11-16 05:31Z), and the sign-off posts a review that comments |
| Posting an old-path machine finding to the PR | goes with the old path |

**Bounds.** Each reply carries a marker that names its ask, as the head's
comment carries one that names its run and head
(`services/gctk/review/comment.go`), and a 👍 is found by the city's own
reaction, so a post run again posts nothing twice. A write that does not land
exits 1, as the head's comment does today, and the step's exit criteria keep it
open until the post lands. The loop's check closes the asks a round answered
only after that round's step has closed, so an ask closes only once its answer
is on the PR.

**The thread rules from PR #1492's reworks,** recorded in tk-1tfzr71.21's notes
of 2026-11-13, each kept:

- Resolve every thread the city rules on behind its answer: the round's post.
- Keep a needs-you thread open until its gate is ruled: the round's post
  leaves a question's thread open.
- Route a reply in a thread the city resolved as feedback: a new post carries
  no mark, so the intake takes it.
- File no gate that mirrors GitHub's thread state: no thread gate exists.
- Resolve a ruled thread only behind an owed reply the same read shows, never
  on a stored stamp (tk-4g6ra0p): the post resolves after reading its reply.
- A post whose own ruling declined or deferred it is answered by that ruling
  (tk-a4j0uiu): each post is its own ask, answered by its own ruling.
- Resolve a declined or deferred machine finding's thread on any PR
  (tk-axacdyl): on the record a lane's finding is answered in the head's
  comment and opens no thread, and the conversion resolves the old path's
  machine-finding threads.

**The 👍 stays the mark of nothing more owed.** `gc_thread_awaits_answer` reads
it through `gc_city_handled`. `pr-post.test.sh` reads the two reaction names
from `pr-facts.sh` (`WB_REACTION`, `WB_RESOLVED_REACTION`), and unit 4 points
that check at the constants in the Go writer.

Three other notes on the write-back are met by each answer being the ruling's
reason. A point that went to a follow-up is answered with the
follow-up, never as fixed, and its thread is resolved, as the operator said on
2026-11-06: "resolve the comment if it's scheduled, that's more than sufficient
for the city to resolve it". A declined lane finding has its answer beside its
lane's verdict in the head's comment. A declined point's code changes only
through a ruling that reopens it, by the skill's "A decline stands".

## 7. The old path, the posture and the rank

**The retirement waits on every rig's move onto the record.** On the old path,
`pr-facts.sh` is the posture, the routing into rework children, findings and
validation passes, and the write-back. Another source for an old-path PR would
rebuild that routing, which the old review path's retirement (tk-1tfzr71.122)
deletes. On 2026-11-16 at 05:31Z the city's seven stores held 24 open beads on
the old path and none on the record, with no open human finding. So every unit
of the effort lands first and acts only on the record, the effort lands, the
rigs move one at a time, and the retirement bead deletes `pr-facts.sh` once no
bead is on the old path.

**The posture's readers.**

| Reader | What it reads after this member |
|---|---|
| `prio_pr_approved` in `assets/scripts/priority-lib.sh` | for a bead on the record, the saved read's approvers at the head the store holds, which `approval()` in `services/gctk/pr/rules.go` computed (unit 2); for `pull_request`, the posture until the retirement deletes that clause |
| `prstatus.Derive` and its read in `services/gctk/prstatus` | the old path only; the retirement deletes the clause with the keys, and moves `prstatus` under the pr domain onto the ledger, the debt `docs/gctk-architecture.md` gives this member |
| `gctk merge`, `merge.sh`, `merge-tail-report.sh` | old merge path code that tk-1tfzr71.70 deletes |
| the helm board (`services/helm/internal/board/derive.go`) and `bead-context.sh` | old-path clauses the retirement deletes with the keys, where the board member (tk-1tfzr71.24) has not |
| `doctor/check-feedback-routing-owed` | deleted by the retirement |

**The rank.** The PR-finishing rank reads approval from the saved read on the
record, never from `reviewDecision`, which settles tk-os61zl6's ask for the
record. `pr_finishing_settled` goes: the fifteen-minute priority reconcile
(`orders/queue-priority.toml`) settles that work at the rank the function reads,
so a rank needs no record of its own, at the cost of up to fifteen minutes for
a bead `pr-facts.sh` re-ranked in its own pass. On the record the PR-finishing
work that carries `anchor_bead` is only an old-path rework child a rig's move
left open. Whether a review run ranks as PR-finishing work is tk-go9npun's,
held for the operator, and it would read approval the same way.

**What stays on `pull_request` until the retirement.** `pr-facts.sh`'s arms
that record a merge, a close and a moved base serve only the old path. On the
record the landing order writes a bead's end.

**The labels.** The retirement waits on tk-1tfzr71.149 as a whole, whose label
step replaces `pr-facts.sh`'s label reconcile
([its section 9](../tk-1tfzr71.149/design.md#9-what-tk-1tfzr7121-needs)).

## 8. The cadence and its order

`refinery-reconcile.sh` runs the merge cadence's arms every sixty seconds:

| Arm | Script | Retired by | Once the retirement lands |
|---|---|---|---|
| before the arms | `merge-tail-report.sh` | tk-1tfzr71.70 | gone, before the retirement |
| 1 | `pr-facts.sh --posture-only` | this member's retirement | removed |
| 2 | `merge.sh` (`gctk merge`) | tk-1tfzr71.70 | gone, before the retirement |
| 3 | `pr-open.sh` | tk-1tfzr71.70 deletes its create path | whatever tk-1tfzr71.70 leaves runs on |
| 4 | `pr-facts.sh --route-comments-only` | this member's retirement | removed |
| 5 | `pre-open-rebase.sh` | tk-1tfzr71.70 | gone, before the retirement |
| 6 | `gate-ensure.sh` | tk-1tfzr71.122 | runs until tk-1tfzr71.122 |
| 7 | `pr-facts.sh` | this member's retirement | removed |
| 8 | `review-sweep.sh` | tk-1tfzr71.122 | runs until tk-1tfzr71.122 |
| 9 | `scaffolding-sweep.sh` | tk-1tfzr71.122 | runs until tk-1tfzr71.122 |

So the driver outlives this member: after the retirement it drives the old
review path's last arms, which close the residue that tk-1tfzr71.122's drain
check counts. Its rows (`refinery-reconcile.sh` with its test, and
`orders/refinery-reconcile.toml`) move to tk-1tfzr71.122, which deletes it with
those arms. `pace-lib.sh` and its test move there too: besides `pr-facts.sh`,
its sourcers are `gate-ensure.sh`, `pr-open.sh` and `pre-open-rebase.sh`, and
once tk-1tfzr71.70 has deleted `pre-open-rebase.sh` and the old-path walks of
`pr-open.sh`, and the retirement has deleted `pr-facts.sh`, `gate-ensure.sh` is
the last. The retirement removes arms 1, 4
and 7 and what is left of the block that holds the merge on the posture.

**The order of the three retirements** is tk-1tfzr71.70, then this member's
retirement, then tk-1tfzr71.122:

- The retirement waits on tk-1tfzr71.70, because `record-failure-cap.sh`'s other
  caller is `gctk merge` and `branch-supersession.sh`'s other caller is
  `pre-open-rebase.sh`, both deleted there. The retirement then deletes both
  files. `lifecycle.sh`'s row, which tk-1tfzr71.70 adds once it has reduced the
  script to a plain write, comes under the retirement, which deletes it once no
  caller is left, as the merge design's section 10 plans.
- tk-1tfzr71.122 waits on the retirement, in place of its edge onto
  tk-1tfzr71.21, because `pr-facts.sh` calls `finding.sh` on the old path until
  the retirement deletes it.

**`review-dismissal.sh`.** Unit 1 moves `live_comments`, what a dismissal
retires, into `pr-post.sh`'s definition, where `gc_thread_awaits_answer`
reads it, so `feedback-def` no longer sources the file. `pr_coords`,
`approval_phrase` and the old receipts' rule (`unrouted_comment_ids`) stay in
it for its two last sourcers, `approval-withdraw.sh` and
`bring-current-guard.sh`, and its row moves to tk-1tfzr71.122, which deletes it
with them. `review-dismissal.test.sh`'s check that no file copies the rule
names `pr-post.sh` as the rule's home.

**`branch-supersession.sh`'s owed behavior** goes into the review-ruling
skill's rule for a conflict ask ([section 4](#4-red-checks-and-conflicts)).

## 9. One writer

The Done reads: "One writer, the landing order, saves one GitHub read per PR,
and nothing else mirrors GitHub state into bead metadata." Each key
`pr-facts.sh` writes:

| Key | Becomes | Why |
|---|---|---|
| `pr_posture` | goes | the saved read holds the approvers and requesters `approval()` finds, and the rank reads them |
| `pr_merge_state` | goes | the saved read holds the merge state |
| `pr_head_oid` | goes | the saved read holds the head, and the record holds the validated one |
| `pr_finishing_settled` | goes | the priority reconcile settles the rank by comparison |
| `pr.conversation` | goes | on the record the board renders the evaluator, and an untaken post or an open ask is the conversation's state |
| `pr_comment_watermark`, `pr_review_watermark`, `pr_issue_comment_watermark` | go | the city's marks on GitHub are the receipts |
| `pr_comment_answered`, `pr_review_answered` | go | the same |
| `pr_comment_batch`, `pr_review_batch`, `pr_issue_comment_batch`, `pr_comment_disposition` | go | each post's ask names it, and its own ruling answers it |
| `pr_unengaged_threads` | goes | the old path's gate for unmarked threads under the city's login; no open bead carries it (2026-11-16), and the conversion resolves such threads |
| `pr_check_rerun` | goes | the Actions run's attempt number says whether it was re-run |
| `status_label_clear_owed` | goes | tk-1tfzr71.149's label comparison retries any clear |
| `pr_url`, which it writes beside `status_label_clear_owed` on a bead that names none | the write goes | the PR's URL is the record's own key (`services/gctk/pr/record`) |
| `signoff_dismissed` | goes | no city request for changes stands to dismiss |
| `merged_sha` and `merge_record_failures` in its merged arm, `blocked_reason` in its abandoned and retargeted parks | go with the old path | on the record the landing order writes a bead's end and files its exceptions |
| `pr_provenance_since` | stays, written by the landing order | a receipt of the city's own act |
| the keys on the children it files: rework children, validation passes, human findings | go with those forms | the ask is the one form on the record |

`gc.pr_close_disposition_*` is written by `pr-dispose.sh` and read by
`pr-facts.sh`'s close arm, which serves the old path. How a ruling retires a PR
on the record is tk-1tfzr71.89's, which every rig's cutover waits on.

**Why a receipt of the city's own act is not a mirror.** A mirror copies a
state GitHub holds, which goes stale the moment GitHub moves, and needs a
writer to keep it current. `pr_provenance_since` records when the city first
read the PR, a fact of the city's that GitHub does not hold and that never
changes, so nothing keeps it current and nothing can disagree with it. The
city's marks are acts of the city's kept on GitHub itself, read back in the one
saved read.

**The definition of feedback stays one copy.** The intake, the evaluator, the
withdrawal and the record each read which posts are feedback, which are the
city's own, and which are taken or handled through the feedback adapter over
`pr-post.sh feedback-def`. The counting rules that were `pr-facts.sh`'s, such as
which review states count, live in Go, as `countedReviewStates` does today.

## 10. What each held note and bead becomes

tk-1tfzr71.21's notes say what the replacement owes, and the beads it blocks
wait on it. Each gets a row. "The retirement" is the bead section 12 files.

**The notes.**

| Note (date) | Becomes |
|---|---|
| PR-finishing rank (10-23) | carried, unit 2: the rank reads the saved read's approvers on the record, and `pr_finishing_settled` goes ([section 7](#7-the-old-path-the-posture-and-the-rank)) |
| Rule 1 list (10-26): tk-ickub0o, a thread files a visit while the PR waits for review | made moot: no thread files a visit or a gate on the record, and a person's open thread holds the PR through GitHub's merge state where the base requires resolved threads |
| tk-mg42wc8, a second copy of "routed" | made moot: "taken" is one rule in the definition, read through one Go function by the intake, the evaluator and the withdrawal |
| tk-icggxv, inline comments a visit carries are not linked to it | made moot: each comment is its own ask, which names it |
| tk-l7dka5, the arms guard demands but not other blockers | carried: the order pours a run only while nothing else writes the branch and no human gate holds the bead, a run takes an ask only when nothing holds the ask (`gctk bead holds`), and a conflict or red-check ask is not filed while a hold or a gate holds the bead |
| tk-nfdq56, routing coupled to conflict state | made moot: posts are taken whatever the merge state, and a conflict is its own ask |
| held: review reads the posture (10-28) | carried, unit 2: the evaluator's condition for each untaken post |
| What a dismissal retires (10-28) | carried, unit 1: `live_comments` moves into `pr-post.sh` |
| The 👍 mark (10-28) | carried, unit 4: the round's post puts it, and `pr-post.test.sh` reads its name from the Go writer |
| `gctk pr owner` (gctk domain move) | dropped on purpose: no webhook or monitor calls it, and the pass reads each PR from the bead that owns it, so the verb would have no caller; unit 6 removes its row from `docs/gctk-architecture.md` |
| Built-once rule 1 (blocked census) | carried: the acts read holds through the waits package and compute none |
| `gate_for` names a key's gate (10-30) | carried, unit 5: the red-check gates are named under their key by `human-gate.sh`'s order |
| tk-306xmm6, tk-5g3y4ds, tk-ec0b012, tk-8njghcm, tk-qnn0yhx (10-30) | see the beads below; tk-8njghcm closed after PR #1492 |
| `review-dismissal.sh`'s `pr_coords` for the sign-off (10-30) | made moot: `converse-signoff.sh` no longer sources the file (read 2026-11-16), and the file moves to tk-1tfzr71.122 |
| tk-a8nb8wo, the city's own posts after a misread (11-03) | carried: nothing is taken while the login does not resolve, and every post the run makes carries the city's mark |
| Test cost (11-05) | carried, the retirement deletes `pr-facts.test.sh` |
| Approval comments (11-05) | carried, unit 2: an approval's message is a post |
| A follow-up read as fixed (11-06) | carried, unit 4: the answer is the ruling's reason, and a scheduled point is resolved |
| tk-tx227cp's re-run rules (11-06, two notes) | carried, unit 5; the monitor's `CANCELED` spelling is moot, since no monitor runs |
| A parked rework child keeps the branch (11-06) | carried, unit 5: no conflict ask while another open bead names the branch |
| The suite's per-run limit (11-06) | carried: new tests are Go tests, outside `tools/run-tests.sh`'s 900-second limit, and every shell suite a unit changes stays within it in a loaded `-j9` wave |
| bead-rehome exit 5 (11-07) | made moot on the record: a PR closed unmerged is the landing order's exception, and a recorded disposition there is tk-1tfzr71.89's |
| Dispatch by sling (11-08) and `route_finishing` (11-08) | made moot: an ask is unrouted and the order pours the run, so no child or route is written |
| Parks file their gate first (11-09) | carried: on the record a PR closed unmerged or a moved base is the landing order's exception, whose gate the next run files when one did not (`blocked` in `services/gctk/pr/landing.go`), and a red-check park is only its gate (unit 5) |
| An open conversation defers a conflict rework (11-09) | carried, unit 5: no conflict ask while a conversation's gate holds the bead |
| A declined lane finding answered (11-10) | made moot by tk-1tfzr71.22: the head's comment answers it beside its lane's verdict |
| A required check that never reports (11-11, and two notes of 11-12) | carried, unit 5; the second 11-12 note's monitor, which reads the case as any BLOCKED PR, is moot, since no monitor runs |
| The merge design's take-over (11-12) | carried: units 2 to 5; the monitor's join dropped on purpose (decision 1); the driver's row moved ([section 8](#8-the-cadence-and-its-order)) |
| `countedReviewStates` (11-12) | carried, unit 2 |
| What the record path owes (11-12) | carried, units 2 and 5; the city's superseded request dropped on purpose, with no live case; the label reconcile is tk-1tfzr71.149's |
| The BLOCKED-thread gate while work is live (11-12, 11-13) | made moot: PR #1492 retired the gate |
| A rework changing declined code (11-13) | made moot by the skill's "A decline stands" |
| Only a person's answer quiets a thread block (11-13) | made moot: the gate retired, as the note of 11-13 says |
| The operator's workflow (11-13) | carried: [section 3](#3-a-persons-post), unit 2 for working, unit 4 for a question's gate closed by a comment |
| PR #1492's rework rules (11-13, three notes) | carried: [section 6](#6-the-write-back) |
| `rejection-repool.sh` comments (11-13) and `deferred-dispatch.sh` comment (11-13) | made moot: the retirement deletes the file |
| The arm's keys (11-13) | made moot: the intake reads no arm key |
| The one-day quiet window (11-13) | made moot: on the record no gate is filed for feedback, since every post becomes an ask |
| The review-lanes design's three things (11-14) | carried: the ask is the form, and units 2 and 4 move the run's ruling onto it |
| The withdrawal reads the new marks (11-15) | carried, unit 2: `unrouted` |
| tk-os61zl6 (11-15) | carried, unit 2, on the record |
| The board's ruling (11-15) | carried: the saved read is the one copy |
| The supersession check asked on a rewrite (11-15) | carried, unit 5: the skill's conflict rule |
| What `pr-facts.sh` files on the record (11-15) | carried, units 2 to 5 |
| Old-path PRs read by `prstatus.Derive` (11-15) | carried: the retirement waits on every cutover |
| The comment path's cost (11-15) | carried: one ask per comment leaves room for tk-ileeqzz |
| The label's writer (11-15) | carried: the retirement waits on tk-1tfzr71.149 |
| Two leads on Gas City (11-15) | both verified at upstream main 76a06b2327, [gas-city-search.md](gas-city-search.md) |
| The moved `close-answered` call (11-15) | carried, unit 4: the call goes in the same change that gives a person's post its new form |
| A deferral's follow-up takes the PR's target (11-16) | carried, unit 4 |

**The beads it blocks.** Where the old path keeps the problem until the
retirement deletes the code, the bead's edge moves onto the retirement, keeping
its close brief and its arm for the validating closer.

| Bead | Becomes |
|---|---|
| tk-1tfzr71.122, the old review path's retirement | its edge moves onto the retirement, and the driver's, the order's, `pace-lib.sh`'s and `review-dismissal.sh`'s rows move to it |
| tk-1tfzr71.23, convoys | stays: it waits by lane A's order, and convoy graduation is already gone |
| tk-1tfzr71.25, the registry sweep | moves onto the retirement, which registers the keys of [section 9](#9-one-writer) retired |
| tk-1tfzr71.50, `bd-lib.sh`'s checked create | moves onto the retirement, which deletes the last caller in this member's files |
| tk-1tfzr71.71, the evaluator's `anchor_bead` reading | moves onto the retirement and gains an edge onto tk-1tfzr71.122: a rework child a rig's move left open holds its PR only through that reading, and the old review path's writers file children without the edge until then |
| tk-306xmm6, answered outdated threads read as unanswered | moves onto the retirement: on the record a post is taken by its mark, whatever its thread's state |
| tk-5g3y4ds, a label that is only a severity word | moves onto the retirement: the head's comment shows a post's ask by its reason, the line that names the post |
| tk-6bovoni, guards over a rewritten main | moves onto the retirement, which deletes `branch-supersession.sh`; the guard's half is on tk-1tfzr71.122 |
| tk-8gradm4.1, a per-pass snapshot | moves onto tk-1tfzr71.122, which deletes the driver; the landing order's one read per pass is the snapshot it asked for |
| tk-ec0b012, two same-text comments share a finding | moves onto the retirement: each comment is its own ask |
| tk-o9i6kp0, approving with comments | stays: an approval's message is read on the record once the effort lands |
| tk-os61zl6, one approval reader | moves onto the retirement; it keeps its edges onto tk-1tfzr71.70 and tk-1tfzr71.122 |
| tk-qnn0yhx, a red-check visit never retracted | moves onto the retirement: on the record the gate is withdrawn once the checks pass |
| tk-t9fl9ss, the suite past its limit | moves onto the retirement, which deletes `pr-facts.test.sh` |
| tk-icggxv, tk-ickub0o, tk-l7dka5, tk-mg42wc8, tk-nfdq56 (closed, superseded by this member) | rows in the notes table above |

## 11. The comparison before pr-facts.sh retires

The description asks to run both paths side by side on one rig and compare
routed feedback before `pr-facts.sh` retires. Both paths read feedback by the
same definition, so what can differ is how each decides a post was handled and
whether gctk's reads find every post. Those differences show over each PR's
whole history at one moment better than over a window of new comments.

So unit 6 runs the intake's take rule read-only over every open PR in every
rig. It does so through a test in the pr package that is skipped unless its
environment names the stores to read and the report to write, and that a
person runs by hand on the effort branch. A program in the unit's spec
directory cannot do it: the whole read and the GitHub adapter it calls are
internal to gctk, and the domain's exported entry points read only beads on the
record, while every open PR is on the old path. The test calls the whole read
and the take rule on each PR an open old-path bead names, writes nothing to a
store or to GitHub, and writes its report into the unit's spec directory. It
compares each feedback post's two receipts: `pr-facts.sh`'s, a post at or
below a watermark or answered mark or in a batch ledger, and the intake's, the
city's 👀 or 👍 on it. Each post on which they differ needs a reason, such as a
review message the old write-back answers only in its living answer, or an
approval's message the old path never counted. The comparison is recorded in
the unit's spec directory, and a difference with no reason goes to the operator
through a gate on tk-1tfzr71.21 before the effort lands. On 2026-11-16 the
city's six repositories held 27 open PRs, which at about 4.4 seconds a whole
read take about two minutes.

Then the first rig to move onto the record after the effort lands is the live
side by side: its PRs on the new path, the other rigs' on the old one. That
rig's cutover bead, already set to watch its first PRs through to their close,
records that each comment on them got its ask, its mark and its answer. The
retirement's drain check counts, in every store, the open beads on the old path
and those still carrying the old receipt keys.

## 12. The units

The effort's units land on `integration/tk-1tfzr71.21`, keep the suite green
and leave the city working. Nothing they build runs on a PR until a rig moves
onto the record, since no PR is on it today. The retirement is filed outside the
effort, on the default branch.

| # | Unit | What it builds | Waits on |
|---|---|---|---|
| 1 | feat(pr): define the city's taken mark beside its handled mark, and keep what a dismissal retires in the definition of feedback | `gc_city_taken` in `pr-post.sh`'s definition, and `live_comments` moved there from `review-dismissal.sh`, so `feedback-def` no longer sources that file; `review-dismissal.sh` keeps `pr_coords`, `approval_phrase` and `unrouted_comment_ids`; `review-dismissal.test.sh` and `pr-post.test.sh` follow; the "Unanswered review threads" warrant re-verified | nothing |
| 2 | feat(gctk): take each person's post on a PR as its own ask, with the city's marks as receipts | in gctk's pr domain: the whole read reads the marks; the act files one ask per untaken post and marks it 👀; the saved read's `untaken`; the evaluator's condition per untaken post; `unrouted` over the marks; an approval's message counted; `pr_provenance_since` stamped by the landing order; `prstatus.Render` reads a PR with an untaken post or an open post ask as working; `prio_pr_approved` reads the saved read's approvers on the record; `pr-facts.sh` stops routing, posting, recording a posture and writing a conversation on the record. Tests: a late review below the newest id is taken; a post whose mark failed is taken again with no second ask; an edited post is not filed twice; an approval's message becomes an ask; a run merges over no untaken post; the withdrawal waits on an untaken comment; the rank on the record; working ahead of merging. The "Saved GitHub read" warrant re-verified | unit 1, and tk-1tfzr71.149 landing on main with the effort's branch brought current |
| 3 | feat(gctk): convert the old path's receipts on a bead that moves onto the record | at a bead's first whole read on the record, while it carries `pr-facts.sh`'s watermarks, answered marks or batch ledgers: the city's 👀 on every feedback post at or below them, each unresolved thread that holds only the city's own posts resolved, each open human finding's post filed as its ask and the finding closed as superseded by it, and the old keys unset in the write that saves the read. Tests: each old key converted; a post at or below a watermark marked and filed nothing; a post above it taken; a human finding superseded by its post's ask; a thread of the city's own resolved and a person's left alone; a bead with no old keys untouched | unit 2 |
| 4 | feat(review): answer each person's post where it was made, in the round that rules it | `review-run.sh post`, in rule-and-repair, replies in a thread and resolves it, puts 👍, leaves a question's thread open with its gate named, and asks again for the review of a person whose request for changes stands once the round has answered every ask from their reviews, each reply found again by a marker naming its ask; part 6 of the step's text in `mol-pr-review.toml` names the answers; the loop's check makes no GitHub call, and its call to `finding.sh close-answered` goes; `review-run.sh finding` and the prepare read's human findings go; the review-ruling skill's batch paragraph replaced, a post read at its URL, and a comment that answers a question closes its gate; the landing order pours a run for a post taken after the run's own question gates; `review-run.test.sh`'s defer case on a target other than `main`; `pr-post.test.sh` reads the reaction names from the Go writer. Tests: each ruling's answer by post kind; a post run again posts nothing twice; an answer that does not land exits 1 and leaves its ask open; a run poured behind a question gate for a newer post, and none behind any other gate | unit 2 |
| 5 | feat(gctk): route a PR's red checks and conflicts from the landing order's read | the pass's read gains the suites' status and creation time; the acts of [section 4](#4-red-checks-and-conflicts) with their gates and their withdrawal; the skill's conflict rule; `pr-facts.sh` stops its conflict and red-check arms on the record. Tests: a code failure's ask and both bounds; a non-code failure re-run once, after its run finished, and a gate only when approved; a gate withdrawn when the checks pass; the stuck suite toggled once and then gated; a conflict ask only on an approved PR that nothing holds | unit 2, and tk-1tfzr71.149 landing on main |
| 6 | docs: state the GitHub intake on the record, and move the cadence's rows | `docs/architecture.md`, `docs/refinery-merge-cadence.md`, `docs/state-machine.md`, `docs/gctk-architecture.md` (the `gctk pr owner` row out, the debt entry), `docs/built-once-target.md` (the replacement named for `pr-facts.sh`, lane A's rows), `tools/deletion-plan.tsv` (the rows of section 8 moved to tk-1tfzr71.122), `lifecycle/lifecycle.toml` (the old receipts written only on the old path), `services/gctk/README.md`; and the comparison of [section 11](#11-the-comparison-before-pr-factssh-retires), with its test in the pr package and its report | units 3, 4 and 5 |
| R | refactor: retire pr-facts.sh and the GitHub intake's old path (outside the effort, target `main`) | its drain check: no open bead on the old path in any store, and none carrying the old receipt keys or an open human finding. Then it deletes `pr-facts.sh`, `review-answer.sh`, `record-failure-cap.sh`, `branch-supersession.sh`, the doctor check and their tests (16,399 lines with their tests at 713e3a733), and `lifecycle.sh` once no caller is left; removes arms 1, 4 and 7; removes the conversion, the comparison's test and `prio_pr_approved`'s posture clause; registers [section 9](#9-one-writer)'s keys retired; moves `prstatus` under the pr domain onto the ledger; rewrites every live line that names `pr-facts.sh` ([section 14](#14-the-files-that-name-pr-factssh)) | tk-1tfzr71.21, tk-1tfzr71.149, tk-1tfzr71.70, and every rig's cutover bead (tk-1tfzr71.78, .80 to .84) |

Each unit's suites fit the runner's per-run limit in a loaded `-j9` wave: the new
logic's tests are Go tests in gctk's packages, which `tools/run-tests.sh` does not
time, and the shell suites the units touch (`pr-post.test.sh`,
`review-dismissal.test.sh`, `review-run.test.sh`, `priority-lib.test.sh`) are
each changed by a few cases. `pr-facts.test.sh`'s parts, which the review of
2026-11-06 saw time out in such a wave (tk-t9fl9ss), go with the retirement.

Units 2 and 5 rewrite code in `services/gctk/pr` that tk-1tfzr71.149's unit 1
rewrites, so they are built on main once that effort has landed, as that design
builds its own unit 1 after the review-lanes effort.

## 13. Edges and notes the implementation child adds

- Units 1 to 6 are filed under the epic (tk-1tfzr71) with
  `target=integration/tk-1tfzr71.21` in each create. tk-1tfzr71.21 and the
  summary task (tk-1tfzr71.163) wait on each through a `blocks` edge. Each unit
  waits on what its row names and is armed to dispatch when they close.
- The retirement is filed under the epic with `target=main`, outside the
  effort, blocked by tk-1tfzr71.21, tk-1tfzr71.149, tk-1tfzr71.70 and each
  cutover bead, and armed on mol-polecat-work. Neither tk-1tfzr71.21 nor the
  summary task waits on it.
- tk-1tfzr71.122's edge onto tk-1tfzr71.21 moves onto the retirement, with a
  note saying why ([section 8](#8-the-cadence-and-its-order)) and naming the
  rows unit 6 moves to it, and the test files that copy `review-dismissal.sh`
  by name, which its deletion of that file changes: `converse-signoff.test.sh`,
  `gc-helm-accept.test.sh`, `conversation-merge-hold.test.sh`,
  `pr-sitting-comment-wiring.test.sh`, `work-submit.test.sh` and
  `test-harness.sh`.
- The held beads' edges move as [section 10](#10-what-each-held-note-and-bead-becomes)
  says, each with a close brief that names what the retirement or
  tk-1tfzr71.122 removes, and each keeps its validating closer's arm, armed
  only once its new edge's add exits 0.
- tk-1tfzr71.70 gets a note: the retirement waits on it, deletes
  `record-failure-cap.sh` and `branch-supersession.sh`, whose other callers it
  deletes, and takes `lifecycle.sh`'s row once it has added it. Whatever it
  leaves of `pr-open.sh` sources no `pace-lib.sh`, whose row moves to
  tk-1tfzr71.122.
- Each cutover bead gets a note: the intake converts each moved bead's old
  receipts at its first whole read, so the keys are gone from it after one pass.
  The first to move after the effort lands also records that each comment on
  its first PRs got its ask, its mark and its answer.
- tk-go9npun gets a note: on the record the rank's approval is the saved read's
  approvers once unit 2 lands.
- tk-ileeqzz gets a note: each comment is its own ask, so triage can answer one
  alone ([section 3](#3-a-persons-post)).
- Before filing, the child surveys the open branches against each unit's files
  again. At this reading, PR #1533 (tk-1tfzr71.150) adds the design units 2 and 5
  build on, and the effort's own branch carries nothing past main.

## 14. The files that name pr-facts.sh

`git grep -l pr-facts origin/main -- ':!specs'` listed 103 files on 2026-11-16.

| Files | What becomes of the mention |
|---|---|
| The retirement's files that name it: `pr-facts.sh` and its test, `review-answer.sh` and its test, `record-failure-cap.sh`, `branch-supersession.sh`, `refinery-reconcile.sh` and its test, `review-dismissal.sh` and its test, `doctor/check-feedback-routing-owed/run.sh`, `orders/refinery-reconcile.toml` | deleted by the retirement, or by tk-1tfzr71.122 for the four that move there, whose comments the retirement rewrites where the driver keeps running |
| Seventeen files under tk-1tfzr71.122's rows, such as `finding.sh`, `gate-ensure.sh`, `signoff.sh` and `approval-withdraw.sh`; two under tk-1tfzr71.70's (`pre-open-rebase.sh` and its test); one under tk-1tfzr71.19's and one under tk-1tfzr71.25's | deleted with those beads' files |
| Old merge path code no row lists yet: `merge.sh`, `merge.test.sh`, `services/gctk/internal/cli/merge.go`, `services/gctk/internal/cli/lifecycle.go` and `services/gctk/internal/lifecycle/machine.go` | tk-1tfzr71.70 deletes them before the retirement |
| `review-verdict.test.sh` | deleted with `review-verdict.sh` by whichever of tk-1tfzr71.70 and tk-1tfzr71.122 lands second, as tk-1tfzr71.70's note of 2026-11-15 says |
| `lifecycle.sh` and `lifecycle.test.sh` | the retirement deletes them, once tk-1tfzr71.70 has reduced the script to a plain write and added its row |
| Code this member changes: `pr-post.sh`, `pr-post.test.sh` (unit 1, unit 4), `services/gctk/pr/feedback.go`, `services/gctk/pr/ready_keys.go` (unit 2), `review-run.sh` (unit 4), `priority-lib.sh`, its test and fixture (unit 2, then the retirement), `services/gctk/prstatus/prstatus.go`, `services/gctk/prstatus/gates.go` (the retirement) | changed by the unit named |
| The helm board's posture and conversation readers: `services/helm/internal/board/derive.go`, `derive_test.go`, `model.go`, the rig board's two fixtures, `services/helm/README.md` | the retirement deletes their old-path clauses, where tk-1tfzr71.24 has not |
| Live scripts whose comments or messages name it: `bd-lib.sh`, `bead-rehome.sh`, `converse-rework.sh` and its test, `converse-signoff.sh` and its test, `demo-deliver.sh`, `feedback-miner.sh`, `gc-helm.sh`, `gc-helm-open.test.sh`, `gh-origin-guard.sh` and its test, `patrol-finding.sh`, `pr-dispose.sh` and its test, `pr-open.sh`, `pr-status-label.sh`, `queue-priority.sh` and its test, `test-harness.sh` and its test, `build-scratch-reap.test.sh`, `preexisting-failure.test.sh`, `doctor/check-state-space/run.sh`, `tools/run-tests.sh` | the retirement rewrites each to name what does the job then, or drops the clause; `pr-dispose.sh`'s consumer is the old path's close arm, and its use on the record is tk-1tfzr71.89's |
| Prompts, formulas and their renders: `template-fragments/polecat-doctrine.template.md`, `formulas/mol-polecat-work.toml`, `formulas/mol-feedback-miner.toml`, the three `generated/seed-audit` renders | the retirement rewrites the sources, and the render follows |
| Docs: `architecture.md`, `authority-map.md`, `built-once-target.md`, `component-model.md`, `finalize-gate.md`, `gh-origin-guard.md`, `human-engagement.md`, `refinery-merge-cadence.md`, `state-machine.md`, `steering.md`, `warrants.md`; and gctk's own account of the shell it does not hold yet, `services/gctk/README.md` and the comment in `services/gctk/cmd/gctk/main.go` | unit 6 states the record's intake, and the retirement removes the old path's account |
| `lifecycle/lifecycle.toml` | unit 6, then the retirement registers the keys retired |
| `tools/deletion-plan.tsv` | unit 6 moves rows, and the retirement removes its own |

## 15. Facts this design rests on

- **The landing order's read** is specified in `specs/tk-1tfzr71.149/design.md`
  at 4d796d181, the head of PR #1533, which awaits the operator. Its section 1
  lists the signs of moved feedback, the number of reviews among them, and its
  section 9 leaves feedback routing, red checks, conflicts and the webhook to
  this member.
- **The saved read today** (`pr_github_read`, `services/gctk/pr/read.go`)
  keeps the newest feedback id in each id space and the threads waiting on the
  city's answer, and the evaluator compares the newest ids with the watermarks
  (`unhandled`, `services/gctk/pr/feedback.go`).
- **gctk's reads** (`services/gctk/internal/gh/gh.go`): inline comments carry
  `reactionGroups { content viewerHasReacted }`, and reviews and conversation
  comments do not.
- **The ask** (`services/gctk/review/ask.go`): a task that blocks the PR's bead,
  names its branch, has no route, assignee or role, and is found again by the
  same reason and source, open or closed. The head's comment shows an ask by
  its whole reason on one line (`oneLine` in `services/gctk/review/passed.go`,
  called from `services/gctk/review/comment.go`). The record closes
  an ask ruled declined, deferred or answered, and a must-fix one once a judged
  head carries its fix, and a question stays open (`answeredAsks`,
  `services/gctk/review/result.go`).
- **The render on the record** (`prstatus.Render`): needs-attention, then
  merging, then working, then needs-review, and merging covers an approved PR
  with only the city's work left.
- **The loop's check** (`review-passed-check.sh`, with a two-minute timeout in
  `formulas/mol-pr-review.toml`) runs in Gas City's gate sandbox: HOME is the
  city's directory, and the environment is a whitelist that carries no GitHub
  token (`ConditionEnv.Environ` in `internal/convergence/condition.go` at
  76a06b2327). Under that HOME, `gh api user` answered "To get started with
  GitHub CLI, please run: gh auth login" on 2026-11-16, so the check reaches
  only the store, as `gctk review passed`'s help says. The rule-and-repair
  step runs in an agent's session, which pushes the round's fixes and posts the
  head's comment today.
- **The stores,** read 2026-11-16 at 05:31Z with `gc bd --db <store> list
  --status open,in_progress,blocked` over the seven stores `gc rig list` names:
  24 open beads with `merge_result=pull_request`, none on the pending record,
  no open human finding, and none carrying `pr_unengaged_threads`.
- **The repositories,** read the same minute with one GraphQL request per rig
  repository: 27 open PRs in six repositories, none of whose latest review from
  the city's account requests changes.
- **The cadence** (`assets/scripts/refinery-reconcile.sh`): a sixty-second
  cooldown, with the arms of [section 8](#8-the-cadence-and-its-order).
- **The callers** of the files this member shares, besides `pr-facts.sh`,
  which sources `pace-lib.sh` and `review-dismissal.sh` and runs the other two:
  `pace-lib.sh` is sourced by
  `gate-ensure.sh`, `pr-open.sh` and `pre-open-rebase.sh`;
  `record-failure-cap.sh` is run by `gctk merge` (`services/gctk/internal/cli/merge.go`);
  `branch-supersession.sh` by `pre-open-rebase.sh`; `review-dismissal.sh` is
  sourced by `approval-withdraw.sh`, `bring-current-guard.sh` and `pr-post.sh`'s
  `feedback-def`.
- **The sizes** at 713e3a733, with `wc -l`: the seventeen rows under
  tk-1tfzr71.21 come to 18,396 lines. Those that move to tk-1tfzr71.122 come to
  1,997 (`refinery-reconcile.sh` with its test and order, `pace-lib.sh` and
  `review-dismissal.sh` with their tests), so the retirement deletes 16,399.
- **The city's API,** `tailscale serve status` and `tailscale funnel status`,
  read 2026-11-16 at 05:36Z: served on the tailnet only, by a proxy to
  loopback, with nothing funnelled.
- **The city's config** declares no `[[github.pr_monitor]]` and no `[[webhook]]`.
