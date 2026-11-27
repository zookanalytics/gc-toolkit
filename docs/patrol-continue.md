---
name: Patrol continue
description: Read it when the deacon's patrol idles between cycles, or before changing the deacon's Stop hooks. Covers what gives the deacon its next cycle after a turn ends, when the hook lets a turn end, and its loop guard.
---

# Patrol continue

The deacon's patrol is a loop of `mol-deacon-patrol` wisps, one cycle each, and
the loop lives in its conversation. Its next-iteration pours the next wisp and
the session goes on to it. The model ends its turn after a cycle anyway, which
leaves the session idle at its prompt, so a `Stop` hook hands it the next cycle
at every turn boundary. The implementation is
`overlays/cycle-recycle/.claude/hooks/patrol-continue.sh`, staged into the
deacon's work dir by the `overlay_dir = "overlays/cycle-recycle"` patch in
`pack.toml`, beside the cycle-recycle hook.

This document is the policy behind it.

## Scope

**Mandate.** Whether the deacon's patrol continues after a turn ends: what
gives it its next cycle, when the hook lets a turn end, its loop guard and
recovery, and how the hook and the context recycle share a turn boundary.

**Boundaries.** The context recycle, which ends a patrol session's
conversation past its threshold, is [cycle-recycle.md](cycle-recycle.md).
What a cycle does is `formulas/mol-deacon-patrol.toml`, and how a session
adopts its wisp is the startup reconcile in `agents/deacon/prompt.template.md`.
Detecting a deacon that has gone cold is the `boot-health` order's
(`orders/boot-health.toml`). The rule
against consent UI from a heartbeat agent is
`template-fragments/heartbeat-no-consent-ui.template.md`.

## What gives a patrol its next cycle

Gas City ships one continuation for a named session in mode `always`, which the
deacon is, and what it ships nearby leaves the rest to the pack:

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

The deacon's formula and prompt tell it to keep cycling, and the model still
ends its turn after a cycle summary or after a failure partway through a cycle. A
remedy that depends on an agent following an instruction fails at exactly the
moment it is needed, so the pack composes one from outside the model's decision:
a `Stop` hook.
[The Gas City search](../specs/tk-r4c0g67/gas-city-search.md) records what was read,
how the candidates compare, and the measurements behind the numbers below.

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
each of these paths.
