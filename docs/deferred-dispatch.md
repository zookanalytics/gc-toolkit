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
deferred-dispatch.sh list        # each armed bead: waiting / dispatchable / closed
deferred-dispatch.sh disarm <bead> --reason "superseded by <x>"
```

## What performs it

`orders/deferred-dispatch.toml` — a `cooldown` exec order at `scope =
"rig"`, so each importing rig reconciles its own store on its own clock,
one pass at a time (see
[One pass at a time, inside the timeout](#one-pass-at-a-time-inside-the-timeout)).
Each pass runs `deferred-dispatch.sh reconcile`, which:

- **dispatches** every armed open bead whose own `blocks` edges have all
  closed — the ones `bd` reports ready, and also the ones bd holds unready
  only through a blocked or deferred ancestor (see below) — stamping its own
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
- **withholds** — leaving the record armed and saying so — when the bead
  is still blocked, when someone holds it by `assignee`, when the sling
  fails, when the recorded arguments are malformed, or when the pass has
  spent its budget;
- **names as STRANDED**, every pass and on stderr, an armed bead sitting
  at a non-`open` live status. The record is kept, because the hold may
  yet clear, but it is counted apart from `waiting` and reported rather
  than left in a silent count. `list` marks the same beads
  `STRANDED — status=<s> is never --ready`. A held bead and a gated bead
  are both "not ready", and conflating them is what hides a dead arm: the
  gated one dispatches when its blocker closes, the held one never
  dispatches at all.

The arm waits on the bead's OWN blockers, which is narrower than `bd list
--ready`. `--ready` applies beads' own claimability predicate — open, no
active blocker of a blocking type (`blocks` / `waits-for` /
`conditional-blocks`), not `in_progress`, `blocked`, `deferred` or `hooked` —
and it ALSO excludes a bead held only by a blocked or deferred ANCESTOR,
because the is_blocked flag cascades DOWN parent-child edges. An armed epic
child whose own blockers have all closed is ready to run, but sits under a
container the operator holds on a human demand gate, so it never enters
`bd --ready` while that gate is open and its arm would never fire. So the
pass reads `bd --ready` as the fast path, then asks any open bead bd holds
unready one direct question — are all of its own `blocks` edges closed? — and
dispatches on a yes. The status gate still holds (a non-`open` bead is a
deliberate hold and is never dispatched), and an assignee still HELDs the
bead. The one question reconcile answers itself is the arm's own: whether the
thing the arm waits on has landed. `bd blocked` and `bd ready` cannot answer
it under this bead's id, because the cascade attributes the block to the
ancestor.

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
has fired within `max(3×interval, 15m)`. Ship the arm without the cadence
and `arm` still succeeds, still writes a well-formed record, and nothing
ever performs it — the same invisible hold, one layer down.
`doctor/check-armed-dispatch-owed` closes the gap the other two leave: the
cadence can be live and the pass still leave a dispatch unmade, so it flags an
arm whose own `blocks` edges have all closed but that has stayed open and
armed past the reconcile window, or one armed at a non-open status the pass can
never dispatch — a dispatch silently not firing, surfaced before a human has to
notice it days later.

## One pass at a time, inside the timeout

Two passes over one store would sling the same ready bead twice, which
mints two input convoys for one work bead and bumps its attempt count
twice. The controller's open-tracking gate keeps a second run from
starting only while the first run's tracking bead stays open, and a sweep
can close that bead under a pass that is still running. The core
`order-tracking-sweep` order closes any tracking bead older than its
`--stale-after` (10m). On a gc build that does not extend the window to the
order's timeout, the controller watchdog closes it 2m after dispatch. So
the pass carries its own lock:

- Before it reads the store, `reconcile` takes a non-blocking exclusive
  `flock` on `<GC_PACK_STATE_DIR>/deferred-dispatch/<rig>/pass.lock` and
  records its pid and start time in `pass.holder` beside it. The lock
  depends on no bead surviving.
- `gc sling` and `gc bd` inherit the descriptor, so the lock is held for as
  long as anything the pass started is live. The kernel releases it on any
  exit, `SIGKILL` included.
- A pass that finds the lock held prints one line and exits 0 without
  listing or slinging. Under the order it also declares the run `skipped`
  in the file the controller names in `GC_ORDER_OUTCOME_FILE`, which the
  controller records as an `order.skipped` event. The controller keeps an
  exit-0 run's output nowhere else.
- A holder older than `DEFERRED_DISPATCH_LOCK_STALL_SECS` (900s) is not a
  slow pass, because the order's timeout would have killed it. That pass
  exits 1, so `order.failed` reports the wedge.
- A pass that cannot take the lock at all exits 1 before it reads the
  store. That covers `flock` missing from `PATH` and a lock file the pass
  cannot create or open. Nothing else carries single-flight, so a pass that
  ran anyway would be the second slinger the lock exists to prevent.

The order's `timeout` kills a pass wherever it stands. A sling killed
mid-flight has already minted its input convoy, leaves it with no
workflow, and spends one of the bead's attempts. So a pass measures a
budget from its own start, `DEFERRED_DISPATCH_PASS_BUDGET_SECS` (420s,
0 = unpaced), and starts a sling only while at least
`DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS` (90s) of it is left. Past that
point it starts no sling. Each remaining ready bead keeps its arm with no
marker on it, this pass counts no attempt against it, and the next pass
slings it. The pass names the beads it left, counts them as `left for the
next pass` in its summary, and declares the run `partial`. The retires and
reports for the rest of the armed set still run.

The budget sits at least one allowance below the timeout, so the last
sling a pass starts can run for twice its allowance before the timeout
lands. The stall bound sits above the timeout, so a pass that is still
running never reads as a wedged one. `deferred-dispatch.test.sh` reads
these numbers from the files that set them and asserts both pairs. A city
override that lowers the order's `timeout` has to lower the budget in its
`env` as well.

`--dry-run` writes nothing and slings nothing, so it takes no lock and
spends no budget. It lists every bead a pass would sling, whether or not a
pass is in flight.

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
