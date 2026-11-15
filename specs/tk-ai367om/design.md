---
name: Design — a stay comes back when its work is ready for the operator's approval
description: The design for tk-ai367om, the design child of initiative tk-vrg93t0, read at main 5d4c3b4cf and integration/tk-1tfzr71.22 at 04d8dad0d against Gas City upstream main 8e7d91b583 and beads v1.3.4. It settles what each stay waits on, how the city holds a PR, as a draft or by its merge, until a staying sitting's reading of its latest ruling is on it and wakes the sitting through a Gas City session wait, the entry's ready answer and the return it starts, every later round and a sitting the operator talks with again, the stay on the conversation's own subject, what a stay does on a rig still on the old review path, the pages, the surface it adds and the units. Read it to approve the design at its gate, or to build one of its units.
---

# Design: a stay comes back when its work is ready for your approval

This is the design record for tk-ai367om, the design child of the initiative
tk-vrg93t0. It settles the eight points of the initiative's "What the design
settles", framed by the initiative's rule (its Goal: a stay comes back at the
operator's next decision about the work, never after it), its table under "What
is built today, against the rule", and its section "What is already settled".

The pack was read at main 5d4c3b4cf and at `integration/tk-1tfzr71.22`
04d8dad0d, where the review run, its draft cycle and its asks have landed
(tk-1tfzr71.123, .124, .126 and .128) on their way to main. Gas City is cited
by symbol or page at `gastownhall/gascity` main 8e7d91b583, and bd at beads
v1.3.4. The search behind each piece of surface the units add is
[gas-city-search.md](gas-city-search.md). The review-lanes design this builds on
is `specs/tk-1tfzr71.108/design.md` on `integration/tk-1tfzr71.22`.

## What the operator approves

Today a sitting you ask to stay comes back when its work's bead closes. For new
work that opens its own PR, that is after the PR has merged, too late to change
anything. For a rework of the PR you discussed, it is when the rework reaches the
branch, before the checks run again. A stay on the conversation's own subject is
refused.

Approving this design changes that on every rig that has moved onto the review
run:

- **Every PR stay comes back when you would be asked to approve.** When the
  review run has passed at the head the refinery validated, the city keeps the
  PR a draft and wakes the sitting. It reads the PR against what you agreed and
  posts its reading on the PR. Only then does the PR leave draft, so GitHub and
  the board ask for your approval with the reading already there. This holds for
  new work, for a rework of the PR you discussed, and for the conversation's own
  subject.
- **Every round.** When you send the result back through the sitting, or the city
  repairs it after a failing check or merges the target in, the sitting reads
  again at the next readiness. It reads only what changed since the head it last
  read, and posts one reading per ruling and head. A send-back owes its reading
  even when the review run answers it without changing the PR. On a PR that is
  ready already, the city then holds its merge until the reading is on it, so an
  approval you gave earlier cannot merge it first.
- **Talking with the sitting again.** Once you speak to a sitting that stays for
  a PR, it holds the conversation, and the PR does not merge until you rule.
  Staying again starts the next round, and ending the stay lets the PR go on.
- **Once the city has asked GitHub to merge the PR**, nothing the city holds
  stops that merge. It asks only once every stay's reading is on the PR and no
  sitting holds for your answer. On a base with no merge queue the PR merges at
  once. On a base that requires a merge queue, a PR already in the queue merges
  once the queue's checks pass, even while you talk with the sitting. No rig in
  the city has one on its default branch.
- **Work that opens no PR** comes back when it closes, as today.
- **The stay ends** when the PR merges, when the work closes without one, or when
  you end it.
- **Until a rig moves onto the review run**, nothing tells a sitting that its PR
  is ready. Stays there come back as they do today, and the sitting tells you
  when, recommending that it end at the hand-off where that is after the merge.

These calls carry a cost either way:

1. **When the PR leaves draft while the sitting reads.**
   - (a) It stays a draft until the reading is on it. GitHub requests no review
     and CI starts only then, so you are asked later by the time the sitting
     takes to read, rounded up to the landing order's next five-minute pass.
     The merge also waits for the reading, through a condition of the city's
     that the label and both boards render, because a round can end on a PR
     that is ready already, which has no draft to keep.
   - (b) It is marked ready at once, and the merge and the needs-review label
     wait for the reading through that condition alone. CI runs while the
     sitting reads, but GitHub shows the PR ready for review before the reading
     is on it.
2. **When the reading finds that the work departs from what you agreed.**
   - (a) The sitting asks you, and the PR does not merge until you answer: a
     draft stays a draft, and a PR that is ready already waits on the city's
     condition. No approval you gave in an earlier round can merge the PR past
     the departure, but you answer the sitting before the PR can be approved
     and merged.
   - (b) The PR leaves draft, or its merge goes on, with the reading on it, and
     your approval decides. You can approve without answering the sitting, but
     an approval you gave in an earlier round can merge the PR before you have
     read the departure.

Approving as it stands ships the first option of each.

## 1. What each stay waits on

**The moment.** A PR is ready for the operator's approval at the moment the
landing order would mark it ready: the record is pending at the PR's head, which
is the head the refinery validated, a passed result of the review run names that
head and the PR's target, no review run is attached to the bead, and no ask a run
can take is open on it (`readyBar` in `services/gctk/pr/draft.go`, which `decide`
in `services/gctk/pr/landing.go` consults before it marks a draft ready). That is
the end of a round in the review-lanes design's section 5, and the moment its
section 9 places this wake at. A stay on work that opens a PR comes back there,
in every round. A stay on work that opens no PR, or that closes without one,
comes back when it closes.

**What a stay watches.** A PR stay watches the bead that owns the work's PR,
which this design calls the PR's bead. Its sitting still sleeps under its
conversation's own wait in the store, the `blocks` edge PR #1480 built, which
keeps the conversation out of bd's ready work and brings the sitting back when
the work closes. Section 3 adds the wake at readiness beside it.

| The ruling sends | The PR's bead the stay watches | The conversation's wait in the store | It comes back |
|---|---|---|---|
| New work that opens its own PR | the work's bead | a `blocks` edge onto that bead, as today | at each readiness of the PR, and when the bead closes |
| A rework of the PR under discussion | that PR's anchor, the conversation's subject | a `blocks` edge onto an open input convoy that tracks the anchor, or, before the PR's first review run, onto the ruling's ask until a run closes it | at the readiness that ends the rework's round, at each later one, and when the anchor closes |
| The conversation's own subject | the subject | a `blocks` edge onto the open input convoy of the subject's dispatch (section 5) | at each readiness of the subject's PR, and when the subject closes |
| Work that opens no PR, or closes without one | none | a `blocks` edge onto the work, as today | when it closes |

