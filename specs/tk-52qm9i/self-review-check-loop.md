---
name: self-review as a bounded [steps.check] verified-green loop
description: How the mol-polecat-work self-review step composes with a ralph check loop — the engine contract that forces a verify-not-run gate and a session-model split, and why the loop is fresh-claimed rather than inline.
---

# self-review is a bounded verified-green check loop

The self-review step of `mol-polecat-work` is a `[steps.check]` loop
(`max_attempts = 3`). Each iteration runs the rig's declared checks in its own
session and, on green, stamps `metadata.self_review_passed_sha = <HEAD>` on the
work bead. The loop's exit condition, `assets/scripts/self-review-check.sh`,
converges only when that stamp names the live HEAD of a clean worktree. A red
iteration spawns the next, up to the budget; the refinery re-runs the real gate
as the backstop. This turns a red hand-off — which the refinery discovers a hop
later and answers by deleting the workflow and repouring a fresh six-step
molecule — into an in-session iteration.

## The check-loop execution contract

A `[steps.check]` compiles (`internal/formula/ralph.go` `expandRalph`) to a
control bead (`gc.kind=ralph`, carrying `gc.max_attempts` /
`gc.check_path` / `gc.check_timeout`), a spec sidecar, and a first iteration
`self-review.iteration.1`. Downstream `needs = ["self-review"]` binds to the
control bead, which the orchestrator closes on convergence
(`engdocs/design/inline-ralph-v0.md`).

The exit condition runs as a child process of the control dispatcher, not in an
agent session (`internal/dispatch/ralph.go` `runRalphCheck` →
`internal/convergence/condition.go` `RunCondition`). That imposes the shape of
the gate:

- **It verifies, it does not run the gate.** The exec is bounded by
  `check.timeout` (default `DefaultGateTimeout = 5m`, `internal/convergence/gate.go`),
  blocks control-bead processing city-wide for its duration, runs under a
  sandboxed PATH (`bd`, `gc`, `dolt`, `jq` plus `/usr/local/bin:/usr/bin:/bin` —
  no guaranteed `go`), and a HOME redirected to the city root (cold build
  caches). A rig's real test suite cannot run here. So the iteration agent runs
  the checks in its own session and stamps the result bound to a commit sha; the
  exit condition confirms the stamp still names the live HEAD. A later commit
  moves HEAD off the stamp and re-gates the loop, so the stamp can go stale but
  cannot certify a different tree.
- **Resolution is `bd`-only.** `gc` subcommands load the full city config
  including the pack import closure, which in this env can be cold; the `gc`
  call then dies before doing anything. The exit condition resolves the work
  bead through the convoy with `bd` alone (`gc.var.issue` on the root is the
  resilient fallback, stamped by the iteration), and cross-checks the two.
- **Exhaustion is the gate's own job.** At `gc.attempt >= gc.max_attempts` the
  orchestrator closes the control bead `gc.outcome=fail` and stops; it never
  touches the work bead, and `submit-and-exit` stays blocked. The exit condition
  is the only thing that runs at that moment, so on the final failing attempt it
  hands the work bead back itself: `aborted_at=self-review-exhausted`, route
  cleared, drained session pins cleared, reassigned to the witness with the
  failure in notes, plus a best-effort nudge. It fires only on the budget's last
  attempt and only once. The budget comes from the control bead's
  `gc.max_attempts` because the condition env sets `GC_ITERATION` but leaves
  `GC_MAX_ITERATIONS` at zero.

## Session model: an inline island, then a fresh loop

The engine question the loop had to settle is how `session_affinity="require"`
interacts with per-iteration fresh context. The answer: a pool-routed retry
clone is created unassigned and has its session-affinity metadata cleared
(`internal/dispatch/ralph.go`, `retryPreservedAssigneeWithConfig` returns empty
for a pool route → `clearSessionAffinityMetadata`). Affinity holds only *within*
one attempt; the engine strips it on every pool retry. `mol-polecat-work` is
pool-routed, so each self-review iteration runs in a fresh pooled session with
fresh context. That is the intended property — a worker judging its own work
with a clean context — not a limitation to work around.

This is incompatible with running the whole molecule inline in one session. The
loop's completion is decided asynchronously by the orchestrator, so a session
cannot flow past it. The steps therefore split into three phases:

- `load-context → workspace-setup → preflight-tests → implement` keep
  `gc.continuation_group = "main"`: one session claims `load-context`, the hook
  vacuums the rest onto it, and it runs them inline. `implement` closes that
  four-step chain forward and drains. Closing before the drain is mandatory: a
  drained session that leaves `load-context` open and routed hands it to a fresh
  polecat, who walks back through `workspace-setup` onto a branch this run
  already built.
- `self-review` carries no continuation group, so its iteration is claimed fresh
  from the pool — the fresh-context property above.
- `submit-and-exit` carries no continuation group either. It must not be
  vacuumed onto the inline session (which drains at `implement`) and stranded;
  it is a clean pool claim once the loop converges.

`submit-and-exit`'s chain-close closes five steps —
`load-context workspace-setup preflight-tests implement submit-and-exit` — not
six. `self-review` is the orchestrator-owned control bead; closing it by hand
would corrupt the loop. The first four are already closed by `implement`, so the
re-attempt is belt-and-suspenders against a crashed `implement` session.
`submit-and-exit`'s own blocker is the control bead, which the orchestrator has
closed by the time this session runs, so it closes at the end of the loop.
