---
name: Unqualified Route Targets Strand Work Silently
description: Why a rig-unqualified pool name in gc.routed_to makes a bead invisible to every pool, why neither builtin doctor check reports it, and where the write-time guard that closes both this and the order-side strand has to live.
---

# Unqualified Route Targets Strand Work Silently

> **Bead:** tk-5cgyk. **Investigated:** 2026-08-10. **Author:** Polecat gc-toolkit.furiosa.
> Companion to `specs/tk-gi2pc/rig-scoped-order-unbound-firing.md`, which
> documents the order-side half of the same defect. That spec asked for a guard
> in order discovery; the mayor's note on this bead asked whether the same
> hazard reaches hand-routed beads. It does, it is unreported, and one guard at
> one write site closes both.

## Scope

**Mandate.** What makes a `gc.routed_to` value claimable, the exact shape that
is not, why every existing check passes over it, and the design for the
write-time guard. Written for whoever implements `gc-xaqpf` in the gascity rig.

**Boundaries.** Not a description of order discovery — that is the companion
spec, and the two are read together. Not a record of the tk-gi2pc cleanup. Line
references to gascity are pinned to the fork at `rigs/gascity` as of
2026-08-10; grep the symbol names, which are stable, rather than trusting the
numbers.

## Symptom

`tk-5cgyk` — the bead carrying the durable fix for the order-side strand — was
itself stranded by the bead-side twin of the defect it fixes. It sat open,
unassigned, and unworked while the orders it fixes kept re-stranding every
cooldown. Its route:

```
tk-5cgyk   gc.routed_to = "gc-toolkit.polecat"      (rig-unqualified)
           live pool     = "gc-toolkit/gc-toolkit.polecat"
```

Every configuration file was correct. `gc doctor` was red the whole time — about
the order side, from `check-rig-scoped-orders-bound` — and silent about this.
The bead was only worked after a human noticed and re-slung it by hand.

## Mechanism: the offer is an exact string match

A pool is offered a bead by string equality and nothing else.

`hookClaimMatchesRoute` (`cmd/gc/cmd_hook_claim.go`) compares the bead's
`gc.routed_to` against each of the claiming session's route targets with
`routedTo == target`. The runtime's standing offer query
(`cmd/gc/dispatch_runtime.go`) is the same equality pushed into the store:

```
bd ready --metadata-field "gc.routed_to=$route" --unassigned --exclude-type=epic
```

There is no prefix search, no late qualification, no fallback. A route that is
one segment short of the pool's identity is not a near miss — it is invisible,
and indistinguishable at rest from a bead nobody routed anywhere.

### Two identity forms, only one of them live

A pool's identity is `Dir + "/" + BindingQualifiedName()`
(`config.Agent.QualifiedName`, `internal/config/config.go`), which for this
city's polecat pools is `<rig>/gc-toolkit.polecat`. The bare
`gc-toolkit.polecat` is the *binding-qualified, rig-unqualified* form. It is:

- **correct at rest in an order file** — `qualifyPool` prepends the firing rig,
  which is what lets one bare pool in `orders/liveness-sweep.toml` mean "this
  importer's own polecats" in four different rigs. The order file's own header
  explains this, and `check-liveness-sweep-wired` asserts it;
- **inert once written onto a bead** — nothing qualifies a bead's route after
  the fact. What is stamped is what is matched.

So the same string is the right thing to write in one place and a silent strand
in the other, and nothing marks the boundary.

## Why nothing reported it

Two builtin checks look like they cover this. Neither does, for two independent
reasons — which is why the live city could carry a stranded bead with both
reporting OK.

**`session-model` / `stale-routed-config` scans the city store only.**
`sessionModelDoctorCheck.Run` (`cmd/gc/doctor_session_model.go`) opens exactly
one store, `c.newStore(c.cityPath)`, and never iterates `cfg.Rigs`. Every bead
in every rig store — which is where nearly all work lives — is outside its
field of view. It could not have seen `tk-5cgyk` whatever its route said.

**`v2-routed-to-namespace` scans every rig store but looks for a different
short form.** It builds its short→canonical alias map from
`unboundRouteIdentity` (`cmd/gc/doctor_routed_to_checks.go`), which is
`Dir + "/" + Name` — the agent's *raw* name, before the binding prefix. So it
maps `gc-toolkit/polecat` → `gc-toolkit/gc-toolkit.polecat`: the
**binding**-unqualified form, missing the `gc-toolkit.`. The form that strands
is the **rig**-unqualified one, missing the `gc-toolkit/`. That check is the
PackV2 binding-name migration; this is a different half of the identity and is
not in its alias map at all.

Between them: the check that covers the right stores looks for the wrong
string, and the check that would recognise the string cannot see the stores.
The gap is not a bug in either — it is the space between two checks that were
each built for something else.

## How the bad value gets written

Three paths, all live today:

1. **Hand-routing.** `gc bd update --set-metadata gc.routed_to=<pool>` accepts
   any string. This is how `tk-5cgyk` was routed.
2. **The order-fire path.** `cmd/gc/order_dispatch.go` and `cmd/gc/cmd_order.go`
   stamp `gc.routed_to = pool` on the wisp from the order's registration. When
   the registration is the unbound city-scope copy the companion spec
   describes, `qualifyPool` has already returned the bare pool unchanged, and
   the bare pool is what gets stamped. **The order-side strand and this one are
   the same write.**
