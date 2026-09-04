---
name: doc-keeper-audit-same-line-overlap
description: "doc-keeper drift audit — a finding on the same brief lines as an in-flight doc-update PR but with distinct provenance gets FILED with a coordination note, not deferred."
metadata: 
  node_type: memory
  type: project
  originSessionId: b1589ed8-3ec3-4009-86e0-efe93ab37cca
---

In the doc-keeper drift audit, dedup is on the **change** = `(provenance + brief/area)`, NOT a whole-doc match. A finding hitting the *same lines* as an open `doc-update` PR but stemming from a *different upstream cause* is a different change → **file it**, don't defer.

Add a COORDINATION block to the bead body: name the overlapping PR (+ head branch), give the **exact final string** the lines must end up as, and note "if the overlapping PR already merged, only your part needs fixing; else set the full final form and expect a rebase." The refinery mr+codex+rebase loop converges in any merge order, so a same-line two-PR window is safe.

Worked example (2026-06-19 run): filed **tk-po9jx** (gascity-reference.md `## Schemas` `.json` links 404 — path moved `docs/schema/` → `docs/reference/schema/` via gascity `2315679e2`/#3461; redirects cover only `/schema` + `/schema/index`) even though in-flight **PR #144** (head `polecat/tk-8ny16`, approved) rewrites those same 3 lines — but #144 only fixes the HOST (`docs.gascityhall.com`→`docs.gascity.com`), leaving the path. Distinct provenance → filed, spelling out the final form `https://docs.gascity.com/reference/schema/<f>.json`. See [[doc-keeper-drift-audit-exclusions]].
