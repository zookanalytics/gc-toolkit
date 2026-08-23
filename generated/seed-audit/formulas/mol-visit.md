Formula: mol-visit
Description: mol-visit — "I want to talk about this": file one visit on a
subject bead, routed to the converse pool. The operator-driven trigger of
the one entry point — all three triggers (formula-driven, event-driven,
operator-driven) collapse into filing a visit (specs/tk-h9pq5/design-doc.md,
Key Components §5; docs/architecture.md "How work moves").

Contract: v1, one step — the one-step formula the architecture names. Run
by whoever wants the conversation (operator shell, a formula step, another
conversation); the step files the visit and exits. Pool demand does the
spawning.

Files no gated work; nothing to sign off.


Required vars:
  {{subject}}: The subject bead the conversation is about — its id IS the conversation's identity
  {{visit}}: The visit prompt: what this visit needs from the operator (decision, review, catch-up). Substituted into a shell command — avoid quote characters, or put the detail in the -d body by hand.

Optional vars:
  {{binding_prefix}}: Import binding prefix with trailing dot; combined with the rig qualifier it names the converse pool (the exact-match read side needs the qualified name — docs/gascity-routing-model.md) (default=gc-toolkit.)

Steps (1):
  └── mol-visit.file-visit: File the visit bead in the subject's continuation group
