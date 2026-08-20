---
name: Teardown input loss — determination for tk-tufrw
description: What actually tore down the converse pane that ate an operator's unsubmitted paragraph on 2026-08-20, which hypotheses the evidence rules out, and why the durable capture cannot be built in this pack.
---

# Session teardown destroys unsubmitted operator input — determination

Bead: `tk-tufrw`. Subject of the lost reply: `tk-gy1ws`.

`tk-tufrw` asks for the trigger to be established *before* a fix is
designed. This document records what fired, with the evidence, and the
ownership split that follows from it.

**The requirement is binding and it is a prohibition** (operator,
2026-08-20T22:21Z): *"draining a session with typed text should be a hard
no."* Tearing down a session that holds unsubmitted operator input is
forbidden — pending input is a hard blocker on teardown, the way an
uncommitted working tree blocks a destructive git operation. Capture and
warning are worth having *in addition*, as the fallback for a teardown
that happens anyway. They are explicitly **not** the fix; an earlier
draft of the bead ranked capture-before-kill first and the operator
overrode it. Everything below is written against the prohibition.

## Verdict

The pane was destroyed by a **reconciler-initiated `no-wake-reason`
drain** of the converse session — the path that stops a session the
controller can find no reason to keep awake. No hypothesis the bead names
fired:

- **Not the idle timer.** `agents/converse/agent.toml` sets
  `idle_timeout = "8h"`. The session was 64 minutes old when it died.
- **Not a witness or liveness sweep.** No sweep touched it; the stop
  came from the session reconciler's own drain scan, and the recorded
  stop reason is a drain, not a reap.
- **Not `restart_window`, and not any one-hour timer.** The bead flags
  `city.toml:214` `restart_window = "1h"` as an unconfirmed candidate.
  It is refuted. `RestartWindow` is the *sliding window over which
  restarts are counted* for crash-loop quarantine —
  `internal/config/config.go`: "the maximum number of agent restarts
  within RestartWindow before the agent is quarantined" — consumed by
  `newCrashTracker` (`cmd/gc/city_runtime.go:331`,
  `cmd/gc/crash_tracker.go:44`). It starts no timer and stops nothing;
  reaching one hour is not an event in it. The ~57-minute arithmetic is
  a coincidence, and the real interval has a different explanation
  (below).

The operator's words were destroyed by **one act, the kill**, and the
drain reaches the pane in no other way. The path, end to end:

1. **The drain is recorded, and nothing is sent.**
   `beginSessionDrainInfo` (`cmd/gc/session_wake.go:160-205`) takes a
   `runtime.Provider` and ignores it — the parameter is literally
   `_ runtime.Provider`, "kept for caller compatibility". It writes an
   in-memory `drainState` and returns.
2. **One tick later the reconciler acks on the agent's behalf.** If
   nothing cancelled in between, `advanceSessionDrainsWithSessionsTraced`
   sets `GC_DRAIN_ACK=1` (`cmd/gc/session_wake.go:606-645`). Its own
   comment states the mechanism: the Phase 1 drain-ack check "sees it on
   the next tick and calls `sp.Stop()` for a clean SIGTERM/SIGKILL — no
   Ctrl-C keystroke injection into the pane."
3. **The kill.** Phase 1 marks the session stop-pending and queues
   `queueDrainAckAsyncStop` (`cmd/gc/session_reconciler.go:291+`) →
   `workerKillSessionTargetWithConfig` → `Provider.Stop` →
   `KillSessionWithProcessesExcluding`
   (`internal/runtime/tmux/tmux.go:880+`): SIGTERM to the pane's whole
   process tree deepest-first with a grace window, SIGKILL for
   survivors, then `tmux kill-session`. That frees the pane and its
   history; `wake_mode = "fresh"` means the respawn shares nothing with
   it.

**Nothing types into the pane.** `Provider.Interrupt` → `SendKeysRaw(name,
"C-c")` (`internal/runtime/tmux/adapter.go:268-287`) is a real API and it
is not on this path: the drain code's own wrapper, `verifiedInterrupt`
(`cmd/gc/session_wake.go:723-737`), has no caller anywhere outside
`session_wake_test.go`. An earlier draft of this determination said the
drain's first act was a `C-c` into the composer. It is not, and the
correction matters in the operator's favour — **the draft was still
there, whole, for the entire window**, and every second of it was time in
which something could have saved the text. This is exactly "teardown
raced a typist", and teardown won by taking the terminal out from under
them.

## Evidence

Session `lx-3r9dc`, template `gc-toolkit/gc-toolkit.converse`, tmux
session `gc-toolkit__converse-lx-3r9dc`.

