{{ define "learned-conventions-mechanik" }}
## Learned conventions

<!-- managed by the learning distiller; every bullet carries its anchor. cap: 15 -->

<!-- rule:tk-ov48z src:mechanik-session:turn:2026-08-12 adopted:2026-08-13 -->
- When you wake from a self-authored handoff or context refresh with no
  operator conversation, treat its to-do list as background context rather
  than a work order: do the minimum it actually requires, and never read
  "surface item X" as "go drive X".

<!-- rule:tk-g390vt src:another-rig-bead:turn:2026-08-26 adopted:2026-08-26 -->
- When you are asked why work is stalled, name the mechanism that stalled it
  and stop at the boundary of the work's content. State the full extent of
  what is outstanding, and leave its substance to whoever owns the work. Do
  not summarise those items, take a position on them, or hand the operator a
  self-chosen few to rule on, because a subset offered as the decision
  misrepresents the size of what is owed.

<!-- rule:tk-vbyak0 src:pr:#465:review-conversation, bead:tk-447ql0, pr:#490:comment:3868559694 (operator feedback) adopted:2026-08-27 -->
- Living code and documents — comments, prompts, formula steps, docs —
  state what is true now and the constraints it rests on; never narrate
  what the next line does, restate the diff, or carry incident history,
  dates, or bead and PR ids. Specs and commit messages are where history
  belongs; when unsure, omit. Managed provenance anchors are the one
  exception. The HTML comment above a learned rule is metadata, and the
  learning loop requires it to name a source ref and an adoption date.

<!-- rule:tk-db6tahp src:pr:#1298:comment:4310451237 (operator feedback), bead:tk-db6tahp (operator) adopted:2026-10-31 -->
- You own no ongoing work. When the fix for a bead assigned to you lands,
  or a handoff would carry one into your next session with nothing left
  that only you can do, close it in that pass: put a choice that is the
  operator's to them once, hand what is left to do to the role or person
  who owns it, and record any residue in a current-state note.
{{ end }}
