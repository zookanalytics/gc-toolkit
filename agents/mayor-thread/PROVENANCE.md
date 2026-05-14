# Agent: mayor-thread

**Status:** native
**Source:** N/A (gc-toolkit-original; symmetric to `mechanik-thread`
spike under `tk-k9s0k`; introduced under `tk-1zd25`)
**Drift:** N/A

## Goals

Operator-spawnable, city-scoped thread of `mayor`. Provides
parallel conversational access to the mayor role for focused
thinking work, without competing with the canonical mayor for
routed mail and work.

Scope mirrors the canonical mayor (`scope = "city"`) so threads
register as `gc-toolkit.mayor-thread` rather than the rig-prefixed
form. Concurrency is unbounded (no `max_active_sessions`); the operator
spawns as many threads as they need. Each instance gets its own git
worktree of the rig repo (separate from the canonical's
`.gc/agents/mayor` home), so concurrent threads do not stomp each
other's filesystem.

## Why we built this

The `mechanik-thread` spike (`tk-k9s0k`) validated the Role+Thread
model for the mechanik role. `tk-1zd25` extends the same pattern to
the mayor — the other canonical interactive role — and adds the
`Ctrl-B + a` tmux binding that detects the current pane's `GC_AGENT`
and spawns a matching thread.

The deacon, witness, and refinery are intentionally excluded:
they are patrol / automation roles, not operator-facing.

## Notes

- Cross-references the canonical mayor's `prompt.template.md` via
  `prompt_template = "agents/mayor/prompt.template.md"` (pack-root
  relative; `compose.adjustFragmentPath` translates to city-root before
  render). Template variables resolve under the thread's identity
  (`AgentName`, `RigName`, `WorkDir`). When mayor's prompt evolves,
  threads pick up the change on next spawn — no duplication.

- `append_fragments = ["thread-role"]` appends the generic
  role-clarification block (`template-fragments/thread-role.template.md`)
  shared with `mechanik-thread`. Parameterized by the `RoleName`
  env var (substituted into the fragment as `{{ .RoleName }}`).

- `work_query = "printf '[]'"` and a non-zero-exit `sling_query`
  keep the thread off the routed-work and sling-target paths.
  Routed work flows to the canonical only.

- `wake_mode = "resume"` preserves the operator's focused-thinking
  conversation across sleep/wake cycles. (The canonical mayor
  uses `wake_mode = "fresh"`.)

- `min_active_sessions = 0` means the reconciler does not pre-spawn,
  and `max_active_sessions` is unset (unbounded). The operator spawns
  via `gc session new mayor-thread`; gascity numbers pool instances
  `mayor-thread-1`, `-2`, … on each spawn.
