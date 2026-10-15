---
name: Steering — how the operator steers the city's work
description: How the operator steers the city's work, deciding which work runs and when. It states the intake rule for which beads may be routed or armed to a work pool, the placement=pending marker that holds every other bead and the writers that set it, the emergency check, the placement sitting's queue (gc-helm.sh unplaced) and how the sitting places a bead. It states the park, an ordinary blocker on a bead that holds work under the bead that has not started while work in flight finishes, with the moves that make and release a park and what a park holds and leaves running. Read it before writing anything that files, routes or arms new work, before parking or releasing work, or before changing a reader that must see a park.
---

# Steering

The operator steers the city's capacity by deciding which work runs, and when.
New work reaches a work pool once the operator has placed it, and not on its
own. An epic is an ordinary bead, and each move acts on a bead and everything
under it, with no logic for epics alone. A park holds work under a bead that
has not started and leaves work already in flight running. Which work it holds,
and which it does not, is [below](#what-a-park-holds).

## Scope

**Mandate.** Which beads may enter a work pool and what holds the rest: the
intake rule, the `placement=pending` marker and the writers that set it, the
emergency check, the placement sitting's queue, and how a bead is placed. How
the operator decides when work runs: the steering moves, the state each move
writes, what that state holds and what it leaves running, and how each move is
released.

**Boundaries.** The design that decides how work is steered by epic, with the
alternatives it rejected and the units that build it, is
[specs/tk-rl8gz4b.2/steer-by-epic.md](../specs/tk-rl8gz4b.2/steer-by-epic.md);
this page states what runs. What an epic is, what it carries, and when it
closes, is [epics.md](epics.md). How a pool claims routed work, and how bd's
blocked flag cascades and a pool reads it, is
[gascity-routing-model.md](gascity-routing-model.md). The hold, the demand and
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
Naming a task parks the bead until the task closes. A park takes one form or the
other, never both.

Either form reads the edge back off the bead before it reports success, and then
prints what the park holds and what it leaves running.

`park` refuses:

- a bead in flight, because its own edge would hold its merge and its close
  (next section);
- a demand gate as the bead to wait on. A demand gate is a wait on the
  operator's decision, and the operator ruled that such a wait does not hold
  armed work. The refusal names the text form, whose gate can name the decision
  the park waits for;
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
reach a poured workflow, and the bead is in flight, so load-context reads only
its own blockers and the rebuild runs. When that sling fails, the script arms a
retry, which deferred dispatch slings once the bead's own blockers close.

### What a park holds

A park holds this work that has not started, in the bead and under it:

- the bead itself and every pool-routed member, because the pool offers only
  what `bd ready` returns;
- a member placed under the bead later, through the same cascade;
- an armed member, because deferred dispatch slings an armed bead only when no
  blocker holds it or any of its ancestors (`assets/scripts/hold-lib.sh`);
- the bead or a member slung by hand, and a workflow poured before the park
  that has not passed load-context. `gc sling --on` pours without reading any
  edge, so the hold is read where such a run starts. The load-context step of
  mol-polecat-work, and of mol-design-convoy, runs
  `assets/scripts/held-work-gate.sh`, which reads the same hold and declines a
  held bead: it arms a re-dispatch that deferred dispatch fires once nothing
  holds the bead, then cancels the run through gascity. A cancelled root is
  closed, so it does not stand in the way of the re-dispatch's pour;
- an Accept. `gc-helm.sh accept` refuses a held subject and names what holds
  it, so the operator releases the hold before the work starts.

An armed member in flight keeps running, such as a rejected handoff armed for a
retry: once a bead carries `branch`, `merge_result` or `rejection_reason`,
deferred dispatch and load-context read only its own blockers.

A blocker of the bead's own still holds a bead in flight. mol-polecat-work's
submit-and-exit reads the hold again before the hand-off, for a blocker that
landed on the bead while it was built. On one, the gate keeps the pushed branch,
arms the re-dispatch and cancels the run, so the hand-off never makes the bead
an anchor with an open blocker of its own, whose merge `merge.sh` would hold
and whose close bd would refuse. The re-dispatch resumes the branch once the
blocker closes.

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
