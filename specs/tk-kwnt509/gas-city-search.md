---
name: Gas City search for the converse sittings' compaction (tk-kwnt509)
description: The primitives searched in Gas City and Claude Code for the three needs of a converse sitting that compacts and goes on, steering a Claude sitting's compaction summary, refusing the compaction of a sitting that has finished, and keeping Gas City's handoff advice from every sitting, with what each covers and why the summary steer and the refusal are the pack's own overlay. Read it when reviewing overlays/converse-compact or a converse template's context_advisory, as AGENTS.md asks of a change that adds operational surface.
---

# Gas City search for the converse sittings' compaction

This change gives the four Claude converse templates an overlay of their own,
`overlays/converse-compact`, whose PreCompact hook prints instructions for the
compaction summary, or refuses the compaction once the sitting has finished,
and it turns `context_advisory` off on every converse template. It adds no
script, order, bead key or lifecycle state. The first and third needs name the
primitive searched at `gastownhall/gascity` main 781c975d7921 (2026-11-21),
Claude Code 2.1.330 and Claude Code's documentation read on 2026-11-21. The
refusal's need names it at `gastownhall/gascity` main 1e7e600f2cc7
(2026-11-25), Claude Code 2.1.332 and the documentation read on 2026-11-25.

## Steer what a sitting's compaction summary keeps

