---
name: Dispatching work
description: How to hand a work bead to a pool — stamp the route, don't sling a formula — plus the gc sling shapes at a pool that pour a molecule instead of routing the bead, and the one that leaves no work bead at all.
---

# Dispatching work

Handing a work bead to a pool is a routing write, not a formula pour. Stamp the
pool's name on the bead; a member claims it and runs `mol-polecat-work` on it.
`gc sling` with a formula does something different — it pours a molecule now and
routes that molecule's root — which suits some work and is the wrong tool for
handing a plain bead to a pool.

## Scope

**Mandate.** How to route a plain work bead to a pool, and which `gc sling`
shapes pour a molecule or strand one instead of routing the bead.

**Boundaries.** The field each path writes and the claim predicate that reads it
back are the routing contract in
[gascity-routing-model.md](gascity-routing-model.md). Cleaning up a molecule
already poured the wrong way is
[gascity-dispatch-containment.md](gascity-dispatch-containment.md). A dispatch
that must wait for a blocker is [deferred-dispatch.md](deferred-dispatch.md).

## Route a work bead by stamping the pool

A pool shares one work queue keyed by `gc.routed_to`. Any eligible member claims
a bead carrying the pool's name and runs `mol-polecat-work` on it. The delivery
is one metadata write:

```bash
gc bd update <bead> --set-metadata gc.routed_to=<rig>/<pool>
```

That write is the pool's own routing: a pool's `sling_query` is
`bd update {} --set-metadata gc.routed_to=<pool>`, so
`gc sling <rig>/<pool> <bead> --no-formula` performs the identical write and
nothing else. Re-stamping the same route is a no-op, which makes this the safe
form to repeat during a redispatch or a remediation. The pack routes pool work
this way throughout — for example the reconcile passes in
`assets/scripts/pr-facts.sh`, and `pre-open-rebase.sh` and `orphan-dispose.sh`.

## `gc sling` with a formula pours a molecule; it does not route the bead

Two shapes attach a formula and pour its molecule:

- `gc sling <pool> <bead> --on <formula>` attaches `<formula>` to `<bead>`.
- `gc sling <pool> <bead>` does the same here without `--on`, because this city
  sets `default_sling_formula = mol-polecat-work` at city scope. `--no-formula`
  is the opt-out.

Either shape pours a fresh workflow and routes the workflow **root** to the pool,
not the bead (the field mechanics are Lane 4 in
[gascity-routing-model.md](gascity-routing-model.md)). That is what you want when
the job is to pour a specific molecule on a bead — a review or a validate pass,
which the pack dispatches exactly this way (`assets/scripts/signoff.sh`,
`gate-ensure.sh`). It is the wrong tool for a plain work bead: a pool member
already runs `mol-polecat-work` on a routed bead, so slinging a formula routes
the root instead of the bead and pours work the pool would run anyway. That is
redundant, and it is not idempotent the way a re-stamp is. Stamp the route
instead.

## Never sling a bare formula name at a pool

```bash
gc sling <pool> <formula>     # a formula name, no bead
```

With no bead there is no work behind the workflow: the root is the only record,
and a member claims a molecule whose first step finds nothing to implement.
Always name the bead — stamp its route, or attach a formula to it with `--on`.
