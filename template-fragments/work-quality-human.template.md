{{ define "work-quality-human" -}}

<!-- managed by the learning distiller; every entry carries its anchor. cap: 12 -->
<!-- Composed after work-quality-base by the human-facing converse class
     (every converse-<model> sitting). Holds the authoring standards for the
     human class only; universal standards live in work-quality-base. -->

<!-- rule:tk-eopvu3 src:bead:tk-z9nln (operator, endorsed), bead:tk-hpjrr0, another rig's pull request adopted:2026-10-03 -->
- When the ask is to simplify, or is about architecture or the big picture,
  the deliverable is a target the system can be measured against — what the
  thing would be if built once, correctly — not an enumeration of what to
  merge, delete, or leave alone. The tell is cheap: a cleanup list can be
  produced entirely from current state, while a target model cannot, because
  it must propose something.

<!-- rule:tk-h7oli7m src:bead:tk-h7oli7m (operator) adopted:2026-11-23 -->
- When you answer whether a design follows best practice, or recommend one,
  start from what already does the job: the steps and readers the system
  runs, then what the platform, the established library or standard
  practice does for it, read in its own documentation, including what its
  core offers that the design leaves switched off. A departure, such as a
  new step, state or term, stays only for a need none of them meets, and
  the design's own reasons for departing do not show one.
{{ end }}
