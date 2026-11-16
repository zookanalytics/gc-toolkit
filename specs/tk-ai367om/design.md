---
name: Design — a stay comes back before your next decision about its work
description: The design for tk-ai367om, the design child of initiative tk-vrg93t0, read at main 713e3a733 against Gas City upstream main 76a06b2327 and beads v1.3.4. It gives the stay as the Gas City commands it runs, when each stay comes back, the hold that keeps a PR from merging before the discussion, a return that always waits for the operator, every round, settling and a conversation that stays available until its subject closes, the conversation's own subject, visits and fresh contexts while the work is out with the Gas City changes the return waits on, a rig on the old review path, the pages, what the earlier draft's machinery became, the surface and the units. Read it to approve the design at its gate, or to build one of its units.
---

# Design: a stay comes back before your next decision about its work

This is the design record for tk-ai367om, the design child of the initiative
tk-vrg93t0. It follows the brief the operator approved in conversation
tk-8e83do9 on 2026-11-16, recorded on tk-ai367om as "Proposed rework brief for
PR #1529". The initiative's rule still frames it: a stay comes back at the
operator's next decision about the work, never after it.

The pack was read at main 713e3a733, which carries the review run, its draft
cycle and its asks since the review-lanes effort landed (tk-1tfzr71.22, PR
#1531). Gas City is cited by symbol or page at `gastownhall/gascity` main
76a06b2327, and bd at beads v1.3.4. The search behind each piece of surface the
units add is [gas-city-search.md](gas-city-search.md).

## What the operator approves

Today a sitting you ask to stay comes back when its work's bead closes. For new
work that opens its own PR, that is after the PR has merged, too late to change
anything. A rework of the PR you discussed comes back when it reaches the
branch, before its checks run again, and a stay on the conversation's own
subject is refused. A sitting that comes back and finds nothing to ask signs
off.

Approving this design changes that on every rig that has moved onto the review
run:

- **A stay is a promise to come back before your next decision about the
  work.** The sitting registers it with Gas City as a session wait on the work,
  and Gas City wakes the sitting with its thread when the wait is satisfied. For
  work that opens a PR, your next decision is the approval, so the promise is
  satisfied when the PR is ready for it, in every round. For work that opens no
  PR, it is satisfied when the work closes.
- **The sitting always comes back to you.** It reads the result against what you
  agreed, posts what it found on the PR and in its hand-back, and waits to
  discuss it with you, even when it finds that the work matches. What it finds
  is advice, never one of the PR's checks.
- **The PR does not merge before that discussion.** When a round ends, the city
  puts on the PR the hold a conversation already keeps on a PR it discusses,
  and wakes the sitting. The landing order marks the PR ready as it does today,
  so CI runs and GitHub requests your review while the sitting reads, usually a
  few minutes before what it found is on the PR. You release the merge by
  settling the exchange, and the conversation stays available until its subject
  closes. Leaving the terminal neither approves the work nor cancels the
  promise.
- **Only native pieces carry it**: Gas City's session wait and its notice, a
  convoy, and the conversation's existing hold on a PR's merge. The earlier
  draft's reading marker, rounds, merge condition, draft rule and entry state
  are gone (section 11).
- **A visit or a fresh context keeps the promise.** Gas City cancels a
  session's waits today when an attach starts it from sleep, and when a reset
  gives it a fresh context. Keeping them is Gas City's work, built in the
  city's fork: gc-gspdoo for the attach and gc-lwa1vp for the reset. The
  return is turned on only once the city's Gas City carries both, because the
  unit that turns it on waits on a gate in this store that you clear then. The
  other units are built meanwhile. Before its return, a promise ends only when
  you end the stay or the sitting's session closes for good (section 8).
- **On a rig still on the old review path**, a rework stay still comes back when
  the rework reaches the branch, and the sitting tells you that any other stay
  would come back only after the merge.

Your ruling of 2026-11-16 in conversation tk-8e83do9, recorded on tk-ai367om as
"Second operator rework ruling", settled two points that the previous revision
of this design left otherwise. GitHub asks for your review at once at the end
of a round, and the return waits for Gas City to keep its promise through a
visit and a fresh context.

## 1. The stay, in commands

A stay runs these steps in this order:

1. **Agree and send the work.** The sitting and the operator agree what the work
   must do, and the sitting sends it as it does today. It slings new work or the
   subject, or sends the PR under discussion back through `converse-rework.sh`,
   which on the review path files the ruling as an ask on the PR's bead.
2. **Stay.** `converse-signoff.sh --stay` records what the operator agreed and
   leaves the conversation open under its sitting, waiting in the store on the
   work through a convoy that tracks it (section 2). That wait is what lets the
   sitting sleep.
3. **Promise the return.** Once the stay has landed, the sitting registers a
   session wait on each bead it promises to come back for, with the instruction
   its return follows:

   ```bash
   gc session wait "$GC_SESSION_ID" --on-beads <the bead> \
     --note "Conversation <conversation>: <the bead> is ready for the operator's next decision. Read it against what was agreed, post what you found, and wait for the operator."
   ```

4. **Keep talking, or leave.** While the operator is attached, the sitting runs
   and answers them. Once they detach, Gas City sleeps it after its template's
   idle window (`sleep_after_idle`, ten minutes for the converse templates),
   because its conversation waits on open work. The promise does not need the
   sitting awake.
5. **Come back.** When the promise's wait is satisfied, Gas City wakes the
   sitting, resumes its thread (`wake_mode = "resume"`), and delivers the note
   as `Wait satisfied (<wait>): <note>`. The sitting holds the conversation for
   the operator, reads the result, compares it with what was agreed, posts what
   it found, and waits for the operator (section 4).
6. **The operator rules.** They can send the work back, and the sitting runs
   steps 1 to 3 again for the next round. They can settle the exchange, and the
   sitting releases the PR's merge and stays available (section 6). Or they end
   the conversation.

What each command does in Gas City today, and what a stay uses it for:

| Command | What it does | In a stay |
|---|---|---|
| `gc session wait <session> --on-beads <beads> --note <text>` | Records a durable wait for the session, as a bead of its own that names the beads. It turns ready when those beads close, or when someone marks it ready, and it is ready at once when they have closed already. A ready wait wakes the session, delivers the note as a queued nudge, and closes once the nudge is delivered. | The promise, registered once the stay has landed. |
| `--sleep` on that command | Also sets the session's wait hold and asks the controller to sleep the session now. The hold keeps every other wake out, an attached client's included, until a wait is ready. It applies only when the wait is registered: no command sleeps a session on a wait it already has. | Not used. The operator is attached when the stay is signed off, and the idle window sleeps the sitting once they leave. |
| `gc wait ready <wait>` | Marks a wait ready by hand. | The landing order's wake at the end of a round (section 3). |
| `gc wait list [--session <session>] --json` | Lists the waits still open, pending or ready, with their session, state and the beads they watch. A wait closes once its notice is delivered or it is cancelled, and the list then leaves it out. | How the landing order finds pending promises, and how the sitting finds its open ones (section 4). |
| `gc wait inspect <wait> --json` | Reads one wait in any state: `pending`, `ready`, `closed` with its nudge's id once its notice is delivered, or `canceled`. | How the sitting confirms a notice, which names its wait. |
| `gc wait cancel <wait>` | Cancels a wait. | Withdraws a promise when the operator ends the stay. |
| `gc session attach <session>` | Attaches to a running session and changes nothing else. A session that is not running is started by the controller "as gc session wake does", which today cancels every wait the session has. | The way back in. Once the city's Gas City carries gc-gspdoo, which the return waits on, an attach that starts a sleeping sitting keeps its promise (section 8). |
| `gc runtime drain-ack` | Lets the controller stop the session, and the sitting's tab title then reads done. The core reaper closes a drained session after a day. | Never while staying, because the reaper's close would cancel the promise. A sign-off that ends the conversation drains. |
| `gc session close` | Ends the session for good, and cancels its waits. | Not in a stay. |
| `gc session reset` | Restarts the session with a fresh thread, and cancels each wait registered before the restart as stale. | A return's hand-over to a fresh context (section 4). Once the city's Gas City carries gc-lwa1vp, which the return waits on, the promises still pending go on into the fresh thread (section 8). |

The stay's wait in the store and its promise do different jobs. Gas City keeps a
manual session awake while ready or claimed work is assigned to it, and sleeps
an idle one only while what is assigned to it waits on something open
(`compute_awake_set.go`). The conversation is assigned to its sitting, so the
stay's own `blocks` edge is what lets the sitting sleep, as PR #1480 built it.
That edge also keeps the conversation reading as a stay to the landing order
(`heldBy` in `services/gctk/pr/admit.go`) and to the boards
(`conversation.Staying`), which lets the PR's review runs go on while the work is
out. The promise is what brings the sitting back at the right moment, which no
close in the store marks for a PR.

## 2. When each stay comes back

On a rig that has moved onto the review run, each stay comes back as this table
gives. Section 9 gives a rig still on the old review path.

| The ruling sends | The stay waits in the store on | The promise watches | It comes back |
|---|---|---|---|
| New work that opens its own PR | an open convoy that tracks the work | the work's bead | at the end of each round on its PR, and when the work closes |
| A rework of the PR under discussion | an open convoy that tracks the PR's anchor | the anchor | at the end of the round the rework starts, and of each later round the operator rules |
| The conversation's own subject | an open convoy that tracks the subject | the subject | at the end of each round on the subject's PR, and when the subject closes |
| Work that opens no PR | an open convoy that tracks the work | the work's bead | when the work closes |

**The moment a PR is ready for the operator's approval.** A round ends when the
record is pending at the PR's head, which is the head the refinery validated,
a passed result of the review run names that head and the PR's target, no
review run is attached to the bead, and no ask a run can take is open on it.
These are the conditions of `readyBar` (`services/gctk/pr/draft.go`) other than
the draft flag. On a draft, the round ends on the pass that marks it ready
(`decide` in `services/gctk/pr/landing.go`). On a PR that is ready already, as
after a send-back the run answers with no push, it ends on the pass that finds
those conditions met at the head the PR was ready at. A PR stay's promise is
satisfied at that moment, and at no bead's close:

- **Not the anchor's close.** The anchor closes once the merge commit is on the
  target, after the decision the return is meant to inform.
- **Not the ask's close.** On the review path a ruling's rework is an ask on the
  PR's bead, which the run's `record` step closes once a head it judged carries
  the fix. The refinery validates that head only after the run lets go of the
  bead, and when the target has moved it merges the target in first, which
  makes a new head the loop must judge. So the ask can close before the head
  the operator approves exists.
- **A rework child's close, on the old path only.** There the rework is a child
  the refinery lands on the PR's branch, and its close means the change the
  operator asked for is on the branch, before the approval. That is the
  promised result, so the old path's rework stay waits on it (section 9).

**Why every stay waits through a convoy.** The hold of section 3 is the PR's
bead's `blocks` edge onto the conversation, and bd refuses it while the
conversation blocks on that bead, because its cycle check walks `blocks`,
`conditional-blocks` and `parent-child` edges (`types.IsSchedulingEdge`, beads
`internal/types/types.go`). A convoy reaches the bead by `tracks`, which that
check does not walk. A stay on the conversation's own subject has a second
reason: the conversation tracks the subject, and bd keeps one edge from a bead
onto another (`DependencyTypeConflictError`, beads `issueops/errors.go`), so
the conversation cannot block on its subject at all.

So every stay waits through a convoy, on either path: the edge onto a convoy
holds the sitting exactly as an edge onto the work would, because the convoy
closes when the work does. The convoy is one that tracks the bead alone and
carries no `owned` label, which Gas City closes once the bead closes
(`convoyStillAutocloses` in `cmd/gc/cmd_convoy.go`). A graph.v2 sling of the
work pours over one, and so does each review run, which the landing order pours
with
`gc formula cook mol-pr-review --attach <bead>` (`runs.Pour` in
`services/gctk/internal/cli/prland.go`). Gas City mints a fresh one-item convoy
for each such pour (`NormalizeInputConvoy` and `CreateSingleItemInputConvoy` in
`internal/graphv2/invocation.go`). The sign-off waits on the newest open one,
the rule `subject_convoy` applies in `converse-signoff.sh` at PR #1515's head.
When none is open, as for a change handed over through `work-submit.sh`, a raw
route or a PR whose first review run has not poured, it makes one with
`gc convoy create <name> <bead>`.

**Several works.** A stay names every bead it waits on, and the sitting promises
a return on each bead whose decision it is staying for. It comes back at each,
and once more when the last of its work has closed.

**Another store.** A stay still waits only on work in its conversation's own
store, because an edge onto another store's bead holds nothing, so the sign-off
keeps refusing that stay, and the sitting ends at the hand-off.

## 3. The hold: the PR waits for the discussion

**The hold is the one a conversation already keeps.** A conversation on an open
PR holds its merge through the anchor's `blocks` edge onto the conversation
(`conversation_hold_merge` in `assets/scripts/gc-helm.sh`; "A conversation on an
open PR holds its merge" in `docs/human-engagement.md`). The evaluator reads
that edge as a wait of the bead's own (`ownWaits` and `KindWait` in
`services/gctk/pr/pr.go`). It holds only the merge, and the PR's review runs go
on while the conversation stays, because `heldBy` keeps no run off for a
conversation its sitting stays in.

**The landing order puts it on at the end of a round.** In each pass, for a PR's
bead whose round has ended (section 2), the landing order reads the pending
session waits that name the bead (`gc wait list --json`). For each whose session
is the sitting of a conversation that is open or in progress, which is the
session `gc session list --json` lists with that conversation's assignee as its
alias (`conversation.IsAssignee`), it first writes the PR's bead's `blocks` edge
onto the conversation, and then marks the wait ready (`gc wait ready <wait>`).
It does both before it marks a draft ready or asks the evaluator about a PR that
is ready, so the pass that ends the round requests no merge.

- An edge already there, as engage writes it for the conversation's own
  subject, is a no-op.
- A write or a read that fails leaves the wait pending, and the next pass tries
  again.
- A wait that is ready already, one that another session registered on the
  bead, and one whose conversation has closed are left alone. Gas City marks the
  other session's wait ready when the bead closes, and cancels a closed
  conversation's once its drained session closes.

**Nothing needs it before the round ends.** Before then the PR is not at the
decision the promise is for, and the evaluator reads it ready only once the
review run has passed at the head the refinery validated with nothing on the
bead left to wait on (`Ready` in `services/gctk/pr/pr.go`).

**Only the operator's settlement lifts it.** The sitting lifts the hold only on
the operator's ruling that settles the returned exchange, with the lift
`converse-hold` gives a sitting (`gc bd dep remove <bead> <conversation>`). It
never lifts the hold because it found nothing to ask. A sign-off that ends the
conversation releases the hold with the close, as every close does.

**What the operator sees.** From the end of the round until the sitting takes the
return up, the PR's `status:` label reads `working`, because the conversation
still stays, and `prstatus` reads a staying conversation that holds a PR as the
city's work (`Render` in `services/gctk/prstatus/render.go`; `Staying` in
`gates.go`). Once the sitting holds the conversation for the operator, the label
reads `needs-attention`, held by that conversation, which is the operator's move,
and the board shows the sitting's hand-back. By then the PR is ready for review,
so GitHub has requested the operator's review and CI has run on its head. Once
the operator settles and the sitting lifts the hold, the label follows the PR's
own conditions again.

