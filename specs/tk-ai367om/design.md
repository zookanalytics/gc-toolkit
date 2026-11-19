---
name: Design — a stay comes back before your next decision about its work
description: Use when you approve the design of a staying sitting that comes back before the operator's next decision about its work (initiative tk-vrg93t0, design child tk-ai367om), or build one of its units. It gives the stay and its promise as the commands they run, the return gate that carries the promise and its one definition in gctk, when each stay comes back, the hold on the PR's merge, the return, every round, settling and a conversation that stays available, the conversation's own subject, visits and fresh contexts, a rig on the old review path, the pages, what the earlier revisions built, the surface and the units. It was read against the pack at integration/tk-vrg93t0 2a6fd322e, Gas City upstream main 17d7d77ce2 and beads v1.3.4.
---

# Design: a stay comes back before your next decision about its work

This is the design record for tk-ai367om, the design child of the initiative
tk-vrg93t0. It follows the brief the operator approved in conversation
tk-8e83do9 on 2026-11-16, recorded on tk-ai367om as "Proposed rework brief for
PR #1529", and the operator's ruling of 2026-11-18 in conversation tk-reymwh1,
recorded on tk-r06d403 and on the rewrite's bead tk-1gsaloy. That ruling has the
sitting come back through its own task, which waits on a gate of the pack's own
that the landing order closes, with no change to Gas City. The operator's words
in that conversation were "a task, especially if the normal approach, that is
blocked normally and cleared is great", and "As a gate in gc-toolkit, it should
be well defined, used everywhere appropriate, etc." The initiative's rule still
frames the design: a stay comes back at the operator's next decision about the
work, never after it.

The pack was read at integration/tk-vrg93t0 2a6fd322e, which carries main at
264fa89a9. Gas City is cited by symbol at `gastownhall/gascity` main
17d7d77ce2, and bd at beads v1.3.4. The search behind each piece of surface the
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

- **A stay comes back before your next decision about the work.** For work on
  a PR, whether it opens one or reworks the PR under discussion, your next
  decision is the approval, so the sitting comes back when the PR is ready for
  it, in every round. For work with no PR, it comes back when the work closes.
- **It comes back through its own task.** While the work is out, the sitting's
  conversation waits on a return gate for each piece of work, which stands for
  "this work is ready for your next decision". The landing order closes a
  work's gate when it marks the work's PR ready for your approval at the end of
  a review round, a rework's round included. bd then reads the conversation as
  ready work, and Gas City wakes the sitting with its thread, as it wakes a
  staying sitting today when its work closes.
- **The return gate is defined once, in gctk.** The definition says what the
  gate is, who files it, what closes it and when, and how each reader tells
  that the city closes it and no person does (section 2). It is the only gate
  kind of the pack's own.
- **The sitting always comes back to you.** It reads the result against what
  you agreed, posts what it found on the PR and in its hand-back, and waits to
  discuss it with you, even when it finds that the work matches. What it finds
  is advice, never one of the PR's checks.
- **The PR does not merge before that discussion.** At the end of a round, the
  landing order puts on the PR the hold a conversation already keeps on a PR it
  discusses, and then closes the gate. It marks the PR ready as it does today,
  so CI runs and GitHub requests your review while the sitting reads, usually a
  few minutes before what it found is on the PR. You release the merge by
  settling the exchange, and the conversation stays available until its subject
  closes. Leaving the terminal neither approves the work nor cancels the
  return. When the sitting stays on several pieces of work, it comes back once
  each of them is ready for your next decision or has closed. Each PR is held
  from the end of its own round, so a PR that is ready first waits, held, until
  the others are, unless you visit the sitting sooner.
- **A visit or a fresh context changes nothing.** Attaching to the sitting and
  resetting its context act on its session, and the return waits in the store,
  on the conversation and its gate. No Gas City change is needed.
- **On a rig still on the old review path**, a rework stay still comes back when
  the rework reaches the branch, and the sitting tells you that any other stay
  would come back only after the merge.

Your ruling of 2026-11-16 in conversation tk-8e83do9, recorded on tk-ai367om as
"Second operator rework ruling", settled that GitHub asks for your review at
once at the end of a round, and this design keeps it. The same ruling had a
visit and a fresh context keep the sitting's promise, which the previous
revision met by waiting for Gas City to change how an attach and a reset treat
a session's waits. Under the ruling of
2026-11-18 the promise waits in the store, which a visit and a fresh context
leave alone, so nothing waits for Gas City.

## 1. The stay, in commands

A stay runs these steps in this order:

1. **Agree and send the work, and promise what the sitting sends.** The sitting
   and the operator agree what the work must do, and the work is sent as it is
   today. The sitting slings new work or the subject before it signs off, and
   once it has sent a piece of work it promises that work's return through
   gctk:

   ```bash
   gctk gate return "$CONVERSATION" --on <the bead>
   ```

   A ruling that sends the PR under discussion back is sent by the sign-off
   itself, through `converse-rework.sh` (`--rework`), which on the review path
   files the ruling as an ask on the PR's bead.
2. **Stay, with the promise.** `converse-signoff.sh --stay` makes the stay in
   one call, in this order: it records what the operator agreed and carries out
   the send its ruling makes, then promises the return on the work that send
   reaches, through the same verb, then leaves the conversation open under its
   sitting. The conversation then waits on the return gate of each piece of
   work it stays for, and on each other bead of its work through a convoy that
   tracks it (section 3), so the sitting comes back once each of them has
   closed (section 2). Nothing is written once the stay has landed.
3. **Keep talking, or leave.** While the operator is attached, the sitting runs
   and answers them. Once they detach, Gas City sleeps it after its template's
   idle window (`sleep_after_idle`, ten minutes for the converse templates),
   because its conversation waits on an open bead.
4. **Come back.** At the end of a round on the PR, the landing order puts the
   hold on the PR and closes the gate on its bead (section 4). The conversation
   is then ready work assigned to the sitting, so Gas City wakes the sitting and
   resumes its thread (`wake_mode = "resume"`), and the prompt runs the entry,
   which reads `returned`. A sitting that is still up gets Gas City's notice
   that a blocker closed instead. The sitting holds the conversation for the
   operator, reads the result, compares it with what was agreed, posts what it
   found, and waits for the operator (section 5).
5. **The operator rules.** They can send the work back, and the sitting runs
   steps 1 and 2 again for the next round. They can settle the exchange, and
   the sitting releases the PR's merge and stays available (section 7). Or they
   end the conversation.

**Which beads the stay promises on.** Whoever sends a piece of work promises its
return as soon as the send is made, so the promise never depends on what the
work's record reads by the time the sign-off runs. That record cannot tell work
just sent from work whose exchange the operator settled: new work can open its
PR before the sign-off runs, or before a re-run of it, and its PR is then on the
record as a settled exchange's PR is. So the sitting promises each piece of
work it sends itself, after the send and before it signs off: new work and the
subject once it has slung them, and a PR other than the one under discussion
once the `prs` skill's `gctk review ask` has filed the ask. The sign-off
promises the work its own call sends: the PR its `--rework` sends back, and the
subject its `--accept` dispatches. A bead that already has the conversation's
open return gate, whoever filed it, keeps that gate: the sign-off files none
again and gives that bead no convoy wait. The sign-off promises nothing on any
other bead it waits on, such as work whose exchange the operator has settled
(section 7) or the subject once its work has closed, and it waits on that
work's close through a convoy. The sign-off refuses a stay on a PR whose merge
the conversation holds when no open return gate covers that PR, because the
stay would wait for a close the hold keeps from coming.

