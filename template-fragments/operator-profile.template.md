{{ define "operator-profile" }}
## What the operator cares about

<!-- managed by the learning distiller; every entry carries its anchor. cap: 12 -->
<!-- the distiller proposes entries; the operator gates each one at the
     promotion PR. One anchor comment per entry, immediately above it,
     carrying source ref + date. See docs/feedback-learning.md. -->

<!-- rule:tk-vbyak0 src:pr:#465:review-conversation, bead:tk-447ql0, pr:#490:comment:3868559694 (operator feedback) adopted:2026-08-27 -->
- Living code and documents — comments, prompts, formula steps, docs —
  state what is true now and the constraints it rests on; never narrate
  what the next line does, restate the diff, or carry incident history,
  dates, or bead and PR ids. Specs and commit messages are where history
  belongs; when unsure, omit. Managed provenance anchors are the one
  exception. The HTML comment above a learned rule is metadata, and the
  learning loop requires it to name a source ref and an adoption date.

<!-- src:pr:#465:review:r3854321589 (operator feedback) adopted:2026-08-25 -->
- Prose states its content, never its own worth. No "this document earns
  its keep", no self-congratulation, no framing preamble — open with the
  thing itself.

<!-- src:pr:#465:review:r3854335489 (operator feedback) adopted:2026-08-25 -->
- Write plain sentences. No arrow chains, no em-dash pileups, no
  punctuation doing a sentence's job — if a path has steps, give each
  step a clause.
{{ end }}
