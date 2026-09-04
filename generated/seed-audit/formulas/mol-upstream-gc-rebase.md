Formula: mol-upstream-gc-rebase
Description: Rebase the gascity rig's `origin/main` onto `upstream/main`, drop already-
landed-or-supplanted local commits, run the quality gate, install, push the
working branch (`rebase/{{issue}}`) to origin, and hand off to refinery for
the force-push to `{{upstream_branch}}`.

Extends `mol-polecat-base` for the standard lifecycle entry points but uses
its own gating steps in place of implement / self-review — the work is a
controlled rebase with a verdict-keeping survey, not a feature.

**Force-push ownership:** the terminal force-push onto `{{upstream_branch}}`
is performed by the rig-scoped refinery via the sub-pack's
`refinery-rebase-handling` overlay, never by this polecat. The polecat pushes
only its own ref `refs/heads/rebase/{{issue}}` and reassigns the bead to
refinery; the overlay detects rebase beads (via `metadata.molecule_id`, with
`metadata.backup_ref` as fallback), preflights, performs the leased
force-push, and closes the bead. "Polecats never force-push to main" stays
absolute; the legitimate rebase tail lives in one auditable place.

## Conflict handling: one fresh iteration per conflict (check loop)

Fork commits represent goals, not literal implementations. When `git rebase`
halts on a kept commit because upstream shifted the surrounding code, the
*intent* still applies — a conflict is the next unit of work, not a failure.

The `rebase` step is a **check loop** (`[steps.check]`, formulas v2 §3.1):
the orchestrator runs the step, runs an exit-condition script when the
iteration closes, and while that script fails it appends another iteration —
each its own bead with a fresh agent session. Materializes as
`<wf>.rebase.spec` (spec), `<wf>.rebase.iteration.N` (work), and
`<wf>.rebase` (ralph control bead holding loop state).

`assets/scripts/rebase-check.sh` is the exit condition: it passes only when
the rebase is finished, the worktree clean, HEAD sits on
`metadata.rebase_onto_sha`, and `metadata.check_passed_sha` equals the live
HEAD. Exhausting `max_attempts` closes the control bead `gc.outcome=fail` —
and because nothing runs after that, the exit condition performs the keeper
handback itself on the last failing attempt: stamps
`aborted_at=rebase-loop-exhausted` on the work bead, reassigns it to
`requesting_keeper` with the failure tail in notes, and nudges. Prior
iterations remain as durable history; `metadata.conflict_resolutions`
accumulates one audit entry per resolved conflict.

The exit condition also appends one `metadata.iteration_timings` entry per
attempt: when the runtime minted the attempt, when a session picked it up,
when the iteration's own work ended, when the check ran, the session that ran
it, and the verdict with its reason. That is the loop's only cost measurement,
because the ralph condition env carries no duration of its own, and it is what
separates a loop resolving conflicts from one wedged on the same error every
attempt.

**Iterations must be pool-routed.** The runtime recycles the previous
iteration's worker session only when the attempt target is a pool. Sling this
formula at a pool, never at a named agent — a named target skips the recycle
and iteration N+1 inherits iteration N's context, losing the fresh-context
property this design exists for. The step declares no `assignee` (which
`[steps.check]` forbids anyway).

The rebase step never hands back mid-loop and never writes
`rebase_in_progress` / `pending_rework` (the retired v11 mechanism —
`mol-upstream-gc-rebase-rework` is kept for manual dispatch only). A conflict
the iteration genuinely cannot resolve is recorded as
`metadata.conflict_questions` — the iteration leaves the rebase in place and
never fakes a resolution; the loop then exhausts and the exit condition
routes the bead to the keeper carrying both `conflict_questions` and
`aborted_at=rebase-loop-exhausted`. No silent drops, no auto-resolution.

## Abort shape (workspace-setup, install, push)

All post-rebase abort paths share one keeper-routed shape, in this order:
reassign the bead to `requesting_keeper` (falling back to
`notify_recipient` only when no keeper was stamped), record the failure tail
in bead **notes** (durable even if mail fails), set `aborted_at`, **nudge the
keeper** — all before any mail. Mail to `notify_recipient` is a SECONDARY
backstop, never the primary signal. The keeper's prime sweep matches
`aborted_at` beads assigned to it. The keeper, not the operator's mail alias,
is the durable holder.