**A stay that stops partway.** The sign-off writes its first `staying:` line
before any other write, so a restart anywhere in the call reads a stay that
stopped short, and the stay's own re-run finishes it (`converse-stay`, "A stay
that stopped short"). The gates the sitting filed for the work it sent itself
are in the store before the call starts, so every attempt finds them, whatever
that work's PR reads by then. No step is left for the sitting to remember
later:

- **Before the send**, nothing has been sent, and the re-run makes the whole
  call.
- **After the send and before its gate**, the ask is open, or the subject is
  dispatched, and the conversation is still the sitting's claimed work, not a
  stay. The re-run finds the send recorded, sends nothing again, and files the
  gate. If the round ended meanwhile, the gate filed after it closes on the
  landing order's next pass, so the sitting comes back for that round then.
- **Inside a gate's create**, between the gate and its edge, the re-run of the
  verb, the sign-off's or the sitting's, files the gate again, and the landing
  order closes the one that nothing waits on (section 2).
- **After the gates and before the conversation is left open**, the re-run finds
  each open gate, files none again, and leaves the conversation open. A gate
  that closed meanwhile leaves the conversation ready once it is open, and the
  call ends by sending the sitting to its entry, which reads `returned`.

What each command does, and what a stay uses it for:

| Command | What it does | In a stay |
|---|---|---|
| `converse-signoff.sh --stay` | Writes everything a sign-off writes, the send its ruling makes among them, then promises the return on the work that send reaches through `gctk gate return`, then leaves the conversation open under its sitting, waiting on each bead's open return gate, the sitting's or its own, and on each other bead of its work through a convoy that tracks that bead. It refuses a stay on a PR whose merge the conversation holds when no open return gate covers that PR. | The stay, with its promise. |
| `gctk gate return <conversation> --on <bead>...` | Files the conversation's return gate on each bead, or finds that bead's open one. It first removes the conversation's `blocks` edges onto its closed return gates, so a return reads only the gates of its own stay, and as it files a bead's gate it removes the conversation's `blocks` edge onto a convoy that tracks that bead, which only a settled stay on that bead leaves. An open gate keeps the conversation's edge from its create, so nothing is promised again on a bead whose gate is still open. A wait anything else put on the conversation stays, such as a park, because `gc-helm.sh park` takes any open bead that is not in flight. | The promise: run by the sitting once it has sent a piece of work itself, and by the stay's sign-off after the send its own call makes. |
| `gctk pr reconcile`, the landing order | In each pass, puts the hold on a PR whose round has ended and then closes each return gate on the PR's bead. It also closes a return gate whose work has closed, or that no open or in-progress conversation waits on. It removes no edge (section 2). | What brings the sitting back. |
| `gc session attach <session>` | Attaches to a running session, or has the controller start one that is not running, with its thread. It changes neither the conversation nor its gate. | The way back in (section 9). |
| `gc session reset` | Restarts the session with a fresh thread, under the same alias and the same assigned work. It changes neither the conversation nor its gate. | A return handed to a fresh context (section 5). |
| `gc runtime drain-ack` | Lets the controller stop the session. The core reaper closes a drained session once it is a day old. | Never while staying, because a closed session leaves the return to a sitting with no thread. A sign-off that ends the conversation drains. |

**Why a promised bead has no convoy wait.** bd reads a bead as ready only once
every bead it waits on through a `blocks` edge has closed. A conversation that
waited on a bead's convoy and on its gate together would come back only once
that work had closed, after the decision the gate is for. So for each bead the
stay names, the conversation waits on one of them: on the bead's next decision
through its return gate, which the bead's close closes as well, or on the
bead's close through a convoy when the stay promises nothing on it. A convoy
wait that an earlier settled stay left on a bead the stay now promises on, as
when the operator sends back a PR they had settled, is removed by
`gctk gate return` as it files that bead's gate, before the sign-off leaves the
conversation open. Either wait is open work blocking the conversation its sitting is
assigned. That lets the sitting sleep, since blocked open assignments do not
prevent the idle sleep (`computeAwakeSet` in `cmd/gc/compute_awake_set.go`), and
it keeps the
conversation reading as a stay to the PR's status and the board
(`conversation.Staying` in `services/gctk/conversation/conversation.go`).

## 2. The return gate

The return gate is a bd gate of a kind the pack defines, and the only such kind.
Its definition is gctk's `gate` package (`services/gctk/gate`). The package sits
outside `internal` so the helm board, a separate module, can import it, as it
imports `waits`. It holds the kind's await type, the rule that says who closes a
gate of each await type, the human-gate rule, the gate's filing and its close.
The verb and the
landing order call it, and nothing else writes the gate. A
later gate kind of the pack's would be defined in the same package.

- **What it is.** A bead of issue type `gate`, whose await type is
  `stay-return` and whose await id is the bead of the work it watches. bd's
  help gives the await id as the "Condition identifier (run ID, PR number,
  etc.)", the thing a gate waits on. It stands for "the operator's next
  decision about this work is due". The conversation it returns to is the bead
  that waits on it, through the conversation's own `blocks` edge onto it. Its
  title names the work and the moment in the operator's words, because the
  board shows it as what the conversation waits on, and its description names
  the definition.
- **Who files it.** Whoever sends the work, through `gctk gate return`, once the
  send is made: the sitting for each piece of work it sends itself, before it
  signs off, and the stay's sign-off for the work its own call sends, before it
  leaves the conversation open (section 1). The verb files each gate with one
  command:

  ```bash
  bd gate create --type stay-return --await-id <the bead> --blocks <the conversation>
  ```

  A conversation has at most one open return gate on each bead. The verb finds
  that gate among the gates that block the conversation, which
  `bd gate list <conversation> --limit 0` lists with each one's await type and
  await id, or files one. The verb refuses a conversation that is neither open nor in
  progress under the caller's alias, since the sitting runs it while it holds
  the conversation, a bead in another store, a bead that has closed, and a store
  the landing order does not read: the city's own, and a rig still on the old
  review path (section 10).
- **One command, two writes in this city.** bd writes the gate and the
  conversation's edge onto it in one transaction only on a proxied server
  (`runGateCreateProxiedServer` in beads `cmd/bd/gate_proxied_server.go`). The
  city's stores run bd against a Dolt server (`dolt_mode` `server` in each
  store's `.beads/metadata.json`), where `gateCreateCmd` creates the gate, then
  adds the edge, then commits. A create that stops between the two leaves an
  open return gate that nothing waits on. The verb's own re-run finds no gate
  the conversation waits on for that bead, so it files one, and the landing
  order closes the gate that nothing waits on (below).
