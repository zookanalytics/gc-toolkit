---
name: Steering — how the operator steers the city's work
description: How the operator steers the city's work, deciding which work runs and when. It states the intake rule for which beads may be routed or armed to a work pool, the placement=pending marker that holds every other bead and the writers that set it, the emergency check, the placement sitting's queue (gc-helm.sh unplaced) and how the sitting places a bead. It states the park, an ordinary blocker on a bead that holds work under the bead that has not started while work in flight finishes, with the moves that make and release a park and what a park holds and leaves running. It states priority flow: a bead's priority is the priority of the bead it follows plus its own shift, the move that sets either, settle, where PR-finishing work ranks and why it never has a parent, the pass that catches raw writes, and the lock the three share. Read it before writing anything that files, routes or arms new work or PR-finishing work, before parking or releasing work, before writing a bead's priority, or before changing a reader that must see a park.
---

# Steering

The operator steers the city's capacity by deciding which work runs, and when.
New work reaches a work pool once the operator has placed it, and not on its
own. An epic is an ordinary bead, and each move acts on a bead and everything
under it, with no logic for epics alone. A park holds work under a bead that
has not started and leaves work already in flight running. Which work it holds,
and which it does not, is [below](#what-a-park-holds). A priority decides the
order work queues in, and work under a bead follows the bead's priority, moved
sooner or later by a shift of its own ([Priority](#priority)).

## Scope

**Mandate.** Which beads may enter a work pool and what holds the rest: the
intake rule, the `placement=pending` marker and the writers that set it, the
emergency check, the placement sitting's queue, and how a bead is placed. How
the operator decides when work runs: the steering moves, the state each move
writes, what that state holds and what it leaves running, and how each move is
released. The order work queues in: how a bead's priority is derived, where it
is written, and the writers that keep it there, the creators of PR-finishing
work among them.

**Boundaries.** The design that decides how work is steered by epic, with the
alternatives it rejected and the units that build it, is
[specs/tk-rl8gz4b.2/steer-by-epic.md](../specs/tk-rl8gz4b.2/steer-by-epic.md);
this page states what runs. What an epic is, what it carries, and when it
closes, is [epics.md](epics.md). How a pool claims routed work, and how bd's
blocked flag cascades and a pool reads it, is
[gascity/routing-model.md](gascity/routing-model.md). The hold, the demand and
the shape law a park follows are invariant I1 in
[component-model.md](component-model.md#i1-in-full-the-hold-the-demand-and-the-shape-law).
The first reaction's method is `agents/proactive/prompt.template.md`, and who
may route, arm or hold a bead, or make each steering move, is
[authority-map.md](authority-map.md).

## The intake rule

A bead may be routed or armed to a work pool only when one of these holds:

- it is a member of an epic, which means it has a parent-child parent;
- it is PR-finishing work of an anchor, which means it carries `anchor_bead`;
- it is an emergency, a red main or a broken gate, checked rather than asserted;
- the operator routed it, through a sitting, a hand sling or an Accept.

Every other bead waits for placement. A bead held this way carries
`placement=pending` and no route and no arm, so no pool is offered it.

## The writers that hold new work

Each writer that files or disposes new work follows the rule.

- **The first reaction** (`assets/scripts/first-reaction-dispose.sh`). It still
  reacts to every finding, because its card is the placement sitting's triage.
  Its actionable exit routes a member, PR-finishing work or a confirmed
  emergency. It marks any other bead `placement=pending` and releases it with no
  route. The blocked exit's `--then-route` arms a dispatch only for a bead the
  rule admits. Any other bead it marks, and arms nothing, while its wait still
  lands as a `blocks` edge. The close exit keeps its validating closer, because a
  close shrinks the queue. Work that is a named agent's own (`--assign`,
  `--then-assign`) is not pool work, so the rule does not read it.
- **The witness** files mail about a pack defect as a bug marked
  `placement=pending` and routed to no pool (`formulas/mol-witness-patrol.toml`,
  the `bug-file` block).
- **The feedback distiller** files each prompt-update and engineering bead
  marked `placement=pending` and routed to no pool
  (`formulas/mol-feedback-distiller.toml`, the file-and-dispatch step). The
  operator still reviews each one at its PR once a polecat builds it.

No held bead is ever readable without its marker. The witness and the
distiller write it in the create, and the first reaction writes it and reads
it back before the release.

A first reaction's subject can still carry `gc.execution_routed_to`, the stamp
a pour leaves, after the pour's workflow has ended. The queue reads that stamp
as a live pour, so the release that holds the bead clears it. When the stamp
survives on a held bead, `gc-helm.sh takeaway` fails the release, and the first
reaction stops without recording its disposition, so a re-run finishes the hold.

## The emergency check

The first reaction claims an emergency with `--emergency <check>`, on the
actionable exit or on the blocked exit with `--then-route`. The claim names the
check on main whose failure the bead is about: a check run's name or a commit
status's context. It is checked against the head of the default branch of the
subject's repository, read from GitHub through the rig checkout's origin. A
check run by that name that concluded `failure`, `timed_out` or
`startup_failure`, or a commit status with that context of `failure` or
`error`, confirms it. A run still going, or one cancelled by a newer push, does
not. Another check failing on main confirms nothing, so a flaky or unrelated red
check cannot carry a routine bead past placement at P0. Every check run and
commit status on the head is read, across all their pages. Each GitHub read is
bounded in time, and a read that does not answer confirms nothing.

A confirmed emergency is written P0, the priority is read back, and then the
bead is routed or armed. A claim the check does not confirm, including one the
check cannot run, is held for placement like any other bead, and the note it
leaves on the bead says what the check found, naming any other check that fails
there. A broken gate counts when it shows as a failing check on main. A latent
hazard, a doctor finding marked blocking, or a failure on one PR's branch does
not.

## The placement sitting's queue

`gc-helm.sh unplaced` lists the queue. It reads every rig store the city has,
skips a suspended rig's store and says so, and orders the beads by priority,
then age. It writes nothing. When a store does not answer, it names that store
and exits 4 after printing the rest. A skipped rig leaves the exit at 0,
because a suspended rig is the operator's choice. `--json` prints one object
for a caller: the queue as `beads`, the suspended rigs it skipped as `skipped`,
and the rigs whose store did not answer as `unread`, so a caller can tell a
partial queue from the whole one.

`assets/scripts/placement.sh` is the one definition of a bead in the queue: it
carries `placement=pending`, and nothing has placed it since. A parent, a route,
an arm, an assignee or a live pour each places a bead, whether or not the marker
was cleared. The same definition serves the queue's other readers:

- the liveness sweep names such a bead's wait, so it does not report the bead as
  an unnamed wait;
- the claim-time re-check of a sweep visit (`liveness-recheck.sh`) names the
  same wait, so a visit filed before intake held the bead does not put it on
  that sitting's agenda as well;
- `doctor/check-blocked-work-armed` owes such a bead no arm, because its
  dispatch is the route the sitting gives it;
- the proactive scan files no first reaction for such a bead, because its next
  move is the sitting's.

## Placing a bead

For each bead in the queue, the sitting does one of three things.

- **Place it under an epic.** Give it the epic as its parent
  (`gc bd update <bead> --parent <epic>`), then route it to its pool
  (`gc sling <rig>/gc-toolkit.polecat <bead>`). A park on the epic holds it from
  then on, through bd's parent-child cascade.
- **Route it on its own.** Route it to its pool with the same sling, and give it
  no parent.
- **Close it**, when the work is not wanted.

A placed bead leaves the queue as soon as it has a parent or a route. Clearing
the marker (`gc bd update <bead> --unset-metadata placement`) keeps the bead's
record honest, and nothing waits on it.

## A park

A park is an ordinary blocker: a `blocks` edge from the parked bead onto an open
bead in the same store. bd marks a bead blocked when it, or any of its
parent-child ancestors, has an open blocker, and `bd ready` leaves a blocked
bead out. So a park on an epic takes the epic and every member under it out of
`bd ready`. No reader tells a park from any other blocker, and none needs to.

### Parking a bead

```
gc-helm.sh park <bead-id> "<text>" [--body "<detail>"]
gc-helm.sh park <bead-id> --waiting-on <bead-id>
```

The text form files a gate of its own and makes the bead wait on it. The gate is
`issue_type=gate`, titled with the text, which says why the bead is parked and
what releases it. The text is required. It is one line of at most 140
characters, refused over the cap rather than cut, the rule a demand's title
follows. `--body` is the gate's description. The gate carries no await type, no
`gc.demand_for` and no hold marker, so no sweep closes or visits it. It is filed
in the bead's own store, because bd resolves an edge only within one store, and
it is born with the bead's edge in one write. Who parked the bead, and when, are
the gate's creator and creation time. Re-running the text form with the same
text files no second gate. A `--body` on the re-run becomes that gate's
description, which is how the detail of a park is corrected.

`--waiting-on` parks the bead behind a bead that already exists and files no
gate. Naming another park's gate parks one more bead for the same reason.
Naming a task parks the bead until the task closes, and naming a human gate
parks it until a person clears the gate. A park takes one form or the other,
never both.

Either form reads the edge back off the bead before it reports success, and then
prints what the park holds and what it leaves running.

`park` refuses:

- a bead in flight, because its own edge would hold its merge and its close
  (next section);
- a closed bead to park or to wait on, a bead in another store to wait on, and
  one of the bead's own parts to wait on, since each edge would hold nothing or
  bd refuses it.

### In flight

A bead is in flight once work on it has started, which any of these shows:

- someone has claimed it, so its status is `in_progress` or `hooked`, bd's
  claim statuses;
- it carries `branch`, `merge_result` or `rejection_reason`;
- a workflow poured for it has passed load-context. A pour sets its own root
  `in_progress` and never claims the bead it was poured for, so the bead's
  status does not show that run.

A park leaves work in flight running:

- A claimed bead stays with whoever claimed it. `bd ready` never offers a
  claimed bead, so the cascade, which works by keeping beads out of `bd ready`,
  changes nothing for it.
- A poured workflow is out of the cascade's reach. Its root has no parent, and
  its steps hang off the root by `tracks` edges, which bd does not cascade.
- PR-finishing work, such as a review rework, a merge-in, a red-check fix or a
  validation pass, carries `anchor_bead` and a `blocks` edge to its anchor,
  never a parent edge.
- An anchor under a parked epic still merges and closes. `merge.sh` reads the
  anchor's own blockers, its children and the beads that name its PR, never its
  parent. bd refuses a close only for open children or a live direct blocker.

That is why `park` refuses a bead in flight. The bead's own edge would be a live
direct blocker, so `merge.sh` would hold its merge and bd would refuse its close.
Parking its parent instead holds the rest of the parent's work and leaves the PR
landing.

A park leaves a rejected handoff running too. When the refinery rejects a
handed-off bead, `rejection-repool.sh` records the `rejection_reason` on it and
dispatches the rebuild as a fresh `mol-polecat-work` pour. The cascade does not
reach a poured workflow, and load-context reads only the bead's own blockers,
so the rebuild runs. When that sling fails, the script arms a retry, which
deferred dispatch slings once the bead's own blockers close.

### What a park holds

A park holds this work that has not started, in the bead and under it:

- the bead itself and every pool-routed member, because the pool offers only
  what `bd ready` returns;
- a member placed under the bead later, through the same cascade;
- an armed member, because deferred dispatch slings an armed bead only when no
  blocker holds it or any of its ancestors (`assets/scripts/hold-lib.sh`);
- a sling of the parked bead itself. mol-polecat-work's load-context refuses a
  work bead that has an open blocker of its own: it holds the molecule and arms
  a re-dispatch that fires once the bead's blockers close.

An armed member in flight keeps running, such as a rejected handoff armed for a
retry: once a bead carries `branch`, `merge_result` or `rejection_reason`,
deferred dispatch reads only its own blockers.

A park does not hold a member slung by hand, or a workflow poured before the
park, because `gc sling --on` pours without reading any edge and load-context
reads no ancestor's blockers. `park` names the poured workflows it leaves
unheld. A member that must not start gets a park of its own, since
mol-polecat-work's load-context refuses a bead with an open blocker of its own.

### Releasing a park

Unparking closes the gate (`gc bd close <gate>`), which releases every bead that
waits on it, as closing any blocker does. To release one bead from a gate that
holds several, remove that bead's edge (`gc bd dep remove <bead> <gate>`). The
operator closes a park gate once it holds nothing. A released bead returns to
`bd ready` on the next read, so the pool offers it again if it is routed, and
its arm fires if it is armed and no other blocker holds it or any of its
ancestors.

### What reads a park as a fault

These readers report a held bead as a fault:

- `doctor/check-blocked-work-armed` reads `bd blocked`, which lists each member
  a park holds, and flags one that has neither a route nor an arm. Its remedy,
  arming the member, leaves the member held until the park is released, since
  deferred dispatch reads its ancestors' blockers.
- The helm board files an epic whose open children sit idle, with nothing in
  flight, under STALLED, so a parked epic reads as stalled. The board's word
  "parked" means a bead carrying a takeaway, not a park.

### Where a park goes

A blocker on a bead with children holds every part of it, so such a bead carries
one only for a wait that belongs to all of its parts: a park on an epic, or a
prerequisite of all of an epic's work. A wait that belongs to one part goes on
that part. This is I1's shape law in
[component-model.md](component-model.md#i1-in-full-the-hold-the-demand-and-the-shape-law).

## Priority

A pool claims the ready bead with the most urgent priority first, and within a
level the oldest ([gascity/routing-model.md](gascity/routing-model.md#the-read-side-the-claim-predicate)).
So a bead's priority decides where it queues.

### The rule

A bead's priority is the priority of the bead it follows, plus its own shift,
kept within P0 to P4 at each level.

- A member follows its parent. A member with several parents follows the most
  urgent one, the parent with the lowest P-number.
- PR-finishing work, a bead carrying `anchor_bead`, follows its anchor. Once
  the anchor's PR is approved, it runs at P0 whatever its shift
  ([PR-finishing work](#pr-finishing-work)).
- A workflow's input convoy, root and steps follow the bead the workflow was
  poured for, at shift 0. They carry no shift of their own. An input convoy
  follows the bead it tracks only when it tracks exactly one; a convoy that
  tracks several follows none of them.
- A bead that follows nothing has its priority set directly. An epic with no
  parent is such a bead, and its priority is where its work starts.

A bead is followed only when its own store holds it and it is neither closed
nor pinned, so a member of a closed epic follows nothing and keeps the priority
it last had.

The shift is a signed integer in the key `priority_shift`: +1 is one level
later, -1 is one level sooner, and absent or empty reads as 0. Shifts add up
through levels, and each level stops at P0 and P4. Under a P1 epic, a member
with no shift queues at P1, a member at shift -1 at P0, and a member at shift +2
at P3. Under a P0 epic, a feature at shift -1 stays at P0, and a task under it
at shift +1 queues at P1. A shift that is not a signed integer makes its bead
unreadable, and every bead that follows it, so no writer computes a priority
from it.

`assets/scripts/priority-lib.sh` is the one definition of the rule, and
`priority-lib.fixture.json` holds the cases any copy of it must agree with.

### Where a priority is written

The bd priority field holds the priority a bead competes at, because a claim
reads that field and a pour copies it once into the workflow's convoy, root and
steps. So the field of a bead that follows something is computed, never chosen:
a hand edit of it is overwritten at the bead's next computation, and the way to
rank such a bead is its shift.

A writer rewrites a bead's computed priority only while the bead is open,
blocked or deferred. A claim already made stands, so a bead `in_progress` or
`hooked` keeps the priority it was claimed at, and a closed or pinned bead is
never written. A workflow root is the exception: its pour sets it `in_progress`
with no claim behind it, and work the workflow fans out later takes the root's
priority, so the root is written while it is live. A move's input is not a
computed priority. The move writes its P-value or its shift to the bead it
moves even when that bead is claimed, because everything that follows the bead
is computed from that input.

Each writer reads the store asking for every class of bead a listing hides by
default: gates, infrastructure beads, template molecules and ephemeral rows. A
bead of any class can be followed, so the move, settle and the pass read the
same beads and compute the same priority for each.

### Moving a priority

```
gc-helm.sh priority <bead-id> <P0-P4> [--dry-run]
gc-helm.sh priority <bead-id> --shift <±n> [--dry-run]
```

A P-value sets the priority of a bead that follows nothing. `--shift` sets the
shift of a bead that follows a parent or an anchor. A P-value on a bead that
follows something is refused, and the refusal names the shift that lands it
there: for a member of a P1 epic, P3 is `--shift +2`. A shift on a bead that
follows nothing is refused, because nothing is there to shift from. Either form
on a workflow's convoy, root or step is refused, because it takes the priority
of the bead the workflow was poured for, and the refusal names that bead.

The move writes the bead's own input first. It then writes every bead that
follows the bead, directly or through others: the members under it, the
PR-finishing work of each anchor among them, and the live workflow of each,
meaning its input convoy, its root and every open step. Held beads are written
too, so a parked epic's members take a new priority while the park holds them,
and each is at its priority when the park is released. The move reads every
write back. `--dry-run` prints what it would write and writes nothing. The
writer is `assets/scripts/queue-priority.sh move`.

### Settle

`queue-priority.sh settle <bead-id>` computes a bead's priority, writes it to the
bead and to every live workflow poured for it, and reads it back. It exits
non-zero when the priority cannot be computed or does not read back. A bead
that follows nothing keeps its own priority, and its workflows take it.

Every writer that settles a bead before making it claimable does so in one
order. It runs settle first and goes on only once settle exits zero. A sling
then pours a workflow, which copies the bead's priority. A route is then
written on its own, with no priority in it. Until then no pool can claim the
bead, and a move that runs after the settle rewrites the bead itself. Such a
writer computes and writes no priority of its own.

`queue-priority.sh settle <bead-id> --print` computes the same priority, prints
the number and writes nothing. It takes no lock, so no writer writes the number
it prints. A move that ran between that computation and a write would be undone
by the write.

### PR-finishing work

PR-finishing work carries an anchor's built branch to its merge. Its creators
are the scripts that make it claimable:

- `gate-ensure.sh` slings the reviews it files, and the validation passes that
  `pr-facts.sh` and `signoff.sh` file.
- `pr-facts.sh` routes the merge-in of an approved PR that conflicts, the fix
  for a red required check, and the comment rework.
- `pre-open-rebase.sh` routes the merge-in before a PR exists.
- `rework-child.sh` slings the rework that a review verdict or an operator
  ruling asks for.

Each child carries `anchor_bead` and follows its anchor.

**It never has a parent.** Each child is joined to its anchor with a `blocks`
edge and a membership edge, never a parent-child edge, so no cascade reaches
it: a park or a decision hold on the anchor's epic leaves the PR's finishing
work running. The suite of each script that files a child asserts that the
child has no parent.

**Its rank.** Each child is filed with `priority_shift=-1` in its create, so it
is born one level sooner than its anchor. Its priority is:

- P0 once the anchor's PR is approved, whatever its shift;
- otherwise its anchor's priority plus its shift: at -1, P1 for an anchor at P2,
  and P0 for an anchor at P1 or P0.

A child adopted or re-routed later keeps the shift it carries, because after its
birth the shift is its own input, which `gc-helm.sh priority --shift` may have
set.

**Reading the approval.** For the rank, a PR is approved when its anchor rests
in `pull_request` and the posture `pr-facts.sh` records there, `pr_posture`,
reads `approved` at the PR head `pr-facts.sh` last read, `pr_head_oid`. The
posture is a dated key stored as `<posture>@<oid>@<since>`
([state-machine.md](state-machine.md#posture)), so the priority function reads
the part before the first `@` and compares the `<oid>` after it with
`pr_head_oid`. An approval recorded at any other head is for code the PR no
longer carries, so it ranks nothing at P0. An anchor that rests anywhere else
has no open PR to be approved, whatever posture an earlier PR left on it, and
leaving `pull_request` clears `pr_head_oid`, so an anchor that returns counts no
approval until `pr-facts.sh` has read its PR again. The posture is not the approval rule `merge.sh` lands on
(`review-verdict.sh`): an unanswered review comment outranks an approval in the
posture, and a PR whose base requires no approving review reports no review
decision, so either ranks as not approved.

**Where it is written.** Each creator runs `queue-priority.sh settle` on a child
before it makes the child claimable, in the order [Settle](#settle) gives.
`rework-child.sh` and `gate-ensure.sh` then sling the child, and the pour copies
its priority. `pr-facts.sh` and `pre-open-rebase.sh` then route it, in a write
that carries no priority. A child whose priority does not settle is neither
slung nor routed, and the creator's retry settles it: the next pass of the
cadence arm, or the caller of `rework-child.sh` running it again.

**Re-ranked when its rank moves.** The rank moves when the posture or the PR
head `pr-facts.sh` records moves the anchor into or out of an approval at that
head, and when the anchor leaves `pull_request`. Either way the anchor's open
reviews, reworks and validation passes are settled again, with their live
workflows. The anchor's
`pr_finishing_settled` records the rank all of that work last settled at,
`approved` or `unapproved`, and reads `unsettled` while a re-rank is owed. The
write that moves the rank marks the record `unsettled` in the same update: the
posture and head write in `pr-facts.sh`, and every transition out of
`pull_request`, through the lifecycle writer's `exit_sets`
([state-machine.md](state-machine.md#the-machine)). Every pass of `pr-facts.sh`
compares the record of each anchor it reads in `pull_request` with the rank the
priority function gives that anchor, one on a draft PR included: it records a
draft's head though it reads no posture for it. Every full pass does the same
for each live anchor that carries a record and rests anywhere else, whichever
writer moved it there. While the two differ, the pass settles the work, and it
records the rank only once every bead of it has settled. A record naming the
other rank turns `unsettled` before the first settle. So a settle that fails, or a pass that
stops partway, leaves a record that a later pass settles again and that no
return to the other rank reads as settled. `pr-facts.sh` settles the work of an
anchor it moves out of `pull_request` in the pass that moves it, and the next
full pass settles an anchor that another writer moved, such as a repool through
`rejection-repool.sh`. A finding or a visit carries `anchor_bead` too, but no
pool claims it, so that settle leaves it as it is.

### The pass

`orders/queue-priority.toml` runs `queue-priority.sh reconcile` in each rig every
fifteen minutes. The pass reads the beads `bd ready` offers the polecat pool,
ephemeral ones included, as the pool's claim reads them, and settles each one
queued at a priority other than the one it follows, together with its whole
workflow. It is there for the raw writes no writer sees: a hand
`bd update --priority` on an epic, a parent edge written by hand or by
`bd create --parent`, and a bead routed or slung without a settle, which queues
at the priority it was filed with until the pass reaches it. Nothing tells the
pack such a write happened, so the pass looks. It takes only the ids from the
queue and reads each queued bead again, the way settle and the move read beads,
then reads what each queued bead follows, never the whole store. A bead that is
not queued waits for its own writer, or for the pass once it is queued. A pass
settles the most urgent beads first and leaves what its time budget cannot
cover for the next pass.

A queued workflow bead is settled with the bead its workflow was poured for.
The pass also writes the queued bead itself and every bead between it and that
bead, because a workflow poured for a step of another workflow is not one of
the workflows poured for the outer one, and still follows it. A pass whose
writes do not reach a stale queued bead names it and fails, so a bead it cannot
settle is never reported settled.

The pool is the agent that `gc agent list` places in the rig under the name
`polecat`. That agent's name carries the binding the city imports the pack
under, which the pack cannot know, and a queue read under any other name reads
back empty. So a pass that cannot read the roster, or finds no such agent in
the rig, or finds several, fails and reads no queue.

### The lock

The move, settle and the pass take one lock per store, a `flock` on
`queue-priority.lock` in the store's `.beads` directory, the path every caller
names the same way. A pass or a settle that read an old priority therefore
cannot write it back after a move. The move and settle wait for the lock, and a
pass that finds it held skips its tick.

The writer that holds the lock records its pid and the time it took the lock in
`queue-priority.holder` beside it, and clears the record when it exits, while it
still holds the lock. A pass that finds the lock held fails, reporting the lock
wedged, only when the writer the record names is still running and took the
lock longer ago than the stall bound (`QUEUE_PRIORITY_LOCK_STALL_SECS`, 900
seconds, above the order's timeout). A writer records itself only after it
takes the lock, so a record whose writer has exited is not the holder's: the
pass skips its tick.
