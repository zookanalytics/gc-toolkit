---
name: Design — a stay comes back before your next decision about its work
description: Use when you approve the design of a staying sitting that comes back before the operator's next decision about its work (initiative tk-vrg93t0, design child tk-ai367om), or build one of its units. It gives what the operator approves on one page, the stay in rules and commands with each case, the stay's gate with its type gctk:needs-review and its one definition in gctk, the PR's own status that resolves it, when a stay comes back, the hold on the PR's merge and its stages, the return, every round, settling and where staying available would go, the conversation's own subject, visits and fresh contexts, the city's own store, the pages, what the earlier revisions built, the surface and the units. It was read against the pack at integration/tk-vrg93t0 2a6fd322e, with sections 2 to 4 also read at main 39099392f and at the head a1be1e0c6 of pull request 1612, Gas City upstream main 17d7d77ce2 and beads v1.3.4.
---

# Design: a stay comes back before your next decision about its work

This is the design record for tk-ai367om, the design child of the initiative
tk-vrg93t0. It follows the brief the operator approved in conversation
tk-8e83do9 on 2026-11-16, recorded on tk-ai367om as "Proposed rework brief for
PR #1529", and the operator's ruling of 2026-11-18 in conversation tk-reymwh1,
recorded on tk-r06d403 and on the rewrite's bead tk-1gsaloy. That ruling has the
sitting come back through its own task, which waits on a gate of the pack's own
that the landing order closes, with no change to Gas City. The operator's words
were "a task, especially if the normal approach, that is blocked normally and
cleared is great", and "As a gate in gc-toolkit, it should be well defined, used
everywhere appropriate, etc." The initiative's rule still frames the design: a
stay comes back at the operator's next decision about the work, never after it.

This revision carries the operator's ruling of 2026-11-20 in conversation
tk-tu5qn05, recorded on tk-1gsaloy. They had said of the previous revision, "I
feel like the whole command and promise, and even the solution, both just feel
like they're complicated", and they ruled "Yes, let's proceed with the
recommendation" on a one-page core, which the sitting of that conversation
wrote into this document with them. The core keeps the path where a stay waits
for one piece of work, and leaves out what the previous revision had added
around it: several pieces of work in one stay, every convoy, and a rule for
each rare stop. A separate reader tried to break five drafts of the core by
reading the scripts at the base. No break was on the path where a stay waits
for one piece of work. Each was in one of those additions, or in something a
draft had added of its own: a close on a question filed on the work, and a
reading of the stay's `--waiting-on` as the piece to bring back. The notes of
tk-1gsaloy hold the drafts and what broke each.

On 2026-11-21, in the same conversation, the operator read that text and gave
the gate its terms, which sections 2 to 4 carry. The gate is filed in bd's own
terms, and its type names the condition that resolves it, in a word the pack
already uses for a PR, `needs-review`: "It should be keyed off that common
class that computes those statuses." Of the hold they said it "needs to be well
thought through from a big picture, what does this all mean in terms of state".
The separate reader attacked a draft of those sections too, and the same notes
hold what it broke.

The pack was read at integration/tk-vrg93t0 2a6fd322e, which carries main at
264fa89a9. Sections 2 to 4 were read again at main 39099392f and at the head
a1be1e0c6 of pull request 1612, which gives a bead's standing one owner. The
effort's branch takes both before unit 1 builds (section 14). Gas City is cited
by symbol at `gastownhall/gascity` main 17d7d77ce2, and bd at beads v1.3.4. The
search behind each piece of surface the units add is
[gas-city-search.md](gas-city-search.md), which also cites the platform facts
this design leans on.

## What the operator approves

Today a sitting you ask to stay comes back when its work's bead closes. For new
work that opens its own PR, that is after the PR has merged, too late to change
anything. A rework of the PR you discussed comes back when it reaches the
branch, before its checks run again, and a stay on the conversation's own
subject is refused. A sitting that comes back and finds nothing to ask signs
off.

Approving this design changes that in every rig:

1. **A stay comes back for one piece of work, before your next decision about
   it.** It comes back once the city has finished with that work's PR and only
   your part is left, or when the work has closed.
2. **The PR does not merge before you and the sitting have settled it.** The
   landing order is what requests a merge, and it requests none while the
   stay's gate is open. The pass that finds the PR finished puts the
   conversation's hold on it, and only then wakes the sitting. It marks the PR
   ready as it does today, as you ruled on 2026-11-16, so CI runs and GitHub
   requests your review, and the sitting is back once the required checks have
   passed.
3. **The sitting always comes back to you, with a short summary and its
   recommendation.** It checks the result against each item you agreed, and
   says on the PR and in its hand-back which items are covered. It closes with
   where that leaves you: every item is covered and you can approve when you
   are comfortable, or which item still needs your word. It waits for you
   either way. What it says is advice, never one of the PR's checks.
4. **You send the work back, settle it, or end the conversation.** Sending it
   back is a new stay, so the sitting comes back once the city has finished
   with the PR again. Settling releases the PR. Leaving the terminal neither
   approves the work nor cancels the return.

How it works:

- **One wait, in bd's own terms.** The stay's gate is a bd gate. Its type,
  `gctk:needs-review`, names the condition that resolves it, its await id is
  the one piece of work, and the bead it blocks is the conversation. A
  conversation has one open at a time, so the landing order never puts a hold
  on a PR while the sitting sleeps on another piece. The type is defined once,
  in gctk (section 2).
- **Who files it.** For a rework of the PR you discussed, or a recommendation
  you accept, the stay's own command files it, right after it sends the work.
  For work the sitting sends itself, the sitting files it with one command
  after the send. A stay that waits only on such work refuses to start without
  the gate, so a skipped step stops the stay.
- **One closer, reading the status the pack already computes.** The landing
  order resolves the gate when the work's PR reads `needs-review` with what
  holds it set aside, or `merging` if you approved early, or when the work has
  closed (section 3).
- **The wake is Gas City's.** It wakes a sitting once nothing open blocks its
  conversation, as it wakes a staying sitting today. A visit and a fresh
  context change nothing, because the return waits in the store.

What it leaves out:

- **Several pieces of work in one stay.** The sitting comes back for one piece
  at a time. Other work it sent, or that you send from a visit while it waits,
  brings no return of its own: it lands as work does today, or, on a PR the
  conversation already holds, waits for the sitting's next return. The sitting
  tells you so before it stays.
- **Staying available until the subject closes.** After you settle, the sitting
  ends, as it does today. That life cycle is a change of its own, which
  tk-lfcb8ug holds (section 7).
- **A return when the work is in trouble**, such as a failed check or a
  question filed on it. Those reach you as they do today. tk-lfcb8ug also holds
  the wider gate type you raised, which would bring the sitting back for them.
- **A return only to say that settled work landed.**

