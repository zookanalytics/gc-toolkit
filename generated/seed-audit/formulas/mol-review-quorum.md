Formula: mol-review-quorum
Description: Gas City-owned review quorum formula scaffold.

This graph-first workflow fans out two read-only reviewer lanes whose lane IDs,
providers, models, and dispatch targets are supplied by formula variables, then
routes a configured synthesis agent to synthesize their durable structured
outputs. Lifecycle owners decide when to invoke it, and future dx-review
compatibility can consume the durable output without owning the workflow. The
internal reviewquorum Go package defines the generic durable contract and
finalizer, but this formula's synthesis step is currently agent-executed rather
than directly wired to that Go finalizer.


Required vars:
  {{lane_one_id}}: Durable ID for reviewer lane one
  {{lane_one_model}}: Model target for reviewer lane one
  {{lane_one_provider}}: Provider identifier for reviewer lane one
  {{lane_one_target}}: Configured Gas City agent target for reviewer lane one
  {{lane_two_id}}: Durable ID for reviewer lane two
  {{lane_two_model}}: Model target for reviewer lane two
  {{lane_two_provider}}: Provider identifier for reviewer lane two
  {{lane_two_target}}: Configured Gas City agent target for reviewer lane two
  {{synthesis_target}}: Configured Gas City agent target for the quorum synthesis step

Optional vars:
  {{base_ref}}: Optional baseline ref used by reviewer prompts when inspecting a diff (default=origin/main)

Steps (10):
  ├── mol-review-quorum.review-lane-one.spec: Step spec for Review lane one (spec)
  ├── mol-review-quorum.review-lane-one.attempt.1: Review lane one
  ├── mol-review-quorum.review-lane-one: Review lane one [needs: mol-review-quorum.review-lane-one.attempt.1]
  ├── mol-review-quorum.review-lane-two.spec: Step spec for Review lane two (spec)
  ├── mol-review-quorum.review-lane-two.attempt.1: Review lane two
  ├── mol-review-quorum.review-lane-two: Review lane two [needs: mol-review-quorum.review-lane-two.attempt.1]
  ├── mol-review-quorum.synthesize-review-quorum.spec: Step spec for Synthesize review quorum (spec)
  ├── mol-review-quorum.synthesize-review-quorum.attempt.1: Synthesize review quorum [needs: mol-review-quorum.review-lane-one, mol-review-quorum.review-lane-two]
  ├── mol-review-quorum.synthesize-review-quorum: Synthesize review quorum [needs: mol-review-quorum.review-lane-one, mol-review-quorum.review-lane-two, mol-review-quorum.synthesize-review-quorum.attempt.1]
  └── mol-review-quorum.workflow-finalize: Finalize workflow [needs: mol-review-quorum.synthesize-review-quorum]