**The rework row.** On the review path a ruling's rework is an ask on the PR's
bead, which `converse-rework.sh` files through `gctk review ask` (tk-1tfzr71.128,
"send a PR on the record back to its review run as an ask carrying the ruling's
checks"). The review run takes the ask, and its `record` step closes it once a
head it judged carries the fix (the review-lanes design, sections 1 and 8). That
close comes before the round ends. The refinery validates the run's last head
only after the run lets go of the bead, and when the target has moved it merges
the target in first, which is a new head the loop must judge (the review-lanes
design, section 5). A stay that waited on the ask would come back at the run's
`record`, before the head the operator approves exists. So the rework stay
watches the anchor instead.

The conversation cannot wait on the anchor through a `blocks` edge of its own,
because it already tracks the anchor and bd keeps one edge from a bead onto
another (`DependencyTypeConflictError`, beads `issueops/errors.go`). It waits on
an open input convoy that tracks the anchor, which Gas City closes when the
anchor closes, the wait section 5 takes from PR #1515. That wait sits beside the
anchor's `blocks` edge onto the conversation, the conversation's hold on the
PR's merge (`conversation_hold_merge` in `assets/scripts/gc-helm.sh`), without a
cycle, because bd's cycle check walks only `blocks`, `conditional-blocks` and
`parent-child` edges (`types.IsSchedulingEdge`, beads `internal/types/types.go`),
and the convoy reaches the anchor by `tracks`.

**Before the first review run.** A PR's anchor has an open input convoy from its
first review run on. The landing order pours every run with
`gc formula cook mol-pr-review --attach <bead>` (`runs.Pour` in
`services/gctk/internal/cli/prland.go`), and `mol-pr-review` declares
`formula_compiler = ">=2.0.0"`, the graph compiler's requirement
(`UsesGraphCompiler` in `internal/formula/requirements.go`). Gas City pours a
graph.v2 cook attached to a bead that is not a convoy over a one-item input
convoy that tracks it (`PrepareInvocation`, then `NormalizeInputConvoy` and
`CreateSingleItemInputConvoy` in `internal/graphv2/invocation.go`, which the
attach arm of `cmd/gc/cmd_formula.go` reaches). It closes that convoy only when
the pour fails (`CloseSyntheticInputConvoy`), or once the bead closes. So a PR on
the review path has one once its first run has poured, whether or not a sling
dispatched its work, and a change a sitting edited and handed over through
`work-submit.sh`, which slings nothing, has one too.

A PR whose first run has not poured has none, as when a conversation opened on a
fresh draft holds its bead, since a conversation that holds the bead and is not
staying keeps every run off it (`heldBy` in `services/gctk/pr/admit.go`). A
rework stay on such a PR waits on the ruling's ask, as tk-1tfzr71.128 built it,
and registers its session wait on the anchor as every PR stay does (section 3).
A conversation that waits on an open ask is staying, so the order can pour the
first run, which takes the ask and mints the convoy. The run's `record` closes
the ask, which brings the sitting back, and the sitting moves its wait onto that
convoy (section 3, The move). From then on the stay waits as this row says.
Section 2 counts it among the stays on the anchor through the ask from its
sign-off on, so the readiness that ends the rework's round waits for its
reading, as it does for every rework stay.

**Several works.** A stay names every bead it waits on. Each PR's bead among them
has its own wake and owes its own reading, so the sitting comes back at each PR's
readiness, and once more when the last of its work has closed.

**Another store.** A stay still waits only on work in its conversation's own
store, because an edge onto another store's bead holds nothing. The session wait
of section 3 can reach another rig's bead, but the sleep and the hold cannot, so
the sign-off keeps refusing that stay, and the sitting ends at the hand-off.

## 2. The reading is on the PR before you are asked

The ready transition is also the moment a PR starts to read as the operator's.
GitHub's draft flag is what its review requests and this repository's CI follow
(`.github/workflows/tests.yml` skips the suite on a draft and runs it on
`ready_for_review`). The evaluator reads a draft as a condition of the city's own
(`KindDraft` in `services/gctk/pr/pr.go`), and the status label reads
`needs-review` only once an approval is all that is left (`Render` in
`services/gctk/prstatus/render.go`), which a draft never is. So under call 1 (a)
the landing order keeps the PR a draft while a stay on its bead owes its reading.
The draft is not the whole hold, because a round can end on a PR that is ready
already, which no draft keeps from merging (section 4). The evaluator holds the
merge for the reading as well (The hold, below).

**The stays on a bead.** A stay on a bead B is a conversation, open or in
progress and assigned to its sitting's alias rather than to `human`, whose own
`blocks` edge reaches B directly, through an open input convoy that tracks B, or
through an ask on B that its newest `staying:` line names. Such a convoy tracks
B alone and carries no `owned` label, the rule `subject_convoy` in
`converse-signoff.sh` applies at PR #1515's head, because Gas City closes such a
convoy when B closes (`convoyStillAutocloses` in `cmd/gc/cmd_convoy.go`). An ask
on B is a task bead that B waits on through its own `blocks` edge
(`review.AsksOn` in `services/gctk/review/ask.go` reads each one). It counts
whether it is open or closed, so a rework stay that waits on the ruling's ask
(section 1, Before the first review run) holds from its sign-off on, through the
window between the ask's close at the run's `record` and its move, and after the
move, which writes no `staying:` line (section 3). It counts only while the
newest `staying:` line names it, because a conversation keeps its edges onto the
work of a stay that returned (`converse-entry.sh`), so a conversation that once
waited on an ask on B and now stays for other work owes B nothing through it.
The order reads the stays from the store: B's dependents through bd's edges
(`bd dep list --direction=up`), the rows of those that read as conversations
(`conversation.IsCandidate`), the dependents of each such convoy among them, and
each conversation among an ask's dependents whose newest `staying:` line names
that ask. Nothing new is recorded for this: the edges are the ones section 1's
table writes, and the lines are the ones the stay's round is read from (The
stay's round, below).
A conversation that tracks B and stays for other work reaches B through no edge
of its own, so it owes B nothing.

**A reading.** A reading is a comment on the PR, posted through
`pr-post.sh comment` like every post of the city, whose body opens with a marker
naming the conversation, the round of its stay and the head it read:

```
<!-- gc:reading <conversation> <round> <head> -->
```

**The stay's round.** Each `--stay` sign-off records a ruling, what the operator
agreed and the work it waits on, which is what the reading compares the PR with.
So each one starts a round of the stay, and a reading answers one round at one
head: a new ruling makes an earlier reading stop counting, even at the same head.
The round is the count of the conversation's `staying:` lines that name work, the
line a stay appends once everything but its wait has landed
(`converse-signoff.sh --stay`), so it is read from the notes the entry already
reads the stay from, and needs no record of its own. A stay that stopped short
and is run again appends that line again and counts one round more, but no
reading names the round it stopped in, because a stay that stopped short never
left the conversation to wait, and a reading comes only at a `ready` entry.

The comment is the rule's own condition, that the reading is on the PR, so
nothing else records it. The city's mark that `pr-post.sh` appends makes it the
city's own post, which the feedback intake never counts. Only a post of the
city's own counts as a reading, by the one definition of it (`gc_city_own` in
`pr-post.sh own-def`), which asks that the city's login posted it, so a marker
anyone else writes into a comment releases nothing. The evaluator reads the PR's
conversation comments on each pass (`GitHub.IssueComments` in
`services/gctk/pr/pr.go`), but the landing order consults `readyBar` before the
evaluator runs (`decide` in `services/gctk/pr/landing.go`), so under call 1 (a)
its draft arm reads the comments itself, and only for a PR whose bead has a
stay.