Section 1 lists what the design leaves as it is, with nothing built. In the
city's own store, which the landing order does not read, a stay works as it
does today (section 10).

## 1. The stay, in rules and commands

**The rules.** C is the conversation, and W is the one piece of work the stay
is for. Each is a bead, named by its id. Conversation `tk-tu5qn05` is about
PR #1588, whose bead is `tk-1gsaloy`: had the operator sent that PR back and
kept the sitting for the result, C would be `tk-tu5qn05` and W `tk-1gsaloy`.
For new work the sitting files and sends, W is the new bead's id.

1. **The gate.** A bd gate of type `gctk:needs-review`, whose await id is W
   and which blocks C (section 2). The type names the condition that resolves
   the gate, and W says only which work. A conversation has at most one open.
2. **The promise.** One command files the gate, or finds the open one for W,
   from W's id and C's id:

   ```bash
   gctk gate create --type gctk:needs-review \
     --await-id <work-bead-id> --blocks <conversation-bead-id>
   ```

   It is bd's `gate create`, which files a gate and adds the dependency onto
   it, with the pack's checks in front (section 2). In the example it ends
   `--await-id tk-1gsaloy --blocks tk-tu5qn05`. The sitting runs it right after
   it sends a piece of work itself. The stay's command runs it after the send
   its own call makes and the waits that call writes, when C has no open gate.
3. **The stay.** `converse-signoff.sh --stay` leaves C open, waiting on its
   gate. A call that sends nothing itself refuses, before any write, when C has
   no open gate. Its `--waiting-on` is the subject's wait only, as it is in a
   sign-off that ends.
4. **The resolve.** Only the landing order resolves the gate, at the first of
   two: W's PR reads `needs-review` or `merging` in its own right, which is
   with what holds it set aside, or W has closed (section 3). Before the
   first, it puts C's hold on the PR, and it requests no merge of that PR while
   the gate is open (section 4).
5. **The wake.** C is ready once its gate has closed, and Gas City wakes the
   sitting for it.
6. **The return.** The sitting checks each agreed item, posts a short summary
   with its recommendation, and holds for the operator, whatever it found
   (section 5).
7. **Settling.** On the operator's ruling the sitting lifts the hold. It then
   ends the conversation, or promises and stays for another piece (section 7).
8. **The city's own store.** The landing order does not read it, so there the
   stay is today's stay, and the promise refuses (section 10).
9. **The stall check.** The promise refuses a W that cannot move until
   something C already holds has landed (section 2).

A conversation holds a PR in only three ways: from engage, while its sitting is
live; from the landing order, in the pass that resolves its one gate and so
wakes its sitting; or across a stay made while it held that PR, whose promise
the stall check read. So no hold is written while the sitting sleeps on.

**The stay, in commands.** A stay takes one of two forms.

- **The stay's own call sends the work.** A ruling that sends the PR under
  discussion back is sent by the sign-off itself, through `converse-rework.sh`
  (`--rework`), which on the review path files the ruling as an ask on the PR's
  bead. A ruling that takes the subject's recommendation (`--accept`)
  dispatches the subject inside the sign-off. Either way one call of
  `converse-signoff.sh --stay` records what the operator agreed, makes the
  send, files the gate on the bead it sent unless the sitting has already
  promised another piece, and leaves the conversation open under its sitting.
- **The sitting sends the work.** New work, the subject it slings, and another
  PR it sends back through the `prs` skill are sent by the sitting before it
  signs off. Once the send is made, it promises the work, and then it stays:

  ```bash
  gctk gate create --type gctk:needs-review \
    --await-id <work-bead-id> --blocks <conversation-bead-id>
  ```

  The stay's call then finds the conversation's open gate and leaves the
  conversation open. A call that finds none, and sends nothing itself, refuses
  and names this command.

In either form the sitting writes what was agreed as a list of items the return
can check, in the work's brief or, for a send-back, in the order its ruling
sends (`converse-settle`, "Send the work"). `--stay` still takes the one line
the entry prints as `AGREED`.

Once the operator detaches, Gas City sleeps the sitting after its template's
idle window (`sleep_after_idle`, ten minutes for the converse templates),
because its conversation waits on an open bead. When the gate closes, the
conversation is ready work assigned to the sitting, so Gas City wakes it and
resumes its thread (`wake_mode = "resume"`), and the prompt runs the entry,
which reads `returned`. A sitting that is still up gets Gas City's notice that
a blocker closed instead. A stay never runs `gc runtime drain-ack`, because the
core reaper closes a drained session once it is a day old, and a closed session
leaves the return to a sitting with no thread.

**Each case.** G is the stay's gate.

| Case | What happens |
|---|---|
| New work W that opens its own PR | The sitting slings W, promises it, and stays. The landing order marks W's PR ready as it does today, and CI runs. Once the PR reads `needs-review` in its own right, the landing order writes the hold and resolves G, and requests no merge. The sitting wakes, compares, and holds. |
| The sitting skips the promise | The stay sends nothing itself and finds no gate, so it refuses before any write and names the command to run. |
| A rework of the PR under discussion | The conversation holds the PR already. The stay's `--rework` files the ask, then the stay files G on the PR's bead. The PR reads `working` in its own right while the ask is open (section 3). |
| The subject itself is sent | By `--accept`, the stay files G on the subject after the dispatch. Slung by the sitting, it is promised like any work (section 8). |
| Work that opens no PR | G resolves on the pass after W closes. There is no hold. |
| The ruling reworks the PR and also sends new work W | With W unpromised, the stay files the PR's gate, and W lands as work does today, which the sitting says before it stays. With W promised first, the stay keeps that gate: the sitting is back when W's PR reads `needs-review`, the PR under discussion stays held from engage, and once W is settled the sitting promises that PR and stays again. |
| The sitting sent two new pieces | It promises one. The promise for the second is refused while the first is open. The second lands as work does today, or is promised after the first is back, if it has not merged. |
| The operator sends the piece back after a return | The ask comes first, then the gate (section 6). The hold from the first return still stands, so an earlier approval merges nothing. |
| The returned piece is still unsettled, and the ruling reworks the PR under discussion, which waits on it | The stall check refuses the PR's gate, because the PR waits on the conversation through that piece. The refusal comes after the ask is filed, so the stay stops short with the rework sent, and the sitting says so. Once the operator settles the piece, the same call finishes the stay. |
| A question for a person is filed on W | It is a hold, so it changes nothing in the PR's own status. While it keeps the city's work from finishing, as a review that ran out of attempts does, the gate stays open, and the question reaches the operator on the board as today. Once the PR's own status turns, the sitting is back, whether or not the question is still open. |
| A required check fails on W's PR | The PR reads `needs-attention` in its own right, so the gate stays open and the sitting sleeps on. The failure reaches the operator as today, and the gate resolves once the check has passed. |
| The operator ends the conversation while the work is out | The conversation closes and its holds go with it. G resolves at its condition with no hold. |
| The stay's command stops partway | Its first `staying:` line makes the entry read `interrupted`, and the same call is run again. The promise is in the store before the call, or the call files it after its own send. |
| W's PR reached `needs-review` between the promise and the stay | The gate was resolved, and the hold was written. A stay that sends nothing refuses and says that the work is back, and the sitting carries out the return. |
| The operator approves on GitHub before the return | The landing order requests no merge while the gate is open. Once the city has finished, the approved PR reads `merging` in its own right, so the gate resolves with the hold, and the hold keeps the merge until the operator settles. |
| W's PR is closed unmerged | The landing order leaves W blocked behind its own question for a person, not closed, so G stays open until that is answered. |
| Two conversations stay for the same work | Each has its own gate and its own hold. |

