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
spawns as many threads as they need. Each instance gets its own
plain scratch directory under `.gc/agents/mayor-thread/` — same
shape as the canonical mayor's `.gc/agents/mayor` home — so
concurrent threads have independent scratch space. Threads are
routers, not doers; any git work targets a rig via
`git -C rigs/<rig>` (matching the canonical's pattern), so they do
not need a private checkout.

## Why we built this

The `mechanik-thread` spike (`tk-k9s0k`) validated the Role+Thread
model for the mechanik role. `tk-1zd25` extends the same pattern to
the mayor — the other canonical interactive role — and adds the
`Ctrl-B + a` tmux binding that detects the current pane's `GC_AGENT`
and spawns a matching thread.

The deacon, witness, and refinery are intentionally excluded:
they are patrol / automation roles, and nobody holds a focused
thinking session with one.

That is a statement about **thread-spawnability**, and it does not
generalise. This paragraph used to end "…, not operator-facing", and
that phrasing was read as a roster: the `operator-next-step-trailing`
fragment was distributed to the roles named here and withheld from the
ones excluded here, which left the refinery — the single largest
producer of "a PR is waiting on you" traffic in the city — running
without the one rule that governs it (tk-l1pj6). Two different tests
were collapsed into one:

- *Does the operator converse with this role?* decides whether it gets
  a thread. Patrol roles: no.
- *Does a human read this role's prose as a report?* decides whether it
  is bound by operator-reply doctrine. The refinery: yes — it holds the
  human-approval merge gate, narrates that queue into a pane the
  operator watches, and parks beads with `gc.routed_to=human`.

The thread exclusion above stands. The operator-facing roster is held,
with a reason per agent, by
`doctor/check-operator-next-step-wiring/run.sh`; classify there, not
here.

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

> 2026-05-19: `work_dir` reshaped from `.gc/worktrees/gc-toolkit/mayor-thread/<base>` (git worktree) to `.gc/agents/mayor-thread/<base>` (plain scratch dir) (tk-pzls5c). Threads are routers, not doers — mayor is strictly a coordinator — so no private rig checkout is needed. `pre_start` worktree-setup call dropped; rig git ops use `git -C rigs/<rig> …` like the canonical. Existing thread-worktree orphans on disk are out of scope for this change; deferred to `tk-cwsj1`.
