{{ define "work-quality" }}
{{/* Elected by roles that author durable output: artifacts that outlive the
     turn and that someone else reads — code, docs, specs, PR and bead bodies,
     findings and reports. A role whose only outputs are its own control flow
     (a claim, a close, a formula-emitted escalation) does not elect it.
     Composing something an operator reads is the other fragment's test; see
     operator-profile.template.md. */ -}}
## Standards for what you produce

<!-- managed by the learning distiller; every entry carries its anchor. cap: 12 -->
<!-- the distiller proposes entries; the operator gates each one at the
     promotion PR. One anchor comment per entry, immediately above it,
     carrying source ref + date. See docs/feedback-learning.md. -->

<!-- rule:tk-uzkg2c src:audit:tk-awa7hv adopted:2026-08-26 -->
- Derive a load-bearing claim at the moment you make it, and check that the
  evidence you cite discriminates. A premise inherited from a bead body, a
  design doc, or one transient measurement is an assertion, not evidence.

<!-- rule:tk-b80kkz src:audit:tk-awa7hv adopted:2026-08-26 -->
- A rename, a re-framing, or a rendering change is not a fix for the thing
  that produced the symptom. Take a report at the severity it was filed,
  find what allowed it to happen, and prefer a design in which it cannot
  happen again over a patch for the instance.

<!-- rule:tk-tketyk src:audit:tk-awa7hv adopted:2026-08-26 -->
- File work as a bead in the pass that names it, and put the bead id in the
  row that proposed it. A prose promise loses members of a set.

<!-- rule:tk-xgaeo src:audit:tk-awa7hv adopted:2026-08-26 -->
- Documentation states what is true now, in the present tense. No "replaces
  the old X", no proposed-amendment section, no rule justified by the history
  of the change that produced it — the commit is the changelog.

<!-- src:pr:#465:review:r3854321589 (operator feedback) adopted:2026-08-25 -->
- Prose states its content, never its own worth. No "this document earns
  its keep", no self-congratulation, no framing preamble — open with the
  thing itself.

<!-- src:pr:#465:review:r3854335489 (operator feedback) adopted:2026-08-25 -->
- Write plain sentences. No arrow chains, no em-dash pileups, no
  punctuation doing a sentence's job — if a path has steps, give each
  step a clause.

<!-- rule:tk-0slk80 src:pr:zookanalytics/gc-toolkit#473:review:r-changes-requested-2026-08-27 (operator, endorsed), pr:#616:review:5108240026, pr:#592:review:5105818489, bead:tk-qu01om:turn:2026-09-18 adopted:2026-09-19 -->
- A design or verification bead's deliverable is the behaviour it decides or
  verifies, in the smallest form that runs, not a specs/ record or a
  document-only PR that defers to an unbuilt component or exists only to give
  the refinery something to merge. When the honest answer is "already fixed" or
  "we will not build it", record that disposition; a deferral is an answer only
  when a bead tracks the component and names the cost of waiting.
{{ end }}
