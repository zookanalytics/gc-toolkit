Formula: mol-doc-keeper-memory-audit
Description: doc-keeper memory audit — keep each agent brief **complete**. Glob the briefs
(`docs/gascity-*.md`), read each brief's `## Scope`, and ask the charter
question from the gap side: does a durable learning in mechanik's auto-memory
fall *inside* some brief's mandate but isn't captured there? Each in-scope,
not-yet-written learning is a gap; the audit files one change-unit `doc-update`
bead proposing the addition, citing the memory entry as provenance. Read-only:
it surfaces, it never edits a doc or the memory.

Two orthogonal gates decide promotion, and a learning promotes only if it clears
both. **Nature:** it must state a *structural* truth about how Gas City is
designed to work — a durable contract or by-design sharp edge — not *operational*
state such as a live defect or its workaround. **Scope:** it must fall inside
some brief's mandate (not its excluded boundaries) and not already be written
there. Operational lore, agent-conduct corrections, and one-off incidents fail a
gate and stay local; and because mechanik auto-memory is overwhelmingly
operational, the expected outcome of a run is that nothing promotes. Each
filed bead (`task_kind=doc-update`, `target=main`, `merge_strategy=mr`) feeds
the shared `doc-update` pipeline — a
pool polecat promotes the learning under `mol-polecat-work` and the refinery
opens one small PR to `main`.

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
  {{binding_prefix}}: Import binding prefix for gastown agent identities, with the trailing dot (e.g. 'gc-toolkit.'). Combined with the rig qualifier it names the polecat pool the filed doc-update beads route to (${GC_RIG:+$GC_RIG/}{{binding_prefix}}polecat). Non-empty default — unlike the sling-poured patrol formulas, this audit is poured by a gc order, and the order-dispatch path does NOT inject routing vars, so this default is the value used at runtime. 'gc-toolkit.' matches every importer's default_sling_target (<rig>/gc-toolkit.polecat). (default=gc-toolkit.)
  {{max_beads_per_run}}: Maximum doc-update beads to file per run. If more candidates survive, file the most-recently-modified N and re-fire next cycle. (default=3)
  {{memory_dir}}: Absolute path to mechanik's auto-memory directory (the audit source; read-only). (default=[[HOME]]/.claude/projects/-home-zook-loomington/memory)

Steps (4):
  ├── mol-doc-keeper-memory-audit.load-context: Prime, locate the memory source, and resolve the brief set
  ├── mol-doc-keeper-memory-audit.scan-and-classify: Read each brief's ## Scope, then find in-scope-but-missing learnings [needs: mol-doc-keeper-memory-audit.load-context]
  ├── mol-doc-keeper-memory-audit.file-and-dispatch: File a change-unit doc-update bead per gap, dispatch it, and drain [needs: mol-doc-keeper-memory-audit.scan-and-classify]
  └── mol-doc-keeper-memory-audit.workflow-finalize: Finalize workflow [needs: mol-doc-keeper-memory-audit.file-and-dispatch]
