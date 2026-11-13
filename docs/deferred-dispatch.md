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
[gascity/routing-model.md](gascity/routing-model.md#a-blocks-dep-between-work-beads-does-not-hold-a-graphv2-dispatch),
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
[gascity/routing-model.md](gascity/routing-model.md). A pour that already
happened is ended through Gas City's run cancel, as the pack's decline does
([pack-authoring.md](pack-authoring.md#a-run-that-must-not-advance-is-cancelled-after-its-wait-is-recorded)). This
doc does not cover slinging in general, and it does not speak for what a
dep edge means to `bd` — it defers to `bd`'s own readiness predicate
rather than restating it. What holds an armed bead is the pool's own serve
rule, `bd ready` with the flags Gas City renders for a pool's demand, with
`gctk bead holds` ([its contract](gctk-architecture.md#the-bead-holds-contract))
for the waits bd cannot judge, and this doc says how the start applies them.

## Arm it instead of remembering it

```bash
"$PACK_DIR/assets/scripts/deferred-dispatch.sh" arm <bead> \
    --target <rig>/<agent> \
    --reason "waits for <blocker> to land"
```

That hands the call to `gctk bead arm`, which writes the pending dispatch onto
the work bead in one write, with a note saying who armed it and why, and
returns. Nothing is held in your context; you may drain immediately.

The arm records the formula the start pours: the one `--sling-arg --on
--sling-arg <formula>` names, or else the target's default, which the city's
config gives. The arm passes `gc sling` nothing else:

```bash
deferred-dispatch.sh arm tk-abc --target gc-toolkit/gc-toolkit.polecat \
    --sling-arg --on --sling-arg mol-pr-from-issue
```

`arm` is fail-closed. It refuses a bead that is closed, one that is
already dispatched (`in_progress`, or carrying `gc.routed_to`), one already
armed for another target or formula, one with no `--target`, a target that
names no formula to pour, one held at any status other than `open`, and one
with a wait edge onto a bead in another store, which bd never holds a bead on.
An arm already on the bead for the same target and formula is a success that
writes nothing.
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
dispatch is already decided sources that file: the proactive scan and sling,
`doctor/check-blocked-work-armed`, `doctor/check-step-terminal` and
`assets/scripts/stand-down.sh`. So an arm also keeps the bead out of the
proactive scan. `tools/gc-proactive.sh scan` looks for raw input to react to,
and it drops a bead that has a dispatch path.
Otherwise a sweep that ran between a blocker closing and the deferred-dispatch
order's next pass would sling a first reaction at a bead the arm is about to
dispatch.
`gc-helm.sh react` and `operator-intake.sh` skip the scan and name a bead to
`tools/gc-proactive.sh sling` directly, so the sling refuses a bead that has a
dispatch path too, and a reaction they ask for cannot race the arm either.

To see what is owed, in this rig's store:

```bash
deferred-dispatch.sh list        # each armed bead and what the next pass would do with it
deferred-dispatch.sh list --json # the armed beads alone, as bd lists them, with no hold
deferred-dispatch.sh disarm <bead> --reason "superseded by <x>"
```

A converse sitting holds a bead with a human gate and writes nothing else the
pass reads, so an armed bead keeps its arm through the hold. The gate holds it
as any blocker does, and the arm sends it once the gate is resolved, unless the
sitting's ruling sends it elsewhere. Then the sitting disarms it before it
answers the gate, at the sign-off or on a turn that does not sign off (the
converse-settle and converse-continue steps).

A person who rules that armed work a human gate holds will not go on runs
`stand-down.sh <bead> --key <situation-key> --ruling "<why>"`. Answering the gate
first would send the work, and bd refuses to close a bead an open gate blocks,
so it removes the arm, ends the run beneath the bead, answers the gate and closes
the bead, in that order. The disarm takes the bead's dispatch lock, which a start
holds while it sends the bead and reads the arm once more under, so a pass already
running cannot send the work past that disarm: a pass that read the gate open
holds the bead, and one that read it closed reads the arm gone. A
gate that also holds another open bead takes no answer, because an answer releases
everything it blocks. With `--successor` naming the evidence, the bead leaves that
gate after its arm and route are gone. Removing that edge first would send the work,
as any release of an armed bead does.

## A named agent hears through Gas City's hand-off

A named agent takes no arm: an arm pours a formula through a pool, and a named
agent is no pool. Work for one goes to it in the form it finds its work by, and
it hears about the work through Gas City's own paths, so the pack keeps no
record for it. The work skill gives each agent's command.

- **An agent that claims through its hook, such as the mechanik, takes a
  route.** `gc sling <agent> <bead> --no-formula --no-convoy` writes
  `gc.routed_to=<agent>`, and a plain named session's hook serves a bead routed
  to its own name once `bd` reports the bead ready
  ([gascity/routing-model.md](gascity/routing-model.md#the-read-side-the-claim-predicate)).
  `--no-convoy` keeps the raw route from filing an auto-convoy around the bead.
- **An agent that finds its work by listing the beads assigned to it takes the
  assignee.** The refinery's patrol lists the open beads assigned to it that
  carry a `branch`, and the keeper's wake sweep lists the beads assigned to it
  that carry a handback. A route never reaches either list.
- **The deacon and the witness patrol their own wisps.** Each one's hook
  answers its patrol's wisp ahead of a bead routed or assigned to it, and
  neither patrol lists assigned beads, so they take mail, which each patrol
  reads every cycle.

A route or an assignee alone gives a running agent no turn. Core's
`nudge-on-route` order would nudge a routed agent, but it reads the route from
a flat event payload, and the build the city runs nests the bead in every
`bead.updated` event, so it nudges nobody. So a writer whose bead is ready
nudges the agent at the write, naming the bead:
`gc session nudge <agent> "<bead> is routed to you and ready"`, or "is assigned
to you" for the assignee form. A nudge to an agent that is not running queues,
and asks the controller to wake the agent, which delivers it.

A bead that still waits on a `blocks` blocker takes the route or the assignee
alone. When the blocker closes, core's `cascade-nudge-on-blocker-close` nudges
each dependent that no other blocker holds, naming it: the assignee with a
queued nudge, which reaches a running session at its next idle boundary, or
else the route with the default delivery. The controller also wakes a stopped
session once ready work is assigned to it.

What no path covers: a running, idle agent is not told about work that becomes
ready another way, such as a lifted park, a removed hold label or a wait that
is not a `blocks` edge, and hears at its next turn. Nothing nudges on a raw
`bd update --assignee` either, so a person hands work to a named agent through
the work skill's send.

`first-reaction-dispose.sh` addresses only an agent whose hook offers the bead,
so both of its named-agent exits route it. The bead `--assign` hands over is
ready, so that exit nudges the agent too. The bead `--then-assign` hands over
waits on its blocker, so that exit writes the route alone.

## What performs it

`orders/deferred-dispatch.toml` is a `cooldown` exec order at `scope = "rig"`,
so each importing rig's pass reads its own store on its own clock. Each pass
runs `gctk bead start-armed` on the rig's store (`services/gctk/arm`), which:

- **retires** the arm on each armed bead that has closed, and on each that
  carries a `merge_result`, whatever holds the bead. Another path has delivered
  the work of a bead that carries one, and pouring its formula again would make
  a redundant workflow and input convoy. The arm is cleared with a note that
  names the case, and nothing is slung.
- **selects** the beads to start by the pool's own serve rule: `bd ready` over
  the beads that carry `gc.dispatch_when_ready`, with the flags Gas City
  renders for a pool's routed demand, `--unassigned`, `--exclude-type=epic`
  and an `--exclude-label` for each of `hold:mayor`, `hold:external` and
  `human`. The arm sends what the pool would serve. bd's readiness holds a bead
  on a wait of its own or of any ancestor, so a park on an epic holds an armed
  bead under it whether or not its work has started.
- **holds back** what bd cannot judge, from `gctk bead holds`' answer for the
  bead: a `waits-for` edge of its own, which the answer calls `unjudged`, and a
  wait edge into another store, which bd never holds a bead on. It also holds a
  bead that carries one of Gas City's hold labels in any spelling, as the
  pool's hook does after bd's exact comparison.
- **starts** each bead left, under the bead's dispatch lock (below). It reads
  the bead once more, so an arm removed since the pass listed it is not sent, a
  hold label set since then keeps the arm, and a bead that closed or was
  delivered since then has its arm retired. It resolves the formula: the one
  the arm names, else the target's default. After an earlier attempt it first
  looks for the root that attempt poured (below). It counts the attempt in one
  write, runs `gc sling <target> <bead> --on <formula> --title "<formula>
  arm:<bead>@<armed at>"`, and clears the arm once the sling exits 0.
- **prints** one JSON line per armed bead: `gctk bead holds`' answer for it,
  with what the pass did with its arm. That is a retire and its case, a start,
  a send already made, a hold and what holds the bead, an arm withdrawn since
  the pass listed it, a question to a person, a bead left for the next pass,
  or a failure. A bead at a status other than
  `open` is held, and its line says so on every pass, because no wait landing
  dispatches it.

A held arm keeps its record. Releasing the hold, by closing a park's gate or by
the prerequisite landing, needs no re-arm: the first pass after it dispatches
the bead. `deferred-dispatch.sh list` prints each arm as the start's dry run
reads it: `HELD by <blocker> "<title>"`, adding `on ancestor <id>` when the
wait sits on an ancestor and `(waits-for, unjudged)` for a wait the store
cannot judge yet, `DISPATCHABLE NOW`, `STRANDED` for a status the start never
sends, and the rest by the act the next pass would take.

### Exactly once

Two records Gas City keeps send each arm once.

- `gc sling` exits 3 only when its launch check counts a live workflow on the
  bead, and it names each one. Gas City's launch check refuses a second pour of
  the same formula while the first run is live, so two passes, or a pass and a
  sling a killed pass left running, pour once. An exit 3 that names a workflow
  which is not an unfinished pour (below) means the work is sent already, so
  the arm is cleared and nothing is slung.
- The token `arm:<bead>@<armed at>` titles the root each start pours. Gas
  City's launch check counts only a run that has not finished, so a start that
  died after its sling landed and before it cleared the arm would pour again
  once that run had ended. After an earlier attempt, the start searches for the
  token first (`gc bd list --all --include-ephemeral --include-gates
  --title-contains "arm:<bead>@<armed at>"`). A root it finds that is not an
  unfinished pour means that attempt landed, whichever formula it poured, so the
  arm is cleared and nothing is slung. A start that succeeds the first time
  searches nothing.

A root is an unfinished pour when it carries `molecule_failed=true`, or when it
or a bead poured under it still carries the fence `gc.instantiating`, whatever
their status. Gas City leaves one when a pour fails part way or the sling that
made it is killed, and while such a root is open, `gc sling` refuses every pour
of that formula on the bead. So the start never reads one as the work sent.
When each root an exit 3 names, or each open root the token finds, is an
unfinished pour, the start keeps the arm and asks a person, naming each root
and the command that closes it with its steps, `gc convoy delete <root>
--force`. A closed unfinished pour holds nothing back, so the next start slings.

The retire on a delivered bead covers what neither record sees: the run that
delivered the work was not poured by the arm, so it carries no token, and once
it has ended no live root is left for exit 3.

### When a start keeps failing

The arm counts its attempts. At three, `GC_MAX_DISPATCH_SLING_FAILURES` by
default, the start asks a person instead of slinging again, because each
attempt mints an input convoy. It asks through a human gate on the bead under
the key `deferred-dispatch-sling-failed.<bead>`, or through a conversation
(`gc-helm.sh open`) when the bead has an open child, since a gate on a parent
would hold its unstarted parts too. The arm stays. Disarming it ends the retry,
and disarming and arming it again starts its attempts over. An ask that does
not reach a person keeps the arm, and the next pass asks again.

A record the start cannot read, such as arguments that name no formula alone,
is reported as malformed, and nothing is slung on it. Such a record, and an
arm that names no formula for a target the city's config gives no default,
count no attempt, so the cap never asks a person about either, and
`doctor/check-armed-dispatch-owed` reports both instead (below).

A listing that cannot be read exits non-zero and says so. It never prints an
empty pass, because for a dispatcher "I could not see the queue" and "nothing
was owed" reading alike is the same disappearing hold this machinery exists to
remove. A read of what holds the arms, or of bd's ready set, that fails sends
nothing and fails the pass, while the retires still run.

Three checks keep the halves together. A test in `services/gctk/arm` asserts
that the order ships, is a rig-scoped cooldown that does not opt out of the
single-flight gate, runs `gctk bead start-armed` on its rig's store, and gives
the start's deadline room below its timeout. `doctor/check-cadence-live` (I10)
asserts the registration is live on every importing rig and has fired within
its cadence window: `max(3×interval, floor)`, where the floor is one trip of
the order dispatch rotation (`assets/scripts/order-cadence.sh`). Ship the arm
without the cadence and `arm` still succeeds and writes a well-formed record,
and nothing ever performs it. `doctor/check-armed-dispatch-owed` closes the gap
the other two leave: the cadence can be live and the pass still leave a
dispatch unmade, so it reads each arm from the start's dry run and flags one
the next pass would start, or one nothing holds whose formula the start cannot
resolve, that has stayed armed past the order's window. It also flags one armed
at a status other than `open`, or one whose record does not decode, which the
start never sends.

## The dispatch lock and the time bound

Every start of an armed bead holds the bead's dispatch lock from its read of
the bead to its last write, and so do `gctk bead arm` and `gctk bead disarm`.
The lock is an `flock` on `dispatch-<bead>.lock` under the city's
`.gc/runtime/packs/gc-toolkit/`, the directory Accept's lock uses, and the
bead's id names its store by its prefix. While it is held the file names its
holder's process and when it took the lock. The kernel releases the lock when
its holder ends, however it ends, and no process the holder starts, `gc sling`
among them, carries it.

- A start that finds a bead's lock held leaves the bead for the next pass.
- `arm` and `disarm` wait for a start that holds the lock, up to one sling's
  allowance, and exit non-zero, writing nothing and naming the holder, if it is
  still held. So once `disarm` exits 0, no start has the bead in flight and
  none will send it.
- Two passes over one store need no lock of their own: each sling runs under
  its bead's lock and Gas City's launch lock, and the order's open-tracking
  gate keeps most passes apart anyway.

The order's `timeout` kills a pass wherever it stands, and a sling killed
mid-flight has already minted its input convoy and spent one of the bead's
attempts. So the start begins no sling once less than one sling's allowance,
90 seconds, is left before its deadline, 7 minutes after it began, which sits
below the order's 600-second timeout. Each bead it leaves keeps its arm
untouched, and the next pass starts it. A sling the timeout does kill is found
by the next start's token search, which asks a person when that sling left its
pour unfinished.

`--dry-run` writes, slings and asks nothing and takes no lock. It prints the
line a pass would print for each armed bead.

## A bead whose job ends when other work lands

A bead whose whole job ends once another bead lands, such as a problem in
code another bead retires, still owes a check before it closes, because the
bead it waits on can close without the fix it promised. So it waits on that
bead through a `blocks` edge, and its arm sends it to the validating closer,
`mol-validate-close`, instead of to a worker:

```bash
gc bd dep add <bead> <blocker> -t blocks
"$PACK_DIR/assets/scripts/deferred-dispatch.sh" arm <bead> \
    --target <rig>/gc-toolkit.polecat \
    --sling-arg --on --sling-arg mol-validate-close \
    --reason "waits for <blocker>; the validating closer checks it once that closes"
```

The edge keeps the bead out of `bd ready` while the blocker is open, and the
pass slings the closer once nothing holds the bead. The closer checks the close
brief in the bead's notes against what landed, then closes the bead or puts it
to a person. The waits skill gives the steps an agent runs, the close brief
among them, and the first reaction's close exit writes the edge and the arm
itself when it is given `--waiting-on <blocker>`. A converse sign-off writes the
brief and the arm for its subject when the ruling leaves the subject waiting on
work the sitting sent, after its headline writes the edge
(`--waiting-on <work> --close-brief "<brief>"`), and then lifts the subject's
`hold:mayor`, every spelling of it, so the pass can send the arm.

bd also defines an `until` edge type. Nothing in the pack acts on one, so an
`until` edge holds no bead and closes none.

## What this does not do

It does not make `gc sling` itself dependency-aware, and it does not give
the poured step beads an edge to the work bead. Both of those are changes
to the `gc` binary (the `gascity` rig), not to this pack, and neither is
implemented. An agent that calls `gc sling` directly on a blocked bead
still pours immediately, exactly as before — this mechanism is opt-in at
the call site.

The layer analysis behind that split, and what each `gc`-side direction
would take, is in `specs/tk-y0ygs/layer-determination.md`.

A blocker in another store holds nothing in bd. `bd` resolves a dependency
id within one store, so a `blocks` edge naming a bead in another rig is
dropped from `bd show`, absent from `bd blocked`, and counts for nothing in
`bd ready`. So `arm` refuses a bead with such an edge, and the start holds an
armed bead that gains one, naming the edge on every pass, until the wait moves
into the bead's own store or the arm is removed. The same-store limit belongs
to the hold doctrine (`docs/component-model.md`, I1).
