Formula: mol-upstream-gc-rebase-rework
Description: Rework a single conflicted kept commit during a gascity upstream rebase
(dispatched by `mol-upstream-gc-rebase` v11 mid-rebase; v12 resolves
conflicts inline and does not use this formula).

A focused polecat re-implements the conflicted commit's *intent* against
the new upstream layer in the parent's shared mid-rebase worktree
(`metadata.work_dir` — `.git/rebase-merge/` state is left intact for the
parent to resume), classifies the outcome, and the parent acts on the
classification:

- **mechanical** — intent transfers cleanly; apply and commit.
- **dropped-absorbed** — upstream provides or supersedes it; leave clean,
  parent will `git rebase --skip`.
- **judgment-required** — rework needed a design call; commit AND
  self-report so the parent dispatches a review polecat first.
- **infeasible** — cannot proceed from this context; hand back to the
  keeper with a question for the operator.

Extends `mol-polecat-base` for `load-context` only — the rest of the
polecat-work chain does not apply: this mol shares the parent's worktree
and pushes no branch. Dispatch metadata stamped by the parent: `work_dir`,
`rebase_bead`, `requesting_keeper`, `commit_sha`, `commit_subject`,
`conflicted_files`, `context_file`. Any setup failure (worktree missing,
mid-rebase state unreadable, commit drift) resolves to
`classification=infeasible` with `infeasible_reason`, close, nudge keeper.

Required vars:
  {{issue}}: The rework bead assigned to this polecat
  {{rebase_bead}}: The parent rebase bead (also stamped as metadata.rebase_bead on the rework bead)
  {{requesting_keeper}}: Keeper agent address to nudge on completion (also stamped as metadata.requesting_keeper)

Optional vars:
  {{base_branch}}: The base branch to rebase on and compare against (e.g., main, integration/convoy-id) (default=main)
  {{build_command}}: Command to run build. From rig `formula_vars` or empty to skip. (default=)
  {{lint_command}}: Command to run linting. From rig `formula_vars` or empty to skip. (default=)
  {{setup_command}}: Setup/install command (e.g., pnpm install). From rig `formula_vars` or empty to skip. (default=)
  {{test_command}}: Command to run tests. From rig `formula_vars` or empty to skip. (default=)
  {{typecheck_command}}: Type check command (e.g., tsc --noEmit). From rig `formula_vars` or empty to skip. (default=)

Steps (7):
  ├── mol-upstream-gc-rebase-rework.load-context: Load context and verify assignment
  ├── mol-upstream-gc-rebase-rework.workspace-setup: Enter the shared rebase worktree and verify the mid-rebase target commit [needs: mol-upstream-gc-rebase-rework.load-context]
  ├── mol-upstream-gc-rebase-rework.preflight-tests: Skip — rework polecat operates inside a mid-rebase worktree [needs: mol-upstream-gc-rebase-rework.workspace-setup]
  ├── mol-upstream-gc-rebase-rework.implement: Skip — replaced by classify-and-rework [needs: mol-upstream-gc-rebase-rework.preflight-tests]
  ├── mol-upstream-gc-rebase-rework.self-review: Skip — replaced by classify-and-rework's commit shape [needs: mol-upstream-gc-rebase-rework.implement]
  ├── mol-upstream-gc-rebase-rework.classify-and-rework: Read the conflict context, classify, do the rework (or skip), commit [needs: mol-upstream-gc-rebase-rework.self-review]
  └── mol-upstream-gc-rebase-rework.workflow-finalize: Finalize workflow [needs: mol-upstream-gc-rebase-rework.classify-and-rework]
