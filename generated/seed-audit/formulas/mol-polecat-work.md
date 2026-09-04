Formula: mol-polecat-work
Description: Polecat work lifecycle — feature-branch variant. Extends the core
mol-polecat-base with worktree/branch setup, affected-aware self-review, and
the refinery handoff. Run by every polecat in the city; the agent prompt
carries the doctrine, this file carries the mechanics.

Contract (self-cleaning model): receive work -> follow steps in order ->
push branch, ONE atomic handoff update to the refinery -> close own step
chain -> drain. A run whose whole product is store work has no branch to
push and takes submit-and-exit's store-only arm instead, which releases the
bead and names the disposition for whoever owns the close. A run whose PR
lands in a repository no refinery covers takes the operator-merge arm, which
parks the anchor on gc.routed_to=human for a person to merge.
NEVER close the work bead: the refinery closes an anchor on a
verified merge, and closes a rework hand-back landed-on-branch, both from
merge-push. ALWAYS close your own step beads through
assets/scripts/step-close.sh — a graph.v2 step advances only by closing its
own bead, and step-close.sh resolves it from the (assignee, gc.step_ref)
pair; $GC_BEAD_ID / $GC_TRIGGER_BEAD_ID name the wrong bead after a claim.
workflow-finalize is the control-dispatcher's — never close it.

Two distinct branch questions: {{base_branch}} is what the worktree is
poured FROM (on a rework child, the reviewed branch — by design);
metadata.target is where the work LANDS. submit-and-exit resolves the
landing target once and fails closed; the marked submit-* blocks are
extracted and executed by assets/scripts/submit-branch-gate.test.sh — run it
after any edit here.

Two distinct BEAD questions, the same way: the bead you claimed is not always
the bead the branch is gated by. On a rework or rebase child the anchor is a
separate bead, and pr-open.sh, pr-facts.sh and merge.sh all read the anchor.
submit-and-exit resolves it once, in step 4c, and the summary follows it.

Rejection-aware: metadata.branch + metadata.rejection_reason mean a prior
attempt bounced with the branch intact — resume it per metadata.prepare_mode
(merge = shared branch, never rebase/force-push), don't redo the work.


Variables:
  {{affected_tests_command}}: Shell-safe command that reads `git diff --name-only origin/{{base_branch}}...HEAD` and runs the matching test subset. Empty = run full test_command. (default=)
  {{base_branch}}: The base branch to rebase on and compare against (e.g., main, integration/convoy-id) (default=main)
  {{binding_prefix}}: Agent identity prefix with trailing dot. Non-empty default on purpose: an empty prefix renders `<rig>/refinery`, an address no agent holds, and the refinery's exact-match find-work makes that strand silent. (default=gc-toolkit.)
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
