Formula: mol-doc-keeper-drift-audit
Description: doc-keeper drift audit — keep each agent brief **true**. Glob the briefs
(`docs/gascity-*.md`), read each brief's `## Scope`, and ask the charter
question: given how the repos it tracks have moved upstream, is any claim the
brief makes *within its scope* now false? Each stale claim is drift; the audit
files one change-unit `doc-update` bead per upstream change, citing the
triggering commits as provenance. Read-only: it produces beads, never edits a
doc.

One pour = one audit run, poured periodically onto the polecat pool. Each filed
bead (`task_kind=doc-update`, `target=main`, `merge_strategy=mr`) feeds the
shared `doc-update` pipeline — a pool polecat edits the brief(s) under
`mol-polecat-work` and the refinery opens one small PR to `main`.

## How every step closes its own bead

Each step below closes its bead with `assets/scripts/step-close.sh --step
<this step's id>`, resolved into `$SC` at the top of each shell block. **Do
not close a step bead any other way, and never on an id read from the
environment.** The helper asks the store which in-progress bead has this
session as its `assignee` and this step as its `metadata."gc.step_ref"` — a
pair that identifies exactly one bead and cannot go stale.

The two environment variables that look like the answer are both wrong.
`$GC_BEAD_ID` is not populated in the step environment (tk-7w69a), so a close
guarded on it short-circuits silently and the step is re-offered forever —
this formula shipped with that bug. `$GC_TRIGGER_BEAD_ID` is worse (tk-niu2f):
`gc hook --claim` does not refresh it, so it still names whatever the session
was spawned with and the close succeeds against a *different* molecule's step
bead, owned by a *different* live session.

If the helper cannot prove which bead is yours it writes nothing and exits 2.
Close it then by the id your `gc hook --claim --json` returned in `.bead_id`,
and note that you did.



Variables:
  {{audit_max_beads_per_run}}: Safety cap on doc-update beads filed per audit run, so a high-drift window cannot swamp the polecat pool. Deferred changes are picked up on the next run. (default=5)
  {{binding_prefix}}: Import binding prefix for gastown agent identities, with the trailing dot (e.g. 'gc-toolkit.'). Combined with the rig qualifier it names the polecat pool the filed doc-update beads route to (${GC_RIG:+$GC_RIG/}{{binding_prefix}}polecat). Non-empty default — unlike the sling-poured patrol formulas, this audit is poured by a gc order, and the order-dispatch path does NOT inject routing vars, so this default is the value used at runtime. 'gc-toolkit.' matches every importer's default_sling_target (<rig>/gc-toolkit.polecat). (default=gc-toolkit.)
  {{gascity_rig}}: Sibling rig directory under $GC_CITY/rigs that holds the upstream gascity checkout. Used as both the repo path and the provenance repo label. (default=gascity)

Steps (4):
  ├── mol-doc-keeper-drift-audit.prime: Prime and orient
  ├── mol-doc-keeper-drift-audit.audit-and-file: Judge each brief against its ## Scope and file change-unit doc-update beads [needs: mol-doc-keeper-drift-audit.prime]
  ├── mol-doc-keeper-drift-audit.drain: Summarize and drain [needs: mol-doc-keeper-drift-audit.audit-and-file]
  └── mol-doc-keeper-drift-audit.workflow-finalize: Finalize workflow [needs: mol-doc-keeper-drift-audit.drain]