| time (2026-08-20 UTC) | fact | source |
|---|---|---|
| 20:59:33 | operator files `tk-gy1ws` | bead |
| 20:59:47 | `session.woke` for `gc-toolkit/gc-toolkit.converse-2` | `gc events` |
| 21:05:10 | last tool call of the session: the takeaway/close block | transcript `cfd57ee4-…jsonl` |
| 21:05:12 | `gc.takeaway` stamped on `tk-gy1ws`; the visit closes | bead |
| 21:05:45 | last assistant turn — a framing that invites a reply | transcript |
| 22:02:15 | `tk-lrylu` closes — the last open converse-pool visit, on an unrelated subject | bead |
| 22:03:13 | reconciler tick observes the session: `state: awake` | reconciler trace `segments/2026/08/20/segment-000010.jsonl` |
| 22:03:17 | same tick's result: `state: draining` | same |
| ~22:04 | operator is mid-compose; pane disappears | operator report |
| 22:04:15 | `session.stopped`, `reason: "drain acknowledged"` | `gc events` |

Two facts pin the mechanism:

- **The agent never drained itself.** The converse prompt's step 8 ends
  a session with `gc runtime drain-ack`. The transcript's last tool call
  is at 21:05:10 and is the takeaway block; `drain-ack` appears in the
  file only as prompt text. Nothing the agent ran caused this stop.
- **`"drain acknowledged by agent"` is a misnomer on this path.** The
  reconciler acks on the agent's behalf: `setReconcilerDrainAckMetadata`
  writes `GC_DRAIN_ACK=1` with `GC_DRAIN_ACK_SOURCE=reconciler`
  (`cmd/gc/session_wake.go:216-245`), and
  `finalizeDrainAckStoppedSession` emits the same event text either way
  (`cmd/gc/session_reconciler.go:544`). Reading that event as "the agent
  chose to exit" is exactly the wrong conclusion, and it is the reading
  the string invites.

The session id is not guesswork: `lx-3r9dc` appears 11 times inside the
lost transcript, and it is the id carried in the 22:04:15 stop payload.

## The window, and why nothing closed it

`beginSessionDrainInfo` (`cmd/gc/session_wake.go:160-205`) deliberately
defers the drain signal by one full reconciler tick so a falsely-orphaned
session gets a chance to be cancelled — and the ack it eventually writes
is consumed by a *later* tick still, so the kill is two tick boundaries
away from the decision. Measured here: drain began in the 22:03:13 tick,
stop recorded at 22:04:15 — a **~58-second** window between the decision
and the kill, with the operator's unsent paragraph sitting untouched in
the pane for all of it.

### What was keeping the pane alive — and it was not the operator

The hour is not a timer. The converse pool is demand-driven
(`min_active_sessions = 0`), so a live converse session survives only
while the pool has demand, and the demand is open visit beads.

`tk-lrylu` — *"visit: tk-yps55 — operator-origin topic intake"*, an
**unrelated** subject — was open across the whole gap and closed at
**22:02:15Z**. It was the last open converse-pool visit. The drain began
in the reconciler tick at **22:03:13Z**, 58 seconds later. The operator's
own visit (`tk-2jyqb`, on `tk-gy1ws`) had closed at 21:05, an hour
earlier.

So the pane the operator was composing in stayed alive for that hour as a
**side effect of somebody else's conversation being open**, and died
within a minute of that unrelated visit closing. Nothing about the
operator — not their presence, not their attention, not the paragraph
they were typing — was an input to the decision at any point.

(Stated as mechanism-fit plus correlation, not as a traced decision: the
reconciler's baseline trace records carry `state` and `sleep_reason` only,
not the wake-reason set. The falsifiable prediction is that a converse
session outlives its own visit exactly until the pool's last open visit
closes.)

### Attachment is not a usable proxy either

Attachment *is* a wake cause — `input.Runtime.Attached` →
`WakeCauseAttached` (`internal/session/lifecycle_projection.go:834-836`)
— so an *attached* pane does not enter this drain. It is far too fragile
to be the protection: this city runs **one tmux client** for everything
(`tmux list-clients` → a single `/dev/pts/*` entry), switched between
per-agent sessions. At most one session reports `session_attached=1` at
any instant, so glancing at any other pane makes the pane you were
typing in eligible for the drain on the next tick.

The operator confirms the pane was responsive — cursor and characters
behaving normally — right up until it vanished. This was not a stale pane
swallowing keystrokes: teardown raced live composition and won.

Once the drain has begun the protection thins out along the window, and
it is worth being exact about where:

- **Before the ack.** The advance scan
  (`advanceSessionDrainsWithSessionsTraced`,
  `cmd/gc/session_wake.go:493+`) has named cancels for `WakePending` and
  `assigned-work`, and above the ack it also cancels generically:
  `no-wake-reason` satisfies `drainReasonCancelable`, so *any* wake
  reason that reappears — attachment included — clears `GC_DRAIN_ACK`
  and drops the drain (`cmd/gc/session_wake.go:587-604`). Re-attaching
  this early does save the session.
- **After the ack.** The stop is decided by the Phase 1 drain-ack
  consumer (`cmd/gc/session_reconciler.go:1966-2032` and `2320-2440`),
  which runs *before* that tick's `ComputeAwakeSet`. Its cancels are
  assigned work, a *structured* pending interaction
  (`pendingInteractionKeepsAwakeInfo` — a prompt the agent is blocked
  on, which a half-typed reply is not), and a config-drift-plus-
  recently-attached special case. Plain attachment on a
  `no-wake-reason` ack is not among them, so attaching here does not
  call the kill off.

