Formula: mol-upstream-gc-rebase
Description: Rebase the gascity rig's `origin/main` onto `upstream/main`, drop already-
landed-or-supplanted local commits, run tests, install, push the working
branch (`rebase/{{issue}}`) to origin, and hand off to refinery for the
force-push to `{{upstream_branch}}`.

Extends `mol-polecat-base` for the standard polecat lifecycle entry points
(load-context, workspace-setup) but uses its own gating steps in place of
the implement / self-review pair — the work isn't a feature implementation,
it's a controlled rebase with a verdict-keeping survey.

**Force-push ownership (v7+):** The terminal force-push that lands the
rebased history onto `{{upstream_branch}}` is performed by the
rig-scoped refinery via the `gascity-keeper` sub-pack's
`refinery-rebase-handling` overlay, not by this polecat. The polecat
pushes its rebased commits to the polecat-owned ref
`refs/heads/rebase/{{issue}}` and reassigns the bead to refinery; the
refinery overlay detects the rebase bead (via `metadata.molecule_id`
matching `mol-upstream-gc-rebase*`, with `metadata.backup_ref` as a
fallback signal), runs preflight against the rebased branch, performs
the safe force-push to `{{upstream_branch}}` (see
`refinery-rebase-handling` for the exact lease form), and closes
the bead. This keeps the absolute "polecats never force-push to
`main`" rule intact while authorising the legitimate rebase tail in
one auditable place (refinery + rig-scoped overlay).

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| upstream_remote | upstream | Git remote name pointing at gastownhall/gascity |
| origin_remote | origin | Git remote name pointing at the city's fork |
| upstream_branch | main | Branch to rebase onto and push back to |
| check_command | make check | Post-rebase quality gate (fmt-check + lint + vet + test in gascity) |
| install_command | make install | Local rebuild of `gc` into `$INSTALL_DIR` |
| notify_recipient | human | Mail target on completion / abort |
| requesting_keeper | (empty) | Keeper address for the install/push abort handbacks; falls back to notify_recipient if unset |

## Conflict handling: one fresh iteration per conflict (check loop)

Our fork commits represent goals/intents, not literal implementations.
When `git rebase` halts on a kept commit because upstream shifted the
surrounding code, the *intent* still applies even though the diff does
not — so a conflict is not a failure, it is the next unit of work.

The `rebase` step is a **check loop** (`[steps.check]`, formulas v2
§3.1). The orchestrator runs the step, runs an exit-condition script when
the iteration closes, and while that script fails it appends another
iteration. Each iteration is its own bead with its own agent session, so
every conflict is met with fresh context. The step materializes as:

| Bead | Kind | Role |
|------|------|------|
| `<wf>.rebase.spec` | `spec` | the serialized step definition (stable prompt) |
| `<wf>.rebase.iteration.N` | (work) | resume the worktree, advance the rebase, run the gate |
| `<wf>.rebase` | `ralph` | control bead; blocks on the live iteration, holds loop state |

`assets/scripts/rebase-check.sh` is the exit condition. It passes only
when the rebase is finished, the worktree is clean, HEAD sits on top of
the upstream tip recorded in `metadata.rebase_onto_sha`, and
`metadata.check_passed_sha` equals the live HEAD. Anything else fails and
the next iteration starts. Exhausting `max_attempts` closes the control
bead with `gc.outcome = fail` and leaves `install` / `push` blocked — and
because nothing runs after that, the exit condition performs the keeper
handback itself on the last failing attempt: it stamps
`aborted_at=rebase-loop-exhausted` on the work bead, reassigns it to
`requesting_keeper` with the failure tail in the notes, and nudges. A
control bead that closes `fail` without a keeper-visible work bead is the
stranded state this rewrite exists to remove, so the handback is part of
the exit condition rather than a step an exhausted loop never reaches.

Prior iterations remain as durable history — retries append, they never
reopen. `metadata.conflict_resolutions` still accumulates one audit entry
per resolved conflict.

**Iterations must be pool-routed.** The runtime recycles the previous
iteration's worker session before appending the next one, but only when
the attempt target is a pool (`beadUsesMetadataPoolRouteWithConfig` in
`internal/dispatch/control.go`, called from `internal/dispatch/retry.go`).
Sling this formula at a pool, never at a named agent: a named target
skips the recycle, iteration N+1 lands in the session that ran iteration
N with iteration N still in its context window, and the fresh-context
property this design exists for is lost. The step declares no `assignee`
— which `[steps.check]` forbids anyway.

**This replaces the v11 rework-polecat dispatch.** v11 hand-rolled the
same loop out of bead-filing, metadata flags, and re-pour: capture the
conflict, file a rework bead, sling a rework polecat under
`mol-upstream-gc-rebase-rework`, set `metadata.rebase_in_progress` +
`metadata.pending_rework`, hand the bead back to the keeper and drain,
then read the classification on re-entry. Every known defect in this area
was a defect in that mechanism rather than in rebasing — re-pour was a
fallback that could not resume a paused rebase and burned ~12 steps, a
handback had to clear the assignee or the bead went invisible to
`scale_check`, and an open rework required a drain before re-pour. The
loop state now lives in the control bead and the exit condition is a
script, so none of those states exist. `mol-upstream-gc-rebase-rework` is
kept for manual dispatch, but this formula no longer slings it.