- **What closes it, and when.** The landing order alone, in each pass
  (section 4):
  - at the end of a review round on its bead's PR, once that PR carries the
    hold of the conversation the gate returns to, when that conversation is
    open or in progress, with a close reason that names the bead and the head;
  - once its bead has closed, with a reason that names the bead;
  - once no conversation that is open or in progress waits on it, as after the
    operator ends the conversation, or after a create that stopped before its
    edge. A gate that nothing waits on closes only once it is five minutes old,
    the order's cooldown, so a pass never closes a gate whose edge bd is still
    writing.

  The landing order reads every open gate with `bd gate list --limit 0`, each
  with its await type and await id. bd lists 50 gates unless `--limit` says
  otherwise, so a bare read could leave a return gate out of every pass while
  the store holds more open gates than that. A gate's bead is its await id,
  and its conversation is the bead that waits on it through a `blocks` edge,
  its dependent (`bd dep list <gate> --direction=up --type blocks`).

  bd's gate check and Gas City's gate sweep leave it alone. bd evaluates only
  the await types it knows, `gh:run`, `gh:pr`, `timer` and `bead`, and passes
  over every other (`evaluateGates` in beads `cmd/bd/gate.go`). Gas City's core
  sweep checks only timer and GitHub gates (`gate-sweep.sh` in the core pack's
  scripts). So the landing order is the gate's only closer.
- **Several gates, one return.** bd reads the conversation as ready only once
  everything it waits on through a `blocks` edge has closed. So a conversation
  that waits on several return gates comes back once each of them has closed:
  every piece of work it stays for is ready for the operator's next decision,
  or has closed. The landing order removes no edge. Each bead whose round ends
  gets the conversation's hold then, and its gate closes (section 4), so a PR
  that is ready first stays held until the sitting comes back for it.
- **How a reader tells that the city closes it.** The definition answers, for a
  gate's await type, whether the city or a person closes it. The city closes a
  timer, `gh:run` or `gh:pr` gate through Gas City's sweep, and a return gate
  through the landing order. A person closes every other gate: a human gate, a
  park, which carries no await type, and a gate of any type nothing closes. A
  human gate, the one whose await type is `human`, is also a question a person
  answers. The readers:
  - The main board's `heldByPerson` (`services/helm/internal/board/state.go`)
    counts every gate that `sweptGate` does not list as a person's, so it would
    read a conversation that waits on its return gate as parked. It reads who
    closes a gate from the definition, so the conversation reads as queued,
    waiting on its work, as a stay reads today.
  - The rig board's `gateHold` and `parked` (`services/helm/internal/rigboard`)
    read every gate that is not a human gate as a park, and they read the
    definition the same way.
  - The human-gate rule's Go readers, `prstatus.IsHumanGate`, which the rig board
    and the PR's status use, and `isHumanGate` in `services/gctk/pr/admit.go`,
    read the rule from the definition. They count only a human gate, so their
    answers do not change. The scripts keep `human_gate` in
    `assets/scripts/bd-lib.sh`, their one rule for a human gate, which also
    counts only a human gate.
  - `converse-entry.sh` reads a stay as `waiting` while its conversation waits
    on an open return gate, and as `returned` once a gate it waits on has
    closed and it waits on nothing open (section 5). It finds the gates with
    `bd gate list <conversation> --all --limit 0`, the gates that block the
    conversation,
    and each gate's bead by its await id.
  - No doctor check reads the gate as anything but a gate.
    `check-wait-is-an-edge` exempts every gate (`terminal_wait_type` in
    `lifecycle/lifecycle.toml`), and `check-blocked-work-armed` reads only
    unassigned beads, which a staying conversation is not.
  - The board reads the store directly unless that read fails its startup probe,
    and then reads the supervisor's API, whose beads carry no await type
    (`apiBead` in `services/helm/internal/source/supervisor.go`). On that
    fallback a conversation waiting on its return gate reads as parked, as
    every gate does there.
- **What else the pack files is not of this kind.** The park gate that
  `gc-helm.sh park` files carries no await type, and a person closes it: the
  verb's help says that closing the gate releases the park, and the board counts
  it as a person's. Every closer in the pack closes a human gate only: the
  retractions through `human-gate.sh --retract`, the sign-off's answers, an
  Accept, a stand-down, `pr-facts.sh`'s withdrawals, and `bead-rehome.sh`'s
  withdrawal of the gates that asked for a close it retries. So the pack files no
  gate today that the city closes, and nothing moves onto this definition.

## 3. When each stay comes back

On a rig that has moved onto the review run, each stay comes back as this table
gives. Section 10 gives a rig still on the old review path.

| The ruling sends | The stay waits on a return gate on | It comes back |
|---|---|---|
| New work that opens its own PR | the work's bead | at the end of each round on its PR, and when the work closes |
| A rework of the PR under discussion | the PR's anchor | at the end of the round the rework starts, and of each later round the operator rules |
| The conversation's own subject | the subject | at the end of each round on the subject's PR, and when the subject closes |
| Work that opens no PR | the work's bead | when the work closes |

A stay that follows a settled exchange promises nothing on that work, and waits
on its close through an open convoy that tracks it (section 7).

**The moment a PR is ready for the operator's approval.** A round ends when the
record is pending at the PR's head, which is the head the refinery validated,
a passed result of the review run names that head and the PR's target, no
review run is attached to the bead, and no ask a run can take is open on it.
These are the conditions of `readyBar` (`services/gctk/pr/draft.go`) other than
the draft flag. On a draft, the round ends on the pass that marks it ready
(`decide` in `services/gctk/pr/landing.go`). On a PR that is ready already, as
after a send-back the run answers with no push, it ends on the pass that finds
those conditions met at the head the PR was ready at. The landing order closes
a return gate that watches the PR's bead at that moment, and no bead's close
marks the moment:

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
  promised result, so the old path's rework stay waits on it (section 10).

**Why neither wait is an edge onto the work.** The hold of section 4 is the PR's bead's `blocks` edge onto the conversation, and bd
refuses an edge from the conversation onto that bead while the hold stands,
because its cycle check walks `blocks`, `conditional-blocks` and `parent-child`
edges (`types.IsSchedulingEdge`, beads `internal/types/types.go`). A stay on
the conversation's own subject has a second reason: the conversation tracks the
subject, and bd keeps one edge from a bead onto another
(`DependencyTypeConflictError`), so the conversation cannot wait on its subject
at all. Neither the convoy nor the gate meets either rule. The convoy reaches
the work through a `tracks` edge, which the cycle check does not walk, and the
gate names it by its await id, which is no edge at all. Gas City closes
the convoy once the work closes, because it tracks that bead alone and carries
no `owned` label (`convoyStillAutocloses` in `cmd/gc/cmd_convoy.go`), and the
landing order closes the gate.

A graph.v2 sling of the work pours over such a convoy, and so does each review
run, which the landing order pours with
`gc formula cook mol-pr-review --attach <bead>` (`runs.Pour` in
`services/gctk/internal/cli/prland.go`). Gas City mints a fresh one-item convoy
for each such pour (`NormalizeInputConvoy` and `CreateSingleItemInputConvoy` in
`internal/graphv2/invocation.go`). On a bead it promises nothing on, the
sign-off waits on the newest open one, the rule `subject_convoy` applies in
`converse-signoff.sh` at PR #1515's head.
When none is open, as for a change handed over through `work-submit.sh`, a raw
route or a PR whose first review run has not poured, it makes one with
`gc convoy create <name> <bead>`.

**Several works.** A stay names every bead it waits on. It promises the return
on each bead whose decision it is staying for (section 1), and each of those beads
has a return gate of its own. The conversation waits on all of them, so the
sitting comes back once each is ready for the operator's next decision or has
closed (section 2). A bead whose round ends first is held from that end, and
its PR waits, held, until the sitting comes back for the rest, unless the
operator visits the sitting sooner (sections 4 and 9). When the sitting stays
again, a bead whose gate is still open keeps it, and nothing is promised again
on it. Once it stays with no return promised, it comes back when the last of
its work has closed.