**Neither rung ever looks at what is typed.** Attachment is the closest
thing to a proxy for "a human is here", and it is a proxy for presence,
not for pending work — a pane can be attached with an empty composer and
unattached with a full one. Nothing on this path reads the pane's
contents at any point, which is why the guard has to be an explicit
input-state check rather than a stricter reading of attachment.

## Why none of this can be built in this pack

Both halves are upstream. The **block** is a reconciler decision, and the
reconciler is the `gc` binary. The **capture** runs into the seam
`docs/gascity-human-engagement.md` → "How a held sitting ends" already
records for the idle reap: **nothing pack-owned runs at kill time.** This
determination extends that finding rather than re-deriving it, and the
same seam holds for the drain path: the kill is issued by the reconciler
against the pane's own process tree, and the pack owns nothing between
that decision and those signals.

Ruled out explicitly, so nobody re-derives them:

- **A tmux hook.** `session-closed` / `pane-exited` fire *after* the
  pane is gone, so there is nothing left to capture. There is no hook on
  the kill itself.
- **A Claude Code `SessionEnd` hook.** It receives session id,
  transcript path, cwd and reason — never the unsent composer buffer —
  and it is racing a SIGTERM with a bounded grace window followed by
  SIGKILL, so it is not guaranteed to run to completion either.
- **A cooldown order polling for draining sessions.** Cooldown orders
  fire on a multi-minute cadence against a ~58-second window, so the
  poll would usually arrive after the kill.
- **`pipe-pane` logging.** It would capture the draft, but a TUI redraws
  continuously; the volume makes it unusable as an always-on capture.

What remains is the drain path itself, which is `gc` binary territory
(`rigs/gascity`). Filed there as **`gc-ze774`**.

That filing is not starting from nothing. gascity already has the
enabling primitive specced and partly built: **`gc-8g41r`**,
"Library-level buffered-input detection (ghost-text aware)", whose
stage-1 spec (`input-area-state.md`, merged 2026-05-10) defines an
`InputAreaState` API over `tmux capture-pane` with per-LLM input shapes
and ghost-text discrimination, plus a `gc session input-area` surface.
Stages 2-6 are pending behind an operator-gated integration branch. A
drain that consults input state is a natural first consumer of it, and
`tk-ko68z` is the gc-toolkit-side follow-up already waiting on the same
convoy.

## Design constraints the evidence imposes

Any fix upstream has to satisfy all five, or it will not have fixed this
incident:

1. **Pending input blocks the drain outright.** This is the requirement,
   not a mitigation. A session holding unsubmitted operator input is not
   drainable; the reconciler must treat it the way it already treats a
   `user_hold` heartbeat — a condition that cancels the drain rather than
   one that decorates it.
2. **The check must survive the whole window, not just the decision.**
   `beginSessionDrainInfo` defers the drain signal by a tick, the ack is
   consumed a tick after that, and the kill landed ~58s after the
   decision — so a human who starts typing *after* the drain began must
   still stop it. One guard is not enough to cover that: it belongs in
   `advanceSessionDrainsWithSessionsTraced` alongside the existing
   `WakePending` / `assigned-work` cancels **and** in the Phase 1
   drain-ack consumer, which today cancels for assigned work alone and
   is the rung that actually issues the stop.
3. **Do not rely on attachment as the proxy.** One client for the whole
   city means the pane being typed into routinely reads as unattached.
   Input state has to be read from the pane itself.
4. **Fallback only: capture before the kill.** Where a drain genuinely
   cannot be blocked (`orphaned`, `suspended`), capture first. The kill
   is the sole destructor — nothing disturbs the pane before it — so a
   capture anywhere upstream of `queueDrainAckAsyncStop` still sees the
   composer intact, and the ack-set tick is the natural site: it is a
   full tick of headroom, and it already knows the session is going.
   Park what it captures where the operator will look; for a converse
   sitting that is the subject bead.
5. **Fix the stop reason's wording.** `"drain acknowledged by agent"`
   for a reconciler-authored ack sent this investigation looking for an
   agent decision that never happened.

## Companion, not a substitute

Typing a bare bead id into `prefix + a` already reopens a conversation on
that subject; it is merely undiscoverable. That returns the operator to
the *subject*. It does not return their *words*, and `tk-tufrw` is
explicit that it does not close the bead.

*Citation corrected:* the bead points at
`assets/scripts/tmux-visit-prompt.sh:130-137`, which today is the
dependency precheck, not this affordance. The pass-through decision is
documented at `tmux-visit-prompt.sh:207-212` — the topic is deliberately
**not** forced with `--topic` — and the resolution itself lives in
`assets/scripts/gc-visit-open.sh:145-158`, which disambiguates by rig
prefix rather than by shape.
