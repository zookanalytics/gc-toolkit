# Agent: mechanik-side

**Status:** native
**Source:** N/A (gc-toolkit-original; spike under `tk-k9s0k`)
**Drift:** N/A

## Goals

Operator-spawnable, rig-scoped side-instance of `mechanik`. Provides
parallel conversational access to the mechanik role for focused
thinking work, without competing with the canonical mechanik for
routed mail and work.

Up to 4 concurrent threads. Each instance gets its own git worktree
of the rig repo (separate from the canonical's `.gc/agents/mechanik`
home), so concurrent threads do not stomp each other's filesystem.

## Why we built this

`gc-h1gxg` decided to make role-instance separation a first-class
operator-facing primitive. The synthesized Role+Thread model from
the four research passes calls for: one durable Role (mechanik), N
ephemeral Threads (mechanik-side-N), with the canonical instance
absorbing routed work and side instances reserved for the operator.

Previously the operator's only option was a scratch clone in a
tmux split (`scratch-clone-guard.md`), which shared the canonical's
working directory and disappeared whenever the canonical mechanik
was reset. mechanik-side survives `gc session reset` of the
canonical because it is a distinct agent identity in pack config.

## Notes

- Cross-references the canonical mechanik's `prompt.template.md` via
  `prompt_template = "../mechanik/prompt.template.md"`. Template
  variables resolve under the side instance's identity (`AgentName`,
  `RigName`, `WorkDir`). When mechanik's prompt evolves, side
  instances pick up the change on next spawn — no duplication.

- `append_fragments = ["mechanik-side-role"]` appends a role-
  clarification block after the canonical body. The fragment ships
  at `template-fragments/mechanik-side-role.template.md`.

- `work_query = "printf '[]'"` and a non-zero-exit `sling_query`
  keep the side instance off the routed-work and sling-target paths.
  Routed work flows to the canonical only.

- `wake_mode = "resume"` preserves the operator's focused-thinking
  conversation across sleep/wake cycles. (The canonical mechanik
  uses `wake_mode = "fresh"`.)

- `min_active_sessions = 0` means the reconciler does not pre-spawn.
  The operator spawns via `gc session new gc-toolkit/gc-toolkit.mechanik-side`,
  bounded by `max_active_sessions = 4`.
