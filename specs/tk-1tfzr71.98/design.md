---
name: Design — deferred dispatch keeps only the arm, as gctk's bead verbs and one order
description: The design for tk-1tfzr71.98, the design child of initiative tk-1tfzr71.16, taken at main dbe034457 and checked against Gas City upstream main 3bcab243e and dba20336ed, the city's gc build 6589a7df45 and bd 1.3.4. It states what is left of deferred dispatch and the upstream fix that retires it, where it lives and which package owns the arm's keys, the trigger its start runs on, how the start sends each arm exactly once, what holds an armed bead, how a named agent hears about ready work, how a stop removes an arm first, what each writer and reader becomes, how the tests reach the real store, the upstream asks it proposes, and the three units the implementation child files. Read it to approve the design at its gate, or to build one of its units.
---

# Design: deferred dispatch keeps only the arm

This is the design record for tk-1tfzr71.98, the design child of the
initiative tk-1tfzr71.16. The pack was read at main dbe034457, the commit
`integration/tk-1tfzr71.16` was cut from. Each Gas City fact is cited by symbol
at upstream main 3bcab243e (2026-11-12), or at dba20336ed (2026-11-13) for the
facts on upstream's open fix, the claim path's retire, the controller's wake,
the hook's routed tier and the pool's serve rule, and checked in the city's gc
build, the fork commit 6589a7df45, wherever the two differ. No file cited here
changed between 3bcab243e and dba20336ed. bd is 1.3.4. The store counts were
read on 2026-11-13 between 01:58Z and 02:10Z, and section 7's reads of the arms
between 06:10Z and 06:24Z.

## What the operator approves

Deferred dispatch is how the pack starts work later. An arm on a bead says
"pour this formula on it through this pool once nothing holds it". Today a
script of 1,325 lines, with a test of 2,190, runs a pass every five minutes in
each rig. The pass carries its own lock, time budget and crash marker, and a
second job: telling a named agent, such as the mechanik or a refinery, that
work assigned to it is ready. Approving this design keeps the arm, which is the
one job Gas City cannot do, and rebuilds it as three gctk verbs and one order.
Upstream tracks that gap as open P1 bugs, gastownhall/gascity#7163 and #8832,
with a draft fix in PR #8834, and the arm retires once that fix lands
(section 12). The design deletes the script and drops what Gas City now does or
reports itself. gctk's `bead` domain takes over the arm's writer and the
declarations of its keys. The scripts, doctor checks, skills and board that
read an arm keep their reads until the arm retires (section 2). The 203 arms
open across six rig stores carry over with no write. What reaches you does not
change: a start that keeps failing still asks you through a human gate.

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
2. **A named agent hears about ready work through Gas City's own hand-off.** A
   writer hands work over with `gc sling <agent> <bead> --no-formula`, which
   routes the bead and nudges the agent. A writer whose agent finds its work by
   listing the beads assigned to it, as the refinery's patrol does, keeps the
   assignment instead (section 6). Gas City nudges again when a blocker closes,
   and its controller wakes a stopped agent that has ready work assigned or
   routed to it. The cost: a running, idle agent is not told about work that
   becomes ready another way, such as a lifted park, a removed hold label or a
   wait that is not a `blocks` edge. It hears at its next turn, or once
   upstream adds a named-session backstop (section 12). A person's raw
   `bd update --assignee` reaches a running agent only at its next turn, so a
   person hands work over with `gc sling`. The other way, a pass in the start
   that nudges each named session about its ready assigned work, runs a second
   nudge flow beside Gas City's.
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

Upstream tracks the gap as open P1 bugs: gastownhall/gascity#7163, and #8832
with its draft fix, PR #8834. None has landed at the commits this design
reads, upstream's or the city's build (section 12).

