Formula: mol-design-convoy
Description: Executable design-convoy pattern — a dispatch molecule that stands an
integration effort up on its subject, the initiative converse reaches by
recommendation, then drains. It is for an initiative whose design must be
settled before or beside its build, on work large or high-blast-radius enough
that one holistic review of design and implementation beats scattered PRs.
Slung `--on` a single subject from the recommend-to-Accept path, it makes the
subject the effort's landing bead: it cuts `integration/<subject-id>` and records
it on the subject, files a design child whose doc lands on that branch, arms an
implementation child behind the design's approval, hands the subject to the
refinery, and files the summary task that writes the subject's PR summary once
the children have landed. The subject's PR carries design and implementation to
the default branch as one reviewed unit, and the subject closes when that PR
merges, as any PR's owning bead does, so work queued behind it starts then.
Doctrine: docs/design-convoy.md.

The molecule writes no code and needs no worktree of its own. Its one push is a
ref push from the rig's checkout, which a converse sitting cannot make. Each step
re-derives the subject from the input convoy ({{convoy_id}}'s one tracked member)
in its own shell, records its result on the subject so a resume is idempotent,
and closes its own step bead through assets/scripts/step-close.sh — resolved by
(gc.root_bead_id, gc.step_ref), never a GC_*BEAD_ID env var, which after a
hook-claim names a different step.

Every PR the effort produces merges only with a standing APPROVED review from an
account other than the city's, which counts until it is dismissed: merge.sh
enforces that as a universal rule, so no check_set token arms it. design_gated
(var, default true) chooses when implementation starts. Gated: the design child
is a stage, slung --merge mr, whose PR into the integration branch is the design
gate, and the implementation child is armed behind the design child's closure, so
the operator's approval of the design's PR is what releases it. All-in-one
(design_gated=false): design and implementation dispatch together and land on the
integration branch with no PR of their own, and the subject's PR is where the
operator first reviews them as one unit.


Variables:
  {{design_gated}}: true (default): the design child is a stage, slung --merge mr, whose PR into the integration branch is the design gate, and the implementation child is held behind the design child by a blocks edge and dispatched when the design child closes, which happens when that PR merges with the operator's approval. false: design and implementation dispatch together and land on the integration branch with no PR of their own, so the subject's PR is the one the operator reviews. Every PR needs a standing APPROVED review from an account other than the city's, which counts until it is dismissed (merge.sh's universal approval rule). The value is read case-insensitively: false, 0, no, or off selects all-in-one; true, 1, yes, or on selects design-gated; an empty or unrecognized value also selects design-gated, with a warning, so a typo never drops the design gate. An Accept takes the default, because its sling passes no var. For all-in-one, the operator takes the recommendation to a sitting (Discuss) instead, and the sitting follows the work skill's steps for taking a recommendation, adding --var design_gated=false to the sling those steps run. (default=true)

Steps (6):
  ├── mol-design-convoy.load-context: Read the initiative and resolve the gate shape
  ├── mol-design-convoy.seed-branch: Cut the integration branch and record it on the subject [needs: mol-design-convoy.load-context]
  ├── mol-design-convoy.arm-design: File the design child, hand the subject to the refinery, and dispatch the design [needs: mol-design-convoy.seed-branch]
  ├── mol-design-convoy.arm-implementation: File the implementation child and arm it behind the design [needs: mol-design-convoy.arm-design]
  ├── mol-design-convoy.arm-summary: File the summary task, arm it behind the children, and drain [needs: mol-design-convoy.arm-implementation]
  └── mol-design-convoy.workflow-finalize: Finalize workflow [needs: mol-design-convoy.arm-summary]
