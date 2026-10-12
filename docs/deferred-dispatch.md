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
rather than restating it. What holds an armed bead is defined once, in
`assets/scripts/hold-lib.sh`, and this doc says how the pass applies it.

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
already dispatched (`in_progress`, or carrying `gc.routed_to`), one with
no `--target`, and one held at any status other than `open`.
`gc.execution_routed_to` alone does not count as dispatched: it is
execution provenance, not a live queue, and an open bead carrying only it
is the shape `doctor/check-blocked-work-armed` flags and names arming as
the fix for, so refusing on it would dead-end that remedy. Arming a bead
that has *no* open blocker is legal and says so — the next pass dispatches
it, which is what makes `arm` a safe universal substitute for a hand-held
sling.

The status refusal is the one that is not about double-dispatch.
`bd list --ready` excludes on status before it looks at dependencies at
all, so a `blocked`, `deferred`, `hooked` or `pinned` bead is as unready
as a gated one and stays that way however many blockers close. Nothing
re-derives status from the dependency graph — whoever set the hold
clears it. An arm recorded on such a bead can therefore never fire, so
`arm` refuses it rather than writing a record that waits forever.

Arming is the default move for a blocked follow-up you file or hold by
hand: arm it rather than leave it unrouted for someone to route once its
blocker lands, so a sitting can queue everything and drain. A blocked bead
that is plainly work and carries neither a route nor `gc.dispatch_when_ready`
is silent manual-follow-up debt — the exact miss
`doctor/check-blocked-work-armed` reports.

An arm is a dispatch path, as a route is. Both are defined once, in
`assets/scripts/dispatch-path.sh`, and each reader that asks whether a bead's
dispatch is already decided sources that file: the proactive scan,
`doctor/check-blocked-work-armed` and `doctor/check-step-terminal`. So an arm
also keeps the bead out of the proactive scan. `tools/gc-proactive.sh scan`
looks for raw input to react to, and it drops a bead that has a dispatch path.
Otherwise a sweep that ran between a blocker closing and the next reconcile
pass would sling a first reaction at a bead the arm is about to dispatch.

To see what is owed, in this rig's store:

```bash
deferred-dispatch.sh list        # each armed bead: held (and by what) / dispatchable / closed
deferred-dispatch.sh disarm <bead> --reason "superseded by <x>"
```

## What performs it

`orders/deferred-dispatch.toml` — a `cooldown` exec order at `scope =
"rig"`, so each importing rig reconciles its own store on its own clock,
and the dispatcher's open-tracking gate gives each rig its own
single-flight. Each pass runs `deferred-dispatch.sh reconcile`, which:

- **dispatches** every armed open bead nothing holds — the ones `bd` reports
  ready, and also the ones bd keeps unready only through an ancestor that
  waits on a demand gate, or through any held ancestor of a bead in flight
  (see below) — stamping its own
  `gc.dispatch_when_ready_slung` marker in its unproven `slinging@` state,
  running the recorded sling, promoting the marker to `slung@` on success,
  then clearing the record;
- **retires** the record on an armed bead that has closed, or whose sling
  reconcile has proven — a `slung@` (or pre-two-state bare-timestamp)
  `gc.dispatch_when_ready_slung` marker surviving into a later pass, from a
  pass that died before disarming — so recovery reads one marker reconcile
  owns rather than the lane-specific stamps a sling leaves (`gc.routed_to`
  for a plain sling, `gc.execution_routed_to` for an `--on` pour) — without
  slinging again;
- **re-slings** an arm whose marker survived in the unproven `slinging@`
  state — a pass that died before or during its sling, or a failed sling
  whose rollback did not land — because that dispatch was never proven and
  retiring it would silently lose the work;
- **withholds** — leaving the record armed and saying so — when a blocker
  holds the bead, on it or on an ancestor, when someone has it by `assignee`,
  when the sling fails, or when the recorded arguments are malformed;
- **names as STRANDED**, every pass and on stderr, an armed bead sitting
  at a non-`open` live status. The record is kept, because the status may
  yet be cleared, but it is counted apart from `held` and reported rather
  than left in a silent count. `list` marks the same beads
  `STRANDED — status=<s> is never --ready`. A stranded bead and a held
  one are both "not ready", and conflating them is what hides a dead arm:
  the held one dispatches when its hold releases, the stranded one never
  dispatches at all.