**What it leaves in place, with nothing built.**

- **Trouble on the work does not wake the sitting**: a question filed on it,
  such as a review that ran out of attempts, a required check that failed, or
  a PR closed unmerged. Each reaches the operator as it does today, and the
  operator can visit the sitting (section 9). tk-lfcb8ug holds a wider type
  that would wake it.
- **Other work the sitting sent** does not bring it back. It is held only when
  it is on a PR the conversation already holds.
- **A sitting cut off between a send and its promise.** If nobody picks it up
  for a whole build and review, that PR turns ready with no hold. It still
  needs the operator's approval, as with every stay today. A promise made late
  resolves on the next pass, with the hold when the PR is still open.
- **A dependency written after the promise** onto something the conversation
  holds. The piece cannot move, and the sitting sleeps until the operator
  visits. The stall check reads only the edges that exist when the promise is
  made.
- **A `bd gate create` that stops between its two writes** leaves a gate that
  nothing waits on. The next run of the promise files another, and the stray
  resolves at its condition with no hold (section 2).
- **A merge queue, a merge made by hand, new work's PR between its ready
  transition and its hold, a closed session, and the minutes before the
  sitting's post** (section 4), and **the board's fallback** (section 2).

## 2. The gate

**A bd gate, in bd's terms.** bd calls gates "async wait conditions"
(`bd gate --help`). The stay's gate fills three of a gate's parts:

| bd's term | What it holds | In the stay's gate |
|---|---|---|
| type (`--type`, stored as the await type) | the kind of condition, as bd's own `timer`, `gh:pr` and `bead` are | `gctk:needs-review` |
| await id (`--await-id`) | which one, bd's "Condition identifier (run ID, PR number, etc.)" | the work's bead id, `<work-bead-id>` |
| blocks (`--blocks`) | the bead that waits | the conversation's bead id, `<conversation-bead-id>` |

The type names the condition that resolves the gate, in the word the pack
already uses for that state of a PR (section 3). It says nothing of what
follows, which is the same for every bd gate: the bead it blocks is free to
go. Here that bead is the conversation, so Gas City wakes its sitting, and
that is the return. A later kind is another type over the same status, such as
the wider one tk-lfcb8ug holds, and a conversation still waits on one open
gate. The prefix `gctk:` keeps the type clear of bd's `gh:` types, which bd's
checker and Gas City's sweep select by that prefix. The gate's title names the
work and the condition in the operator's words.

The type is defined once, in gctk's `gate` package (`services/gctk/gate`),
which sits outside `internal`, as `waits` and `prstatus` do, so a board can
import it. The package holds the type, the rule that the city closes a gate of
this type, the gate's filing and the form of its resolve. The verb and the
landing order call it, and nothing else writes the gate.

- **Who files it.** `gctk gate create`, run by whoever sent the work, once the
  send is made (section 1). The verb is a helper over one bd command, which
  files the gate and adds the conversation's dependency onto it:

  ```bash
  bd gate create --type gctk:needs-review \
    --await-id <work-bead-id> --blocks <conversation-bead-id>
  ```

  The verb finds the conversation's open gate among the gates that block the
  conversation, which `bd gate list <conversation-bead-id> --limit 0` lists
  with each one's await type and await id, and files one only when none is
  open. It takes only a type the
  package defines, and it refuses, writing nothing:
  - a conversation that is neither open nor in progress under the caller's
    alias, since the sitting runs it while it holds the conversation;
  - a conversation that already waits on an open gate of this type for another
    bead;
  - a bead in another store, and a bead that has closed;
  - a bead in the city's own store, which the landing order does not read
    (section 10);
  - a bead that waits on the conversation through another bead (the stall
    check). It walks the bead's own waits as `waits_on_conversation` in
    `converse-signoff.sh` does, and goes on past the bead's own hold, so a PR
    the conversation holds can be promised, and one that waits on another piece
    the conversation holds cannot. An ask on the bead, and what that ask waits
    on, are among the waits it walks. The stay's own call runs the verb after
    its headline's edges are written, so the check reads them too.
- **One command, two writes in this city.** bd writes the gate and the
  conversation's edge onto it in one transaction only on a proxied server
  (`runGateCreateProxiedServer` in beads `cmd/bd/gate_proxied_server.go`). The
  city's stores run bd against a Dolt server, where `gateCreateCmd` creates the
  gate, then adds the edge, then commits. A create that stops between the two
  leaves an open gate that nothing waits on, and the verb's next run files
  another.
- **What resolves it, and when.** The landing order alone, at the condition
  section 3 defines and in the pass section 4 gives. A resolve is bd's close of
  the gate, with a reason that names the bead and what resolved it: the own
  status its PR read at a head, or the bead's close.

  A gate that no open or in-progress conversation waits on, as after the
  operator ends the conversation or after a create that stopped before its
  edge, resolves at the same condition and puts no hold on anything.

  The landing order lists the store's open gates in each pass, and again
  before a merge request (section 4), with `bd gate list --limit 0`. bd lists
  50 gates unless `--limit` says otherwise, and a gate left off the list would
  never resolve. The read is of open gates
  only: on 2026-11-20 the fullest store the order reads held 19, and the read
  took about 0.3 seconds, in a pass main runs once a minute for each rig. A
  gate's bead is its await id, and its conversation is its dependent through a
  `blocks` edge (`bd dep list <gate> --direction=up --type blocks`). bd's gate
  check evaluates only `gh:run`, `gh:pr`, `timer` and `bead` gates
  (`evaluateGates` in beads `cmd/bd/gate.go`), and Gas City's core sweep checks
  only timer and GitHub gates, so the landing order is the gate's only closer.
