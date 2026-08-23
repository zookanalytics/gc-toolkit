Formula: mol-polecat-base
Description: Polecat base formula — shared steps for all polecat work variants.

This formula defines the common lifecycle steps that every polecat variant
shares: loading context, workspace setup (placeholder), preflight tests,
implementation, and self-review. Variant formulas extend this base and
override workspace-setup with their specific branching/worktree strategy,
then add a terminal step (submit, commit, etc).

## Variables

| Variable | Source | Description |
|----------|--------|-------------|
| convoy_id | runtime | Input convoy tracking the single work bead |
| base_branch | caller | Base branch to rebase on (default: main) |
| setup_command | rig `formula_vars` | Setup/install command. Empty = skip. |
| typecheck_command | rig `formula_vars` | Type check command. Empty = skip. |
| test_command | rig `formula_vars` | Test command. Empty = skip. |
| lint_command | rig `formula_vars` | Lint command. Empty = skip. |
| build_command | rig `formula_vars` | Build command. Empty = skip. |

Steps run in independent shell contexts, so each step that needs the work
bead re-derives it from the input convoy:

```bash
CONVOY_STATUS=$(gc convoy status {{convoy_id}} --json)
WORK_BEAD_ID=$(printf '%s' "$CONVOY_STATUS" | jq -r 'if (.children | length) == 1 then .children[0].id else empty end')
```

Variables:
  {{base_branch}}: The base branch to rebase on and compare against (e.g., main, integration/convoy-id) (default=main)
  {{build_command}}: Command to run build. From rig `formula_vars` or empty to skip. (default=)
  {{lint_command}}: Command to run linting. From rig `formula_vars` or empty to skip. (default=)
  {{setup_command}}: Setup/install command (e.g., pnpm install). From rig `formula_vars` or empty to skip. (default=)
  {{test_command}}: Command to run tests. From rig `formula_vars` or empty to skip. (default=)
  {{typecheck_command}}: Type check command (e.g., tsc --noEmit). From rig `formula_vars` or empty to skip. (default=)

Steps (6):
  ├── mol-polecat-base.load-context: Load context and verify assignment
  ├── mol-polecat-base.workspace-setup: Set up workspace (override in variant formulas) [needs: mol-polecat-base.load-context]
  ├── mol-polecat-base.preflight-tests: Verify pre-flights pass on base branch [needs: mol-polecat-base.workspace-setup]
  ├── mol-polecat-base.implement: Implement the solution [needs: mol-polecat-base.preflight-tests]
  ├── mol-polecat-base.self-review: Self-review and run tests [needs: mol-polecat-base.implement]
  └── mol-polecat-base.workflow-finalize: Finalize workflow [needs: mol-polecat-base.self-review]