**The hold.** A stay owes its reading at the PR's head while no reading of its
current round at that head is on the PR, whether its conversation is open or in
progress. It holds the PR while it owes its reading or is in progress. A stay is
in progress when its sitting holds the conversation, which during a stay it does
to ask or talk with the operator (section 3, step 3; section 4, Talking with the
sitting again), and while it repairs the stay's wait, in the stopped-short
recovery of `converse-stay` and in the move (section 3). The rule has two
readers:

- **The evaluator** gains a condition of the city's that holds the merge while a
  stay on the bead owes its reading at the head or is in progress, whether the
  PR is a draft or ready. A PR that is ready already when its stay comes to owe
  a reading, as when a round ends at a head the PR was ready at (section 4), has
  no draft to keep, so this condition is what holds it.
- **`readyBar`** gains the same clause after the ones it has, under call 1 (a),
  so the order keeps the PR a draft for as long, and GitHub asks for no review
  before the reading.

The order's outcome names the conversation and the head. Once every stay on the
bead is open with its reading of its current round at the head on the PR, the
evaluator's condition is met, and the order marks a draft ready on its next pass
(`orders/pr-reconcile.toml`, every five minutes).

This departs from the review-lanes design's section 5 in where a round begins.
There a round begins at the city's first push after the PR was last marked
ready, so a review run that answers an ask with no push makes no round, and the
PR stays ready. A stay's round begins at its sign-off instead (A reading, above),
so its hold must reach a PR that is ready. A condition of the evaluator's reaches
it with no new writer of the draft flag, which the order sets only from draft to
ready and which only a writer that pushes returns to draft. The return to draft
that was weighed instead is in [gas-city-search.md](gas-city-search.md). The
condition holds the merge as an open ask or `merge_hold` does, which section 5
keeps holding after the PR is marked ready.

**What the operator sees while the sitting reads.** On GitHub, the PR is a draft,
or ready when its round ended on a PR that was ready already. Its `status:` label
reads `working`, or `merging` when an approval from an earlier round still stands
on it and no conversation that stays holds its merge (`Render`). `gctk pr status`
names the sitting's reading at the head among the conditions not met. The rig
board renders the PR from the same facts, with the reading as the city's work in
flight, and the conversation's own row as its stay. Once the reading is posted,
the PR shows it, the order marks a draft ready and CI runs, and the label turns
to `needs-review`, or to `merging` on a PR that an approval still stands on. A
stay that holds for the operator's answer reads as a person's move, whether or
not its reading is on the PR yet: the PR's label reads `needs-attention`, held
by that conversation.

**What the hold does not cover.**

- A person who marks the PR ready on GitHub themselves passes the draft, because
  the order changes the draft flag only from draft to ready, and a person's
  toggle is left for the cycle to finish (the review-lanes design, section 5).
  GitHub then asks for review before the reading is on the PR, and the
  evaluator's condition still holds the merge until it is.
- An operator who has opened a stay's conversation and not yet spoken in it.
  Engaging a live sitting attaches the operator to it and adds no hold, so the
  hold for the exchange begins at the sitting's claim on the operator's first
  turn (section 4). engage does not take the hold itself. A hold on the PR's
  merge that it wrote would stand under a stay nobody talks to: the PR would
  read as the city's work (`Render` reads a stay that holds a PR as `working`),
  and no wake would come to clear it. A claim that it wrote would read to the
  entry as a stay that stopped short, whose recovery stays again and lets the
  hold go. The window is the time the operator takes to write that turn, and a
  merge in it still waits for green checks and the landing order's next
  five-minute pass.
- A PR whose merge the landing order has already requested. The order reads the
  stays when it asks the evaluator whether the PR is ready, and requests the
  merge in the same pass, which it does only once every stay on the bead has
  its reading of its current round at the head on the PR and none is in
  progress. So the reading is on the PR when the merge is requested, and a
  claim that lands after that read does not stop the request. On a base with no
  merge queue, the request merges the PR at once. On a base that requires a
  merge queue, the order adds the PR to the queue and from then on leaves it to
  GitHub: `decide` in `services/gctk/pr/landing.go` returns before `readyBar`
  and the evaluator for a PR that is in its base's merge queue, so no condition
  the evaluator reads reaches it, this one included. GitHub merges it once the
  queue's checks pass, unless it leaves the queue first. A sitting the operator
  speaks to then holds its conversation but not the merge. No rig in the city
  has a merge queue on its default branch (GitHub's `repository.mergeQueue`,
  read for each rig on 2026-11-15), so the design builds nothing for a queued
  PR. On a rig that adds one, the stay's condition stops at the queue, as every
  condition of the evaluator's does.
- A stay whose sitting no wait can wake still stays, so it keeps the PR from
  merging, and a draft a draft, and the condition names it. That is a stay whose
  session has closed, whose return was cut short before it registered its wait
  again (section 3), or whose wait's note failed to reach it. The operator
  brings a sitting back by engaging the conversation, which runs the entry and
  the reading, or ends the stay by dismissing it. Gas City closes a session only
  when a person or a prune asks, and a hold that wedged silently would break the
  rule's other half, so the hold stands and names what clears it.

**Call 1 (b), if chosen.** `readyBar` gains no clause, so the order marks the PR
ready at once, and the evaluator's condition alone holds the merge and keeps the
label at `working` while CI runs. The stays, the reading and the wake are the
same, and the order marks the waits ready at the round's end, which on a draft is
as it marks the PR ready, the review-lanes design's section 9 sentence as
written.

## 3. The wake and the return

**The wake.** A stay also registers a Gas City session wait on each PR's bead it
watches, as its sign-off's last write. A sign-off cannot tell whether new work
will open a PR, so it registers one on each work bead the stay names:

```bash
gc session wait "$GC_SESSION_ID" --on-beads <the PR's bead> \
  --note "A PR this sitting stays for may wait for its reading: run converse-entry.sh."
```