- **How a reader tells that the city closes it.** The package answers that the
  city closes a `gctk:needs-review` gate, and two rules have to ask it:
  - The park rule reads every gate that is no human gate as a park, and it
    comes before the rule for a stay (`gateHold`, in
    `services/helm/internal/rigboard/table.go` on main and in
    `services/gctk/standing/rules.go` with pull request 1612). It asks the
    package, so a conversation that waits on its gate reads as staying, in the
    queued group, as a stay reads today.
  - With pull request 1612, the rule for how far the city carries a bead reads
    a wait on a gate that is no human gate as stuck
    (`services/gctk/standing/advance.go`). It asks the package too, so a
    staying conversation and the PR it holds read as advancing while the work
    is out, as a stay's do today.
  - The rule for a stay counts any open `blocks` edge of the conversation's
    own, a gate included (`conversation.Staying`), and every other reader of a
    gate's type asks only whether it is a human gate (`IsHumanGate`). Neither
    changes.
  - `converse-entry.sh` reads a stay by the one gate its newest `staying:` line
    names (section 5).
  - No doctor check reads the gate as anything but a gate:
    `check-wait-is-an-edge` exempts every gate, and `check-blocked-work-armed`
    reads only unassigned beads.
  - On the board's fallback onto the supervisor's API, whose beads carry no
    await type (`services/helm/internal/source/supervisor.go`), a conversation
    waiting on its gate reads as parked, as every gate does there.

The pack files no other gate that the city closes. A park's gate carries no
await type and a person closes it, and every closer in the pack closes a human
gate only, so nothing else moves onto this definition.

## 3. When a stay comes back: the PR's own status

In a rig's store, a stay comes back as this table gives. Section 10 gives the
city's own store.

| The stay is for | Its gate names | It comes back |
|---|---|---|
| New work that opens its own PR | the work's bead | when its PR reads `needs-review` or `merging` in its own right, or when the work closes |
| A rework of the PR under discussion | the PR's bead | when that PR reads so again, once the rework is done |
| The conversation's own subject | the subject | when the subject's PR reads so, or when the subject closes |
| Work that opens no PR | the work's bead | when the work closes |

**One place for a PR's status, and views on it.** For each PR on the pending
record, the pr domain's evaluator lists every condition the PR has not met,
each with a kind (`services/gctk/pr/pr.go`): its record, its GitHub side, such
as a draft, a required check that is pending or failed and a missing approval,
the review's result, and each bead its own bead waits for. The status owner
(`services/gctk/prstatus`) reads that answer beside the facts about what the
bead waits for (`Facts`), and pull request 1612 gives a bead's standing the
same single owner. What a person or an agent sees is a view on that data.

| View | What it shows | Who reads it |
|---|---|---|
| The `status:` label | one word: `working`, `needs-review`, `merging` or `needs-attention` | GitHub, where a label is one key and explains nothing |
| `gctk pr status` | the word, what holds the PR, and each condition not met | agents and the board |
| A bead's standing (pull request 1612) | whose move it is, the rule that says so, and its frontier | the board and a sitting |
| The PR's own status, which this design adds | where the PR stands with what holds it set aside | the landing order, for the gate |

The design adds that one view and no data.

**The PR's own status.** The conditions fall in two groups.

- **What holds the PR:** a hold set by hand, and a wait on a bead that only a
  person clears, by the person rules: a human gate, a decision, a conversation
  or a bead assigned to a person (`IsHumanGate` and `Clears` in
  `services/gctk/standing/person`, with pull request 1612). The status owner
  sorts each of the bead's waits by those rules already, when it reads the
  facts for the label.
- **The PR's own:** everything else the evaluator lists. A wait on work is
  among it: a send-back, a review run, a park, or other work that lands first,
  whoever that other work waits for.

The own status is the label's rule (`Render`) read over the second group
alone, with one change of order: the city's work comes before an approval. An
approved PR the city is still changing reads `working` here, where its label
reads `merging`.

| Own status | When, first match |
|---|---|
| `needs-attention` | Something of its own that only a person clears: its record does not read or the PR is not open, a required check failed, a review run ended with no result, a review thread waits on the city's answer and nothing acts on it, or an approved PR with nothing else left is in a merge state that holds it. |
| `working` | The city still has something to do, approved or not: the PR is a draft, GitHub is not read at its head, a required check is pending, no review has passed at its head, its bead waits on work, such as a send-back or a review run, or anything else the evaluator lists, such as a changed head or feedback not yet handled. |
| `merging` | An approval stands, and nothing of its own is left. |
| `needs-review` | Only an approval is left, or a request for changes that its author has to lift. |

A hold never changes the own status. On the label, a hold a person has to clear
reads `needs-attention`, and a staying conversation's hold reads `working`,
approved or not.

**When the gate resolves.**

```
A gate is resolved when:
  gctk:needs-review: the target bead's PR has own status needs-review
                     OR own status merging
                     OR the target bead is closed
A gate stays open while:
  gctk:needs-review: own status working
                     OR own status needs-attention
                     OR the target bead is open and owns no PR on the record
```

It is never escalated. Where bd would escalate a gate, at a failed run or a PR
closed unmerged, the trouble reaches the operator as it does today, and the
gate stays open. `merging` is in the list because a PR the operator approved
early never reads `needs-review`.

**What the moment is, for a PR.** The city has finished with it: the landing
order has marked it ready, its review has passed at the head the refinery
validated, its required checks have passed, and no send-back or review run is
open on its bead. That is later than the ready transition, which does not wait
for CI (`readyBar` in `services/gctk/pr/draft.go`): this repository's CI skips
a draft (`.github/workflows/tests.yml`), so its checks run once the PR is
ready. An open send-back keeps the PR `working` whether or not a run can take
it yet, so one that waits on other work, which main files since PR #1563,
keeps its gate open too. No bead's close marks the moment. The PR's
own bead closes after the merge, and a send-back can close before the head the
operator approves exists, as the search record gives.

**Why the wait is not an edge onto the work.** The hold of section 4 is the
PR's bead's `blocks` edge onto the conversation, and bd refuses an edge from
the conversation onto that bead while the hold stands, because its cycle check
walks `blocks`, `conditional-blocks` and `parent-child` edges
(`types.IsSchedulingEdge`, beads `internal/types/types.go`). A stay on the
conversation's own subject has a second reason: the conversation tracks the
subject, and bd keeps one edge from a bead onto another
(`DependencyTypeConflictError`). The gate names the work by its await id, which
is no edge, so it meets neither rule.

**Another store.** A stay waits only on work in its conversation's own store,
because an edge onto another store's bead holds nothing, so the promise refuses
that work, and the sitting ends at the hand-off.

## 4. The hold: the PR waits for the discussion

**The hold is the one a conversation already keeps.** A conversation on an open
PR holds its merge through the anchor's `blocks` edge onto the conversation
(`conversation_hold_merge` in `assets/scripts/gc-helm.sh`). The evaluator reads
that edge as a wait of the bead's own (`ownWaits` and `KindWait` in
`services/gctk/pr/pr.go`). It holds only the merge: the landing order keeps a
review run off a PR only for an open human gate (`heldBy` in
`services/gctk/pr/admit.go`), and the refinery leaves out the conversations
among what holds a bead (`assets/scripts/refinery-find-work.sh`), so the PR's
review runs and its validation go on.