Variables:
  {{base_branch}}: The base branch to rebase on and compare against (e.g., main, integration/convoy-id) (default=main)
  {{build_command}}: Command to run build. From rig `formula_vars` or empty to skip. (default=)
  {{check_command}}: Post-rebase quality gate command. The default `make check` in gascity is fmt-check + lint + vet + test — the authoritative safety net for the kept set, since conflict resolutions are committed by `git rebase --continue` without the pre-commit hook. Operators can scope down (e.g. --var check_command='make test'); the default is intentionally the full gate. (default=make check)
  {{install_command}}: Command that rebuilds and installs the gc binary locally (default=make install)
  {{lint_command}}: Command to run linting. From rig `formula_vars` or empty to skip. (default=)
  {{notify_recipient}}: Mail target for completion and abort notifications (default=human)
  {{origin_remote}}: Git remote name pointing at the city's fork (default=origin)
  {{requesting_keeper}}: Keeper agent address (e.g., gascity/gascity-keeper.keeper) for abort handbacks. Optional; falls back to notify_recipient, but a keeper-aware operator should stamp metadata.requesting_keeper at dispatch. (default=)
  {{setup_command}}: Setup/install command (e.g., pnpm install). From rig `formula_vars` or empty to skip. (default=)
  {{test_command}}: Command to run tests. From rig `formula_vars` or empty to skip. (default=)
  {{typecheck_command}}: Type check command (e.g., tsc --noEmit). From rig `formula_vars` or empty to skip. (default=)
  {{upstream_branch}}: Branch to rebase onto and push back to (default=main)
  {{upstream_remote}}: Git remote name pointing at the upstream gascity repository (default=upstream)

Steps (13):
  ├── mol-upstream-gc-rebase.load-context: Load context and verify assignment
  ├── mol-upstream-gc-rebase.workspace-setup: Set up gascity worktree, fetch upstream, write safety backup ref [needs: mol-upstream-gc-rebase.load-context]
  ├── mol-upstream-gc-rebase.preflight-tests: Skip — rebase variant uses its own gates [needs: mol-upstream-gc-rebase.workspace-setup]
  ├── mol-upstream-gc-rebase.implement: Skip — replaced by survey + rebase steps [needs: mol-upstream-gc-rebase.preflight-tests]
  ├── mol-upstream-gc-rebase.self-review: Skip — replaced by the rebase check loop + install [needs: mol-upstream-gc-rebase.implement]
  ├── mol-upstream-gc-rebase.survey: Classify each divergent commit as drop-merged-upstream / drop-supplanted / keep [needs: mol-upstream-gc-rebase.self-review]
  ├── mol-upstream-gc-rebase.rebase.spec: Step spec for Rebase onto upstream, one conflict per iteration, until the gate is green (spec)
  ├── mol-upstream-gc-rebase.rebase.iteration.1: Rebase onto upstream, one conflict per iteration, until the gate is green [needs: mol-upstream-gc-rebase.survey]
  ├── mol-upstream-gc-rebase.rebase: Rebase onto upstream, one conflict per iteration, until the gate is green [needs: mol-upstream-gc-rebase.survey, mol-upstream-gc-rebase.rebase.iteration.1]
  ├── mol-upstream-gc-rebase.install: Rebuild and install gc from the rebased state [needs: mol-upstream-gc-rebase.rebase]
  ├── mol-upstream-gc-rebase.push: Push the rebased branch to origin (polecat-owned ref, no force on main) [needs: mol-upstream-gc-rebase.install]
  ├── mol-upstream-gc-rebase.notify-and-handoff: Mail the completion summary, append to bead notes, hand off to refinery [needs: mol-upstream-gc-rebase.push]
  └── mol-upstream-gc-rebase.workflow-finalize: Finalize workflow [needs: mol-upstream-gc-rebase.notify-and-handoff]
