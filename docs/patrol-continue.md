---
name: Patrol continue
description: Read it when a patrol session idles between cycles, or before changing how the witness ends a pass, the deacon's Stop hooks or the witness-nudge order. Covers what gives the deacon and the witness their next cycle after a turn ends, why the witness waits before its pour, when the hook lets a turn end, its loop guard, and when the order nudges.
---

# Patrol continue

The deacon's patrol is a loop of `mol-deacon-patrol` wisps and the witness's
is a loop of `mol-witness-patrol` wisps, one cycle each. They continue
differently:

- **The witness ends its turn at the end of every pass**, and Gas City's
  reassignment restart runs the next one. Its `next-iteration` step waits out the
  cycle, pours and assigns the next wisp, leaves it open, burns the current one
  and stops. A fresh session then adopts that wisp through its startup reconcile.
  This is the ending of Gas Town's witness plus the wait
  ([built-once-target.md](built-once-target.md#patrol)).
- **The `witness-nudge` order is the witness's backstop**, for a session the
  restart does not reach: one that ended its turn short of `next-iteration`, or
  still holding its wisp. The implementation is `orders/witness-nudge.toml` and
  `assets/scripts/witness-nudge.sh`.
- **The deacon's loop lives in its conversation.** Its next-iteration pours the
  next wisp and the session goes on to it. The model ends its turn after a cycle
  anyway, which leaves the session idle at its prompt, so a `Stop` hook hands it
  the next cycle at every turn boundary. The implementation is
  `overlays/cycle-recycle/.claude/hooks/patrol-continue.sh`, staged into the
  deacon's work dir by the `overlay_dir = "overlays/cycle-recycle"` patch in
  `pack.toml`, beside the cycle-recycle hook.

This document is the policy behind all three.

## Scope

**Mandate.** Whether the deacon's and the witness's patrols continue after a
turn ends: what gives each its next cycle, how the witness ends a pass and spaces
its passes, when the hook lets a turn end, its loop guard and recovery, how the
hook and the context recycle share a turn boundary, and when the order nudges a
witness.

**Boundaries.** The context recycle, which ends a patrol session's
conversation past its threshold, is [cycle-recycle.md](cycle-recycle.md).
What a cycle does is `formulas/mol-deacon-patrol.toml` and
`formulas/mol-witness-patrol.toml`, and how a session adopts its wisp is the
startup reconcile in `agents/deacon/prompt.template.md` and
`agents/witness/prompt.template.md`. Detecting a deacon that has gone cold is
the `boot-health` order's (`orders/boot-health.toml`). The `witness-nudge` order
reads a witness's pane and not its wisps, and it files nothing, so no order or
doctor check here reports a witness whose patrol has stopped advancing. The rule
against consent UI from a heartbeat agent is
`template-fragments/heartbeat-no-consent-ui.template.md`.

## What gives a patrol its next cycle

Gas City ships one continuation for a named session in mode `always`, which both
patrols are, and what it ships nearby leaves the rest to the pack:

- Gas City restarts a `wake_mode = "fresh"` session whose assigned bead has
  changed, on a new conversation. Once the next wisp is assigned and the current
  one is gone, that restart needs nothing more from the model. It is held off
  while the bead the session last recorded is still open and assigned to it, so a
  session whose turn ended partway through a cycle is not restarted. On the legacy
  reconciler it is also held off while the session holds any in-progress claim, so
  neither is a session that marked its next wisp in progress.
- Gas City exempts such a session from `idle_timeout` and `max_session_age`, so
  the `idle_timeout` in each `agent.toml` never stops it, and an idle patrol
  session stays up with nothing to do.
- A configured nudge arrives at most once per session, near its start.
- The `[session]` stall timeouts restart an idle session on the legacy reconciler
  only. They are city-wide, and no pack can set them. The v2 work ladder that
  replaces them paces pool seats, and a patrol session is not one.

So a witness that reaches `next-iteration` continues without further help. The
deacon's formula and prompt tell it to keep cycling, and the model still ends its
turn after a cycle summary or after a failure partway through a cycle, and a
witness can stop short of its last step the same way. A remedy that depends on an
agent following an instruction fails at exactly the moment it is needed, so for
those shapes the pack composes one from outside the model's decision: a `Stop` hook
for the deacon, and a nudge from an order for the witness.
[The Gas City search](../specs/tk-r4c0g67/gas-city-search.md) records what was read,
how the candidates compare, and the measurements behind the numbers below.

## How the witness ends a pass

`next-iteration` runs in this order, and the order is the design:

1. **It waits `event_timeout` (600s).** A wait after the pour never holds: a session
   with its next wisp assigned and its current one burned is restarted about 40
   seconds into that wait. While the session holds its current wisp in progress the
   restart holds off, so a wait before the pour runs to its end. Gas Town's step has
   no wait, because it credits an idle policy that Gas City refuses on an always-on
   session, so nothing there spaces its passes.
2. **It pours and assigns the next wisp and burns the current one.** A guard that
   fires leaves the current wisp in place and ends the turn, and the order gives that
   session its next try.
3. **It writes `IDLE: no work, exiting turn.` and stops.** The restart comes about a
   minute later.

The session never marks its next wisp in progress or works it in the same
conversation, because a session holding in-progress work gets no restart. The
startup adopt marks a wisp in progress because there a fresh session is taking its
own wisp.

A pass takes about a minute, so the passes run about twelve minutes apart. A rig's
witness then costs about 120 sessions a day, each a short conversation.

## The witness's order

The order is the backstop for a session the restart does not reach.
`orders/witness-nudge.toml` runs `assets/scripts/witness-nudge.sh` every 5m,
city-wide. The script reads the session list once. It nudges each witness that
is `active`, has nobody attached, and whose pane has printed nothing and taken
no nudge for 660s. A nudge is its only action: it resets no session, reads no
bead, keeps no state and files nothing.

- **What counts as quiet.** `last_active` is the last time tmux saw the pane move,
  by its output or by the echo of anything typed into it. A working pane animates a
  spinner, so a witness in a long tool call or its inter-cycle wait reads as busy,
  and it is left alone. The bound sits over the formula's 600s `event_timeout`, so
  a witness that moved that wait to the background is not nudged out of it, and the
  script's suite fails when the default drops to it. A pane that has written the
  idle line is restarted well inside the bound. A pane that takes a nudge and
  does nothing gets another one after the bound, not one per pass, because
  `last_nudge_delivered_at` counts as well.
- **The pace.** A witness that reaches `next-iteration` is never nudged. One that
  stops short waits out the bound and the next pass, which is up to about 16 minutes
  at the declared interval, and then takes one pass, which ends at `next-iteration`
  like any other.
- **An attached operator.** A session with a client attached is skipped, because
  the person at the pane can prompt it. The next pass after they leave counts the
  same quiet clock.
- **An outage.** When the session list cannot be read, the pass exits 1 and nudges
  nothing, and the next pass tries again. A witness spends nothing while the store
  is down, and its patrol resumes on the first pass after the store returns. When
  the session list still answers and only the witness's own store is down, the
  nudge goes out and buys a short failing pass, at the order's pace.
- **Delivery.** The nudge goes with `--delivery immediate`, because the default
  `wait-idle` queues what it cannot deliver now, a queued nudge stamps no delivery,
  and each later pass would stack another on top of it. The pane is quiet, so
  nothing is typed into a running turn. A turn that starts in the moment between
  the read and the nudge takes the text as its next prompt. A session waiting on a
  permission prompt refuses the nudge, so nothing piles up behind it, and the pass
  exits 1 until the prompt is answered. A Gas City build that reads an
  `AskUserQuestion` dialog refuses there too. On one that does not, the nudge's
  Enter selects the dialog's focused option, and the witness's prompt forbids that
  dialog.

## What the deacon's hook does

At the end of every turn the hook, in order:

1. **Self-gates to the deacon.** It derives the role from the trailing
   component of `GC_AGENT`. The witness and the refinery carry the same
   overlay, and for them the hook does nothing.
2. **Reads the turn from the hook payload:** the conversation's
   `session_id` and its `background_tasks`.
3. **Leaves a turn with a running background task alone.** The task's
   completion notification starts the next turn, and a hand-back now would
   race the wait the task serves, such as an inter-cycle wait the deacon
   moved to the background.
4. **Counts the stop against the last hand-back** (the loop guard, below).
5. **Hands the next cycle back** by printing
   `{"decision": "block", "reason": "<instruction>"}` on stdout. Claude Code
   feeds the reason to the model as Stop hook feedback and the turn goes on.
   The instruction is to adopt the wisp next-iteration poured through the
   startup reconcile and work `mol-deacon-patrol` from check-inbox, or to
   finish the current cycle when next-iteration has not run.

A payload with no session id, or with a task list that is not a list, lets
the turn end, since nothing is known about the turn.

## The loop guard

A real cycle spends the formula's `event_timeout` (600s) in its inter-cycle
wait. A stop that comes within 300s of a hand-back is a rapid stop: that turn
ran no cycle. The hook counts rapid stops in a row, per conversation, in one
state file per session bead under `$TMPDIR`. A stop after a longer turn
clears the count, and a new conversation starts it over. The 300s bound has
to stay under every `event_timeout` the deacon is poured with, or each real
cycle would count as a rapid stop, so the hook's suite fails when the
formula default or the startup pour drops to it.

After three rapid stops in a row the hook stops handing back. Another
hand-back would only loop, so it resets the session instead
(`gc session reset`, by the session's alias or id). The fresh conversation
starts from the deacon's prompt, and its startup reconcile adopts the wisp
the patrol left. A reset that fails lets the turn end, and boot-health is
then what reports the cold deacon.

The reset waits while an operator is attached to the deacon's pane, because
it would end the conversation under them. An attachment the hook cannot read
counts as one, as it does for the context recycle. The turn ends and the
count stands, so the deacon takes the operator's next prompt, and the next
rapid stop with nobody attached takes the reset. A deacon the operator
leaves without a prompt stays idle, and boot-health reports it cold.

The reset also waits for its `recovery` line in the incident ledger. The
deacon's prompt reads the ledger before it patrols, in place of the
transcript the reset ends, so the hook writes the line first and resets only
once the append succeeds. When the ledger script is missing or the append
fails, the turn ends and the count stands, so the next rapid stop tries the
line again. The deacon is then idle until something prompts it, and
boot-health reports it cold.

Claude Code has its own bound: it overrides a hook that blocks the turn from
ending nine times in a row with no tool call in between, and ends the turn.
A cycle runs tools, so the bound never meets a working patrol. The guard
acts first, so a looping conversation is replaced rather than left to end
idle.

## With cycle-recycle

Both hooks run on the same `Stop` event. When cycle-recycle recycles, past
the context threshold or on a pack change, it writes its handoff and resets
the session, which ends the conversation even though the hand-back continued
the turn, and the next session's startup reconcile adopts the wisp. When it
has nothing to recycle, and whenever it defers, the hand-back keeps the patrol
going, so a deferred recycle reaches its next turn boundary.

## The city store

The deacon's wisps live in the city store, and its shell keeps the
directory it last changed to. A `gc bd list` or `gc bd mol wisp` with no
bead id answers from the store that directory selects, so from a rig
checkout the reconcile would find no wisp and pour one into the rig's store,
where no later reconcile looks. Every wisp query and pour in the prompt and
the formula names the city store with `--city="$GC_CITY_PATH"`.
`assets/scripts/patrol-wisp-reconcile.test.sh` runs them from a directory
whose store differs.

## Invariants

- **Always exit 0.** A block rides the JSON decision, never the exit code, so
  a hook that fails lets the turn end instead of wedging it.
- **stdout carries the decision and nothing else.** Diagnostics go to stderr.
- **Never prompt the operator** (`heartbeat-no-consent-ui`).
- **A hand-back reads no store.** The payload and the state file decide it,
  so the common path costs one `jq` read and one small file write.

`assets/scripts/patrol-continue-hook.test.sh` runs the shipped hook against
each of these paths, and `assets/scripts/witness-nudge.test.sh` runs the order's
script and pins its wiring.