**It is one hold, and what it means changes as the stay moves.**

| Stage | The conversation | The hold means | The PR's label reads |
|---|---|---|---|
| The operator and the sitting talk | in progress | the operator's move | `needs-attention` |
| The sitting stays for this PR | open, waiting on its gate | the work's move comes first | `working` |
| The sitting stays for new work | open, waiting on its gate | nothing yet: the new PR is not held | as any PR's does |
| The PR's own status reaches `needs-review` | its gate resolves, and the sitting wakes | the operator's move: settle with the sitting | `needs-attention` |
| The operator settles | lifts the hold, or closes | nothing | `needs-review`, or `merging` if approved |

**The landing order puts it on, and then resolves the gate.** Where it decides
an open PR at its head (`decideAtHead` in `services/gctk/pr/landing.go`), the
landing order looks for an open gate of this type whose await id is the PR's
bead. When the PR's own status is `needs-review` or `merging`, it does this, in
order:

1. For each such gate, it writes the PR's bead's `blocks` edge onto the
   conversation that waits on the gate, when that conversation is open or in
   progress.
2. It resolves each gate.
3. It requests nothing else of that PR in that pass.

The landing order requests no merge of a PR while an open gate of this type
names its bead. A PR it finds ready under such a gate reads `merging` in its
own right, so it gets the hold and the resolve in place of the merge request.
It lists the gates once more at its last read before a merge request (`merge`
in `landing.go`). That read is of the bead's status and assignee today, and a
gate is no edge of the bead's, so without the second list a gate filed during
the act would go unseen. From the next pass on, the hold is a wait the
evaluator reads.

- An edge already there, as engage writes it for the conversation's own
  subject, is a no-op.
- A read or a write that does not land leaves the gate open and ends that PR's
  pass with no merge requested. The next pass tries again.
- A conversation that has closed gets no hold.

The same pass resolves each open gate whose bead has closed.

**Why the hold is not written when the sitting stays for new work.** The hold
is a `blocks` edge, and on work that is not built yet it would stop the build,
not only the merge. So the landing order writes it in step 1. For the PR under
discussion the conversation holds it from engage, and step 1 writes nothing.

**Only the operator's settlement lifts it.** The sitting lifts the hold only on
the operator's ruling that settles the returned exchange, with the lift
`converse-hold` gives a sitting
(`gc bd dep remove <work-bead-id> <conversation-bead-id>`). It
never lifts the hold because it found nothing to ask. A sign-off that ends the
conversation releases the hold with the close, as every close does.

**What the operator sees.** Once the gate has resolved, the conversation is
open under its sitting with no wait of its own, so it is the operator's move.
The PR's `status:` label reads `needs-attention`, held by that conversation
(`Render` in `services/gctk/prstatus/render.go`, on the facts' `Owed`). By then
the PR is ready and its required checks have passed, so GitHub has requested
the operator's review.

**What the hold does not cover.**

- **A merge the landing order has already requested.** On a base that requires
  a merge queue, the order adds the PR to the queue and leaves it to GitHub from
  then on, because `decideAtHead` returns for a PR in its base's merge queue
  before it reads anything else. No rig in the city has a merge queue on its
  default branch (GitHub's `repository.mergeQueue`, read for each rig on
  2026-11-16), so the design builds nothing for a queued PR.
- **A merge made by hand.** The rule binds the landing order's own request. A
  person who merges a PR on GitHub has made the decision the return was for.
- **New work's PR between its ready transition and the hold.** The PR is ready
  and not yet held while its checks run, and for up to a pass after they pass
  its label can read `needs-review`. An approval given then merges nothing,
  because the gate is still open.
- **A sitting whose session has closed.** The gate still resolves and the hold
  still goes on, so the PR waits, held by the conversation, which the board
  lists as the operator's. The return starts once the operator engages the
  conversation and a sitting takes it up from the record.
- **The minutes between the gate's resolve and the sitting's post.** The PR is
  held and reads `needs-attention` before the sitting has posted what it found.

## 5. The return

The sitting takes the return up when its entry reads `returned`, in this order:

1. **Read why it is back.** The entry reads `returned` once the gate the stay's
   newest `staying:` line names has closed. The gate's close reason names its
   bead and what resolved it: the own status its PR read at a head, or the
   bead's close.
2. **Record what the operator owes, first.** The PR's merge is already held
   when the sitting wakes, and it stays held if the sitting never wakes
   (section 4). What the sitting records here is the conversation's `holding:`
   line, which a restart reads and which holds no merge. The entry has already
   claimed the conversation, with `gc hook --claim`, so the sitting records the
   line in one write guarded on that claim:

   ```bash
   gc bd update "$CONVERSATION" --if-assignee "$GC_ALIAS" --if-status in_progress \
     --append-notes "holding: <what the operator owes>"
   ```

   A guard that does not match writes nothing and exits 13
   (`cmd/bd/update.go`), as when the operator ended the conversation meanwhile.
   The sitting then records no line, and says in the thread what stopped it.
3. **Read the result** at the PR's head, which is the head the gate resolved
   at, with the review run's account of each round since the head it last read.
4. **Check it against what was agreed, item by item.** The items are the ones
   the stay recorded in the work's brief or in the send-back's order, with the
   thread and `AGREED` beside them.
5. **Post a short summary with its recommendation**, on the PR through
   `pr-post.sh comment` and in its hand-back. The summary names what was
   discussed, lists each agreed item with whether it is covered and how the
   sitting checked it, and closes with one of three lines, so the operator can
   tell at a glance which it is:
   - every item is covered, the sitting sees nothing left to discuss, and the
     operator can approve when they are comfortable, or raise anything else;
   - some items are covered, and it names each one that still needs the
     operator's word, with the question;
   - the work departs from what was agreed in a way the operator has to rule
     on.

   The summary is advice in the sitting's own voice. It claims no more than
   the sitting checked, and it is not one of the PR's checks.
6. **Wait for the operator.** The hold stands until they rule, whichever line
   the summary closed with.

A restart after step 2 reads the `holding:` line that stands, and a restart
before it reads `returned` again, because the closed gate stays in the store. A
sitting whose context runs low hands the return over as `converse-stay` gives
and runs `gc session reset`, which changes neither the conversation nor its
gate.

When the work closes, merged or closed without a PR, its gate closes on the
landing order's next pass. The sitting reads how the work closed, compares as
above unless the PR merged at a head it already discussed, and holds for the
operator, as on any return.

## 6. Every round

**A send-back through the sitting.** The operator's ruling sends the PR back: an
ask on the PR's bead through `converse-rework.sh` for the PR under discussion,
or `gctk review ask` through the `prs` skill for another PR such as new work's.
The sitting stays again, and the ask comes before the gate: the sign-off sends
the ask with `--rework` and then files the gate, and for another PR the sitting
files the ask and then the gate before it signs off. So the PR reads `working`
in its own right when the gate is filed, and the hold stays on it. It reads
`needs-review` again whether or not the review run pushes:

- **The run pushes a fix.** Its push returns the PR to draft. The landing order
  marks the new head ready once its review has passed, and the gate resolves
  once that head's required checks have passed.
- **The run declines, defers or answers the ask.** Its pass rule counts such an
  ask as ruled (`judge` in `services/gctk/review/passed.go`), its `record` closes
  the ask as a no-op (`answeredAsks` in `services/gctk/review/result.go`), and
  its push step, with nothing to push, returns before it would return the PR to
  draft (`cmd_push` in `assets/scripts/review-run.sh`). The gate resolves at
  the head the PR was ready at, once the run has let go of the bead.

An approval the operator gave in an earlier round cannot merge the PR
meanwhile, because the hold stands.

**A round the city starts by itself**, such as a repair after a failing check or
a merge of the target, keeps the PR `working` until the head the city leaves
has passed its review and its checks. A gate that is open then resolves there.
After a return there is no gate, and the hold stands until the operator
settles.

A gate closes once, so each stay brings the sitting back once, and each round
the operator rules is a stay of its own. Nothing records which head a return
read, because no rule waits on that record.

## 7. Settling, ending, and where staying available would go

**Settling.** The operator rules that the returned exchange is settled, for
example that the work may merge. The sitting lifts the hold and records the
ruling. It then ends the conversation, as a sitting does today, or promises
another piece of work and stays for it. Nothing promises the settled work
again, and nothing waits for it to land.

**Ending.** The operator can end the conversation at any time. The sign-off
without `--stay` closes the conversation and releases its holds with the close.
A gate still open then has no open conversation, so it resolves at its
condition and holds nothing (section 2).

**Staying available is a change of its own.** The operator's direction of
2026-11-15 in conversation tk-8e83do9 was that "as long as the subject is open,
the discussion is available to be resumed", and on 2026-11-20 they described
the life cycle it belongs to: a sitting on a PR stays available, asleep and
easy to resume, until the PR closes; a gate put earlier is the explicit ask to
be woken before the approval; and when the subject closes the sitting is done
and closes itself out, unless it asked to be told and kept. tk-lfcb8ug holds
that idea, and this design builds none of it. It fits the same shape: a gate
that resolves only at the subject's close would be a second type, and the type
built here also resolves earlier, with the hold. The same bead holds the wider
type the operator raised on 2026-11-21, `gctk:needs-attention`, which would
also resolve when the PR needs a person. Nothing here has to be undone for
either, because a conversation already waits on one gate at a time.

## 8. The conversation's own subject

PR #1515 (closed unmerged; `refs/pull/1515/head` keeps its head 6ffdc541f) let a
sitting stay when its ruling sends its own subject, by waiting on the input
convoy the subject's dispatch pours, and came back after the merge. This design
needs no convoy for it. The gate names the subject by its await id, which is no
edge onto the subject, so on the review path the sign-off takes a stay on the
subject, and the sitting comes back when the subject's PR reads `needs-review`
in its own right. A ruling that takes the subject's recommendation (`--accept`) sends the
subject inside the sign-off, which then files the subject's gate itself. A
sitting that slings the subject sends it first, promises it, and then stays.

A stay on the PR under discussion is the same case, so on the review path the
sign-off stops refusing a stay on the PR whose merge the conversation holds: the
stay's gate brings the sitting back before that merge.

## 9. Visits and fresh contexts while the work is out

Attaching to the sitting and resetting its context act on its session. The
return waits in the store, on the conversation's edge onto its gate, and
neither one changes the conversation or its gate.

- **A visit** attaches to a sitting that runs, or has the controller start a
  sleeping one with its thread (`gc session attach`). Gas City cancels the
  session's waits as it starts it (`Store.WakeSession` in
  `internal/session/wait_store.go`), and a staying sitting has none. The entry
  reads `waiting`, which keeps the sitting, and it sleeps again once the tab
  detaches, as it does today.
