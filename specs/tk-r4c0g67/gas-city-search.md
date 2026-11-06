---
name: Gas City search for a witness's hourly patrol
description: Read this when you change how a witness's patrol continues or how far apart its passes run, or ask why the witness defers its next wisp, why a nudge order backs it, or why the deacon takes a Stop hook instead. It is the search the arch check asks for before the pack adds the defer and the witness-nudge order. It holds what Gas City, bd and the published packs ship for an always-on session's next turn and its pace, read at named upstream commits, the transcript census behind the cause, and the comparisons behind the defer and the order.
---

# Gas City search for a witness's hourly patrol

A witness is a named session in mode `always`, and its patrol is a loop of wisps,
one pass each. Each of the three witnesses running on 2026-10-31 sat idle at its
prompt for two to three days, twice, until something restarted it, and its HELP
mail went unread the whole time. On 2026-11-06 two of them had printed nothing for
54 and 57 hours, each holding its patrol wisp in progress.

This change takes Gas Town's ending for the witness, with one named difference: its
last step defers the next wisp an hour with bd. A pass pours and assigns the next
wisp, defers it, burns the current one and ends the turn, and once the hour has
passed Gas City's reassignment restart runs the next pass in a fresh session. It
also adds an order that nudges a witness whose pass stopped with its wisp still in
progress, as the backstop for a session that stops short of that step
([patrol-continue.md](../../docs/patrol-continue.md#the-witnesss-order)). The order is
new operational surface and the defer puts a bd state to a new use, so the arch
check asks what Gas City already ships for each need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City's continuation for a named session in mode `always` is the reassignment
restart, and Gas City applies no idle interval to such a session, so nothing it
ships spaces the passes. bd's dated defer spaces them with what both already do:
bd keeps a deferred bead out of the open list the restart reads, and its own wake
returns the bead to open once the date has passed. The restart holds off in the
shapes that stall, and the first of them is this pack's own: our copy of the step
told the session to carry on in its conversation, where upstream had ended the turn
since June. The other shape, a session that stops short of its last step, is
upstream's as well. There Gas City's stall timeouts are city-wide and ignored under
the v2 reconciler this city is moving to, and its ladder and backstops govern pool
seats only, so a pack composes the backstop from a documented seam. The two on offer
are a provider hook and an order that nudges, and the second won the comparison
below.

## The cause

The census reads witness transcripts on every rig, 8,073 sessions born since
2026-10-14. A session's class comes from its own Bash commands: the first command
outside the startup reconcile that holds both the pour and a burn, then any
`bd update` that marks the next wisp in progress at or after it. A new transcript
within 15 minutes of the pour means the restart worked. Pours run from a scratch
script land in neither class, so the stalls below were read by hand.

Gas City's any-claim guard, #8012 (`2dec01c71`, merged 2026-10-17), reached this city
with the build installed at 2026-10-24T19:01Z, and the supervisor restarted at 19:03Z.

| After the pour, the session | Before that build | Since that build |
|---|---|---|
| left the next wisp open | 6,648 of 6,675 restarted | 369 of 369 restarted |
| marked the next wisp in progress | 142 of 148 restarted | 0 of 8 restarted |

Since that build, 13 gaps of 6 hours or more separate one witness session's start
from the next. Nine sessions held their next wisp, three stopped short of
`next-iteration` still holding their wisp, and one hit a usage limit.

**The shape that adopts its next wisp is ours.** Our `next-iteration` waited after
the pour and then told the session to read the formula again for the next cycle, so
a session that took the text at its word carried on in the same conversation and
sometimes marked its next wisp in progress. Gas Town's ended the turn at that point
from 2026-06-07 (gascity `a7af62efe`, #3156), and ours never took that change. The
restart used to cover the difference: it fired anyway, a median 39 seconds into the
wait, so the conversational loop in our text rarely ran. #8012 took that cover away
on 2026-10-24 for a session holding any in-progress work, and the session idled.
Healthy witnesses were not looping in their conversations. They ran a fresh session
about every two minutes, and the supervisor log holds 6,384 "Cycled fresh-mode
session" lines naming a witness.

**The shape that stops short is upstream's as well.** Gas City's restart holds off
for a session that still holds its current wisp
([the reassignment restart](#the-reassignment-restart)), and Gas Town answers that
gap with a watcher ([Gas Town](#gas-town)).

**gastownhall/gascity #4090 is not that shape.** Open since 2026-07-08, it reports this
ending frozen on Gas City 1.3.3: patrol sessions poured and assigned their successor,
exited idle and were never recycled, and its reporter runs a nudge order as the
workaround. That release has no reassignment restart. `792ad0337` (#3288) added it and
is in neither `v1.3.3` nor `v1.3.5`. This city's build has it, and here the same shape
was restarted 53 of 53 times. So closing that issue does not by itself retire the
order, which serves a session that stops short.

## The need

- The next pass comes without the model's cooperation once a pass has ended, and a
  session that ends its turn short of that still gets another turn, because the
  model ending its turn early is the failure. The measured shapes are in
  [the cause](#the-cause).
- Passes run about an hour apart, the pace Gas Town's witness asks for, so a
  witness spends about a fifth of what a ten-minute spacing spends and HELP mail
  waits up to an hour.
- A pass that stops gets its next turn within a bounded time, short against that
  hour.
- A pack can ship it, and it reaches witnesses without changing how any other
  session in the city behaves.
- It keeps working when the city moves to the v2 reconciler, which the operator
  has ruled follows the next upstream sync (tk-gf45oyj).
- It interrupts no running turn and no operator at the pane, and it spends nothing
  while the store is down.

## Where the search looked

The backstop was read on 2026-10-31 and the pace on 2026-11-05 and 11-06:

- Gas City at upstream main `d1a150cac8f8` (2026-10-31): the configuration and CLI
  references, the guides and tutorials, the core pack's orders and overlays, and its
  source for session restarts, stall recycling, the work ladder and pool backstops,
  idle and age limits, nudge delivery, events and the hooks it installs.
- Gas City at upstream main `f798826db` (2026-11-05): the idle limits' exemption for
  an always-on session, how the controller reads an assigned patrol wisp as wake
  demand and treats bd's deferred status, and the marker the reassignment restart
  compares.
- bd at its upstream release `v1.3.4` (gastownhall/beads `a60c4c3a0`): `--defer` and
  the wake of an expired defer. The city runs bd 1.3.2 (`9b65b9e19`), which carries
  the same code.
- The Gas Town pack at `cb6a612882b8`, the pin that Gas City at `d1a150cac8f8`
  bundles, every published pack at packs main `0b0d96250f66`, with the history of
  Gas Town's `next-iteration`, and the Gas Town pack at packs `66897e7132c9`
  (2026-11-02) for its witness's ending and agent settings as they ship.
- The Claude Code hooks reference, for the hook alternative.
- The city's installed build, `gc` 1.4.3 at the fork commit `e03752646`. It is
  not an ancestor of upstream main, so it says what runs here and not what Gas
  City ships. Its supervisor log says this city runs the legacy reconciler, as a
  fallback.

## What Gas City ships near the need

### The reassignment restart

An alive `wake_mode = "fresh"` session whose assigned bead differs from the bead
it last recorded is stopped and started on a new conversation (package main,
`cycleAliveSessionForFreshReassign` on the legacy reconciler and `freshCycle` on
v2). The awake decision flags it: `RequiresFreshCycle` is set when the session's
anchor, the work bead it is assigned, differs from its recorded
`currently_processing_bead_id` (`cmd/gc/compute_awake_set.go:586` at `f798826db`).
That marker is only ever overwritten, by `recordCurrentBeadIDOnWake`
(`cmd/gc/session_bead_cycle.go:29`) and `armCurrentBead`
(`cmd/gc/reconcile_arms_heals.go:540`), so it survives an idle hour. This is what
normally moves a witness from one wisp to the next, and it does not need the
model's cooperation. Gas City's config check names the pairing of mode
`always` and `wake_mode = "fresh"` "a deliberate restart-per-cycle actor" (package
config). Its restart reaches a session at an idle prompt as it does one in a wait:
53 of 53 sessions that ended their turn with the next wisp open since the build were
restarted, a median 52 seconds after the turn ended and at most 302.

It holds off in both shapes that stall. The legacy reconciler skips it when the
previous bead is still open and assigned to the session, and when the session
holds any in-progress claim (`sessionHasFreshInProgressClaim`). So a witness that
set its next wisp in progress and then ended its turn is not restarted, and
neither is one that stopped partway through a cycle. I read no any-claim guard in
the v2 arm, so the first shape should restart there, though v2 does not run in this
city to prove it. `freshCycleDefers` keeps the hold on an open previous bead, so
the second shape would not.

### What holds a deferred wisp, and what releases it

`bd update --defer <date>` records the bead in bd's `deferred` status with the date,
unless the date is past or the same call sets a status of its own
(`cmd/bd/update.go:315-320` at `v1.3.4`). A ready read or a claim returns every
expired dated defer in its store to `open` and clears the date
(`WakeExpiredDefersInTx`, `internal/storage/issueops/wake_defers.go:53`), wisps
included, and `GetReadyWork` runs that first (`internal/storage/dolt/queries.go:98`).
In bd's compact durations `h` is hours and `m` is months
(`internal/timeparsing/parser.go:22-32`).

Gas City reads an assigned root-only patrol wisp as wake demand through a live list
of the beads bd records `open` (`listOpenForControllerDemandLive`,
`cmd/gc/build_desired_state.go:3088`, read at `:1950`). A row in that list counts
when `isOpenAssignedMoleculeWork` (`:3560`) passes it, and `markReadyAssigned`
(`:3550`) marks it ready. The legacy reconciler's read is that list
(`legacyDemandReads.RawOpen`, `cmd/gc/allocator_demand_reads.go:92`). v2's is the
same list on a bd store, whose cache folds bd's richer statuses into open, and the
cache's raw status on a store whose cache keeps it (`v2DemandReads.RawOpen`, `:189`,
and the comment at `:130-137`). `isOpenAssignedMoleculeWork` reads a row's status,
assignee and type, and never its `defer_until`. So a deferred wisp is no demand, and
a wisp kept open with a future date would restart the session at once. The
controller also makes a live ready read of each store on its passes
(`cache.liveReady`, `build_desired_state.go:2055` and `:2061`), which runs
`bd ready --json` (`BdStore.Ready`, `internal/beads/bdstore.go:3538`, its arguments
at `:3687`), so its own passes release an expired defer.

So bd's status holds the hour, bd's own wake releases it, and the restart then fires
as it does for any reassignment. On one rig a witness stayed idle through a
five-minute defer, the wisp woke 29 seconds after its date, the restart came 2
minutes 46 seconds after it, and the new session ran its pass
([deferred-restart-proof.md](deferred-restart-proof.md)).

The sitting that proposed the defer read the hold from `beads.IsDeferred`
(`internal/beads/beads.go:949`) and the deferred filter at
`cmd/gc/assigned_work_scope.go:241`. Those serve pool demand and do not decide a
named session's patrol wisp. `IsDeferred` also reads a dated deferred row
differently by build: at `e03752646` it is a clock check, and at `f798826db` a row bd
records deferred stays deferred until the store wakes it (`normalizedBdReadState`,
`internal/beads/bdstore.go:1471`, #6207). Neither changes the path above, which
reads bd's raw status on both.

### The stall timeouts

`[session] progress_stall_timeout` and `claim_holder_stall_timeout`
([SessionConfig](https://docs.gascity.com/reference/config#sessionconfig))
restart a desired, alive session whose provider-reported activity is older than
the setting (package main, `sessionProgressStalled` and
`sessionClaimHolderStalled`). The tmux provider reads the pane's window activity,
less the keystrokes that same process typed (package tmux,
`Provider.GetLastActivity`, `discountedActivity`), so the controller discounts its
own nudges and a separate `gc session list` process discounts nothing. The block
has no exemption for mode `always`, so on the legacy reconciler the pair would
restart an idle witness whether or not it holds a claim. This is the nearest
thing Gas City ships, and it does not serve:

- **It is city-wide, and a pack cannot ship it.** `SessionConfig` has no agent or
  rig form, and `PackConfig` has no session table (package config). It is a town
  commit that changes every session.
- **It reaches sessions that must not restart.** The docs ask for a value "above
  the longest legitimate alive-idle period for the city". A converse sitting
  waits in place for a person with its visit in progress
  (`agents/_converse/prompt.template.md`), for as long as the person takes. For a
  session holding a claim, only an attached client, a pending interaction, a start
  in flight, a pin and a provider known to be down hold the restart back, so a
  sitting whose operator has left its pane takes it. The restart rotates the session
  key, so the conversation ends.
- **Gas City is retiring it.** Both rows read "Legacy only: deprecated and ignored
  under the v2 reconciler, whose work ladder replaces it", and the controller logs
  the deprecation (`v2IgnoredSettings`). The ladder that replaces it does not
  govern a named session, so the witness would lose its continuation on the day
  of the ruled switch.

### The work ladder and the pool backstops

The v2 work ladder "paces outstanding work on pool seats"
([DaemonConfig](https://docs.gascity.com/reference/config#daemonconfig)).
`ladderGoverns` admits only rows with `pool_managed=true`. The legacy backstops
it replaces read the same key: `poolClaimBackstop`, `poolContinuationBackstop` and
`poolExecutionBackstop`. The session sync clears that key on a configured named
session, and a witness's row carries `configured_named_mode=always` and no
`pool_managed`.

### The idle limits

`idle_timeout` and `max_session_age` are "Not applied to a [[named_session]] with
mode = "always"" ([Agent](https://docs.gascity.com/reference/config#agent)), and
[Configure the Gastown Pack](https://docs.gascity.com/guides/gastown-config-recipes)
says it of the witness by name: "`idle_timeout` and `max_session_age` have no effect
on `mayor`, `deacon`, `boot`, or `witness`: the Gastown pack runs them as always-on
named sessions (`mode = "always"`), and the orchestrator keeps those running"
(`docs/guides/gastown-config-recipes.md:97-99` at `f798826db`). In source,
`lifecycleSetting` (`cmd/gc/reconcile_arms_idle.go`) returns a value only for a
named session whose mode is not `always`, the same at `f798826db` and `e03752646`,
since `281cedb15` (2026-04-11). On 2026-11-05 a witness held no assigned work for six
minutes, through 52 controller passes, and nothing stopped it (tk-r4c0g67's notes).
`v2LatchRefusals` also refuses a v2 boot on any agent that sets `max_session_age`, so
setting it would block the ruled switch. `ComputeAwakeSet` exempts an always-mode
named session from idle sleep, so `sleep_after_idle` and `[session_sleep]` do not
reach it either. The named-session circuit breaker suppresses respawns and starts no
turn.

### The configured nudge

An agent's `nudge` is "text typed into the agent's session after startup"
([Agent](https://docs.gascity.com/reference/config#agent)). Its recovery re-send
is for a pool session only. A named session's bead carries startup kickoff keys
(package main, `startupKickoffStateKey`), and at this commit nothing reads them.

### Commands somebody has to run

A session can run `gc runtime request-restart`, `gc runtime drain-ack` or
`gc handoff` on itself. Gas Town's boot agent "wakes fresh, checks the deacon, and
exits, so the orchestrator keeps starting it again"
([Configure the Gastown Pack](https://docs.gascity.com/guides/gastown-config-recipes#stop-boot-from-restarting)),
and Gas Town's deacon falls back to `gc runtime drain-ack`. All of these need the
model to run them, and a turn the model ended is what we are recovering from.

From outside a session, [`gc session nudge`](https://docs.gascity.com/reference/cli#gc-session-nudge),
`gc session reset` and `gc session wake` give it a turn or a restart, and
`gc mail send --notify` requests "a recipient turn after sending". "Unread mail
alone does not request a wake", and a notify buys one turn per message, which runs
no orphan or queue check on a quiet rig. `gc session wait` wakes a session when
named beads close, so somebody has to register the wait, and a stalled patrol has no
bead about to close. So these are seams, and a caller has to supply the policy.

### Orders, events and hook events

Gas City's [orders](https://docs.gascity.com/tutorials/07-orders#trigger-types)
are its native scheduled job, and
[Coming from Gas Town](https://docs.gascity.com/getting-started/coming-from-gastown#common-translation-patterns)
says to "Prefer the order" over a new role. None of core's orders gives a turn to
an idle patrol session. `nudge-on-route` and `cascade-nudge-on-blocker-close` act
on a routed bead and a closed blocker. `notify-on-human-gate-creation` and
`renudge-stale-human-gates` act on gates. `nudge-mail-sweep` closes stale nudge
and mail beads, and despite its name it nudges nothing. `reaper` and `jsonl-export`
nudge only the target `GC_MAINTENANCE_DONE_TARGET` names.

The event bus has no turn-end event (package events), so an event order cannot
fire at a turn's end. `gc converge` and a `[steps.check]` loop are bounded
refinement loops that end when a gate passes, and a patrol has no such gate.

Gas City's Claude settings wire `SessionStart`, `PreCompact` and `UserPromptSubmit`
(package hooks, `config/claude.json`), and none of its provider configs wires a
turn-end hook that acts on the session. It leaves the door open: the comment on
`claudeFileNeedsUpgrade` names "an extra Stop hook entry" as a custom addition, and
`codexHookOutput` renders a block decision for a `Stop` event. `overlay_dir` is how
a pack stages provider files into an agent's work dir.

## What the published packs do

### Gas Town

Gas Town declares its witness and deacon as named sessions in mode `always` with
`wake_mode = "fresh"`, and its witness's `next-iteration` pours the next wisp,
assigns it, burns the current one and ends the turn with `IDLE: no work, exiting
turn.`, at the bundled pin and at packs `66897e7132c9`. The formula credits a
`session_sleep` policy with the restart, and its witness ships `idle_timeout = "1h"`
(`gastown/agents/witness/agent.toml`). #3156 (gascity `a7af62efe`), which gave the step
that ending, states the intent: "Deacon & witness (`mode=always` patrol): ~1h via
`idle_timeout=1h`". Neither reaches an always-on session ([the idle
limits](#the-idle-limits)), and Gas Town's own `test_deacon_ends_turn.sh` says the
sleep policy "never engages for an always-on session". What restarts it is the
reassignment restart above, about a minute after each pass, and the test says so of
the deacon: "Gas City moves an always-on deacon onto its next cycle only when the
wisp it was running is gone". So Gas Town's witness runs back to back on Gas City
today, and the hour it asks for is what the defer gives this one.

So Gas Town has the same gap in the mid-cycle shape, and at packs main it answers
with a watcher. `witness-heartbeat-check` reports that "Patrol stalls of 14h to 63h
were observed in production this way with no alert". `mol-deacon-patrol`'s
health-scan reads it, taking the newer of `last_active` and
`last_nudge_delivered_at` against a 90 minute window, and its table says "nudge,
then warrant if the stall survives the nudge". The check is absent at the bundled
pin, this city imports no Gas Town pack, so `gc gastown` is an unknown command
here, and its nudge lives in a health-scan step this pack's deacon does not carry.
It confirms the shape and the clock this change uses. This change takes a shorter
window, 11 minutes, because it nudges only a witness that holds its wisp in
progress, whose pane goes quiet only once its pass has stopped. Gas Town's 90
minutes covers a witness idle between passes.

Gas Town's step is the ending this change takes, with the differences named in
[the comparison](#the-comparison). The plan's page lists every remaining difference
between our witness and Gas Town's
([built-once-target.md](../../docs/built-once-target.md#patrol)).

Gas Town's deacon prompt rejects a hand-back at the turn boundary: "A deacon that
re-enters its own loop never ends a turn and patrols back to back, model call
after model call, on an idle town." An order leaves the turn ended and sets the
pace from outside, so it does not take that risk.

### oversight-rig

`patrol-project-leads` is the published composition this change follows: a
`cooldown` order on a `15m` interval whose exec runs `gc session nudge` on each
active `project-lead`, a named session in mode `always`. Its script is plumbing,
and the decisions stay with the session.

No published pack wires a `Stop` hook, and none sets either stall timeout.

### This pack

`orders/quota-park-nudge.toml` already gives a turn to sessions parked at a
provider banner, because "nothing else wakes it". It skips attached sessions, reads
`last_active` as the pane's last output, and uses `--delivery immediate`. The
deletion plan retires it under tk-1tfzr71.18, so this change leaves it untouched.
Its `epoch` jq definition is copied, because sharing it would mean editing a file
the plan retires, and the definition is ten lines.

## The comparison

Two questions decide the design: what spaces the passes, and what backs a pass that
stops.

### What spaces the passes

These were the options put to the operator (gate tk-b3tsqfe). The token figures are
arithmetic from the per-pass average below, not measured.

| | Defer the next wisp an hour | An order resets the witness after an hour | Gas Town's ending as it ships | A ten-minute wait in the step |
|---|---|---|---|---|
| Pace | about an hour | about an hour | back to back, a session about every two minutes | about twelve minutes |
| Tokens a rig a day | about 20M | about 20M | 398M and 480M on one rig's busiest days, with no spacing | about 100M |
| What starts the next pass | the reassignment restart, after bd's wake | `gc session reset` from our order | the reassignment restart | the reassignment restart, after the wait |
| What it rests on | bd's deferred status, its wake on a ready read, the controller's ready read | the order's lane, a quiet clock and a reset that can fail in the outage it serves | nothing new | the model taking the wait |
| Differences from Gas Town | one, the defer | two, an ending that assigns no next wisp and the reset | none | one, the wait |
| New surface | one write in the step, and the startup reconcile reads deferred wisps | a second action in the order's script | none | none |
| If its own write fails | the next pass comes within minutes, as Gas Town's does | the witness idles until the next order pass | no write of its own | no write of its own |

A restart for another reason inside the interval runs that pass early under the
defer, because the startup reconcile adopts the deferred wisp. Under the reset it
would run a pass early too.

**The decision.** The operator asked for "Gas Town's witness logic but with a longer
delay before it spins up again" and accepted the defer on 2026-11-06 (conversation
tk-fm7kex0), with a proof on one rig first and the order's reset as the fallback if
the proof failed. The proof passed. The defer keeps Gas Town's ending and Gas City's
own restart and adds one write, where the reset would add a second difference and a
restart path of ours.

**What else reads the wisp.** Nothing in the pack burns, closes or reports a deferred
patrol wisp. The witness's own orphan recovery lists no wisps, and the liveness sweep
reads unassigned ready work only. The deacon's stuck-session rule is a judgment about
a patrol wisp "stale past the freshness you already treat as wedged"
(`formulas/mol-deacon-patrol.toml`). No warrant has named a witness since 2026-08-12,
while all three sat visibly stale for days from 2026-10-31, and a dog probe's nudge
would buy one early pass at most.

### What backs a pass that stops

The candidates are ending the turn as Gas Town does, a hand-back at the turn
boundary, which is the hook this branch first extended to the witness and which
remains on main for the deacon, and a nudge from a cooldown order. The first changes
how a pass ends, and the other two act once a session has stopped, so the question
is what each covers.

| | End the turn as Gas Town does | `Stop` hook hand-back | Cooldown order and nudge |
|---|---|---|---|
| A session that holds its next wisp and idles | the session no longer marks it, by the step and the prompt | the next cycle at once | the next cycle after the quiet bound and the next pass |
| A session that stops short of its last step | no restart, so it does not help | the next cycle at once | the next cycle after the quiet bound and the next pass |
| A witness already idle at landing | needs one prompt by hand | needs one prompt by hand | reached by the first pass, since it holds its wisp in progress |
| An operator who leaves the pane with no prompt | no restart if it holds its wisp | stays idle | reached once they detach |
| A conversation Claude Code ends after nine blocks | not applicable | stays idle | reached |
| A prompt arriving mid-cycle | none is typed | cannot, it runs only at a boundary | cannot, a working pane does not read as quiet |
| A witness waiting out its deferred next pass | idle by design | the hook would hand it a cycle at once | left alone, since it holds no wisp in progress |
| An attached operator | the restart reads no attachment, so it ends the conversation under them at each burn | the hand-back goes on, only the reset waits | skipped |
| Store or controller outage | the pour guard leaves the wisp, and the turn ends | quick turns while cycles fail, and a reset to retry | the pass fails and spends nothing, and the next one retries |
| Loop risk | none, a fresh session per pass | needs a guard, a state file, a reset and a failed-reset path | none, the order sets the pace |
| Pace | an hour a pass with the defer | at once, which would undo the hour | for a stopped pass, about 11 to 16 minutes after its pane went quiet, longer on a loaded host |
| What it depends on | the model reaching the step, and the controller's restart | nothing for a hand-back, the store and controller for the reset | the controller's order lane, the session list, the rig map and the rig's store |
| Provider | any | Claude Code only | any, by way of `gc session nudge` |
| v2 | `freshCycle` restarts it, by reading, since v2 does not run here | unaffected | unaffected |
| New surface | one write in a step, and a prompt paragraph | a role and several paths in an existing script | one order, one short script and its suite |

**Pace and token cost.** The census sets the per-pass cost. Across the 7,017 sessions
that left the next wisp open and were restarted, each averaged 13 API calls, 59.8k
tokens of cache writes, 623.7k of cache reads and 4.2k of output, 688k tokens in all
and 91% of them cache reads (772k across the 369 since the build). A pass reached its
pour a median 53 seconds in, and 122 at the 90th percentile. So a pass, the hour and a
restart of a few minutes make about 24 passes a rig a day, about 20M tokens. With no
spacing, one rig spent 398M and 480M tokens on its two busiest days, at 575 and 698
sessions. A witness spends next to nothing while it idles, so against the last week
this is new spend.

[The ending probe](ending-probe.md) runs the step on the witness's model against a
stubbed `gc`: 3 of 3 runs poured, assigned, deferred, burned, wrote the idle line and
stopped.

The 11 to 16 minutes is the quiet bound plus the next order pass. The declared
interval is 5m. The pack's `boot-health`, also on 5m, ran 5.0 to 5.7 minutes apart
over its last ten runs on 2026-10-31. On a loaded host the dispatch budget can stretch
a 5m order past fifteen minutes (`max_dispatches_per_tick`), so the bound is minutes
to tens of minutes where the failure was days. The hook is faster at the boundary, and
the measured harm does not need that speed.

**A nudge arriving mid-cycle.** `--delivery` defaults to `wait-idle`. For a
Claude-family session it delivers live when the pane reads idle, and a wrapped
provider such as this city's `claude-watch` counts, because
`workerHandleForNudgeTarget` hands the worker the provider's family. Otherwise it
queues: behind a pending prompt, for a pane it reads as busy, or when no idle
boundary comes within 30 seconds (package main, `deliverSessionNudgeLegacy`; package
worker, `nudgeWaitIdle`). A queued nudge stamps no `last_nudge_delivered_at`, so an
order that keeps no state would queue another on each pass, and the session would
take them all at once. So the script sends `--delivery immediate`, as
`quota-park-nudge.sh` does. A working pane animates a spinner and reads as busy, so
the gate keeps the nudge away from a running turn. When a turn starts between the
read and the nudge, Claude Code takes the typed text as its next prompt.

`refuseOrQueueNudgeBehindPendingInteraction` refuses an immediate nudge to a session
at a permission prompt, so nothing queues behind it and the pass exits 1 until the
prompt is answered. Upstream main refuses at an `AskUserQuestion` dialog too
(`parseAskUserQuestion`), and its comment says why: "the nudge's Enter would select
that option". The installed build reads permission prompts only, so until this city
syncs, a nudge would answer such a dialog. The witness's prompt forbids that dialog,
and the retained witness transcripts hold one such call, on 2026-10-04. An immediate
nudge still queues when the agent is down in its pane, which lasts until the
controller restarts it, or when a Codex turn would be interrupted by its submit keys.

**An attached operator.** The session list carries `attached`, and such a session
is skipped.

**A store outage.** `gc session list` fails, the script exits 1 and nudges nothing,
and the order's `idempotent = true` keeps a contended store from skipping a pass that
could still run. When the session list answers but the rig map or a witness's own
store does not, that witness is not nudged and the pass exits 1. Witness cycles could
not make progress in that outage anyway, so waiting spends nothing, and the first pass
after it ends gets each stopped witness going.

**What the order costs.** It takes one read of the session list per pass (about a
second on 2026-10-31) and one tracking wisp per run. For a witness past the bound it
adds one rig-map read per pass and one read of that witness's in-progress wisps: a pass
over the live city on 2026-11-06, with the nudge intercepted, took 4.3 seconds and
picked the two witnesses quiet for over two days with their wisp in progress. It gives
no report: a witness whose pane keeps printing while its patrol stands still gets no
nudge, and neither does one that holds no patrol wisp at all or whose deferred wisp
never wakes, and nothing reports them. tk-1tfzr71.18 owns that report. A nudge buys
one pass. Three hand nudges on 2026-10-30, sent with the default delivery and carrying
the instruction this order's nudge carries, each reached an idle witness and bought a
pass of 11 to 42 seconds. Each pass adopted its wisp and read its inbox, orphans and
refinery queue, and two of them poured the next wisp. `--delivery immediate` is the
form `quota-park-nudge.sh` sends, and it reached witnesses on 2026-10-26 and
2026-10-27. The comment on `orders/boot-health.toml` calls delivery to a fresh-wake
singleton unreliable. All of those nudges landed, so that comment does not hold here,
and the bead that retires that order carries the point.

**The decision.** The witness takes Gas Town's ending with the defer, which removes
the cause of 9 of the 13 stalls at one write of new surface and makes the restart the
normal continuation. It leaves the three that stopped short, so a backstop stays.
Between the backstop's two candidates the order meets every item in the need, reaches
the cold cases the hook cannot, leaves a witness waiting out its hour alone, and needs
no loop guard. So the order stays as the backstop, and the branch's changes to the
hook come out.

## The deacon

The deacon keeps its hook, and this change leaves its behaviour as it is on main.
Its hook has an arch review behind it, it has held the deacon's patrol since it
landed, and `boot-health` reports the cases it misses. Its step differs from Gas
Town's in the same way the witness's did, and neither its ending nor the order is
weighed here. tk-hpy4lgk carries that, since a change to it would also have to weigh
the deacon's ledger and its doctor sweep.

## What the change adds

It adds no pack noun: no bead kind, lifecycle state or metadata key, so it takes no
warrant ([warrants.md](../../docs/warrants.md)), and no warrant covers its paths. The
ending adds one write, bd's own `--defer`, and the startup reconcile reads the
deferred status beside open and in progress. That status is bd's, and Gas City and bd
both act on it with no pack code. The surface is one order and one script that runs
`gc session list`, `rig-map.sh`, `gc bd list` and `gc session nudge`. It adds no
semantics Gas City's mechanisms express: it holds no claim, assigns nothing and waits
on nothing. The quiet clock is read from Gas City's own session row, and whether a
pass is in progress from the wisp's own status.

## When the answer changes

- Gas City gives an always-on patrol an idle interval, as Gas Town's step assumes,
  for instance by applying `idle_timeout` to it. The defer then goes, and the step is
  Gas Town's as it ships.
- bd or Gas City changes what holds a deferred wisp: bd stops recording `--defer` as
  its deferred status, its ready read stops waking an expired defer, or the
  controller's demand read starts reading `defer_until`. The proof is then run again
  before anything else changes.
- Gas City ships a continuation for a session that stops short, whether or not it
  closes #4090 with it, or a stall recycler with an agent-level form that the v2
  reconciler honours. On 2026-10-31 none exists at the commits above. The order then
  goes.
- tk-1tfzr71.19 moves the witness's duties onto orders or Gas Town's roles. The order
  goes if that takes Gas Town's deacon, which nudges a quiet witness through its
  health scan.
