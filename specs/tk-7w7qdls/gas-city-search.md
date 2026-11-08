---
name: Gas City search for how a converse sitting ends
description: The search the arch check asks for behind tk-7w7qdls. What Gas City ships for stopping a manual session that holds no work, closing a stopped one, and showing a session's tab as done, read at upstream 9f807760c and re-read at the deployed fork build cb80c5354, and why the change composes sleep_after_idle and drain-ack and sets the done mark with tmux itself. Read it when checking whether the converse ending can move further onto Gas City.
---

# Gas City search for how a converse sitting ends

This change ends a converse sitting on Gas City's own features. Each
`converse-<model>` template gains `sleep_after_idle = "10m"`, the pack's
`converse-reap` order and script go, and the sign-off's drain block and
`gc-helm dismiss` mark the operator's tab done before their
`gc runtime drain-ack`. The facts below were read at upstream
`gastownhall/gascity` `9f807760c` (main on 2026-11-05) and again at `cb80c5354`,
the fork build the city runs, whose merge-base is `9f807760c`. The fork changes
four of the files named below, and none where a cited symbol sits:
`cmd/gc/session_reconciler.go` inside the legacy reconciler's tick,
`cmd/gc/cmd_start.go` outside `buildFingerprintExtra`,
`internal/session/manager.go` in one `Info` field, and
`internal/config/validate_semantics.go` in the source label of its warnings.
The probe that ran them is
[idle-sleep-probe.md](idle-sleep-probe.md).

## Stopping a sitting that holds no conversation: `sleep_after_idle`, composed

The need is a backstop that stops a sitting once it holds no open conversation
and nobody is watching it, and never while it holds one or is watched. Gas City
ships it as the agent's `sleep_after_idle`.

- `ResolveSessionSleepPolicy` (`internal/config/session_sleep.go`) resolves the
  agent's `sleep_after_idle` first, then a rig's or the workspace's
  `[session_sleep]` default for the agent's class. `ClassifySessionSleepAgent`
  puts a template with `attach = true` and `wake_mode = "resume"` in the
  interactive-resume class.
- The awake set's idle-sleep block (`ComputeAwakeSet`,
  `cmd/gc/compute_awake_set.go`) takes a manual session's idle time from
  `[chat_sessions] idle_timeout` when that is set, and otherwise from its
  agent's `SleepAfterIdle`. It exempts an attached session, claimed
  `in_progress` work (`holdsClaimedWork`), assigned-work demand, and a manual
  session inside its grace (`inManualGracePeriod`). Its clock is
  `detached_at`, which `armDetachedAt` (`cmd/gc/reconcile_arms_heals.go`)
  stamps on a live, unattached row and clears while a client is attached.
- The v2 allocator then applies the sleep policy itself
  (`configSleepSuppressed`, `cmd/gc/allocator_decide.go`), from the later of
  `detached_at` and the last terminal output, and keeps a session awake only
  for what `wakeDemandOverridesSleepSuppression`
  (`cmd/gc/session_reconciler.go`) lets outrank the policy: an attached client,
  assigned work, an explicit wake, routed demand. The manual grace is not among
  them, so under a sleep policy it spares nothing. The bead's reading named the
  grace as an exemption. The probe slept a manual session two minutes after it
  started.
- `configWakeSuppressedAt` (`cmd/gc/session_sleep.go`) keeps a slept session
  asleep while its recorded `sleep_policy_fingerprint` matches the template's
  policy, so a change to the policy wakes every session it slept.
- `v2LatchRefusals` (`cmd/gc/reconcile_latch.go`) refuses the v2 reconciler
  for `[chat_sessions] idle_timeout`, for an agent's `depends_on` and for an
  agent's `max_session_age`. It does not refuse `sleep_after_idle`.
- `ValidateSemantics` (`internal/config/validate_semantics.go`) warns when an
  agent sets both `idle_timeout` and `sleep_after_idle`, `"0"` included, and
  `splitStrictConfigWarnings` (`cmd/gc/strict_warnings.go`) keeps that warning
  non-fatal under strict mode
  (`TestSplitStrictConfigWarnings_IdleSleepMaskingWarningIsNonFatal`,
  `cmd/gc/strict_warnings_test.go`). The templates keep `idle_timeout = "0"`,
  so the city logs that warning at each load.

