Formula: mol-design-convoy
Description: Executable design-convoy pattern — a dispatch molecule that stands up an owned
integration convoy converse reaches by recommendation, then drains. Slung `--on`
a single subject (the initiative) from the recommend-to-Accept path, it creates
the owned convoy, cuts its integration branch, files a design child whose doc
lands on that branch, and arms an implementation child behind the design's
approval. Design and implementation graduate to the default branch as one
reviewed unit. Doctrine: docs/design-convoy.md.

The molecule writes no code and needs no worktree of its own; convoy-seed.sh
carries the push rights a converse sitting lacks. Each step re-derives the
subject from the input convoy ({{convoy_id}}'s one tracked member) in its own
shell, records its result on the subject so a resume is idempotent, and closes
its own step bead through assets/scripts/step-close.sh — resolved by
(gc.root_bead_id, gc.step_ref), never a GC_*BEAD_ID env var, which after a
hook-claim names a different step.

design_gated (var, default true) chooses the shape. Gated: the design child
carries the approval lane (check_set=codex,approval), so merge.sh holds its
checkpoint PR until an operator approves, and the implementation is armed behind
that closure — two operator gates (the checkpoint PR, then graduation).
All-in-one (design_gated=false): design and implementation dispatch together and
are reviewed once at graduation — one gate.


Variables:
  {{design_gated}}: true (default): the design child carries the approval lane, so merge.sh holds its checkpoint PR for an operator APPROVED review and the implementation child is armed behind the design's closure — two operator gates. false: design and implementation dispatch together and land on the integration branch in parallel, reviewed once at graduation — one gate. The operator overrides per initiative at Accept with --var design_gated=false. (default=true)

Steps (6):
  ├── mol-design-convoy.load-context: Read the initiative and resolve the convoy shape
  ├── mol-design-convoy.seed-convoy: Create the owned convoy and cut its integration branch [needs: mol-design-convoy.load-context]
  ├── mol-design-convoy.arm-design: File the design child and arm gate 1 [needs: mol-design-convoy.seed-convoy]
  ├── mol-design-convoy.arm-implementation: File the implementation child and arm it behind the design [needs: mol-design-convoy.arm-design]
  ├── mol-design-convoy.drain: Close the step chain and drain [needs: mol-design-convoy.arm-implementation]
  └── mol-design-convoy.workflow-finalize: Finalize workflow [needs: mol-design-convoy.drain]
