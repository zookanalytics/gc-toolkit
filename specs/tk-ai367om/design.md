---
name: Design — a stay comes back when its work is ready for the operator's approval
description: The design for tk-ai367om, the design child of initiative tk-vrg93t0, read at main 5d4c3b4cf and integration/tk-1tfzr71.22 at 04d8dad0d against Gas City upstream main 8e7d91b583 and beads v1.3.4. It settles what each stay waits on, how the landing order keeps a PR a draft until a staying sitting's reading is on it and wakes the sitting through a Gas City session wait, the entry's ready answer and the return it starts, every later round, the stay on the conversation's own subject, what a stay does on a rig still on the old review path, the pages, the surface it adds and the units. Read it to approve the design at its gate, or to build one of its units.
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
  read, and posts one reading per head.
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
   - (b) It is marked ready at once, and the merge and the needs-review label
     wait for the reading. CI runs while the sitting reads, but GitHub shows the
     PR ready for review before the reading is on it, and the merge rule gains a
     condition that the label and both boards must render.
2. **When the reading finds that the work departs from what you agreed.**
   - (a) The sitting asks you, and the PR stays a draft until you answer. No
     approval you gave in an earlier round can merge the PR past the departure,
     but you answer the sitting before the PR can be approved and merged.
   - (b) The PR leaves draft with the reading on it, and your approval decides.
     You can approve without answering the sitting, but an approval you gave in
     an earlier round can merge the PR before you have read the departure.

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
| A rework of the PR under discussion | that PR's anchor, the conversation's subject | a `blocks` edge onto an open input convoy that tracks the anchor | at the readiness that ends the rework's round, at each later one, and when the anchor closes |
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

An anchor with no open input convoy, such as a change a sitting edited and
handed over through `work-submit.sh`, which slings nothing, leaves the rework
stay waiting on the ask, as tk-1tfzr71.128 built it. That stay comes back at the
run's `record`, a step before the readiness and still before the operator is
asked to approve. Its reading names the run's last head, which a later merge of
the target can follow. That residual is the only PR stay that does not come back
at readiness, and the sitting says so when it recommends staying.

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
the landing order keeps the PR a draft while a stay on its bead owes its reading,
and a draft cannot merge.

**The stays on a bead.** A stay on a bead B is a conversation, open or in
progress and assigned to its sitting's alias rather than to `human`, whose own
`blocks` edge reaches B directly or through an open input convoy that tracks B.
Such a convoy tracks B alone and carries no `owned` label, the rule
`subject_convoy` in `converse-signoff.sh` applies at PR #1515's head, because
Gas City closes such a convoy when B closes (`convoyStillAutocloses` in
`cmd/gc/cmd_convoy.go`). The order reads the stays from the store: B's
dependents through bd's edges (`bd dep list --direction=up`), the rows of those
that read as conversations (`conversation.IsCandidate`), and the dependents of
each such convoy among them. Nothing new is recorded for this: the edges are the
ones section 1's table writes. A conversation that tracks B and stays for other
work reaches B through no edge of its own, so it owes B nothing.

**A reading.** A reading is a comment on the PR, posted through
`pr-post.sh comment` like every post of the city, whose body opens with a marker
naming the conversation and the head it read:

```
<!-- gc:reading <conversation> <head> -->
```

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

**The hold.** `readyBar` gains one clause after the ones it has: the PR stays a
draft while a stay on its bead is open with no reading of its own at the PR's
head on the PR, or is in progress. A stay is in progress when its sitting holds
the conversation, which during a stay it does only to ask the operator something
(section 3, step 3, and the stopped-short recovery of `converse-stay`). The
order's outcome names the conversation and the head. Once every stay on the bead
is open with its reading at the head on the PR, the order marks the PR ready on
its next pass (`orders/pr-reconcile.toml`, every five minutes).

**What the operator sees while the sitting reads.** On GitHub, the PR is a draft.
Its `status:` label reads `working`, or `merging` when an approval from an
earlier round still stands on it and no conversation that stays holds its merge
(`Render`). `gctk pr status` names the sitting's reading at the head among the
conditions not met. The rig board renders the PR
from the same facts, with the reading as the city's work in flight, and the
conversation's own row as its stay. Once the reading is posted, the PR shows it,
the order marks the PR ready, CI runs, and the label turns to `needs-review`, or
to `merging` on a PR that an approval still stands on. A stay that holds for the
operator's answer reads as a person's move: the PR's label reads
`needs-attention`, held by that conversation.

**What the hold does not cover.**

- A person who marks the PR ready on GitHub themselves passes the hold, because
  the order changes the draft flag only from draft to ready, and a person's
  toggle is left for the cycle to finish (the review-lanes design, section 5).
