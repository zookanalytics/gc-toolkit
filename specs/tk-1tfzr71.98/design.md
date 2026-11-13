---
name: Design — deferred dispatch keeps only the arm, as gctk's bead verbs and one order
description: The design for tk-1tfzr71.98, the design child of initiative tk-1tfzr71.16, taken at main dbe034457 and checked against Gas City upstream main 3bcab243e, the city's gc build 6589a7df45 and bd 1.3.4. It states what is left of deferred dispatch and where it lives, the trigger its start runs on, how the start sends each arm exactly once, what holds an armed bead, how a named agent hears about ready work, how a stop removes an arm first, what each writer and reader becomes, how the tests reach the real store, the upstream asks it proposes, and the three units the implementation child files. Read it to approve the design at its gate, or to build one of its units.
---

# Design: deferred dispatch keeps only the arm

This is the design record for tk-1tfzr71.98, the design child of the
initiative tk-1tfzr71.16. The pack was read at main dbe034457, the commit
`integration/tk-1tfzr71.16` was cut from. Each Gas City fact is cited by symbol
at upstream main 3bcab243e (2026-11-12), and checked in the city's gc build,
the fork commit 6589a7df45, wherever the two differ. bd is 1.3.4. The store
counts were read on 2026-11-13 between 01:58Z and 02:10Z.

## What the operator approves

Deferred dispatch is how the pack starts work later. An arm on a bead says
"pour this formula on it through this pool once nothing holds it". Today a
script of 1,325 lines, with a test of 2,190, runs a pass every five minutes in
each rig. The pass carries its own lock, time budget and crash marker, and a
second job: telling a named agent, such as the mechanik or a refinery, that
work assigned to it is ready. Approving this design keeps the arm, which is the
one job Gas City cannot do, and rebuilds it as three gctk verbs and one order.
It deletes the script and drops what Gas City now does or reports itself. The
203 arms open across six rig stores carry over with no write. What reaches you
does not change: a start that keeps failing still asks you through a human
gate.

Three calls carry a cost either way:

1. **The start runs on the five-minute cadence only.** An armed bead starts
   within one cadence of its release. The order's passes ran 5 to 9 minutes
   apart in each rig over the week to 2026-11-13, not five, because every
   order shares one dispatch budget. A second registration per rig on
   Gas City's bead-close event would usually start it within about a minute.
   It would add six registrations to the order ring whose budget is already
   waiting on your ruling (tk-q9rnmfr), which slows every other order's turn.
   The event could never be the only trigger either, because Gas City's event
   bus drops events by design. So the initiative's Done line, "no pass polls
   for ready work", does not hold: the cadence is what the rule that admits an
   order requires (section 3).
2. **A named agent hears about ready work from one pass, not from a record
   each writer must leave.** Today an assignment tells the agent only when its
   writer remembers to record a notice, so your own `bd update --assignee`
   tells nobody (tk-t91hbtx). The start's pass instead nudges each named
   session about every ready, unclaimed bead assigned to it, once per bead,
   whoever wrote the assignee. The cost is latency where nothing else speaks
   first: a notice the old verb sent at once can wait up to one cadence. Gas
   City's own nudge still reaches a running agent when a blocker closes, and a
   writer that knows its bead is ready nudges at the write. The other way keeps
   the per-bead record and its verb beside the pass, two mechanisms for one
   notice (section 6).
3. **An arm whose bead waits on a bead in another store is held until someone
   moves the wait.** bd in this city never holds a bead on such an edge, so
   today the arm can fire while the other bead is still open (tk-ajlktr0). The
   start holds such a bead and says so on every pass, and `arm` refuses one.
   One armed bead has such an edge today, onto a bead that has closed, and the
   implementation child removes that edge. The other way reads the other
   store's bead on every pass, which builds for a shape the pack already
   refuses to write (section 7).

Approving the design as it stands ships the first option of each. Section 8
answers each held problem, and section 13 lists the units.

## 1. What is left of deferred dispatch

One job is left. An arm pours a named formula on a bead through a pool, once
nothing holds the bead, exactly once. It pours nothing on a bead that has
closed or whose work another path has delivered.

Gas City still has no expression for it at upstream 3bcab243e:

- No core order or script calls `gc sling`. A search of
  `internal/bootstrap/packs/core/assets` and `orders` for the command finds
  only comments in `nudge-on-route`.
- The core order `cascade-nudge-on-blocker-close` runs on `bead.closed`. Its
  script re-reads the closes with `gc events --type bead.closed --since 5m`,
  lists each closed bead's `blocks` dependents, and nudges every open or
  deferred one that no other blocker holds (`still_held`), at its assignee or
  else its `gc.routed_to` target. It pours nothing.
- The core order `nudge-on-route` runs on `bead.updated` and nudges a bead's
  `gc.routed_to` target once per pair of bead and target. It pours nothing.
- `gc sling` pours at once. Nothing in `internal/sling` or
  `cmd/gc/cmd_sling.go` reads the bead's readiness before a pour, and
  `validateExistingBeadInQuerier` checks only that the bead exists. A dry run
  on the installed build prints "A wisp will be attached automatically" for a
  blocked bead.

