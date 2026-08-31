Formula: mol-upstream-gc-pr-prep
Description: Prepare an upstream pull request from one or more local-fork commits. An
ordered batch is cherry-picked onto a single branch and lands as one combined
PR draft; N=1 is the single-commit case. Mechanical work through
`push-branch`, then `prepare-pr-handoff` drafts the PR title/body (and an
optional issue draft), then `handback-to-keeper` re-routes the bead to the
requesting keeper for the conversational tail.

PR creation itself is operator-gated and currently blocked at the city level —
this mol stops at branch push + draft-on-bead. The keeper (or operator) decides
when to run the assembled `gh pr create` command.

Extends `mol-polecat-base` for load-context but replaces the implement /
self-review chain with cherry-pick / scrub / test / push / draft / handback.
Every abort path (cherry-pick conflict, test failure, push race) mails the
keeper + operator and hands the bead back open, assigned and routed to the
keeper — never stranded `in_progress` on the drained session.

Required vars:
  {{commit_sha}}: Whitespace-separated, ORDERED list of one-or-more local commits on origin/main to extract for upstream submission. Apply order is topological — old→new, as the commits sit on origin/main. A single SHA (N=1) is the original single-commit behavior.
  {{requesting_keeper}}: Keeper agent address (e.g., gascity/gascity-keeper.keeper) the bead returns to after prep

Optional vars:
  {{base_branch}}: The base branch to rebase on and compare against (e.g., main, integration/convoy-id) (default=main)
  {{branch_name}}: Explicit name for the assembled PR branch. Empty (default): a single SHA yields upstream-pr/<short-sha>, multiple SHAs yield upstream-pr/<issue> (stable + unique). Set: used verbatim, e.g. upstream-pr/test-env-isolation. (default=)
  {{build_command}}: Command to run build. From rig `formula_vars` or empty to skip. (default=)
  {{lint_command}}: Command to run linting. From rig `formula_vars` or empty to skip. (default=)
  {{origin_remote}}: Git remote name pointing at the city's fork (default=origin)
  {{setup_command}}: Setup/install command (e.g., pnpm install). From rig `formula_vars` or empty to skip. (default=)
  {{test_command}}: Test command run after cherry-pick + scrub (default=make test)
  {{typecheck_command}}: Type check command (e.g., tsc --noEmit). From rig `formula_vars` or empty to skip. (default=)
  {{upstream_branch}}: Branch the eventual upstream PR will target (default=main)
  {{upstream_remote}}: Git remote name pointing at the upstream gascity repository (default=upstream)

Steps (12):
  ├── mol-upstream-gc-pr-prep.load-context: Load context and verify assignment
  ├── mol-upstream-gc-pr-prep.workspace-setup: Set up gascity worktree branched off upstream [needs: mol-upstream-gc-pr-prep.load-context]
  ├── mol-upstream-gc-pr-prep.preflight-tests: Skip — pr-prep variant uses its own gates [needs: mol-upstream-gc-pr-prep.workspace-setup]
  ├── mol-upstream-gc-pr-prep.implement: Skip — replaced by cherry-pick + scrub-commit-message steps [needs: mol-upstream-gc-pr-prep.preflight-tests]
  ├── mol-upstream-gc-pr-prep.self-review: Skip — replaced by test + prepare-pr-handoff steps [needs: mol-upstream-gc-pr-prep.implement]
  ├── mol-upstream-gc-pr-prep.cherry-pick: Cherry-pick the ordered batch onto upstream, scrubbing each commit [needs: mol-upstream-gc-pr-prep.self-review]
  ├── mol-upstream-gc-pr-prep.scrub-commit-message: Persist the combined scrub diff (scrub applied per-commit in cherry-pick) [needs: mol-upstream-gc-pr-prep.cherry-pick]
  ├── mol-upstream-gc-pr-prep.test: Run the test suite on the cherry-picked branch [needs: mol-upstream-gc-pr-prep.scrub-commit-message]
  ├── mol-upstream-gc-pr-prep.push-branch: Push the prepped branch to origin [needs: mol-upstream-gc-pr-prep.test]
  ├── mol-upstream-gc-pr-prep.prepare-pr-handoff: Draft PR title/body, optional issue, and gh commands [needs: mol-upstream-gc-pr-prep.push-branch]
  ├── mol-upstream-gc-pr-prep.handback-to-keeper: Reassign the bead to the keeper, nudge, mail backstop [needs: mol-upstream-gc-pr-prep.prepare-pr-handoff]
  └── mol-upstream-gc-pr-prep.workflow-finalize: Finalize workflow [needs: mol-upstream-gc-pr-prep.handback-to-keeper]
