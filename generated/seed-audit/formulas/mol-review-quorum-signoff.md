Formula: mol-review-quorum-signoff
Description: Two-lane review quorum that ends in a single signoff. Two read-only reviewer
lanes read the same diff on DIFFERENT providers; a synthesis step combines
their findings, writes findings.md + findings.json, and makes THE ONE
signoff.sh verdict call. It is the gc-toolkit realization of the core
mol-review-quorum scaffold (lane fan-out + per-lane provider + the
review-quorum.lane.v1 durable schema), wired to this rig's signoff seam.

Attached at dispatch to a review bead exactly as mol-review is
(gc sling <pool> <review-bead> --on mol-review-quorum-signoff), and takes the
same values as vars: the review bead, the check, the anchor, the branch, the
base its diff starts from, the commit under review, the anchor's PR once one is
open, and why the review went out. One sling pours the two lanes and the
synthesis, so all three read the same commit.

The mol-review hard contract is preserved intact: ONE verdict per claim — the
synthesis makes the single signoff.sh call and the lanes never call it; the
verdict is posted as a COMMENT, never a GitHub approval (signoff.sh owns
that). The lanes add reviewer breadth on a second
provider; the check, the finding beads, and the rework child are the same
machinery mol-review hands to.

Lane routing is per-step: each lane carries gc.run_target / gc.provider, so
the two lanes land on two provider pools and each runs on its pool's default
model. The synthesis reads each lane's durable review-quorum.lane.v1 output
from the lane step bead's gc.output_json.

Each step closes its own bead through assets/scripts/step-close.sh, which
resolves by (gc.root_bead_id, gc.step_ref) — never a GC_*BEAD_ID env var. The
lanes run in separate pool sessions and each closes its own lane step; the
synthesis is the terminal step and closes the chain forward. No shell variable
survives from one block to the next, so each block names the values it uses.


Required vars:
  {{lane_one_id}}: Durable ID for reviewer lane one
  {{lane_one_provider}}: Provider identifier for reviewer lane one
  {{lane_one_target}}: Gas City pool target for reviewer lane one
  {{lane_two_id}}: Durable ID for reviewer lane two
  {{lane_two_provider}}: Provider identifier for reviewer lane two
  {{lane_two_target}}: Gas City pool target for reviewer lane two
  {{synthesis_target}}: Gas City pool target for the synthesis-and-signoff step

Optional vars:
  {{anchor_bead}}: The work bead the verdict lands on, whose description says what the change is for. (default=)
  {{binding_prefix}}: The binding the city imports the pack under, with its trailing dot: the prefix of the pack's skill names in a session's catalog. Sling adds it to every pour. (default=gc-toolkit.)
  {{check}}: The check this review applies: the review bead's check_name, in lowercase. (default=)
  {{review_base}}: The branch the change lands on, where its diff starts. (default=)
  {{review_bead}}: The review bead this run answers. (default=)
  {{review_branch}}: The branch under review. (default=)
  {{review_context}}: Why this review went out, such as a bring-current round for triage to rule on, else empty. Free text, so the steps name it in prose and never inside a shell block. (default=)
  {{review_pr_number}}: That PR's number, empty with it. (default=)
  {{review_pr_url}}: The anchor's open PR, empty before one opens. (default=)
  {{reviewed_oid}}: The commit under review: the branch's head when the review was dispatched, never moved or cleared. (default=)

Steps (4):
  ├── mol-review-quorum-signoff.review-lane-one: Review lane one
  ├── mol-review-quorum-signoff.review-lane-two: Review lane two
  ├── mol-review-quorum-signoff.synthesize-and-signoff: Synthesize the two lanes and hand ONE verdict to signoff.sh [needs: mol-review-quorum-signoff.review-lane-one, mol-review-quorum-signoff.review-lane-two]
  └── mol-review-quorum-signoff.workflow-finalize: Finalize workflow [needs: mol-review-quorum-signoff.synthesize-and-signoff]