The v6 upstream-wins/`--ours` mechanism (tk-gzat2) that silently dropped
local hunks remains gone: no silent drops, no auto-resolution.

## Failure modes

| Step | Failure handling |
|------|------------------|
| survey | LLM judgment can be wrong; record verdicts on the bead and proceed — the rebase step's patch-id check is the safety net for `drop-merged-upstream` |
| rebase | A conflict is the next iteration, not a failure. The step's own exit condition (`rebase-check.sh`) is the safety net for "we accepted a resolution that broke the kept set": it will not pass until `{{check_command}}` is green at the live HEAD, so a bad resolution simply fails the gate and buys another iteration. `metadata.backup_ref` keeps any state recoverable. Exhausting `max_attempts` closes the control bead `gc.outcome=fail`; the exit condition hands the work bead back to the keeper on that last failing attempt (`aborted_at=rebase-loop-exhausted`, reassigned, failure tail in notes, nudge), so the keeper's ordinary `aborted_at` sweep surfaces it. |
| install | Keeper handback (`aborted_at=install`, reassign to `requesting_keeper`, tail in notes) + keeper nudge first; mail secondary. Bead stays open. |
| push | Push of `HEAD:rebase/{{issue}}` is fast-forward on the polecat-owned ref — failures here are auth/network/ref-protection, NOT a race against `{{upstream_branch}}`. Keeper handback (`aborted_at=push`, reassign to `requesting_keeper`, context in notes) + keeper nudge first; mail secondary. Race-loss against `{{upstream_branch}}` is detected and escalated by refinery via the overlay's `--force-with-lease` lease, not by this step. |

The post-rebase **abort** paths (install, push) — and the
workspace-setup backup-ref refusal — share the same keeper-routed shape: reassign the bead to the requesting
keeper (`requesting_keeper`, falling back to `notify_recipient` only when
no keeper was stamped), record the failure tail in the bead **notes**
(durable even if mail fails), set `aborted_at`, and **nudge the keeper**,
all **before** any mail. Mail to `notify_recipient` is a SECONDARY backstop
only — never the primary operator signal. The keeper's prime sweep matches
`aborted_at` beads assigned to it, so a human-needing abort surfaces on the
next operator engagement with the keeper regardless of whether mail
arrived. We do not assign the operator's mail alias as the bead owner: the
keeper is the durable holder and the operator's contact point (the keeper
is the single upstream front-door; see gastownhall/gascity#2082 alignment).

The rebase step no longer hands back mid-loop. v11's rework-dispatch
handback (`metadata.rebase_in_progress=true` + `metadata.pending_rework` +
reassignment to the keeper, worktree parked mid-rebase awaiting a re-pour)
is gone: the loop keeps the worktree and resumes itself, so there is
nothing for the keeper to re-pour. Those two metadata keys are no longer
written by this formula. The one handback the rebase step still performs is
at the END of the loop, described above: `aborted_at=rebase-loop-exhausted`,
written by the exit condition, not by an iteration.

A conflict the iteration genuinely cannot resolve uses the existing
`metadata.conflict_questions` shape — the iteration records the question,
leaves the rebase where it is, and does NOT fake a resolution. The loop
then exhausts its budget, the control bead closes `gc.outcome=fail`, and
the exit condition routes the work bead to the keeper carrying both
`conflict_questions` and `aborted_at=rebase-loop-exhausted`. The keeper's
operator conversation handles `conflict_questions` as before; what changed
is that it now reliably reaches the keeper's hook instead of depending on
an agent that has already stopped running.

Variables:
  {{base_branch}}: The base branch to rebase on and compare against (e.g., main, integration/convoy-id) (default=main)
  {{build_command}}: Command to run build. From rig `formula_vars` or empty to skip. (default=)
  {{check_command}}: Post-rebase quality gate command. The default `make check` in gascity is `fmt-check lint vet test` — running the full Go pipeline on the rebased tip. The wider gate is the authoritative safety net for the kept set, since conflict resolutions are committed by `git rebase --continue` and the gascity pre-commit hook (which covers the same surfaces) does not run on them. Operators can override (e.g., `--var check_command='make test'` to scope down) but the default is intentionally the full gate. (default=make check)
  {{install_command}}: Command that rebuilds and installs the gc binary locally (default=make install)
  {{lint_command}}: Command to run linting. From rig `formula_vars` or empty to skip. (default=)
  {{notify_recipient}}: Mail target for completion and abort notifications (default=human)
  {{origin_remote}}: Git remote name pointing at the city's fork (default=origin)
  {{requesting_keeper}}: Keeper agent address (e.g., gascity/gascity-keeper.keeper) for the rework-dispatch handback. Optional; the rebase step falls back to notify_recipient if unset, but a keeper-aware operator should stamp metadata.requesting_keeper at dispatch so the cooperative-handback path lands cleanly. (default=)
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