The landing order marks such a wait ready (`gc wait ready <wait>`) on every pass
that finds the round ended at the PR's head while a stay owes its reading there.
The round has ended when `readyBar`'s conditions other than the draft flag hold:
the record is pending at the PR's head, a passed result names that head and the
target, no review run is attached to the bead and no ask a run can take is open
on it. On a draft, that is the pass on which the PR would leave draft but for the
reading. On a PR that is ready already, which `decide` takes to the evaluator
without consulting `readyBar`, it is the pass that finds the round over at a head
the PR was ready at. It marks the waits of each stay that owes its reading and
waits open: those in state `pending` whose `dep_ids` name the PR's bead and
whose `session_id` is the stay's sitting (`gc wait list --json`), the session
`gc session list --json` lists with the conversation's assignee as its `alias`.
A wait another session registered on the bead is left to turn ready when the
bead closes. Gas City wakes the session for
a ready wait (the `wait-ready` reason in `cmd/gc/compute_awake_set.go`) and
delivers its note as a queued nudge, `Wait satisfied (<wait>): <note>`
(`dispatchReadyWaitNudgesWithSnapshot` in `cmd/gc/cmd_wait.go`). The prompt runs
the entry on that notice, as it does on the notice that a blocker closed. A wait
whose bead closes first is marked ready by Gas City itself, at the same moment
the conversation's wait in the store brings the sitting back.

This is the review-lanes design's section 9 wake, with two changes. Under call 1
(a) the order marks the waits ready while the reading is owed, and the PR ready
only after it. Marking them as it marks the PR ready, as section 9 words it,
would ask the operator before the reading, which the rule rules out. And a round
that ends on a PR that is ready already comes to no ready transition, so the
order marks the waits ready at the round's end, which section 9 does not reach.

**Why the session wait is the wake and not the sleep.** An explicit wake,
`gc session wake` or the API's, cancels every wait of the session
(`Store.wakeSessionFromBead` in `internal/session/wait_store.go`), and an attach
to a stopped session asks the controller to start it "as gc session wake does"
(`gc session attach`). A fresh
restart cancels a wait registered before it as stale (`WaitInfo.ContinuationStale`
in `internal/session/waits.go`), and closing a session cancels its waits
(`prepareWaitWakeStateHooked` in `cmd/gc/cmd_wait.go`). A wait marked ready closes
once its note is delivered. So the wait cannot be the stay's record, as PR #1480's
search found for the sleep (`specs/tk-pb9wnr3/gas-city-search.md`), and the
conversation's edge stays the sleep and the record. A sitting brought back by an
attach or a restart runs the entry first, and the entry finds a stay missing its
wait, so `converse-stay` registers it again. Between a cancel and that
registration the hold still stands, because it reads the conversation, and the
entry reads its `ready` answer from the record, not the wait, so a readiness
reached in that window is read once the sitting is up.

**What the entry prints.** `converse-entry.sh` gains one entry beside `waiting`
and `returned`:

| Entry | What it means | The skill to load |
|---|---|---|
| `ready` | A PR this sitting stays for waits at its head for this sitting's reading. | `converse-stay` |

Beside the values a stay prints (`CONV`, `CONVERSATION`, `SUBJECT`, `GATES`,
`WORK`, `AGREED`), a `ready` entry prints `READING=<the PR's bead> <the round>
<the head> <the PR's URL>` and `READ=<the head this conversation last read on
that PR, in any round>`, or `READ=none`. A `waiting` or `ready` entry also prints
`WAIT=` with the open session wait on each PR's bead the stay watches, or
`missing`, and `MOVE=<convoy>` while the stay owes its move (The move, below).

The entry asks gctk, which holds the hold's rule, rather than deciding the rule
itself: `gctk pr status <bead> --json` gains a `reading` key, `{"head": <oid>,
"owed": [{"conversation": <id>, "round": <n>}...], "held": [<conversation>...]}`,
present while the round has ended at the PR's head and a stay owes its reading
there or is in progress, on a draft or on a PR that is ready already. `owed`
names a stay in progress as well while its reading is not on the PR, and `held`
names every stay in progress. The entry reads `ready` when `owed` names its
conversation, and takes the round it prints from there, so the round is counted
once, in gctk. It checks for `ready` after a stay that stopped short
(`interrupted`) and before `returned` and `waiting`. A conversation that holds,
whose newest record is a `holding:` line, reads `ready` while `owed` names it,
as after a return cut short between recording its hold and posting its reading
(A return cut short, below), and otherwise reads as the hold that stands
(`interrupted`, with `converse-continue`).

**The move.** A rework stay that waits on the ruling's ask (section 1, Before the
first review run) is brought back when the run's `record` closes the ask, because
the ask was its wait in the store. The PR's bead is still open, so the work is
still out. The stay owes its move while its newest `staying:` line names an ask
that has closed on a PR's bead that is still open, an open input convoy tracks
that bead by section 2's rule, and the conversation has no `blocks` edge onto
such a convoy. The entry reads a stay that owes its move in place of `returned`.
It answers `waiting`, or `ready` when the round ended before the sitting came
back, and prints `MOVE=` with one such convoy. `converse-stay` makes the move
before anything else:

1. **Make the guarded write the sign-off ends on**, which leaves the conversation
   open under its sitting and drops any claim its wake took.
2. **Write the conversation's `blocks` edge onto `MOVE`.**
3. **Register each session wait `WAIT` names as `missing`.**

The status write comes before the edge, where the sign-off writes the edge
first, so that a move cut short never leaves the conversation claimed while it
waits on open work, which the entry reads as a stay that stopped short, or at
`ready` as a return under way. Between the two writes the conversation is open
with nothing holding it, which reads as ready work, but its sitting is awake and
writes the edge next. A restart between them wakes the sitting to the same
entry, since the stay still owes its move, and `converse-stay` makes the move
again, its status write dropping the claim that entry took.

At `waiting` the sitting then sleeps again, and reads, posts and tells nothing.
At `ready` it goes on to the return below. The move writes no `staying:` line, so
the stay's round stays the one its sign-off started, and the reading at the
round's end answers that round. From then on the stay waits as section 1's
rework row says, so every round of section 4 applies to it.

From the ask's close until the move, the conversation, which holds the PR's
merge, waits on nothing open, so the landing order reads it as holding the bead
rather than staying, and pours no run on it (`heldBy`). The move's edge lets the
next pass pour, which a later head in the round, such as a merge of the target,
needs. When the ask has closed and no open input convoy tracks the PR's bead, no
run took the ask, because a run that takes one has poured such a convoy, so the
ask closed without a run, as when a person closes it: the stay owes no move, and
the entry answers `returned`.

**The return at `ready`.** `converse-stay`'s return gains a reading, in this
order:

1. **Register the wait again, then read the PR at the head `READING` names**, the
   head the refinery validated and the review run passed. The wake's wait closed
   once its note was delivered, so the return first registers each wait `WAIT`
   names as `missing`, and a return cut short while the conversation waits open
   is woken again by the order's next pass. When `READ` names an earlier head of
   the same PR, read the change since that head (`git diff <READ>..<head>`), with
   the review run's account of each head between them. When `READ` names this
   head, as after a round that ended with no push, the PR has not changed since
   the last reading: read how the round's review run ruled each ask the new
   ruling filed, declined, deferred or answered, from the rulings the run
   records.
2. **Compare it with what was agreed**, `AGREED` and the thread, as the return
   compares today.
