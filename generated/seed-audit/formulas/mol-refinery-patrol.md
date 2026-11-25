Formula: mol-refinery-patrol
Description: The refinery's steps, on Gas Town's. A refinery session takes ONE item and
ends: Gas City starts it when an item assigned to the refinery waits, or a wake
names one. It claims that item, brings its branch current with its target by
merge, runs the rig's checks, then lands it, publishes its PR or sends it back,
and ends at end-session. Steps are not materialized; read each step as you
reach it. A claim a session left in progress is the next session's: find-work
adopts it, and you re-derive where it was from git and bead state.

Work beads flow directly: a polecat sets `branch` and `target` on its work
bead and assigns it to you. Every step makes one call to a tested pack script
and passes it the bead it acts for; each script refuses a bead whose branch is
not the one checked out in your tree for it (`refinery-lib.sh`). Resolve the
scripts at shell runtime, since formula bodies get no {{.ConfigDir}}:
`"$(b='{{binding_prefix}}'; gc "${b%.}" scripts-dir)/<script>"`.

The merge strategy is the bead's `merge_strategy`: `direct` lands by a
fast-forward push, and `mr` publishes a pull request. The PR's bead stays open
on Gas Town's pending-through-merge record until the landing order (orders/
pr-reconcile.toml) verifies its merge, which is not yours to run:
docs/refinery-merge-cadence.md.

Variables:
  {{binding_prefix}}: Agent identity prefix with trailing dot. Non-empty default on purpose: this patrol sends a bead back to the polecat pool, and an empty prefix names <rig>/polecat instead of <rig>/<binding>.polecat, which no pool claims. (default=gc-toolkit.)
  {{build_command}}: Build command. Empty = skip. (default=)
  {{default_merge_strategy}}: The strategy for a bead that names none: 'direct' lands by a fast-forward push, 'mr' publishes a PR. Whatever this says, a bead that would land direct on the rig's default branch takes mr, so the default branch takes work only through a PR (docs/warrants.md). The merge-push step reads the rig's value, else this default. (default=direct)
  {{delete_merged_branches}}: Delete a branch from origin once its direct landing is recorded. (default=true)
  {{lint_command}}: Lint command. Empty = skip. (default=)
  {{rig_name}}: The rig this refinery serves, which the prompt's step read passes as it passes every var. (default=)
  {{run_tests}}: Whether the gate runs test_command. (default=true)
  {{setup_command}}: Setup/install command. Empty = skip. (default=)
  {{target_branch}}: The rig's default branch, which a bead with no target lands on. (default=main)
  {{test_command}}: Test command (when run_tests is true). (default=)
  {{typecheck_command}}: Type check command. Empty = skip. (default=)

Steps (9):
  ├── mol-refinery-patrol.validate-identity: Validate canonical agent identity
  ├── mol-refinery-patrol.check-inbox: Check mail [needs: mol-refinery-patrol.validate-identity]
  ├── mol-refinery-patrol.find-work: Claim the one item this session takes [needs: mol-refinery-patrol.check-inbox]
  ├── mol-refinery-patrol.rebase: Bring the branch current with its target [needs: mol-refinery-patrol.find-work]
  ├── mol-refinery-patrol.run-tests: Run quality checks and tests [needs: mol-refinery-patrol.rebase]
  ├── mol-refinery-patrol.handle-failures: Handle quality check or test failures [needs: mol-refinery-patrol.run-tests]
  ├── mol-refinery-patrol.merge-push: Land the branch, or publish its PR [needs: mol-refinery-patrol.handle-failures]
  ├── mol-refinery-patrol.end-session: Give back the claim you still hold, and end the session [needs: mol-refinery-patrol.merge-push]
  └── mol-refinery-patrol.workflow-finalize: Finalize workflow [needs: mol-refinery-patrol.end-session]
