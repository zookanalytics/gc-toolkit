Formula: mol-refinery-patrol
Description: Refinery patrol loop — merge JUDGMENT only. Poured as a root-only wisp:

  gc bd mol wisp mol-refinery-patrol --root-only --var target_branch={{target_branch}} --var rig_name={{rig_name}} --var binding_prefix={{binding_prefix}}
  gc bd update $WISP --assignee=$GC_AGENT

The pour passes the rig's identity and nothing else, so the merge policy is
the formula's default as it stood when this wisp was poured. It is rendered
here for the steps that read it:

  default_merge_strategy={{default_merge_strategy}}
  check_set={{check_set}}

Each wisp is ONE iteration: find one assigned work bead, prepare its branch,
run the rig's checks, decide (land / gate / reject), pour the next wisp,
burn this one. Steps are not materialized; read each description as you
reach it. On crash, re-derive position from git and bead state.

Everything downstream of the gating handoff — check arming and review
dispatch, PR opening, the merge itself, external PR facts, convoy
graduation — is the refinery-reconcile ORDER's (60s, no session). This
formula never runs those passes: docs/refinery-merge-cadence.md.

State writes: every merge_result transition goes through
assets/scripts/lifecycle.sh (one atomic validated write per transition);
every escalation goes through assets/scripts/escalate.sh (one open visit
per situation key). Resolve both at shell runtime — formula bodies get no
{{.ConfigDir}}:

    LC=""; for c in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
      [ -x "$c/assets/scripts/lifecycle.sh" ] && { LC="$c/assets/scripts/lifecycle.sh"; break; }
    done

Marked blocks are extracted and executed by their tests
(find-work-gating-guard, mr-aware-rejection-failclosed,
preexisting-failure-dedup, one-anchor-per-pr, patrol-wisp-reconcile,
patrol-pour-vars) — keep
markers and keep the blocks backslash-free (TOML eats line-ending
backslashes).

Variables:
  {{auto_ff_rig_main}}: After a direct merge, best-effort fast-forward the rig's canonical checkout when it is on the target branch with a clean tree. Never blocks the merge. (default=true)
  {{binding_prefix}}: Agent identity prefix with trailing dot. Non-empty default on purpose: this patrol re-routes a rejected bead to the polecat pool, and an empty prefix renders <rig>/polecat instead of <rig>/gc-toolkit.polecat, so the bead is re-dispatched to an address no pool holds. (default=gc-toolkit.)
  {{build_command}}: Build command. Empty = skip. (default=)
  {{check_set}}: Merge gating check-set stamped on every anchor this formula transitions into a gating state: comma list of check names, each requiring check.<name>=green before merge.sh lands the PR. 'correctness' = a review dispatched by the cadence's gate-ensure, the check that also holds the PR `## Summary` to the whole branch diff, so 'none' forgoes that summary check along with the rest of the review; 'triage' = a review that reads the check index at the reviewed commit and widens `check_set` through `signoff.sh --add-gates` with the specialist checks the diff warrants, adding only and never removing. Approval is not a check_set token — it is a universal merge rule (merge.sh requires every PR to carry a standing non-city APPROVED review), armed for every anchor and named by no token here. The 'none' sentinel is stamped (never collapsed to empty) so checkless-by-choice and never-normalized stay distinct on the anchor; an EMPTY value is treated as absent and recovers this default, because the --root-only pour path hand-substitutes raw TOML and a mis-substitution must not silently un-gate every PR. Neither the startup pour nor the next-iteration pour passes it, so each wisp renders this default as it stands when that wisp is poured, and a changed default reaches the next wisp. (default=correctness,triage)
  {{default_merge_strategy}}: Default when metadata.merge_strategy is unset: 'direct' = FF + push to target; 'mr'/'pr' = gated PR pipeline. Neither the startup pour nor the next-iteration pour passes it, so each wisp renders this default as it stands when that wisp is poured. (default=mr)
  {{delete_merged_branches}}: Delete source branches after a direct merge. (default=true)
  {{lint_command}}: Lint command. Empty = skip. (default=tools/lint.sh $(git diff --name-only origin/main...HEAD))
  {{rig_name}}: Rig this patrol serves; injected by the pour (forwarded verbatim by next-iteration). Declared so the {{rig_name}} token in the pour commands resolves instead of surviving literally. (default=)
  {{run_tests}}: Whether to run tests before merging. (default=true)
  {{setup_command}}: Setup/install command. Empty = skip. (default=)
  {{target_branch}}: Default target branch for merges. (default=main)
  {{test_command}}: Test command (when run_tests is true). (default=)
  {{typecheck_command}}: Type check command. Empty = skip. (default=)

Steps (10):
  ├── mol-refinery-patrol.validate-identity: Validate canonical agent identity
  ├── mol-refinery-patrol.check-inbox: Check mail [needs: mol-refinery-patrol.validate-identity]
  ├── mol-refinery-patrol.find-work: Find next work bead assigned to me [needs: mol-refinery-patrol.check-inbox]
  ├── mol-refinery-patrol.rebase: Prepare the branch on its target [needs: mol-refinery-patrol.find-work]
  ├── mol-refinery-patrol.run-tests: Run quality checks and tests [needs: mol-refinery-patrol.rebase]
  ├── mol-refinery-patrol.handle-failures: Handle quality check or test failures [needs: mol-refinery-patrol.run-tests]
  ├── mol-refinery-patrol.merge-push: Merge and push (direct) or transition to gating (mr) [needs: mol-refinery-patrol.handle-failures]
  ├── mol-refinery-patrol.patrol-summary: Record patrol cycle summary [needs: mol-refinery-patrol.merge-push]
  ├── mol-refinery-patrol.next-iteration: Pour next iteration and loop [needs: mol-refinery-patrol.patrol-summary]
  └── mol-refinery-patrol.workflow-finalize: Finalize workflow [needs: mol-refinery-patrol.next-iteration]