**What the hold does not cover.**

- **A merge the landing order has already requested.** After a settlement the
  order requests the merge once the evaluator reads the PR ready. On a base with
  no merge queue it merges at once. On a base that requires a merge queue, the
  order adds the PR to the queue and leaves it to GitHub from then on, because
  `decide` returns before `readyBar` and the evaluator for a PR in its base's
  merge queue. A sitting the operator speaks to after that holds its
  conversation but not the merge. No rig in the city has a merge queue on its
  default branch (GitHub's `repository.mergeQueue`, read for each rig on
  2026-11-16), so the design builds nothing for a queued PR.
- **A sitting whose session has closed.** The landing order writes no hold for
  a promise it does not find, and nothing wakes the sitting for it. A visit and
  a fresh context keep a promise (section 8), so before its return a promise is
  gone only once the operator has ended the stay, which closes the conversation
  and its holds with it, or once the sitting's session has closed for good.
  After a session's close, a PR whose merge the conversation holds through
  engage's edge, such as the PR under discussion, stays held, reading
  `working` and naming the conversation, until a sitting takes the conversation
  up again and promises again (section 4). Any other PR merges on the
  operator's approval meanwhile, and the stay comes back when the work closes.
- **The minute between the end of a round and the sitting's wake.** The PR is
  held and reads `working`, and the sitting has not yet posted what it found.