3. **Decide whether the comparison leaves the operator anything to answer before
   they approve, and make the write that the answer needs.**
   - **It does.** Claim the conversation back and record the hold in one guarded
     write: the claim-back's `gc bd update` (`converse-stay`) carries the hold's
     `holding:` line (`converse-hold`) as its `--append-notes`, and bd applies
     the guard and both changes as one update. From before the reading lands
     until the operator answers, the PR does not merge, and a draft stays a
     draft (call 2, option a). A conversation that holds already, as when the
     return runs again, has made this write.
   - **It does not.** Lift the conversation's hold on the PR's merge when it
     holds one, with the lift `converse-hold` gives a sitting that is helping
     the PR land, because that hold waited for this reading and the operator's
     approval now decides. The stay still owes its reading, so the evaluator's
     condition goes on holding the merge, and a draft a draft, until the post.
4. **Post the reading** through `pr-post.sh comment`, its body opening with the
   marker. A restart reads whether this post has landed (A return cut short,
   below). When a comment with this conversation's marker for this round and
   head is on the PR already, as when an earlier post landed and its reply did
   not, edit it in place with `pr-post.sh edit`.
5. **Hold, or stay on.** When the conversation holds, as step 3's write or an
   earlier hold left it, finish the hold whose record is its newest `holding:`
   line (`converse-hold`). Otherwise record and post the hand-back, which says
   what the reading found and that the sitting comes back at the next readiness
   or when the work closes. Staying on writes nothing else: the conversation's
   wait in the store is unchanged, and the next entry registers the session wait
   again.

**A return cut short.** A restart reads whether the post has landed. Until it
lands, the stay owes its reading, so the evaluator's condition holds the merge,
and the entry reads `ready`, both for an open conversation cut short before or
after its lift and for one that holds, cut short after step 3's write. The
return then runs again. It registers only the waits `WAIT` names as missing. Its
lift can run again, because bd's `dep remove` confirms the same way whether or
not the edge is still there (`cmd/bd/dep.go` at beads v1.3.4). A conversation
that holds already makes no second claim. Once the post has landed, the stay
owes nothing. A restart on the clean path then reads `waiting`, and the sitting
ends its turn with nothing said and nothing recorded, as `converse-stay` has it
while the work is out. Only the return's hand-back is lost: the operator's tab
prints the stay's last recorded hand-back, and the reading on the PR says what
the return found. A restart on the held path reads as the hold that stands,
whose `holding:` line step 3 wrote, and the sitting takes the hold up again from
the record (`converse-continue`, After a restart). The suite holds each case.

**The return at `returned`.** The work closed: its PR merged, or it closed without
one. The return reads how it closed. When the PR merged at a head this
conversation read, it says so in a line and signs off, with nothing left to
compare. Otherwise it compares as it does today. A sign-off that ends the stay
cancels the stay's open session waits (`gc wait cancel`), so no wait outlives its
conversation.

## 4. Every round

**When the sitting reads again.** Every readiness of the PR owes a reading from
each stay on its bead that has no reading of its current round at that head on
the PR. A new head owes one, whatever started the round: a send-back the
operator ruled through the sitting, an ask someone put on the PR, a repair after
a failing check, or a merge of the target. A new ruling of the stay owes one
too, even when its round ends at the head the last reading read (A send-back
through the sitting, below). The rule puts the reading on the PR before the
operator is asked to approve, and they are asked about the head the round ends
at. A round's reading reads only the change since the head the conversation last
read, so a merge of the target that git made without help, or a one-line repair,
costs a short reading.

**No reading twice.** A reading is one comment per conversation, round and head,
which its marker names. `reading.owed` names a conversation only while no post
of the city's own with its marker for the stay's current round at the head is on
the PR, so a wake at a head the sitting has read in this round reads `waiting`,
and a return that runs again edits a comment of its own that it finds there
rather than posting a second (section 3, step 4). An ask someone else put on the
PR, which the review run answers with no push, leaves the head and the stay's
round as they were, so the reading stands.

**A send-back through the sitting.** On the review path, a ruling that sends the
PR back files an ask on the PR's bead with the checks it names, through
`converse-rework.sh` for the PR the conversation is about and through the `prs`
skill's `gctk review ask` for another PR, such as new work's. The sitting stays
again on the same work, with the same wait in the store, and that sign-off starts
the stay's next round. The ask holds the PR's bead by its own edge while it is
open. The round ends in one of two ways:

- **The review run pushes a fix.** Its push returns the PR to draft, and the
  round ends at the new head, as any round does.
- **The run declines, defers or answers the ask.** Its pass rule counts such an
  ask as ruled (`judge` in `services/gctk/review/passed.go`), its `record` closes
  the ask as a no-op (`answeredAsks` in `services/gctk/review/result.go`), and
  its push step, with nothing to push, returns before it would return the PR to
  draft (`cmd_push` in `assets/scripts/review-run.sh`). The round ends at the
  head the PR was ready at, with the PR still ready. The new round's reading is
  owed all the same, so the evaluator's condition holds the merge, and the order
  wakes the sitting at the round's end (sections 2 and 3). The return reads how
  the run ruled the ask, and when that departs from what the operator agreed,
  it asks them before the PR can merge (call 2).

The operator's approval of an earlier round carries across the round unless
triage rules it material (the review-lanes design, section 4). With no new head,
the change triage reads since the last passed head is empty (the review-lanes
design, section 2), so the evaluator's condition is what keeps that approval from
merging the PR before the reading.

**Talking with the sitting again.** When the operator takes up a stay's
conversation again and speaks, the sitting holds before it answers their first
turn: it claims the conversation back and records the hold in the one guarded
write the return's hold makes (section 3, step 3), then holds (`converse-hold`).
The stay is then in progress, so no PR it watches merges unless the landing
order has already requested its merge (section 2, What the hold does not
cover), and a draft stays a draft. The exchange ends in a sign-off:

- **Staying again** starts the stay's next round, whose reading the merge then
  waits for. When the operator rules that nothing changes, the sitting stays
  again with the same agreement, and its reading of that round says so in a line.
- **Ending the stay** closes the conversation, which no longer holds the PR.

The sitting of a stay on work that opens no PR holds nothing for the exchange,
because there is no merge to hold, and answers the operator through the
sign-off's `--answer`, as `converse-stay` has it. Before the operator's first
turn nothing holds the merge for the exchange (section 2, What the hold does not
cover).

**What ends the stay.**

- **The merge.** The PR's bead closes. The conversation's wait in the store
  clears, directly or because Gas City closes the input convoy with the bead it
  tracks, and the sitting comes back to `returned`.
- **The work's close without a PR**, such as a close as a duplicate or a stand
  down. The same.
- **The operator.** A sign-off without `--stay` closes the conversation over its
  wait and cancels its session waits, and the conversation is no longer among
  the PR's stays, so the hold lets go.

## 5. The conversation's own subject

PR #1515 (its head 6ffdc541f, which `refs/pull/1515/head` keeps) let a sitting
stay when its ruling sends its own subject or takes its recommendation, by waiting
on the input convoy the subject's dispatch pours, and came back after the merge.
What holds from it:

- **The wait in the store.** The conversation tracks its subject, so it cannot
  write a `blocks` edge onto it. A graph.v2 sling of a bead pours its run over a
  convoy that tracks that bead alone (`graphv2.NormalizeInputConvoy` and
  `CreateSingleItemInputConvoy` in `internal/graphv2/invocation.go`), and Gas
  City closes that convoy when the bead closes (`doConvoyAutocloseWith` and
  `convoyStillAutocloses` in `cmd/gc/cmd_convoy.go`). A `blocks` edge onto it
  sleeps the sitting until the subject closes. Section 1's rework row composes
  the same wait for the same reason.
- **An open convoy only.** A convoy closed by hand, or a second stay's edge onto a
  convoy that has closed, is no wait. PR #1515's correctness round made its entry
  count only an open convoy (finding tk-xvjd1u7, fixed at 275cbf44b), and the
  build keeps that.
- **The order of a sitting that sends its subject.** It sends the subject first,
  so the convoy exists, and then stays. A stay with no open convoy to wait on and
  no `--accept` is refused before any write.
- **A subject that went out with no formula's sling**, such as a change a sitting
  resumed and handed over through `work-submit.sh`, has no convoy that closes
  with it when the sitting signs off. Its PR's first review run pours one
  (section 1, Before the first review run), but only after the hand-off. Its
  stay is refused before any write, and the sitting ends at the hand-off.

What changes is when it comes back. The stay also watches the subject as its PR's
bead, so it comes back at each readiness of the subject's PR, not after the merge.
PR #1515 closed re-homed onto tk-vrg93t0, so the build takes its convoy wait and
its entry's reading of that wait from its head, and none of its return.

## 6. A rig still on the old review path

The ready transition runs only in the landing order, which a rig's PRs reach once
its cutover sets `pending_through_merge` and moves its open beads onto the record
(`refinery-land.sh`; tk-1tfzr71.78 for gc-toolkit). On the old path nothing marks
a PR ready for approval in a form a stay could wait on. The code that comes
closest, `gate-ensure.sh`'s settled verdict, is on the deletion plan with
tk-1tfzr71.22, so it gets no new work (AGENTS.md), and neither does
`rework-child.sh`, which retires with it.

Until a rig cuts over:

- **The stay registers the same session waits on both paths**, and its wait in
  the store differs only for a rework, which on the old path waits on its rework
  child, as today. On the old path no order marks a session wait ready, and Gas
  City marks it ready only when its bead closes, which brings the sitting back no
  earlier than the conversation's wait in the store does. So the stay comes back
  as the initiative's table "What is built today" has it: a rework when it
  reaches the PR's branch, through the rework child, and new work or the
  conversation's own subject after the merge.
- **The sitting says when.** It tells the operator when its stay would come back,
  and recommends ending at the hand-off, with what was agreed written into the
  work's brief in full, when that is after the merge. That is tk-lv4r5mv's rule,
  which landed on main in #1523 after this design read main, and it stands for
  those rows until the rig's cutover.
- **How it tells the path.** A PR's bead whose merge result is on the record is on
  the new path (`pr.OnRecord`, which `gctk pr status` reads). For work that has
  no PR yet, the rig's switch tells it, read as `refinery-lib.sh` reads the
  rig's formula vars (`gc formula show mol-refinery-patrol --rig <rig> --json`,
  the var `pending_through_merge`).

Once the rig cuts over, its PR stays come back at readiness with no change to the
stay, because the waits are already the ones the new path reads.

## 7. What the pack's pages say

Each page and skill that describes a stay states the rule and when each stay
comes back, by section 1's table, with the old path's rows until a rig cuts over:

- **`docs/human-engagement.md`**, its section "A sitting that stays for the
  return": the rule, the table, the hold and what the operator sees (section 2),
  the wake and the reading (section 3), every round and talking with the sitting
  again (section 4), the old path (section 6).
- **The converse prompt's "End or stay?"** (its decision 4): the sitting says when
  the stay would come back, by the table. It recommends staying when its reading
  will help the operator judge the result before they approve, and ending at the
  hand-off where the rig's path brings the stay back after the merge. Its table of
  entries gains `ready`, and it runs the entry on a `Wait satisfied` notice.
- **`converse-stay`**: the stay's session wait, the move (section 3), `ready`,
  the return's reading with its post as the last write and each restart of the
  return, staying on, every round, the hold while the operator talks with the
  sitting again in place of today's "Do not hold" for a stay on a PR, and what
  ends the stay.
- **`converse-settle`**: the order of a sitting that sends its subject and stays
  (section 5), and that a stay on a PR's work keeps the PR from merging, and a
  draft a draft, until its reading is on it.
- **`converse-hold`**: a hold during a stay, after a reading or while the
  operator talks with the sitting again, records its `holding:` line in the
  write that claims the conversation back, and keeps the PR from merging, and a
  draft a draft, until the operator rules, unless the landing order has already
  requested the merge. A reading that leaves the operator nothing to answer
  lifts the conversation's hold on the PR's merge before it is posted.
- **`docs/product-goals.md`** gains one sentence in its "Human gates and
  conversations" surface: a conversation the operator asks to stay with its work
  comes back before their next decision about that work, never after it, and for
  a PR its reading is on the PR before they are asked to approve. That is a
  promise about when a surface the operator watches reaches them, which the PM
  check judges a change to a stay against. Everything else stays in the pages
  above, because the file states goals and surfaces, not features.

tk-lv4r5mv wrote these passages for the old path, and they are on main. The words
unit rewrites them once, on the effort's branch brought current with main
(sections 9 and 10).

This design's own change states the rule in `docs/architecture.md`, at the
document's altitude, because a design that moves the architecture changes that
document. Its "How humans engage" says when a stay comes back, what the city
holds for the reading, as a draft or by the merge of a PR that is ready already,
and that a sitting the operator talks with again holds the PR until they rule,
unless the landing order has already requested its merge.
Step 9 of its "How work moves" names the wake beside the close, and its Debt
names the gap until the build lands, with tk-vrg93t0 as the work that retires
it. The words unit narrows that Debt entry
to the rigs still on the old review path. It also gives
`docs/lifecycle-composition.md`, which calls `closed` the one signal the waiting
side keys on, the exception step 9 names.

## 8. The surface this adds

Each item's search is in [gas-city-search.md](gas-city-search.md).

- **`converse-signoff.sh --stay`**, an existing mode, gains: the session wait on
  each PR's bead it watches; `--waiting-on` naming the subject, through the
  subject dispatch's input convoy; the rework stay's wait on the review path,
  through the anchor's input convoy, or through the ruling's ask while the
  anchor has none; and, in a sign-off that ends a stay, the cancel of the stay's
  waits.
- **`converse-entry.sh`** gains the `ready` entry with its `READING`, which names
  the round, and `READ` values, `WAIT` on a `waiting` entry, and `MOVE` on a
  `waiting` or `ready` entry of a stay that owes its move (section 3). It also
  reads `ready` for a conversation that holds while its stay owes its reading.
