Formula: mol-polecat-report
Description: Polecat report-only variant — investigates an issue and writes findings
as bead notes, without creating a branch or opening a pull request.

Extends mol-polecat-base with a lightweight workspace (no git checkout, no
isolated worktree) and a write-report terminal step instead of commit+push.
Designed for tasks that produce analysis, recommendations, or investigation
results — not code changes.

## Polecat Contract (Report-Only Model)

1. Receive work (molecule poured with this formula, assigned to you)
2. Follow steps in order (read descriptions, execute, move to next)
3. Write findings to bead notes, close bead, exit
4. You are GONE — no branch, no PR, no push

**No code changes.** Investigation results land as bead notes. Zero calls
to `git push` or `gh pr create`.

## Failure Modes

| Situation | Action |
|-----------|--------|
| Investigation blocked | Mail Witness, mark yourself stuck |
| Blocked on external | Mail Witness, mark yourself stuck |
| Context filling | `gc runtime request-restart` (blocks until controller kills you) |
| Unsure what to do | Mail Witness, don't guess |

Variables:
  {{base_branch}}: The base branch to rebase on and compare against (e.g., main, integration/convoy-id) (default=main)
  {{build_command}}: Command to run build. From rig `formula_vars` or empty to skip. (default=)
  {{lint_command}}: Command to run linting. From rig `formula_vars` or empty to skip. (default=)
  {{setup_command}}: Setup/install command (e.g., pnpm install). From rig `formula_vars` or empty to skip. (default=)
  {{test_command}}: Command to run tests. From rig `formula_vars` or empty to skip. (default=)
  {{typecheck_command}}: Type check command (e.g., tsc --noEmit). From rig `formula_vars` or empty to skip. (default=)

Steps (7):
  ├── mol-polecat-report.load-context: Load context and verify assignment
  ├── mol-polecat-report.workspace-setup: Verify assignment (report-only, no worktree) [needs: mol-polecat-report.load-context]
  ├── mol-polecat-report.preflight-tests: Skip pre-flights (no code changes) [needs: mol-polecat-report.workspace-setup]
  ├── mol-polecat-report.implement: Investigate (no code changes) [needs: mol-polecat-report.preflight-tests]
  ├── mol-polecat-report.self-review: Self-review: verify investigation is complete [needs: mol-polecat-report.implement]
  ├── mol-polecat-report.write-report: Write report to bead notes and close [needs: mol-polecat-report.self-review]
  └── mol-polecat-report.workflow-finalize: Finalize workflow [needs: mol-polecat-report.write-report]