## 4. The return

The sitting takes the return up on the promise's notice, in this order:

1. **Confirm the notice.** A `Wait satisfied` notice is text in the prompt
   stream, so the sitting reads the wait it names in the record
   (`gc wait inspect <wait> --json`) and acts only on a wait of its own session,
   ready or closed by that delivery, that names a bead its stay waits for.
2. **Hold first.** It claims the conversation back and records the hold's
   `holding:` line in one guarded write: the claim-back's
   `gc bd update --if-assignee "$GC_ALIAS" --if-status open --status in_progress`
   (`converse-stay`) carries the line as its `--append-notes`, and bd applies the
   guard and both changes as one update (`cmd/bd/update.go`). From then on the
   conversation is the operator's move, and a restart reads the hold that stands
   (`converse-entry.sh`, `interrupted`, with `converse-continue`).
3. **Read the result** at the PR's head, which is the head the round ended at,
   with the change since the head the sitting last read and the review run's
   account of each round between.
4. **Compare it with what was agreed**, the thread and `AGREED`, as the return
   compares today.
5. **Post what it found** on the PR through `pr-post.sh comment` and in its
   hand-back: where the work matches what was agreed and where it departs, as
   advice. When it finds that the work matches, it says so.
6. **Wait for the operator.** The hold stands until they rule.

**A return cut short.** A restart after step 2 reads the hold that stands, and
the sitting carries the return on from its thread, or from the record when the
thread is gone: the hold's line and what it has already posted on the PR. A
restart between the notice and step 2 resumes the thread, which holds the
notice.

