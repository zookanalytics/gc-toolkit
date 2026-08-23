Formula: mol-upstream-gc-rebase-rework
Description: Rework a single conflicted kept commit during a gascity upstream rebase.

The `mol-upstream-gc-rebase` parent halts when `git rebase` cannot apply a
kept commit cleanly because upstream shifted the surrounding code. Auto-
resolving in favor of upstream (the v6 upstream-wins approach) silently
discards real work. Auto-failing back to the operator on every conflict
loses the value of agent dispatch. This formula is the middle path: a
focused polecat re-implements the commit's *intent* against the new
upstream layer in the rebase worktree, classifies the work it did, and
the parent rebase polecat acts on the classification.

The rework polecat:

1. Shares the parent's mid-rebase worktree (read from
   `metadata.work_dir`). The `.git/rebase-merge/` state survives drain
   and is left intact for the parent polecat to resume.
2. Reads the captured conflict context (`metadata.context_file`, plus the
   commit body and adjacent upstream diffs prepared at dispatch).
3. Classifies the work into one of four outcomes:
   - **mechanical** — intent preserved, only anchor/surrounding code
     shifted. Apply the equivalent change against the new layer. No
     design judgment required.
   - **dropped-absorbed** — upstream already provides this behavior or
     supersedes it. Skip the commit; the parent polecat will
     `git rebase --skip`.
   - **judgment-required** — rework needed a design call (different API
     surface, deprecated dependency, behavior choice). Do the rework
     AND self-report so the parent dispatches a review polecat before
     `git rebase --continue`.
   - **infeasible** — the rework cannot be done from this polecat's
     context. Hand back to the requesting keeper with a question for
     the operator.
4. Commits the rework onto the rebase HEAD (for `mechanical` and
   `judgment-required`); leaves the index clean (for `dropped-absorbed`);
   neither commits nor resolves conflicts (for `infeasible`).
5. Sets `metadata.classification` (and `metadata.judgment_summary` when
   applicable) on the rework bead, closes the rework bead, nudges the
   requesting keeper so the parent rebase mol can be re-poured.

Extends `mol-polecat-base` for `load-context` only — the rest of the
polecat-work chain (workspace-setup that creates a new worktree,
preflight, implement, self-review, submit-to-refinery) does not apply.
We share the parent's worktree and we do not push a feature branch.

## Variables

| Variable | Required | Description |
|----------|----------|-------------|
| issue | yes | The rework bead this polecat is working on |
| rebase_bead | yes (set by parent rebase polecat as metadata.rebase_bead) | The parent rebase bead |
| requesting_keeper | yes (set by parent as metadata.requesting_keeper) | Keeper to nudge on completion |

The rework bead must carry the following metadata at dispatch (stamped by
the parent rebase polecat):

| Field | Description |
|-------|-------------|
| work_dir | Shared rebase worktree path (parent's metadata.work_dir) |
| rebase_bead | Parent rebase bead ID |
| requesting_keeper | Keeper agent address for handback nudge |
| commit_sha | The conflicted kept commit's SHA |
| commit_subject | The conflicted kept commit's subject (for human-readable context) |
| conflicted_files | JSON array of file paths the rebase halted on |
| context_file | Path inside the worktree to the markdown context dump |

## Failure modes

| Step | Failure handling |
|------|------------------|
| workspace-setup | Worktree missing or wrong commit mid-rebase → set `metadata.classification=infeasible`, set `metadata.infeasible_reason`, close, nudge keeper. The parent rebase polecat will see infeasible on re-entry and hand the rebase bead back to the keeper. |
| classify-and-rework | Operator-relevant judgment is fine (that's the `judgment-required` classification) — only mark `infeasible` when the polecat genuinely cannot proceed (missing dependencies, undecidable scope, context exhausted) |

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
