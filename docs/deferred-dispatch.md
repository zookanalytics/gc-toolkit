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
one pass at a time (see
[One pass at a time, inside the timeout](#one-pass-at-a-time-inside-the-timeout)).
Each pass runs `deferred-dispatch.sh reconcile`, which:

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
  when the sling fails, when the recorded arguments are malformed, or when
  the pass has spent its budget;
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
or pinned ancestor ends the walk.

A read that fails fails the pass, so an unread hold never passes for none. A
read that answers without an id it was asked for says this store holds no
such bead: a bead in another store, or one deleted. bd's cascade passes a
hold down only from an ancestor row the store holds, so an ancestor with no
row, or a blocker with no row on an ancestor, holds nothing, as it holds
nothing in `bd list --ready`. A blocker with no row on the bead itself holds
it, marked unread, because it is the bead's own sequencing and the walk
cannot tell whether it is open. The walk runs only where bd keeps the bead
out of `--ready`, though, and bd holds nothing on an edge it cannot resolve,
so a bead bd has no other reason to hold is ready and the pass slings it, as
`arm` warns when it records the arm. An ancestor past the walk's depth cap
(`HOLD_MAX_DEPTH` in `hold-lib.sh`) is never read, and it holds the bead as
unread.

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
parked arm says why it is parked and what releases it. A blocker of the
bead's own that the store does not return shows as `(unreadable)`, and so
does an ancestor past the depth cap. The pass log names,
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
  records its pid and start time in `pass.holder` beside it. `<rig>` is
  `GC_RIG`. With only `GC_RIG_ROOT` set, it is the root's last path element
  plus a checksum of the whole path, so two rigs never share a lock. The
  lock depends on no bead surviving.
- Only the pass process holds the lock's descriptor. Every `gc` and
  `escalate.sh` call the pass makes runs with it closed. A process that a
  `gc` call starts can outlive the pass: a store read can bring up a Dolt
  server, and `gc` hands the descriptors it was given to what it starts. A
  process that kept the descriptor would hold the lock against every later
  pass. The kernel releases the lock when the pass exits, however it exits,
  `SIGKILL` included. The order's timeout kills the pass's whole process
  group, its `gc sling` with it, and the next pass re-attempts the
  unconfirmed sling through the `slinging@` recovery.
- A pass that finds the lock held prints one line and exits 0 without
  listing or slinging. Under the order it also declares the run `skipped`
  in the file the controller names in `GC_ORDER_OUTCOME_FILE` (gascity's
  exec-order outcome contract, `internal/orders/exec_outcome.go`), which the
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
point it starts no sling and files no escalation, since `escalate.sh` is
store work the timeout can cut short too. Each remaining ready bead keeps
its arm with no marker on it, this pass counts no attempt against it, and
the next pass slings it. A capped bead stays capped and armed, and the next
pass files its escalation. The pass names the beads it left, counts the
ready ones as `left for the next pass` in its summary, and declares the run
`partial`, naming each bead and what it left there. The controller reads a
declaration only after a run that exits 0, so a pass that also had a
failure declares nothing. It exits 1, and its output, which the controller
keeps for a failed run, names what it left. The retires and reports for the
rest of the armed set still run. Each retire is one write, and a retire the
timeout cuts short is made again by the next pass.

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

## The resolved-by consumer (`until`)

A `blocks` edge says "X must land before me": when X closes the dependent
becomes ready and is still fully owed. An `until` edge says the other thing —
"X resolves me" — and the same reconcile pass acts on it. Once a bead's own
`until` targets have all closed, the pass disposes the bead through
`assets/scripts/bead-rehome.sh`, so the close carries a successor pointer
(`gc.superseded_by`) instead of the bead re-entering triage as fresh work. A
wait whose named cause has landed is closed, not re-derived by hand.

`until` is not a blocking type, so an `until` edge does not hold a bead out of
`bd ready`. bd also keeps one edge type per pair of beads: a bead cannot carry
both a `blocks` edge and an `until` edge to the same X, and `bd dep add` refuses
the second. So a bead that waits on X and is resolved by X carries only the
`until` edge, and it reads as ready while X is open. The unnamed-wait census in
`assets/scripts/liveness-sweep.sh` reads `bd ready` and has no arm for `until`,
so it reports such a bead as an unnamed wait until X closes.

The pass acts only on an OPEN, UNASSIGNED bead: a non-`open` status is a
deliberate hold and an assignee is a live worker, both left alone. It disposes
only when EVERY `until` target has closed — a target still open, or one the
status read cannot resolve, leaves the bead waiting, never disposed on a guess.
A bead that one of its own `blocks` blockers still holds waits for that blocker
as well, and so does one whose blocker the status read cannot resolve. `bd
close` refuses a blocked bead, and `bead-rehome` stamps its pointer before that
refusal, so a call there would leave a live bead pointing at a successor.
ONLY `until` disposes: a `blocks` edge is never a dispose trigger, so the common
sequencing edge ("land A before B", where B is still owed after A) is never
auto-closed.

Which beads are owed is decided in one place, `assets/scripts/until-resolved.sh`,
which the pass and its doctor mirror both read. It makes one listing of the
store, then one status read of every bead the candidates' edges name, and
decides every candidate in one jq pass.

Open and unassigned is not the same as idle. An anchor stays open and
unassigned for as long as its PR is reviewed, and a bead slung to a pool stays
that way until a worker claims it. bd closes either without complaint, so the
guard is the pass's own. The pass disposes only a pure wait: a bead that
carries no live work as `assets/scripts/live-work.sh` defines it. The marks of
live work fall into these groups:

- **Dispatched:** a pool route, a deferred-dispatch arm or its sling marker, a
  formula pour, a deferred route, a claim, or a bound session.
- **Worked:** a branch, a worktree, a commit, a review round, a landing target,
  a PR, a landing state, or an outcome.
- **Owned by another closer:** any `task_kind`, a molecule step or workflow
  root, a demand, a duplicate diagnosis, or an issue type outside plain work
  (task, bug, feature, chore, spike). An epic closes on its own ruling.
- **Parked:** a `hold_reason` or a `rebase_hold`.
- **Structural:** a convoy that tracks the bead or parents it, or an open child
  under it.

The pass reads these marks twice. The first read is the row the pass-start
listing returns. The second is a fresh read of the bead and of what depends on
it, made just before the close, because a sling or a claim can land
mid-pass. That includes a sling the pass's own dispatch half made moments
earlier. A bead with any mark is reported and left open, which is never a pass
failure. The fresh read also confirms the bead is still owed: its `until` edge
to the successor is still there, no `until` target has reopened, and no
`blocks` blocker has opened. Removing the edge is how a person keeps a bead the
pass would otherwise dispose, so a bead whose edge went after the listing is
kept. A dispatch that lands after the fresh read meets a closed bead: no
pool offers it, and `mol-polecat-work`'s load-context quiesces a pour over it.
The guard runs before `bead-rehome` is called, because `bead-rehome` can stamp
its successor pointer and still have the close refused. A pointer on an anchor
reads as a disposed anchor to `scaffolding-sweep.sh`, which then retires that
anchor's review scaffolding.

When the close is held, commonly by an open visit tracking the bead,
`bead-rehome` records the successor pointer and refuses the close rather than
forcing it, leaving an open, pointed, findable bead that a later pass retries
once the hold clears. Enumeration is fail-closed the way the dispatch half is:
an unreadable store leaves every until-gated bead for the next pass rather than
reading "none owed". The same-store limit below holds for an `until` target as
much as for a `blocks` blocker — one in another rig is not seen here.

A pass pinned to a store, by the order's `GC_RIG_ROOT` or by `--db`, reads
every bead from that store whatever its id prefix says. Left to itself,
`bead-rehome` derives each bead's store from its id prefix, so the pass names
its store instead, as the rig whose `.beads` it is, and `bead-rehome` closes
there. A pinned store that no rig in `gc rig list` holds disposes nothing,
because a close aimed by id prefix could land in another store. An unpinned
pass leaves the store to `bead-rehome`, whose derivation by prefix is the
routing an unpinned read of an id takes.

A disposal costs a fresh read and a `bead-rehome` call, which makes several
store reads and writes of its own, so a target with many `until` dependents
could run a pass past the order's timeout. The timeout kills a pass mid-loop,
before it prints its summary. So the until half starts a disposal only while
one disposal's allowance (`DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS`, 30s) is
left in the same pass budget (`DEFERRED_DISPATCH_PASS_BUDGET_SECS`, 420s from the
start of the pass, 0 for unpaced). The owed beads past that point wait,
untouched, for the next pass, and the summary counts them as left for the next
pass. The budget counts from the start of the pass, so the until half spends
only what the dispatch half left, and with nothing left it does not list the
store at all. The budget sits at least one disposal allowance below the order's
timeout, so the last disposal a pass starts can run for twice its allowance, and
`deferred-dispatch.test.sh` holds the budget and each allowance against the
order's timeout. A dry run spends no budget.

The two halves enumerate independently. A dispatch half that cannot read its
armed set, or that stops short of it, still lets the until half run, and a
failure in either fails the pass.

The positive control in `deferred-dispatch.test.sh` and `check-cadence-live`
(I10) cover this half too, because this is the same order on the same cadence.
`doctor/check-until-resolved-owed` is the resolved-by mirror of
`check-armed-dispatch-owed`: it flags an open, unassigned
bead whose `until` targets have all closed and that no open `blocks` blocker
of its own still holds, yet that has stayed undisposed past the reconcile window — the
disposition silently not firing, surfaced before the bead drifts back into a
triage sitting. It decides through the same `until-resolved.sh` and makes the
same fresh read before it reports a bead, so it reports what the pass would do.
It measures how long a bead has been owed from the moment it became owed: the
latest of its `until` targets' closes, its `until` edges' creation, and its
`blocks` blockers' closes. An edge added today to a target that closed last
week is owed from today. A resolved bead the pass left open because it carries
live work is reported separately, as a decision for a person. If the work is
still wanted, the person removes the `until` edge. If the target's close made
it moot, the work is retired and the bead disposed by ruling.

## What this does not do

It does not make `gc sling` itself dependency-aware, and it does not give
the poured step beads an edge to the work bead. Both of those are changes
to the `gc` binary (the `gascity` rig), not to this pack, and neither is
implemented. An agent that calls `gc sling` directly on a blocked bead
still pours immediately, exactly as before — this mechanism is opt-in at
the call site.

The layer analysis behind that split, and what each `gc`-side direction
would take, is in `specs/tk-y0ygs/layer-determination.md`.

A blocker in another store holds nothing here either. `bd` resolves a
dependency id within one store, so a `blocks` edge naming a bead in
another rig is dropped from `bd show`, absent from `bd blocked`, and
counts for nothing in `bd list --ready`. An armed bead whose only blocker
lives elsewhere therefore reads as ready, and the next pass slings it
while that blocker is still open. The same-store limit belongs to the
hold doctrine (`docs/component-model.md`, I1), and sequencing across rigs
needs the blocker mirrored into the waiting bead's own store; that `arm`
inherits the limit without saying so is tracked on `tk-6shsru`.