**Another store.** A stay still waits only on work in its conversation's own
store, because an edge onto another store's bead holds nothing, so the sign-off
keeps refusing that stay, and the sitting ends at the hand-off.

## 4. The hold: the PR waits for the discussion

**The hold is the one a conversation already keeps.** A conversation on an open
PR holds its merge through the anchor's `blocks` edge onto the conversation
(`conversation_hold_merge` in `assets/scripts/gc-helm.sh`; "A conversation on an
open PR holds its merge" in `docs/human-engagement.md`). The evaluator reads
that edge as a wait of the bead's own (`ownWaits` and `KindWait` in
`services/gctk/pr/pr.go`). It holds only the merge: the landing order keeps a
review run off a PR only for an open human gate (`heldBy` in
`services/gctk/pr/admit.go`), so the PR's review runs go on.

**The landing order puts it on at the end of a round, and then closes the
gate.** In each pass, for a PR's bead whose round has ended (section 3), the
landing order reads the open return gates whose await id is the bead. For each
gate, it writes
the PR's bead's `blocks` edge onto the conversation the gate returns to, when
that conversation is open or in progress, and then it closes the gate. It does
both before it marks a draft ready or asks the evaluator about a PR that is
ready, so the pass that ends the round requests no merge.

- An edge already there, as engage writes it for the conversation's own
  subject, is a no-op.
- A read or a write that fails leaves the gate open, and the next pass tries
  again.
- A conversation that has closed gets no hold.

The same pass closes each open return gate whose bead has closed, or that no
open or in-progress conversation waits on (section 2).

**Nothing needs it before the round ends.** Before then the PR is not at the
decision the return is for, and the evaluator reads it ready only once the
review run has passed at the head the refinery validated with nothing on the
bead left to wait on (`Ready` in `services/gctk/pr/pr.go`).

**Only the operator's settlement lifts it.** The sitting lifts the hold only on
the operator's ruling that settles the returned exchange, with the lift
`converse-hold` gives a sitting (`gc bd dep remove <bead> <conversation>`). It
never lifts the hold because it found nothing to ask. A sign-off that ends the
conversation releases the hold with the close, as every close does.

**What the operator sees.** Once the last gate the conversation waits on has
closed, the conversation is open under its sitting with no wait of its own, so
it is the operator's move. The
PR's `status:` label reads `needs-attention`, held by that conversation
(`Render` in `services/gctk/prstatus/render.go`; `Staying` and `Owed` in
`gates.go`), and the board shows the conversation's latest hand-back until the
sitting posts its new one, usually within a minute or two. By then the PR is ready for review, so
GitHub has requested the operator's review and CI has run on its head. Once the
operator settles and the sitting lifts the hold, the label follows the PR's own
conditions again.

**While one PR is ready and another piece of work is out.** The ready PR is held,
and its `status:` label reads `working`: the conversation that holds it still
waits on the other piece's open gate, so it is a conversation whose sitting
stays for work, which the label counts as the city's (`Facts.Staying` in
`services/gctk/prstatus/gates.go`, and `Render`). GitHub has requested the
operator's review and CI has run on its head, because the landing order marked
it ready at the end of its round. The PR waits, held, until the sitting comes
back for the rest of the work. An operator who wants it discussed sooner visits
the sitting (section 9).

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
- **A sitting whose session has closed.** The gate still closes at the end of
  the round and the hold still goes on, so the PR waits, reading
  `needs-attention` and held by the conversation, which the board lists as the
  operator's. Gas City wakes no session that has closed, so the return starts
  once the operator engages the conversation and a sitting takes it up from the
  record.
- **The minutes between the end of a round and the sitting's post.** The PR is
  held and reads `needs-attention` before the sitting has posted what it found.

## 5. The return

The sitting takes the return up when its entry reads `returned`, in this order:

1. **Read why it is back.** The entry reads `returned` once a return gate the
   conversation waits on has closed and the conversation waits on nothing
   open. Each closed gate's close reason names its bead and the moment: the end
   of a round at a head, or the bead's close. The reason is in the record, so
   the sitting needs no notice to trust.
2. **Record what the operator owes, first.** The PR's merge is already held
   when the sitting wakes: the landing order wrote the conversation's hold on
   the PR before it closed the gate (section 4), and the PR stays held if the
   sitting never wakes. What the sitting records here is the conversation's own
   record of what the operator owes, its `holding:` line, which a restart
   reads. The line holds no merge. The entry has already claimed the
   conversation: it runs `gc hook --claim` before it reads the stay, so a
   conversation it reads as `returned` is in progress under the sitting. The
   sitting records the line in one write guarded on that claim:

   ```bash
   gc bd update "$CONVERSATION" --if-assignee "$GC_ALIAS" --if-status in_progress \
     --append-notes "holding: <what the operator owes>"
   ```

   bd applies the guard and the line as one update, and a guard that does not
   match writes nothing and exits 13 (`cmd/bd/update.go`), as when the operator
   ended the conversation meanwhile. The sitting then records no line, and says
   in the thread what stopped it. `converse-stay`'s claim-back, guarded on
   `open`, is for a stay that stopped short: on a return it finds the
   conversation claimed and writes nothing. Once the line is recorded, the
   conversation is the operator's move, and a restart reads the line that
   stands (`converse-entry.sh`, `interrupted`, with `converse-continue`).
3. **Read the result** at the PR's head, which is the head the round ended at,
   with the change since the head the sitting last read and the review run's
   account of each round between.
4. **Compare it with what was agreed**, the thread and `AGREED`, as the return
   compares today.
5. **Post what it found** on the PR through `pr-post.sh comment` and in its
   hand-back: where the work matches what was agreed and where it departs, as
   advice. When it finds that the work matches, it says so.
6. **Wait for the operator.** The hold stands until they rule.

**A return cut short.** A restart after step 2 reads the `holding:` line that
stands, and the sitting carries the return on from its thread, or from the
record when the thread is gone: that line and what it has already posted on the
PR. A
restart before step 2 reads `returned` again, because the closed gate stays in
the store.

