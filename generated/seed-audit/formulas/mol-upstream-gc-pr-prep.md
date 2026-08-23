Formula: mol-upstream-gc-pr-prep
Description: Prepare an upstream pull request from one or more local-fork commits. An
ordered batch is cherry-picked onto a single branch and lands as one combined
PR draft; N=1 is the original single-commit behavior. Mechanical work through
`push-branch`, then a `prepare-pr-handoff` step that drafts the PR title/body
(and an optional issue draft), then a `handback-to-keeper` step that re-routes
the bead to the requesting keeper for the conversational tail.

PR creation itself is operator-gated and currently blocked at the city level —
this mol stops at branch push + draft-on-bead. The keeper (or operator) decides
when and whether to run the assembled `gh pr create` command.

Extends `mol-polecat-base` for load-context but replaces the implement /
self-review chain with the cherry-pick / scrub / test / push / draft / handback
sequence below.

## Variables

| Variable | Required | Description |
|----------|----------|-------------|
| commit_sha | yes (set by keeper as `metadata.commit_sha`) | ordered, whitespace-separated list of one-or-more local commits to extract (old→new; N=1 = single-commit) |
| branch_name | no (set by keeper as `metadata.branch_name`) | explicit PR branch name; empty → `upstream-pr/<short-sha>` (N=1) or `upstream-pr/<issue>` (batch) |
| upstream_remote | no (default `upstream`) | upstream remote name |
| origin_remote | no (default `origin`) | origin remote name |
| upstream_branch | no (default `main`) | branch this PR will target |
| test_command | no (default `make test`) | post-cherry-pick test command |
| requesting_keeper | yes (set by keeper as `metadata.requesting_keeper`) | who to hand back to |

## Failure modes

| Step | Failure handling |
|------|------------------|
| cherry-pick | A conflict on any commit halts the chain; records which `conflict_sha`; resets the branch to the upstream base (no partial branch stranded); mails keeper + operator; hands the bead back to the keeper |
| scrub-commit-message | No-op marker — the scrub is applied per-commit inside the cherry-pick loop; this step persists the combined `scrub_diff` covering every commit |
| test | Failure mails keeper + operator; bead stays open (operator decides whether to investigate or abandon) |
| push-branch | If origin already has the branch and rejects, retry with `--force-with-lease`; if that also rejects, treat as race |
| prepare-pr-handoff | LLM judgment — record `issue_advice` even when no |
| handback-to-keeper | Reassign + nudge; the keeper's prime sweeps for `metadata.suggested_pr_title` |

Required vars:
  {{commit_sha}}: Whitespace-separated, ORDERED list of one-or-more local commits on origin/main to extract for upstream submission. Apply order is topological — old→new, as the commits sit on origin/main. A single SHA (N=1) is the original single-commit behavior.
  {{requesting_keeper}}: Keeper agent address (e.g., gascity/gascity-keeper.keeper) the bead returns to after prep

Optional vars:
  {{base_branch}}: The base branch to rebase on and compare against (e.g., main, integration/convoy-id) (default=main)
  {{branch_name}}: Explicit name for the assembled PR branch. Empty (default): a single SHA yields upstream-pr/<short-sha> (today's behavior), multiple SHAs yield upstream-pr/<issue> (stable + unique). Set: used verbatim, e.g. upstream-pr/test-env-isolation. (default=)
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