- A stay whose sitting no wait can wake still stays, so it keeps the PR a draft,
  and the condition names it. That is a stay whose session has closed, whose
  return was cut short before it registered its wait again (section 3), or whose
  wait's note failed to reach it. The operator brings a sitting back by engaging
  the conversation, which runs the entry and the reading, or ends the stay by
  dismissing it. Gas City closes a session only when a person or a prune asks,
  and a hold that wedged silently would break the rule's other half, so the hold
  stands and names what clears it.

**Call 1 (b), if chosen.** The order marks the PR ready at once, and the
evaluator gains the same clause as a condition of the city's, which holds the
merge and keeps the label at `working` while CI runs. The stays, the reading and
the wake are the same, and the order then marks the waits ready as it marks the
PR ready, which is the review-lanes design's section 9 sentence as written.

## 3. The wake and the return

**The wake.** A stay also registers a Gas City session wait on each PR's bead it
watches, as its sign-off's last write. A sign-off cannot tell whether new work
will open a PR, so it registers one on each work bead the stay names:

```bash
gc session wait "$GC_SESSION_ID" --on-beads <the PR's bead> \
  --note "A PR this sitting stays for may wait for its reading: run converse-entry.sh."
```

The landing order marks such a wait ready (`gc wait ready <wait>`) on every pass
on which the PR would leave draft but for a stay's reading. It marks the waits of
each stay that owes its reading and waits open: those in state `pending` whose
`dep_ids` name the PR's bead and whose `session_id` is the stay's sitting
(`gc wait list --json`), the session `gc session list --json` lists with the
conversation's assignee as its `alias`. A wait another session registered on the
bead is left to turn ready when the bead closes. Gas City wakes the session for
a ready wait (the `wait-ready` reason in `cmd/gc/compute_awake_set.go`) and
delivers its note as a queued nudge, `Wait satisfied (<wait>): <note>`
(`dispatchReadyWaitNudgesWithSnapshot` in `cmd/gc/cmd_wait.go`). The prompt runs
the entry on that notice, as it does on the notice that a blocker closed. A wait
whose bead closes first is marked ready by Gas City itself, at the same moment
the conversation's wait in the store brings the sitting back.

This is the review-lanes design's section 9 wake, with one change of timing:
under call 1 (a) the order marks the waits ready while the reading is owed, and
the PR ready only after it. Marking them as it marks the PR ready, as section 9
words it, would ask the operator before the reading, which the rule rules out.

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
`WORK`, `AGREED`), a `ready` entry prints `READING=<the PR's bead> <the head> <the
PR's URL>` and `READ=<the head this conversation last read on that PR>`, or
`READ=none`. A `waiting` or `ready` entry also prints `WAIT=` with the open
session wait on each PR's bead the stay watches, or `missing`.

The entry asks gctk, which holds the hold's rule, rather than deciding the rule
itself: `gctk pr status <bead> --json` gains a `reading` key, `{"head": <oid>,
"owed": [<conversation>...], "held": [<conversation>...]}`, present while the PR
waits at its head for a stay. The entry reads `ready` when `owed` names its
conversation. It checks for `ready` after a stay that stopped short
(`interrupted`) and before `returned` and `waiting`.

**The return at `ready`.** `converse-stay`'s return gains a reading, in this
order:

1. **Register the wait again, then read the PR at the head `READING` names**, the
   head the refinery validated and the review run passed. The wake's wait closed
   once its note was delivered, so the return first registers each wait `WAIT`
   names as `missing`, and a return cut short while the conversation waits open
   is woken again by the order's next pass. When `READ` names an earlier head of
   the same PR, read the change since that head (`git diff <READ>..<head>`), with
   the review run's account of each head between them.
2. **Compare it with what was agreed**, `AGREED` and the thread, as the return
   compares today.
3. **Decide whether the comparison leaves the operator anything to answer before
   they approve.** When it does, claim the conversation back first, with the
   guarded write the hold's claim-back uses, so the PR stays a draft from before
   the reading lands until the operator answers (call 2, option a).
4. **Post the reading** through `pr-post.sh comment`, its body opening with the
   marker. When a comment with this conversation's marker at this head is on the
   PR already, as after a restart, edit it in place with `pr-post.sh edit`.
5. **Hold, or stay on.** Hold (`converse-hold`) when step 3 claimed the
   conversation. Otherwise record and post the hand-back, which says what the
   reading found and that the sitting comes back at the next readiness or when
   the work closes. A sitting that stays on lifts its conversation's hold on the
   PR's merge when it holds one, with the lift `converse-hold` gives a sitting
   that is helping the PR land, because that hold waited for this reading and
   the operator's approval now decides. Staying on writes nothing else: the
   conversation's wait in the store is unchanged, and the next entry registers
   the session wait again.