The arm waits on what holds the bead, as `assets/scripts/hold-lib.sh`
defines it: an open `blocks` blocker on the bead or on one of its
parent-child ancestors. A park and a prerequisite hold alike, so an armed
member of a parked epic, or of an epic that waits on a task, is held at any
depth under it, and so is a bead whose own blocker is still open. A demand
gate on an ancestor does not count: it is the operator's pending decision
(`gc.demand_for`), and waiting on that decision is not a hold. A demand gate
on the bead itself does count. Where `bd` decides the same question, the
definition follows it: a closed or pinned blocker holds nothing, and a closed
or pinned ancestor ends the walk. It fails closed, so a blocker or an
ancestor the pass cannot read holds the bead.

A hold holds work that has not started. A bead whose work has started is in
flight: it carries a `branch`, a `merge_result` or a `rejection_reason`. Only
a blocker of its own holds a bead in flight, and the walk reads none of its
ancestors, so a park on its epic leaves it running. An armed re-dispatch of
work already begun therefore fires under a parked epic once its own blockers
close, while the epic's members that have not started stay held, including
the ones under a parent in flight.

`bd list --ready` stays the fast path. bd's `is_blocked` flag cascades down
parent-child edges, so an armed child of an epic that waits only on a demand
gate never enters `--ready`, and neither does a bead in flight under a parked
epic. The pass therefore asks hold-lib about every open armed bead bd keeps
unready, and slings the ones nothing holds. The
status gate still holds (a non-`open` bead is never dispatched), and an
assignee still keeps the pass off the bead. The pass reads each generation
of ancestors in one listing and their blockers in one more, so its cost does
not grow with the number of armed beads under a held epic.

A held arm keeps its record. Releasing the hold, by closing a park's gate or
by the prerequisite landing, needs no re-arm: the first pass after it
dispatches the bead. `list` shows a held arm as `HELD by <blocker>
"<title>"`, adding `on ancestor <id>` when the edge sits on an ancestor, so a
parked arm says why it is parked and what releases it. A blocker or an
ancestor the pass could not read shows as `(unreadable)`. The pass log names,
on every pass, each hold that sits on an ancestor once, followed by the arms
it keeps. An arm its own blocker holds is counted in the summary without a
line, because the output of a failing pass reaches its `order.failed` event
only as its last 2 KB, and a line per arm would push the pass's warnings out.

The pass stamps `gc.dispatch_when_ready_slung` as `slinging@<ts>`
**first**, slings **second**, promotes the marker to `slung@<ts>` on
success **third**, and clears the whole record **last**. A pass that dies
before promoting the marker leaves the unproven `slinging@` state, which
the next pass re-slings rather than retires — so a crash mid-dispatch costs
a retry, never a silently lost dispatch. A marker surviving as `slung@` (or
an unprefixed timestamp) is a proven dispatch whose pass died before
disarming, and the next pass retires it rather than pouring a second time —
one marker reconcile owns, not an inference from whichever stamp a delivery
lane happened to leave. A sling that fails rolls the marker back, so the arm
retries next pass.

An unreadable listing exits non-zero and says so. It never prints a
zero-count summary — for a dispatcher, "I could not see the queue" and
"nothing was owed" reading alike is the same disappearing hold this
machinery exists to remove.

Three checks keep the halves together. The positive control closing
`assets/scripts/deferred-dispatch.test.sh` asserts the order file ships,
is a rig-scoped cooldown, does not opt out of the single-flight gate, and
still reaches this script's `reconcile` verb. `doctor/check-cadence-live`
(I10) then asserts the registration is live on every importing rig and
has fired within its cadence window: `max(3×interval, floor)`, where the floor
is one trip of the order dispatch rotation (`assets/scripts/order-cadence.sh`).
Ship the arm without the cadence
and `arm` still succeeds, still writes a well-formed record, and nothing
ever performs it — the same invisible hold, one layer down.
`doctor/check-armed-dispatch-owed` closes the gap the other two leave: the
cadence can be live and the pass still leave a dispatch unmade, so it flags an
arm nothing holds that has stayed open and armed past the reconcile window, or
one armed at a non-open status the pass can never dispatch — a dispatch
silently not firing, surfaced before a human has to notice it days later. It
reads holds through the same `hold-lib.sh`, so an arm a park holds is not
reported.

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