3. **The pack's own formulas.** `formulas/mol-refinery-patrol.toml` (two sites)
   writes `gc.routed_to="${GC_RIG:+$GC_RIG/}{{binding_prefix}}polecat"`. The
   `${GC_RIG:+…}` guard collapses to the bare pool whenever `GC_RIG` is empty.
   The refinery is rig-scoped so it is normally set — which is precisely the
   problem: the failure needs an unusual context and then produces no signal,
   so it is invisible until someone counts unworked beads. That file is shared
   by all four rigs (one file, symlinked), so it is left alone here; the
   detector below covers it, and the write-time guard removes the class.

## The fix, in two halves

The same shape the companion spec used, and for the same reason: refusing the
bad state beats detecting it, but the refusal lives in Go and the detector can
ship from this pack today.

### Half 1 — the write-time guard (gascity Go; NOT this pack)

**Where.** The site that stamps a route onto a bead. `cmd/gc/cmd_sling.go`'s
`SetMetadata(req.BeadID, beadmeta.RoutedToMetadataKey, routedTo)` is the
primary one, and it already has a precedent sitting on it:
`agentutil.NormalizePoolRouteTarget` (`internal/agentutil/resolve.go`)
normalizes a slot-suffixed target at exactly this point, and its docstring
names this exact failure — *"Recording the slot-suffixed value in
`gc.routed_to` therefore leaves the bead structurally invisible to the pool.
Normalizing at the routing write site keeps slot-suffixed slings reachable by
any slot."* A rig-unqualified pool name is the same defect one segment over,
and belongs in the same place. The order-fire stamps
(`cmd/gc/order_dispatch.go`, `cmd/gc/cmd_order.go`) need the same treatment;
covering them is what makes this guard subsume the order-side one.

**The rule.** A value being written to `gc.routed_to` must resolve to a live
route identity — one of the expanded per-rig/per-city agent identities, the set
`gc agent list` prints. If it does not, and exactly one rig-qualification of it
does *for the store the bead is being written to*, qualify it (the
`NormalizePoolRouteTarget` treatment). If it does not and the qualification is
ambiguous or absent, refuse the write with an error naming the candidates.

**One detail decides whether that patch is correct or catastrophic.** The test
is *"does this resolve to a live identity"*, never *"does this look
qualified"*. Bare route values that are perfectly live exist and are common:
`gc-toolkit.mayor`, `gc-toolkit.deacon`, `gc-toolkit.mechanik` are city-scope
named sessions with no rig prefix by design. A syntactic rule — "a dot and no
slash is broken" — would refuse every route to every city-scope agent in the
town. Equally, the guard must not reach the *order file's* pool field, where
the bare form is correct at rest and qualified later; it governs the write of
`gc.routed_to` onto a bead, and only that.

**Sentinels.** `gc.routed_to=human` names no agent on purpose — the signoff
round cap writes it, the quiesce sweeps read it. Whatever set of non-agent
sentinels the guard honours must be explicit and shared with the detector
below, which currently allows exactly `human`.

**The test.** Stamp a bare rig-pool name onto a bead in a rig store and assert
the write is qualified or refused; stamp a live city-scope bare identity and
assert it is untouched; stamp `human` and assert it is untouched. Then the
order-side case: fire an order whose registration carries a bare pool with no
rig bound, and assert no bead is left carrying an unclaimable route.

Tracked as **`gc-xaqpf`** in the gascity rig (priority 1), together with the
order-discovery guard from the companion spec.

### Half 2 — the detector (this pack, shipped with this bead)

`doctor/check-routed-work-claimable` errors for every open, unassigned bead
whose `gc.routed_to` is non-empty, matches no live agent identity, and whose
rig-qualified form does. It scans every store `gc rig list` reports, so it
covers the two blind spots above at once: all rig stores, and the
rig-unqualified form specifically.

It reports the exact repair when the bead's own rig qualifies the route into a
live identity (the `tk-5cgyk` shape), and lists candidates when nothing does —
which is the city-store shape a stranded wisp takes, so it also catches the
tk-gi2pc strand from the bead side. A route matching nothing at all is reported
in the details but left out of the verdict: unclaimable, but indistinguishable
from a sentinel we do not know about, and `human` proves those exist. Every
unreadable probe warns rather than passing, because "could not tell" and
"nothing wrong" are different answers and collapsing them is the same fail-open
that let this strand run.

Against the live city on 2026-08-10 it reports exactly one bead — `tk-5cgyk`
itself — and nothing else. Once half 1 lands it is permanently green and
becomes the regression gate.

## What was deliberately not done

- **No change to `mol-refinery-patrol.toml`.** The `${GC_RIG:+…}` collapse is a
  real exposure, but that file is shared by all four rigs and the pattern is
  deliberate elsewhere; changing route-writing behaviour town-wide is not this
  bead's mandate. The detector covers it and the write-time guard removes it.
- **No repair pass over existing beads.** The detector names the repair; it
  does not perform it. A doctor `--fix` arm that rewrites routes is defensible
  later, but a check that silently mutates work routing on its first outing is
  not how this should earn trust.
- **No syntactic rule.** Ruled out above: it would refuse every city-scope
  agent's route.
- **No widening to assigned or closed beads.** An assignee is its own
  reachability; the route is not what carries those.