**A return handed to a fresh context.** When the sitting's context runs low
during the return, it hands the return over as `converse-stay` gives ("When your
context runs low during the return") and runs `gc session reset`. The
conversation and its gate stay as they were, and the fresh thread finishes the
return from the hand-over.

**The return at the work's close.** When the work closes, merged or closed
without a PR, its return gate closes on the landing order's next pass, or the
convoy closes at once when no return was promised, and the entry reads
`returned`. The sitting reads how the work closed. When the PR merged at a head
it already discussed with the operator, it says so in a line. Otherwise it reads
and compares as above. Then it ends the conversation if the subject has closed,
and otherwise stays available (section 7).

## 6. Every round

**A send-back through the sitting.** The operator's ruling sends the PR back: an
ask on the PR's bead through `converse-rework.sh` for the PR under discussion,
or `gctk review ask` through the `prs` skill for another PR such as new work's.
The sitting stays again, and the stay files the ask before the gate: the
sign-off sends the ask with `--rework` and then files the gate, and for another
PR the sitting files the ask through the `prs` skill and runs
`gctk gate return` before it signs off. So the round has not ended when the gate
is filed, and the hold stays on the PR. The round ends whether or not the
review run pushes:

- **The run pushes a fix.** Its push returns the PR to draft, and the round ends
  at the new head, as any round does.
- **The run declines, defers or answers the ask.** Its pass rule counts such an
  ask as ruled (`judge` in `services/gctk/review/passed.go`), its `record` closes
  the ask as a no-op (`answeredAsks` in `services/gctk/review/result.go`), and
  its push step, with nothing to push, returns before it would return the PR to
  draft (`cmd_push` in `assets/scripts/review-run.sh`). The round ends at the
  head the PR was ready at, and the landing order finds it over on the PR that is
  ready already.

Either way the gate promised for this round is open when the round ends, so the
sitting comes back. An approval the operator gave in an earlier round cannot
merge the PR meanwhile, because the hold stands.

**A round the city starts by itself**, such as a repair after a failing check or
a merge of the target, ends once, at the head the city leaves. A gate promised
before it closes at that end.

**One return per promise.** A gate closes once, so each promise brings the
sitting back once, and each round the operator rules is a promise of its own.
Nothing records which head a return read, because no rule waits on that record.

## 7. Settling, and a conversation that stays available

**Settling.** The operator rules that the returned exchange is settled, for
example that the work may merge. The sitting lifts the hold, records the ruling,
and stays on with no promise for that work: it signs off with `--stay` on the
same work with a ruling that leaves its PR standing (`--no-rework`). Nothing
sends that work again, so nothing promises its return: the sign-off files no
return gate on it, and its conversation waits on the work's close through a
convoy. A bead of the stay whose return gate is still
open keeps it: the conversation goes on waiting on that gate, and nothing is
promised again on it (section 3). The conversation is open under its sitting
again, the sitting
sleeps, and nothing holds the settled work's PR for it.

**Available until the subject closes.** The operator can come back to the
conversation at any time by attaching, and nothing in the sitting's absence
approves or cancels anything. When the work closes, the sitting comes back
(`returned`), says how the work closed, and ends the conversation if the subject
has closed. While the subject is still open, it stays on the subject instead, a
stay that waits through a convoy that tracks the subject, again with no
promise. So the conversation stays available until its subject closes.

**Ending.** The operator can end the conversation at any time. The sign-off
without `--stay` closes the conversation and releases its holds with the close,
and the landing order closes the conversation's open return gates on its next
pass, since the conversation they return to has closed. A ruling that settles a
discussion-only subject and closes it ends the conversation the same way, as
today.

## 8. The conversation's own subject

PR #1515 (its head 6ffdc541f, which `refs/pull/1515/head` keeps) let a sitting
stay when its ruling sends its own subject, by waiting on the input convoy the
subject's dispatch pours, and came back after the merge. What holds from it:

- **The wait in the store** is the subject's return gate, or, once the
  operator has settled the subject's exchange, a convoy that tracks the
  subject (section 3).
- **An open convoy only.** A convoy closed by hand, or one that has closed, is no
  wait. PR #1515's correctness round made the entry count only an open convoy
  (finding tk-xvjd1u7, fixed at 275cbf44b), and the build keeps that.
- **The order of the writes.** The sitting sends the subject first and
  promises it, then signs off with the stay, which finds the subject's gate and
  then leaves the conversation open. A ruling that takes the subject's
  recommendation (`--accept`) sends the subject inside the sign-off, which then
  files the subject's gate itself.
- **The subject waits on nothing of its own convoy.** A `blocks` edge from the
  subject onto a convoy that tracks it would hold the subject's own work and its
  close, so the sign-off writes the conversation's wait alone.

What changes is when the sitting comes back: at the end of each round on the
subject's PR, not after the merge. The sign-off takes a stay on the subject on
either path, since neither its return gate, which names the subject by its
await id, nor a convoy is an edge onto the subject. A stay on the PR under
discussion is the same case on the review path, so there the sign-off stops
refusing a stay on the PR whose merge the conversation holds once a return gate
covers that PR, because the stay comes back before that merge. On the old path
it keeps refusing that stay (section 10).

## 9. Visits and fresh contexts while the work is out

Attaching to the sitting and resetting its context act on its session. The
return waits in the store, on the conversation's edges onto its return gates,
and neither one changes the conversation or its gates.

- **A visit while the sitting runs**, with the operator's tab still attached or
  within the idle window: `gc session attach` attaches and changes nothing. The
  sitting answers the operator through the sign-off's `--answer` while the work
  is out, as `converse-stay` has it.
- **A visit to a sleeping sitting** has the controller start the session with
  its thread. Gas City cancels the session's waits as it starts it
  (`Store.WakeSession` in `internal/session/wait_store.go`), and a staying sitting
  has none. The claim answers `drain`, the entry reads `waiting`, which keeps
  the sitting, and the sitting sleeps again once the tab detaches, as it does
  today.
- **A fresh context.** `gc session reset` restarts the session with a fresh
  thread under the same alias and the same assigned work. The conversation
  still waits on its gate, and the fresh thread's entry reads `waiting` or
  `returned` from the store.
- **A visit while one piece of work is ready and another is out.** The entry
  reads `waiting`, because the conversation still waits on the other piece's
  gate. The operator can discuss the ready piece now: the sitting reads it and
  compares it with what was agreed as on a return (section 5), and its PR is
  held already. When the operator rules, the sitting signs off on that ruling
  as on any other. A send-back promises the bead's next round, and a
  settlement lifts its hold. When the operator only wants to wait for the rest,
  a stay again names only the work still out, whose gates stay open. It writes
  nothing for a bead whose gate has closed and whose PR the conversation still
  holds: the conversation never waits on the close of a PR whose merge it
  holds, so that PR stays held, and the sitting discusses it again when it
  comes back for the rest.

So the return needs no change to Gas City. The previous revision promised the
return with a Gas City session wait, which needed Gas City to change in these
places: an attach that starts a sleeping session cancels its waits
(gc-gspdoo), a reset cancels them as stale (gc-lwa1vp), and a ready wait does
not wake a session that slept at the end of its idle window (gc-qxq03t, found by
unit 1's probe and recorded on tk-u41ko5k). The attach fix stays filed in the
Gas City rig as a bug in its own right, and this effort waits on none of them
(conversation tk-reymwh1).

## 10. A rig still on the old review path

The end of a round is read only by the landing order, which a rig's PRs reach
once its cutover sets `pending_through_merge` and moves its open beads onto the
record (`refinery-land.sh`; gc-toolkit cut over with tk-1tfzr71.78). On the old path no
order reads it, so a stay promises no return there: the sign-off files no gate
on such a rig, and the promise's verb refuses one (section 2). Until a rig cuts
over:

- **A rework stay** waits on its rework child, through a convoy as every stay
  that promises nothing does, so it comes back when the rework reaches the PR's branch, before the
  approval. The conversation's hold on the anchor, which engage writes, holds the
  merge until the operator settles the return.
- **A stay on new work or on the conversation's own subject** would come back
  after its PR merges. The sitting says so and recommends ending at the
  hand-off, with what was agreed written into the work's brief in full, which is
  tk-lv4r5mv's rule on main.
- **A stay on the PR whose merge the conversation holds** stays refused, because
  it would wait for that merge while the conversation holds it, and nothing
  would bring the sitting back before it.
- **How the sign-off and the sitting tell the path.** A PR's bead whose merge result is on the
  record is on the new path (`pr.OnRecord`, which `gctk pr status` reads). For
  work with no PR yet, the rig's switch tells it, read as `refinery-lib.sh` reads
  the rig's formula vars (`gc formula show mol-refinery-patrol --rig <rig> --json`,
  the var `pending_through_merge`). The promise's verb reads the rig's switch the
  same way before it files a gate.

`gate-ensure.sh` and `rework-child.sh` are on the deletion plan with
tk-1tfzr71.122 (`tools/deletion-plan.tsv`), so neither gets new work.

## 11. What the pack's pages say

Each page and skill that describes a stay states the rule and when each stay
comes back, by section 3's table, with the old path's rows until a rig cuts
over:

- **`docs/human-engagement.md`**, its section "A sitting that stays for the
  return": the stay's commands (section 1), the return gate (section 2), when it
  comes back (section 3), the hold and what the operator sees (section 4), the
  return (section 5), every round (section 6), settling and availability
  (section 7), visits and fresh contexts (section 9) and the old path
  (section 10).
- **The converse prompt's "End or stay?"** (its decision 4): the sitting says when
  the stay would come back, by the table, and that it will come back to discuss
  the result whatever it finds. On an entry that reads `returned`, the prompt
  runs the return (`converse-stay`).
- **`converse-stay`**: the stay and its promise, the sitting's own
  `gctk gate return` once it has sent a piece of work itself or sent a PR back
  through the `prs` skill, a stay that stopped short and its re-run, the
  return's steps with the record of
  what the operator owes first, a return cut short, a return handed to a fresh
  context, several works, which come back
  together once each is ready or has closed, settling, staying available,
  visits, among them one that discusses a piece of work ready before the rest,
  and ending.
- **`converse-settle`**: send, then the promise of each piece of work the
  sitting sent, then the stay, which files the gate of the work its own call
  sends before it leaves the conversation open, and a stay on the
  conversation's own subject (section 8).
- **`converse-hold`**: the hold of a returned exchange, recorded in one write
  guarded on the claim the entry took (section 5), and the lift of the PR's
  merge hold only on the operator's settlement.
- **`docs/product-goals.md`** gains one sentence in its "Human gates and
  conversations" surface: a conversation the operator asks to stay with its work
  comes back to discuss it before their next decision about that work, never
  after it. That promise is about when a surface the operator watches reaches
  them, so it is a goal the PM check judges a change to a stay against.

The words unit rewrites the passages tk-lv4r5mv wrote for the old path once, on
the effort's branch brought current with main (sections 14 and 15).

This design's own change states the rule in `docs/architecture.md` at the
document's altitude. Its "How humans engage" says when a stay comes back, that
it comes back through its own task, which waits in the store on a return gate
while Gas City sleeps the sitting, that the landing order holds the PR's merge
and releases the return at the end of a round, that a visit and a fresh context
leave the return alone, that the return always waits for the operator, what
holds the PR until the operator settles, and that the conversation stays
available until its subject closes. The gate's package, its closes and how the
wake reaches the sitting are how the parts carry the return out, so they stay
in this design.
Its Debt names the stay that comes back only when its work closes, with
tk-vrg93t0 as the work that retires it, and the words unit narrows that entry to
the rigs still on the old review path. The gate's close is a close, so step 9 of
"How work moves" keeps `closed` as the one signal waiting parties key on, and
`docs/lifecycle-composition.md` needs no change.

## 12. What the earlier revisions built, and what this keeps

The first draft kept the PR a draft until the sitting posted a marked reading,
and released the hold itself when the reading found nothing to ask. The previous
revision dropped that machinery, had the return always wait for the operator,
and promised the return with a Gas City session wait. Each piece was weighed
for whether this design still needs it:

- **The reading's marker, and the stay's round counted from its lines**:
  dropped. No rule waits on a posted reading, and each round the operator rules
  is a promise of its own, which brings the sitting back once.
- **`gctk pr status`'s `reading` key and its owed and held lists**: dropped. The
  landing order reads the return gates themselves.
- **The evaluator's condition for a stay**: dropped. The hold is the
  conversation's existing edge, which the evaluator already reads as a wait.
- **The clause that kept the PR a draft for the reading**: dropped. The operator
  ruled that GitHub asks for review at once at the end of a round, so no draft
  rule is kept.
- **The move onto the first review run's convoy**: dropped. A rework stay on the
  review path waits through a convoy that tracks the anchor from its sign-off,
  one the sign-off makes when no run has poured one.
- **The entry's `ready` and its `READING`, `READ`, `WAIT` and `MOVE` values**:
  dropped. The gate's close reason says why the sitting woke.
- **The clean return's lift of the merge hold**: dropped. Only the operator's
  settlement lifts it.
- **The session wait as the promise**, with the landing order's `gc wait ready`,
  its reads of `gc wait list` and `gc session list`, the sitting's check of a
  `Wait satisfied` notice with `gc wait inspect`, its registration of a promise
  again on an entry, and its hand-over of other promises through a reset:
  dropped. The return gate carries the promise in the store, where only its
  closer changes it.
- **The Gas City prerequisite** (gc-gspdoo and gc-lwa1vp) and the human gate on
  unit 3 that stood for it: dropped. The ruling of 2026-11-18 answered that gate
  and the one on unit 1.
- **Kept**: the hold put on at the end of a round before the sitting wakes; the
  convoy wait from PR #1515, for a stay that promises nothing on its work; the
  narrowing to the stays' own conversations; the
  merge-queue boundary; and the old path's rows.

## 13. The surface this adds

Each item's search is in [gas-city-search.md](gas-city-search.md).

- **The return gate**, a bead kind of the pack's own: a bd gate whose await type
  is `stay-return`, defined in `services/gctk/gate` (section 2). It adds no
  metadata key, because its await type, its await id and its edges are bd's own
  fields. As a pack noun it needs a warrant (`docs/foundation.md`,
  "Boundaries"), which unit 1 adds to `docs/warrants.md` with the gate. The
  warrant names Gas City's session wait as the primitive the gate stands in
  for: Gas City calls its durable waits the closest platform concept to a gate,
  and its session wait cannot hold the promise today. Its evidence is the
  search's section on the promise. It retires when Gas City's session wait
  keeps a promise through an attach and a reset and wakes a sitting that slept
  at the end of its idle window, or when bd or Gas City ships a gate that
  closes when a review round leaves a PR ready for the operator's approval, a
  round with no push included.
- **`gctk gate return <conversation> --on <bead>...`**, a verb of the agent
  class under a new noun, `gate`, which owns the pack's gate kinds: the stay's
  promise, which the sitting runs once it has sent a piece of work itself, and
  the sign-off after the send its own call makes (section 1).
- **The landing order** (`gctk pr reconcile`) gains one step in its pass: the
  hold and the close of the return gates at the end of a round, before its ready
  transition or the evaluator's read, and the close of a return gate whose work
  has closed or that no open or in-progress conversation waits on. It removes no
  edge, and its ready transition is unchanged.
- **The boards** read who closes a gate from the definition (section 2).
- **`converse-signoff.sh --stay`**, an existing mode, files the return gate on
  the work its own call sends through `gctk gate return`, after that send and
  before it leaves the conversation open, keeps each open return gate the
  sitting filed, and waits through a convoy that tracks each other bead it
  waits on, the newest open one or one it makes with `gc convoy create`. It
  takes a stay on the conversation's own subject,
  writing the subject no wait onto its own convoy, and on the review path a
  stay on the PR whose merge the conversation holds once a return gate covers
  that PR. It refuses that stay when none does. It gains no flag.
- **`converse-entry.sh`** reads a stay's wait through its convoy or its return
  gate. It gains no entry and no value.

None of the surface is a store, a lifecycle state or a metadata key.

The gate's package and the verb are Go in gctk, and the landing order's step is
Go in its pr domain. The sign-off and the entry change what an existing mode
writes and what the entry reads. That corrects what the stay's Debt entry in
`docs/architecture.md` names: a stay that comes back only when its work closes,
and that is refused on the conversation's own subject. They add no verb, mode or
key, so the build changes them in place under the rule for a script that already
exists (`AGENTS.md`, "New pack code is written in Go, in gctk"), and no script
is added.

## 14. The units

Each of units 1 to 3 lands on `integration/tk-vrg93t0`, keeps the suite green
and leaves the city working. On a rig still on the old path, nothing they add
runs but the convoy wait, because the sign-off files no gate there and the
promise's verb refuses such a rig.

| Unit | What it does | Waits on | Releases |
|---|---|---|---|
| 1. The return gate (gctk) | The package `services/gctk/gate`: the return gate's await type and title, the rule for who closes a gate of each await type and the human-gate rule, the gate's filing, and its close with its reason. The verb `gctk gate return` with its refusals, which files each gate with one `bd gate create` whose await id is the bead and whose blocked bead is the conversation. In the landing order's pass, at the end of a round on a draft or on a PR that is ready already: for each open return gate whose await id is the bead, the bead's `blocks` edge onto the conversation that waits on the gate when it is open or in progress, then the gate's close, before the ready transition or the evaluator's read; and in every pass, the close of an open return gate whose bead has closed, or that no open or in-progress conversation waits on once it is five minutes old, with no edge removed. The main board's `heldByPerson`, the rig board's `gateHold` and `parked`, `prstatus.IsHumanGate` and the pr domain's `isHumanGate` read the definition. `docs/gctk-architecture.md` gains the verb's row, the `gate` noun and the order's new step, and `docs/warrants.md` the return gate's warrant (section 13). Tests: the gate the verb files on each bead and the one it finds, the conversation's waits after the verb, onto each of its open return gates, onto no closed return gate and onto no convoy that tracks a bead it promises on, with a park and its other convoys left in place, and each refusal; the hold and the close for new work, for a rework and for the subject; a send-back the run answers with no push closes the gate at the round's end on a ready PR, and an approval from an earlier round does not merge it; a gate filed after its round ended closes on the next pass, with the hold already there left alone; a round with no open return gate writes nothing; a due return gate past the first 50 open gates in the store is read and closed; a conversation that has closed gets no hold; an edge already there is left alone; a failed read or write leaves the gate open and is retried; a PR in its base's merge queue is left to GitHub; a gate whose bead or whose conversation has closed closes; a gate that nothing waits on, as a create that stopped before its edge leaves, closes once it is five minutes old and not before; with several works, a gate that closes leaves the conversation waiting on the others, each bead whose round ends gets its hold and its gate closes in that pass, and the conversation reads ready only once its last gate has closed; the verb promises nothing again on a bead whose gate is still open; the boards read a conversation that waits on its return gate as queued, and a park as a person's. | this rewrite (tk-1gsaloy) | unit 2, once tk-ps47p6p brings the branch current |
| 2. The stay carries its promise, and the entry reads it (scripts) | `converse-signoff.sh --stay`: after the send its ruling makes and before it leaves the conversation open, the return gate on the work that send reaches, through `gctk gate return`: the PR its `--rework` sends back and the subject its `--accept` dispatches; no gate filed again and no convoy wait for a bead whose open return gate the sitting or an earlier stay filed; the wait onto the newest open convoy that tracks each other bead it waits on, or onto one it makes with `gc convoy create`; a stay on the subject, with the subject left waiting on nothing of its own convoy, from PR #1515's head with its open-convoy fix; on the review path, a stay on the PR whose merge the conversation holds when a return gate covers that PR, and that stay refused when none does; on the old path, that stay refused as today. `converse-entry.sh`: `waiting` and `returned` read through the return gates and the convoys. The stay's line agrees with the record when each bead it names has the conversation's edge onto a convoy that tracks it, or is the await id of a return gate the conversation waits on, or has closed. Tests, one per row of section 3 and of section 10: what the sign-off writes, the gates it files after its own send and the beads it files them on, a bead the sitting promised whose PR opened before the sign-off, and before a re-run of it, keeping its gate with no convoy wait, a PR whose exchange the operator settled waiting through a convoy with no gate, a convoy made when none is open, a closed convoy that is no wait, the refusal of a stay on a held PR that no open gate covers, what a stop at each point of the call leaves and the re-run that finishes it, the entry before and after the convoy closes and before and after the gate closes, and the old path's refusal. | unit 1 and tk-ps47p6p | unit 3, once tk-imuvm2j brings the branch current |
| 3. The words | The converse prompt's "End or stay?" and its handling of a return; `converse-stay`, `converse-settle` and `converse-hold` (section 11); `docs/human-engagement.md`; the sentence in `docs/product-goals.md`; the skill-needs pins of the table and of each example's call through the real parsers, among them the stay's call, the sitting's `gctk gate return` once it has sent a piece of work itself and for a PR sent back through the `prs` skill, a stay on several works that comes back once each is ready or has closed, and a stay again after a visit that names only the work still out; the return's hold write, guarded on the claim the entry took, which records the `holding:` line on an ordinary return, and the entry after it, which a restart reads as `interrupted` with the hold standing; the stay's Debt entry in `docs/architecture.md`, narrowed to the rigs still on the old review path. | unit 2 and tk-imuvm2j | the landing |

The initiative's "Done when" asks for a test of each row of the table. Units 1
and 2 hold the rows in their suites, and unit 3 pins them in the words.

No unit builds terminal access: a wrapper around engage's attach, richer tab
status, the subject's PR in the terminal, and finding and cleaning up terminals
are epic tk-uipsrmt's, which is held for prioritization and blocks nothing here.
The return path needs none of them.

## 15. Edges and notes

- The implementation child (tk-y4iqs8j) filed units 1 to 3 (tk-u41ko5k,
  tk-4mknrrf and tk-r06d403) the way it was filed itself
  (`docs/design-convoy.md`), with `target=integration/tk-vrg93t0` in each
  create. The landing bead (tk-vrg93t0) and the summary task (tk-pgxs4zx) wait on
  every unit through a `blocks` edge, and each unit waits on its row through a
  `blocks` edge and is armed. This rewrite (tk-1gsaloy) keeps the units, their
  edges and their arms. Each unit, the landing bead and the summary task also
  wait on it, and its change rewrites each unit's description to this design.
- The refinery's hand-offs bring the effort's branch current before each unit:
  tk-jj483vu before unit 1, which has closed, tk-ps47p6p once unit 1 lands, and
  tk-imuvm2j once unit 2 lands. Main carries the rule that new pack code is
  written in Go, in gctk.
- The human gates that held unit 1 (tk-p5pkn4k, key `stay-wake-probe`) and
  unit 3 (tk-50kk1fa, key `gas-city-keeps-waits`) are answered by the ruling of
  2026-11-18, and no gate replaces them.
- The previous revision left a note on gc-toolkit's cutover (tk-1tfzr71.78) to
  watch one stay through a round with a visit and a hand-over among its events,
  because Gas City's session wait could end the promise at either. The return
  gate changes with neither, and that cutover has closed, so this revision adds
  no watch: units 1 and 2 hold the rows in their suites.
- A note on tk-35ob5gq, the city board's reading of a stay: the hold the landing
  order puts on at the end of a round is the conversation's existing edge, so
  the board reads it as it reads engage's. A conversation that waits on its
  return gates has an open wait of its own, which `conversation.Staying` reads
  as a stay, and unit 1 makes the board read a return gate as the city's.

## 16. Facts this design rests on

Gas City, at upstream main 17d7d77ce2:

- A manual session is wanted awake while ready or claimed work is assigned to
  it. Open work counts once it is ready (`workBeadHasAwakeDemand`), and its
  `assigned-work` demand exempts the session from the idle sleep, while
  blocked open assignments do not keep it awake (`computeAwakeSet` in
  `cmd/gc/compute_awake_set.go`). A session asleep at the end of its idle window
  wakes for assigned work (`HasAssignedWork` in
  `wakeDemandOverridesSleepSuppression`, `cmd/gc/session_reconciler.go`), and
  that function lets no ready session wait through.
- Core's order `cascade-nudge-on-blocker-close` runs on `bead.closed` and nudges
  the assignee of each open dependent of the closed bead
  (`internal/bootstrap/packs/core/orders/cascade-nudge-on-blocker-close.toml`).
- Core's gate sweep checks timer and GitHub gates in each store, and skips bead
  gates (`internal/bootstrap/packs/core/assets/scripts/gate-sweep.sh`).
- `Store.WakeSession` cancels the session's waits as it starts it
  (`cancelWaitsAndCollectNudgeIDs`, `internal/session/wait_store.go`), and a
  wait registered before a fresh restart is cancelled as `continuation-stale`
  (`WaitInfo.ContinuationStale` in `internal/session/waits.go`;
  `cmd/gc/cmd_wait.go`).
- `gt gate` maps to `gc wait` and to formula gates, and "Durable waits are the
  closest platform concept" (`docs/reference/gastown-command-map.md`).
- A formula's `[steps.gate]` stamps its declared type verbatim on the gate bead
  as `gc.gate_type` metadata, "the parser never validates them", and "No
  bundled watcher resolves any gate type"
  (`docs/reference/specs/formula-spec-v2.md`). Gas City's stores "have no
  gate-condition column" (`GateTypeMetadataKey` in `internal/beadmeta/keys.go`).
- The gate kind Gas City defines for itself, the cross-store gate, is marked by
  the label `gc:cross-store-gate` and `gc.cross_store_gate_*` metadata, and its
  controller releases it (`internal/dispatch/cross_store_gate.go`).
- The core reaper closes drained sessions older than a day
  (`gc session prune --state drained --before "$SESSION_STATE_PRUNE_AGE"` in
  `internal/bootstrap/packs/core/assets/scripts/reaper.sh`, 24h by default).
- `gc convoy create <name> <issues>` makes a convoy that tracks the issues, and
  Gas City closes a convoy with no `owned` label once its tracked beads close
  (`convoyStillAutocloses` in `cmd/gc/cmd_convoy.go`). A graph.v2 pour on a bead
  that is not a convoy mints a fresh one-item convoy that tracks it
  (`NormalizeInputConvoy` and `CreateSingleItemInputConvoy` in
  `internal/graphv2/invocation.go`).

bd, at beads v1.3.4:

- `bd gate create` files a bead of issue type `gate` with the await type its
  `--type` names, which it does not check, and the await id its `--await-id`
  names, which its help gives as the "Condition identifier (run ID, PR number,
  etc.)". It writes the `blocks` edge of the bead its `--blocks` names onto the
  gate (`buildGateIssue` and `gateCreateCmd` in `cmd/bd/gate.go`). On a Dolt
  server it creates the gate, then adds the edge, then commits, and only on a
  proxied server does it write both in one transaction
  (`runGateCreateProxiedServer` in `cmd/bd/gate_proxied_server.go`). The city's
  stores run on a Dolt server (`dolt_mode` `server`).
