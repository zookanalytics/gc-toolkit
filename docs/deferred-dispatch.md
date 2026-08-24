---
name: Deferred dispatch
description: How a dispatch that must wait for other work is recorded, performed, and fed — so the waiting lives on the bead instead of in an agent's context, and ready work is converted into a dispatch by something rather than by nobody. Read it when you want to sling something whose blockers have not closed yet, or when you are asking why ready work is not being picked up.
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
where that record lives, what performs it, and what feeds it — the durable
form of "not yet" in this city's dispatch path, and the bounded converter
that turns ready work into a dispatch so the path has an input.

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

`doctor/check-deferred-dispatch-wired` asserts all three halves ship —
the arm/reconcile script, this order, and the feeder below — and that each
order's `exec` still reaches the verb it is supposed to run. Ship the arm
without the cadence and `arm` still succeeds, still writes a well-formed
record, and nothing ever performs it — the same invisible hold, one layer
down. Ship both without a feeder and nothing ever arms anything, which is
the state the next section describes.

## What feeds it

For most of this mechanism's life, nothing did.

`arm` shipped. `reconcile` shipped. Both worked. And every call to `arm`
had to come from an agent that decided to make one — which meant that in
practice, almost none were made. Measured in the gc-toolkit store on
2026-08-24: **252 ready work beads, all unrouted; 147 of them older than a
week; 51 older than 30 days; the oldest 123 days.** `deferred-dispatch.sh
list` reported "no pending dispatches in this store" the whole time, and it
was telling the truth — nothing was owed, because nothing had ever armed
anything. `core.control-dispatcher` and the polecat pools were ACTIVE on
all four rigs throughout. This was never a dead actor. It was an unfed
input: the machine ran, and the hopper was empty.

That failure is invisible from inside the mechanism. Every component
reports healthy, and a queue nobody feeds is indistinguishable from a queue
with nothing owed — the same silence this whole design exists to remove,
one layer further up.

`orders/dispatch-feeder.toml` is the input half. Every 10 minutes, per rig,
`assets/scripts/dispatch-feeder.sh feed`:

- selects ready work through **`bd list --ready`** — beads' own predicate,
  the same read `reconcile` makes, never a private copy of the blocking
  rules;
- excludes what must not be auto-slung: epics and convoys, specs, decisions
  and events, graph.v2 step beads and descriptor beads, anything already
  routed or already armed, anything carrying `gc.takeaway` or `triage.hold`
  or a `hold:*` label, anything with an assignee, and any `task_kind` other
  than `implementation` — a deny-by-default allow-list, so a kind invented
  next month is not auto-slingable by accident. Against the live 330-bead
  ready listing that removed 188 and left 142;
- orders what survives **oldest-created first**, so the 31d+ tail drains
  rather than starving behind every fresh arrival;
- and calls **`deferred-dispatch.sh arm`** — the shipped verb, not a second
  dispatch path.

That last point is the design, not a detail. Arming rather than slinging
keeps two existing fail-closed layers in the path: `arm` refuses a bead that
is closed or already dispatched, and `reconcile` refuses to sling one that
is held or already routed. A feeder that slung for itself would bypass both
and re-implement a dispatcher that is already written and already tested.
`doctor/check-deferred-dispatch-wired` asserts the feeder calls `arm` and
never slings directly.

### Bounded by construction

An unbounded feeder over a 252-deep queue is a spend incident, not a fix.
Two caps, both enforced in the script rather than asked of a caller:

| Knob | Default | What it bounds |
|---|---|---|
| `DISPATCH_FEEDER_ENABLED` | `1` | The whole pass. `0`/`false`/`no`/`off` arms nothing and says so. |
| `DISPATCH_FEEDER_MAX_IN_FLIGHT` | `2` | Beads this feeder has auto-armed that are still open, **per rig**. |
| `DISPATCH_FEEDER_MAX_PER_TICK` | `1` | Arms one pass may write, whatever the in-flight cap allows. |

`MAX_IN_FLIGHT = 2` matches the polecat pool ceiling of 2/rig, so the feeder
can never commit more work than the pool can execute; four rigs × 2 = 8
city-wide, which is the ceiling that already exists. Raising it above the
pool size only builds a queue of armed beads waiting for a polecat.

The in-flight count is taken from the feeder's own `gc.auto_armed_by`
marker, **not** from `gc.dispatch_when_ready`. It has to be: `reconcile`
clears the arm keys the instant it slings, so counting those would drop
every dispatched bead out of the tally within one 2-minute tick and the cap
would bind on nothing.

The three knobs are `[order.env]` defaults in `orders/dispatch-feeder.toml`,
overridden from `city.toml` without a pack change — the same surface the
2026-08-20..23 tooling-spend controls used:

```toml
[[orders.overrides]]
name = "dispatch-feeder"
rig  = "*"                       # or a single rig name
[orders.overrides.env]
DISPATCH_FEEDER_MAX_IN_FLIGHT = "1"
```

and the hard off switch, which stops all auto-arming and leaves hand-slung
work and hand-written arms completely unaffected:

```toml
[[orders.overrides]]
name = "dispatch-feeder"
rig  = "*"
enabled = false
```

To see the accounting without writing anything:

```bash
"$PACK_DIR/assets/scripts/dispatch-feeder.sh" status
"$PACK_DIR/assets/scripts/dispatch-feeder.sh" feed --dry-run
```

### It fails closed, twice, for two different reasons

An unreadable **candidate listing** exits non-zero and says so, rather than
printing a zero summary — that summary would read exactly like a board with
nothing ready, which is how 252 beads aged out unnoticed.

An unreadable **in-flight count** also exits non-zero, and this one matters
more. Read as zero it does not merely under-report: it hands the pass a full
budget and defeats the cap. That is the single way this feeder becomes the
spend incident it was written to avoid, so it refuses rather than guesses.
The same rule covers the knobs themselves — an unparseable or empty cap, or
an enable flag that is neither on nor off, refuses the pass instead of
silently restoring a default the operator believes they overrode.

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
