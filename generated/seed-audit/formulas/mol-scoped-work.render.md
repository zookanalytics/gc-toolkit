Formula: mol-scoped-work
Description: Graph-first worktree lifecycle.

This is the built-in v2 workflow prototype for Gas City. It models work as an
explicit DAG with:

- a durable `body` scope bead
- explicit worktree setup and teardown
- first-class step beads that can be routed independently
- continuation metadata for same-session execution

Use this as the opt-in replacement for hierarchy-first single-session formulas.


Variables:
  {{base_branch}}: Base branch to branch from (default=main)
  {{build_command}}: Optional build command (default=)
  {{lint_command}}: Optional lint command (default=)
  {{setup_command}}: Optional setup command (install deps, bootstrap tools) (default=)
  {{test_command}}: Optional test command (default=)
  {{typecheck_command}}: Optional typecheck command (default=)

Steps (28):
  ├── mol-scoped-work.load-context.spec: Step spec for Load context and inspect the assignment (spec)
  ├── mol-scoped-work.load-context.attempt.1: Load context and inspect the assignment
  ├── mol-scoped-work.load-context: Load context and inspect the assignment [needs: mol-scoped-work.load-context.attempt.1]
  ├── mol-scoped-work.workspace-setup.spec: Step spec for Set up a worktree and branch (spec)
  ├── mol-scoped-work.workspace-setup.attempt.1: Set up a worktree and branch [needs: mol-scoped-work.load-context]
  ├── mol-scoped-work.workspace-setup: Set up a worktree and branch [needs: mol-scoped-work.load-context, mol-scoped-work.workspace-setup.attempt.1]
  ├── mol-scoped-work.preflight-tests.spec: Step spec for Run preflight checks on the base branch (spec)
  ├── mol-scoped-work.implement.spec: Step spec for Implement the requested change (spec)
  ├── mol-scoped-work.self-review.spec: Step spec for Review the diff and run verification (spec)
  ├── mol-scoped-work.submit.spec: Step spec for Finalize the work item (spec)
  ├── mol-scoped-work.cleanup-worktree.spec: Step spec for Clean up the worktree (spec)
  ├── mol-scoped-work.workspace-setup-scope-check: Finalize scope for Set up a worktree and branch [needs: mol-scoped-work.workspace-setup]
  ├── mol-scoped-work.preflight-tests.attempt.1: Run preflight checks on the base branch [needs: mol-scoped-work.workspace-setup-scope-check]
  ├── mol-scoped-work.preflight-tests: Run preflight checks on the base branch [needs: mol-scoped-work.workspace-setup-scope-check, mol-scoped-work.preflight-tests.attempt.1]
  ├── mol-scoped-work.preflight-tests-scope-check: Finalize scope for Run preflight checks on the base branch [needs: mol-scoped-work.preflight-tests]
  ├── mol-scoped-work.implement.attempt.1: Implement the requested change [needs: mol-scoped-work.preflight-tests-scope-check]
  ├── mol-scoped-work.implement: Implement the requested change [needs: mol-scoped-work.preflight-tests-scope-check, mol-scoped-work.implement.attempt.1]
  ├── mol-scoped-work.implement-scope-check: Finalize scope for Implement the requested change [needs: mol-scoped-work.implement]
  ├── mol-scoped-work.self-review.attempt.1: Review the diff and run verification [needs: mol-scoped-work.implement-scope-check]
  ├── mol-scoped-work.self-review: Review the diff and run verification [needs: mol-scoped-work.implement-scope-check, mol-scoped-work.self-review.attempt.1]
  ├── mol-scoped-work.self-review-scope-check: Finalize scope for Review the diff and run verification [needs: mol-scoped-work.self-review]
  ├── mol-scoped-work.submit.attempt.1: Finalize the work item [needs: mol-scoped-work.self-review-scope-check]
  ├── mol-scoped-work.submit: Finalize the work item [needs: mol-scoped-work.self-review-scope-check, mol-scoped-work.submit.attempt.1]
  ├── mol-scoped-work.body: Worktree body scope [needs: mol-scoped-work.workspace-setup, mol-scoped-work.preflight-tests, mol-scoped-work.implement, mol-scoped-work.self-review, mol-scoped-work.submit]
  ├── mol-scoped-work.cleanup-worktree.attempt.1: Clean up the worktree [needs: mol-scoped-work.body]
  ├── mol-scoped-work.cleanup-worktree: Clean up the worktree [needs: mol-scoped-work.body, mol-scoped-work.cleanup-worktree.attempt.1]
  ├── mol-scoped-work.submit-scope-check: Finalize scope for Finalize the work item [needs: mol-scoped-work.submit]
  └── mol-scoped-work.workflow-finalize: Finalize workflow [needs: mol-scoped-work.body, mol-scoped-work.submit-scope-check]