**A promise that is gone.** Gas City lists only the waits still open, pending or
ready, so a promise leaves `gc wait list --session "$GC_SESSION_ID" --json` once
its notice is delivered, when the operator's ending cancels it, and when the
session closes. A visit and a fresh context keep it (section 8). So on every
entry that reads `waiting`, the sitting reads its open promises. It then
registers each promise the stay's hand-back names that no open promise names
and whose notice its thread does not hold, as the stay's own step 3 does. That
covers three cases:

- **A restart between the stay and the promise.** The promise was never
  registered, and this registers it.
- **A notice that reached a thread which ended before it held the
  conversation**, such as a thread a reset replaced at that moment. The round's
  end still holds at the PR's head, so the landing order marks the new promise
  ready on its next pass, finds its hold there already, and the sitting comes
  back once. On work that has closed, Gas City marks the promise ready at once.
- **A sitting that takes the conversation up after its session closed.** The
  stay still owes its returns, so the new sitting promises them.

A return the sitting has taken up holds the conversation, so its entry reads the
hold that stands, not `waiting`, and it registers nothing. A settled stay names
no promise. The sitting never asks the operator whether to promise again, and
nothing records a promise beside Gas City's own list and the stay's hand-back.

**A hand-over while another return is pending.** A return handed to a fresh
context resets the session (`converse-stay`, "When your context runs low during
the return"). The promise it is returning on was delivered already. Each other
promise still pending goes on into the fresh thread, because gc-lwa1vp keeps a
session's open waits through a fresh restart (section 8). The fresh thread
finishes the return from the hand-over, and each other promise brings it back
when its work is ready, as it would have brought back the thread before it.

**The return at the work's close.** When the work closes, merged or closed
without a PR, the stay's wait in the store clears, its promise turns ready as
well, and the entry reads `returned`. The sitting reads how the work closed.
When the PR merged at a head it already discussed with the operator, it says so
in a line. Otherwise it reads and compares as above. Then it ends the
conversation if the subject has closed, and otherwise stays available
(section 6).

## 5. Every round

**A send-back through the sitting.** The operator's ruling sends the PR back: an
ask on the PR's bead through `converse-rework.sh` for the PR under discussion,
or `gctk review ask` through the `prs` skill for another PR such as new work's.
The sitting stays again and promises again, and the hold stays on the PR. The
round ends whether or not the review run pushes:

- **The run pushes a fix.** Its push returns the PR to draft, and the round ends
  at the new head, as any round does.
- **The run declines, defers or answers the ask.** Its pass rule counts such an
  ask as ruled (`judge` in `services/gctk/review/passed.go`), its `record` closes
  the ask as a no-op (`answeredAsks` in `services/gctk/review/result.go`), and
  its push step, with nothing to push, returns before it would return the PR to
  draft (`cmd_push` in `assets/scripts/review-run.sh`). The round ends at the
  head the PR was ready at, and the landing order finds it over on the PR that is
  ready already.

Either way the promise registered for this round is pending when the round
ends, so the sitting comes back. An approval the operator gave in an earlier
round cannot merge the PR meanwhile, because the hold stands.

**A round the city starts by itself**, such as a repair after a failing check or
a merge of the target, ends once, at the head the city leaves. A promise
registered before it is satisfied at that end.

**One return per promise.** A promise's wait closes once its notice is
delivered, so each promise brings the sitting back once, and each round the
operator rules is a promise of its own. Nothing records which head a return
read, because no rule waits on that record.

## 6. Settling, and a conversation that stays available

**Settling.** The operator rules that the returned exchange is settled, for
example that the work may merge. The sitting lifts the hold, records the ruling,
and stays on with no promise: it signs off with `--stay` on the same work and
registers no session wait. The conversation is open under its sitting again, the
sitting sleeps, and nothing holds the PR for it.

**Available until the subject closes.** The operator can come back to the
conversation at any time by attaching, and nothing in the sitting's absence
approves or cancels anything. When the work closes, the sitting comes back
(`returned`), says how the work closed, and ends the conversation if the subject
has closed. While the subject is still open, it stays on the subject instead, a
stay whose wait in the store is a convoy that tracks the subject, again with no
promise. So the conversation stays available until its subject closes.

**Ending.** The operator can end the conversation at any time. The sitting
cancels its pending promises (`gc wait cancel <wait>`), and the sign-off without
`--stay` closes the conversation and releases its holds with the close. A ruling
that settles a discussion-only subject and closes it ends the conversation the
same way, as today.

## 7. The conversation's own subject

PR #1515 (its head 6ffdc541f, which `refs/pull/1515/head` keeps) let a sitting
stay when its ruling sends its own subject, by waiting on the input convoy the
subject's dispatch pours, and came back after the merge. What holds from it:

- **The wait in the store** is a convoy that tracks the subject, as section 2
  gives for every stay.
- **An open convoy only.** A convoy closed by hand, or one that has closed, is no
  wait. PR #1515's correctness round made the entry count only an open convoy
  (finding tk-xvjd1u7, fixed at 275cbf44b), and the build keeps that.
- **The order of the writes.** The sitting sends the subject first, so the
  dispatch's convoy exists, then stays, then promises.
- **The subject waits on nothing of its own convoy.** A `blocks` edge from the
  subject onto a convoy that tracks it would hold the subject's own work and its
  close, so the sign-off writes the conversation's wait alone.

What changes is when the sitting comes back: at the end of each round on the
subject's PR, not after the merge. The sign-off takes a stay on the subject on
either path, since the convoy removes the edge bd would refuse. A stay on the PR
under discussion is the same case on the review path, so there the sign-off
stops refusing a stay on the PR whose merge the conversation holds, because the
stay comes back before that merge. On the old path it keeps refusing that stay
(section 9).

## 8. Visits and fresh contexts while the work is out, and the Gas City changes they need

**A visit while the sitting runs**, with the operator's tab still attached or
within the idle window: `gc session attach` attaches and changes nothing else,
so the promise stands. The sitting answers the operator through the sign-off's
`--answer` while the work is out, as `converse-stay` has it.

**A visit to a sleeping sitting** asks the controller to start the session "as gc
session wake does" (`sessionAttach.attachOnceControllerStarts`, then
`doSessionWake`, in `cmd/gc/cmd_session.go` and `cmd/gc/cmd_session_wake.go`).
`Store.WakeSession` cancels every wait the session has, and withdraws their
queued notices, as it clears what keeps the session from starting
(`wakeSessionFromBead` in `internal/session/wait_store.go`). So today that visit
cancels the promise, though the attach resumes the same conversation.

