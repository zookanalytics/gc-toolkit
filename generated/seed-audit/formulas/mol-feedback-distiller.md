Formula: mol-feedback-distiller
Description: mol-feedback-distiller — turn pending feedback observations into reviewed
prompt-update proposals, on judgment rather than counters.

Agents and the miner record corrective feedback as observation beads
(task_kind=observation, closed at creation, provenance-keyed). This formula
runs on a daily heartbeat order; the D7 gate here is the real cadence — it
scopes the JUDGING of observations (volume / urgency / age), never the run:
the retirement pass over adopted rules is unconditional, every run. Judging
uses the learning-distill rubric (D6: promotion is a reasoned judgment — a
standing directive or operator-endorsed observation promotes at N=1, a
diff-scoped nit waits for recurrence; counts and heat are inputs, never
arithmetic). Output: at most a few change-unit `prompt-update` beads into
the pool worker -> refinery -> operator-review pipeline (D3). Base rate:
ZERO or ONE proposals per run; a chatty run is a smell.

A proposal names a CARRIER before it names rule text: a conventions bullet,
an operator-profile entry, a work-quality entry, a review-rubric dimension, or
an exemplar pair.
The carrier decides the target file, the budget, and which gates apply; the
rubric holds the selection rule.

Read-only plus bead-filing: this formula never edits a fragment, prompt, or
skill — only an operator-merged PR changes agent behavior.

Every step closes its own bead through `assets/scripts/step-close.sh --step
<step-id>` (resolved into `$SC` at the top of each shell block) — never any
other way, and never on an id read from the environment; the helper resolves
by (gc.root_bead_id, gc.step_ref) and refuses when it cannot prove which
molecule it is executing.
No-op arms close their OWN bead and end their shell WITHOUT draining (the
successors re-derive the gates and no-op cheaply; only the terminal step
drains). `DISTILL_RUN` (open | gated | aborted | off-home) is session state;
a worker waking fresh re-runs step 1 §1-§3 to rebuild it — never guesses.

Spec: specs/2026-08-learning-system/implementation-design.md §3; rulings D5-D7.


Variables:
  {{binding_prefix}}: Agent identity prefix with trailing dot. Non-empty default on purpose: this formula is poured by a gc order, and order dispatch injects no routing vars. (default=gc-toolkit.)
  {{distill_max_age_days}}: Trickle guard (D7): when the oldest pending observation exceeds this age, the run proceeds regardless of count. (default=14)
  {{distill_min_pending}}: Cadence-gate floor (D7): judge when pending observations reach this count. Urgent observations (obs.endorsed=operator or obs.directive=standing) never wait on volume. (default=5)
  {{exemplar_cap}}: Entry budget for the exemplar corpus, template-fragments/learning-exemplars.template.md (carrier: exemplar). Read per review rather than per turn, so the cap is larger per unit of cost and still bounded. (default=8)
  {{fragment_bullet_cap}}: Bullet budget per learned-conventions fragment. A promotion past the cap must name a displacement in the same proposal or it does not file. (default=15)
  {{max_beads_per_run}}: Maximum prompt-update/engineering beads filed per run; dropped survivors re-surface next cycle (state is durable, so this is naturally resumable). (default=3)
  {{profile_entry_cap}}: Entry budget for the operator profile (carrier: profile). Same displacement rule as fragment_bullet_cap. (default=12)
  {{rig_list}}: Space-separated rig names whose stores hold observations (D5). Empty = runtime enumeration; if that fails, the run aborts fail-safe — never judge on a partial observation set. (default=)
  {{work_quality_entry_cap}}: Entry budget for the work-quality fragment (carrier: work-quality). Same displacement rule as fragment_bullet_cap. (default=12)

Steps (4):
  ├── mol-feedback-distiller.load-and-gate: Prime, home-rig gate, read pending observations cross-rig, apply the D7 cadence gate
  ├── mol-feedback-distiller.judge-and-cluster: Judge the pending set with the learning-distill rubric; cluster onto pattern beads; run the retirement pass [needs: mol-feedback-distiller.load-and-gate]
  ├── mol-feedback-distiller.file-and-dispatch: File one prompt-update bead per proposal, stamp consumed observations, visit contested rules, drain [needs: mol-feedback-distiller.judge-and-cluster]
  └── mol-feedback-distiller.workflow-finalize: Finalize workflow [needs: mol-feedback-distiller.file-and-dispatch]