- **The evaluator** (`pr.Ready`) gains a condition of the city's: a stay on the
  bead that owes its reading at the head, or is in progress, holds the merge.
  `gctk pr status` and both boards name it among the conditions not met.
- **The landing order** (`gctk pr reconcile`) gains one clause in its ready
  transition, and the wake at a round's end, on a draft or on a PR that is ready
  already, through its Gas City adapter (`services/gctk/internal/gascity`):
  `gc session list --json`, `gc wait list --json` and `gc wait ready`.
- **`gctk pr status --json`** gains the `reading` key, and `prstatus` gains the
  stays on a bead, read through their edges onto it, onto its open input
  convoys and onto its asks, and their readings among the facts it renders.
- **A reading's marker** in the body of a PR comment, naming the conversation,
  the stay's round and the head.

None of it is a store, a lifecycle state, a bead kind or a metadata key. The
stays are read off the edges a stay already writes, a stay's round off the
`staying:` lines it already writes, the reading off the comment the rule asks
for, and the wake is Gas City's.

## 9. The units

Each unit lands on `integration/tk-vrg93t0`, keeps the suite green and leaves the
city working. On a rig still on the old path, nothing a unit adds runs but the
waits a stay registers, which nothing there marks ready.

| Unit | What it does | Waits on | Releases |
|---|---|---|---|
| 1. The reading rule, the hold and the wake | First, a probe in a scratch city: a session wait with no `--sleep` on a sleeping session, marked ready with `gc wait ready`, wakes the session and delivers its note, and an attach to the sleeping session cancels it. Then, in the pr domain: the stays on a bead, read from the store, and each stay's round, read from its conversation's `staying:` lines (section 2); each stay's reading of its round at a head, read from the PR's comments by the marker; the evaluator's condition and `readyBar`'s clause; in the landing order's pass, the wake at a round's end, on a draft or on a PR that is ready already, through the Gas City adapter's `gc session list --json`, `gc wait list --json` and `gc wait ready`, which marks only the waits of the stays that owe their reading; `gctk pr status --json`'s `reading` key; `prstatus` renders a stay that owes its reading as the city's work and a stay in progress as a person's move, whether or not it owes its reading. Tests, one per row of section 1's table: the hold and the wake for new work through a `blocks` edge, for a rework and for the subject through an open input convoy, for a rework through an ask on the bead before its first review run, both while the ask is open and after it has closed, nothing for a closed convoy, nothing for an ask the conversation's newest `staying:` line no longer names or for a conversation that tracks the bead and stays for other work, and nothing for work with no PR; a stay in progress holds the draft and the merge of a ready PR, is named in `held`, and in `owed` as well while its reading is not on the PR, and is not woken; every stay's reading of its current round at the head lets the PR leave draft and meets the condition; a reading at an earlier head, or of an earlier round at the same head, does not; a send-back whose ask the run declines, defers or answers with no push owes the new round's reading, so on a ready PR an approval of an earlier round does not merge it until that reading is on it, and the order marks the stay's wait ready at the round's end; an ask someone else put on the PR that ends with no push owes no new reading; a person's toggle to ready is left alone and the merge still waits; a wait already ready is not marked again; a wait another session registered on the bead is left alone; a store or GitHub read that fails leaves the draft and is retried; a PR already in its base's merge queue is left to GitHub, whatever its stays owe or hold: the pass requests no merge, no removal from the queue and no change of its draft flag. | tk-1tfzr71.22 | unit 2 |
| 2. The stay and the entry | `converse-signoff.sh --stay`: the session wait on each PR's bead; the subject's convoy wait and its refusals, from PR #1515's head with its open-convoy fix; the rework stay's convoy wait on a PR on the record, and the ask when the anchor has no open convoy; on the old path, the waits as they are; a sign-off that ends a stay cancels its waits. `converse-entry.sh`: `ready` with `READING`, its round included, and `READ`, read from `gctk pr status --json`; `WAIT` on `waiting`; `MOVE` on a stay that owes its move; `ready` for a conversation that holds while its stay owes its reading; the restarts of section 3's return. Tests, one per row: what the sign-off writes for each, the sign-off's wait on the ask with its session wait on the anchor when the anchor has no open convoy, `waiting` and `ready` with `MOVE` once the ask has closed, the move's status write, edge and wait, `returned` when the ask closed with no open convoy, a restart between the move's status write and its edge, the entry's answer before, during and after a reading, a second wake at a head already read in the round, `ready` for a new round at the head the last reading read, a stopped stay run again, which counts one round more before any reading, a missing wait after an attach and at a `ready` wake, a return cut short after it registered its wait again, and a restart between each two steps of the return: on the clean path, after its lift, which reads `ready` and finishes, and after its post, which reads `waiting` with the merge hold lifted and only the hand-back lost; on the held path, after the one write that claims and records the hold, which reads `ready` and posts with the hold standing, and after its post, which reads as the hold that stands. | unit 1 | unit 3 |
| 3. The words | The converse prompt's "End or stay?" and its entry table, and its seven renders; `converse-stay`, its move, the return's order with the reading's post last, and its hold while the operator talks with the sitting again included, `converse-settle` and `converse-hold` (section 7); `docs/human-engagement.md`; the sentence in `docs/product-goals.md`; `docs/lifecycle-composition.md`'s close signal; the skill-needs pins of the table and of each example's call through the real parsers; the stay's Debt entry in `docs/architecture.md`, narrowed to the rigs still on the old review path (section 7). | unit 2 | the landing |

The initiative's "Done when" asks for a test of each row of the table. Units 1
and 2 hold the rows in their suites, and unit 3 pins them in the words.

## 10. Edges and notes the implementation child adds

- The implementation child (tk-y4iqs8j) files the units the way it was filed
  itself (`docs/design-convoy.md`), with `target=integration/tk-vrg93t0` in each
  create. The landing bead
  (tk-vrg93t0) and the summary task (tk-pgxs4zx) wait on every unit through a
  `blocks` edge. Each unit waits on what its row names, through a `blocks` edge,
  and is armed.
- Unit 1 waits on tk-1tfzr71.22, whose branch carries the ready transition and
  the asks this builds on. Once tk-1tfzr71.22 has landed on main, the effort's
  branch is brought current with main before unit 1 builds
  (`skills/work/integration-effort.md`, "Bring the effort's branch current").
- Unit 3 needs no edge onto tk-lv4r5mv, which has closed. The passages it wrote
  for the old path reach the effort's branch when that branch is brought current
  with main before unit 1, and unit 3 rewrites them there.
- A note on tk-1tfzr71.78, gc-toolkit's cutover: among the rig's first PRs on the
  new path, watch one stay through a round, from the hold and the wake to the
  reading and the PR leaving draft.
- A note on tk-35ob5gq, the city board's reading of a stay: the city board reads a
  stay that owes its reading by the same facts, once unit 1 has added them.

## 11. Facts this design rests on