A restart between step 3 and step 5 finds the conversation in progress with its
reading still owed, or posted with no hold recorded. The entry reads either as a
return under way (`NEXT=converse-stay`), and the skill carries it on from what the
record and the PR show. The suite holds each case.

**The return at `returned`.** The work closed: its PR merged, or it closed without
one. The return reads how it closed. When the PR merged at a head this
conversation read, it says so in a line and signs off, with nothing left to
compare. Otherwise it compares as it does today. A sign-off that ends the stay
cancels the stay's open session waits (`gc wait cancel`), so no wait outlives its
conversation.

## 4. Every round

**When the sitting reads again.** Every readiness of the PR owes a reading from
each stay on its bead, whatever started the round: a send-back the operator ruled
through the sitting, an ask someone put on the PR, a repair after a failing
check, or a merge of the target. The rule puts the reading on the PR before the
operator is asked to approve, and they are asked about the head the round ends
at. A round's reading reads only the change since the head the conversation last
read, so a merge of the target that git made without help, or a one-line repair,
costs a short reading.

**No reading twice.** A reading is one comment per conversation and head, which
its marker names. `reading.owed` names a conversation only while no post of the
city's own with its marker at the head is on the PR, so a wake at a head the
sitting has already read reads `waiting`, and a return that restarts finds its
own comment and edits it.

**A send-back through the sitting.** On the review path, a ruling that sends the
PR back files an ask on the PR's bead with the checks it names, through
`converse-rework.sh` for the PR the conversation is about and through the `prs`
skill's `gctk review ask` for another PR, such as new work's. The sitting stays
again on the same work, with the same wait in the store. The ask holds the PR's
bead by its own edge, the next round's readiness owes the sitting its next
reading, and the operator's approval of an earlier round carries across it unless
triage rules the round material (the review-lanes design, section 4).

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
  with it. Its stay is refused before any write, and the sitting ends at the
  hand-off.

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
  built on its branch and not yet landed, and it stands for those rows until the
  rig's cutover.
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
  the wake and the reading (section 3), every round (section 4), the old path
  (section 6).
- **The converse prompt's "End or stay?"** (its decision 4): the sitting says when
  the stay would come back, by the table. It recommends staying when its reading
  will help the operator judge the result before they approve, and ending at the
  hand-off where the rig's path brings the stay back after the merge. Its table of
  entries gains `ready`, and it runs the entry on a `Wait satisfied` notice.
- **`converse-stay`**: the stay's session wait, `ready`, the return's reading,
  staying on, every round, and what ends the stay.
- **`converse-settle`**: the order of a sitting that sends its subject and stays
  (section 5), and that a stay on a PR's work keeps the PR a draft until its
  reading is on it.
- **`converse-hold`**: a hold after a reading keeps the PR a draft until the
  operator answers, and staying on after a reading lifts the conversation's hold
  on the PR's merge.
- **`docs/product-goals.md`** gains one sentence in its "Human gates and
  conversations" surface: a conversation the operator asks to stay with its work
  comes back before their next decision about that work, never after it, and for
  a PR its reading is on the PR before they are asked to approve. That is a
  promise about when a surface the operator watches reaches them, which the PM
  check judges a change to a stay against. Everything else stays in the pages
  above, because the file states goals and surfaces, not features.

tk-lv4r5mv writes these passages for the old path. The words unit waits for it to
land and rewrites them once (section 9).

## 8. The surface this adds

Each item's search is in [gas-city-search.md](gas-city-search.md).

- **`converse-signoff.sh --stay`**, an existing mode, gains: the session wait on
  each PR's bead it watches; `--waiting-on` naming the subject, through the
  subject dispatch's input convoy; the rework stay's wait on the review path,
  through the anchor's input convoy; and, in a sign-off that ends a stay, the
  cancel of the stay's waits.
- **`converse-entry.sh`** gains the `ready` entry with its `READING` and `READ`
  values, and `WAIT` on a `waiting` entry.
- **The landing order** (`gctk pr reconcile`) gains one clause in its ready
  transition and the wake, through its Gas City adapter
  (`services/gctk/internal/gascity`): `gc session list --json`,
  `gc wait list --json` and `gc wait ready`.
- **`gctk pr status --json`** gains the `reading` key, and `prstatus` gains the
  stays on a bead and their readings among the facts it renders.
- **A reading's marker** in the body of a PR comment.

None of it is a store, a lifecycle state, a bead kind or a metadata key. The
stays are read off the edges a stay already writes, the reading off the comment
the rule asks for, and the wake is Gas City's.

## 9. The units

