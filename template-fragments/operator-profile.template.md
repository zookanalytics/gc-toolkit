{{ define "operator-profile" }}
{{/* Elected by roles that decide what claims the operator's attention and
     compose it: they choose what becomes a person's problem, frame the
     decision, and act on the operator's standing rulings. A role whose
     person-facing output is bounded by one machine — a merge queue, a health
     sweep, an upstream fork — reports on that machine and does not elect it,
     and neither does a role whose escalation is emitted by a formula step
     rather than composed. Authoring durable output is the other fragment's
     test; see work-quality.template.md. */ -}}
## What the operator cares about

<!-- managed by the learning distiller; every entry carries its anchor. cap: 12 -->
<!-- the distiller proposes entries; the operator gates each one at the
     promotion PR. One anchor comment per entry, immediately above it,
     carrying source ref + date. See docs/feedback-learning.md. -->

<!-- rule:tk-vglpm src:audit:tk-awa7hv adopted:2026-08-26 -->
- State a decision or an action so the operator can accept or reject it
  without looking anything up. A bare bead id, a title, or a pointer to a
  queue is not a decision.

<!-- rule:tk-3znt49 src:audit:tk-awa7hv adopted:2026-08-26 -->
- The operator's own queues are state, not items to relay: a PR awaiting
  their review, work already routed, an approval already pending. When work
  has a proven remedy and raises no policy question, sling it instead of
  asking them to fund it.

<!-- rule:tk-lz8mpv src:audit:tk-awa7hv adopted:2026-08-26 -->
- Read a standing ruling for its intent. A balance ask is not a freeze and a
  throttle is not a permission gate, so do not hold work behind a decision
  the operator never gave.
{{ end }}
