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

Every PR this convoy produces, the design child's checkpoint PR included, merges
only with a standing APPROVED review from an account other than the city's,
which counts until it is dismissed: merge.sh enforces that as a universal rule,
so no check_set token arms it. design_gated (var, default
true) chooses when implementation starts. Gated: the implementation child is
armed behind the design child's closure, so the operator's approval of the
design's PR is what releases it. All-in-one (design_gated=false): design and
implementation dispatch together, and the graduation PR is where the operator
first reviews them as one unit.


Variables:
  {{design_gated}}: true (default): the implementation child is held behind the design child by a blocks edge and dispatched when the design child closes, which happens when its checkpoint PR merges with the operator's approval. false: design and implementation dispatch together and land on the integration branch in parallel. Either way every PR needs a standing APPROVED review from an account other than the city's, which counts until it is dismissed (merge.sh's universal approval rule). The value is read case-insensitively: false, 0, no, or off selects all-in-one; true, 1, yes, or on selects design-gated; an empty or unrecognized value also selects design-gated, with a warning, so a typo never drops the design gate. The operator overrides per initiative at Accept with --var design_gated=false. (default=true)

Steps (6):
  ├── mol-design-convoy.load-context: Read the initiative and resolve the convoy shape
  ├── mol-design-convoy.seed-convoy: Create the owned convoy and cut its integration branch [needs: mol-design-convoy.load-context]
  ├── mol-design-convoy.arm-design: File the design child and dispatch it [needs: mol-design-convoy.seed-convoy]
  ├── mol-design-convoy.arm-implementation: File the implementation child and arm it behind the design [needs: mol-design-convoy.arm-design]
  ├── mol-design-convoy.drain: Close the step chain and drain [needs: mol-design-convoy.arm-implementation]
  └── mol-design-convoy.workflow-finalize: Finalize workflow [needs: mol-design-convoy.drain]