**The change, which is Gas City's (gc-gspdoo).** An attach that starts a stopped
session resumes it with its pending waits and their queued notices kept. These
are the callers of the wake today, which the change must weigh:

- `gc session attach` for a session that is not running, the change's own case.
- `gc session wake`, the operator's explicit wake.
- The API's session wake (`handleSessionWake` in
  `internal/api/handler_sessions.go`, and `Server.wakeSession` in
  `internal/api/huma_handlers_sessions_command.go`).
- The API's message resume, which already keeps waits but consumes only an
  operator's suspend (`Store.ResumeHeld` in `internal/session/resume.go`), and
  whose notes say never to reuse the wake there because it cancels the session's
  waits (`internal/api/AGENTS.md`).

The narrowest change is a wake for the attach alone that keeps the waits.
Whether `gc session wake` and the API's wake should keep them too is Gas City's
call once it has reviewed their callers.

**A fresh context.** `gc session reset` asks for a fresh restart:
`SessionHandle.Reset` (`internal/worker/handle_lifecycle.go`) calls
`Manager.RequestFreshRestart` (`internal/session/manager.go`), which writes
`continuation_reset_pending` beside `restart_requested`. The start that consumes
the reset moves the session to its next `continuation_epoch`
(`cmd/gc/reconcile_effect_launch.go`). Each wait registered before the reset
then reads stale and is cancelled with the reason `continuation-stale`
(`WaitInfo.ContinuationStale` in `internal/session/waits.go`;
`prepareWaitWakeStateHooked` in `cmd/gc/cmd_wait.go`). So today a return handed
to a fresh context ends every other promise the sitting has pending, though the
session, its alias and its conversation go on. Gas City already spares one
kind of wait: a wait registered while the reset is pending is marked
`registered_reset_pending` (`CreateWait` in `internal/session/wait_store.go`),
belongs to the conversation the restart opens, and is delivered there
(`DeliveryEpoch` and `HeldForPendingReset`).

**The change for a fresh context, which is Gas City's (gc-lwa1vp).** A fresh
restart of a session that stays open keeps its open waits, pending or ready.
Each goes on into the conversation the restart opens, as a wait registered while
the reset is pending does already, and a ready one's notice is delivered there.
A fresh restart then ends no wait, so a wait still ends once its notice is
delivered, once `gc wait cancel` cancels it, or once its session closes. The
narrowest change covers the restart a session or its operator asks for. Whether
the controller's own fresh restarts, the other writers of
`continuation_reset_pending`, keep waits too is Gas City's call. gc-lwa1vp is
filed beside gc-gspdoo in the Gas City rig and held for the operator's
placement.

**Until both land, the return is not on.** The operator ruled in conversation
tk-8e83do9 on 2026-11-16 ("Second operator rework ruling" on tk-ai367om, items 1
and 2) that the early visit must not cancel a promise and ask the operator to
promise again. The same ruling says a context hand-over must not withdraw the
sitting's other promises or ask the operator to authorize them again. So keeping
a promise through a visit and through a fresh context is a prerequisite for
turning the return on, not a gap the return ships with. The words unit, which
turns the return on, waits on a gate in this store, which the operator clears
once the city's Gas City carries both changes, built, verified and running, with
no wait for upstream (section 14). Units 1 and 2 build meanwhile, and the effort
lands only after the words unit. Gas City owns both changes, their local patch
in the city's fork and their upstream path. No flag for either exists today, and
nothing in the pack depends on one.

The ruling asks for that native behavior "with an explicit handover or a bounded
restriction on resets until that behavior exists". This design builds neither
bridge, because the gate keeps the return off until both changes run, so no
promise exists for a reset to withdraw before then. A restriction in the pack
would also bind only the resets a sitting makes itself, not an operator's.

**No command sleeps a session on a wait it already has.** A stay needs none,
because the idle window sleeps the sitting once the operator leaves, and a ready
wait wakes a session whether it slept idle or under a wait hold. The cost is
that a sitting the operator leaves keeps running for up to its idle window.

## 9. A rig still on the old review path

The end of a round is read only by the landing order, which a rig's PRs reach
once its cutover sets `pending_through_merge` and moves its open beads onto the
record (`refinery-land.sh`; tk-1tfzr71.78 for gc-toolkit). On the old path no
order marks a promise ready, and Gas City marks it ready only when its bead
closes. So until a rig cuts over:

- **A rework stay** waits on its rework child, through a convoy as every stay
  does, and promises on the child, so it comes back when the rework reaches the
  PR's branch, before the approval. The conversation's hold on the anchor, which
  engage writes, holds the merge until the operator settles the return.
- **A stay on new work or on the conversation's own subject** would come back
  after its PR merges. The sitting says so and recommends ending at the
  hand-off, with what was agreed written into the work's brief in full, which is
  tk-lv4r5mv's rule on main.
- **A stay on the PR whose merge the conversation holds** stays refused, because
  it would wait for that merge while the conversation holds it, and nothing
  would bring the sitting back before it.
- **How the sitting tells the path.** A PR's bead whose merge result is on the
  record is on the new path (`pr.OnRecord`, which `gctk pr status` reads). For
  work with no PR yet, the rig's switch tells it, read as `refinery-lib.sh` reads
  the rig's formula vars (`gc formula show mol-refinery-patrol --rig <rig> --json`,
  the var `pending_through_merge`).

`gate-ensure.sh` and `rework-child.sh` are on the deletion plan with
tk-1tfzr71.122 (`tools/deletion-plan.tsv`), so neither gets new work.

## 10. What the pack's pages say

Each page and skill that describes a stay states the rule and when each stay
comes back, by section 2's table, with the old path's rows until a rig cuts
over:

- **`docs/human-engagement.md`**, its section "A sitting that stays for the
  return": the stay's commands and what each does (section 1), when it comes back
  (section 2), the hold and what the operator sees (section 3), the return
  (section 4), every round (section 5), settling and availability (section 6),
  visits and fresh contexts (section 8) and the old path (section 9).
- **The converse prompt's "End or stay?"** (its decision 4): the sitting says when
  the stay would come back, by the table, and that it will come back to discuss
  the result whatever it finds. On a `Wait satisfied` notice the prompt confirms
  the wait and runs the return (`converse-stay`).
- **`converse-stay`**: the promise's command after the stay lands, the return's
  steps with the hold first, a return cut short, a promise that is gone and
  registered again, a hand-over while another promise is pending, settling,
  staying available, visits, and ending.
- **`converse-settle`**: send, then stay, then promise, and a stay on the
  conversation's own subject (section 7).
- **`converse-hold`**: the hold of a returned exchange, recorded in the write
  that claims the conversation back, and the lift of the PR's merge hold only on
  the operator's settlement.
- **`docs/product-goals.md`** gains one sentence in its "Human gates and
  conversations" surface: a conversation the operator asks to stay with its work
  comes back to discuss it before their next decision about that work, never
  after it. That promise is about when a surface the operator watches reaches
  them, so it is a goal the PM check judges a change to a stay against.

The words unit rewrites the passages tk-lv4r5mv wrote for the old path once, on
the effort's branch brought current with main (sections 13 and 14).

This design's own change states the rule in `docs/architecture.md` at the
document's altitude. Its "How humans engage" says what a stay promises, that a
visit and a fresh context keep the promise, when it comes back, that the return
always waits for the operator, what holds the PR until the operator settles, and
that the conversation stays available until its subject closes. Step 9 of its
"How work moves" names the wake beside the close. Its Debt names the stay that
comes back only when its work closes, with tk-vrg93t0 as the work that retires
it, and the promise Gas City does not yet keep through a visit or a fresh
context, with gc-gspdoo and gc-lwa1vp. The words unit removes the second entry,
which the gate it waits on makes untrue, and narrows the first Debt entry to the
rigs still on the old review path, and gives `docs/lifecycle-composition.md`,
which calls `closed` the one signal the waiting side keys on, the exception step
9 names.

## 11. What the earlier draft built, and what this keeps

The design this replaces kept the PR a draft until the sitting posted a marked
reading, and released the hold itself when the reading found nothing to ask.
Under the approved brief the return always waits for the operator, so nothing
waits for a reading to be posted, and the operator's settlement is the release.
Each piece was weighed for whether this design still needs it:

- **The reading's marker, and the stay's round counted from its lines**: dropped.
  No rule waits on a posted reading, and each round the operator rules is a
  promise of its own, which brings the sitting back once.
- **`gctk pr status`'s `reading` key and its owed and held lists**: dropped. The
  landing order reads the promises themselves, through Gas City.
- **The evaluator's condition for a stay**: dropped. The hold is the
  conversation's existing edge, which the evaluator already reads as a wait.
- **The clause that kept the PR a draft for the reading**: dropped. The operator
  ruled that GitHub asks for review at once at the end of a round, so no draft
  rule is kept, not even the narrower one keyed on the promise's notice that the
  previous revision offered as an option.
- **The move onto the first review run's convoy**: dropped. A rework stay on the
  review path waits through a convoy that tracks the anchor from its sign-off,
  one the sign-off makes when no run has poured one.
- **The entry's `ready` and its `READING`, `READ`, `WAIT` and `MOVE` values**:
  dropped. The notice says why the sitting woke, and the record, read with
  `gc wait inspect`, confirms it.
- **The clean return's lift of the merge hold**: dropped. Only the operator's
  settlement lifts it.
- **Kept**: the wake at the end of a round, now with the hold put on before it;
  the convoy wait from PR #1515; the narrowing to the waits of the stays' own
  sittings; the merge-queue boundary; and the old path's rows.

## 12. The surface this adds

Each item's search is in [gas-city-search.md](gas-city-search.md).

- **The landing order** (`gctk pr reconcile`) gains one step in its pass: at the
  end of a round, for each pending session wait on the PR's bead whose session is
  the sitting of an open or in-progress conversation, the hold and then the wake,
  through its Gas City adapter (`services/gctk/internal/gascity`:
  `gc wait list --json`, `gc session list --json` and `gc wait ready`) and the
  store's `blocks` edge. Its ready transition is unchanged.
- **`converse-signoff.sh --stay`**, an existing mode, waits through a convoy that
  tracks each bead it waits on, the newest open one or one it makes with
  `gc convoy create`. It takes a stay on the conversation's own subject, writing
  the subject no wait onto its own convoy, and on the review path a stay on the
  PR whose merge the conversation holds. It gains no flag.
- **`converse-entry.sh`** reads a stay's wait through its convoy, as it read it
  at PR #1515's head. It gains no entry and no value.

The promise is a command the sitting runs itself, `gc session wait`, so it is no
surface of the pack's. None of the surface is a store, a lifecycle state, a bead
kind or a metadata key.

