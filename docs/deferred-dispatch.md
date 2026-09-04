---
name: Deferred dispatch
description: How to record a dispatch that must wait for other work, so the waiting lives on the bead instead of in an agent's context. Read it when you want to sling something whose blockers have not closed yet.
---

# Deferred dispatch

A dispatch that has to wait is a fact about the work. It belongs on the
bead.

Before this existed, it lived in an agent's head. `gc sling` pours its
formula immediately and takes no notice of the bead's `blocks`
dependencies — the mechanism is in
[gascity-routing-model.md](gascity-routing-model.md#a-blocks-dep-between-work-beads-does-not-hold-a-graphv2-dispatch),
and the short version is that none of the records the pour creates
carries an edge to the work bead, so a `blocks` edge between two work
beads is not on any path a readiness query walks. Sling a blocked bead
and a polecat claims it within a couple of minutes.

The remedy was therefore *"sling only beads that `gc bd blocked` does not
list; hold the rest and sling when their deps close."* That hold has no
home in the ledger. It lives in one session's context, is invisible to
every other agent and to the operator, and has no recovery path: if the
holder dies, the bead sits forever behind a `blocks` edge that nothing
acts on, and nothing anywhere knows a dispatch was owed.

## Scope

**Mandate.** How a dispatch that must wait for other work is recorded,
where that record lives, and what performs it — the durable form of "not
yet" in this city's dispatch path.

**Boundaries.** *Why* a dependency edge does not gate a formula dispatch,
and which record each delivery lane routes, belong to the routing
contract and live in
[gascity-routing-model.md](gascity-routing-model.md). Recovering a pour
that already happened is
[gascity-dispatch-containment.md](gascity-dispatch-containment.md). This
doc does not cover slinging in general, and it does not speak for what a
dep edge means to `bd` — it defers to `bd`'s own readiness predicate
rather than restating it.

## Arm it instead of remembering it

```bash
"$PACK_DIR/assets/scripts/deferred-dispatch.sh" arm <bead> \
    --target <rig>/<agent> \
    --reason "waits for <blocker> to land"
```

That writes the pending dispatch onto the work bead as metadata, appends
a note saying who armed it and why, and returns. Nothing is held in your
context; you may drain immediately.

Extra `gc sling` arguments are recorded too, and replayed verbatim when
the dispatch fires:

```bash
deferred-dispatch.sh arm tk-abc --target gc-toolkit/gc-toolkit.polecat \
    --sling-arg --on --sling-arg mol-pr-from-issue
```

`arm` is fail-closed. It refuses a bead that is closed, one that is
already dispatched (`in_progress`, or carrying `gc.routed_to` /
`gc.execution_routed_to`), and one with no `--target`. Arming a bead that
has *no* open blocker is legal and says so — the next pass dispatches it,
which is what makes `arm` a safe universal substitute for a hand-held
sling.

To see what is owed, in this rig's store:

```bash
deferred-dispatch.sh list        # each armed bead: waiting / dispatchable / closed
deferred-dispatch.sh disarm <bead> --reason "superseded by <x>"
```

## What performs it

`orders/deferred-dispatch.toml` — a `cooldown` exec order at `scope =
"rig"`, so each importing rig reconciles its own store on its own clock,
and the dispatcher's open-tracking gate gives each rig its own
single-flight. Each pass runs `deferred-dispatch.sh reconcile`, which:

- **dispatches** every armed bead that `bd` now reports ready — running
  the recorded sling, then clearing the record;
- **retires** the record on an armed bead that has closed, or that is
  already routed (the crash-between-sling-and-disarm case), without
  slinging;
- **withholds** — leaving the record armed and saying so — when the bead
  is still blocked, when someone holds it by `assignee`, when the sling
  fails, or when the recorded arguments are malformed.

Dispatchability is not re-implemented here. `bd list --ready` applies
beads' own predicate — open, no active blocker of a blocking type
(`blocks` / `waits-for` / `conditional-blocks`), not `in_progress`,
`blocked`, `deferred` or `hooked`, parent-child blocked-flag cascade
included. Asking `bd` is what keeps this from drifting away from the
predicate every other reader uses.

The pass slings **first** and clears the record **second**. Dying between
the two leaves an armed bead that is already routed, which the next pass
retires rather than pouring a second workflow onto.

An unreadable listing exits non-zero and says so. It never prints a
zero-count summary — for a dispatcher, "I could not see the queue" and
"nothing was owed" reading alike is the same disappearing hold this
machinery exists to remove.

Two checks keep the halves together. The positive control closing
`assets/scripts/deferred-dispatch.test.sh` asserts the order file ships,
is a rig-scoped cooldown, does not opt out of the single-flight gate, and
still reaches this script's `reconcile` verb. `doctor/check-cadence-live`
(I10) then asserts the registration is live on every importing rig and
has fired within `max(3×interval, 15m)`. Ship the arm without the cadence
and `arm` still succeeds, still writes a well-formed record, and nothing
ever performs it — the same invisible hold, one layer down.

## What this does not do

It does not make `gc sling` itself dependency-aware, and it does not give
the poured step beads an edge to the work bead. Both of those are changes
to the `gc` binary (the `gascity` rig), not to this pack, and neither is
implemented. An agent that calls `gc sling` directly on a blocked bead
still pours immediately, exactly as before — this mechanism is opt-in at
the call site.

The layer analysis behind that split, and what each `gc`-side direction
would take, is in `specs/tk-y0ygs/layer-determination.md`.

It also does not close a bead its blocker resolved. "X must land before
me" and "X resolves me" are different claims, and only the first has a
consumer today; the second is tracked on `tk-4dksv`. The two are the same
shape — an edge nothing acts on — and this order is the natural host for
that consumer when it is built.

A blocker in another store holds nothing here either. `bd` resolves a
dependency id within one store, so a `blocks` edge naming a bead in
another rig is dropped from `bd show`, absent from `bd blocked`, and
counts for nothing in `bd list --ready`. An armed bead whose only blocker
lives elsewhere therefore reads as ready, and the next pass slings it
while that blocker is still open. The same-store limit belongs to the
hold doctrine (`docs/component-model.md`, I1), and sequencing across rigs
needs the blocker mirrored into the waiting bead's own store; that `arm`
inherits the limit without saying so is tracked on `tk-6shsru`.