- **A fresh context.** `gc session reset` restarts the session with a fresh
  thread under the same alias and the same assigned work, and the fresh
  thread's entry reads `waiting` or `returned` from the store.
- **A ruling made on a visit.** A ruling that adds to the piece the sitting
  waits for is an ask on that piece, whose gate is open already. A ruling that
  sends other work gets no gate while that one is open: the promise refuses a
  second piece, and the sitting tells the operator that the work brings no
  return of its own. Work on a PR the conversation holds stays held until the
  sitting is back.

So the return needs no change to Gas City. A Gas City session wait, which an
earlier revision used for the promise, would need Gas City to change in these
places: an attach that starts a sleeping session cancels its waits (gc-gspdoo),
a reset cancels them as stale (gc-lwa1vp), and a ready wait does not wake a
session that slept at the end of its idle window (gc-qxq03t, found by unit 1's
probe and recorded on tk-u41ko5k). This effort waits on none of them
(conversation tk-reymwh1).

## 10. The city's own store

Only the landing order reads a PR's own status for a gate, and it is a
rig-scoped order (`scope = "rig"` in `orders/pr-reconcile.toml`): it reads each
rig's store and never the city's own. Since PR #1615 main has no other merge
path and no `pending_through_merge` switch, so the verb tells where it can
promise by one test, that the bead's store is a rig's. In the city's own store
nothing would resolve a gate. There the promise refuses, the sign-off files no
gate, and a stay is today's stay, unchanged: the conversation waits on its work
through an edge and comes back when the work closes, and a stay on the
conversation's own subject stays refused.

## 11. What the pack's pages say

Each page and skill that describes a stay states the rule and when a stay comes
back, by section 3's table, with section 10's rule for the city's own store:

- **`docs/human-engagement.md`**, its section "A sitting that stays for the
  return": sections 1 to 7, 9 and 10 of this design, in the page's words.
- **The converse prompt's "End or stay?"** (its decision 4): the sitting says
  when the stay would come back, by the table, that it comes back for one piece
  of work, and that it will come back to discuss the result whatever it finds.
  On an entry that reads `returned`, the prompt runs the return.
- **`converse-stay`**: the stay's two forms, the sitting's own
  `gctk gate create`, a stay that stopped short and its re-run, the return's
  steps with its summary and the three lines it closes with, a ruling made on
  a visit, settling and ending.
- **`converse-settle`**: send, with what was agreed written as a list of items
  the return can check, then the promise of the piece the sitting sent, then
  the stay; what the sitting tells the operator about other work it sent; and
  a stay on the conversation's own subject.
- **`converse-hold`**: the hold of a returned exchange, recorded in one write
  guarded on the claim the entry took, and the lift of the PR's merge hold only
  on the operator's settlement.