- `bd gate --help` documents the types `human`, `timer`, `gh:run`, `gh:pr` and
  `bead`, and says gates "must be closed (manually or via watchers) for the
  blocked step to proceed". It gives no guidance for a type of one's own.
- `bd gate list <bead>` lists the gates that block that bead, and `bd gate list`
  every open gate in the store, each with its await type and await id. `--all`
  adds the closed ones. Either read stops at 50 gates unless `--limit` says
  otherwise, and `--limit 0` lists them all (`gateListCmd` and
  `filterIssueGates` in `cmd/bd/gate.go`).
- `bd gate check` evaluates `gh:run`, `gh:pr`, `timer` and `bead` gates and
  passes over every other await type (`evaluateGates`), and a `gh:pr` gate waits
  for its PR's merge (`checkGHPR`).
- bd keeps one edge from a bead onto another (`DependencyTypeConflictError`), and
  its cycle check walks only `blocks`, `conditional-blocks` and `parent-child`
  edges (`types.IsSchedulingEdge`).
- `bd dep remove` confirms the same way whether or not the edge was there
  (`cmd/bd/dep.go`), and a guarded `bd update` applies its guard and every change
  it carries, `--append-notes` among them, as one update. When its guard does not
  match, it writes nothing and exits 13 (`cmd/bd/update.go`).