Main has moved past the initiative's description. The until disposal is gone,
by the operator's ruling in conversation tk-u5edbg1, and #1390 deleted
`until-resolved.sh`, `live-work.sh` and `doctor/check-until-resolved-owed`.
`hold-lib.sh` is gone too, and the pass asks `gctk bead holds` what holds each
armed bead (#1454). The warrant in `docs/warrants.md`, "Deferred dispatch
residual", stands as recorded. Unit 1 re-verifies its evidence at the upstream
commit it builds against, and restates its Retires-when line in upstream's
terms (section 12).

Retiring here: the notice and its record (`deferred-dispatch.sh notify`,
`gc.notify_when_ready`), the per-rig pass lock, the two-state crash marker
(`gc.dispatch_when_ready_slung`), the pass's partial-outcome declarations, and
the script itself.

## 2. Where it lives

The arm moves into gctk's `bead` domain in this member, as
`docs/gctk-architecture.md` plans it, and the port deletes the shell it
replaces in the same change (item P5 of `docs/built-once-target.md`).

The domain is two packages, so that it forms no import cycle with `waits`.

- **The record**, `services/gctk/arm/record`, declares the arm's keys as its
  own, decodes a bead's arm into typed values, and makes every write to them,
  each as one ledger write. It asks no other domain. Its answer for a bead is
  the target, the formula the arm names (its `--on`, empty when it names none,
  so the start pours the target's default), the reason, who armed it and when,
  the attempts, and whether they have reached the cap, which is
  `GC_MAX_DISPATCH_SLING_FAILURES` (3 by default). At the cap the start asks a
  person instead of slinging.
- **The verbs' rules**, `services/gctk/arm`, are what `gctk bead arm` refuses,
  the dispatch lock that `arm`, `disarm` and the start hold (section 4), and
  the start itself. They ask `waits` what holds a bead and the record for its
  arm, and no domain asks them.

`waits` asks the record for the arm that `gctk bead holds` prints, so
`waits.Holds.Arm` is the record's answer. That arm keeps the fields it prints
today, less the crash marker and the notice, which retire. `queue` reads the
arm from `waits.Holds` to tell whether a bead starts by itself, so it needs no
change.

| Verb | Caller class | What it does |
|---|---|---|
| `gctk bead arm <bead> --target <rig>/<pool> [--on <formula>] --reason <text> [--db <path>]` | agent, hook | Records the arm. With no `--on` it records the target's default formula, read from `gc config show --json` (`DefaultSlingFormula`). It refuses a closed bead, a bead not `open`, a bead already dispatched (`in_progress`, or a `gc.routed_to` route), a target with no formula to pour, and a bead with a wait edge into another store. An arm already present with the same target and formula is a success that writes nothing, and a different one is refused. |
| `gctk bead disarm <bead> --reason <text> [--db <path>]` | agent, hook | Removes the arm in one write, under the bead's dispatch lock (section 4). It exits 0 once no arm remains, the case where none was there included. Once it exits 0, no start has the bead in flight and none will send it. |
| `gctk bead start-armed [--db <path>] [--dry-run]` | order | Retires the arm on each closed or delivered bead, and starts each armed bead section 7's rule sends (section 4). It prints one JSON object per arm it reads: `gctk bead holds`' answer for the bead, with what the pass did with the arm, or with `--dry-run` would do. That is a retire and its case, a start, an exit 3 read as already sent, a hold and what holds the bead, a cap reached, an unfinished pour it asks a person about, a failed sling or a malformed record. |

Nothing remains of `deferred-dispatch.sh`. `orders/deferred-dispatch.toml`
keeps its name, cadence, rig scope and single-flight gate, so
`doctor/check-cadence-live` and the order's history carry on, and its `exec`
runs `gctk bead start-armed`. `assets/scripts/dispatch-path.sh` keeps both
halves of a dispatch path, the route and the arm, and the hold labels, and its
readers keep asking it.

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

Listing the arms needs no verb of its own. The start's dry run prints every arm
in a store and what the start would do with each, which is what
`deferred-dispatch.sh list` prints today, and `gctk bead holds` prints the arm
of each bead it is given.

The arm keeps its keys' stored spellings, so no stored arm is rewritten:
`gc.dispatch_when_ready` (the target), `_args`, `_armed_by`, `_armed_at`,
`_reason` and `_fail_count`. What changes is where they are declared and who
writes them. The record declares the six as its own, so no other gctk package
reads or writes them through the ledger, and `waits` drops the read-only
declarations it makes of them today and asks the record. They leave
`lifecycle/lifecycle.toml`'s `[metadata.deferred_dispatch]` group, and the
generated `services/gctk/key-registry.json` names the record as their owner.
This is the takeover `docs/gctk-architecture.md`'s ledger sets for the change
that moves a key's writer. The design makes one named exception to that page's
"The rules a domain move follows":

- Readers outside gctk's `bead` domain keep reading the arm's keys as they do
  today until the arm retires.
- This departs from rules 1 and 6, for a residual under a dated warrant:
  upstream's fix is expected to retire the arm, and a reader migration built
  now would be rebuilt then.
- The operator ruled this on 2026-11-13 in conversation tk-au9jrqt. Unit 1
  records it as one Debt entry in `docs/gctk-architecture.md`.

The pack's checks allow the exception. The key registry is generated from the
Go declarations alone (`TestKeyRegistryIsCurrent`,
`services/gctk/cmd/gctk/registry_test.go`), and each drift check against
`lifecycle/lifecycle.toml` tests only the keys its own scripts write, none of
which writes an arm key.

`resling_target`, which shares the group, is `await-ruling.sh`'s own key and
stays. The crash marker `gc.dispatch_when_ready_slung` and the notice key
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
  sling the timeout kills is recovered by section 4's search, which asks a
  person when that sling left its pour unfinished. The partial and
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
refinery's patrol writes it when it takes a bead's work. At merge-push it
writes `pre_open_gate` or `pull_request`, or `merged` in the write that closes
the bead when the strategy is direct. It writes `blocked` or
`refused_false_completion` when one of its checks stops the work. `pr-open.sh`,
`pr-facts.sh` and `merge.sh` move an anchor on from there. A polecat's hand-off
writes none. Work sent back for rework carries none either. A rework of a
branch under review is a child bead of its own, whether a sign-off, a ruling or
the merge cadence files it, and merge-push closes the child with none once its
work lands on the branch. `rejection-repool.sh` moves a rejected bead to
unanchored, which removes the key, before it pours the rework or arms its
re-sling. So the retire leaves alone the arm that re-sends work in flight, and
the start sends that arm when section 7's rule does. tk-iqpxk89 is one, read on
2026-11-13 at 03:32Z: a sign-off's rework armed for `mol-polecat-work` that
carries its branch and rejection reason and no `merge_result`.

Each start of an armed bead runs these steps, holding the bead's dispatch lock
from the first to the last. The lock is a `flock` file per store and bead under
the city's `.gc/runtime/packs/gc-toolkit/`, the directory Accept's lock already
uses.

1. Read the bead once more. An arm removed since the pass's listing is not
   sent, and a hold label set since then keeps the bead armed. A bead that has
   closed or gained a `merge_result` since then has its arm retired as above.
2. Resolve the formula: the arm's `--on`, or else the target's default formula.
3. When the arm records an earlier attempt (`_fail_count` above 0), search for
   the workflow roots that carry the arm's token, `arm:<bead>@<armed at>`. A
   root found there that is not an unfinished pour (below) means the earlier
   attempt landed, whichever formula it carries: disarm, and stop here. While
   an unfinished pour found there is still open, the start keeps the arm,
   slings nothing, and asks a person as step 6 does, naming the root.
4. Raise `_fail_count` by one in one write.
5. Run `gc sling <target> <bead> --on <formula> --title "<formula>
   arm:<bead>@<armed at>"`.
6. Exit 0: disarm. Exit 3: `gc sling` exits 3 only when its launch check
   counts a live workflow on the bead (`sourceworkflow.ConflictError`, mapped
   to 3 in `cmd/gc/cmd_sling.go`), and it names each one. When one of them is
   not an unfinished pour, the work is already sent: disarm. When each is an
   unfinished pour, nothing works the bead, so the start keeps the arm and
   asks a person, naming those roots. Any other exit keeps the arm for the
   next pass. At three attempts the start asks a person instead of slinging,
   as the pass does today, through `human-gate.sh` under the key
   `deferred-dispatch-sling-failed.<bead>`, or through `gc-helm.sh open` when
   the bead has an open child.

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
window. It is a title on Gas City's own root, `<formula> arm:<bead>@<armed
at>`, found by `gc bd list --all --include-ephemeral --include-gates
--title-contains "arm:<bead>@<armed at>"`. The argument is the part of the
token that names no formula, the way Accept searches for `accept:<token>`
alone (`accept_token_root`, `assets/scripts/gc-helm.sh`; the "Accept's lock"
warrant). An arm that names no formula resolves its target's default at each
start, and that default can change between an attempt and its retry. A search
that named the formula would then miss the root the earlier attempt poured,
and Gas City's launch check, which is scoped to the formula, would not refuse
the second pour either. The search includes gates because a pour Gas City left
unfinished keeps its root typed as a gate (below), and bd's `list` shows a gate
only with `--include-gates`, which `--all` does not imply. The token is
searched only after an earlier attempt, so a start that succeeds the first
time costs no search.

The launch check has a second half: it also refuses while a live root of any
formula names the bead in `gc.source_bead_id`
(`checkLegacySourceWorkflowConflict`, `internal/sling/sling_core.go`), a key
its comment says a convoy-first `--on` launch never stamps. So an exit 3 can
also mean that a run of another formula, launched some other way, already works
the bead. The start reads that as sent too, since the bead is already being
worked, and it prints the line `gc sling` printed, which names the live
workflow.

A root that carries `molecule_failed=true`, or still carries the fence
`gc.instantiating`, whatever its status, is an unfinished pour. It never shows
that the arm's work was sent, whether step 3's search finds it or an exit 3
names it. Gas City pours a graph in one batch where its store supports one
(`instantiateViaGraphApply`, `internal/molecule/graph_apply.go`). Otherwise, or
once the batch has failed twice with a transient error, `Instantiate`
(`internal/molecule/molecule.go`) makes the beads one at a time, root first.
The fence it puts on each bead as it makes it also types the bead as a gate and
withholds its route (`fenceGraphWorkflowBead`), and only once every bead is
made does it lift the fences and restore each type and route. When that pour
fails part way, `markFailed` stamps `molecule_failed=true` on each bead made so
far and clears its fence without restoring its type or route, and closes
nothing. `gc sling` closes the failed root in a cleanup of its own
(`closeFailedGraphV2Roots`, `internal/sling/sling.go`), which returns its error
and leaves the root open when its lookup or its close fails, or when the sling
stops before the cleanup runs. A sling killed while it makes the beads leaves
its root open, still fenced and typed as a gate. Upstream tracks both states
as open P1 bugs: gastownhall/gascity#6177, a failed chain that only a retry
under the same key closes, and #6179, a fenced chain a killed client leaves.
Accept's search already skips a `molecule_failed` root whatever its status
(`accept_token_root`).

While the root of an unfinished `--on` pour is open, Gas City refuses every
sling of that formula on the bead with exit 3, naming that root. The launch
check (`liveConvoyTrackedWorkflowRoots`, `internal/sling/sling_attachment.go`)
walks every synthetic input convoy that tracks the bead, closed ones included,
and keeps each root that is not terminal, is a workflow and carries the same
`gc.formula_name`. It reads neither mark. An unfinished pour's convoy still
tracks the bead: a failed sling closes it with `CloseSyntheticInputConvoy`
(`internal/graphv2/invocation.go`), which leaves the `tracks` edge in place,
and a killed one leaves it open. The check runs before the pour
(`attachFormulaToBead`, `internal/sling/sling_core.go`), so a retry is refused
before anything it does could close the old root. A retry of that formula
cannot pour while the root is open, so the start keeps the arm, slings
nothing, and asks a person through step 6's gate, naming the root and the
command that closes it with its steps, `gc convoy delete <root> --force`
(`cmdWorkflowDelete`, `cmd/gc/cmd_convoy_dispatch.go`). It ends no Gas City run
itself. It reads the roots an exit 3 names from the line `gc sling` prints
(`printSourceWorkflowConflictLines`, `cmd/gc/cmd_sling.go`). Once the root is
closed and the gate is cleared, the next start slings, because a closed
unfinished pour holds nothing back: step 3 passes over it, and the launch check
skips a terminal root.

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
crash marker. The 15 notice records become inert, with `gc.notify_when_ready`
registered as retired. Each one's bead is assigned to the agent it names, and
that agent hears through section 6's paths: Gas City's blocker-close nudge, or
the controller's wake if the agent is stopped. At worst a running agent hears
at its next turn, so no notice strands. Two arms need a word. The edge from
tk-nt5uda onto gc-vz6v0 holds nothing today, because its target has closed, but
section 7's rule would hold the arm on it, so the implementation child removes
that edge (section 14).
The arm aimed at rig-c's proactive agent stays, and behaves as it does today.

No wait strands silently. The start names on every pass each arm it holds and
why, each arm at a status other than `open` or `closed`, and each assigned arm,
and `doctor/check-armed-dispatch-owed` still reports an arm nothing holds that
has stayed armed past the cadence window.

## 6. A named agent hears about ready work

A named agent hears about ready work through Gas City's own paths, and the
pack adds no pass, record or ledger for it.

- **A hand-off routes the bead and nudges the agent.** A writer hands a bead to
  a named agent with `gc sling <agent> <bead> --no-formula`, which writes
  `gc.routed_to=<agent>`. A named session's hook serves work routed to its
  alias: the work query's origin gate lets a named session into the routed
  tier only when the probe target is exactly its `GC_ALIAS`
  (`namedSelfTargetAdmit`, `internal/config/workquery.go`), and that tier
  serves only a bead the store reports ready. A named session's alias is its
  qualified name, which is what the hand-off routes to: a dry run of
  `gc sling gc-toolkit.mechanik <bead> --no-formula` on the installed build
  writes `gc.routed_to=gc-toolkit.mechanik`, and `gc session list` gives the
  mechanik that alias. Core's `nudge-on-route` order then nudges the routed
  target once per pair of bead and target, with the default delivery.
- **A blocker closes.** `cascade-nudge-on-blocker-close` nudges each dependent
  no other blocker holds, at its assignee, or else at its `gc.routed_to`
  target, with a message that names the dependent. The city's copy, which
  matches the fork commit 6589a7df45 byte for byte, queues the assignee nudge
  (`--delivery=queue --reference-bead <dependent>`, fork change gc-f3k8d,
  51055e7d3f) and sends the routed one with the default delivery. A queued
  nudge reaches a running session at its next idle boundary and never wakes
  one that is not running: `gc session nudge`'s help says "queue delivers it as
  a notice at the next boundary and never wakes the session", and
  `queueSessionNudgeWithWorker` enqueues it and requests no wake. Upstream's
  own copy at 3bcab243e sends both nudges with the default delivery.
- **The default nudge gives an idle named session a turn.** With the default
  delivery, `wait-idle`, `deliverSessionNudgeLegacy` delivers to a running idle
  session at once. For a session that is not running, `shouldQueueManagedNudgeWake`
  answers true, and `queueManagedSessionNudgeWake` queues the nudge and records
  a wake (`RequestWakeUnlessHeld`), so the controller starts the session and the
  nudge reaches its first boundary. This is read from the build's source at
  6589a7df45, not from a live run, and unit 2 records a live check.
- **The controller wakes a stopped session that has ready work.** Its awake
  set wakes a session that has ready open work, or unblocked work in progress,
  assigned to it: the assigned-work pass of `computeAwakeSetKeyed`, through
  `workBeadHasAwakeDemand` (`cmd/gc/compute_awake_set.go`). It wakes an
  on-demand named session for work routed to it too. The default probe of the
  session's backing template counts routed work as that pool's demand, and
  `computeNamedSessionDemandOn` marks the demand on a backing pool of one
  session, which wakes the sleeping session (`cmd/gc/build_desired_state.go`).
- **Only a running, idle named session is uncovered.** The controller's wake
  covers a stopped one. Gas City's idle-claim backstop re-nudges a pool slot
  whose assigned work it never began, and its comment says "Pool slots only."
  (`nudgeStalledPoolClaims`, `cmd/gc/idle_nudge.go`).

The gap: a running, idle named agent is not told until its next turn about
work that becomes ready other than by the close of a `blocks` blocker, such as
a lifted park, a removed hold label or a wait that is not a `blocks` edge. Nor
is it told about a raw `bd update --assignee` that no hand-off wrote, because
nothing nudges on an assignee write. That gap is section 12's second ask, and a
person hands work over with `gc sling`.

Each writer that records a notice today takes one of two forms, by one test:
how does its receiving agent find that work?

- **The agent claims through its hook.** A routed bead reaches it the same way,
  so the writer hands over with `gc sling <agent> <bead> --no-formula`. A bead
  that still waits is routed all the same: the hook serves it once bd reports
  it ready, and cascade-nudge nudges the routed target when its blocker closes.
- **The agent finds its work some other way**, such as a patrol that lists the
  beads assigned to it. A route never reaches that list, so the writer keeps
  its assignment, and nudges at the write once bd reports the bead ready:

  ```bash
  gc bd update <bead> --assignee <session> && gc session nudge <session> "<bead> is assigned to you and ready"
  ```

  A bead that still waits on a blocker takes the assignee alone, and
  cascade-nudge tells the agent when the blocker closes.

Section 10 names each site's form.

## 7. What holds an armed bead

The start selects armed beads by the pool's own serve rule, so the arm sends
exactly what the pool would serve, and the switch to upstream's fix changes no
behavior.

- **The rule** is `bd ready` over the beads that carry
  `gc.dispatch_when_ready`, with the flags of the routed pool-demand tier,
  which `PoolDemandServeRulesForQuery` (`internal/config/workquery.go`)
  renders for every generated demand query: `--unassigned`,
  `--exclude-type=epic`, and an `--exclude-label` for each of
  `beadmeta.DispatchHoldLabels` and `beadmeta.HumanLabel`. At 6589a7df45 and
  at dba20336ed those labels are `hold:mayor`, `hold:external` and `human`.
  bd 1.3.4's `bd ready` takes `--has-metadata-key gc.dispatch_when_ready` with
  those flags. On 2026-11-13 between 06:23Z and 06:24Z, the rule selected the
  same arms in every rig store as today's pass does, which sends an open,
  unassigned arm with no hold label that `gctk bead holds` answers `clear`
  with no wait edge into another store: tk-1tfzr71.95, tk-gk44rud and
  tk-n4i5lh1 in gc-toolkit's, whose last wait had landed at 06:19Z, and none
  in any other.
- **What bd cannot judge.** From that set, the start holds back what bd cannot
  judge, by asking `gctk bead holds`. It holds a `waits-for` edge of the bead's
  own, which `gctk bead holds` answers `unjudged`, because the bd the city runs
  judges it by its spawner's status rather than its gate. It holds a wait edge
  into another store, from the answer's `foreign` list, because bd never blocks
  a dependent on a cross-prefix target, as upstream's
  `internal/readywork/crossstore.go` records ("beads v1.3.2,
  issueops.IsExternalDepTarget"). Gas City re-judges such an edge only on a
  city with a class binding, and the city's `gc config show` names none.
  `gctk bead holds` also gives the reason the start prints for each arm it
  holds.
- **The hook's hold test.** bd's `--exclude-label` compares a label exactly,
  and the pool's hook then drops a candidate that carries `hold:mayor` or
  `hold:external` trimmed and in any case (`isHeldHookCandidate`,
  `cmd/gc/cmd_hook.go`, through `beadmeta.HasDispatchHold`, whose comment
  calls the hook's filter "the last word on what a session is served"). So the
  start holds such a bead back too, with the comparison `HasDispatchHold` makes,
  which gctk's `queue` already copies (`hasDispatchHold`,
  `services/gctk/queue/queue.go`). The `has_dispatch_hold` test of
  `dispatch-path.sh` leaves this rule.

The rule reads only arms still owed, because section 4 retires the arm on a
closed or delivered bead first. The delivery stamp has to be read there and not
here. bd's readiness reads no `merge_result`, so a delivered anchor, which
rests open and unassigned, reads ready once its own waits land, and
`gctk bead holds` reads the stamp as evidence that the work is in flight, not
as a hold (`rowFlight`, `services/gctk/waits/waits.go`).

bd's readiness cascades a wait on any ancestor down parent-child edges, to
every member, started or not. So a park holds an armed re-send of work in
flight under the parked epic until the park lifts, and so does any other wait
on an ancestor. That is the one place the start departs from
`docs/steering.md`, whose rule is that a park leaves work in flight running,
because once a bead is in flight only its own waits hold it. No arm has that
shape now. Between 06:10Z and 06:11Z on 2026-11-13, 4 arms across the six rig
stores were on work in flight, each held by a wait of its own, and none of
them had an ancestor that waits.

## 8. The held problems

- **tk-t91hbtx, a notice whoever wrote the assignee.** Section 6 answers it:
  work reaches a named agent through Gas City's hand-off, which nudges, and the
  controller wakes a stopped agent. A person's raw `bd update --assignee`
  reaches a running agent only at its next turn, which is section 12's second
  ask. Unit 2.
- **tk-ajlktr0, an arm fired past a cross-store blocker.** On bd 1.3.4 such an
  edge holds nothing in bd's readiness (section 7). The start holds back a bead
  whose `gctk bead holds` answer lists a wait edge into another store, and
  names it on every pass, `arm` refuses one, and the pack already refuses to
  write such a wait (#1414). Unit 1.
- **tk-v6bnjjp, a `conditional-blocks` or `waits-for` blocker ignored.** That
  finding read `hold-lib.sh`, which is gone. A `conditional-blocks` edge holds
  through bd's readiness, and a `waits-for` edge or a wait into another store
  holds through `gctk bead holds` (section 7). Unit 1 adds a store acceptance
  case for each, an unstarted armed bead whose only open blocker is that edge,
  run against the real bd.
- **tk-cedhuvm, exit 3 read as malformed arguments.** Exit 3 means a live
  workflow already works the bead, so it retires the arm, unless each workflow
  it names is a pour Gas City never finished, which keeps the arm and asks a
  person. No pack failure shares that exit (section 4). Unit 1.

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

**Notices** (unit 2) take section 6's forms, by how each receiving agent finds
the work. The line numbers are at dbe034457.

- **The refinery's sites keep the assignment.** The refinery's patrol finds its
  work by listing the open beads assigned to it that carry a `branch`
  (`find-work`, `formulas/mol-refinery-patrol.toml`), so a route never reaches
  it. Each of these beads waits on a blocker when it is assigned, so its writer
  writes the assignee alone, and cascade-nudge tells the refinery when the
  blocker closes:
  - `mol-design-convoy`'s dispatch step (line 548), which hands the refinery
    the landing bead while it waits on its children and its summary task;
  - `skills/work/integration-effort.md`'s landing (line 80), which waits the
    same way, and its bring-current hand-off (line 165), which waits on the
    outside work;
  - the refinery prompt's bring-current conflict hand-off (line 164), which
    waits on its human gate.

  The patrol never takes a hand-off, which carries no `branch`, and the
  refinery takes one today when it reads the notice. Unit 2 rewrites that part
  of the refinery prompt, so the refinery takes a hand-off from the nudge,
  which names it.
- **First reaction's assign exits hand work to the agent's hook.**
  `first-reaction-dispose.sh --assign` and `--then-assign` (line 938) address
  only an agent whose own hook offers the bead, which they test first with
  `tools/gc-proactive.sh assignable`, so each hands over with
  `gc sling <agent> <bead> --no-formula`. The bead `--then-assign` hands over
  still waits, and its route serves once bd reports it ready.
- **The sites that address any named agent take the form of the agent they
  name.** These are the `work` skill's named-agent send (line 228) and its
  `takeaway --assign` (line 321), and the `watch-dispatched-work` fragment
  (line 18). The mechanik claims through its hook, since its wake nudge says to
  check "assigned work (gc hook)" (`agents/mechanik/agent.toml`), so it takes
  `gc sling`. The refinery keeps the assignment, as above. The deacon, the
  witness and the keeper find their own work other ways, so unit 2 settles
  each one's path in its live check before the skill names its form. The
  notices open in the stores name only the mechanik and the refinery
  (section 5).

**Readers of the keys** keep their reads under section 2's exception. A reader
changes only where it reads a key that retires, the crash marker
`gc.dispatch_when_ready_slung` or the notice key `gc.notify_when_ready`, or
where it calls the deleted script. There it takes the smallest change that
swaps that read or call:

- `skills/work/integration-effort.md` tests `.arm.slung` from
  `gctk bead holds` before it adds a wait to a summary task (line 115). It
  tests the arm alone, since the start disarms an arm once it has sent it
  (unit 1).
- `check-armed-dispatch-owed` reads the marker, the fail count and the cap
  itself. It reads each arm from the start's dry run instead, as the doctor
  checks below say (unit 1).
- `stand-down.sh` reads the arm and the notice to decide whether to disarm
  (line 192). It disarms with no read first, since the verb exits 0 once no arm
  remains (unit 2).
- The sitting skills' withdraw blocks read the arm's target before they call
  the script's disarm (line 41 of `converse-continue`, line 149 of
  `converse-settle`). They call `gctk bead disarm` with no read first, for the
  same reason (unit 3).
- Each doctor check or script whose remedy text names the script names the
  verbs instead (unit 3). These are the disarm remedies of
  `check-armed-dispatch-owed` (lines 307 and 445, where the second also names
  the script's `list`, which becomes the start's dry run) and
  `check-po-queue-only` (line 462), the arm remedy of
  `check-blocked-work-armed` (line 304), and `gc-helm.sh place`'s disarm remedy
  (line 2365). A caller's own messages about its call change with the call.

**The doctor checks:**

- `check-armed-dispatch-owed` survives. It still reports an arm at a status
  other than `open` or `closed`, and an arm nothing holds past the cadence
  window. It still passes over the arm on a closed or delivered bead, which the
  start retires. It reads each arm from the start's dry run, so it stops
  listing the arms by their key and reading the marker, the fail count and the
  cap (unit 1).
- `check-blocked-work-armed` survives, and keeps its read of a dispatch path
  through `dispatch-path.sh`. Only its finding's remedy changes, to name
  `gctk bead arm` (unit 3). Open PR #1486 (tk-ltcv43q) edits this check, and
  whichever lands second takes the other's lines.
- `check-po-queue-only` survives, and keeps its read of the arm's target and
  arguments. Only its remedy text changes, to name the verbs (unit 3).
- `check-step-terminal` survives, and keeps its read of a dispatch path through
  `dispatch-path.sh`. None of its text names the script, so it does not change.
- `check-cadence-live` drops its `flock` requirement only if no pass lock
  remains anywhere. `refinery-reconcile.sh` takes one through `bd-lib.sh`, so
  unit 1 checks before it removes it.

**Files the deletion plan retires.** `finding.sh` (tk-1tfzr71.22) and
`rejection-repool.sh` (tk-1tfzr71.20) each change only the line that calls the
script. That is rule 7's exception in `docs/gctk-architecture.md`: the move
deletes the script, so each of its call sites swaps onto the verb, in retiring
code too, and nothing else there changes. Their reads of the arm's keys stay,
and so do those of `pr-facts.sh` (tk-1tfzr71.21) and `pre-open-rebase.sh`
(tk-1tfzr71.20), as every reader's do under section 2's exception, and rule 7
leaves a caller in retiring code to the member that retires it. The reads are
`finding.sh`'s read-back that a follow-up is armed for its fix pool (lines 865
to 873), `rejection-repool.sh`'s read of the arm on the bead it adopts
(line 279), `pr-facts.sh`'s armed anchor that defers a conflict rework and
armed rework child that it leaves to its arm (lines 1775, 1813, 2733, 2843 and
3850), and `pre-open-rebase.sh`'s armed rework child (line 267). `gctk
merge`'s `mergeInDeferred`, which defers a merge-in on an armed anchor
(`services/gctk/internal/cli/merge.go`, line 1014), is left the same way. It
has no row in `tools/deletion-plan.tsv`, but the re-implementation register and
the Debt entry in `docs/gctk-architecture.md` retire gctk's `merge` whole with
tk-1tfzr71.20 and give it no layering work.
The liveness scripts that tk-1tfzr71.19 retires source `dispatch-path.sh` for
the hold labels alone, which do not change, so rule 7's exception asks nothing
of them. Section 14 names these reads in each member's notes.

**The helm board.** The board's `selfStart`
(`services/helm/internal/board/state.go`, lines 46 and 142) reads the arm's key
from the board's own rows, beside the route and the assignee, to say a queued
bead starts by itself. Those rows are the board's second data plane, which the
board member (tk-1tfzr71.24) retires. The board keeps that read under
section 2's exception, so it does not change, and section 2's one Debt entry
covers it.

**Open PR #1488** (tk-1tfzr71.20) adds an arm in `refinery-requeue.sh` and a
notice in `effort-bring-current.sh`, and deletes `rejection-repool.sh` with its
arm. It also edits `stand-down.sh`'s refusals, lines this design does not
change, and `dispatch-path.sh`'s header, where it names a new reader. Its
`refinery-lib.sh` asks `has_dispatch_path` of a rework child the refinery's
requeue filed, and sends on a child with no dispatch path and no hold (line 53
at #1488's head 893215bd9). `dispatch-path.sh` keeps its arm half, so that
question keeps working whichever lands first. Whichever of #1488 and unit 2 or
3 lands second converts only the other's arm, disarm and notice call sites.

**Open PRs #1480, #1481 and #1484** change sites this section converts, and
whichever of each and unit 2 or 3 lands second converts the other's sites.
#1480 (tk-pb9wnr3) rewrites the converse skills: `converse-continue` no longer
shows, reads or disarms the subject's arm, and `converse-settle` keeps its
reads, its withdraw block and its arms at new lines. #1481 (tk-bvw8j5t) adds
the `converse-edit` skill, which reads its subject's arm and disarms it, arms
the subject for its validating closer (`mol-validate-close`), and disarms the
subject when the operator drops the change. #1484 (tk-qs1fqpu) rewrites the
refinery prompt's bring-current conflict hand-off: its block files a task for a
polecat before it records the notice, and its recovery steps name the notice
command again. #1488 moves the same block into `effort-bring-current.sh`.

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
when it deletes them. `docs/steering.md` says twice that an armed member in
flight keeps running under a park, in a rejected handoff's retry and in what a
park holds. Section 7's rule ends that, so both lines change in unit 1. In
unit 1, `services/gctk/README.md`'s layout gains the two packages
and `docs/gctk-architecture.md` gains section 2's Debt entry.

Callers find the script today through `GC_DEFERRED_DISPATCH_TOOL` or
`GC_DEFERRED_DISPATCH_SH`, which their tests set. Both retire with it, and the
tests set `GCTK_BIN`. `GC_MAX_DISPATCH_SLING_FAILURES` stays the cap's
setting, and the record reads it. `bead-context.sh` keeps reading the setting
and the fail count, and the owed check reads whether the cap is reached from
the start's dry run.

## 11. Tests against the real store

The shell suites stub bd, and the stub enforces none of bd's close or edge
semantics, which is how stand-down's worst defect reached a hand-run proof
before any suite (`specs/tk-utv2kaq/real-store-proof.sh`). gctk already runs
the bd the city runs against a scratch store on a Dolt server of its own
(`services/gctk/internal/gcbd/acceptance_test.go`,
`GCTK_STORE_ACCEPTANCE=1`). The arm's tests use that harness:

- **What holds an armed bead**, one case per shape of section 7's rule,
  against the real bd: an open and a closed `blocks` blocker; an armed bead
  whose only open blocker is a `conditional-blocks` edge, which is held; a
  `waits-for` edge, which holds the bead, and a wait edge into another store,
  which holds it too; an armed bead labeled `human`, which is not sent, and an
  armed epic, which is not sent either; a hold label, in Gas City's spelling
  and in another case; an assignee; a status other than `open`; and a park on
  an ancestor, which holds unstarted and in-flight work alike.
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
- **The recovery after an earlier attempt**, with each root made in the real
  store under the arm's token: a root poured for one formula while the arm now
  resolves another, which disarms and slings nothing; an open root carrying
  `molecule_failed=true`, and an open root still fenced by `gc.instantiating`,
  each typed as a gate as Gas City leaves it, and each of which keeps the arm,
  slings nothing and asks a person, naming the root; and a closed
  `molecule_failed` root, which does not disarm, so the retry slings.
- **The record's decoding**, in gctk's ordinary suite on the fake store: the
  formula the start pours from each stored form of `_args`
  (`["--on","<formula>"]`, `["--on=<formula>"]`, `[]`, absent and malformed),
  and the attempts below, at and past the cap.

A test cannot run Gas City's launch, so `gc sling` is a shim that records each
call and exits 0, 1 or 3 as the case says. On exit 3 it prints the line
`gc sling` prints, naming roots made in the store. The exit-3 cases pin
tk-cedhuvm's answer: an exit 3 that names a root Gas City finished disarms,
and one whose only named root is an unfinished pour keeps the arm and asks a
person. Unit 3 runs stand-down's real-store proof again against its scripts.
The store harness is opt-in, as it is today, so each unit runs it and records
the run in its PR. The retirement cases also run in gctk's
ordinary suite on its fake store (`services/gctk/internal/gcbd/fake`), so they
run on every test run. They carry the regression `deferred-dispatch.test.sh`
holds for the delivered retire, which unit 1 deletes with `reconcile`.

## 12. The upstream asks

Upstream already tracks the missing primitive as open P1 bugs:

- gastownhall/gascity#7163, "a formula slung onto a blocked bead runs before
  its blockers close", which proposes a start gate;
- #8832, "native execution admission loses current input readiness", with
  draft fix PR #8834, which pours at once and holds the workflow's steps at
  ready, demand and claim until the input bead is ready.

On 2026-11-13 both issues and the PR were open, and the PR a draft. Neither
upstream main dba20336ed nor the city's build carries the fix. The design
proposes no new ask for it.

Once that fix lands, the arm becomes a plain `gc sling <pool> <bead> --on
<formula>` at arm time, and the order, the dispatch lock, the title token, the
cap and the owed check retire. Two behaviors must find a home then:

- **Skipping a bead whose work another path delivered.** Gas City's claim path
  retires a workflow only once its input work is closed, handed to another
  assignee, or gone from every store (`retireDoneWorkflowCandidates`,
  `cmd/gc/cmd_hook_claim.go`). A delivered anchor is none of these, since it
  rests open and unassigned (section 4).
- **A stop that cancels a waiting workflow.** A workflow poured at arm time
  waits as a live root, and exit 3 refuses a re-sling of the same formula while
  that root is live (`checkLegacySourceWorkflowConflict`,
  `internal/sling/sling_core.go`). So a stop cancels the waiting workflow where
  today it removes an arm.

Two asks stay proposed. Posting them is the operator's decision, and neither
is sent.

1. **A launch key.** The fix leaves one part of a launch that waits uncovered:
   a caller's key that makes a launch exactly once, whatever an earlier root's
   status. It would retire Accept's lock.
2. **A claim backstop for named sessions.** The idle-claim backstop serves pool
   slots only. Extended to a named session holding ready, unclaimed assigned
   work, it would close section 6's gap. Upstream built a named-seat claim
   backstop (#6302) and removed it, together with its named-seat execution
   backstop (#6287), in #6551, merged on 2026-09-25 and fixing #6524, where the
   claim backstop restarted named always-on seats on every nudge. The revert's
   release notes say named seats have no controller claim or execution
   backstop, and list a follow-up, ga-o1w8h. The city's gascity rig tracks that
   gap as gc-pn2gms.

## 13. The units

Each unit lands on `integration/tk-1tfzr71.16` and leaves the pack's tests
passing. Nothing reaches the city until the effort's PR merges to main, so the
new start replaces the old pass at that landing, with every arm carried over
(section 5). Each unit waits on the one before it.

1. **The start in gctk, and the arm's keys with it.** Build `gctk bead arm`,
   `gctk bead disarm` and `gctk bead start-armed` in `services/gctk/arm`, over
   the record in `services/gctk/arm/record` (section 2), with sections 4 and 7:
   the retirement of the arm on a closed or delivered bead, the selection of
   armed beads by section 7's rule, the dispatch lock, the formula resolution,
   the token, exit 3 as sent, the ask about an unfinished pour, the cap's ask
   and the time bound. Take the six live keys over in the record, have `waits`
   ask the record for the arm and drop its declarations of the arm's keys and
   the marker, add both packages to `layers_test.go`'s domains, regenerate
   `key-registry.json`, and remove the six from `lifecycle/lifecycle.toml`,
   where the marker stays registered as retired. Point
   `orders/deferred-dispatch.toml`'s `exec` at the verb. Delete
   `reconcile` from `deferred-dispatch.sh` with its pass lock, budget, marker
   and outcome code, and have its `arm` and `disarm` call the gctk verbs until
   unit 3 deletes the file. Move the owed check onto the start's dry run and
   `integration-effort.md`'s `.arm.slung` test onto the arm alone, and add
   section 11's cases, with the retirements in gctk's ordinary suite as well as
   the store harness. Update `docs/deferred-dispatch.md`'s account of what
   performs the arm, `docs/gctk-architecture.md`'s rows,
   `services/gctk/README.md`'s layout, `gctk bead holds`' help on the arm it
   prints, `docs/refinery-merge-cadence.md`'s lock line, `docs/steering.md`'s
   two lines on an armed member in flight, and the warrant. The warrant's Covers
   gains the dispatch lock and the token, its evidence is re-verified at the
   upstream commit the unit builds against, and its Retires-when line is
   restated in upstream's terms: Gas City holds a poured workflow's steps until
   its input bead is ready, citing #8832, #8834 and #7163. Record section 2's
   exception as one Debt entry in `docs/gctk-architecture.md`. It answers
   tk-ajlktr0, tk-v6bnjjp and tk-cedhuvm.
2. **Named agents hear through Gas City's hand-off.** Retire `notify` and
   `gc.notify_when_ready`, registered as retired, with `noticeKey` dropped from
   `waits`. Make `stand-down.sh` disarm with no read first. Move each notice
   writer to its section 6 form (section 10). Rewrite the notice section of
   `docs/deferred-dispatch.md`, and point `docs/pack-authoring.md`'s link at
   it. Record a live check on the city's build that each receiving agent finds
   the work in its section 6 form and hears the nudge. It adds no pass and no
   ledger. It answers tk-t91hbtx.
3. **Callers onto the verbs, and the script goes.** Move every arm and disarm
   caller in section 10 onto the verbs, and add the disarm to
   `takeaway --release` and `accept` (section 9). Change each remedy text that
   names the script. Delete `deferred-dispatch.sh` and its test, and retire the
   two path variables. Move the remaining docs, re-run stand-down's real-store
   proof, and update lane B's row in `docs/built-once-target.md`. No reader
   moves onto the record, `dispatch-path.sh` keeps its arm half, and its test's
   scan stays off. It answers tk-5trydl2.

What each unit releases: none releases a waiting bead by itself. tk-1tfzr71.17
and tk-1tfzr71.25 wait on tk-1tfzr71.16 with `blocks` edges, and so do the four
held problems, so all of them are released when the effort's PR merges to main
and closes tk-1tfzr71.16. tk-1tfzr71.17 then builds its intake exits on the
two verbs and section 6's hand-off, and tk-1tfzr71.25 retires the registry
entries this effort leaves marked as retired. The held problems' validating
closers check each answer above once that landing is on main.

## 14. Edges and notes the implementation child adds

- **tk-5trydl2** waits on tk-1tfzr71.16: a close brief naming section 9's
  disarm, a `blocks` edge (both carry the `tk` prefix), an armed validating
  closer, and the lift of its `hold:mayor`, by AGENTS.md's recipe.
- **tk-nt5uda** loses its `blocks` edge onto gc-vz6v0, a closed bead in the
  gascity store, with a note saying why, so section 7's rule cannot hold it once
  its own blocker tk-wmwcdlc.4 closes.
- **tk-1tfzr71.20** gets a note naming section 10's #1488 arm, disarm and
  notice call sites, and which unit converts them if #1488 lands first. The
  note also names the reads of the arm in the code it retires, which section 10
  leaves to it: `pre-open-rebase.sh`'s armed rework child,
  `rejection-repool.sh`'s arm on the bead it adopts, and `gctk merge`'s
  `mergeInDeferred`. Each asks whether a bead is armed, and for what, and its
  replacement may read the arm's keys for that, as section 2's exception
  allows.
- **tk-1tfzr71.21** gets a note naming `pr-facts.sh`'s reads of the arm, the
  armed anchor that defers a conflict rework and the armed rework child it
  leaves to its arm, and that its replacement may read the arm's keys for the
  same question, as section 2's exception allows.
- **tk-1tfzr71.22** gets a note that `finding.sh`'s arm call moves to
  `gctk bead arm`, so its replacement arms through the verb. The note also
  names `finding.sh`'s read-back, which asks whether the follow-up is armed for
  its fix pool. The verb's exit answers that.
- **tk-1tfzr71.24** gets a note that the board's `selfStart` reads the arm's
  key from the board's own rows, a read section 2's exception covers, so it is
  added to no board Debt entry. Whether a bead starts by itself is also
  `queue`'s answer, which reads the arm from the record and which the rig page
  already asks.
- **tk-t91hbtx** gets a note that section 6 answers it with Gas City's
  hand-off, and that a person's raw assignment to a running agent stays a gap
  until upstream ask 2, so its validating closer judges it on that answer.
- **The units** are filed as tk-1tfzr71.99's description says, with
  `target=integration/tk-1tfzr71.16` in each create, and tk-1tfzr71.16 and the
  summary task wait on each.

## 15. Gas City facts, and the search behind the surface the units add

The units add three verbs, an order's new `exec`, a lock per bead, a title
token on the pours they make, and a line per arm that the start prints. For
each, the search was for a Gas City or bd primitive that pours on readiness,
reports a finished launch, or keeps and reads a launch put off until a bead is
ready, and none covers the need. The start's lines decode the arm, a record
only the pack keeps, so no primitive reads it. Section 6 adds no surface: it
composes Gas City's hand-off, its nudges and its controller's wake. Nor does an
unfinished pour (section 4): the start asks a person through the gate it
already has, and Gas City's own `gc convoy delete` closes the root.

| Fact | Upstream 3bcab243e and dba20336ed | The city's build 6589a7df45 |
|---|---|---|
| Nothing pours a formula when a bead's blockers close | no core order or script calls `gc sling`; `cascade-nudge-on-blocker-close.sh` and `nudge-on-route.sh` only nudge | same scripts, plus the queued delivery below |
| `gc sling` pours without reading readiness | `internal/sling`: `validateExistingBeadInQuerier` checks existence only, and no readiness check precedes a pour | a dry run on a blocked armed bead prints "A wisp will be attached automatically" |
| Nothing keeps a launch for later, so nothing lists or decodes one | no command or order records a launch for a later pour (the two rows above), so none reports one | same; bd 1.3.4's `list --has-metadata-key` selects the rows that carry a key and decodes no value |
| Exit 3 means the launch check counts a live workflow on the bead, and names it | `cmd/gc/cmd_sling.go`: the `DoSling` error branch returns 3 for `*sourceworkflow.ConflictError` only, and `printSourceWorkflowConflictLines` prints the workflows it names; `internal/sourceworkflow/sourceworkflow.go` documents the mapping; `checkLegacySourceWorkflowConflict` in `internal/sling/sling_core.go` raises it for a live root of the same formula that the bead's input convoy tracks, or of any formula whose `gc.source_bead_id` names the bead | same |
| A pour made one bead at a time can leave a root it never finished, typed as a gate | `instantiateViaGraphApply`, `internal/molecule/graph_apply.go`, pours in one batch where the store supports one; otherwise, or after two transient batch failures, `Instantiate`, `internal/molecule/molecule.go`, makes the root first, and `fenceGraphWorkflowBead` keeps every bead fenced with `gc.instantiating`, typed as a gate and with its route withheld until all are made; `markFailed` stamps a pour that fails part way `molecule_failed=true` and clears the fences without restoring a type or route, and closes nothing; `closeFailedGraphV2Roots`, `internal/sling/sling.go`, is a separate cleanup that returns its error | same functions; bd 1.3.4's `list` shows a gate only with `--include-gates`, which `--all` does not imply (`applyTypeSuppressions`, `internal/workapi/list.go`) |
| The launch check counts an unfinished pour while its root is open | `liveConvoyTrackedWorkflowRoots`, `internal/sling/sling_attachment.go`, walks closed synthetic convoys too and reads neither mark; `CloseSyntheticInputConvoy`, `internal/graphv2/invocation.go`, closes a failed pour's convoy and keeps its `tracks` edge; `attachFormulaToBead`, `internal/sling/sling_core.go`, runs the check before the pour | same functions |
| `gc convoy delete <root> --force` closes a workflow root and its steps | `cmdWorkflowDelete` and `findWorkflowBeads`, `cmd/gc/cmd_convoy_dispatch.go` | same |
| Upstream tracks unfinished pours as #6177 and #6179 | both issues open, labeled `kind/bug` and `priority/p1`, read on 2026-11-13: #6177 for a failed chain that only a same-key retry closes, #6179 for a fenced chain a killed client leaves | the build carries no fix for either |
| A dry run reports a live same-formula root, and nothing reports a finished one | `dryRunReportBlockingMolecule` with `sling.LiveConvoyTrackedWorkflowRoots`, "the same check checkLegacySourceWorkflowConflict runs at launch time" | same |
| `--title` names the root of a formula pour | `cmd/gc/cmd_sling.go`: "wisp root bead title (with --formula or --on)" | same |
| bd ignores a cross-prefix blocker, and Gas City re-judges one only on a split city | `internal/readywork/crossstore.go` header | `gc config show` names no class binding |
| The idle-claim backstop serves pool slots only | `nudgeStalledPoolClaims`, `cmd/gc/idle_nudge.go` | same |
| A default nudge wakes a stopped session, and a queued one does not | `deliverSessionNudgeLegacy`, `shouldQueueManagedNudgeWake` | same functions; `queueSessionNudgeWithWorker`; the help text of `gc session nudge`; cascade-nudge queues its assignee nudge (51055e7d3f) |
| `--reference-bead` exists on the fork only | absent from `cmd/gc/cmd_session.go` | present |
| The controller wakes a stopped session that has ready work assigned to it, and an on-demand named session that has ready work routed to it | the assigned-work pass of `computeAwakeSetKeyed`, through `workBeadHasAwakeDemand`, `cmd/gc/compute_awake_set.go`; for routed work, the default probe of the session's backing template and `computeNamedSessionDemandOn`, `cmd/gc/build_desired_state.go` | same functions |
| A named session's hook serves work routed to its alias | `namedSelfTargetAdmit`, `internal/config/workquery.go`, lets a named session into the routed tier only when the probe target is its `GC_ALIAS` | same; `gc sling gc-toolkit.mechanik <bead> --no-formula --dry-run` writes `gc.routed_to=gc-toolkit.mechanik`, the mechanik's alias |
| The pool serves by `PoolDemandServeRulesForQuery` | `internal/config/workquery.go`: `--unassigned`, `--exclude-type=epic`, and an `--exclude-label` for each of `beadmeta.DispatchHoldLabels` and `beadmeta.HumanLabel`, rendered into every generated demand query | same; the labels are `hold:mayor`, `hold:external` and `human`, and bd 1.3.4's `bd ready` takes `--has-metadata-key` with those flags |
| The hook drops a held candidate whatever its label's case | `isHeldHookCandidate`, `cmd/gc/cmd_hook.go`, through `beadmeta.HasDispatchHold`, which compares each label trimmed and in any case, where the routed tier's `--exclude-label` compares exactly | same |
| Upstream tracks the gap as #7163 and #8832, with draft fix #8834 | both issues open, labeled `kind/bug` and `priority/p1`, and #8834 an open draft that closes #8832, read on 2026-11-13; neither commit carries the fix | the build carries no part of #8834 |
| Upstream removed its named-seat backstop | 386211397c (#6551), an ancestor of both commits, reverts #6302 and #6287, and its release notes say named seats have no controller claim or execution backstop and name follow-up ga-o1w8h | same: 386211397c is an ancestor of the build |
| Gas City's readiness treats a blocker closed as blocked as still holding | `beads.DependencySatisfied` with `beads.ReadinessWorkOutcome`, `internal/beads/beads.go` | same |

The last fact is not one the design relies on. The start's rule and
`gctk bead holds` read bd's readiness, which may release such a dependent where
Gas City's own readiness holds it, so that difference is filed as its own bead
for `waits` (tk-ih6w722).