- **`docs/product-goals.md`** gains one sentence in its "Human gates and
  conversations" surface: a conversation the operator asks to stay with its work
  comes back to discuss it before their next decision about that work, never
  after it. That is a goal the PM check judges a change to a stay against.

The words unit rewrites the passages tk-lv4r5mv wrote for the old path once, on
the effort's branch brought current with main.

This design's own change states the rule in `docs/architecture.md` at the
document's altitude: when a stay comes back, that it comes back through its own
task, that the landing order holds the PR's merge and releases the
conversation once the PR is left with the operator's part, and that the return
always waits for the operator. How the conversation waits and how the landing
order releases it, the gate of section 2, stays in this design until the units
build it, and then in `docs/gctk-architecture.md` and
`docs/human-engagement.md` (section 14). Its Debt names the stay that comes
back only when its work closes, with tk-vrg93t0 as the work that retires it,
and the words unit narrows that entry to the city's own store. The release is
the gate's close, so step 9 of "How work moves" keeps `closed` as the one
signal waiting parties key on.

## 12. What the earlier revisions built, and what this keeps

The first draft kept the PR a draft until the sitting posted a marked reading.
The next revision had the return always wait for the operator and promised it
with a Gas City session wait. The revision before this one moved the promise
onto a gate of the pack's own, and around it built a rule for who promises
which work, a convoy wait for work the stay promised nothing on, and an account
of each stop.

What those revisions dropped stays dropped: the reading's marker and the rounds
counted from it, the `reading` key of `gctk pr status`, the evaluator's
condition for a stay, the draft kept for the reading, the entry's `ready`
values, the clean return's lift of the hold, and the session wait with its Gas
City prerequisite. This revision drops more:

- **Several pieces of work in one stay.** With one gate for each piece that
  closed on its own, a PR was held while its sitting slept on another piece,
  and the conversation stalled whenever that other piece could not move until
  the held PR landed. With the gates closed together, a piece that had no PR
  yet was left unheld. A conversation now waits on one gate.
- **Every convoy.** The wait for settled work to land goes, and so does the
  wait for the subject's close, whose edge stayed on the conversation when new
  work was sent. PR #1515's convoy on the subject goes with them.
- **The promise of each PR the conversation holds, and the stay that promises
  nothing.** A stay needs a gate, and a call that sends nothing refuses without
  one, so no stay comes back only after the merge without saying so.
- **The third close**, of a gate nothing waits on once it is five minutes old.
  Such a gate closes with its work and holds nothing.
- **The removal of the conversation's edges onto closed gates and convoys.** The
  entry reads a stay by the one gate its newest line names.

It keeps the gate and its one definition, the promise as the one act that says
what a stay comes back for, the hold put on before the sitting wakes, the
merge-queue boundary, and today's stay in the city's own store.

The text the operator read on 2026-11-20 called the gate a return gate, with an
await type `stay-return` and a verb `gctk gate return`, and gave its moment as
the ready transition's conditions less the draft flag. "Return" named what
follows a gate's close, which is no part of a bd gate, and that list kept the
moment beside the status the pack already computes. A new word for the state,
`ready-for-approval`, was weighed and dropped for `needs-review`.

A flag on the sign-off that named the piece was weighed against the promise.
The sign-off's `--waiting-on` cannot carry it, because that flag makes the
subject wait on a bead and arms the subject's closer, whatever the stay comes
back for. A flag of its own would fold the promise into the stay's call. The
verb stays the one way, because a sitting can run it at any moment and not only
as it signs off.

## 13. The surface this adds

Each item's search is in [gas-city-search.md](gas-city-search.md).

- **The gate type `gctk:needs-review`**, a bd gate type of the pack's own,
  defined in `services/gctk/gate` (section 2). It adds no metadata key, because
  its await type, its await id and its edges are bd's own fields. As a pack
  noun it needs a warrant (`docs/foundation.md`, "Boundaries"), which unit 1
  adds to `docs/warrants.md` with the gate. The warrant names Gas City's
  session wait as the primitive the gate stands in for. It retires when that
  wait keeps a promise through an attach and a reset and wakes a sitting that
  slept at the end of its idle window, or when bd or Gas City ships a gate that
  resolves when a PR is left with only a person's part.
- **The verb `gctk gate create`**, of the agent class under a new noun, `gate`,
  which owns the pack's gate types. It takes bd's own flags, `--type`,
  `--await-id` and `--blocks`, as rule 2 of section 1 gives them, and is bd's
  `gate create` with the pack's checks in front.
- **The PR's own status**, one more view in the status owner
  (`services/gctk/prstatus`), over the answer and the facts the label reads
  (section 3). The landing order is handed it as it is handed the labels
  (`Labels` in `services/gctk/pr/labels.go`), because `prstatus` imports `pr`.
  It adds no key to `gctk pr status`.
- **The landing order** (`gctk pr reconcile`) gains one step where it decides
  an open PR at its head: for an open gate that names the PR's bead, the hold
  and the gate's resolve once the own status is `needs-review` or `merging`,
  and no merge request while such a gate is open. In every pass it resolves a
  gate whose work has closed.
- **The park rule and the rule for how far the city carries a bead** ask the
  package whether the city closes a gate (section 2).
- **`converse-signoff.sh --stay`**, an existing mode, on the review path files
  the gate through the verb on the work its own call sends, keeps an open gate
  the sitting filed, refuses a call that sends nothing when the conversation
  has none, and no longer makes the conversation wait on its `--waiting-on`
  beads or on the ruling's ask. It takes a stay on the conversation's own
  subject and on the PR whose merge the conversation holds. It gains no flag.
- **`converse-entry.sh`** reads a stay by the gate its newest `staying:` line
  names. It gains no entry and no value.

None of the surface is a store, a lifecycle state or a metadata key. The gate's
package, the verb and the own status are Go in gctk, and the landing order's
step is Go in its pr domain. The sign-off and the entry change what an existing
mode writes and what the entry reads, and add no verb, mode or key, so the
build changes them in place under the rule for a script that already exists
(`AGENTS.md`, "New pack code is written in Go, in gctk").

What the two scripts do today, at the base, which the build changes:
`converse-signoff.sh --stay` needs a `--waiting-on` bead or `--rework`, makes
the conversation wait through a `blocks` edge on each `--waiting-on` bead that
is no gate and on the ruling's ask, and refuses the subject, work in another
store, and a bead that waits on the conversation. The same `--waiting-on` makes
the subject wait on the bead and arms the subject's closer. The headline's
writer (`takeaway` in `assets/scripts/gc-helm.sh` at the base, and
`gctk bead takeaway` on main) writes an edge for each wait it is given, apart
from the bead itself and a rider already landed on its branch, and removes
none. `converse-entry.sh` reads a stay off its `staying:` lines and the
conversation's own `blocks` edges, and reads a claimed conversation that waits
on open work with neither a `staying:` nor a `holding:` line as `unreadable`.

## 14. The units

