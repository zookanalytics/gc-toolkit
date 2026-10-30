---
name: Patrol continue
description: How the deacon and the witness keep patrolling after a turn ends — the Stop hook that hands the next cycle back, when it lets a turn end, its loop guard, and why neither patrol waits on a controller restart. Read it when a patrol session idles between cycles or before changing its Stop hooks.
---

# Patrol continue

The deacon's patrol is a loop of `mol-deacon-patrol` wisps and the witness's
is a loop of `mol-witness-patrol` wisps, one cycle each. Each loop lives in
its session's conversation: next-iteration pours the next wisp and the session
goes on to it. The model ends its turn after a cycle anyway, so a `Stop` hook
hands the next cycle back at every turn boundary.

The implementation is
`overlays/cycle-recycle/.claude/hooks/patrol-continue.sh`, staged into the
deacon's and each witness's work dir by the `overlay_dir =
"overlays/cycle-recycle"` patches in `pack.toml`, beside the cycle-recycle
hook. This document is the policy behind it.

## Scope

**Mandate.** Whether the deacon's and the witness's patrols continue after a
turn ends: what hands the next cycle back, when a turn is allowed to end, the
loop guard and its recovery, and how this hook and the context recycle share a
turn boundary.

**Boundaries.** The context recycle, which ends a patrol session's
conversation past its threshold, is [cycle-recycle.md](cycle-recycle.md).
What a cycle does is `formulas/mol-deacon-patrol.toml` and
`formulas/mol-witness-patrol.toml`, and how a session adopts its wisp is the
startup reconcile in `agents/deacon/prompt.template.md` and
`agents/witness/prompt.template.md`. Detecting a deacon that has gone cold is
the `boot-health` order's (`orders/boot-health.toml`). No order or doctor
check watches whether a witness's patrol is advancing. The rule against
consent UI from a heartbeat agent is
`template-fragments/heartbeat-no-consent-ui.template.md`.

## Why a hook

Nothing outside the conversation gives an ended turn another one:

- The deacon and the witness are named sessions in mode `always`. Gas City
  exempts such a session from `idle_timeout`, so the `idle_timeout` in each
  one's `agent.toml` never stops it, and an idle patrol session stays up with
  nothing to do.
- Its configured nudge arrives at most once per session, when the first turn
  ends.
- Gas City restarts a `wake_mode = "fresh"` session whose assigned bead has
  changed, so a new wisp assigned to a patrol session can restart it. That
  restart serves a reassignment, and it is held off while the session holds
  any in-progress claim, or while the bead it last recorded is still open and
  assigned to it. A session that adopted its next wisp before ending its turn
  is never restarted. Neither is one whose turn ended partway through a cycle,
  since it still holds that cycle's wisp. Neither patrol relies on the
  restart.

The patrol formulas and the prompts tell each session to keep cycling, and
the model still ends its turn after a cycle summary, or after a failure
partway through a cycle. A remedy that depends on an agent following an
instruction fails at exactly the moment it is needed. The harness runs a
`Stop` hook at every turn end whatever the model's state, so the hand-back
runs there.

## What it does

At the end of every turn the hook, in order:

1. **Self-gates to the deacon and the witness.** It derives the role from the
   trailing component of `GC_AGENT`. The refinery carries the same overlay
   and ends its turn when it runs out of work, so for it the hook does
   nothing.
2. **Reads the turn from the hook payload:** the conversation's
   `session_id` and its `background_tasks`.
3. **Leaves a turn with a running background task alone.** The task's
   completion notification starts the next turn, and a hand-back now would
   race the wait the task serves, such as an inter-cycle wait the session
   moved to the background.
4. **Counts the stop against the last hand-back** (the loop guard, below).
5. **Hands the next cycle back** by printing
   `{"decision": "block", "reason": "<instruction>"}` on stdout. Claude Code
   feeds the reason to the model as Stop hook feedback and the turn goes on.
   The instruction is to finish next-iteration's inter-cycle wait if the
   session skipped it, then adopt the wisp next-iteration poured through the
   startup reconcile and work the role's patrol formula (`mol-deacon-patrol`
   or `mol-witness-patrol`) from check-inbox. When next-iteration has not
   run, the instruction is to finish the current cycle. The wait is named
   because a session that skipped it would otherwise go straight on to the
   next cycle, and the patrol would run at the model's pace instead of the
   formula's.

A payload with no session id, or with a task list that is not a list, lets
the turn end, since nothing is known about the turn.

## The loop guard

A real cycle spends the formula's `event_timeout` (600s) in its inter-cycle
wait. A stop that comes within 300s of a hand-back is a rapid stop: that turn
did not run a full cycle and its wait. The hand-back after a rapid stop says
so and asks for whichever of the two has not run. The hook counts rapid stops
in a row, per conversation, in one state file per session bead under
`$TMPDIR`. A stop after a longer turn clears the count, and a new conversation
starts it over. The 300s bound has
to stay under every `event_timeout` the deacon and the witness are poured
with, or each real cycle would count as a rapid stop. So the hook's suite
fails when either formula's default or the deacon's startup pour drops to it,
and when a witness pour starts passing an `event_timeout` of its own.

After three rapid stops in a row the hook stops handing back. Another
hand-back would only loop, so it resets the session instead
(`gc session reset`, by the session's alias or id). The fresh conversation
starts from the role's prompt, and its startup reconcile adopts the wisp the
patrol left. A reset that fails lets the turn end. boot-health then reports
the cold deacon, and a witness stays idle until something prompts it.

The reset waits while an operator is attached to the session's pane, because
it would end the conversation under them. An attachment the hook cannot read
counts as one, as it does for the context recycle. The turn ends and the
count stands, so the session takes the operator's next prompt, and the next
rapid stop with nobody attached takes the reset. A patrol session the
operator leaves without a prompt stays idle. boot-health reports a deacon left
that way cold, and nothing reports a witness.

The deacon's reset also waits for its `recovery` line in the incident ledger.
The deacon's prompt reads the ledger before it patrols, in place of the
transcript the reset ends, so the hook writes the line first and resets only
once the append succeeds. When the ledger script is missing or the append
fails, the turn ends and the count stands, so the next rapid stop tries the
line again. The deacon is then idle until something prompts it, and
boot-health reports it cold. The witness's prompt reads no ledger, so its
reset writes no line and waits for none.

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

## The deacon's city store

The deacon's wisps live in the city store, and its shell keeps the
directory it last changed to. A `gc bd list` or `gc bd mol wisp` with no
bead id answers from the store that directory selects, so from a rig
checkout the reconcile would find no wisp and pour one into the rig's store,
where no later reconcile looks. Every wisp query and pour in the deacon's
prompt and formula names the city store with `--city="$GC_CITY_PATH"`.
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
