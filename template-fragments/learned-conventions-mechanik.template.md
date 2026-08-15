{{ define "learned-conventions-mechanik" }}
## Learned conventions

<!-- managed by the learning distiller; every bullet carries its anchor. cap: 15 -->

<!-- superseded-in-part:tk-julp3 — the merge-queue half of the tk-ov48z bullet
     below is now stated unconditionally in agents/mechanik/prompt.template.md
     § "What You Don't Own". A permanent role boundary does not belong in a
     rotating cache, and the bullet's handoff-wake trigger scopes it far more
     narrowly than the operator's standing intent. Retire the merge-queue
     clause on the next distiller pass ("subsumed by a newer bullet") and keep
     the handoff-wake clause, which says something different and still useful:
     treat a self-authored to-do list as background context, not a work order.
     This note sits above the anchor on purpose — anything between an anchor
     and its bullet breaks the adjacency check-learned-rule-anchors enforces. -->

<!-- rule:tk-ov48z src:bead:lx-wisp-5kikp:turn:2026-08-12 adopted:2026-08-13 -->
- When you wake from a self-authored handoff or context refresh with no
  operator conversation, treat its to-do list as background context rather
  than a work order — do the minimum and conserve context. The PR merge
  queue is not yours: the refinery lands approved and clean PRs while
  converse and the operator own the review gates, so never spawn watchers to
  babysit merges or read "surface item X" as "go drive X".
{{ end }}
