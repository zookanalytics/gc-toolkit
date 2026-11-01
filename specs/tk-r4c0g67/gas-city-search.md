---
name: Gas City search for a witness's next patrol turn
description: Read this when you change how a witness's patrol continues, or ask why the witness ends its turn with a nudge order behind it while the deacon takes a Stop hook. It is the search the arch check asks for before the pack adds the witness-nudge order. It holds what Gas City and its published packs ship for a named session whose turn has ended, read at named upstream commits, the transcript census behind the cause, and the comparison that chose Gas Town's ending with the order as its backstop.
---

# Gas City search for a witness's next patrol turn

A witness is a named session in mode `always`, and its patrol is a loop of wisps,
one pass each. Each of the three witnesses running on 2026-10-31 sat idle at its
prompt for two to three days, twice, until something restarted it, and its HELP
mail went unread the whole time.

This change takes Gas Town's ending for the witness, with one named difference: its
last step waits before it pours. A pass then ends the way Gas Town's does. The step
pours and assigns the next wisp, leaves it open, burns the current one and ends the
turn, and Gas City's reassignment restart runs the next pass in a fresh session.
It also adds an order that nudges a witness whose pane has gone quiet, as the
backstop for a session that stops short of that step
([patrol-continue.md](../../docs/patrol-continue.md#the-witnesss-order)). An order is
new operational surface, so the arch check asks what Gas City already ships for the
need ([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City's continuation for a named session in mode `always` is the reassignment
restart. It holds off in the shapes that stall, and the first of them is this
pack's own: our copy of the step told the session to carry on in its conversation,
where upstream had ended the turn since June. The other shape, a session that stops
short of its last step, is upstream's as well. There Gas City's stall timeouts are
city-wide and ignored under the v2 reconciler this city is moving to, and its ladder
and backstops govern pool seats only, so a pack composes the backstop from a
documented seam. The two on offer are a provider hook and an order that nudges, and
the second won the comparison below.

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

**The shape that stops short is upstream's as well.** gastownhall/gascity #4090, open
since 2026-07-08, reports patrol sessions holding their wisp with every native
recycle path deferring, and its reporter runs a nudge order as the workaround.

## The need

- The next pass comes without the model's cooperation once a pass has ended, and a
  session that ends its turn short of that still gets another turn, because the
  model ending its turn early is the failure. The measured shapes are in
  [the cause](#the-cause).
- It comes within a bounded time, of the same order as the formula's 600s
  inter-cycle wait.
- A pack can ship it, and it reaches witnesses without changing how any other
  session in the city behaves.
- It keeps working when the city moves to the v2 reconciler, which the operator
  has ruled follows the next upstream sync (tk-gf45oyj).
- It interrupts no running turn and no operator at the pane, and it spends nothing
  while the store is down.

## Where the search looked

Each was read on 2026-10-31:

- Gas City at upstream main `d1a150cac8f8`: the configuration and CLI references,
  the guides and tutorials, the core pack's orders and overlays, and its source
  for session restarts, stall recycling, the work ladder and pool backstops, idle
  and age limits, nudge delivery, events and the hooks it installs.
- The Gas Town pack at `cb6a612882b8`, the pin that Gas City at that commit
  bundles, and every published pack at packs main `0b0d96250f66`, with the history
  of Gas Town's `next-iteration`.
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
v2). This is what normally moves a witness from one wisp to the next, and it does
not need the model's cooperation. Gas City's config check names the pairing of mode
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
mode = "always"" ([Agent](https://docs.gascity.com/reference/config#agent), and
[Configure the Gastown Pack](https://docs.gascity.com/guides/gastown-config-recipes)
says the same of the witness). `v2LatchRefusals` also refuses a v2 boot on any
agent that sets `max_session_age`, so setting it would block the ruled switch.
`ComputeAwakeSet` exempts an always-mode named session from idle sleep, so
`sleep_after_idle` and `[session_sleep]` do not reach it either. The named-session
circuit breaker suppresses respawns and starts no turn.

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
turn.`, all at the bundled pin. The formula credits a `session_sleep` policy with
the restart. `ComputeAwakeSet` exempts these sessions from idle sleep, and Gas
Town's own `test_deacon_ends_turn.sh` says that policy "never engages for an
always-on session". What restarts it is the reassignment restart above, and the
test says so of the deacon: "Gas City moves an always-on deacon onto its next cycle
only when the wisp it was running is gone".

So Gas Town has the same gap in the mid-cycle shape, and at packs main it answers
with a watcher. `witness-heartbeat-check` reports that "Patrol stalls of 14h to 63h
were observed in production this way with no alert". `mol-deacon-patrol`'s
health-scan reads it, taking the newer of `last_active` and
`last_nudge_delivered_at` against a 90 minute window, and its table says "nudge,
then warrant if the stall survives the nudge". The check is absent at the bundled
pin, this city imports no Gas Town pack, so `gc gastown` is an unknown command
here, and its nudge lives in a health-scan step this pack's deacon does not carry.
It confirms the shape and the clock this change uses. This change takes a shorter
window, because this witness has a 600s wait to compare against rather than a
one-hour idle timeout.

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

The candidates are ending the turn as Gas Town does, a hand-back at the turn
boundary, which is the hook this branch first extended to the witness and which
remains on main for the deacon, and a nudge from a cooldown order. The first
changes how a pass ends, and the other two act once a session has stopped, so the
question is what each covers.

| | End the turn as Gas Town does | `Stop` hook hand-back | Cooldown order and nudge |
|---|---|---|---|
| A session that holds its next wisp and idles | the session no longer marks it, by the step and the prompt | the next cycle at once | the next cycle after the quiet bound and the next pass |
| A session that stops short of its last step | no restart, so it does not help | the next cycle at once | the next cycle after the quiet bound and the next pass |
| A witness already idle at landing | needs one prompt by hand | needs one prompt by hand | reached by the first pass |
| An operator who leaves the pane with no prompt | no restart if it holds its wisp | stays idle | reached once they detach |
| A conversation Claude Code ends after nine blocks | not applicable | stays idle | reached |
| A prompt arriving mid-cycle | none is typed | cannot, it runs only at a boundary | cannot, a working pane does not read as quiet |
| An attached operator | the restart reads no attachment, so it ends the conversation under them at each burn, as it did before this change | the hand-back goes on, only the reset waits | skipped |
| Store or controller outage | the pour guard leaves the wisp, and the turn ends | quick turns while cycles fail, and a reset to retry | the pass fails and spends nothing, and the next one retries |
| Loop risk | none, a fresh session per pass | needs a guard, a state file, a reset and a failed-reset path | none, the order sets the pace |
| Pace | about twelve minutes a pass with the wait | the formula's, while the model takes the wait | for a witness that went quiet, about 11 to 16 minutes after its turn ended, longer on a loaded host |
| What it depends on | the model reaching the step, and the controller's restart | nothing for a hand-back, the store and controller for the reset | the controller's order lane and the session list |
| Provider | any | Claude Code only | any, by way of `gc session nudge` |
| v2 | `freshCycle` restarts it, by reading, since v2 does not run here | unaffected | unaffected |
| New surface | none, a step's prose and a prompt paragraph | a role and several paths in an existing script | one order, one short script and its suite |

**Pace and token cost.** The wait comes before the pour because a wait after it
never holds. A healthy session was killed a median 39 seconds into its wait (330
sessions since the build whose kill is in the event archive; 44 seconds across all
513 with one), and its successor's transcript started a median 65 seconds in. While
the session holds its current wisp in progress the restart holds off, so a wait
before the pour runs to its end. Gas Town's has no wait because it credits a
`session_sleep` policy, and `ComputeAwakeSet` exempts these sessions from idle sleep,
so its ending would run back to back here.

Those measured numbers set the pace. Across the 7,017 sessions that left the next
wisp open and were restarted, a new session started a median 133 seconds after the
last. Each averaged 13 API calls, 59.8k tokens of cache writes, 623.7k of cache reads
and 4.2k of output, 688k tokens in all and 91% of them cache reads (772k across the
369 since the build). A pass reached its pour a median 53 seconds in, and 122 at the
90th percentile. So the new step's cycle is that minute, the 600 second wait, and a
restart about a minute after the turn ends: about twelve minutes, or about 120 passes
a rig a day by arithmetic. Each pass gains one API call, because the session now
outlives its wait, at about 73k tokens of cache reads. The wait loses no cache: every
cache write on record is in the one-hour tier, and after 194 gaps of 500 seconds or
more the next call wrote a mean 1.4k tokens and read a mean 85.9k. That comes to about
100M tokens a rig a day, nearly all cache reads. With no spacing, one rig spent 398M
and 480M tokens on its two busiest days, at 575 and 698 sessions. A witness spends
next to nothing while it idles, so against the last week this is new spend.

The nearest measured case for the spacing is the deacon, whose step has waited before
its pour since 2026-10-01. Of its 841 sessions from 2026-10-02 to 10-12, 751 waited and
then poured, one poured with no wait, and the other 89 show no pour the census could
read. The pour came a median 602 seconds after the wait began (580 at the 10th
percentile, 642 at the 90th), and its sessions started a median 903 seconds apart, on a
longer pass. No witness has run this step, so its pace and whether its model takes the
wait are what only a live run can show. Under the old step, 39 of the 369 restarted
witnesses since the build issued no wait the census could read. A witness that skips
the wait under this step costs one short cycle, not a stall.

[The ending probe](ending-probe.md) runs the step on the witness's model against a
stubbed `gc`, and it holds what a late configured nudge does.

The 11 to 16 minutes this record first gave as the pace holds only for a witness that
went quiet. It is the quiet bound plus the next order pass. The declared interval is
5m. The pack's `boot-health`, also on 5m, ran 5.0 to 5.7 minutes apart over its last
ten runs on 2026-10-31. On a loaded host the dispatch budget can stretch a 5m order
past fifteen minutes (`max_dispatches_per_tick`), so the bound is minutes to tens of
minutes where the failure was days. The hook is faster at the boundary, and the
measured harm does not need that speed.

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
and the order's `idempotent = true` keeps a contended store from skipping a pass
that could still run. Witness cycles could not make progress in that outage anyway,
so waiting spends nothing, and the first pass after it ends gets each witness going.
When the session list still answers and only the witness's own store is down, the
nudge goes out and buys a short failing pass, at the order's pace.

**What the order costs.** It takes one read of the session list per pass (about a
second on 2026-10-31) and one tracking wisp per run. It gives no report: a witness
whose pane keeps printing while its patrol stands still gets no nudge, and nothing
reports it. tk-1tfzr71.18 owns that report. A nudge buys one pass. Three hand nudges
on 2026-10-30, sent with the default delivery and carrying the instruction this
order's nudge carries, each reached an idle witness and bought a pass of 11 to 42
seconds. Each pass adopted its wisp and read its inbox, orphans and refinery queue,
and two of them poured the next wisp. `--delivery immediate` is the form
`quota-park-nudge.sh` sends, and it reached witnesses on 2026-10-26 and 2026-10-27.
The comment on `orders/boot-health.toml` calls delivery to a fresh-wake singleton
unreliable. All of those nudges landed, so that comment does not hold here, and the
bead that retires that order carries the point.

**The decision.** The witness takes Gas Town's ending with the wait before the pour,
because it removes the cause of 9 of the 13 stalls at no new surface and makes the
restart the normal continuation. It leaves the three that stopped short, so a backstop
stays. Between the backstop's two candidates the order meets every item in the need,
reaches the cold cases the hook cannot, and needs no loop guard. The hook's own account
of itself had grown to wait wording, a repeat hand-back, a failed-reset path and a
bound that holds only where `timeout` is on `PATH`, all of which go with this move. So
the order stays as the backstop, and the branch's changes to the hook come out.

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
ending adds no surface: it reorders two blocks of one step, unchanged, and rewrites
that step's prose and a prompt paragraph. The surface is one order and one script that
runs `gc session list` and `gc session nudge`. It adds no semantics Gas City's mechanisms express: it holds no
claim, assigns nothing and waits on nothing. The quiet clock is read from Gas City's
own session row.

## When the answer changes

- Gas City paces an always-on session, as Gas Town's step assumes. The wait then goes.
- Gas City closes #4090 or ships a continuation for a session that stops short, or a
  stall recycler with an agent-level form that the v2 reconciler honours. On 2026-10-31
  none exists at the commits above. The order then goes.
- tk-1tfzr71.19 moves the witness's duties onto orders or Gas Town's roles. The order
  goes if that takes Gas Town's deacon, which nudges a quiet witness through its
  health scan.