**Not covered by Gas City.** Gas City's managed Claude settings wire
`SessionStart` with the matcher `startup` alone, running `gc prime --hook`, a
`PreCompact` hook running `gc handoff --auto "context cycle"`, and two
`UserPromptSubmit` hooks, `gc nudge drain --inject` and `gc mail check
--inject` (`internal/hooks/config/claude.json`). `gc handoff --auto` mails the
session and requests no restart, and the one line it writes as the hook's
output is `Handoff: sent auto mail <id> (restart skipped).` (`doHandoffAuto`
in `cmd/gc/cmd_handoff.go`). Claude Code reads a PreCompact hook's output as
instructions for the summary, so that line is all a sitting's summary is told
today. The core pack's per-provider overlays wire the same `gc handoff --auto`
for the other providers (`internal/bootstrap/packs/core/overlay/per-provider/`),
and no Gas City config steers what a summary keeps. The open upstream issues
that name PreCompact or compaction ask for the hook's output format (#6349),
timeouts and an override surface for the managed Claude settings (#4298),
recovery points for long-lived agents (#4386) and an end to the handoff mail
the hook leaves (#7208, #6211). None proposes steering what the summary keeps.

**Covered by Claude Code: the PreCompact hook.** "When a PreCompact hook exits
0 and doesn't block, Claude Code uses its stdout as instructions for the
compaction summary." The output is to stay "under 10,000 characters per hook",
and longer output is cut at the cap. "Exit with code 2 to block compaction."
The matcher `auto` covers auto-compaction and idle compaction
([hooks](https://code.claude.com/docs/en/hooks), "PreCompact"). Hook entries
merge across settings levels rather than replacing each other (same page,
"Hook locations"), so the pack's hook runs beside Gas City's. The pack composes
it: the hook prints a fixed text, `.claude/hooks/converse-compact.md`, and
exits 0, unless the sitting has finished (the next need).

**Why an overlay of its own.** Gas City copies an agent's overlay into its work
dir when the session starts, overwriting a plain file and merging
`settings.json` entry by entry (`copyOrMergeFileWithAdaptRel` in
`internal/overlay/overlay.go`, `MergeSettingsJSON` in
`internal/overlay/merge.go`). An agent has one overlay (`OverlayDir` on `Agent`
in `internal/config/config.go`), and the four
Claude sittings shared `overlays/gh-origin-guard` with the mechanik, the po,
the proactive pool and demo. A hook added there would reach those roles too,
so the sittings take their own overlay, which carries the gh guard's
registration as well.

**Not taken: a SessionStart hook on `compact`.** Claude Code runs a SessionStart
hook whose matcher is `compact` after a compaction and adds its output to the
compacted context ([context window](https://code.claude.com/docs/en/context-window),
"What survives compaction"). The steered summary already ends by sending the
sitting through its entry, and the prompt says the same, so the change adds no
second hook.

## Refuse the compaction of a sitting that has finished

The need: a sitting whose last act, `gc runtime drain-ack`, has run is kept
alive only while a tab is attached, and Claude Code's idle compaction then
summarizes a thread the sitting runs nothing more on. Of the 102 compactions of Claude
sittings from 2026-10-30 to 2026-11-23, 28 came after the drain-ack (tk-kwnt509's
notes, the findings block of 2026-11-25T18:02:18Z). On this city on
2026-11-25, read with `tmux -L loomington show-environment` and
`gc session list`, two converse sittings held the flag below at 19:02Z, both
in state draining. The unattached one was asleep by 19:09Z, and its tmux
session was gone with the flag. The other had a tab attached, had drained at
18:12:52Z on a thread of 415,598 tokens, and still held the flag at 19:09Z.

**Covered by Gas City: the drain-ack's flag, `GC_DRAIN_ACK`.** Every
`gc runtime drain-ack` that lands writes `GC_DRAIN_ACK=1` into the session's
metadata, the session's own ack and an operator's `--operator` ack alike,
under both reconcilers: `providerDrainOps.setDrainAck`, which
`finishRuntimeDrainAck` runs through `rowAckedDrainOps` on the v2 path and
`persistedAckDrainOps` on the legacy one (`cmd/gc/cmd_runtime_drain.go`). On
the tmux runtime the metadata is the session's tmux environment:
`Provider.SetMeta` is `Tmux.SetEnvironment`, which runs
`set-environment -t <session> <key> <value>`, and Gas City reads it back with
`Provider.GetMeta`, which is `Tmux.GetEnvironment`, running
`show-environment -t <session> <key>` (`internal/runtime/tmux/adapter.go`,
`internal/runtime/tmux/tmux.go`). An ack Gas City refuses, such as a session's
own ack while it holds a claim it started, writes neither the row nor the flag
(`runtimeDrainAck`, `drainAckRefused`), and `gc runtime undrain` removes the
flag (`providerDrainOps.clearDrain`, `set-environment -u`). The CLI reference
says drain-ack "Sets GC_DRAIN_ACK metadata on the session"
([`gc runtime drain-ack`](https://docs.gascity.com/reference/cli#gc-runtime-drain-ack)).
The hook makes Gas City's own read from inside the session's pane,
`tmux show-environment -t "$TMUX_PANE" GC_DRAIN_ACK`, and refuses only on the
exact answer `GC_DRAIN_ACK=1`. That is the flag each converse template's tab
title already reads for its `done` mark
([specs/tk-7w7qdls/gas-city-search.md](../tk-7w7qdls/gas-city-search.md#marking-the-tab-done-the-drain-flag-composed)).

**The flag ends with the session.** A stop kills the tmux session:
`Provider.Stop` runs `KillSessionWithProcessesExcluding`, which ends in
`kill-session`. A start makes a new one with `new-session`, and a name still
held refuses the start (`ErrSessionExists` in `Provider.Start`), so it never
lands in an old session's environment. A sitting that starts again after a
stop, as a stay's wake or an engage does, therefore holds no flag. A stay
acknowledges no drain (`skills/converse-stay/SKILL.md`, "A stay closes
nothing, so it drains nothing"), and engage never hands a conversation to a
session that still holds its alias while a tab is attached
(`assets/scripts/gc-helm.sh`, engage). The one path that runs a new agent
process inside a kept tmux session, `Provider.Relaunch`, which leaves "its
session environment" intact, applies a launch-only config change, and an
attached client holds it as it holds the stop (`relaunchCall` in
`cmd/gc/reconcile_effect_restart.go`).

**Not covered by Gas City: a command that answers whether a session
acknowledged its drain.** `isDrainAcked` has no CLI caller. `gc runtime
drain-check` answers another question: "Consults two sources: the runtime's
GC_DRAIN metadata flag, which "gc runtime drain" sets, and the session row's
state, which reads draining once the controller has begun stopping the
session" (`newRuntimeDrainCheckCmd`). A drain asked of a sitting that still
holds its conversation reads draining there, and the converse prompt's `stop`
case has that sitting go on with its conversation after Gas City refuses its
ack, so a refusal keyed on drain-check could refuse a live sitting. It also
loads the city's config and opens the session store on each call. Gas City's
own PreCompact hook, `gc handoff --auto`, never blocks a compaction.

**Covered by Claude Code: a PreCompact hook that exits 2.** "Exit with code 2
to block compaction. For a manual `/compact`, the stderr message is shown to
the user." "If compaction was triggered proactively before the context limit,
Claude Code skips it and the conversation continues uncompacted. If compaction
was triggered to recover from a context-limit error already returned by the
API, the underlying error surfaces and the current request fails." The `auto`
matcher covers "Auto-compact when the conversation reaches the auto-compact
window, and idle compaction"
([hooks](https://code.claude.com/docs/en/hooks), "PreCompact"). The installed
Claude Code 2.1.332 holds the strings "Compaction blocked by PreCompact hook"
and "Reactive compact runs despite a PreCompact hook's block, because the
request cannot go out uncompacted", so at a full window this version compacts
anyway, where the page says the request fails. A finished sitting reaches a
full window only if someone types into it. In the same binary the idle timer
is armed from the state a main-thread request saves and is not armed again
when it fires (`EVn`), so a refused idle compaction waits for another request
before it is tried again. [verification.md](verification.md) shows the
typed refusal and counts the hook's runs, and says why the idle compaction
could not be staged.

**Not taken.** Turning idle compaction off for the sittings, through Claude
Code's `idleCompaction` setting, would also stop the hour-mark compaction of a
live sitting, which this course keeps. Stopping the session at the drain-ack
while a tab is attached is Gas City's to decide, and it holds that stop by
design so the operator's tab stays readable ("v2's stop verb holds while a
client is attached (L3)", `v2SignaledStopHeldForAttach` in
`cmd/gc/session_reconciler.go`). That reason holds here, since the tab shows
the sitting's last screen, so the hook works beside the hold and changes
nothing in Gas City.

**Why the check sits in the hook's command and not in gctk.** The check is
Claude Code configuration keyed on tmux's state: it reads one variable of the
hook's own tmux session and tells Claude Code whether to compact, as the
template's title string reads the same variable to tell tmux what to draw. It
needs no store, city config or pack state. Run through gctk, the hook would
still need a shell fallback that prints the steer and exits 0 when the binary
is missing or fails, since a failed read must never refuse a live sitting, so
the command could not be a bare gctk call. AGENTS.md names code that only
configures another tool as logic gctk is inappropriate for.

## Keep Gas City's handoff advice from a sitting

**Covered by Gas City: the agent's `context_advisory`.** The advisory is on by
default, with a tier at 60% that tells a session to plan a handoff and reset
itself and one at 80% that tells it to run `gc session reset` on itself
(`DefaultContextAdvisory` in `internal/config/context_advisory.go`). An
agent's own table is merged over the city's `[agent_defaults]` and the built-in
default (`Agent.ContextAdvisory` in `internal/config/config.go`, and
`ResolveContextAdvisory`, which `contextInjectLineForSample` in
`cmd/gc/context_inject.go` calls with the target agent's table from
`cmd/gc/cmd_nudge.go`). A policy that is not enabled renders nothing before any
environment override applies (`contextUsageMessageForPolicy`). The two callers
that pass no agent table run only for a hook with no session identity or a
session that does not resolve, which a live sitting is not. So each converse
template sets `context_advisory = { enabled = false }`, and every other agent
keeps the default. [verification.md](verification.md) shows the resolved
result for every agent.
