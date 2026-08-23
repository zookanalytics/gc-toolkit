Formula: mol-feedback-distiller
Description: mol-feedback-distiller — turn pending feedback observations into reviewed
prompt-update proposals, on judgment rather than counters.

What it does, plainly: agents and the miner record corrective feedback about
*standing* behavior as observation beads (`task_kind=observation`, closed at
creation, provenance-keyed). This formula runs on a daily heartbeat order,
gates the JUDGING of those observations on pending volume and urgency (D7 —
the timer is a heartbeat, this gate is the cadence; the gate scopes the
judging, never the run, so the retirement pass keeps its own unconditional
every-run cadence), reads the pending observations cross-rig (D5),
judges them with the learning-distill rubric (D6: promotion is a *reasoned
judgment*, not a counter comparison — an explicit standing directive or an
operator-endorsed observation promotes at N=1, a diff-scoped nit waits for
real recurrence; occurrence counts, source diversity, and heat are inputs the
reasoning weighs, never promotion arithmetic), clusters evidence onto standing
pattern beads, asks the retirement questions of already-adopted rules, and
files at most a few change-unit `prompt-update` beads into the pool worker →
refinery → operator-review (D3) pipeline.

Base rate: the **expected** outcome of a run is ZERO or ONE proposals. A
chatty run is a smell that the standing-vs-diff judgment is being skipped,
not a yield to celebrate. And the formula is read-only plus bead-filing: it
never edits a fragment, prompt, or skill — it surfaces, reasons, and files;
only a promotion PR merged by the operator changes agent behavior (D2/D3).

Spec: specs/2026-08-learning-system/implementation-design.md §3;
rulings: specs/2026-08-learning-system/decisions.md D5, D6, D7.


Variables:
  {{binding_prefix}}: Import binding prefix for gastown agent identities, with the trailing dot (e.g. 'gc-toolkit.'). Combined with the rig qualifier it names the polecat pool the filed prompt-update beads route to (${GC_RIG:+$GC_RIG/}{{binding_prefix}}polecat). Non-empty default — unlike the sling-poured patrol formulas, this distiller is poured by a gc order, and the order-dispatch path does NOT inject routing vars, so this default is the value used at runtime. 'gc-toolkit.' matches every importer's default_sling_target (<rig>/gc-toolkit.polecat). (default=gc-toolkit.)
  {{distill_max_age_days}}: Trickle guard (D7): if the oldest pending observation is older than this many days, the run proceeds regardless of count — a trickle still gets processed eventually. (default=14)
  {{distill_min_pending}}: Cadence-gate floor (D7): the run proceeds when pending (undistilled) observations reach this count. Below it the run still proceeds if any pending observation is urgent (obs.endorsed=operator or obs.directive=standing — those never wait on volume) or the oldest pending exceeds distill_max_age_days. (default=5)
  {{fragment_bullet_cap}}: Bullet budget per learned-conventions fragment. A promotion that would push its target fragment past this cap must name a displacement (retire or merge a weaker incumbent in the same proposal) or it does not file. (default=15)
  {{max_beads_per_run}}: Maximum prompt-update beads to file per run. If more proposals survive judgment and dedup, file the strongest N and let the rest re-surface next cycle (the state is pending observations + pattern beads + open beads/PRs, so this is naturally resumable). (default=3)
  {{rig_list}}: Space-separated rig names whose bead stores hold observations to read (D5: every importing rig captures into its own store; the distiller reads them all). Empty means attempt runtime rig enumeration (build-validation V2); if enumeration fails or returns nothing, the run aborts fail-safe (gc.outcome=fail, nothing filed) — never judge on a partial observation set. (default=)

Steps (4):
  ├── mol-feedback-distiller.load-and-gate: Prime, home-rig gate, read pending observations cross-rig, apply the D7 cadence gate
  ├── mol-feedback-distiller.judge-and-cluster: Judge the pending set with the learning-distill rubric; cluster onto pattern beads; run the retirement pass [needs: mol-feedback-distiller.load-and-gate]
  ├── mol-feedback-distiller.file-and-dispatch: File one prompt-update bead per proposal, stamp consumed observations, visit contested rules, drain [needs: mol-feedback-distiller.judge-and-cluster]
  └── mol-feedback-distiller.workflow-finalize: Finalize workflow [needs: mol-feedback-distiller.file-and-dispatch]
