Formula: mol-polecat-work
Description: Polecat work lifecycle — feature-branch variant.

## gc-toolkit MIRROR of the gastown formula of the same name

This file SHADOWS `gastown/formulas/mol-polecat-work.toml`: the pack search
order resolves `rigs/gc-toolkit/formulas` after `gastown/formulas`, so this
copy is what every polecat in the city actually runs. It was copied verbatim
from base on 2026-08-17 and then given two `submit-and-exit` deltas. Both are
listed in `docs/gascity-packs.md` §7a and executed by
`assets/scripts/submit-branch-gate.test.sh` — run that test after any
reconciliation against base, because taking base's `submit-and-exit` wholesale
silently restores both defects.

**Why the deltas exist.** `{{base_branch}}` answers two different questions in
this formula, and base's `submit-and-exit` treats them as one:

- **branch FROM** — what `workspace-setup` pours the worktree from and what
  `self-review` diffs against. On a rework this is the branch *under review*:
  the signoff dispatch slings the child with
  `--var base_branch=<reviewed branch>` on purpose, so the worktree has the
  PR-only files (tk-qqgeo).
- **merge INTO** — where the refinery lands the work. That is
  `metadata.target`, which the signoff already set to the real landing branch
  (`REVIEW_BASE`, normally `main`).

`{{base_branch}}` is the first. Base's `submit-and-exit` spends it on the
second, and separately rebuilds the branch name from a template as though
`metadata.branch` did not exist — contradicting its own `workspace-setup`,
which calls a pre-set `metadata.branch` authoritative. On a rework child both
misread the same way: the gate rejects the branch this formula just told the
polecat to check out, and the target write renders `target=<the branch being
pushed>`, a self-merge. Fixed in `submit-and-exit` steps 1 and 5 (tk-3yj8g).

Extends mol-polecat-base with feature-branch workspace setup and
refinery-based submission. The polecat creates a feature branch,
implements the work, then pushes and reassigns to the refinery for
merge review.

## Polecat Contract (Self-Cleaning Model)

1. Receive work (molecule poured with this formula, assigned to you)
2. Follow steps in order (read descriptions, execute, move to next)
3. Submit: push branch, set metadata on work bead, assign to refinery, exit
4. You are GONE — Refinery merges, closes the bead

**No MR beads.** Work beads flow directly: pool → polecat → refinery → closed.
The polecat sets `metadata.branch` and `metadata.target` on the work bead
and reassigns it to the refinery. The refinery merges and closes.

**NEVER CLOSE BEADS.** You must not run `bd close` or set status=closed.
Even if you believe the code is already merged, reassign to refinery —
only the refinery verifies merges and closes beads.
`{{base_branch}}` may come from the work bead's own `metadata.target` or
be inherited from a parent convoy with `metadata.target` set.

## Variables

| Variable | Source | Description |
|----------|--------|-------------|
| binding_prefix | import binding | Agent identity prefix for bound Gas Town imports. |
| affected_tests_command | rig `formula_vars` | Shell-safe command that reads `git diff --name-only origin/{{base_branch}}...HEAD` and runs the matching test subset. Empty = run full `test_command`. |

**Rejection-aware.** If the work bead has `metadata.branch` and
`metadata.rejection_reason`, a previous attempt was rejected by the
refinery. Resume the existing branch — don't redo all the work.

## Failure Modes

| Situation | Action |
|-----------|--------|
| Tests fail | Fix them. Do not proceed with failures. |
| Blocked on external | Mail Witness, mark yourself stuck |
| Context filling | `gc runtime request-restart` (blocks until controller kills you) |
| Unsure what to do | Mail Witness, don't guess |

Variables:
  {{affected_tests_command}}: Shell-safe affected-tests command. Must read `git diff --name-only origin/{{base_branch}}...HEAD` and run the matching test subset. From rig `formula_vars` or empty to run full test_command. (default=)
  {{base_branch}}: The base branch to rebase on and compare against (e.g., main, integration/convoy-id) (default=main)
  {{binding_prefix}}: Import binding prefix for gastown agent identities, including trailing dot when bound. (default=)
  {{build_command}}: Command to run build. From rig `formula_vars` or empty to skip. (default=)
  {{lint_command}}: Command to run linting. From rig `formula_vars` or empty to skip. (default=)
  {{setup_command}}: Setup/install command (e.g., pnpm install). From rig `formula_vars` or empty to skip. (default=)
  {{test_command}}: Command to run tests. From rig `formula_vars` or empty to skip. (default=)
  {{typecheck_command}}: Type check command (e.g., tsc --noEmit). From rig `formula_vars` or empty to skip. (default=)

Steps (7):
  ├── mol-polecat-work.load-context: Load context and verify assignment
  ├── mol-polecat-work.workspace-setup: Set up worktree and feature branch [needs: mol-polecat-work.load-context]
  ├── mol-polecat-work.preflight-tests: Verify pre-flights pass on base branch [needs: mol-polecat-work.workspace-setup]
  ├── mol-polecat-work.implement: Implement the solution [needs: mol-polecat-work.preflight-tests]
  ├── mol-polecat-work.self-review: Self-review and run tests (affected-aware) [needs: mol-polecat-work.implement]
  ├── mol-polecat-work.submit-and-exit: Submit work to refinery and exit [needs: mol-polecat-work.self-review]
  └── mol-polecat-work.workflow-finalize: Finalize workflow [needs: mol-polecat-work.submit-and-exit]
