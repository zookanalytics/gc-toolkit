Formula: mol-upstream-gc-sync
Description: Detect upstream-gascity drift in the vendored gastown pack. Read-only —
walks `agents/*/PROVENANCE.md`, asks the gascity rig what's changed since
each pinned commit, writes a markdown report into bead notes plus a
referenced file. No file mutation, no pin bumps (apply and pin-bump are
follow-up mols).

Extends `mol-polecat-base` for `load-context`, but replaces the
`implement / self-review` chain with a single `survey` step that drives
`tools/upstream-gc-sync.sh`, then a `report-and-close` step that persists
the output and closes the bead. Every abort path leaves the bead open,
reassigned to `{{notify_recipient}}` (or `human`), with the failure tail
in notes and `metadata.aborted_at` naming the step.

Variables:
  {{base_branch}}: The base branch to rebase on and compare against (e.g., main, integration/convoy-id) (default=main)
  {{build_command}}: Command to run build. From rig `formula_vars` or empty to skip. (default=)
  {{lint_command}}: Command to run linting. From rig `formula_vars` or empty to skip. (default=)
  {{notify_recipient}}: Optional mail address to notify with the report (e.g., human, gascity/gascity-keeper.keeper). Empty = skip mail. (default=)
  {{setup_command}}: Setup/install command (e.g., pnpm install). From rig `formula_vars` or empty to skip. (default=)
  {{sync_script}}: Drift-detector script path (relative to the pack root) (default=tools/upstream-gc-sync.sh)
  {{test_command}}: Command to run tests. From rig `formula_vars` or empty to skip. (default=)
  {{typecheck_command}}: Type check command (e.g., tsc --noEmit). From rig `formula_vars` or empty to skip. (default=)
  {{upstream_ref}}: Ref in the upstream rig to compare each pin against (default=origin/main)
  {{upstream_rig}}: Upstream rig name (resolved via 'gc rig list --json') (default=gascity)
  {{with_diff}}: If '1', the report includes per-agent unified diffs (default=0)

Steps (8):
  ├── mol-upstream-gc-sync.load-context: Load context and verify assignment
  ├── mol-upstream-gc-sync.workspace-setup: Set up gc-toolkit worktree (read-only — no branch needed) [needs: mol-upstream-gc-sync.load-context]
  ├── mol-upstream-gc-sync.preflight-tests: Skip — sync variant is read-only [needs: mol-upstream-gc-sync.workspace-setup]
  ├── mol-upstream-gc-sync.implement: Skip — replaced by survey step [needs: mol-upstream-gc-sync.preflight-tests]
  ├── mol-upstream-gc-sync.self-review: Skip — replaced by survey step [needs: mol-upstream-gc-sync.implement]
  ├── mol-upstream-gc-sync.survey: Run the drift-detector script and capture the report [needs: mol-upstream-gc-sync.workspace-setup]
  ├── mol-upstream-gc-sync.report-and-close: Append report to bead notes, optionally mail, close bead, exit [needs: mol-upstream-gc-sync.survey]
  └── mol-upstream-gc-sync.workflow-finalize: Finalize workflow [needs: mol-upstream-gc-sync.self-review, mol-upstream-gc-sync.report-and-close]