Each unit lands on `integration/tk-vrg93t0`, keeps the suite green and leaves the
city working. On a rig still on the old path, nothing a unit adds runs but the
waits a stay registers, which nothing there marks ready.

| Unit | What it does | Waits on | Releases |
|---|---|---|---|
| 1. The reading rule, the hold and the wake | First, a probe in a scratch city: a session wait with no `--sleep` on a sleeping session, marked ready with `gc wait ready`, wakes the session and delivers its note, and an attach to the sleeping session cancels it. Then, in the pr domain: the stays on a bead, read from the store (section 2); each stay's reading at a head, read from the PR's comments by the marker; `readyBar`'s clause; in the landing order's pass, the wake through the Gas City adapter's `gc session list --json`, `gc wait list --json` and `gc wait ready`, which marks only the waits of the stays that owe their reading; `gctk pr status --json`'s `reading` key; `prstatus` renders a stay that owes its reading as the city's work and a stay in progress as a person's move. Tests, one per row of section 1's table: the hold and the wake for new work through a `blocks` edge, for a rework and for the subject through an open input convoy, nothing for a closed convoy or for a conversation that tracks the bead and stays for other work, and nothing for work with no PR; a stay in progress holds the draft and is not woken; every stay's reading at the head lets the PR leave draft; a reading at an earlier head does not; a person's toggle to ready is left alone; a wait already ready is not marked again; a wait another session registered on the bead is left alone; a store or GitHub read that fails leaves the draft and is retried. | tk-1tfzr71.22 | unit 2 |
| 2. The stay and the entry | `converse-signoff.sh --stay`: the session wait on each PR's bead; the subject's convoy wait and its refusals, from PR #1515's head with its open-convoy fix; the rework stay's convoy wait on a PR on the record, and the ask when the anchor has no open convoy; on the old path, the waits as they are; a sign-off that ends a stay cancels its waits. `converse-entry.sh`: `ready` with `READING` and `READ`, read from `gctk pr status --json`; `WAIT` on `waiting`; the restarts of section 3's return. Tests, one per row: what the sign-off writes for each, the entry's answer before, during and after a reading, a second wake at a head already read, a missing wait after an attach and at a `ready` wake, a return cut short after it registered its wait again, and a restart between each two steps of the return. | unit 1 | unit 3 |
| 3. The words | The converse prompt's "End or stay?" and its entry table, and its seven renders; `converse-stay`, `converse-settle` and `converse-hold` (section 7); `docs/human-engagement.md`; the sentence in `docs/product-goals.md`; the skill-needs pins of the table and of each example's call through the real parsers; `docs/architecture.md` where it describes the stay. | unit 2; tk-lv4r5mv | the landing |

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
- Unit 3 waits on tk-lv4r5mv, which rewrites the same passages for the old path.
- A note on tk-1tfzr71.78, gc-toolkit's cutover: among the rig's first PRs on the
  new path, watch one stay through a round, from the hold and the wake to the
  reading and the PR leaving draft.
- A note on tk-35ob5gq, the city board's reading of a stay: the city board reads a
  stay that owes its reading by the same facts, once unit 1 has added them.
- A note on tk-lv4r5mv: unit 3 rewrites its passages once the review path brings
  a PR stay back at readiness.

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
- A graph.v2 sling of a bead pours over a convoy that tracks that bead alone, and
  Gas City closes the convoy when the bead closes
  (`internal/graphv2/invocation.go`, `cmd/gc/cmd_convoy.go`).

bd, at beads v1.3.4:

- A `gh:pr` gate waits for its PR's merge (`cmd/bd/gate.go`), and nothing in bd or
  Gas City closes at a PR's readiness.
- bd keeps one edge from a bead onto another (`DependencyTypeConflictError`), and
  its cycle check walks only `blocks`, `conditional-blocks` and `parent-child`
  edges (`types.IsSchedulingEdge`).

The pack, at main 5d4c3b4cf and `integration/tk-1tfzr71.22` 04d8dad0d:

- The landing order marks a draft ready when `readyBar` finds nothing that keeps
  it a draft, without waiting for CI (`services/gctk/pr/draft.go`,
  `services/gctk/pr/landing.go`), on a five-minute cooldown
  (`orders/pr-reconcile.toml`).
- A conversation its sitting stays in keeps no review run off the branch
  (`heldBy` in `services/gctk/pr/admit.go`), and `prstatus` reads a stay that
  holds a PR as `working` (`Render`).
- A conversation on an open PR holds the PR's merge through the anchor's
  `blocks` edge onto it (`conversation_hold_merge` in `assets/scripts/gc-helm.sh`),
  and `converse-hold` lifts that edge for a sitting that is helping the PR land.
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
