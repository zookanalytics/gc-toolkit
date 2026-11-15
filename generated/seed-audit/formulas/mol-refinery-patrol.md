Formula: mol-refinery-patrol
Description: Refinery patrol loop, on Gas Town's steps. Poured as a root-only wisp:

  gc bd mol wisp mol-refinery-patrol --root-only --var target_branch={{target_branch}} --var rig_name={{rig_name}} --var binding_prefix={{binding_prefix}}
  gc bd update $WISP --assignee=$GC_AGENT

Each wisp is ONE iteration: take one work bead assigned to you, bring its
branch current with its target by merge, run the rig's checks, then land it,
publish its PR or send it back, pour the next wisp and burn this one. Steps are
not materialized; read each step as you reach it. On a crash, re-derive where
you were from git and bead state.

Work beads flow directly: a polecat sets `branch` and `target` on its work
bead and assigns it to you. Every step makes one call to a tested pack script
and passes it the bead it acts for; each script refuses a bead whose branch is
not the one checked out in your tree for it (`refinery-lib.sh`). Resolve the
scripts at shell runtime, since formula bodies get no {{.ConfigDir}}:
`"$(b='{{binding_prefix}}'; gc "${b%.}" scripts-dir)/<script>"`.

The merge strategy is the bead's `merge_strategy`: `direct` lands by a
fast-forward push, and `mr` publishes a pull request. On a rig whose
`pending_through_merge` formula var is "true", the PR's bead stays open on Gas
Town's pending-through-merge record until the landing order (orders/
pr-reconcile.toml) verifies its merge; on any other rig the merge cadence
(the refinery-reconcile order) opens and merges it. Neither is yours to run:
docs/refinery-merge-cadence.md.

Variables:
  {{binding_prefix}}: Agent identity prefix with trailing dot. Non-empty default on purpose: this patrol sends a bead back to the polecat pool, and an empty prefix names <rig>/polecat instead of <rig>/gc-toolkit.polecat, which no pool claims. (default=gc-toolkit.)
  {{build_command}}: Build command. Empty = skip. (default=)
  {{check_set}}: The merge cadence's gating check set, stamped on a bead the old path parks for the cadence: a comma list of checks, each a lane that must derive green before merge.sh lands the PR. 'none' is stamped as itself, and an empty value recovers this default. Read only while pending_through_merge is unset. (default=correctness,triage)
  {{default_merge_strategy}}: The strategy for a bead that names none: 'direct' lands by a fast-forward push, 'mr' publishes a PR. Whatever this says, a bead that would land direct on the rig's default branch takes mr, so the default branch takes work only through a PR (docs/warrants.md). The merge-push step reads the rig's value, else this default. (default=direct)
  {{delete_merged_branches}}: Delete a branch from origin once its direct landing is recorded. (default=true)
  {{lint_command}}: Lint command. Empty = skip. (default=)
  {{pending_through_merge}}: Whether the rig is on the new path: 'true' has the merge-push step publish an mr bead's PR and record it pending until the landing order verifies its merge. Any other value keeps the old path, where the bead parks for the merge cadence. A rig sets it in its [rigs.formula_vars] at its cutover, and the merge-push step reads the rig's value. (default=false)
  {{rig_name}}: Rig this patrol serves; injected by the pour and forwarded by next-iteration. Declared so the {{rig_name}} token in the pour command resolves. (default=)
  {{run_tests}}: Whether the gate runs test_command. (default=true)
  {{setup_command}}: Setup/install command. Empty = skip. (default=)
  {{target_branch}}: The rig's default branch, which a bead with no target lands on. (default=main)
  {{test_command}}: Test command (when run_tests is true). (default=)
  {{typecheck_command}}: Type check command. Empty = skip. (default=)

Steps (10):
  ├── mol-refinery-patrol.validate-identity: Validate canonical agent identity
  ├── mol-refinery-patrol.check-inbox: Check mail [needs: mol-refinery-patrol.validate-identity]
  ├── mol-refinery-patrol.find-work: Find the next work bead assigned to you [needs: mol-refinery-patrol.check-inbox]
  ├── mol-refinery-patrol.rebase: Bring the branch current with its target [needs: mol-refinery-patrol.find-work]
  ├── mol-refinery-patrol.run-tests: Run quality checks and tests [needs: mol-refinery-patrol.rebase]
  ├── mol-refinery-patrol.handle-failures: Handle quality check or test failures [needs: mol-refinery-patrol.run-tests]
  ├── mol-refinery-patrol.merge-push: Land the branch, or publish its PR [needs: mol-refinery-patrol.handle-failures]
  ├── mol-refinery-patrol.patrol-summary: Record patrol cycle summary [needs: mol-refinery-patrol.merge-push]
  ├── mol-refinery-patrol.next-iteration: Pour the next iteration and loop [needs: mol-refinery-patrol.patrol-summary]
  └── mol-refinery-patrol.workflow-finalize: Finalize workflow [needs: mol-refinery-patrol.next-iteration]
