---
name: Gas City search for the kill guard (tk-73z7kto)
description: The primitives searched in Gas City, bd, Claude Code and Codex for refusing a pkill or killall an agent types, with what each covers and why the gap is a gctk verb run by the tool-use hook every agent carries. Read it when reviewing gctk session kill-guard or its registration, as AGENTS.md asks of a change that adds operational surface.
---

# Gas City search for the kill guard

This change adds one gctk verb, `gctk session kill-guard`, and registers it as a
second handler in the `PreToolUse` group for `Bash` that every agent already
runs for the gh origin guard. It also takes one Go module, `mvdan.cc/sh/v3`. It
adds no order, script, metadata key, bead kind or state. Each need names the
primitive searched, at `gastownhall/gascity` main 77143ecd18ff (2026-11-25),
Claude Code 2.1.332 and codex-cli 0.167.2.

## Refuse a command an agent types, with a reason it can act on

**Gas City: not covered.** An agent's config sets what its session starts with,
and none of its keys refuses a command
([docs/reference/config.md](https://github.com/gastownhall/gascity/blob/77143ecd18ff/docs/reference/config.md)).
`args` passes flags to the provider, `option_defaults` picks a provider option
such as `permission_mode`, and `permission_modes` is "a config-only lookup
table consumed by external clients ... currently no runtime code reads this
field". `install_agent_hooks` chooses which providers get Gas City's own hooks,
and the Claude ones (`internal/hooks/config/claude.json`) are `SessionStart`,
`PreCompact` and `UserPromptSubmit`, none of which runs before a tool.

**bd: not covered.** bd holds work, and nothing in it sees a shell call.

**Claude Code: a hook covers it, and a permission rule does not.** A permission
rule, such as `permissions.deny` holding `Bash(pkill:*)`, or the same rule
passed as a flag through `args`, refuses with fixed text of Claude Code's own:
`Permission to use ${tool} with ${rule} has been denied.` (function `P3t` in the
2.1.332 binary). That text cannot tell an agent how to stop the process it
started, so the agent's next move is another pattern. A `PreToolUse` hook
refuses with a reason the hook writes: `permissionDecision` `deny` with
`permissionDecisionReason`, which the hook schema in 2.1.332 describes as the
"Reason for the permission decision (PreToolUse only)". The verb is that hook.

**Codex: the same hook covers it.** Codex sends a shell call to a `PreToolUse`
hook in the shape Claude Code does and reads the same deny object back, which
the gh origin guard's Codex registration already depends on
([docs/gh-origin-guard.md](../../docs/gh-origin-guard.md#codex)). Codex also
checks commands against its own rules (`codex execpolicy`). A rule there would
state the guard a second time, for one provider, beside the hook both providers
already run.

## Deliver the hook to every agent

**Covered: an agent's `overlay_dir`.** Gas City copies an agent's overlay into
its working directory at each start (`OverlayDir` in `internal/config/config.go`)
and merges a staged `.claude/settings.json` into the one there
(`MergeSettingsJSON` in `internal/overlay/merge.go`). The merge keys a hook
category's entries by their matcher, so one `Bash` group per file is the shape
it merges. Every agent already runs the `Bash` group that holds the gh origin
guard: each Claude agent through its overlay, and each Codex agent through the
copy `gh-origin-guard-codex.sh` makes of the gh-origin-guard overlay's group in
the Codex home. The kill guard's handler joins that group in each overlay, so
it reaches every agent with no new wiring.
`services/gctk/cmd/gctk/kill_guard_wiring_test.go` fails when a group that runs
the gh origin guard does not also run the kill guard, once and in one spelling.

## Read the command as the shell will

**Covered: `mvdan.cc/sh/v3`.** Gas City reads shell with this library: its
`internal/genshell` package interprets the shell programs Gas City generates
"by an embedded POSIX interpreter (mvdan.cc/sh)", and its `go.mod` requires
v3.13.1. The guard parses the typed command with the library's `syntax` package
at that version, so a `pkill` in a commit message, a here-document's body or a
grep's pattern is text and not a call. It decodes a `$'...'` string with the
`expand` package's `Format`, as the library's own expander does, so a script
such as `bash -c $'echo start\npkill -f x'` is read as bash runs it. The two
packages import only the standard library and the module's own packages.

## Where the logic lives

The rule is logic, so it is Go in gctk (AGENTS.md, "New pack code is written in
Go, in gctk"), and the handler only calls gctk. Its command exits 0 whatever
gctk does, so a gctk that is missing, or too old to know the verb, lets the call
run: Claude Code reads a `PreToolUse` hook's exit 2 as a refusal.

`gh-origin-guard-codex.sh` grows by one predicate. It only configures Codex's
hooks file, which gctk is inappropriate for, as it is for other code that only
configures another tool. It already copies the whole group, and it now owns the
kill guard's handler as well as the gh guard's. Without that, a later change to
the kill guard's command would leave the old handler running beside the new one.

## What it costs

The handler runs before every shell call of every agent. It took a median of
18 ms per call, and 21 ms at the 90th percentile, over 30 runs on the city's
host at a load average near 30 (2026-11-25), with the binary
`go build ./services/gctk/cmd/gctk` makes.
