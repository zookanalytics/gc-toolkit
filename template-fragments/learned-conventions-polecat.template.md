{{ define "learned-conventions-polecat" }}
## Learned conventions

<!-- managed by the learning distiller; every bullet carries its anchor. cap: 15 -->
<!-- rule:<pattern-bead> src:<refs> adopted:<date> -->
<!-- seeded empty: no rules adopted yet. The anchor comment above is the exact
     format each promotion PR copies — one anchor per bullet, immediately above
     its bullet. See docs/feedback-learning.md. -->

<!-- rule:tk-48ru7 src:gc-lhums,tk-8xjj6,tk-01vkp,gc-l2c6v adopted:2026-08-12 -->
- When a fix, guard, correction, or triage is keyed on a named site or symptom, treat that site as the minimum, not the scope — mechanically enumerate every equivalent instance (grep the retired phrase, every caller of a shared write helper, the full untruncated failure set) and address all of them before declaring done. Pair each positive assertion a change adds with an absence check for the state it retired, or a stale instance survives a green suite.
{{ end }}