Each of units 1 to 3 lands on `integration/tk-vrg93t0`, keeps the suite green
and leaves the city working. In the city's own store, nothing they add runs.

| Unit | What it does | Waits on | Releases |
|---|---|---|---|
| 1. The gate (gctk) | The package `services/gctk/gate`: the type `gctk:needs-review` and the gate's title, the rule that the city closes a gate of that type, the gate's filing, and its resolve with its reason. The verb `gctk gate create --type gctk:needs-review --await-id <work-bead-id> --blocks <conversation-bead-id>`, which files the gate with one `bd gate create`, finds the open one for that bead, and makes each refusal of section 2. The PR's own status in `services/gctk/prstatus`, beside the label's rule: the same answer and facts, with what holds the PR set aside and the city's work ranked before an approval (section 3). In the landing order, where it decides an open PR at its head: for each open gate whose await id is the bead, once the own status is `needs-review` or `merging`, the hold when its conversation is open or in progress, then the gate's resolve, and nothing else requested of that PR in that pass; no merge request while such a gate is open, looked for again at the last read before a merge request; and in every pass, the resolve of an open gate whose bead has closed. The park rule's `gateHold` and the rule for how far the city carries a bead ask the package. The landing order is handed the own status as it is handed the labels. `docs/gctk-architecture.md` gains the verb's row, the `gate` noun, the own status and the order's new step, and `docs/warrants.md` the gate's warrant. Tests: the gate the verb files and the one it finds; each refusal; the own status for each row of section 3's table, among them a draft, a pending check, a failed check, an open send-back, one that waits on other work, an attached review run and an approved PR the city is still changing, and a question, a conversation and a hand hold that change none of them; the hold and the resolve for new work, for a rework and for the subject; a send-back the run answers with no push resolves the gate on a ready PR, and an approval from an earlier round does not merge it; a gate filed on a PR that already reads `needs-review` resolves on the next pass; a PR found ready under an open gate gets the hold and the resolve and no merge request; a gate past the first 50 open gates in the store is resolved; a gate whose conversation has closed resolves with no hold; a write that does not land ends that PR's pass and is retried; a PR in its base's merge queue is left to GitHub; a gate whose bead has closed resolves; a conversation that waits on its gate reads as staying and as advancing, and so does the PR it holds, and a park reads as a person's. | this rewrite (tk-1gsaloy), pull request 1612 (tk-ssm8qns.27) and tk-oknae24, which brings the branch current once that has landed | unit 2, once tk-ps47p6p brings the branch current |
| 2. The stay carries its gate, and the entry reads it (scripts) | `converse-signoff.sh --stay` on the review path: after the send its ruling makes and the waits its call writes, the gate through `gctk gate create` on the bead that send reached, when the conversation has no open gate; an open gate the sitting filed kept; a call that sends nothing refused before any write when the conversation has no open gate, with a message that says when a gate of the conversation's has closed since, so the work is back; no edge from the conversation onto a `--waiting-on` bead and no wait on the ruling's ask; the second `staying:` line naming the gate; a stay on the subject and on the PR whose merge the conversation holds; `--accept` beside `--stay`. In the city's own store, the stay as it is today. `converse-entry.sh`: `waiting` while the gate the newest `staying:` line names is open and `returned` once it has closed; `WORK` as that gate's await id; a claimed conversation that waits on an open `gctk:needs-review` gate with no `staying:` or `holding:` line read as `interrupted`, a stay the sitting has promised and not yet made. Tests, one per row of section 3 and one for section 10: what the sign-off writes, the gate it files after its own send, a promised gate kept, the refusal with no gate, a stop at each point of the call and the re-run that finishes it, the entry before and after the gate closes, a restart between the promise and the stay, and the stay in the city's own store. | unit 1 and tk-ps47p6p | unit 3, once tk-imuvm2j brings the branch current |
| 3. The words | The converse prompt's "End or stay?" and its handling of a return, with the return's summary of each agreed item and the three lines it closes with; `converse-stay`, `converse-settle` and `converse-hold` (section 11); `docs/human-engagement.md`; the sentence in `docs/product-goals.md`; the skill-needs pins of the table and of each example's call through the real parsers, among them the stay's call in each form, the sitting's `gctk gate create`, and a ruling made on a visit; the return's hold write, guarded on the claim the entry took; the stay's Debt entry in `docs/architecture.md`, narrowed to the city's own store. | unit 2 and tk-imuvm2j | the landing |

The initiative's "Done when" asks for a test of each row of the table. Units 1
and 2 hold the rows in their suites, and unit 3 pins them in the words.

No unit builds terminal access: a wrapper around engage's attach, richer tab
status, the subject's PR in the terminal, and finding and cleaning up terminals
are epic tk-uipsrmt's, which is held for prioritization and blocks nothing here.

## 15. Edges and notes

- The implementation child (tk-y4iqs8j) filed units 1 to 3 (tk-u41ko5k,
  tk-4mknrrf and tk-r06d403) the way it was filed itself
  (`docs/design-convoy.md`), with `target=integration/tk-vrg93t0` in each
  create. The landing bead (tk-vrg93t0) and the summary task (tk-pgxs4zx) wait on
  every unit through a `blocks` edge, and each unit waits on its row through a
  `blocks` edge and is armed. This rewrite (tk-1gsaloy) keeps the units, their
  edges and their arms. Each unit, the landing bead and the summary task also
  wait on it, and each unit's description is rewritten to this design.
- The refinery's hand-offs bring the effort's branch current before each unit:
  tk-jj483vu before unit 1, which has closed, tk-oknae24 once pull request 1612
  (tk-ssm8qns.27) has landed, which unit 1 waits on, tk-ps47p6p once unit 1
  lands, and tk-imuvm2j once unit 2 lands. Main carries the rule that new pack
  code is written in Go, in gctk, and since PR #1563 the sign-off's
  `--rework-waiting-on` (section 3). Since PR #1615 main carries no old merge
  path and no `pending_through_merge` switch, which section 10 is written for.
  Since PR #1559 the landing order runs once a minute and decides each PR on
  the read the PR watch saved, and with pull request 1612 a bead's standing has
  one owner, which holds the park rule (section 2).
- The human gates that held unit 1 (tk-p5pkn4k, key `stay-wake-probe`) and
  unit 3 (tk-50kk1fa, key `gas-city-keeps-waits`) are answered by the ruling of
  2026-11-18, and no gate replaces them.
- A note on tk-35ob5gq, the city board's reading of a stay: the hold the landing
  order puts on is the conversation's existing edge, so the board reads it as
  it reads engage's. A conversation that waits on its gate has an open wait of
  its own, which `conversation.Staying` reads as a stay, and unit 1 has the
  park rule read the gate as the city's.
- tk-lfcb8ug holds the life cycle in which a conversation stays available
  until its subject closes (section 7). It waits on nothing here, and nothing
  here waits on it.
