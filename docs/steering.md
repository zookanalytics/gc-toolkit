---
name: Steering — how the operator decides when work runs
description: The model the operator steers polecat capacity with. A park is an ordinary blocker on a bead, which holds work under the bead that has not started while work in flight finishes. Covers the moves that make and release a park, what a park holds and what it leaves running. Read it before parking or releasing work, or before changing a reader that must see a park.
---

# Steering

The operator steers polecat capacity by deciding when work runs. An epic is an
ordinary bead, and each move acts on a bead and everything under it, with no
logic for epics alone. A park holds work under a bead that has not started and
leaves work already in flight running. Which work it holds, and which it does
not, is [below](#what-a-park-holds).

## Scope

**Mandate.** How the operator decides when work runs: the steering moves, the
state each move writes, what that state holds and what it leaves running, and
how each move is released.

**Boundaries.** How bd's blocked flag cascades, and how a pool reads it, is
[gascity-routing-model.md](gascity-routing-model.md). The hold, the demand and
the shape law a park follows are invariant I1 in
[component-model.md](component-model.md#i1-in-full-the-hold-the-demand-and-the-shape-law).
Who may make each move is [authority-map.md](authority-map.md). What an epic is,
and when it closes, is [epics.md](epics.md). The design behind this model, with
the alternatives it rejected and the work it still owes, is
[the steer-by-epic design](../specs/tk-rl8gz4b.2/steer-by-epic.md).

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
the gate's creator and creation time.

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

A bead is in flight once work on it has started. It carries `branch`,
`merge_result` or `rejection_reason`, or a workflow poured for it has passed
load-context. A park leaves work in flight running:

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

A park does hold a rejected handoff. When the refinery rejects a handed-off
bead, it routes the work bead itself back to the polecat pool, and a member is
inside the cascade, so the rework waits for the park's release.

### What a park holds

A park holds this work that has not started, in the bead and under it:

- the bead itself and every pool-routed member, because the pool offers only
  what `bd ready` returns;
- a member placed under the bead later, through the same cascade;
- a sling of the parked bead itself. mol-polecat-work's load-context refuses a
  work bead that has an open blocker of its own: it holds the molecule and arms
  a re-dispatch that fires once the bead's blockers close.

A park does not hold these members:

- an armed member, because deferred dispatch slings an armed bead once its own
  blockers close, without reading its ancestors;
- a member slung by hand, or a workflow poured before the park, because
  `gc sling --on` pours without reading any edge and load-context reads no
  ancestor's blockers.

`park` names the armed members and the poured workflows it leaves unheld. A
member that must not start gets a park of its own: deferred dispatch waits on an
armed bead's own blockers, and mol-polecat-work's load-context refuses a bead
with an open blocker of its own.

### Releasing a park

Unparking closes the gate (`gc bd close <gate>`), which releases every bead that
waits on it, as closing any blocker does. To release one bead from a gate that
holds several, remove that bead's edge (`gc bd dep remove <bead> <gate>`). The
operator closes a park gate once it holds nothing. A released bead returns to
`bd ready` on the next read, so the pool offers it again if it is routed, and
its arm fires if it is armed and its other blockers are closed.

### What reads a park as a fault

These readers report a held bead as a fault:

- `doctor/check-blocked-work-armed` reads `bd blocked`, which lists each member
  a park holds, and flags one that has neither a route nor an arm. Its remedy,
  arming the member, would dispatch it past the park.
- The helm board files an epic whose open children sit idle, with nothing in
  flight, under STALLED, so a parked epic reads as stalled. The board's word
  "parked" means a bead carrying a takeaway, not a park.

### Where a park goes

A blocker on a bead with children holds every part of it, so such a bead carries
one only for a wait that belongs to all of its parts: a park on an epic, or a
prerequisite of all of an epic's work. A wait that belongs to one part goes on
that part. This is I1's shape law in
[component-model.md](component-model.md#i1-in-full-the-hold-the-demand-and-the-shape-law).