The landing order's step is Go in gctk's pr domain. The two scripts change what
an existing mode writes and what the entry reads. That corrects what the stay's
first Debt entry in `docs/architecture.md` names: a stay that comes back only
when its work closes, and that is refused on the conversation's own subject.
They add no verb, mode or key, so the build changes them in place under the rule
for a script that already exists (`AGENTS.md`, "New pack code is written in Go,
in gctk").

## 13. The units

Each of units 1 to 3 lands on `integration/tk-vrg93t0`, keeps the suite green
and leaves the city working. On a rig still on the old path, nothing they add
runs but the convoy wait and the promise, which Gas City marks ready at the
bead's close.

| Unit | What it does | Waits on | Releases |
|---|---|---|---|
| 0. Gas City keeps a session's waits through an attach that starts it (gc-gspdoo) and through a fresh restart (gc-lwa1vp) | The changes of section 8, built by Gas City: their local patch in the city's fork, and their upstream path. Each bead's "Done when" is its test: a wait still pending after the attach, and after a reset that hands one return over while another wait is pending, wakes the session with its note once marked ready. | nothing in this effort | unit 3, through the gate of section 14, which the operator clears once the city's gc carries both, built, verified and running |
| 1. The hold and the wake at the end of a round (gctk) | First, a probe in a scratch city: a session wait with no `--sleep`, on a session that has slept, marked ready with `gc wait ready`, wakes the session and delivers its note. Then, in the pr domain: in the landing order's pass, at the end of a round on a draft or on a PR that is ready already, for each pending session wait on the bead whose session is the sitting of an open or in-progress conversation, the bead's `blocks` edge onto that conversation, then `gc wait ready`, before the ready transition or the evaluator's read. Tests: the hold and the wake for new work, for a rework and for the subject; a send-back the run answers with no push wakes the sitting at the round's end on a ready PR, and an approval from an earlier round does not merge it; a promise registered after its round ended, as section 4's fresh thread registers it, is marked ready on the next pass, with the hold already there left alone; a round with no pending promise writes nothing; a wait of another session, a wait already ready, a wait whose conversation has closed and an edge already there are left alone; a failed read or write leaves the wait pending and is retried; a PR in its base's merge queue is left to GitHub. | the effort's branch brought current with main | unit 2 |
| 2. The stay waits through a convoy (scripts) | `converse-signoff.sh --stay`: the wait onto the newest open convoy that tracks each bead it waits on, or onto one it makes with `gc convoy create`; a stay on the subject, with the subject left waiting on nothing of its own convoy, from PR #1515's head with its open-convoy fix; on the review path, a stay on the PR whose merge the conversation holds; on the old path, that stay refused as today. `converse-entry.sh`: `waiting` and `returned` read through the convoy. Tests, one per row of section 2 and of section 9: what the sign-off writes, a convoy made when none is open, a closed convoy that is no wait, the entry before and after the convoy closes, and the old path's refusal. | unit 1 | unit 3 |
| 3. The words | The converse prompt's "End or stay?" and its handling of a `Wait satisfied` notice; `converse-stay`, `converse-settle` and `converse-hold` (section 10); `docs/human-engagement.md`; the sentence in `docs/product-goals.md`; `docs/lifecycle-composition.md`'s close signal; the skill-needs pins of the table and of each example's call through the real parsers, among them a hand-over while another promise is pending, whose reset cancels no promise, and the entry that reads `waiting` registering only a promise that is neither open nor held as a notice; the stay's first Debt entry in `docs/architecture.md`, narrowed to the rigs still on the old review path, and its second, the promise Gas City does not keep, removed. A check in a scratch city on the city's gc: a sitting's promise still pending after an attach that starts it from sleep, and after a reset that hands one return over while another promise is pending, brings the sitting back when marked ready. | unit 2, and the gate of section 14 | the landing |

The initiative's "Done when" asks for a test of each row of the table. Units 1
and 2 hold the rows in their suites, and unit 3 pins them in the words.

No unit builds terminal access: a wrapper around engage's attach, richer tab
status, the subject's PR in the terminal, and finding and cleaning up terminals
are epic tk-uipsrmt's, which is held for prioritization and blocks nothing here.
The return path needs none of them.

## 14. Edges and notes the implementation child adds

- The implementation child (tk-y4iqs8j) files units 1 to 3 the way it was filed
  itself (`docs/design-convoy.md`), with `target=integration/tk-vrg93t0` in each
  create. The landing bead (tk-vrg93t0) and the summary task (tk-pgxs4zx) wait on
  every unit through a `blocks` edge. Each unit waits on what its row names,
  through a `blocks` edge, and is armed.
- Unit 0 is filed already, as gc-gspdoo and gc-lwa1vp in the Gas City rig, each
  held for the operator's placement. An edge onto another store's bead holds
  nothing, so unit 3 waits on them through a human gate in this store, the gate
  the waits skill gives a bead whose blocker is in another store
  (`skills/waits/SKILL.md`, "Make a bead wait on other work"). The
  implementation child files the gate on unit 3 once it has filed the unit, and
  arms unit 3 as it arms every unit:

  ```bash
  "$(gc gc-toolkit scripts-dir)/human-gate.sh" --subject <unit 3> --key gas-city-keeps-waits \
    --message "Clear once the city's Gas City keeps a session's waits through an attach (gc-gspdoo) and a reset (gc-lwa1vp), built, verified and running."
  ```

  The operator clears it once the city's gc carries both changes, each past its
  "Done when", with no wait for upstream, and the armed unit then starts. No
  other unit waits on the gate, so units 1 and 2 build while Gas City builds its
  changes. The Debt entry in `docs/architecture.md` names both beads until
  unit 3 removes it.
- The review run reached main with tk-1tfzr71.22 (PR #1531, 713e3a733), so the
  effort's branch is brought current with main before unit 1 builds
  (`skills/work/integration-effort.md`, "Bring the effort's branch current"),
  which also brings main's rule that new pack code is written in Go, in gctk.
- A note on tk-1tfzr71.78, gc-toolkit's cutover: among the rig's first PRs on the
  new path, watch one stay through a round, from the promise and the hold to the
  return and the operator's settlement, with a visit to the sleeping sitting and
  a hand-over while another of its returns is pending among the round's events.
- A note on tk-35ob5gq, the city board's reading of a stay: the hold the landing
  order puts on at the end of a round is the conversation's existing edge, so the
  board reads it as it reads engage's.

## 15. Facts this design rests on

Gas City, at upstream main 76a06b2327:

- `gc session wait` needs at least one `--on-beads` and a `--note`, registers a
  wait for the session `$GC_SESSION_ID` names by default, and marks it ready at
  once when its beads have already closed (`cmdSessionWait` and `doSessionWait`
  in `cmd/gc/cmd_wait.go`). `--sleep` also sets the session's wait hold and pokes
  the controller to drain the session (`setSessionWaitHold`), and only when the
  wait is not ready at once.
- A wait is a bead of type `gate` labelled `gc:wait`, whose watched beads are its
  `dep_ids` metadata, not dependency edges (`CreateWait` in
  `internal/session/wait_store.go`).
- A ready wait wakes its session (the `wait-ready` reason in
  `cmd/gc/compute_awake_set.go`), whether it slept idle or under a wait hold, and
  is delivered as a queued nudge and then closed with the nudge's id
  (`CloseWaitFromNudge`). A cancelled wait reads `canceled` (`CancelWait`).
  The notice reads `Wait satisfied (<wait>): <note>`
  (`dispatchReadyWaitNudgesWithSnapshot`).
- A delivered or cancelled wait is a closed bead (`setWaitTerminalState`), so
  `gc wait list` lists only the waits still open, pending or ready (`ListWaits`
  and `WaitsForSession`), and `gc wait inspect <wait>` reads one wait in any
  state (`GetWait`), all in `internal/session/wait_store.go`.
- A manual session is wanted awake while ready or claimed work is assigned to
  it, and sleeps after its idle window while it is not attached and what is
  assigned to it only waits on something open. A wait hold keeps every
  demand-driven wake and the attached wake out (`compute_awake_set.go`).
- `Store.WakeSession` cancels every wait of its session and withdraws their
  queued notices (`wakeSessionFromBead`). Its callers are `gc session wake`
  (`doSessionWake`), an attach that starts a stopped session
  (`sessionAttach.attachOnceControllerStarts`), and the API's session wake.
  `Store.ResumeHeld`, the API's message resume, keeps waits and consumes only an
  operator's suspend.
- A wait registered before a fresh restart is cancelled as stale, with the
  reason `continuation-stale`, and a closed session's waits are cancelled
  (`prepareWaitWakeStateHooked` in `cmd/gc/cmd_wait.go`;
  `WaitInfo.ContinuationStale` in `internal/session/waits.go`).
  `gc session reset` asks for that restart through `SessionHandle.Reset`
  (`internal/worker/handle_lifecycle.go`) and `Manager.RequestFreshRestart`
  (`internal/session/manager.go`), which writes `continuation_reset_pending`
  and `restart_requested`. The start that consumes it moves the session to its
  next `continuation_epoch` (`cmd/gc/reconcile_effect_launch.go`). A wait
  registered while the reset is pending is marked `registered_reset_pending`
  (`CreateWait`), and belongs to, and is delivered in, the conversation the
  restart opens (`DeliveryEpoch` and `HeldForPendingReset`).
- The core reaper closes drained sessions older than a day
  (`gc session prune --state drained --before 24h` in
  `internal/bootstrap/packs/core/assets/scripts/reaper.sh`).
- `gc convoy create <name> <issues>` makes a convoy that tracks the issues, and
  Gas City closes a convoy with no `owned` label once its tracked beads close
  (`convoyStillAutocloses` in `cmd/gc/cmd_convoy.go`). A graph.v2 pour on a bead
  that is not a convoy mints a fresh one-item convoy that tracks it
  (`NormalizeInputConvoy` and `CreateSingleItemInputConvoy` in
  `internal/graphv2/invocation.go`).

bd, at beads v1.3.4:

- A `gh:pr` gate waits for its PR's merge (`cmd/bd/gate.go`), and nothing in bd or
  Gas City closes at a PR's readiness.
- bd keeps one edge from a bead onto another (`DependencyTypeConflictError`), and
  its cycle check walks only `blocks`, `conditional-blocks` and `parent-child`
  edges (`types.IsSchedulingEdge`).
- `bd dep remove` confirms the same way whether or not the edge was there
  (`cmd/bd/dep.go`), and a guarded `bd update` applies its guard and every change
  it carries, `--status` and `--append-notes` among them, as one update
  (`cmd/bd/update.go`).

GitHub, through its GraphQL API, read on 2026-11-16: no rig in the city has a
merge queue on its default branch (`repository.mergeQueue`, read for each rig
whose origin is on GitHub).

The pack, at main 713e3a733:

- The landing order marks a draft ready when `readyBar` finds nothing that keeps
  it a draft, without waiting for CI, on a five-minute cooldown
  (`services/gctk/pr/draft.go`, `decide` in `services/gctk/pr/landing.go`,
  `orders/pr-reconcile.toml`). It consults `readyBar` only for a draft, asks the
  evaluator directly about a PR that is ready, returns before both for a PR in
  its base's merge queue, and reads the bead once more before it requests a merge.
- The evaluator reads each open wait of the bead's own as a condition
  (`ownWaits`, `KindWait` in `services/gctk/pr/pr.go`). `prstatus` reads a PR held
  by a conversation its sitting stays in as `working`, and one held by any other
  conversation as `needs-attention` (`Render`; `Staying` and `Owed` in
  `services/gctk/prstatus/gates.go`).
- `heldBy` keeps every review run off a PR an open conversation holds unless the
  conversation stays, open under its sitting with a wait of its own holding it
  (`services/gctk/pr/admit.go`; `conversation.Staying` in
  `services/gctk/conversation/conversation.go`).
- A review run can pass with no push (`judge` in `services/gctk/review/passed.go`,
  `answeredAsks` in `services/gctk/review/result.go`, `cmd_push` in
  `assets/scripts/review-run.sh`).
- `converse-rework.sh` files a ruling on the pending record as an ask through
  `gctk review ask`, and `converse-signoff.sh --stay` makes a rework stay wait on
  that ask.
- A bead whose blocker is in another rig's store waits on a human gate in its
  own store that names the blocker, which a person clears once the blocker
  lands, because a `blocks` edge across two stores holds nothing
  (`skills/waits/SKILL.md`, "Make a bead wait on other work").
- A converse sitting is a manual session with `wake_mode = "resume"`,
  `sleep_after_idle = "10m"` and `idle_timeout = "0"`
  (`agents/converse-claude-opus/agent.toml` and its siblings).
- `converse-entry.sh` prints `fresh`, `interrupted`, `waiting`, `returned`,
  `none`, `stop` or `unreadable`, and reads a stay off its `staying:` lines and
  its own `blocks` edges. A claimed conversation whose newest line is `holding:`
  reads as a hold that stands.
- `gate-ensure.sh` and `rework-child.sh` are on the deletion plan with
  tk-1tfzr71.122 (`tools/deletion-plan.tsv`).
- A rig is on the new path once its `pending_through_merge` formula var is
  `true` (`refinery-land.sh`, `refinery-lib.sh`).
