Formula: mol-review-quorum-signoff
Description: Two-lane review quorum that ends in a single signoff. Two read-only reviewer
lanes read the same diff on DIFFERENT providers; a synthesis step combines
their findings, writes findings.md + findings.json, and makes THE ONE
signoff.sh verdict call. It is the gc-toolkit realization of the core
mol-review-quorum scaffold (lane fan-out + per-lane provider + the
review-quorum.lane.v1 durable schema), wired to this rig's signoff seam.

Attached at dispatch to a review bead exactly as mol-review is
(gc sling <pool> <review-bead> --on mol-review-quorum-signoff), and reads the
same dispatch metadata: task_kind=review, check_name (the gate the verdict
satisfies), anchor_bead, review_branch / review_base pre-open or
pr_url / pr_number post-open, and the dispatch-pinned reviewed_oid.

The mol-review hard contract is preserved intact: ONE verdict per claim — the
synthesis makes the single signoff.sh call and the lanes never call it; the
verdict is posted as a COMMENT, never a GitHub approval (signoff.sh owns
that). The lanes add reviewer breadth on a second
provider; the merge gate, the finding beads, and the rework child are the same
machinery mol-review hands to.

Lane routing is per-step: each lane carries gc.run_target / gc.provider, so
the two lanes land on two provider pools and each runs on its pool's default
model. The synthesis reads each lane's durable review-quorum.lane.v1 output
from the lane step bead's
gc.output_json. base_ref defaults to origin/main; the caller passes the
review's base so the lanes diff against the branch's real landing target.

Each step re-derives REVIEW_BEAD from the input convoy in its own shell and
closes its own bead through assets/scripts/step-close.sh, which resolves by
(gc.root_bead_id, gc.step_ref) — never a GC_*BEAD_ID env var. The lanes run in
separate pool sessions and each closes its own lane step; the synthesis is the
terminal step and closes the chain forward.


Required vars:
  {{lane_one_id}}: Durable ID for reviewer lane one
  {{lane_one_provider}}: Provider identifier for reviewer lane one
  {{lane_one_target}}: Gas City pool target for reviewer lane one
  {{lane_two_id}}: Durable ID for reviewer lane two
  {{lane_two_provider}}: Provider identifier for reviewer lane two
  {{lane_two_target}}: Gas City pool target for reviewer lane two
  {{synthesis_target}}: Gas City pool target for the synthesis-and-signoff step

Optional vars:
  {{base_ref}}: Diff baseline the lanes review against; the caller passes origin/<review_base> (default=origin/main)

Steps (4):
  ├── mol-review-quorum-signoff.review-lane-one: Review lane one
  ├── mol-review-quorum-signoff.review-lane-two: Review lane two
  ├── mol-review-quorum-signoff.synthesize-and-signoff: Synthesize the two lanes and hand ONE verdict to signoff.sh [needs: mol-review-quorum-signoff.review-lane-one, mol-review-quorum-signoff.review-lane-two]
  └── mol-review-quorum-signoff.workflow-finalize: Finalize workflow [needs: mol-review-quorum-signoff.synthesize-and-signoff]
