---
name: Teardown input loss — determination for tk-tufrw
description: What actually tore down the converse pane that ate an operator's unsubmitted paragraph on 2026-08-20, which hypotheses the evidence rules out, and why the durable capture cannot be built in this pack.
---

# Session teardown destroys unsubmitted operator input — determination

Bead: `tk-tufrw`. Subject of the lost reply: `tk-gy1ws`.

`tk-tufrw` asks for the trigger to be established *before* a fix is
designed, and names three candidates: an idle timer, a periodic
witness/liveness sweep, or something else. It is the third. This
document records what fired, with the evidence, and the ownership split
that follows from it.

## Verdict

The pane was destroyed by a **reconciler-initiated `no-wake-reason`
drain** of the converse session — the path that stops a session the
controller can find no reason to keep awake. Neither named hypothesis
fired:

- **Not the idle timer.** `agents/converse/agent.toml` sets
  `idle_timeout = "8h"`. The session was 64 minutes old when it died.
- **Not a witness or liveness sweep.** No sweep touched it; the stop
  came from the session reconciler's own drain scan, and the recorded
  stop reason is a drain, not a reap.

The operator's words were destroyed **twice over, by two separate
actions**, and the first one is not the kill:

1. **A `C-c` typed into their terminal.** A drain's first act is
   `runtime.Provider.Interrupt`, which for tmux is
   `SendKeysRaw(name, "C-c")` (`internal/runtime/tmux/adapter.go:270-282`).
   That keystroke lands in whatever is focused in the pane — here, a
   composer holding an unsent paragraph.
2. **The kill.** `workerKillSessionTargetWithConfig` →
   `KillSessionWithProcesses`, which frees the pane and its history.
   `wake_mode = "fresh"` means the respawn shares nothing with it.

So this is not only "teardown raced a typist". The runtime **injected a
cancel keystroke into a terminal a human was composing in**, roughly a
minute before taking the pane away.

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
defers the interrupt by one full reconciler tick so a falsely-orphaned
session gets a chance to be cancelled. Measured here: drain began in the
22:03:13 tick, stop recorded at 22:04:15 — a **~58-second** window
between the decision and the kill, with the `C-c` somewhere inside it.

Attachment is a wake cause — `input.Runtime.Attached` →
`WakeCauseAttached` (`internal/session/lifecycle_projection.go:834-836`)
— so an *attached* pane does not enter this drain at all. That defence
did not apply, and the city's tmux layout explains why it is thin: there
is **one tmux client** for the whole city (`tmux list-clients` →
a single `/dev/pts/*` entry), switched between per-agent sessions, so at
most one agent session reports `session_attached=1` at any instant and
every other live pane the operator moves between reads as unattached.

Once the drain has begun, the advance scan
(`advanceSessionDrainsWithSessionsTraced`,
`cmd/gc/session_wake.go:493+`) cancels only for `WakePending` and
`assigned-work` wake reasons. **It has no attachment check and no
pending-input check.** A human who attaches and starts typing at second
5 of the window is not a cancel condition on that path.

And the cancel that does exist could not have saved the text anyway: the
`C-c` is sent to the pane, so by the time any later tick reconsiders,
the composer has already been cleared.

## Why the capture cannot be built in this pack

`docs/gascity-human-engagement.md` → "How a held sitting ends" already
records the seam, established for the idle reap: **nothing pack-owned
runs at kill time.** This determination extends that finding rather than
re-deriving it, and the same seam holds for the drain path — with the
additional point that the destructive act here is a keystroke sent
*into* the pane, which no pack-side hook can intercept either.

Ruled out explicitly, so nobody re-derives them:

- **A tmux hook.** `session-closed` / `pane-exited` fire *after* the
  pane is gone, so there is nothing left to capture. No tmux hook fires
  on an inbound `send-keys`.
- **A Claude Code `SessionEnd` hook.** It receives session id,
  transcript path, cwd and reason — never the unsent composer buffer —
  and would run after the `C-c` had already cleared it.
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

Any fix upstream has to satisfy all four, or it will not have fixed this
incident:

1. **Capture before the interrupt, not before the kill.** The `C-c` is
   the first destructor. A capture placed at the kill site captures an
   already-cleared composer.
2. **Do not rely on attachment.** One client for the whole city means an
   actively-used pane routinely reads as unattached.
3. **Park it where the operator will look.** For a converse sitting that
   is the subject bead — the thing they were writing about.
4. **Fix the stop reason's wording.** `"drain acknowledged by agent"`
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
