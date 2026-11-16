---
name: Design — a person's PR comments, red checks and conflicts reach work from the beads, and pr-facts.sh retires
description: The design for tk-1tfzr71.161, the design child of initiative tk-1tfzr71.21, under the operator's ruling of 2026-11-16 (conversation tk-q3jegyy) and on the landing-order design as PR #1533 merged it (bc181140b), read at main 713e3a733 and 73845e65f and against Gas City upstream main 994008c628. Each comment a person leaves on a city PR becomes an ask on the PR's bead, which the landing order files from the PR's saved read and marks 👀, and the review run's round that rules it answers it where it was made; triage answers one that needs only an answer. The city dismisses a request for changes once every point is answered, asks a person a question in one place, the gate on the board, and repairs red checks and conflicts through the PR's own review run. Written for a city whose rigs are all on the new merge path, its last unit deletes pr-facts.sh. Read it to approve the design at its gate, or to build one of its units.
---

# Design: a person's PR comments, red checks and conflicts reach work from the beads, and pr-facts.sh retires

This is the design record for tk-1tfzr71.161, the design child of the
initiative tk-1tfzr71.21. It applies the operator's ruling of 2026-11-16 in
conversation tk-q3jegyy, whose seven points the Rework brief on
tk-1tfzr71.161's notes gives in full. The pack was read at main 713e3a733,
which `integration/tk-1tfzr71.21` points at, and the files this design cites
anew at main 73845e65f. The reads and acts it builds on are the landing-order
design's, `specs/tk-1tfzr71.149/design.md` at bc181140b, the commit with which
PR #1533 merged into `integration/tk-1tfzr71.149`. That file sits on that
branch until the landing-order effort lands on main, so the links to it here
resolve once it does. Gas City is cited by symbol at `gastownhall/gascity`
main 994008c628 (2026-11-16T20:35:45Z), the packs by path at
`gastownhall/gascity-packs` main 0f07496d2f, and the city's stores and
repositories as [section 14](#14-facts-this-design-rests-on) dates them. The
search behind the surface the units add is
[gas-city-search.md](gas-city-search.md).

## What the operator approves

Today one script (`pr-facts.sh`, 5,780 lines with an 8,188-line test) runs
three times in every one-minute pass of the merge cadence. It reads every open
PR's reviews and comments, copies what it finds onto each PR's bead in keys
only the pack's scripts parse, routes comments into work, and answers on GitHub
in a separate sweep. Approving this design replaces that script and deletes
it.

**The new merge path.** On it, the bead that owns a PR stays open, marked as a
PR waiting to merge, until the landing order, the order that merges the city's
PRs, merges the PR and closes the bead. The pack's docs call that mark the
pending record, since its keys are copied from Gas Town's own record of a PR
([state-machine.md](../../docs/state-machine.md#the-pending-record)). This
design calls it the new merge path throughout, and it is written for a city
whose rigs are all on it: every rig moves onto it before this effort lands
([section 7](#7-a-city-on-the-new-merge-path)).

**An ask.** An ask is a small record of one piece of work on a PR's branch: an
open bead that blocks the bead owning the PR and names the PR's branch. No
worker pool claims it, so only the PR's review run works it, and one run rules
every ask open on its PR together. One ask per comment means one such record
per comment, so each comment gets its own answer. It does not mean one run, or
one model session, per comment.

What approving it ships:

- **Each comment you leave on a city PR becomes an ask, and the city marks it
  👀** within about 4 minutes. That covers a review's message, an inline
  comment, a conversation comment and the message on an approval. The review
  run's round that rules it answers it where you made it.
- **A comment that needs only an answer, or nothing, costs a short run.**
  Triage, the run's first step, answers it with a reply or a 👍 and closes its
  ask, and the ruling session does no work for it.
- **Your request for changes is dismissed once every point it raised is
  answered, and you are asked to review again,** as today. The note says what
  became of the points. A dismissal is never an approval: the PR then reads
  needs-review, and it merges only on your approval.
- **The city asks you a question in one place, a human gate on the board,** and
  you answer there as at any other gate. The PR points at the gate and asks
  nothing itself. A comment you make on the PR while a question is open is read
  like any comment, and when it settles the question, the city's reply to it
  says so and the gate closes.
- **A red check or a conflict becomes work for the PR's own review run:** an
  ask to fix a required check that failed, one re-run of a check that failed for
  a cause no code fixes, an ask to merge the target into an approved PR that
  conflicts, and a gate only where the city cannot go on.
- **This effort deletes `pr-facts.sh`, `review-answer.sh`, three arms of the
  merge cadence and a doctor check** in its last unit.

Decisions to check, each settled here unless you say otherwise:

1. **The PR's review run repairs red checks and conflicts, not Gas City's PR
   monitor and its repair beads.** The monitor would put a second worker on the
   branch of every PR GitHub reads as blocked, one waiting on your approval
   included, and it cannot tell a required check from the rest.
   [Section 4](#4-red-checks-and-conflicts) names each difference from the
   monitor, its reason and what would end it. The other option is the earlier
   plan: run the monitor and tie its repair beads to the PR, at that cost.
2. **No webhook now.** A webhook is an optimization you take when you decide
   to, as a bead of its own. It would bring a comment in within seconds rather
   than within about 4 minutes, and it needs a public address GitHub can
   deliver to and a secret in your environment. Nothing is built for it, and
   the design stays ready for it: a delivery would run the same read of one PR
   that the city's check of every PR runs each 2 minutes
   ([section 5](#5-the-webhook)).
3. **One ask per comment, ruled together.** A review with ten inline comments
   files ten asks, which one run rules. A comment that asks for nothing costs
   triage's session, about 0.8M tokens, and the ruling step waking to find
   nothing, about 0.6M, where today's ruling session costs about 6.4M. An
   approval whose message says only "looks good" costs the same, and its merge
   waits for that short run: the city reads the message within about 4
   minutes, then triage's session and the ruling step's take about 2 and 1.5
   minutes as measured. An
   approval with no message files nothing
   ([section 3](#3-a-persons-post)).
4. **The retirement is a unit of this effort, and it waits only on what the
   code needs:** the landing-order effort (tk-1tfzr71.149), whose label writes
   replace `pr-facts.sh`'s, and the old merge path's retirement (tk-1tfzr71.70),
   which deletes the other callers of two shared files first. A `blocks` edge
   onto each rig's move states that no PR is on the old path when the
   retirement lands, and costs no time once the rigs have moved
   ([section 8](#8-the-cadence-and-the-order-of-the-retirements)).
5. **Where this departs from the bead's description.** The description names
   Gas City's PR monitor, its repair beads and the webhook receiver as the
   intake, and this design keeps the city's own repair model instead, for the
   reasons in decision 1. The description asks for both paths side by side on
   one rig before `pr-facts.sh` retires, and the operator's ruling of
   2026-11-16 drops that: a fault it would have caught shows on a live PR,
   where the operator's approval still gates the merge.

## From your seat

What you do and meet on a city PR, in the order you meet it. The sections
after this one give the mechanism.

**You comment.** A review's message, an inline comment and a conversation
comment are each read the same way. Within about 4 minutes the city puts 👀 on
your comment, which is how you know it has it, and the PR's label and its row
on the board read working. A review run rules it, together with every other
comment open on the PR: the run already working on the PR, or a new one when
none is. The round that rules it answers where you made it. An inline comment
gets a reply in its thread, which says what was done, the fix with its commit,
or a decline or a deferral with its reason, and the thread is resolved. A
review's message or a conversation comment that is owed words gets a reply
comment that links it, and a 👍 alone when nothing more is owed. You do
nothing more unless you disagree, and a new comment is how you say so.

**You request changes.** Each point of that review, its message and each inline
comment, is answered as above, and the PR reads working while the city works
them. Once every point is answered, the city dismisses your request with a
one-line note that counts what became of the points, fixed, declined, deferred
or answered, each answer being beside its point on the PR. It then asks you to
review again, which puts the PR back in your review queue on GitHub. The PR
reads needs-review once the city's work on it is done. A dismissed request is
not an approval: the PR merges only once you approve.

**You approve with a message,** such as "approved, but rename X". Your approval
stands, and the message is a comment as above: it gets 👀 and an ask, the PR
reads working rather than merging, and the merge waits until the city has
answered it. A message that asks for nothing, such as "looks good", is answered
by triage with a 👍, and the merge waits only for that short run. When the run
rules the fix a material change, your approval is withdrawn, as for any
material change after an approval, and the PR waits for your approval again.

**The city asks you a question.** When a run cannot rule a comment without you,
it files a human gate on the PR's bead. The board shows the gate on the PR's
row as what the row needs from you, and keeps the row owed until the gate is
answered. On GitHub the PR's labels read `status: needs-attention` and
`held: gate`, and the round's reply to the comment that raised the question
names it and says it waits on the board. Nothing on the PR asks for the answer.
You answer on the board, as at any other gate. The gate closes with your answer
as its reason, the row stops being owed, and the next run rules the comment by
your answer and replies to it with what it did.

**You comment while a question is open.** The comment is read like any other,
and a run rules it even while the question's gate holds the PR. When the
comment settles the question or makes it moot, the run closes the gate with
your comment named as its answer, and its reply to your comment says so in
plain words and names the question. When it does not, the reply says the
question still stands and waits on the board.

**The city finishes.** Once a run has passed at the PR's head, its required
checks pass and you have approved, the landing order merges it. The PR reads
merging and then merged, its bead closes, and the city's labels come off.

## 1. Where the intake reads and where it acts

The landing-order design splits the city's work on GitHub into reading and
acting ([its sections 3 to 6](../tk-1tfzr71.149/design.md#3-where-the-signs-are-kept)),
and each part of the intake sits where that split puts it.

- **The one-PR update reads and saves.** `gctk pr refresh` reads one PR on
  GitHub, only on the side whose signs moved, and saves what it read on the bead
  that owns the PR, in the PR's saved read (`pr_github_read`). It is the only
  writer of the saved read. The cheap question (`pr-poll`, every 2 minutes)
  runs it for each PR whose signs moved, the net (`pr-compare`, every 10
  minutes) for each PR whose facts differ from the saved read, and a webhook
  would run it for the PR a delivery names.
- **The update's conversation part gains the city's marks.** It reads the
  city's reactions on each review and each conversation comment
  (`reactionGroups { content viewerHasReacted }`), which gctk's reads ask for on
  inline comments already (`commentFields` in
  `services/gctk/internal/gh/gh.go`). In place of the newest feedback id in
  each id space, the conversation part keeps `untaken`: each feedback post that
  carries neither of the city's marks ([section 2](#2-the-receipts)), with what
  its ask's reason names, so the take decides from the bead.
- **The update's checks part gains each check suite at the head,** with its
  status, its creation time and the GitHub Actions run behind it with that
  run's attempt number (`workflowRun { databaseId runAttempt }`), fields on
  nodes its read returns already, for the re-run of a non-code failure and the
  check that never reports ([section 4](#4-red-checks-and-conflicts)).
- **The landing order acts from the beads.** `pr-reconcile`, every minute,
  decides each record from its saved read and the store. The intake's acts are
  among its acts: the take of each untaken post
  ([section 3](#3-a-persons-post)), the conversion of the old receipts
  ([section 2](#2-the-receipts)), and the red-check and conflict acts
  ([section 4](#4-red-checks-and-conflicts)). Each act runs under the record
  lock, guarded on the status and assignee read under it, starts no later than
  45 seconds into the run and stops at 30 seconds, in the run's shuffled order
  ([its section 5](../tk-1tfzr71.149/design.md#5-how-the-landing-order-starts)).
  An act that does not land leaves its difference on the bead, the next run
  acts on it again, and nothing records it.
- **The merge reads GitHub itself.** The merge's own read in its run is a whole
  read, so the evaluator's condition for each untaken post applies to it too. A
  comment made seconds before the merge, which no saved read holds yet, holds
  the merge.

**The take refreshes the PR once its marks land.** A reaction moves no sign the
cheap question reads: it leaves the post's own `updatedAt` where it was (all 7
of the city's reactions read on the 40 most recently updated PRs here were
later than their post's time), and it moves no count. So the take does not
wait for a pass to see its 👀. Once its marks have landed and it has released
the record lock, it runs the one-PR update for the PR's conversation, as a
webhook rule would, and the saved read shows the marks before the next run
decides. The update stays the only writer of the saved read. A mark that did
not land leaves the post untaken in that read, and the next run marks it again.

**When a comment reaches its take.** A conversation comment moves the PR's
comment count, an inline comment the comment and review counts, and a review
the review count
([its section 1](../tk-1tfzr71.149/design.md#1-the-cheap-signs)). So a comment
reaches the saved read within the cheap question's 2 minutes and its take
within the landing order's next minute, each run starting up to 30 seconds late
at the next lane pass: about 4 minutes at the most, and about 2 on average
([its section 6](../tk-1tfzr71.149/design.md#6-the-orders-and-their-cadence)).

**A review that sits below the newest id.** A person can start a review, see
another post land, and submit the review afterwards. GitHub gives the review
and its inline comments ids from when they were started, so they can sit below
the newest id. The late review raises the review count, so the cheap question
reads the PR as moved and the update reads its conversation. There the review
and its comments carry no mark of the city's, whatever their ids, so they are
untaken and the take files them. No receipt is a high-water mark, so nothing
can fall below one.

**Nothing read is lost.** Each pass compares what GitHub shows now with the
signs saved on the bead, so an event the city never received costs nothing:
the next pass reads its result. A post the city has not taken stays in the
saved read's `untaken` until its mark lands. A read that fails changes nothing,
and the next pass reads again. An edit of a post the city has taken files
nothing new: the run reads the post at its URL as it stands when it rules it,
and an edit made after its ruling is not ruled again, while a new comment is.
An edit that takes the not-for-review mark out of a post makes it feedback
with no count moved, and the net, which reads each post's time, finds it
within its 10 minutes.

## 2. The receipts

A post is taken when it carries one of the city's two marks, which the
definition of feedback reads:

| Mark | Put by | Says |
|---|---|---|
| 👀 (`EYES`) | the take, once the post's ask is filed | the city has the post and owes it an answer |
| 👍 (`THUMBS_UP`) | the post that answers a round, made by the ruling step or by triage, once a ruling leaves the post owed nothing more | the city owes the post nothing more |

A feedback post that carries neither is **untaken**. The definition stays one
copy, in `assets/scripts/pr-post.sh`, which gctk reads through its feedback
adapter. `gc_city_handled` already reads the 👍 there, and unit 1 adds
`gc_city_taken` beside it for the 👀. A mark is the reader's own reaction
(`viewerHasReacted`), so it reads the city's account without a login read of
its own.

What reads the receipts:

- **The evaluator.** Its feedback condition (`unhandled` in
  `services/gctk/pr/feedback.go`) becomes one condition for each post in the
  saved read's `untaken`. The review threads waiting on the city's answer stay
  as they are (`awaiting`, through `gc_thread_awaits_answer`).
- **The approval withdrawal.** `unrouted` (`services/gctk/pr/feedback.go`,
  through `services/gctk/pr/withdraw.go`) becomes the untaken feedback posts of
  the approvals the withdrawal would dismiss: each approval's own message and
  its inline comments, read with their marks. A dismissal retires both: the
  intake counts no dismissed review's message, since `countedReviewStates`
  holds no `DISMISSED`, and the definition leaves out a dismissed review's
  inline comments (`live_comments`). So a withdrawal waits until the take has
  filed every post a dismissal would retire. The message is in that set because
  the landing order acts on a withdrawal in the first run that reaches its
  record, from the saved read, whether or not the take has filed the approval's
  message yet. Without the message in the set, an approval that says "approved,
  but rename X" and carries no inline comment would be dismissed for a material
  newer head before its message is taken, and its request would be lost.
- **The approving review's message.** `countedReviewStates` gains `APPROVED`,
  so an approval that carries text is a post like any review's
  ([the merge design's section 3, case 1](../tk-1tfzr71.66/design.md#3-how-an-approval-behaves-when-the-pr-changes)),
  and the withdrawal above waits on it while it is untaken.

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
`pr-facts.sh` to the one-PR update, which stamps it in the write that saves the
first conversation it reads for a bead that lacks it, the instant the
conversation part already applies the definition from
([its section 3](../tk-1tfzr71.149/design.md#3-where-the-signs-are-kept)).
While the city's login does not resolve, the conversation read fails and
nothing is taken (`Login` in `services/gctk/internal/gh/gh.go` refuses an
answer with no login), so no post is read as the city's own on a misread.

**The old receipts on a moved bead.** Every rig moves onto the new merge path
while `pr-facts.sh` still serves its comments, so each bead open when this
effort lands carries `pr-facts.sh`'s receipts: the watermarks, the answered
marks and the batch ledgers. The landing order converts them, as an act it
decides from the bead, and takes no post on a bead that still carries them, so
no post the old path routed is filed twice. The conversion makes its own read
of the PR's posts and threads, once. It puts the city's 👀 on every feedback
post at or below those marks that carries neither mark, resolves each
unresolved thread that holds only the city's own posts (the old path's machine
findings, which the rig's move closed), files the post of each open human
finding as its ask and closes the finding as superseded by it, unsets the old
keys, and runs the one-PR update for the PR (unit 3). A post `pr-facts.sh`
marked 👀 when it routed it is taken already, so the conversion leaves it as it
is. Each open bead is converted in the landing order's first runs after the
effort lands. The conversion is removed once no open bead carries the keys, by
a bead filed beside the units ([section 11](#11-the-units)).

## 3. A person's post

**The form.** Each post a person makes is one ask on the bead that owns the PR
(`gctk review ask`, `FileAsk` in `services/gctk/review/ask.go`): a review that
carries a message, an inline comment, or a conversation comment. The ask's
reason is one line naming the post: its kind, its author, the PR, an inline
comment's file and the line it was made on (`originalLine`, which a later push
does not move), and its URL. It is the ask the review-lanes design gives work
on a PR's branch
([its section 1](../tk-1tfzr71.108/design.md#asks-work-on-the-prs-branch)), so
no bead kind comes with it.

The take files it, then marks the post 👀. `FileAsk` finds an ask with the same
reason, open or closed, and files none, so a post whose mark did not land is not
filed twice on the retry, and an edit of the post's text changes nothing the
reason holds. The text stays on GitHub, where the run reads it at the post's
URL, so the run rules the post as it stands, and the head's comment, which
shows an ask by its reason on one line, names the post without repeating it.

**Which posts start a run.** The definition of feedback decides, and it goes by
marks, never by who posted (`gc_feedback` in `pr-post.sh`'s `feedback-def`). A
post is feedback unless it is the city's own or is marked not for review:

- **The city's own** is a post under the city's login that carries the city's
  mark, or that was made before the PR's provenance instant. A post under the
  city's login without the mark is feedback, such as one a person's own session
  posts under that login.
- **Not for review** is a post whose body opens with `<!-- gc:no-review -->`,
  or begins with a prefix the rig declares in `not-for-review.toml` at the root
  of its repository ([not-for-review.md](../../docs/not-for-review.md)). A
  rig marks a bot's posts that way: the mark where the rig writes the bot's
  text, and a declared prefix where it cannot. A bot's comment that carries
  neither is feedback, like a person's. This rig declares no prefix.

So a person's review message, inline comment, conversation comment and approval
message each become an ask, and so does a bot's comment the rig has not marked.
The city's own posts, a marked or declared post, an approval with no message,
a reaction, and an edit of a post already taken become none.

**Posts read together start one run.** The landing order pours one review run
for a PR at a time, only while no run is attached to its bead
(`services/gctk/pr/admit.go`), and the run's ruling step rules every ask open on
the PR at once. So posts the take files together, such as a review's message
and its ten inline comments, are one run. Nothing waits for a quiet period
before a run starts: the first post taken starts it, and posts taken while it
works join it.

**What a post costs.** A post taken while a run works joins the round whose
ruling step has not yet read the asks, or adds a round, up to the run's three
(`max_attempts` in `formulas/mol-pr-review.toml`). A post taken after a run
has ended starts a new one: triage, the lanes when the head needs checks, and
the ruling step. By the measurement of 2026-11-15, recorded on tk-ileeqzz, a
run for a comment that needs only an answer costs about 7.7M tokens and about
12 minutes of session time, of which the ruling session is about 6.4M and
triage about 0.8M. With the cheap answer below, triage answers such a comment
and the ruling step wakes, finds nothing and closes, about 0.6M at a session's
floor by the same measurement.

**The cheap answer.** Triage answers a post that needs only an answer, or needs
nothing, and closes its ask, and the ruling step does no work for it (unit 6).
Triage rules a post `answered` only when it asks for no change to the branch
and no person's decision, such as a question about the change, a thank-you or
an approval's "looks good", and leaves every other post to the ruling step. Its
answer is posted as any answer is ([section 6](#6-the-write-back)): a reply
where words are owed, and a 👍 where nothing is. What that takes, from
tk-ileeqzz's account of the code:

- Triage's output carries a ruling for each ask it answers, and the pass rule
  (`judge` in `services/gctk/review/passed.go`), the result writer
  (`answeredAsks` in `services/gctk/review/result.go`) and the head's comment
  (`services/gctk/review/comment.go`) read triage's rulings beside the ruling
  step's.
- Triage posts its answers through `review-run.sh post`, which serves only the
  ruling step today.
- The ruling step stays in the round. Gas City fixes a round's steps when it
  creates the round, and a step bonds one formula from its output
  (`OnCompleteSpec` in `internal/formula`), which triage's lanes take. When
  triage leaves it no ask and no finding, the step's read says so, and the step
  closes at once.
- The review-triage skill, which says triage classifies and never judges, gains
  the bar above.

tk-ileeqzz, held for the operator's placement, is that unit: the implementation
child closes it as superseded by unit 6, which carries its done. Its done reads
"no ruling or fixing session runs for it", and unit 6 departs from that one
clause: the ruling step's session still wakes and closes, at its floor, since
no step of a round is skipped once the round is made.

**The two beads on the filter.** Two open beads say where the filter reads a
post wrongly today:

- **tk-306xmm6,** `pr-facts.sh` reading an outdated thread it has answered as
  unanswered: settled by this effort. On the new intake a post is taken once by
  its mark, whatever its thread's state, and a thread waits on the city only
  while its newest live post is feedback with no 👍
  (`gc_thread_awaits_answer`), so a thread the city answered holds nothing. The
  bead keeps its edge onto tk-1tfzr71.21 and its arm for the validating closer,
  which checks it once the effort lands.
- **tk-8685r0a,** the feedback miner reading a person's own posts under the
  city's login as the city's: not settled here. The intake reads such a post as
  feedback, which is what that bead's done asks of it, and the miner's half
  stays with that bead.

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
  findings under their asks. No human finding is left on a bead once the take
  files asks and the conversion supersedes any that a moved bead carries.
- The loop's record (`recorder.record` in `services/gctk/internal/cli/review.go`)
  no longer runs `finding.sh close-answered`, for the same reason. `finding.sh`
  itself stays until tk-1tfzr71.122 deletes it.
- A deferral's follow-up is filed by `review-run.sh defer`, which takes the
  PR's target as its own already. `review-run.test.sh` gives its defer case a
  fixture target other than `main`, as the validating close of tk-grjsnf6
  asks, since the finding verb's case goes with the verb.

**The operator's three ends.** In conversation tk-2m30oko (2026-11-13) the
operator said the city owns every comment: "If a comment shows up, its job is
to evaluate the comment, act on that comment, and do one of, I think, three
things", which are to fix it and mark it resolved, to rule on it, decline it
and resolve it, or to say "I need to talk to a human" and use a human gate.
Each maps onto a ruling of the post's ask:

| The operator's end | The ruling | What the PR shows |
|---|---|---|
| Act on it: fix it and mark it resolved | must-fix, with the commit that fixes it | the head's comment names the commit, and the round that rules it, at a head carrying the fix, replies in the thread naming the commit and resolves it |
| Rule on it: ignore or decline it, and resolve it | declined, deferred or answered | the round's post replies with the reason and resolves the thread, or puts 👍 where nothing more is owed |
| Talk to a human | question, with its gate | the gate asks you on the board; the PR's labels read needs-attention and `held: gate`; the round's reply names the question and says it waits on the board; the thread stays open until the question is settled |

The same words say "a PR with new comments added, goes from whatever state it's
in to working". `prstatus.Render` reads an approved PR whose only conditions
are the city's work as merging (`services/gctk/prstatus/render.go`). Unit 2 has
it read a PR with an untaken post, or an open ask that carries a person's post,
as working ahead of merging. "If it can't resolve all the comments, then it goes
to needs-attention": an open gate already reads needs-attention there.

**A question has one place.** The run asks a person through a human gate on the
PR's bead (`review-run.sh question`, which files it under the key
`review-question-<slug>`), and the person answers it on the board, as at any
other gate. The PR points at the gate, through its labels and through the
round's reply to the comment that raised the question, and nothing on the PR
asks for the answer. A question's ask stays open until its gate is settled
(`answeredAsks` in `services/gctk/review/result.go`), and the run records no
passed result while the gate is open.

**A comment made while a question is open** is feedback like any other: the
take files its ask, the PR reads working, and a run rules it. The landing order
pours no run while a human gate holds the bead today
([the review-lanes design's section 1](../tk-1tfzr71.108/design.md#what-pours-it)),
so such a comment would wait behind the gate. Unit 4 lets the order pour a run
while the only gates holding the bead are questions a review run put to a
person and an ask for a person's post was filed after the newest of them. That
run rules the new posts. When one settles a question or makes it moot, the run
resolves that gate with the post as its answer, headed `ruled:` or `moot:` with
the post's words and its URL, and its reply to the post says so in plain words
and names the question. When none does, the gate stays, and the reply says the
question still stands and waits on the board.

## 4. Red checks and conflicts

**The repair model.** A red check or a conflict on a city PR is an ask on the
PR's own bead, filed by the landing order from the saved read, which the PR's
review run works. Gas City's PR monitor files repair beads instead. For the
PR's own record the pack already writes Gas Town's keys and more: the bead that
owns a PR on the new merge path carries Gas Town's record, `merge_result`,
`pr_url`, `pr_number`, `pr_state`, `pr_last_checked_at` and the rest, with Gas
Town's values and meanings (`services/gctk/pr/record`), and the saved read
beside them. For repair work the design differs from the monitor in three ways,
each read at upstream main 994008c628:

| Difference | Gas City's monitor | This design | Why | What would end it |
|---|---|---|---|---|
| Who repairs | a standalone task at priority 1, labeled `github`, `ci`, `repair` and `pr-monitor`, routed to the monitor's `repair_route`, which validation requires, with the monitor's `repair_workflow` poured on it, so a second worker writes the PR's branch (`ensureGitHubPRRepairBead` in `cmd/gc/cmd_github.go`; `repair_route is required` in `internal/config/github_pr_monitor.go`) | an ask on the PR's own bead, which the PR's review run works | the review run is the one writer of a PR's branch while it works ([the review-lanes design, section 1](../tk-1tfzr71.108/design.md#what-pours-it)), and a second writer would push beside it | nothing upstream: the reason is the city's one-writer rule, and no gap in Gas City |
| Where GitHub's facts live | copied onto the repair bead in `github.*` keys: the failure kind, the merge state, the failed and pending checks and more (`githubPRRepairVolatileMetadata` in `cmd/gc/cmd_github.go`) | kept once, in the PR's saved read, which the one-PR update alone writes | tk-1tfzr71.21's Done: one GitHub read per PR, and nothing else mirrors GitHub state into bead metadata | nothing upstream: the reason is the same one-copy rule |
| When repair is filed | for every PR `classifyPullRequest` calls actionable: a failed check, `DIRTY`, `BEHIND`, `UNSTABLE`, or `BLOCKED`, which includes a PR that only waits on an approval (`internal/githubmonitor/monitor.go`) | for a required check that failed at the head, and for a conflict once the PR is approved | the monitor's query reads no check's `isRequired` (`pullRequestsQuery` in `internal/githubmonitor/client.go`), so a check that is not required counts; `checkFailed` spells the cancelled conclusion `CANCELED` where GitHub spells `CANCELLED`, so `checkPending` reads a cancelled check as pending; and a PR waiting on a review needs no repair | upstream reading each check's required flag at the PR's number, spelling the conclusion as GitHub does, and filing nothing for a PR that only waits on a review: then the city could take the monitor's classification, and its repair would still go to the PR's run, by the first row |

The monitor also runs only when asked: `gc github pr backfill` is the only
caller of its listing (`ListOpenPullRequests`, called from
`cmd/gc/cmd_github.go`), and nothing in Gas City schedules it.

This reverses the earlier plan. tk-1tfzr71.21's description names
`[[github.pr_monitor]]` with `--create-repair-beads` as the upstream-native
intake, and the merge design's sections 4 and 11 have this effort build a join
that ties each repair bead to the bead that owns its PR
([specs/tk-1tfzr71.66/design.md](../tk-1tfzr71.66/design.md#4-where-triage-sits-and-how-the-city-decides-to-merge)).
So the city declares no `[[github.pr_monitor]]`, and the join is not built. The
city's config declares no monitor and no webhook today.

The two faults in the third row's reason, the missing required flag and the
cancelled conclusion's spelling, are findings the operator may send upstream.
This design sends nothing.

**The acts.** Each is decided from the saved read and the store by the landing
order, and taken under the record lock within its limits. An act that files
work, re-runs a check or files a gate is skipped while a hold set by hand
(`merge_hold`, `rebase_hold`) or a human gate holds the bead, as
`pr-facts.sh`'s red-check arm stands down today, since bringing the branch
current or sending a fixer performs one horn of what a person may be deciding.
A conversation on the PR holds only its merge (tk-1tfzr71.164, #1541), so it
skips none of them. The withdrawal of a red-check gate is never skipped:

- **A code failure.** A required check whose latest result at the head is
  `FAILURE`, and whose name is not a deploy's, gets an ask naming the PR, the
  head, the failing checks with their run logs and the branch to fix, the
  reason `pr-facts.sh` gives its ask on the new merge path today, one per head. Two
  bounds read the bead's red-check asks, open or closed, each of which names
  its head: a closed ask at this head with the PR still red there files a gate
  (`pr-fix-unmoved.<n>`) in place of a second ask, and a red head after three
  earlier heads each drew an ask files a gate (`pr-fix-capped.<n>`) in place of
  a fourth, as `pr-facts.sh`'s cap of three does today. A deploy's failure
  files a gate.
- **A non-code failure,** one that timed out, was cancelled, failed to start or
  wants an action. The order re-runs the failed jobs of each GitHub Actions run
  that holds such a failure, once per head, and only once those runs have
  finished, which their check suites' status in the saved read shows, since
  GitHub re-runs a run's failed jobs only once the whole run has finished.
  A re-run keeps the run and its check suite and raises the run's attempt
  number, so GitHub itself records it. The head reads re-run once a run at the
  head that holds a required check shows an attempt above 1 on the suites in
  the saved read, whoever re-ran it, and no key records it. One run's own
  attempt cannot bound the head, because each new run at a head starts at
  attempt 1, and a head carries several: one for each workflow, and one more
  each time an event starts a workflow again, such as an edit of the PR's
  body, which starts this repository's pr-size workflow. A failure at a head
  that reads re-run, a re-run GitHub refuses, and a failure outside any Actions
  run each file a gate (`pr-fix-noncode.<n>`) only on an approved PR. An
  unapproved PR waits for its review, and a refused re-run is asked for again
  at the next run, since nothing records the refusal.
- **The gates withdrawn.** Each red-check gate on the bead closes as moot once
  the saved read shows every required check passing at the PR's head. The gate
  is named under its key by the order `human-gate.sh`'s dedup uses (created,
  then id), as tk-1tfzr71.21's note of 2026-10-30 asks.
- **A required check that never reports.** At an approved PR whose review
  result passed at its head, GitHub reads `BLOCKED`, the saved read lists no
  required run at the head, and a check suite there has stayed queued with no
  runs for ten minutes since its creation. A suite that never starts moves no
  sign, so the saved read still holds it as queued, and the order compares its
  creation time with the clock. The order returns the PR to draft and marks it
  ready again, which sends the `pull_request` event that restarts the workflow,
  with the draft verbs the review-lanes effort built. The notes of 2026-11-12
  found a re-run of the stuck run refused and a dispatched run's checks not
  counted. It does this once per head beyond the draft cycle's own transition,
  counted from the PR's timeline, and files a gate (`pr-check-unreported.<n>`)
  after that.
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
The first is kept by the attempt numbers of the head's runs, where
`pr-facts.sh` records the head in `pr_check_rerun`. On the new merge path the
park is only the gate, which is withdrawn once the checks pass.

## 5. The webhook

Nothing is built for a webhook. It stays an optimization the operator takes
when they decide to, as a bead of its own.

**What it would buy.** A comment would reach its take within seconds of the
delivery, rather than within the cheap question's 2 minutes and the landing
order's minute. Nothing is lost without it: the cheap question reads every PR
the city owns at every pass, and GitHub does not redeliver a delivery that
failed, so even with a webhook the cheap question stays the backstop
([the landing-order design's section 8](../tk-1tfzr71.149/design.md#8-the-webhook)).

**What it would ask of the operator.** GitHub delivers only to an address it
can reach, and the city's API is served on the tailnet only (`tailscale serve
status` and `tailscale funnel status`, read 2026-11-16), so a webhook needs a
public route to the service that receives it, guarded by GitHub's signature,
and a secret for that signature in the operator's environment.

**Why the design is ready for it.** The route that fits is the github pack's
webhook service, whose rule for an event that names a PR runs `gctk pr refresh`
for that PR and then the landing order
([the landing-order design's section 8](../tk-1tfzr71.149/design.md#8-the-webhook)).
The one-PR update saves the PR's untaken posts like any other part of its read,
and the landing order takes them, so a delivery reaches the take through the
same two calls the cheap question makes, and the intake needs no change for it.
Gas City's own receiver does not fit: a public hook may fire only a formula
order, never an exec order (`routeOrder` in `internal/webhooksink/sink.go`), so
each delivery would wake an agent, and a private or tenant hook answers no
request GitHub makes (`webhookRequestAllowed` in
`internal/api/handler_webhook.go`).

## 6. The write-back

The take keeps one act on GitHub, the 👀 that takes a post. The answers are made
in the post that answers a round (`review-run.sh post`, part 6 of the ruling
step in `formulas/mol-pr-review.toml`), which the ruling step makes for the
asks it ruled and triage for the asks it answered (unit 6), because the step
that rules a post is the step that knows what became of it. The loop's check,
which records the run's result, cannot make them: Gas City runs it with HOME
set to the city's directory and a whitelist of variables that carries no GitHub
token (`ConditionEnv.Environ` in `internal/convergence/condition.go`), so gh
has no login there, and `gctk review passed` reads only the store.

| Act today | What becomes of it |
|---|---|
| 👀 on each routed post (`pr-facts.sh`'s sweep) | the take, right after the post's ask is filed |
| A reply in an inline comment's thread with its answer | the round's post, for each ask ruled declined, deferred or answered, or put to a person |
| A reply to a post that has no thread, a review's message or a conversation comment | the round's post, as a conversation comment of the city's that links the post, where the ruling owes words: declined, deferred, answered, put to a person, or settling a question |
| Resolving the thread | the round's post, behind the reply its own read shows, for an ask the round ruled; a question's thread stays open until the question is settled |
| 👍 where nothing more is owed | the round's post, on a post whose ruling leaves it owed nothing more |
| One living answer per review (`review-answer.sh`) | goes: each post has its own answer beside it, and the head's comment (`gctk review comment`) shows each ask's ruling |
| Dismissing a person's request for changes once every point is answered | stays, made by the round's post: once every ask from a request for changes has its answer on the PR, the post dismisses that review with a one-line note and asks its author for a review again |
| Dismissing the city's own superseded request for changes | goes: no open PR carries one (0 of 27 in the city's six repositories, 2026-11-16 05:31Z), and the sign-off posts a review that comments |
| Posting an old-path machine finding to the PR | goes with the old path |

**The dismissal of a request for changes.** A person's request for changes
holds the merge and is GitHub's own blocking signal, so a review answered in
full but left standing tells its reader the opposite of the truth, as the rule
in `pr-facts.sh` says today. So once every point a request for changes raised
has its answer on the PR, a must-fix point fixed at a head the round pushed and
each other point answered by its ruling, the round's post dismisses that review
and asks its author for a review again, which puts the PR back in their queue
to judge the result, its declined and deferred points included. GitHub
dismisses review objects, so each review is dismissed on its own, once the asks
for its message and for each of its inline comments are answered, which the
post's own read of the review's comments ties together. A question's point is
answered once its gate is settled and the run has posted what it did. The
dismissal's note is one line: how many of the review's points were fixed,
declined, deferred or answered, each answer being beside its point on the PR.

**What the PR reads after the dismissal.** A dismissed review counts for
nothing in the approval rule, so the person is neither an approver nor a
requester, and the evaluator waits on an approval. The PR reads needs-review
once the city's work on it is done, and working while it is not, and never
merging (`prstatus.Render`): a dismissal is not an approval, and the merge
waits for an approval given after it. One case needs a change for that to hold.
The approval rule (`approval()` in `services/gctk/pr/rules.go`) takes each
account's latest review that approves or requests changes and skips a
dismissed one, so an approval the person gave before the request for changes
would stand again once the request is dismissed. Unit 4 has the rule read a
dismissed review as its account's latest opinion, standing for neither, so an
earlier approval stays superseded. In this repository's last 100 PRs, each of
the nine dismissed requests for changes was its reviewer's first review on the
PR, so no case has met this yet.

**Bounds.** Each reply carries a marker that names its ask, as the head's
comment carries one that names its run and head
(`services/gctk/review/comment.go`), a 👍 is found by the city's own reaction,
and a dismissal by the review's state, so a post run again posts nothing twice.
A write that does not land exits 1, as the head's comment does today, and the
step's exit criteria keep it open until the post lands. The loop's check closes
the asks a round answered only after that round's step has closed, so an ask
closes only once its answer is on the PR.

**The thread rules from PR #1492's reworks,** recorded in tk-1tfzr71.21's notes
of 2026-11-13, each kept:

- Resolve every thread the city rules on behind its answer: the round's post.
- Keep a needs-you thread open until its gate is ruled: the round's post
  leaves a question's thread open.
- Route a reply in a thread the city resolved as feedback: a new post carries
  no mark, so the take files it.
- File no gate that mirrors GitHub's thread state: no thread gate exists.
- Resolve a ruled thread only behind an owed reply the same read shows, never
  on a stored stamp (tk-4g6ra0p): the post resolves after reading its reply.
- A post whose own ruling declined or deferred it is answered by that ruling
  (tk-a4j0uiu): each post is its own ask, answered by its own ruling.
- Resolve a declined or deferred machine finding's thread on any PR
  (tk-axacdyl): on the new merge path a lane's finding is answered in the
  head's comment and opens no thread, and the conversion resolves the old
  path's machine-finding threads.

**The 👍 stays the mark of nothing more owed.** `gc_thread_awaits_answer` reads
it through `gc_city_handled`. `pr-post.test.sh` reads the two reaction names
from `pr-facts.sh` (`WB_REACTION`, `WB_RESOLVED_REACTION`), and unit 4 points
that check at the constants in the Go writer.

Three other notes on the write-back are met by each answer being the ruling's
reason. A point that went to a follow-up is answered with the follow-up, never
as fixed, and its thread is resolved, as the operator said on 2026-11-06:
"resolve the comment if it's scheduled, that's more than sufficient for the
city to resolve it". A declined lane finding has its answer beside its lane's
verdict in the head's comment. A declined point's code changes only through a
ruling that reopens it, by the skill's "A decline stands".

## 7. A city on the new merge path

**Every rig is on the new merge path before this effort lands.** This rig
moves once tk-1tfzr71.89 and tk-1tfzr71.165 have landed (tk-1tfzr71.164 landed
on 2026-11-16), and the other five rigs move together once this rig's first PR
has merged on the new path, as the cutover beads' notes of 2026-11-16 say. No
rig's move waits on this effort, because `pr-facts.sh` serves a PR's comments
on the new path until this effort deletes it. So the units are written for the
new merge path alone, and no clause of theirs keeps a PR on the old path
working.

**What guarantees no PR is on the old path.** The retirement unit, which
deletes the code a PR on the old path would need, carries a `blocks` edge onto
each rig's cutover bead (tk-1tfzr71.78, .80 to .84). They close before the
units build, so the edges cost no time, and they state the guarantee where a
reader of the unit looks. Its drain check reads every store before it deletes
anything, and a bead found on the old path goes to a person. The other units
build code that runs only once the effort lands, after the retirement unit, so
none of them needs a clause that turns `pr-facts.sh` off: they change nothing
in it.

**The posture's readers.**

| Reader | What it reads once the effort lands |
|---|---|
| `prio_pr_approved` in `assets/scripts/priority-lib.sh` | the saved read's approvers at the head the store holds, which `approval()` in `services/gctk/pr/rules.go` computed (unit 2); the retirement unit deletes its clause for `pull_request` |
| `prstatus.Derive` and its read in `services/gctk/prstatus` | nothing: the retirement unit deletes the old path's clause with the keys, and moves `prstatus` under the pr domain onto the ledger, the debt `docs/gctk-architecture.md` gives this member |
| `gctk merge`, `merge.sh`, `merge-tail-report.sh` | old merge path code that tk-1tfzr71.70 deletes |
| the helm board (`services/helm/internal/board/derive.go`) and `bead-context.sh` | nothing: the retirement unit deletes their old-path clauses with the keys, where the board member (tk-1tfzr71.24) has not |
| `doctor/check-feedback-routing-owed` | deleted by the retirement unit |

**The rank.** The PR-finishing rank reads approval from the saved read, never
from `reviewDecision`, which settles tk-os61zl6's ask for the new merge path.
`pr_finishing_settled` goes: the fifteen-minute priority reconcile
(`orders/queue-priority.toml`) settles that work at the rank the function reads,
so a rank needs no record of its own, at the cost of up to fifteen minutes for
a bead `pr-facts.sh` re-ranked in its own pass. On the new merge path the
PR-finishing work that carries `anchor_bead` is only an old-path rework child a
rig's move left open. Whether a review run ranks as PR-finishing work is
tk-go9npun's, held for the operator, and it would read approval the same way.

**The labels.** The retirement unit waits on tk-1tfzr71.149 as a whole, whose
label writes replace `pr-facts.sh`'s label reconcile
([its section 9](../tk-1tfzr71.149/design.md#9-labels)).

**When the intake faults after the effort lands.** No old path runs beside it,
so a fault is fixed forward, as any fault in the landing order is. What a fault
costs and where it shows:

- **A fault delays and never merges over a comment.** A post the take could not
  file stays in the saved read's `untaken`, which holds the PR's merge through
  the evaluator's condition, and the merge's own read holds it for a post no
  saved read has yet. A take that keeps failing leaves its PR waiting, as a red
  check does, and every other PR's acts go on, since the landing order takes
  records in a shuffled order and stops each act at 30 seconds.
- **It shows on the PR and the board.** The comment carries no 👀, and the PR
  reads working with no run on it, on its label and on the board. A run of the
  landing order in which a take failed exits non-zero, so Gas City's run
  history records it as failed, as the cheap question's history does a read
  that failed.
- **Nothing switches back.** The effort deletes `pr-facts.sh`, so the repair is
  a fix to the intake, filed as a bead like any defect, and the PR the fault
  held goes on once the fix lands.

## 8. The cadence and the order of the retirements

**The intake's cadence is the landing-order design's.** The cheap question runs
every 2 minutes, the landing order every minute and the net every 10 minutes
([its section 6](../tk-1tfzr71.149/design.md#6-the-orders-and-their-cadence)).
The intake adds no order and no GitHub request to a pass that finds nothing
moved. What it saves of GitHub is read by the one-PR update, and its other
GitHub calls are its acts, each made only where an act is due: a mark and the
refresh after it, the conversion's one read of a moved bead, a re-run, and a
draft cycle.

**The merge cadence.** `refinery-reconcile.sh` runs the merge cadence's arms
every sixty seconds:

| Arm | Script | Retired by | Once this effort lands |
|---|---|---|---|
| before the arms | `merge-tail-report.sh` | tk-1tfzr71.70 | gone already |
| 1 | `pr-facts.sh --posture-only` | this effort's retirement unit | removed |
| 2 | `merge.sh` (`gctk merge`) | tk-1tfzr71.70 | gone already |
| 3 | `pr-open.sh` | tk-1tfzr71.70 deletes its create path | whatever tk-1tfzr71.70 leaves runs on |
| 4 | `pr-facts.sh --route-comments-only` | this effort's retirement unit | removed |
| 5 | `pre-open-rebase.sh` | tk-1tfzr71.70 | gone already |
| 6 | `gate-ensure.sh` | tk-1tfzr71.122 | runs until tk-1tfzr71.122 |
| 7 | `pr-facts.sh` | this effort's retirement unit | removed |
| 8 | `review-sweep.sh` | tk-1tfzr71.122 | runs until tk-1tfzr71.122 |
| 9 | `scaffolding-sweep.sh` | tk-1tfzr71.122 | runs until tk-1tfzr71.122 |

So the driver outlives this effort: once it lands, the driver drives the old
review path's last arms, which close the residue that tk-1tfzr71.122's drain
check counts. Its rows (`refinery-reconcile.sh` with its test, and
`orders/refinery-reconcile.toml`) move to tk-1tfzr71.122, which deletes it with
those arms. `pace-lib.sh` and its test move there too: besides `pr-facts.sh`,
its sourcers are `gate-ensure.sh`, `pr-open.sh` and `pre-open-rebase.sh`, and
once tk-1tfzr71.70 has deleted `pre-open-rebase.sh` and the old-path walks of
`pr-open.sh`, and the retirement unit has deleted `pr-facts.sh`,
`gate-ensure.sh` is the last. The retirement unit removes arms 1, 4 and 7 and
what is left of the block that holds the merge on the posture.

**The order of the three retirements** is tk-1tfzr71.70, then this effort with
its retirement unit, then tk-1tfzr71.122. Each wait is one the code needs:

- The retirement unit waits on tk-1tfzr71.70, because `record-failure-cap.sh`'s
  other caller is `gctk merge` and `branch-supersession.sh`'s other caller is
  `pre-open-rebase.sh`, both deleted there. The unit then deletes both files.
  `lifecycle.sh`'s row, which tk-1tfzr71.70 adds once it has reduced the script
  to a plain write, comes under the retirement unit, which deletes it once no
  caller is left, as the merge design's section 10 plans.
- The retirement unit waits on tk-1tfzr71.149, whose label writes replace
  `pr-facts.sh`'s label reconcile.
- tk-1tfzr71.122 keeps its edge onto tk-1tfzr71.21, because `pr-facts.sh` calls
  `finding.sh` until the retirement unit deletes it, and because
  `gate-ensure.sh` needs `pace-lib.sh` and `bring-current-guard.sh` needs
  `review-dismissal.sh`, which is why those files' rows move to it.

The steps a staged rollout added are gone: the comparison of the two intakes
over every open PR, a gate for a difference it found with no reason, and the
first rig to move after the effort lands as a live side by side. Each would
have caught a post the two intakes read differently, such as one the old path
had routed that the new path reads as untaken. Such a post now shows on a live
PR on the new path, as an old comment answered a second time or a comment left
without its 👀, where the operator's approval still gates the merge.

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
and nothing else mirrors GitHub state into bead metadata." Under the
landing-order design that writer is the one-PR update, which the cheap
question, the net and a webhook call, and the landing order reads that read and
saves none of it
([its section 12](../tk-1tfzr71.149/design.md#12-the-github-intakes-finish-line)).
The intake keeps to it: what it saves of GitHub the update saves, and its acts
write asks, gates and the city's marks, never a copy of GitHub's state. Each key
`pr-facts.sh` writes:

| Key | Becomes | Why |
|---|---|---|
| `pr_posture` | goes | the saved read holds the approvers and requesters `approval()` finds, and the rank reads them |
| `pr_merge_state` | goes | the saved read holds the merge state |
| `pr_head_oid` | goes | the saved read holds the head, and the record holds the validated one |
| `pr_finishing_settled` | goes | the priority reconcile settles the rank by comparison |
| `pr.conversation` | goes | the board renders the evaluator, and an untaken post or an open ask is the conversation's state |
| `pr_comment_watermark`, `pr_review_watermark`, `pr_issue_comment_watermark` | go | the city's marks on GitHub are the receipts; the conversion unsets them |
| `pr_comment_answered`, `pr_review_answered` | go | the same |
| `pr_comment_batch`, `pr_review_batch`, `pr_issue_comment_batch`, `pr_comment_disposition` | go | each post's ask names it, and its own ruling answers it |
| `pr_unengaged_threads` | goes | the old path's gate for unmarked threads under the city's login; no open bead carries it (2026-11-16), and the conversion resolves such threads |
| `pr_check_rerun` | goes | the attempt numbers of the head's Actions runs, on the suites in the saved read, say whether the head was re-run |
| `status_label_clear_owed` | goes | tk-1tfzr71.149's label comparison retries any clear |
| `pr_url`, which it writes beside `status_label_clear_owed` on a bead that names none | the write goes | the PR's URL is the record's own key (`services/gctk/pr/record`) |
| `signoff_dismissed` | goes | no city request for changes stands to dismiss |
| `merged_sha` and `merge_record_failures` in its merged arm, `blocked_reason` in its abandoned and retargeted parks | go with the old path | on the new merge path the landing order writes a bead's end and files its exceptions |
| `pr_provenance_since` | stays, written by the one-PR update | a receipt of the city's own act |
| the keys on the children it files: rework children, validation passes, human findings | go with those forms | the ask is the one form on the new merge path |

`gc.pr_close_disposition_*` is written by `pr-dispose.sh` and read by
`pr-facts.sh`'s close arm, which serves the old path. How a ruling retires a PR
on the new merge path is tk-1tfzr71.89's, which this rig's move waits on.

**Why a receipt of the city's own act is not a mirror.** A mirror copies a
state GitHub holds, which goes stale the moment GitHub moves, and needs a
writer to keep it current. `pr_provenance_since` records when the city first
read the PR, a fact of the city's that GitHub does not hold and that never
changes, so nothing keeps it current and nothing can disagree with it. The
city's marks are acts of the city's kept on GitHub itself, read back in the one
saved read.

**The definition of feedback stays one copy.** The take, the evaluator, the
withdrawal and the update's conversation read each read which posts are
feedback, which are the city's own, and which are taken or handled through the
feedback adapter over `pr-post.sh feedback-def`. The counting rules that were
`pr-facts.sh`'s, such as which review states count, live in Go, as
`countedReviewStates` does today.

## 10. What each held note and bead becomes

tk-1tfzr71.21's notes say what the replacement owes, and the beads it blocks
wait on it. Each gets a row. "The retirement unit" is unit 7 of
[section 11](#11-the-units).

**The notes.**

| Note (date) | Becomes |
|---|---|
| PR-finishing rank (10-23) | carried, unit 2: the rank reads the saved read's approvers, and `pr_finishing_settled` goes ([section 7](#7-a-city-on-the-new-merge-path)) |
| Rule 1 list (10-26): tk-ickub0o, a thread files a visit while the PR waits for review | made moot: no thread files a visit or a gate on the new merge path, and a person's open thread holds the PR through GitHub's merge state where the base requires resolved threads |
| tk-mg42wc8, a second copy of "routed" | made moot: "taken" is one rule in the definition, read through one Go function by the take, the evaluator and the withdrawal |
| tk-icggxv, inline comments a visit carries are not linked to it | made moot: each comment is its own ask, which names it |
| tk-l7dka5, the arms guard demands but not other blockers | carried: the order pours a run only while nothing else writes the branch and no human gate holds the bead, a conversation holding only the merge; a run takes an ask only when nothing holds the ask (`gctk bead holds`); and a conflict or red-check ask is not filed while a hold set by hand or a human gate holds the bead |
| tk-nfdq56, routing coupled to conflict state | made moot: posts are taken whatever the merge state, and a conflict is its own ask |
| held: review reads the posture (10-28) | carried, unit 2: the evaluator's condition for each untaken post |
| What a dismissal retires (10-28) | carried, unit 1: `live_comments` moves into `pr-post.sh` |
| The 👍 mark (10-28) | carried, unit 4: the round's post puts it, and `pr-post.test.sh` reads its name from the Go writer |
| `gctk pr owner` (gctk domain move) | dropped on purpose: `gctk pr refresh` finds the bead that owns a PR itself ([the landing-order design's section 4](../tk-1tfzr71.149/design.md#4-the-one-pr-updates-read)), so the verb would have no caller; the retirement unit removes its row from `docs/gctk-architecture.md` |
| Built-once rule 1 (blocked census) | carried: the acts read holds through the waits package and compute none |
| `gate_for` names a key's gate (10-30) | carried, unit 5: the red-check gates are named under their key by `human-gate.sh`'s order |
| tk-306xmm6, tk-5g3y4ds, tk-ec0b012, tk-8njghcm, tk-qnn0yhx (10-30) | see the beads below; tk-8njghcm closed after PR #1492 |
| `review-dismissal.sh`'s `pr_coords` for the sign-off (10-30) | made moot: `converse-signoff.sh` no longer sources the file (read 2026-11-16), and the file moves to tk-1tfzr71.122 |
| tk-a8nb8wo, the city's own posts after a misread (11-03) | carried: nothing is taken while the login does not resolve, and every post the run makes carries the city's mark |
| Test cost (11-05) | carried: the retirement unit deletes `pr-facts.test.sh` |
| Approval comments (11-05) | carried, unit 2: an approval's message is a post |
| A follow-up read as fixed (11-06) | carried, unit 4: the answer is the ruling's reason, and a scheduled point is resolved |
| tk-tx227cp's re-run rules (11-06, two notes) | carried, unit 5, with the head's run attempts in place of `pr_check_rerun`; the monitor's `CANCELED` spelling is moot, since no monitor runs, and it is listed for upstream ([section 4](#4-red-checks-and-conflicts)) |
| A parked rework child keeps the branch (11-06) | carried, unit 5: no conflict ask while another open bead names the branch |
| The suite's per-run limit (11-06) | carried: new tests are Go tests, outside `tools/run-tests.sh`'s 900-second limit, and every shell suite a unit changes stays within it in a loaded `-j9` wave |
| bead-rehome exit 5 (11-07) | made moot: a PR closed unmerged is the landing order's exception, and a recorded disposition there is tk-1tfzr71.89's |
| Dispatch by sling (11-08) and `route_finishing` (11-08) | made moot: an ask is unrouted and the order pours the run, so no child or route is written |
| Parks file their gate first (11-09) | carried: a PR closed unmerged or a moved base is the landing order's exception, whose gate the next run files when one did not (`blocked` in `services/gctk/pr/landing.go`), and a red-check park is only its gate (unit 5) |
| An open conversation defers a conflict rework (11-09) | superseded: a conversation on a PR holds only its merge (tk-1tfzr71.164, #1541, the operator's ruling in conversation tk-dt0815o), so a conflict ask is filed while one is open, and a hold set by hand or a human gate still defers it (unit 5) |
| A declined lane finding answered (11-10) | made moot by tk-1tfzr71.22: the head's comment answers it beside its lane's verdict |
| A required check that never reports (11-11, and two notes of 11-12) | carried, unit 5; the second 11-12 note's monitor, which reads the case as any BLOCKED PR, is moot, since no monitor runs |
| The merge design's take-over (11-12) | carried: units 2 to 5; the monitor's join dropped on purpose (decision 1); the driver's row moved ([section 8](#8-the-cadence-and-the-order-of-the-retirements)) |
| `countedReviewStates` (11-12) | carried, unit 2 |
| What the record path owes (11-12) | carried, units 2 and 5; the city's superseded request dropped on purpose, with no live case; the label reconcile is tk-1tfzr71.149's |
| The BLOCKED-thread gate while work is live (11-12, 11-13) | made moot: PR #1492 retired the gate |
| A rework changing declined code (11-13) | made moot by the skill's "A decline stands" |
| Only a person's answer quiets a thread block (11-13) | made moot: the gate retired, as the note of 11-13 says |
| The operator's workflow (11-13) | carried: [From your seat](#from-your-seat) and [section 3](#3-a-persons-post), unit 2 for working, unit 4 for a question's gate |
| PR #1492's rework rules (11-13, three notes) | carried: [section 6](#6-the-write-back) |
| `rejection-repool.sh` comments (11-13) and `deferred-dispatch.sh` comment (11-13) | made moot: the retirement unit deletes the file |
| The arm's keys (11-13) | made moot: the intake reads no arm key |
| The one-day quiet window (11-13) | made moot: no gate is filed for feedback, since every post becomes an ask |
| The review-lanes design's three things (11-14) | carried: the ask is the form, and units 2 and 4 move the run's ruling onto it |
| The withdrawal reads the new marks (11-15) | carried, unit 2: `unrouted`, over each approval's own message as well as its inline comments |
| tk-os61zl6 (11-15) | carried, unit 2 |
| The board's ruling (11-15) | carried: the saved read is the one copy |
| The supersession check asked on a rewrite (11-15) | carried, unit 5: the skill's conflict rule |
| What `pr-facts.sh` files on the record (11-15) | carried, units 2 to 5 |
| Old-path PRs read by `prstatus.Derive` (11-15) | carried: the retirement unit deletes the old-path clause, and its edges onto each cutover bead say no PR is on the old path then |
| The comment path's cost (11-15) | carried: unit 6 builds tk-ileeqzz's cheap answer |
| The label's writer (11-15) | carried: the retirement unit waits on tk-1tfzr71.149 |
| Two leads on Gas City (11-15) | both verified at upstream main 994008c628, [gas-city-search.md](gas-city-search.md) |
| The moved `close-answered` call (11-15) | carried, unit 4: the call goes in the same change that gives a person's post its new form |
| A deferral's follow-up takes the PR's target (11-16) | carried, unit 4 |

**The beads it blocks.** The retirement is a unit of this effort, so a bead
that waits for the code this effort deletes keeps its edge onto tk-1tfzr71.21,
its close brief and its arm for the validating closer, and the closer checks it
once the effort lands.

| Bead | Becomes |
|---|---|
| tk-1tfzr71.122, the old review path's retirement | keeps its edge; the retirement unit moves the driver's, the order's, `pace-lib.sh`'s and `review-dismissal.sh`'s rows to it |
| tk-1tfzr71.23, convoys | stays: it waits by lane A's order, and convoy graduation is already gone |
| tk-1tfzr71.25, the registry sweep | keeps its edge, since the retirement unit registers the keys of [section 9](#9-one-writer) retired, and gains one onto the conversion's removal, which registers the old receipt keys retired |
| tk-1tfzr71.50, `bd-lib.sh`'s checked create | keeps its edge: the retirement unit deletes the last caller in this effort's files |
| tk-1tfzr71.71, the evaluator's `anchor_bead` reading | keeps its edge and gains one onto tk-1tfzr71.122: a rework child a rig's move left open holds its PR only through that reading, and the old review path's writers file children without the edge until then |
| tk-306xmm6, answered outdated threads read as unanswered | keeps its edge: settled when the effort lands ([section 3](#3-a-persons-post)) |
| tk-5g3y4ds, a label that is only a severity word | keeps its edge: the head's comment shows a post's ask by its reason, the line that names the post |
| tk-6bovoni, guards over a rewritten main | keeps its edge: the retirement unit deletes `branch-supersession.sh`; the guard's half is on tk-1tfzr71.122 |
| tk-8gradm4.1, a per-pass snapshot | moves onto tk-1tfzr71.122, which deletes the driver; the cheap question and the one-PR update are the snapshot it asked for |
| tk-ec0b012, two same-text comments share a finding | keeps its edge: each comment is its own ask |
| tk-o9i6kp0, approving with comments | stays: an approval's message is read once the effort lands |
| tk-os61zl6, one approval reader | keeps its edge, and its edges onto tk-1tfzr71.70 and tk-1tfzr71.122 |
| tk-qnn0yhx, a red-check visit never retracted | keeps its edge: the gate is withdrawn once the checks pass |
| tk-t9fl9ss, the suite past its limit | keeps its edge: the retirement unit deletes `pr-facts.test.sh` |
| tk-icggxv, tk-ickub0o, tk-l7dka5, tk-mg42wc8, tk-nfdq56 (closed, superseded by this member) | rows in the notes table above |

## 11. The units

The effort's units land on `integration/tk-1tfzr71.21`, keep the suite green
and leave the city working. Nothing they build runs until the effort lands on
main, with the retirement unit among them. Each unit's change carries the docs
its own behavior changes, and the retirement unit states the intake whole.

| # | Unit | What it builds | Waits on |
|---|---|---|---|
| 1 | feat(pr): define the city's taken mark beside its handled mark, and keep what a dismissal retires in the definition of feedback | `gc_city_taken` in `pr-post.sh`'s definition, and `live_comments` moved there from `review-dismissal.sh`, so `feedback-def` no longer sources that file; `review-dismissal.sh` keeps `pr_coords`, `approval_phrase` and `unrouted_comment_ids`; `review-dismissal.test.sh` and `pr-post.test.sh` follow; the "Unanswered review threads" warrant re-verified | nothing |
| 2 | feat(gctk): take each person's post on a PR as its own ask, with the city's marks as receipts | in gctk's pr domain: the one-PR update's conversation read asks for the marks, saves `untaken` with each post's naming fields, and stamps `pr_provenance_since`; the landing order's take files one ask per untaken post, marks it 👀, and runs the one-PR update once its marks land, and a run in which a take failed exits non-zero; the evaluator's condition per untaken post, which the merge's own read applies too; `unrouted` over the marks, with each approval's own message among the posts it waits on; an approval's message counted; `prstatus.Render` reads a PR with an untaken post or an open post ask as working; `prio_pr_approved` reads the saved read's approvers. Tests: a late review below the newest id is taken; a post whose mark failed is marked again with no second ask; an edited post is not filed twice; an approval's message becomes an ask; no merge over an untaken post, one the saved read lacks included; the withdrawal waits on an untaken inline comment; a withdrawal for a material newer head that acts before the take has filed the message of an approval with no inline comment waits, and dismisses the approval in a later run once the message is taken; the rank; working ahead of merging. The "Saved GitHub read" warrant re-verified | unit 1, and tk-1tfzr71.149 landing on main with the effort's branch brought current |
| 3 | feat(gctk): convert the old path's receipts on a bead that moved onto the new merge path | a landing-order act, decided from the bead, for a bead that carries `pr-facts.sh`'s watermarks, answered marks or batch ledgers, taken before any take on that bead: its own read of the posts and threads, the city's 👀 on every feedback post at or below the old marks that carries neither mark, each unresolved thread that holds only the city's own posts resolved, each open human finding's post filed as its ask and the finding closed as superseded by it, the old keys unset, and the one-PR update run. Tests: each old key converted; a post at or below a watermark marked and nothing filed; a post above it taken by the take after the conversion; a post `pr-facts.sh` marked left as it is; a human finding superseded by its post's ask; a thread of the city's own resolved and a person's left alone; no take on a bead that still carries old keys; a bead with no old keys untouched | unit 2 |
| 4 | feat(review): answer each person's post where it was made, in the round that rules it | `review-run.sh post`, in the ruling step, replies in a thread and resolves it, replies with a linking comment to a post that has no thread where words are owed, puts 👍, leaves a question's thread open with its gate named, dismisses a person's request for changes once every point it raised has its answer on the PR, with its one-line note, and asks its author for a review again, each reply found again by a marker naming its ask; `approval()` reads a dismissed review as its account's latest opinion; part 6 of the step's text in `mol-pr-review.toml` names the answers; the loop's check makes no GitHub call, and its call to `finding.sh close-answered` goes; `review-run.sh finding` and the prepare read's human findings go; the review-ruling skill's batch paragraph replaced, a post read at its URL; a comment that settles a question or makes it moot resolves its gate, naming the comment, with a reply that says so, and one that does not gets a reply that the question stands and waits on the board; the landing order pours a run for a post whose ask was filed after the bead's newest question gate, behind no other gate; `review-run.test.sh`'s defer case on a target other than `main`; `pr-post.test.sh` reads the reaction names from the Go writer; the architecture page's Debt entry on a comment made while a question is open out. Tests: each ruling's answer by post kind; a post run again posts nothing twice; an answer that does not land exits 1 and leaves its ask open; a request for changes dismissed once its last point is answered and not before, with the review asked again; an approval given before a dismissed request for changes does not stand; a run poured behind a question gate for a newer post, and none behind any other gate; a gate resolved by a comment that settles it, and kept with its reply for one that does not | unit 2 |
| 5 | feat(gctk): route a PR's red checks and conflicts from the saved read | the one-PR update's checks read gains each suite's status, creation time, and Actions run with its attempt; the landing order's acts of [section 4](#4-red-checks-and-conflicts), with their gates and their withdrawal; the skill's conflict rule. Tests: a code failure's ask and both bounds; a non-code failure re-run once per head after its runs finished, and not re-run again when a second run at that head, at attempt 1, fails; a re-run GitHub refuses and a failure outside any Actions run each gated; each non-code gate only when approved; a gate withdrawn when the checks pass; the stuck suite toggled once and then gated; a conflict ask only on an approved PR that nothing holds, and filed while a conversation is open | unit 2, and tk-1tfzr71.149 landing on main |
| 6 | feat(review): let triage answer a person's post that needs only an answer | triage's output carries a ruling for each ask it answers; the pass rule, the result writer and the head's comment read it beside the ruling step's; triage posts those answers through `review-run.sh post`; the ruling step's read leaves out the asks triage ruled, and the step closes at once when nothing is left; the review-triage skill's bar. Tests: a question answered by triage with a reply and its ask closed, the ruling step closing at once; an approval's "looks good" answered with 👍; a post that asks for a change left to the ruling step; a round with one of each | unit 4 |
| 7 | refactor: retire pr-facts.sh and the GitHub intake's old path | its drain check: no open bead on the old path in any store. Then it deletes `pr-facts.sh`, `review-answer.sh`, `record-failure-cap.sh`, `branch-supersession.sh`, the doctor check and their tests, and `lifecycle.sh` once no caller is left; removes arms 1, 4 and 7; deletes the readers of the keys of [section 9](#9-one-writer) and `prio_pr_approved`'s posture clause, and registers those keys retired; moves `prstatus` under the pr domain onto the ledger; moves the rows of [section 8](#8-the-cadence-and-the-order-of-the-retirements) to tk-1tfzr71.122 in `tools/deletion-plan.tsv`; states the intake in `docs/state-machine.md`, `docs/refinery-merge-cadence.md`, `docs/not-for-review.md`, `docs/gctk-architecture.md` (the `gctk pr owner` row out) and `services/gctk/README.md`, names the replacement for `pr-facts.sh` in `docs/built-once-target.md`, and takes the intake's Debt entry on the merge cadence out of `docs/architecture.md`; rewrites every live line that names `pr-facts.sh` ([section 13](#13-the-files-that-name-pr-factssh)) | units 2 to 6, tk-1tfzr71.149, tk-1tfzr71.70, and each cutover bead (tk-1tfzr71.78, .80 to .84) |
| — | refactor: remove the conversion of the old receipts (outside the effort, target `main`) | its drain check: no open bead in any store carries `pr-facts.sh`'s receipt keys or an open human finding. Then it deletes unit 3's conversion and its tests, and registers the old receipt keys retired | tk-1tfzr71.21 |

Each unit's suites fit the runner's per-run limit in a loaded `-j9` wave: the new
logic's tests are Go tests in gctk's packages, which `tools/run-tests.sh` does not
time, and the shell suites the units touch (`pr-post.test.sh`,
`review-dismissal.test.sh`, `review-run.test.sh`, `priority-lib.test.sh`) are
each changed by a few cases. `pr-facts.test.sh`'s parts, which the review of
2026-11-06 saw time out in such a wave (tk-t9fl9ss), go with the retirement
unit.

Units 2 and 5 change code in `services/gctk/pr` that tk-1tfzr71.149's units
rewrite, so they are built on main once that effort has landed, as that design
builds its own first unit after the review-lanes effort.

The conversion's removal is the one piece outside the effort. The conversion
must run in the city after the effort lands, on each bead the rigs' moves left
carrying the old receipts, so the effort cannot delete it. The removal waits on
the effort, and its drain check says when the last such bead is converted,
within the landing order's first runs.

## 12. Edges and notes the implementation child adds

- Units 1 to 7 are filed under the epic (tk-1tfzr71) with
  `target=integration/tk-1tfzr71.21` in each create. tk-1tfzr71.21 and the
  summary task (tk-1tfzr71.163) wait on each through a `blocks` edge. Each unit
  waits on what its row names and is armed to dispatch when they close.
- The conversion's removal is filed under the epic with `target=main`, outside
  the effort, blocked by tk-1tfzr71.21, and armed on mol-polecat-work. Neither
  tk-1tfzr71.21 nor the summary task waits on it. tk-1tfzr71.25 gains a
  `blocks` edge onto it.
- tk-1tfzr71.122 gets a note: it keeps its edge onto tk-1tfzr71.21
  ([section 8](#8-the-cadence-and-the-order-of-the-retirements)), unit 7 moves
  the driver's, the order's, `pace-lib.sh`'s and `review-dismissal.sh`'s rows to
  it, and its deletion of `review-dismissal.sh` changes the test files that copy
  that file by name: `converse-signoff.test.sh`, `gc-helm-accept.test.sh`,
  `conversation-merge-hold.test.sh`, `pr-sitting-comment-wiring.test.sh`,
  `work-submit.test.sh` and `test-harness.sh`.
- tk-8gradm4.1's edge moves from tk-1tfzr71.21 onto tk-1tfzr71.122, and
  tk-1tfzr71.71 gains an edge onto tk-1tfzr71.122, each with a close brief that
  names what tk-1tfzr71.122 removes, and each keeping its validating closer's
  arm, armed only once its new edge's add exits 0.
- tk-1tfzr71.70 gets a note: unit 7 waits on it, deletes
  `record-failure-cap.sh` and `branch-supersession.sh`, whose other callers it
  deletes, and takes `lifecycle.sh`'s row once it has added it. Whatever it
  leaves of `pr-open.sh` sources no `pace-lib.sh`, whose row moves to
  tk-1tfzr71.122.
- Each cutover bead (tk-1tfzr71.78, .80 to .84) gets a note: unit 7 waits on
  it, and the conversion turns each moved bead's old receipts into the city's
  marks in the landing order's first runs after the effort lands.
- tk-go9npun gets a note: the rank's approval is the saved read's approvers
  once unit 2 lands.
- tk-ileeqzz closes folded into unit 6 through the disposition writer
  (`bead-rehome.sh --kind folded`), whose `supersedes` edge names unit 6 as the
  bead that carries its work. Nothing waits on it (read 2026-11-16).
- Before filing, the child surveys the open branches against each unit's files
  again. At this reading PR #1533 has merged into `integration/tk-1tfzr71.149`
  (bc181140b), whose implementation child (tk-1tfzr71.151) builds the reads and
  acts units 2, 3 and 5 build on, and the effort's own branch carries nothing
  main lacks.

## 13. The files that name pr-facts.sh

`git grep -l pr-facts origin/main -- ':!specs'` listed 103 files on 2026-11-16,
at 713e3a733.

| Files | What becomes of the mention |
|---|---|
| The retirement unit's files that name it: `pr-facts.sh` and its test, `review-answer.sh` and its test, `record-failure-cap.sh`, `branch-supersession.sh`, `refinery-reconcile.sh` and its test, `review-dismissal.sh` and its test, `doctor/check-feedback-routing-owed/run.sh`, `orders/refinery-reconcile.toml` | deleted by the retirement unit, or by tk-1tfzr71.122 for the four that move there, whose comments the retirement unit rewrites where the driver keeps running |
| Seventeen files under tk-1tfzr71.122's rows, such as `finding.sh`, `gate-ensure.sh`, `signoff.sh` and `approval-withdraw.sh`; two under tk-1tfzr71.70's (`pre-open-rebase.sh` and its test); one under tk-1tfzr71.19's and one under tk-1tfzr71.25's | deleted with those beads' files |
| Old merge path code no row lists yet: `merge.sh`, `merge.test.sh`, `services/gctk/internal/cli/merge.go`, `services/gctk/internal/cli/lifecycle.go` and `services/gctk/internal/lifecycle/machine.go` | tk-1tfzr71.70 deletes them before the retirement unit |
| `review-verdict.test.sh` | deleted with `review-verdict.sh` by whichever of tk-1tfzr71.70 and tk-1tfzr71.122 lands second, as tk-1tfzr71.70's note of 2026-11-15 says |
| `lifecycle.sh` and `lifecycle.test.sh` | the retirement unit deletes them, once tk-1tfzr71.70 has reduced the script to a plain write and added its row |
| Code this member changes: `pr-post.sh`, `pr-post.test.sh` (unit 1, unit 4), `services/gctk/pr/feedback.go`, `services/gctk/pr/ready_keys.go` (unit 2), `review-run.sh` (units 4 and 6), `priority-lib.sh`, its test and fixture (unit 2, then the retirement unit), `services/gctk/prstatus/prstatus.go`, `services/gctk/prstatus/gates.go` (the retirement unit) | changed by the unit named |
| The helm board's posture and conversation readers: `services/helm/internal/board/derive.go`, `derive_test.go`, `model.go`, the rig board's two fixtures, `services/helm/README.md` | the retirement unit deletes their old-path clauses, where tk-1tfzr71.24 has not |
| Live scripts whose comments or messages name it: `bd-lib.sh`, `bead-rehome.sh`, `converse-rework.sh` and its test, `converse-signoff.sh` and its test, `demo-deliver.sh`, `feedback-miner.sh`, `gc-helm.sh`, `gc-helm-open.test.sh`, `gh-origin-guard.sh` and its test, `patrol-finding.sh`, `pr-dispose.sh` and its test, `pr-open.sh`, `pr-status-label.sh`, `queue-priority.sh` and its test, `test-harness.sh` and its test, `build-scratch-reap.test.sh`, `preexisting-failure.test.sh`, `doctor/check-state-space/run.sh`, `tools/run-tests.sh` | the retirement unit rewrites each to name what does the job then, or drops the clause; `pr-dispose.sh`'s consumer is the old path's close arm, and its use on the new merge path is tk-1tfzr71.89's |
| Prompts, formulas and their renders: `template-fragments/polecat-doctrine.template.md`, `formulas/mol-polecat-work.toml`, `formulas/mol-feedback-miner.toml`, the three `generated/seed-audit` renders | the retirement unit rewrites the sources, and the render follows |
| Docs: `architecture.md`, `authority-map.md`, `built-once-target.md`, `component-model.md`, `finalize-gate.md`, `gh-origin-guard.md`, `human-engagement.md`, `refinery-merge-cadence.md`, `state-machine.md`, `steering.md`, `warrants.md`; and gctk's own account of the shell it does not hold yet, `services/gctk/README.md` and the comment in `services/gctk/cmd/gctk/main.go` | the retirement unit states the intake and removes the old path's account |
| `lifecycle/lifecycle.toml` | the retirement unit registers the keys retired, and the conversion's removal the old receipt keys |
| `tools/deletion-plan.tsv` | the retirement unit moves rows to tk-1tfzr71.122 and removes its own |

## 14. Facts this design rests on

- **The landing-order design** is `specs/tk-1tfzr71.149/design.md` at
  bc181140b, PR #1533's merge into `integration/tk-1tfzr71.149` on 2026-11-16 at
  20:34:19Z, whose design files are the same blobs as its head e206cf6e2. Its
  section 3 makes the one-PR update the only writer of the saved read, in four
  parts, its section 5 has the landing order act from the beads, read GitHub
  only for the merge, start no act past 45 seconds and stop each at 30, its
  section 6 sets the cadence and the latency of about 4 minutes, its section 8
  gives the webhook's route through the github pack's service, and its section
  12 makes routing a person's posts a landing-order act taken from the bead.
- **The saved read today** (`pr_github_read`, `services/gctk/pr/read.go`)
  keeps the newest feedback id in each id space and the threads waiting on the
  city's answer, and the evaluator compares the newest ids with the watermarks
  (`unhandled`, `services/gctk/pr/feedback.go`).
- **gctk's reads** (`services/gctk/internal/gh/gh.go`): inline comments carry
  `reactionGroups { content viewerHasReacted }`, and reviews and conversation
  comments do not.
- **A reaction and the times GitHub keeps**, read 2026-11-16 at about 20:4xZ
  on this repository's 40 most recently updated PRs: the city's reactions on
  inline comments, five 👍 and two 👀, were each later than their comment's
  `updatedAt`, so a reaction does not move its post's time. Each was earlier
  than its PR's `updatedAt`, which later events had moved, so the reads do not
  say whether a reaction moves the PR's.
- **The withdrawal's place in a run** (`services/gctk/pr/landing.go`): an open
  PR's run calls `carry`, which carries out each open withdrawal by dismissing
  the approvals that stand on a commit without its head, before any
  `observeAlone`, its whole read. `unrouted` reads only the inline comments
  those approvals carry, and `countedReviewStates` holds `COMMENTED` and
  `CHANGES_REQUESTED` (`services/gctk/pr/feedback.go`).
- **The approval rule** (`approval()` in `services/gctk/pr/rules.go`, at main
  73845e65f) takes each account's latest review that approves or requests
  changes, skipping any other state, a dismissed review included.
- **Today's dismissal** (`pr-facts.sh` at main 8b9c4caf3, the comment that
  opens "A human CHANGES_REQUESTED holds the merge"): once every finding one
  review raised has closed, the review is dismissed and its author asked again,
  with a one-line note, per review, and "Dismissal is not approval: the merge
  still gates on an explicit one." In this repository's last 100 PRs, read
  2026-11-16, nine requests for changes were dismissed by the city's account,
  and each was its reviewer's first review on the PR, followed by an approval.
- **The render** (`prstatus.Render`, `services/gctk/prstatus/render.go`):
  needs-attention, then merging, then working, then needs-review. Merging
  covers an approved PR with only the city's work left, and needs-review a PR
  where only an approval is left. An open human gate reads needs-attention,
  and its label is `held: gate` (`services/gctk/prstatus/prstatus.go`).
- **The review run** (`formulas/mol-pr-review.toml` at main 73845e65f):
  triage, a lane for each check triage picks, which triage's output bonds, and
  the ruling step; at most three iterations (`max_attempts`). The landing order
  pours one run per PR at a time, while no run is attached, no other open bead
  names the branch and no human gate holds the bead; a conversation holds only
  the merge (`services/gctk/pr/admit.go` at 73845e65f, after #1541).
- **A step's bond.** Gas City bonds one formula from a step's output: a step
  carries one `OnCompleteSpec`, with one `for_each` and one `bond`
  (`internal/formula` at 994008c628).
- **The costs** (tk-ileeqzz, from the measurement of 2026-11-15 in conversation
  tk-9p5oh6j's notes): a run for a comment that needs only an answer, about
  7.7M tokens processed and about 12 minutes of session time, of which the
  ruling session is about 6.4M and triage about 0.8M; the cheapest fix-pool
  sessions about 0.6M and 1.5 minutes, and a triage session 2.1 minutes.
- **The definition of feedback** (`pr-post.sh` at main 73845e65f):
  `gc_feedback` is "not the city's own, and not marked as not for review";
  `gc_city_own` is a post under the city's login that carries the city's mark
  or was made before the provenance instant; `gc_not_for_review` reads the mark
  `<!-- gc:no-review -->` at the body's opening or a prefix the rig declares;
  `gc_thread_awaits_answer` reads an unresolved thread whose newest live post
  with no 👍 is feedback.
- **The ask** (`services/gctk/review/ask.go`): a task that blocks the PR's bead,
  names its branch, has no route, assignee or role, and is found again by the
  same reason and source, open or closed. The head's comment shows an ask by
  its whole reason on one line (`oneLine` in `services/gctk/review/passed.go`,
  called from `services/gctk/review/comment.go`). The record closes an ask
  ruled declined, deferred or answered, and a must-fix one once a judged head
  carries its fix, and a question stays open (`answeredAsks`,
  `services/gctk/review/result.go`).
- **The loop's check** (`review-passed-check.sh`, with a two-minute timeout in
  `formulas/mol-pr-review.toml`) runs in Gas City's gate sandbox: HOME is the
  city's directory, and the environment is a whitelist that carries no GitHub
  token (`ConditionEnv.Environ` in `internal/convergence/condition.go`). Under
  that HOME, `gh api user` answered "To get started with GitHub CLI, please
  run: gh auth login" on 2026-11-16, so the check reaches only the store, as
  `gctk review passed`'s help says.
- **Gas City's PR monitor** at upstream main 994008c628, whose files cited here
  are unchanged since 76a06b2327: the query, `checkFailed`, `checkPending` and
  `classifyPullRequest` of [section 4](#4-red-checks-and-conflicts), and
  `ensureGitHubPRRepairBead`, which files a task at priority 1 with the labels
  `github`, `ci`, `repair` and `pr-monitor`, routed to `repair_route`, deduped
  on owner, repository, number and head, and carrying the `github.*` keys.
  `gc github pr backfill` is the only caller of `ListOpenPullRequests`.
- **The rigs' moves** (the notes of tk-1tfzr71.78 of 2026-11-16, 20:34Z and
  20:37Z): the shadow comparison is dropped; this rig's move waits on
  tk-1tfzr71.89 and tk-1tfzr71.165, tk-1tfzr71.164 having landed; and the
  other five rigs' moves (tk-1tfzr71.80 to .84) each wait on this rig's alone
  among the cutovers. tk-1tfzr71.70 waits on each cutover bead, and
  tk-1tfzr71.149 on its own children, so neither waits on this effort.
- **The stores,** read 2026-11-16 at 05:31Z with `gc bd --db <store> list
  --status open,in_progress,blocked` over the seven stores `gc rig list` names:
  24 open beads with `merge_result=pull_request`, none on the new merge path,
  no open human finding, and none carrying `pr_unengaged_threads`.
- **The repositories,** read the same minute with one GraphQL request per rig
  repository: 27 open PRs in six repositories, none of whose latest review from
  the city's account requests changes.
- **The cadence** (`assets/scripts/refinery-reconcile.sh`): a sixty-second
  cooldown, with the arms of [section 8](#8-the-cadence-and-the-order-of-the-retirements).
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
  `review-dismissal.sh` with their tests), so the retirement unit deletes 16,399.
- **The city's API,** `tailscale serve status` and `tailscale funnel status`,
  read 2026-11-16 at 05:36Z: served on the tailnet only, by a proxy to
  loopback, with nothing funnelled.
- **The city's config** declares no `[[github.pr_monitor]]` and no `[[webhook]]`.
