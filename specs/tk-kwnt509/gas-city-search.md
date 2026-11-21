---
name: Gas City search for the converse sittings' compaction (tk-kwnt509)
description: The primitives searched in Gas City and Claude Code for the two needs of a converse sitting that compacts and goes on, steering a Claude sitting's compaction summary and keeping Gas City's handoff advice from every sitting, with what each covers and why the summary steer is the pack's own overlay. Read it when reviewing overlays/converse-compact or a converse template's context_advisory, as AGENTS.md asks of a change that adds operational surface.
---

# Gas City search for the converse sittings' compaction

This change gives the four Claude converse templates an overlay of their own,
`overlays/converse-compact`, whose PreCompact hook prints instructions for the
compaction summary, and it turns `context_advisory` off on every converse
template. It adds no script, order, bead key or lifecycle state. Each need
names the primitive searched, at `gastownhall/gascity` main 781c975d7921
(2026-11-21), Claude Code 2.1.330, and Claude Code's documentation read on
2026-11-21.

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
exits 0 whatever happens.

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
