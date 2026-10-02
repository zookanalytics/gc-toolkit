{{ define "learned-conventions-converse" }}
## Learned conventions

<!-- managed by the learning distiller; every bullet carries its anchor. cap: 15 -->
<!-- rule:<pattern-bead> src:<refs> adopted:<date> -->
<!-- The anchor comment above is the exact format each promotion PR copies —
     one anchor per bullet, immediately above its bullet. See
     docs/feedback-learning.md. -->

<!-- rule:tk-n7r69z src:bead:tk-to8lt9, bead:tk-kwmyg3 (operator) adopted:2026-10-02 -->
- Express a wait or a gated hand-off as a graph edge — a blocked-by
  dependency on the prerequisites, plus a deferred-dispatch arm where a
  successor must auto-sling on the blocker's close — not a passive gc.hold
  note or a manual sling a later sitting must run. A gc.hold note still
  surfaces the bead in gc hook and bd ready as live demand; a blocked-by
  edge excludes it until the blocker lands, then self-clears.
{{ end }}
