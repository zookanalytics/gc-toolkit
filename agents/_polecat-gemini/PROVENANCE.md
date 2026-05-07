# Agent: polecat-gemini (DISABLED — gemini CLI command-substitution incompatibility)

**Status:** staged-inert (parent dir prefixed with `_` so `agent_discovery.go` skips it)
**Source:** N/A (gc-toolkit-original; mirrors `polecat` shape)
**Drift:** N/A

## Goals

Same as `polecat-codex` but for the Gemini CLI provider. Staged for future enablement.

## Why disabled (2026-05-05)

First test (tk-mmny1) showed gemini CLI 0.40.1 hardcodes a `detectCommandSubstitution` check in `run_shell_command` that runs BEFORE the Policy Engine. It blocks any command containing `$(...)`, backticks, `<()`, or `>()`. The polecat prompt's standard claim/wisp/branch workflow uses `$()` extensively (e.g., `WISP=$(gc bd mol wisp ... | jq -r '.new_epic_id')`) and so every gemini polecat fails to make progress: spawns, runs the no-substitution preamble, hits the first `$()` line, gets blocked, exits, supervisor respawns. Hot loop.

There is no flag, env var, settings.json key, admin policy, or `commandPrefix` rule that bypasses the detector — verified by reading the bundled JS at `/home/linuxbrew/.linuxbrew/Cellar/gemini-cli/0.40.1/libexec/lib/node_modules/@google/gemini-cli/bundle/chunk-UN6XCVMJ.js`.

## How to re-enable

Pre-requisite: pick a workaround for the substitution block, implement it in the polecat prompt or pack, then:

```
mv rigs/gc-toolkit/agents/_polecat-gemini rigs/gc-toolkit/agents/polecat-gemini
gc reload
```

Workaround options (see tk-mmny1 for details):

1. **Script-file wrapper**: polecat workflow becomes shell scripts in `assets/scripts/`; the prompt calls `bash <script>` instead of inlining `$()`.
2. **Custom MCP tool**: wrap polecat operations as an MCP server; gemini calls `mcp_polecat_*` tools.
3. **Prompt rewrite**: convert `$()` to write-then-read patterns. Painful.

## Notes

`polecat-codex` is the existing alternative-provider slot. It works (verified on signal-loom Epic 6 cross-agent review-chain). Whether to invest in fixing gemini compatibility or rely on codex is a separate decision (downstream of tk-mmny1).
