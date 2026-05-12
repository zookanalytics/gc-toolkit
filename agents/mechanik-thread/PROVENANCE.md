# Agent: mechanik-thread

**Status:** native
**Source:** N/A (gc-toolkit-original; spike under `tk-k9s0k`)
**Drift:** N/A

## Goals

Operator-spawnable, rig-scoped thread of `mechanik`. Provides
parallel conversational access to the mechanik role for focused
thinking work, without competing with the canonical mechanik for
routed mail and work.

Concurrency is unbounded (no `max_active_sessions`); the operator
spawns as many threads as they need. Each instance gets its own git
worktree of the rig repo (separate from the canonical's
`.gc/agents/mechanik` home), so concurrent threads do not stomp each
other's filesystem.

## Why we built this

`gc-h1gxg` decided to make role-instance separation a first-class
operator-facing primitive. The synthesized Role+Thread model from
the four research passes calls for: one durable Role (mechanik), N
ephemeral Threads (mechanik-thread-N), with the canonical instance
absorbing routed work and threads reserved for the operator.

Previously the operator's only option was a scratch clone in a
tmux split (`scratch-clone-guard.md`), which shared the canonical's
working directory and disappeared whenever the canonical mechanik
was reset. mechanik-thread survives `gc session reset` of the
canonical because it is a distinct agent identity in pack config.

## Notes

- Cross-references the canonical mechanik's `prompt.template.md` via
  `prompt_template = "agents/mechanik/prompt.template.md"` (pack-root
  relative; `compose.adjustFragmentPath` translates to city-root before
  render). Template variables resolve under the thread's identity
  (`AgentName`, `RigName`, `WorkDir`). When mechanik's prompt evolves,
  threads pick up the change on next spawn — no duplication.

- `append_fragments = ["mechanik-thread-role"]` appends a role-
  clarification block after the canonical body. The fragment ships
  at `template-fragments/mechanik-thread-role.template.md`.

- `work_query = "printf '[]'"` and a non-zero-exit `sling_query`
  keep the thread off the routed-work and sling-target paths.
  Routed work flows to the canonical only.

- `wake_mode = "resume"` preserves the operator's focused-thinking
  conversation across sleep/wake cycles. (The canonical mechanik
  uses `wake_mode = "fresh"`.)

- `min_active_sessions = 0` means the reconciler does not pre-spawn,
  and `max_active_sessions` is unset (unbounded). The operator spawns
  via `gc session new gc-toolkit/gc-toolkit.mechanik-thread`; gascity
  numbers pool instances `mechanik-thread-1`, `-2`, … on each spawn.

> 2026-05-11: renamed from `mechanik-side` to `mechanik-thread` pre-merge per mechanik+operator decision (slit FP design `Thread` primitive; cross-platform convergence on thread-as-conversation-identity).