Main has moved past the initiative's description. The until disposal is gone,
by the operator's ruling in conversation tk-u5edbg1, and #1390 deleted
`until-resolved.sh`, `live-work.sh` and `doctor/check-until-resolved-owed`.
`hold-lib.sh` is gone too, and the pass asks `gctk bead holds` what holds each
armed bead (#1454). The warrant in `docs/warrants.md`, "Deferred dispatch
residual", stands as recorded, and unit 1 re-verifies its evidence at the
upstream commit it builds against.

Retiring here: the notice and its record (`deferred-dispatch.sh notify`,
`gc.notify_when_ready`), the per-rig pass lock, the two-state crash marker
(`gc.dispatch_when_ready_slung`), the pass's partial-outcome declarations, and
the script itself.

## 2. Where it lives

The arm moves into gctk's `bead` domain in this member, as
`docs/gctk-architecture.md` plans it, and the port deletes the shell it
replaces in the same change (item P5 of `docs/built-once-target.md`).

| Verb | Caller class | What it does |
|---|---|---|
| `gctk bead arm <bead> --target <rig>/<pool> [--on <formula>] --reason <text> [--db <path>]` | agent, hook | Records the arm. With no `--on` it records the target's default formula, read from `gc config show --json` (`DefaultSlingFormula`). It refuses a closed bead, a bead not `open`, a bead already dispatched (`in_progress`, or a `gc.routed_to` route), a target with no formula to pour, and a bead with a wait edge into another store. An arm already present with the same target and formula is a success that writes nothing, and a different one is refused. |
| `gctk bead disarm <bead> --reason <text> [--db <path>]` | agent, hook | Removes the arm in one write, under the bead's dispatch lock (section 4). It exits 0 once no arm remains, the case where none was there included. Once it exits 0, no start has the bead in flight and none will send it. |
| `gctk bead start-armed [--db <path>] [--dry-run]` | order | Retires the arm on each closed or delivered bead, starts each armed bead nothing holds (section 4), and nudges each named session about its ready, unclaimed assigned work (section 6). |

Nothing remains of `deferred-dispatch.sh`. `orders/deferred-dispatch.toml`
keeps its name, cadence, rig scope and single-flight gate, so
`doctor/check-cadence-live` and the order's history carry on, and its `exec`
runs `gctk bead start-armed`. `assets/scripts/dispatch-path.sh` stays as it is:
the arm's key is still a dispatch path, and its readers need no change.

The whole files that retire are `assets/scripts/deferred-dispatch.sh` and
`assets/scripts/deferred-dispatch.test.sh`, 3,515 lines at dbe034457. They take
no row in `tools/deletion-plan.tsv`. A row matters only on main, and the
landing that carries this effort to main deletes both files in the same change.
The last unit updates lane B's row in `docs/built-once-target.md` from "partial
files" to the measured net.

A caller that names the script by path calls the gctk verb through the
`gctk-bin` block afterwards (`assets/scripts/gctk-bin.test.sh` holds every copy
of it to one line):

```bash
"$GCTK" bead arm <bead> --target <rig>/gc-toolkit.polecat --on mol-validate-close --reason "waits for <blocker>; the validating closer checks it once that closes"
"$GCTK" bead disarm <bead> --reason "<why>"
```

Listing the arms needs no verb. `gc bd list --has-metadata-key
gc.dispatch_when_ready` lists them natively, and `gctk bead holds` already
prints each bead's arm beside what holds it.

The arm keeps its keys, so no stored arm is rewritten: `gc.dispatch_when_ready`
(the target), `_args`, `_armed_by`, `_armed_at`, `_reason` and `_fail_count`.
The crash marker `gc.dispatch_when_ready_slung` and the notice key
`gc.notify_when_ready` stay registered in `lifecycle/lifecycle.toml` as
retired, so residue reads as known and no doctor error fires on it. The arm's
note keeps its prefix, `deferred-dispatch: `, because `mol-validate-close`
reads that note when a bead has no close brief and `converse-signoff.sh` uses
it to find where a close brief ends.

## 3. Event or cadence

The start runs on a cooldown cadence, every five minutes per rig, as the
existing registration does. `docs/gctk-architecture.md` admits an order only
when each pass converges from durable state, because Gas City's event bus is
lossy by design: a bare `bd` write reaches it only through the controller's
cache rescan, which skips some changes, and an exec order's cursor moves before
its script runs. An event can cut the latency but can never decide, so a
cadence must run anyway. A second registration on `bead.closed` is call 1's
other way, and its cost is six more registrations on a ring the dispatch budget
already stretches (`orders.max_dispatches_per_tick`, 4 by default).

The cadence runs longer than its interval, because the budget serves every due
order in turn. In the city's event log and its archives, from 2026-11-05
16:06Z to 2026-11-13 02:59Z, the order's `order.fired` events in each rig came
5.0 to 9.0 minutes apart, median 6.0.

What the chosen shape still needs:

- **The lock, reshaped.** The per-rig pass lock retires. Two passes over one
  store can no longer pour twice, because each sling runs under the bead's own
  dispatch lock and Gas City's launch lock (section 4). What remains is one lock
  per bead, which the rule that admits an order requires ("one lock shared with
  every pack writer of the field it writes"), held by `arm`, `disarm` and the
  start.
- **A time bound, not a budget with declarations.** The order rule requires a
  per-pass call and time budget its suite asserts. The start stops starting
  slings once less than one sling's allowance remains before a deadline set
  below the order's timeout, and leaves the rest armed for the next pass. A
  sling the timeout kills is recovered by section 4's search. The partial and
  skipped outcome declarations retire, since the next pass and the doctor's
  owed check carry what a pass leaves.
- **No marker.** Section 4 replaces it.

## 4. Exactly once

A dispatch stops being owed once its bead closes or another path delivers its
work. Before the start asks what holds an armed bead, it disarms each one in
either case, with a note that names the case, and slings nothing, as
`deferred-dispatch.sh`'s pass does today:

- **The bead has closed.**
- **The bead carries a `merge_result`.** Another path has already delivered
  its work, and pouring the formula again would make a redundant workflow and
  input convoy.

Both retire the arm whatever holds the bead. The start names each arm it
retires, and a dry run names each retire it would make and writes nothing.

`merge_result` is the anchor state (`lifecycle/lifecycle.toml`). The
refinery's patrol writes it when it takes a bead's work: `pre_open_gate` or
`pull_request` at merge-push, or `blocked` or `refused_false_completion` when
one of its checks stops the work. `pr-open.sh`, `pr-facts.sh` and `merge.sh`
move an anchor on from there. A polecat's hand-off writes none. Work sent back for rework
carries none either. A sign-off's rework is a child bead of its own, and
`rejection-repool.sh` moves a rejected bead to unanchored, which removes the
key, before it pours the rework or arms its re-sling. So the retire leaves
alone the arm that re-sends work in flight, the case section 7's exception
covers. tk-iqpxk89 is one, read on 2026-11-13 at 03:32Z: a sign-off's rework
armed for `mol-polecat-work` that carries its branch and rejection reason and
no `merge_result`.

Each start of an armed bead runs these steps, holding the bead's dispatch lock
from the first to the last. The lock is a `flock` file per store and bead under
the city's `.gc/runtime/packs/gc-toolkit/`, the directory Accept's lock already
uses.

1. Read the bead once more. An arm removed since the pass's listing is not
   sent, and a hold label set since then keeps the bead armed. A bead that has
   closed or gained a `merge_result` since then has its arm retired as above.
2. Resolve the formula: the arm's `--on`, or else the target's default formula.
3. When the arm records an earlier attempt (`_fail_count` above 0), search for
   a workflow root titled with the arm's token, `<formula> arm:<bead>@<armed
   at>`. A root that is not a closed `molecule_failed` one means the earlier
   attempt landed: disarm, and stop here.
4. Raise `_fail_count` by one in one write.
5. Run `gc sling <target> <bead> --on <formula> --title "<formula>
   arm:<bead>@<armed at>"`.
6. Exit 0: disarm. Exit 3: disarm too, because `gc sling` exits 3 only when a
   live workflow already works the bead (`sourceworkflow.ConflictError`, mapped
   to 3 in `cmd/gc/cmd_sling.go`), so the work is already sent. Any other exit
   keeps the arm for the next pass. At three attempts the start asks a person
   instead of slinging, as the pass does today, through `human-gate.sh` under
   the key `deferred-dispatch-sling-failed.<bead>`, or through
   `gc-helm.sh open` when the bead has an open child.

What Gas City reports is enough while the first run is live. Its launch takes a
per-bead lock and refuses a second root of the same formula while one is live,
and a dry run reports the same check, scoped to the formula
(`dryRunReportBlockingMolecule`, which calls
`sling.LiveConvoyTrackedWorkflowRoots`, "the same check
checkLegacySourceWorkflowConflict runs at launch time"). Two passes, or a pass
and a sling a killed pass left running, therefore pour once. Gas City cannot
report a run that has finished, because the launch check counts only roots
that are not terminal. So a start that died after its sling landed, and before
its disarm, would pour again once that run had ended. The token closes that
window. It is a title on Gas City's own root, found by
`gc bd list --all --include-ephemeral --title-contains`, the way Accept finds
its own pour (the "Accept's lock" warrant). It is searched only after an
earlier attempt, so a start that succeeds the first time costs no search.

The launch check has a second half: it also refuses while a live root of any
formula names the bead in `gc.source_bead_id`
(`checkLegacySourceWorkflowConflict`, `internal/sling/sling_core.go`), a key
its comment says a convoy-first `--on` launch never stamps. So an exit 3 can
also mean that a run of another formula, launched some other way, already works
the bead. The start reads that as sent too, since the bead is already being
worked, and it prints the line `gc sling` printed, which names the live
workflow.

Neither the token nor exit 3 sees work that another path delivered, which is
why the delivery stamp retires an arm. The run that delivered the work was not
poured by the arm, so its root carries no token, and once that run has ended
no live root is left for exit 3. The lifecycle writer clears the assignee when
an anchor enters `pre_open_gate` or `pull_request` (`detached_states` in
`lifecycle/lifecycle.toml`), so a delivered bead reads open and unassigned, and
section 7 says why `gctk bead holds` can answer `clear` for it. A start that
read only Gas City's records would pour it again. The stamp outlives the run
that delivered the work, so the start reads the stamp.

The two-state marker retires. Its `slinging@` state meant "try again", which
the start now does by default, and its `slung@` state meant "already sent",
which exit 3 and the token now answer from Gas City's own records. The marker
also cost a write after every sling. A malformed arm no longer shares an exit
with `gc sling`: `arm` validates what it records, and the start reports a
record it cannot read as malformed, in words, and slings nothing (tk-cedhuvm).

Every formula an arm names today is a graph.v2 formula. All four, core's
`mol-polecat-report` included, declare `formula_compiler = ">=2.0.0"`, which
`formula.UsesGraphCompiler` reads as a graph formula. The lock and the token do
not depend on Gas City's launch lock, which covers only the case of a sling
still running after the pass that started it was killed.

## 5. The arms in every store, and the cut-over

The deferred-dispatch order is registered on six rigs: gc-toolkit, gascity and
four more, written here as rig-a to rig-d. The city store holds no arm and no
notice.

| Store | Arms | `mol-validate-close` | `mol-polecat-work` | `mol-design-convoy` | `mol-polecat-report` | no formula named | Notices |
|---|---|---|---|---|---|---|---|
| gc-toolkit | 144 | 70 | 24 | 6 | 4 | 40 | 8 mechanik, 2 refinery |
| gascity | 8 | | 1 | | | 7 | |
| rig-a | 17 | 5 | 6 | | | 6 | |
| rig-b | 11 | 3 | 4 | | 1 | 3 | 1 mechanik |
| rig-c | 7 | | | | 4 | 3 | 4 refinery |
| rig-d | 16 | | | | | 16 | |
| **all** | **203** | **78** | **35** | **6** | **9** | **75** | **15** |

Every arm is on an `open` bead, every target is a polecat pool except one, and
no arm is assigned, carries a hold label, a crash marker or a failure count.
Every arm records its arm time. `gctk bead holds` holds all 203: 197 by a wait
of their own before their work has started, 4 in flight by a wait of their own,
1 through its epic's park (tk-rctkrj.2, under the park gate tk-u5t8h6x), and 1
by its own wait while also carrying a wait edge into another store (tk-nt5uda,
onto the closed gc-vz6v0).

No arm is a raw route. An arm with no formula named pours its target's
`default_sling_formula`, which is `mol-polecat-work` for both kinds of target
the arms name. The initiative's dry run on the installed gc 1.4.3 shows it for
the polecat pool, and a dry run on the one arm whose target is not a polecat
pool, a bead in rig-c's store armed for `rig-c/gc-toolkit.proactive`, names
`mol-polecat-work` as the formula it pours. What each class becomes:

- **An arm that names its formula** is sent as it is.
- **An arm that names none** is sent on its target's default formula, which the
  start names explicitly so the root carries the token. That is what a bare
  sling pours today, so nothing changes for these 75.
- **A raw route** needs no arm, because a pool serves a raw-routed bead only
  once bd reports it ready. `arm` refuses a target with no formula to pour, and
  its message gives `gc sling <target> <bead> --no-formula --no-convoy`.

The cut-over writes nothing to the stores. The new start reads the same keys,
so the 203 arms carry over when the landing reaches main. No arm carries the
crash marker. The 15 notice records become inert, and the start's notice pass
covers the beads they name, because each is assigned to the named session it
would have told. Two arms need a word. The edge from tk-nt5uda onto gc-vz6v0
holds nothing today, because its target has closed, but section 7's rule would
hold the arm on it, so the implementation child removes that edge (section 14).
The arm aimed at rig-c's proactive agent stays, and behaves as it does today.

No wait strands silently. The start names on every pass each arm it holds and
why, each arm at a status other than `open` or `closed`, and each assigned arm,
and `doctor/check-armed-dispatch-owed` still reports an arm nothing holds that
has stayed armed past the cadence window.

## 6. A named agent hears about ready work

What Gas City does on the city's build:

- **A blocker closes.** `cascade-nudge-on-blocker-close` nudges the assignee
  of each dependent no other blocker holds. The city's copy, which matches the
  fork commit 6589a7df45 byte for byte, queues that nudge
  (`--delivery=queue --reference-bead <dependent>`, fork change gc-f3k8d,
  51055e7d3f). A queued nudge reaches a running session at its next idle
  boundary and never wakes one that is not running: `gc session nudge`'s help
  says "queue delivers it as a notice at the next boundary and never wakes the
  session", and `queueSessionNudgeWithWorker` enqueues it and requests no wake.
  Upstream's own copy at 3bcab243e sends the nudge with the default delivery.
- **The default nudge gives an idle named session a turn.** With the default
  delivery, `wait-idle`, `deliverSessionNudgeLegacy` delivers to a running idle
  session at once. For a session that is not running, `shouldQueueManagedNudgeWake`
  answers true, and `queueManagedSessionNudgeWake` queues the nudge and records
  a wake (`RequestWakeUnlessHeld`), so the controller starts the session and the
  nudge reaches its first boundary. This is read from the build's source at
  6589a7df45, not from a live run, and unit 2 records a live check.
- **No backstop covers a named session.** Gas City's idle-claim backstop
  re-nudges a pool slot whose assigned work it never began, and its comment
  says "Pool slots only." (`nudgeStalledPoolClaims`, `cmd/gc/idle_nudge.go`).
- **Nothing nudges on an assignee write.** `nudge-on-route` reads
  `gc.routed_to`, and cascade-nudge reads only closes and only `blocks` edges.

So one notice survives, for one case: a ready, unclaimed bead assigned to a
named session. The start's pass sends it, whoever wrote the assignee, which is
tk-t91hbtx's ask. For each named session, the configured named agents as
`gc session list` reports them, it reads the beads bd reports ready and
assigned to it in the rig's store, the hook's own assignee tier. It nudges the
session with the default delivery about each one it has not nudged about
before. A ledger records each pair of session and bead after its nudge exits
0. It is a state file per store under the pack's state directory, the shape
core's cascade-nudge keeps. An entry is dropped once its bead is claimed,
closed, reassigned or no longer ready, so a bead that becomes ready again is
nudged again. A lost ledger costs one repeated nudge per bead, never a missed
one.

The record and its verb retire, and so do their failure modes: a writer that
forgets to record, a record lost between a retire's read and its unset, and a
notice on a city-store bead that no rig pass ever reads. A writer that assigns
a bead it knows is ready nudges at the write, so the agent hears at once:

```bash
gc bd update <bead> --assignee <session> && gc session nudge <session> "<bead> is assigned to you and ready: run gc hook --claim --json"
```

A writer that assigns a bead still waiting on a blocker writes only the
assignee, and cascade-nudge or the pass tells the agent once it is ready. The
pass covers rig stores only, and the city store holds no notice today. Each
caller of `notify` becomes one of the two forms in section 10.

## 7. What holds an armed bead

The start sends an armed bead only when all of these hold: `gctk bead holds`
answers `clear` and lists no wait edge into another store, the bead is `open`,
it has no assignee, and it carries no hold label (`has_dispatch_hold` in
`dispatch-path.sh`).

The test reads only arms still owed, because section 4 retires the arm on a
closed or delivered bead first. The delivery stamp has to be read there and not
here. `gctk bead holds` reads a `merge_result` as evidence that the work is in
flight, not as a hold (`rowFlight`, `services/gctk/waits/waits.go`), so a
delivered anchor is held only by its own waits and answers `clear` once they
land.

That test is bd's readiness with one named exception and two holds bd does not
make.

- **The exception.** Work in flight is held only by its own waits, so a park
  on its epic leaves it running, by `docs/steering.md`'s definition of in
  flight. bd's readiness cascades every ancestor's wait down parent-child
  edges, and `gctk bead holds` keeps that cascade for work that has not
  started.
- **A `waits-for` edge of the bead's own** is unjudged, because the bd the city
  runs judges it by its spawner's status rather than its gate, so the start
  holds it.
- **A wait edge into another store** holds the bead too. bd never blocks a
  dependent on a cross-prefix target, as upstream's
  `internal/readywork/crossstore.go` records ("beads v1.3.2,
  issueops.IsExternalDepTarget"). Gas City re-judges such an edge only on a
  city with a class binding, and the city's `gc config show` names none.

The park model works with native readiness, not against it. A park is a gate
that blocks an epic, bd's cascade holds every unstarted member under it at any
depth, and the start honors that because it reads the same answer. The one
place the two differ is work already started under a parked epic, which the
steering model keeps running on purpose, so an armed re-dispatch of it fires
once its own waits land. No arm is in that shape today. The 4 armed beads in
flight are each held by a wait of their own, and the one armed member of a
parked epic has not started.

## 8. The held problems

- **tk-t91hbtx, a notice whoever wrote the assignee.** Section 6's pass notices
  every ready, unclaimed bead assigned to a named session, from the assignee
  and bd's readiness, with no record a writer must leave. Unit 2.
- **tk-ajlktr0, an arm fired past a cross-store blocker.** On bd 1.3.4 such an
  edge holds nothing in bd's readiness (section 7). The start holds a bead with
  any wait edge into another store and names it on every pass, `arm` refuses
  one, and the pack already refuses to write such a wait (#1414). Unit 1.
- **tk-v6bnjjp, a `conditional-blocks` or `waits-for` blocker ignored.** That
  finding read `hold-lib.sh`, which is gone. `gctk bead holds` reads bd's
  blocked set, which counts `conditional-blocks`, and answers `unjudged` for a
  `waits-for` edge of the bead's own, and the start holds both. Unit 1 adds a
  store acceptance case for each, an unstarted armed bead whose only open
  blocker is that edge, run against the real bd.
- **tk-cedhuvm, exit 3 read as malformed arguments.** Exit 3 means a live
  workflow already works the bead, so it retires the arm, and no pack failure
  shares that exit (section 4). Unit 1.

Each of these waits on tk-1tfzr71.16 through a `blocks` edge with an armed
validating closer, which checks it once the effort lands on main.

## 9. Stopping an armed bead

A write that stops an armed bead, or sends it on by another way, removes the
arm first, through `gctk bead disarm`, and goes on only once that exits 0. The
disarm takes the bead's dispatch lock, so a start already sending the bead
finishes before the disarm returns, and the run it poured is there for the stop
to cancel. A start that has not reached the bead yet reads the arm gone. So
once the disarm returns, releasing the bead's holds sends nothing.

The writers, in the order the census read them:

- **`stand-down.sh`** already disarms before its release, its gate answers and
  its close. It keeps that order and calls the verb.
- **`gc-helm.sh takeaway --release`** never touches the arm, so a stopped armed
  bead goes out again once nothing holds it (tk-5trydl2). Its first write
  becomes the disarm, before the release write, the edges, the run cancel and
  any `--route`. `first-reaction-dispose.sh`'s blocked exit arms after its
  release, so it is unaffected.
- **`gc-helm.sh accept`** answers the recommendation's gate before its own
  `gc sling --on`. On an armed bead the answer could release the arm ahead of
  Accept's pour, so Accept disarms first too.
- **The sitting skills** (`converse-settle`, `converse-continue`,
  `converse-epic-review`) and the work skill already disarm before they answer
  a gate, re-send or close, and they call the verb.

tk-77b54fz and tk-ks7yjzo are about the release's own write, which reopens a
bead that closed between its read and its write, and cannot stop a raw-routed
bead a live polecat holds. Their validating closers were slung when
tk-1tfzr71.15 landed. This design changes only the arm's part of the release.

## 10. Every writer and reader, and what each becomes

`git grep -l -E 'deferred-dispatch|dispatch_when_ready|notify_when_ready'`,
excluding tests, specs, generated files and test data, finds 64 files at
dbe034457.

**Arms**, each moving to `"$GCTK" bead arm` (unit 3): `AGENTS.md`'s hold rule,
`await-ruling.sh` (which `decline.sh`, `work-gate.sh` and `work-setup.sh`
reach), `converse-signoff.sh`, `finding.sh`, `first-reaction-dispose.sh`'s
close exit and `--then-route`, `gc-helm.sh place`, `rejection-repool.sh`,
`store-only-exit.sh` (which `work-submit.sh` reaches), `mol-design-convoy`'s
dispatch step (the implementation child and the summary task), and the
`waits`, `converse-settle` and `work` skills, `skills/work/integration-effort.md`
and the `watch-dispatched-work` fragment. `first-reaction-dispose.sh`'s
`--then-route` arm names no formula today and records the target's default.

**Disarms**, each moving to `"$GCTK" bead disarm` (unit 3): `stand-down.sh` and
the `converse-continue`, `converse-epic-review`, `converse-settle`, `waits` and
`work` skills. `gc-helm.sh takeaway --release` and `accept` gain one (section 9).

**Notices** (unit 2). These writers assign a bead that waits on a blocker, so
each writes only the assignee: `mol-design-convoy`'s dispatch step, which hands
the landing bead to the refinery, `skills/work/integration-effort.md` for the
landing and a hand-off, the refinery prompt's bring-current conflict hand-off,
and `first-reaction-dispose.sh --then-assign`. These assign a bead that is
usually ready, so each nudges at the write when bd reports it ready:
`first-reaction-dispose.sh --assign`, the `work` skill's named-agent
assignment and the `watch-dispatched-work` fragment. Unit 2 reads each site's
bead at the write before it picks the form, and a site whose bead can be either
nudges only when bd reports it ready.

**Readers of the keys** keep reading the same keys and need no change:
`dispatch-path.sh` and the readers that source it (`tools/gc-proactive.sh`,
`check-blocked-work-armed`, `check-step-terminal`), `bead-context.sh`
(`--frontier` reads the fail count), `blocker-holder.sh`, `pr-facts.sh`,
`pre-open-rebase.sh`, `seed-audit-reaudit.sh`, `finding.sh`'s read-back,
`gc-helm.sh place`'s comparison, `check-po-queue-only`, and in Go
`queue.scheduled`, `cli.mergeInDeferred` and the helm board's `selfStart`. Four
readers change. `stand-down.sh` stops reading the notice key (unit 2).
`services/gctk/waits/keys.go` drops `armSlungKey` (unit 1) and `noticeKey`
(unit 2), and `key-registry.json` follows. `skills/work/integration-effort.md`
stops testing `.arm.slung` from `gctk bead holds` and tests the arm alone
(unit 1).

**The doctor checks:**

- `check-armed-dispatch-owed` survives. It still reports an arm at a status
  other than `open` or `closed`, and an arm nothing holds past the cadence
  window, through `gctk bead holds`. It still passes over the arm on a closed or
  delivered bead, which the start retires. It stops reading the marker
  (unit 1).
- `check-blocked-work-armed` survives unchanged. Its finding's remedy names
  `gctk bead arm` (unit 3). Open PR #1486 (tk-ltcv43q) edits this check, and
  whichever lands second takes the other's lines.
- `check-po-queue-only` survives. Its remedy text names the verbs (unit 3).
- `check-step-terminal` survives unchanged.
- `check-cadence-live` drops its `flock` requirement only if no pass lock
  remains anywhere. `refinery-reconcile.sh` takes one through `bd-lib.sh`, so
  unit 1 checks before it removes it.

**Files the deletion plan retires.** `finding.sh` (tk-1tfzr71.22) and
`rejection-repool.sh` (tk-1tfzr71.20) each change only the line that calls the
script, so they keep working until their retirement. `pr-facts.sh`
(tk-1tfzr71.21) and `pre-open-rebase.sh` (tk-1tfzr71.20) only read keys that
do not change, so they take no edit.

**Open PR #1488** (tk-1tfzr71.20) adds an arm in `refinery-requeue.sh` and a
notice in `effort-bring-current.sh`, and drops `rejection-repool.sh`'s arm. It
also edits `dispatch-path.sh`'s header and `stand-down.sh`'s refusals, lines
this design does not change. Whichever of #1488 and unit 2 or 3 lands second
converts the other's call sites.

**The docs** that describe the script move to the verbs in the unit that
changes the behavior they describe: `docs/deferred-dispatch.md`,
`docs/gctk-architecture.md` (the three rows, and `start-armed`'s defense, which
no longer names a window it leaves), `docs/warrants.md`,
`docs/authority-map.md`, `docs/component-model.md`, `docs/human-engagement.md`,
`docs/install.md`, `docs/state-machine.md`, `docs/steering.md`, the route step
in `docs/architecture.md` and the `docs/gascity/` pages that link the script.
Other files name the script in passing, and each changes in the unit that makes
its line untrue. `docs/refinery-merge-cadence.md` says the script takes its
pass lock through `bd-lib.sh`, which unit 1 ends. `docs/pack-authoring.md`
links the notice section that unit 2 rewrites. `docs/review-correctness.md` and
`docs/review-demo.md` take their examples from the script and its test, and
`assets/scripts/test-harness.sh`'s comments name both, so unit 3 replaces each
when it deletes them.

Callers find the script today through `GC_DEFERRED_DISPATCH_TOOL` or
`GC_DEFERRED_DISPATCH_SH`, which their tests set. Both retire with it, and the
tests set `GCTK_BIN`. `GC_MAX_DISPATCH_SLING_FAILURES`, which `bead-context.sh`
and the owed check also read, stays the cap's setting.

## 11. Tests against the real store

The shell suites stub bd, and the stub enforces none of bd's close or edge
semantics, which is how stand-down's worst defect reached a hand-run proof
before any suite (`specs/tk-utv2kaq/real-store-proof.sh`). gctk already runs
the bd the city runs against a scratch store on a Dolt server of its own
(`services/gctk/internal/gcbd/acceptance_test.go`,
`GCTK_STORE_ACCEPTANCE=1`). The arm's tests use that harness:

- **What holds an armed bead**, one case per shape, each compared with what the
  real bd does: an open and a closed `blocks` blocker, a `conditional-blocks`
  blocker alone, a `waits-for` edge alone, a park on an ancestor for unstarted
  and for in-flight work, a hold label, a status other than `open`, and a wait
  edge into another store.
- **The retirements**: an open, unassigned armed bead that carries
  `merge_result=pull_request` with no open blocker and no live workflow left on
  it, the same at `pre_open_gate`, the same behind an open `blocks` blocker,
  and an armed bead that has closed. In each the start slings nothing, the arm
  is gone, and the note names the case, with the `merge_result` it read. A dry
  run of each reports the retire and writes nothing.
- **The stop's order**: an armed bead behind a human gate, then the disarm,
  then the gate's answer, after which the start sends nothing.
- **The writes**: `arm` and `disarm` against the real store, and the start's
  disarm after a sling.

A test cannot run Gas City's launch, so `gc sling` is a shim that records each
call and exits 0, 1 or 3 as the case says, and the exit-3 case pins
tk-cedhuvm's answer. Unit 3 runs stand-down's real-store proof again against
its scripts. The store harness is opt-in, as it is today, so each unit runs it
and records the run in its PR. The retirement cases also run in gctk's
ordinary suite on its fake store (`services/gctk/internal/gcbd/fake`), so they
run on every test run. They carry the regression `deferred-dispatch.test.sh`
holds for the delivered retire, which unit 1 deletes with `reconcile`.

## 12. The upstream asks

The design proposes two asks to Gas City. Posting them is the operator's
decision, and neither is sent.

1. **A launch that waits on readiness.** `gc sling <target> <bead> --on
   <formula>` with a flag that records the launch on the bead and performs it
   once Gas City's readiness first reports the bead ready, exactly once under
   a caller's key whatever an earlier root's status. It would retire the arm,
   its order, the dispatch lock and the title token, and with the key it would
   retire Accept's lock too. It is the trigger the warrant names for its
   retirement.
2. **A claim backstop for named sessions.** The idle-claim backstop serves pool
   slots only. Extended to a named session holding ready, unclaimed assigned
   work, it would retire the start's notice pass. The city's gascity rig
   tracks that gap as gc-pn2gms.

## 13. The units

Each unit lands on `integration/tk-1tfzr71.16` and leaves the pack's tests
passing. Nothing reaches the city until the effort's PR merges to main, so the
new start replaces the old pass at that landing, with every arm carried over
(section 5). Each unit waits on the one before it.

1. **The start in gctk.** Build `gctk bead arm`, `gctk bead disarm` and
   `gctk bead start-armed` with sections 4 and 7: the retirement of the arm on
   a closed or delivered bead, the dispatch lock, the formula resolution, the
   token, exit 3 as sent, the cap's ask and the time bound. Point
   `orders/deferred-dispatch.toml`'s `exec` at the verb. Delete
   `reconcile` from `deferred-dispatch.sh` with its pass lock, budget, marker
   and outcome code, and have its `arm` and `disarm` call the gctk verbs until
   unit 3 deletes the file. Register the marker key as retired, drop
   `armSlungKey`, change the owed check and `integration-effort.md`'s
   `.arm.slung` test, and add section 11's cases, with the retirements in
   gctk's ordinary suite as well as the store harness. Update
   `docs/deferred-dispatch.md`'s account of what performs the arm,
   `docs/gctk-architecture.md`'s rows, `docs/refinery-merge-cadence.md`'s lock
   line and the warrant, whose Covers gains the dispatch lock and the token and
   whose evidence is re-verified at the upstream commit the unit builds
   against. It answers tk-ajlktr0, tk-v6bnjjp and tk-cedhuvm.
2. **Notices from the pass.** Add section 6's notice half and its ledger to
   `gctk bead start-armed`. Retire `notify` and `gc.notify_when_ready`
   (registered as retired, `noticeKey` dropped, `stand-down.sh`'s read
   removed), move each notice caller to section 10's form, rewrite the notice
   section of `docs/deferred-dispatch.md`, and point `docs/pack-authoring.md`'s
   link at the rewritten section. Record a live check that a default nudge
   gives an idle named session a turn on the city's build. It answers
   tk-t91hbtx.
3. **Callers onto the verbs, and the script goes.** Move every arm and disarm
   caller in section 10 onto the verbs, add the disarm to `takeaway --release`
   and `accept` (section 9), delete `deferred-dispatch.sh` and its test, retire
   the two path variables, move the remaining docs, re-run stand-down's
   real-store proof, and update lane B's row in `docs/built-once-target.md`.
   It answers tk-5trydl2.

What each unit releases: none releases a waiting bead by itself. tk-1tfzr71.17
and tk-1tfzr71.25 wait on tk-1tfzr71.16 with `blocks` edges, and so do the four
held problems, so all of them are released when the effort's PR merges to main
and closes tk-1tfzr71.16. tk-1tfzr71.17 then builds its intake exits on the
two verbs and the assignee-only notice, and tk-1tfzr71.25 retires the registry
entries this effort leaves marked as retired. The held problems' validating
closers check each answer above once that landing is on main.

## 14. Edges and notes the implementation child adds

- **tk-5trydl2** waits on tk-1tfzr71.16: a close brief naming section 9's
  disarm, a `blocks` edge (both carry the `tk` prefix), an armed validating
  closer, and the lift of its `hold:mayor`, by AGENTS.md's recipe.
- **tk-nt5uda** loses its `blocks` edge onto gc-vz6v0, a closed bead in the
  gascity store, with a note saying why, so section 7's rule cannot hold it once
  its own blocker tk-wmwcdlc.4 closes.
- **tk-1tfzr71.20** gets a note naming section 10's #1488 call sites and which
  unit converts them if #1488 lands first.
- **tk-1tfzr71.22** gets a note that `finding.sh`'s arm call moves to
  `gctk bead arm`, so its replacement arms through the verb.
- **The units** are filed as tk-1tfzr71.99's description says, with
  `target=integration/tk-1tfzr71.16` in each create, and tk-1tfzr71.16 and the
  summary task wait on each.

## 15. Gas City facts, and the search behind the surface the units add

The units add three verbs, an order's new `exec`, a lock per bead, a title
token on the pours they make and a notice ledger. For each, the search was for
a Gas City or bd primitive that pours on readiness, nudges a named session
about assigned work, or reports a finished launch, and none covers the need.

| Fact | Upstream 3bcab243e | The city's build 6589a7df45 |
|---|---|---|
| Nothing pours a formula when a bead's blockers close | no core order or script calls `gc sling`; `cascade-nudge-on-blocker-close.sh` and `nudge-on-route.sh` only nudge | same scripts, plus the queued delivery below |
| `gc sling` pours without reading readiness | `internal/sling`: `validateExistingBeadInQuerier` checks existence only, and no readiness check precedes a pour | a dry run on a blocked armed bead prints "A wisp will be attached automatically" |
| Exit 3 means a live workflow already works the bead | `cmd/gc/cmd_sling.go`: the `DoSling` error branch returns 3 for `*sourceworkflow.ConflictError` only; `internal/sourceworkflow/sourceworkflow.go` documents the mapping; `checkLegacySourceWorkflowConflict` in `internal/sling/sling_core.go` raises it for a live root of the same formula that the bead's input convoy tracks, or of any formula whose `gc.source_bead_id` names the bead | same |
| A dry run reports a live same-formula root, and nothing reports a finished one | `dryRunReportBlockingMolecule` with `sling.LiveConvoyTrackedWorkflowRoots`, "the same check checkLegacySourceWorkflowConflict runs at launch time" | same |
| `--title` names the root of a formula pour | `cmd/gc/cmd_sling.go`: "wisp root bead title (with --formula or --on)" | same |
| bd ignores a cross-prefix blocker, and Gas City re-judges one only on a split city | `internal/readywork/crossstore.go` header | `gc config show` names no class binding |
| The idle-claim backstop serves pool slots only | `nudgeStalledPoolClaims`, `cmd/gc/idle_nudge.go` | same |
| A default nudge wakes a stopped session, and a queued one does not | `deliverSessionNudgeLegacy`, `shouldQueueManagedNudgeWake` | same functions; `queueSessionNudgeWithWorker`; the help text of `gc session nudge`; cascade-nudge queues its assignee nudge (51055e7d3f) |
| `--reference-bead` exists on the fork only | absent from `cmd/gc/cmd_session.go` | present |
| Gas City's readiness treats a blocker closed as blocked as still holding | `beads.DependencySatisfied` with `beads.ReadinessWorkOutcome`, `internal/beads/beads.go` | same |

The last fact is not one the design relies on. `gctk bead holds` reads bd's
blocked set, which may release such a dependent where Gas City's own readiness
holds it, so that difference is filed as its own bead for `waits` (tk-ih6w722).
