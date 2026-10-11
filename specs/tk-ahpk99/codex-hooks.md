---
name: How Codex reaches the gh origin guard — the evidence
description: What tk-ahpk99 established about how Codex 0.160.1 loads, trusts and runs a PreToolUse hook, the probes that showed each fact, and the follow-ups it filed. Read it to re-check docs/gh-origin-guard.md's Codex section against a newer Codex.
---

# How Codex reaches the gh origin guard — the evidence

tk-ahpk99 found dog and polecat-codex outside the gh origin guard, and assumed
Codex needed an adapter around the guard's resolution logic, because the guard
reads a Claude hook payload and writes a Claude permission decision. Codex
0.160.1 speaks that format already. What it needed was a registration in a
place Codex reads, and the directory a Codex call runs in, which its payload
leaves out. converse-codex, added after the bead was filed, is a third codex
agent with the same gap.

Source references are to `openai/codex` at tag `rust-v0.160.1`, read with
`gh api repos/openai/codex/contents/<path>?ref=rust-v0.160.1`. Live probes ran
the installed `codex-cli 0.160.1` on the city host on 2026-10-10.

## The payload and the decision

- A shell call reaches a hook as `tool_name: "Bash"` with
  `tool_input: {"command": <cmd>}` (`core/src/tools/handlers/unified_exec/exec_command.rs`,
  `pre_tool_use_payload`). The payload also carries `cwd`, `session_id`,
  `turn_id`, `transcript_path` and `tool_use_id`, the call's `call_id`
  (`hooks/src/events/pre_tool_use.rs`, `core/src/tools/registry.rs`).
  `turn_id` is a Codex extension; Claude sends none.
- `cwd` is the turn's environment directory (`core/src/hook_runtime.rs`,
  `tool_hook_cwd`). The call's `workdir` argument is not in the payload.
- Exit 0 with `hookSpecificOutput: {hookEventName: "PreToolUse",
  permissionDecision: "deny", permissionDecisionReason: <non-empty>}` blocks the
  call. The output schema allows no other keys inside `hookSpecificOutput`, and
  JSON that does not parse marks the hook failed, which does not block
  (`hooks/src/events/pre_tool_use.rs`, `parse_completed`). The guard's deny
  object is exactly the accepted shape.
- `write_stdin`, text sent into a shell an earlier call started, emits no
  PreToolUse (`.../unified_exec/write_stdin.rs`).
- A hook runs as `$SHELL -lc <command>` with the session's environment replayed
  (`hooks/src/engine/command_runner.rs`, `build_command`), so `GC_RIG_ROOT` and
  `GC_CITY_PATH` reach it.

## Where Codex reads hooks

`codex app-server` answers `hooks/list` for a directory without starting a
session or calling a model. It was driven over stdio with a scratch
`CODEX_HOME` whose `config.toml` trusts the project.

| Session directory | Hooks file | Listed |
|---|---|---|
| linked worktree of repository R | the worktree's own `.codex/hooks.json` | no |
| linked worktree of repository R | `R/.codex/hooks.json`, the main checkout | yes |
| plain directory inside city repository C (dog's shape) | `C/.codex/hooks.json` and the directory's own | both |
| any | `$CODEX_HOME/hooks.json` | yes |

Against the live Codex home, `hooks/list` for both live polecat-codex
worktrees listed nothing, although each holds a gc-managed `.codex/hooks.json`.
gc's managed Codex hooks are therefore inert for worktree agents; gc-c54dxs
carries that to gascity.

## Trust

A hook that is not managed runs only when `hooks.state.<key>.trusted_hash` in
the Codex home's `config.toml` matches its current hash, or under
`--dangerously-bypass-hook-trust` (`hooks/src/engine/discovery.rs`,
`hook_trust_status`). The key is the source path, the event and the hook's
indices, and the hash covers its content. In the TUI an untrusted hook raises
"Hooks need review" before the session starts, with "Review hooks", "Trust all
and continue" and "Continue without trusting" (`tui/src/startup_hooks_review.rs`).
gc's startup handling sends Down and Enter to it (gascity
`internal/runtime/dialog.go`, `acceptCodexHookReviewDialog`), and the live gc
binary carries those strings. The trust item's explicit confirmation applies
only when a shortcut key highlights it (`tui/src/bottom_pane/list_selection_view.rs`).
The review runs before `App::run` starts the thread, so by code reading the
first session after a new registration already runs it; no live TUI run checked
that.

## Where a call runs

Codex records a call the model makes in the transcript before it dispatches the
tool (`core/src/stream_events_utils.rs`, `handle_output_item_done`), and the
transcript writer writes and flushes each line as it receives it
(`rollout/src/recorder.rs`). The line is a `response_item` whose payload is a
`function_call` carrying `call_id` and an `arguments` JSON string with `cmd` and
`workdir`.

In 60 recent rollouts in the live Codex home, every shell call was
`exec_command`. 821 of 3,926 calls set `workdir` to a directory other than the
session's, and 9 of 63 `gh issue|pr|api` calls did, most of them into review
worktrees under `$TMPDIR`.

## End to end

`codex exec` ran in a scratch `CODEX_HOME` holding only the `hooks.json` the
registration script wrote, with `--dangerously-bypass-hook-trust` standing in
for gc's trust step. `GC_RIG_ROOT` named a scratch checkout whose origin is
ours, and a scratch clone with a third-party origin served as the `workdir`.
The prompt asked for `gh issue create` twice: once with that clone as
`workdir`, once with none.

- With `gpt-6.1-sol`, the live Codex home's default model, both calls went
  through Codex's code-mode tool, a
  `custom_tool_call` named `exec` whose script calls `exec_command`. The nested
  call has no transcript line of its own, so the guard found no directory and
  refused both, and Codex blocked both. That is why the guard treats a missing
  line as an unknown directory, and why it looks the call up only after its
  scan finds a guarded write.
- With `gpt-5.5`, the model gc's codex agents run, both were direct
  `function_call`s. The first was refused "aimed at github.com/get-convex/agent",
  a target the guard can only reach by reading the `workdir`. The second, aimed
  at our own repository, was allowed. A `gh` stub placed first on `PATH` in the
  launch environment never ran (its log stayed empty) and the real gh did, so
  the allowed call opened zookanalytics/gc-toolkit#1165. It was closed as not
  planned with no comment. A live probe of an allowed call needs a target that
  cannot be reached, not a `PATH` stub.

## Follow-ups

- gc-c54dxs (gascity): Codex never reads a linked worktree's `.codex/hooks.json`,
  so gc's managed Codex hooks for polecat-codex and converse-codex never run.
- tk-g09rf07: a Codex session started outside gc finds no guard, because the
  registration resolves it only through `GC_RIG_ROOT` and `GC_CITY_PATH`.