GitHub, through its GraphQL API, read on 2026-11-16: no rig in the city has a
merge queue on its default branch (`repository.mergeQueue`, read for each rig
whose origin is on GitHub).

The pack, at integration/tk-vrg93t0 2a6fd322e:

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
- `heldBy` keeps a review run off a PR only for an open human gate on its bead,
  since a conversation holds only the PR's merge (`services/gctk/pr/admit.go`).
- The main board counts every gate other than a timer, `gh:run` or `gh:pr` gate
  as a person's (`heldByPerson` and `sweptGate` in
  `services/helm/internal/board/state.go`), and the rig board reads every gate
  that is not a human gate as a park (`gateHold` in
  `services/helm/internal/rigboard/table.go`, `parked` in `build.go`).
- A review run can pass with no push (`judge` in `services/gctk/review/passed.go`,
  `answeredAsks` in `services/gctk/review/result.go`, `cmd_push` in
  `assets/scripts/review-run.sh`).
- `converse-rework.sh` files a ruling on the pending record as an ask through
  `gctk review ask`, and `converse-signoff.sh --stay` makes a rework stay wait on
  that ask.
- A converse sitting is a manual session with `wake_mode = "resume"`,
  `sleep_after_idle = "10m"` and `idle_timeout = "0"`
  (`agents/converse-claude-opus/agent.toml` and its siblings).
- `converse-entry.sh` prints `fresh`, `interrupted`, `waiting`, `returned`,
  `none`, `stop` or `unreadable`, and reads a stay off its `staying:` lines and
  its own `blocks` edges. It claims the conversation with `gc hook --claim`
  before it reads a stay, so a conversation it reads as `returned` is in
  progress under the sitting (the ordinary return in `converse-entry.test.sh`).
  A claimed conversation whose newest line is `holding:` reads as a hold that
  stands.
- `gc-helm.sh park` files a gate with no await type, which a person closes to
  release the park, and every closer in the pack closes a human gate only.
- `gate-ensure.sh` and `rework-child.sh` are on the deletion plan with
  tk-1tfzr71.122 (`tools/deletion-plan.tsv`).
- A rig is on the new path once its `pending_through_merge` formula var is
  `true` (`refinery-land.sh`, `refinery-lib.sh`).