## Stopping a sitting whose conversation is done: `gc runtime drain-ack`, kept

The sign-off and the dismiss already stop the session with
`gc runtime drain-ack`. Under v2 the fence's attach leg holds that stop while a
client is attached (`stopLegs` in `cmd/gc/reconcile_effect_stop.go`,
`attachLeg` in `cmd/gc/reconcile_session_fence.go`), and the held stop backs off
from 10 seconds, doubling, to five minutes (`vetoBackoff`,
`cmd/gc/allocator_backoff.go`). That is the behaviour the design wants: the
pane stays live while the operator watches, and the agent stops once they
leave.

## Closing a stopped sitting: the core reaper, for drained records only

The core pack's `reaper` order runs `gc session prune --state drained --before
24h` (`internal/bootstrap/packs/core/assets/scripts/reaper.sh`,
`SESSION_STATE_PRUNE_AGE`). `PruneDetailed` matches a record by its metadata
state, and `pruneStateAllowed` (`internal/session/manager.go`) admits `drained`
and the older `asleep` with sleep reason `drained`, never an idle-slept
`asleep` one. A drain-acked sitting is closed a day after its stop. An
idle-slept sitting's record stays asleep, holding no process, until something
closes it. Gas City ships nothing that closes it, and the design accepts it.

## Marking the tab done: none, so the pack sets the title format with tmux

The need is that the operator's tab stop looking live once the conversation is
done, while the pane stays live under it.

- Gas City writes no pane or terminal title: no non-test code at `9f807760c`
  runs `select-pane -T`, sets `set-titles` or reads `pane_title`. The one
  title it generates, `generateAndSetTitle` (`internal/api/title_generate.go`),
  writes the session record.
- `gc session rename` writes the record's title, which `gc session list` and
  the board show, and nothing a tab shows.
- `gc session submit` and `gc session nudge` type into the agent, so an agent
  that draws its own name as its terminal title can be told to `/rename`
  itself, which is how `gctk session title` titles a sitting. That does not
  serve the ending. A submit made during the sign-off's own turn is queued for
  the session's next boundary, and the probe saw a queued `/rename` never reach
  a session whose drain-ack had run. A submit to a session that is not running
  resumes it (`Manager.submit`, `internal/session/submit.go`).
- An agent's `session_live` runs only at a start of the session, or when its
  value changes (`runSessionLive`, `internal/runtime/tmux/adapter.go`), and
  `gc session` and `gc runtime` have no verb that sets a tmux option.

So the change sets the session's `set-titles-string` to `done · #T`, the
option its template's `session_live` already sets to `#T`. The agent's drain
block sets it on its own pane's session through `$TMUX_PANE`. `gc-helm dismiss`
can run outside every tmux server, as the board's route does, and Gas City
publishes no socket path, so it names the server as Gas City does:
`tmuxConfigFromSession` (`cmd/gc/providers.go`) takes `[session] socket`, and
otherwise the city's name, and the dismiss reads those from
`gc config show --json` and `gc status --json`. `GC_TMUX_SOCKET` reaches only
`session_setup` and `session_live` commands (`internal/runtime/tmux/adapter.go`),
and no session or service carries it.

What retires the mark: a Gas City command or session field that sets a
session's terminal title, or a lifecycle hook a pack can attach to a
conversation's close.

## What landing restarts

Nothing. A live session restarts on drift of its core fingerprint
(`hashCoreFieldsExtra`, `internal/runtime/fingerprint.go`) or of the
`FingerprintExtra` keys `buildFingerprintExtra` adds (`cmd/gc/cmd_start.go`):
pool sizes, `depends_on`, and a `wake_mode` other than `resume`. Neither holds
the sleep policy, and `sleep_after_idle` does not change the launch command. A
`session_live` change is a live-only drift that restarts nothing. The live
city had two converse sittings open when this was read, both attached.
