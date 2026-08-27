Formula: mol-polecat-commit
Description: Polecat direct-commit variant — commits directly to base_branch.

Extends mol-polecat-base with a simplified workspace setup (worktree on
base_branch, no feature branch) and direct commit+push instead of refinery
submission. Designed for small installations where merge review is
unnecessary.

## Polecat Contract (Direct-Commit Model)

1. Receive work (molecule poured with this formula, assigned to you)
2. Follow steps in order (read descriptions, execute, move to next)
3. Commit to base_branch, push, close bead, exit
4. You are GONE — no refinery step needed

**No feature branch.** Work is committed directly to base_branch.
Push conflicts are handled by fetch + rebase + retry (up to 3 times).

## Failure Modes

| Situation | Action |
|-----------|--------|
| Tests fail | Fix them. Do not proceed with failures. |
| Push conflict (3 retries exhausted) | Mail Witness, mark yourself stuck |
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
  ├── mol-polecat-commit.load-context: Load context and verify assignment
  ├── mol-polecat-commit.workspace-setup: Set up worktree on base branch [needs: mol-polecat-commit.load-context]
  ├── mol-polecat-commit.preflight-tests: Verify pre-flights pass on base branch [needs: mol-polecat-commit.workspace-setup]
  ├── mol-polecat-commit.implement: Implement the solution [needs: mol-polecat-commit.preflight-tests]
  ├── mol-polecat-commit.self-review: Self-review and run tests [needs: mol-polecat-commit.implement]
  ├── mol-polecat-commit.commit-and-push: Commit to base branch, push, and exit [needs: mol-polecat-commit.self-review]
  └── mol-polecat-commit.workflow-finalize: Finalize workflow [needs: mol-polecat-commit.commit-and-push]