Gas City, at 8e7d91b583:

- `gc session wait` needs at least one `--on-beads` and a `--note`, registers a
  wait for the session `$GC_SESSION_ID` names by default, and marks it ready at
  once when its beads have already closed (`cmdSessionWait` and `doSessionWait`
  in `cmd/gc/cmd_wait.go`). A `deps` wait turns ready when its beads close, all
  of them or any (`depsWaitReadyDetailedFrom`). `gc wait ready <wait>` marks one
  ready by hand, and `gc wait list --json` names each open wait's session, state
  and `dep_ids` (`docs/reference/cli.md`, `gc wait`).
- A ready wait wakes its session (the `wait-ready` reason in
  `cmd/gc/compute_awake_set.go`) and reaches it as a queued nudge, `Wait satisfied
  (<wait>): <note>` (`dispatchReadyWaitNudgesWithSnapshot`), and it closes once
  the nudge is delivered (`finalizeReadyWaitFromNudge`).
- An explicit wake, `gc session wake` or the API's, cancels every wait of its
  session (`Store.wakeSessionFromBead` in `internal/session/wait_store.go`,
  through `Store.WakeSession`), `gc session attach` asks the controller to
  start a stopped session as `gc session wake` does, a wait registered before a
  fresh restart is cancelled as stale (`WaitInfo.ContinuationStale` in
  `internal/session/waits.go`), and a closed session's waits are cancelled
  (`prepareWaitWakeStateHooked`). A wait hold, which `--sleep` sets, suppresses a
  session's demand-driven wake (`cmd/gc/compute_awake_set.go`).
- A graph.v2 sling of a bead, and a graph.v2 cook attached to a bead that is not
  a convoy, pour over a convoy that tracks that bead alone (`PrepareInvocation`,
  `NormalizeInputConvoy` and `CreateSingleItemInputConvoy` in
  `internal/graphv2/invocation.go`, which the attach arm of
  `cmd/gc/cmd_formula.go` reaches). Gas City closes that convoy when the pour
  fails (`CloseSyntheticInputConvoy`) or once the bead closes
  (`convoyStillAutocloses` in `cmd/gc/cmd_convoy.go`).

bd, at beads v1.3.4:

- A `gh:pr` gate waits for its PR's merge (`cmd/bd/gate.go`), and nothing in bd or
  Gas City closes at a PR's readiness.
- bd keeps one edge from a bead onto another (`DependencyTypeConflictError`), and
  its cycle check walks only `blocks`, `conditional-blocks` and `parent-child`
  edges (`types.IsSchedulingEdge`).
- `bd dep remove` confirms the same way whether or not the edge was there
  (`cmd/bd/dep.go`), and a guarded `bd update` applies its guard and every
  change it carries, `--status` and `--append-notes` among them, as one update
  (`cmd/bd/update.go`).

GitHub, through its GraphQL API, read on 2026-11-15:

- `dequeuePullRequest` removes a pull request from its base's merge queue, and
  `enqueuePullRequest` adds one (GitHub's GraphQL reference, mutations).
- No rig in the city has a merge queue on its default branch
  (`repository.mergeQueue`, read for each rig whose origin is on GitHub).

The pack, at main 5d4c3b4cf and `integration/tk-1tfzr71.22` 04d8dad0d:

- The landing order marks a draft ready when `readyBar` finds nothing that keeps
  it a draft, without waiting for CI (`services/gctk/pr/draft.go`,
  `services/gctk/pr/landing.go`), on a five-minute cooldown
  (`orders/pr-reconcile.toml`). It consults `readyBar` only for a draft, and asks
  the evaluator directly about a PR that is ready (`decide`).
- For a PR that is in its base's merge queue, `decide` returns before `readyBar`
  and the evaluator, and the order requests a merge, or adds a PR to its base's
  merge queue, only in the pass whose evaluator read found it ready, after
  reading the bead once more (`services/gctk/pr/landing.go`). Nothing in gctk
  removes a PR from a merge queue (`services/gctk/internal/gh/gh.go`).
- A review run can pass with no push. Its pass rule counts an ask ruled
  declined, deferred or answered as ruled (`judge` in
  `services/gctk/review/passed.go`), its `record` closes such an ask as a no-op
  (`answeredAsks` in `services/gctk/review/result.go`), and its push step returns
  before `gctk pr draft` when the worktree is at the head the round judged
  (`cmd_push` in `assets/scripts/review-run.sh`). Only a writer that pushes
  returns a PR to draft (`Draft` in `services/gctk/pr/draft.go`).
- The landing order pours each review run with
  `gc formula cook mol-pr-review --attach <bead>` (`runs.Pour` in
  `services/gctk/internal/cli/prland.go`), and `mol-pr-review` declares
  `formula_compiler = ">=2.0.0"`.
- A conversation its sitting stays in, which a wait of its own holds, keeps no
  review run off the branch, and an open conversation that holds the bead and
  does not stay keeps every run off it (`heldBy` in
  `services/gctk/pr/admit.go`). `prstatus` reads a stay that holds a PR as
  `working` (`Render`).
- An ask is a task bead the PR's bead waits on through its own `blocks` edge,
  with a `discovered-from` edge onto the bead it came from, and `review.AsksOn`
  reads every ask on a bead, open or closed (`services/gctk/review/ask.go`).
  `converse-signoff.sh --stay` is the pack's writer of a conversation's own
  `blocks` edges, which `converse-entry.sh` reads as a stay's: "nothing but a
  stay gives a conversation a `blocks` edge".
- A conversation on an open PR holds the PR's merge through the anchor's
  `blocks` edge onto it (`conversation_hold_merge` in `assets/scripts/gc-helm.sh`),
  and `converse-hold` lifts that edge for a sitting that is helping the PR land.
  The lift lasts for the sitting: engage adds the edge only for a conversation
  no live sitting holds, and attaches the operator to a live one without adding
  it (`gc-helm.sh`, engage).
- While its work is out, a staying sitting answers the operator through the
  sign-off's `--answer` and does not hold (`skills/converse-stay`, "While the
  work is out"), and the entry reads a claimed stay whose newest record is its
  `staying:` line as one that stopped short, and a claimed one whose newest is a
  `holding:` line as a hold that stands (`converse-entry.sh`).
- `converse-entry.sh` prints `fresh`, `interrupted`, `waiting`, `returned`, `none`,
  `stop` or `unreadable`, and reads a stay off its `staying:` lines and its own
  `blocks` edges. A stay writes those, then the edge, then a guarded write that
  leaves the conversation open under its sitting (`converse-signoff.sh --stay`).
- CI skips its suite on a draft and runs it on `ready_for_review`
  (`.github/workflows/tests.yml`).
- `gate-ensure.sh` and `rework-child.sh` are on the deletion plan with
  tk-1tfzr71.22 (`tools/deletion-plan.tsv`).
- A rig is on the new path once its `pending_through_merge` formula var is
  `true` (`refinery-land.sh`, `refinery-lib.sh`).
