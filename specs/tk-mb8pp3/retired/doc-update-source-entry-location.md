---
name: doc-update-source-entry-location
description: "A doc-keeper doc-update bead's \"Source entry: <name>.md\" resolves to the mechanik/town-root auto-memory dir, not the rig memory; promote the durable principle+method, omit volatile incident detail."
metadata: 
  node_type: memory
  type: reference
  originSessionId: fc4304d2-f37d-48a4-8d2d-f19aea4b5b94
---

doc-keeper `doc-update` beads (label `doc-keeper`/`doc-update`, `task_kind=doc-update`) carry a **Provenance** block ending in `Source entry: <name>.md`. That file lives in the **mechanik / town-root auto-memory**, NOT this rig's memory:

`/home/zook/.claude/projects/-home-zook-loomington/memory/<name>.md`

(distinct from a polecat/refinery's own rig memory at `-home-zook-loomington-rigs-gc-toolkit/memory/`). Read it directly with the Read tool — one `find /home/zook -maxdepth 6 -name '<name>.md'` locates it if the path drifts.

**Mandate:** the source entry is a mechanik incident note; the brief gets the **durable principle + audit/method only, paraphrased**. Deliberately OMIT the volatile incident detail the source carries: dated inventories (e.g. "2026-05-27"), bead/commit IDs, absolute home paths, internal fork URLs, and stale pack paths (`.gc/system/packs/...` is retired; "maintenance" pack folded into core — don't transcribe either; see [[gascity-agents-doc-source-of-truth]]). If review shows the fact is already in the brief or doesn't belong, close as a no-op.

It's an impl task (produces a commit) → normal mr-mode done sequence (push `polecat/<bead>`, hand to refinery), not the non-impl/self-close path. Worked example: tk-i21z7 added the mirror-vs-overlay section to gascity-local-patching.md.
