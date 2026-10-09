{{ define "work-quality-base" }}
{{/* The shared base of the work-quality carrier: the authoring standards that
     hold for every role that produces durable output, whatever class it sits
     in. Each such role composes this fragment AND its per-class fragment
     (work-quality-polecats / work-quality-human / work-quality-system), so a
     universal standard lives here once instead of in each class.
     Elected by roles that author durable output: artifacts that outlive the
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

<!-- rule:tk-b80kkz src:audit:tk-awa7hv, pr:#992:review:5402830626 (operator feedback), pr:#1045:comment:6031460436 (operator feedback), pr:#1132:comment:6066452298 adopted:2026-08-26 updated:2026-10-09 -->
- A rename, a re-framing, a rendering change, a sweep that closes state
  which should not exist, or one more guard for each newly found bypass is
  not a fix for the thing that produced the symptom. Take a report at the
  severity it was filed, find what allowed it to happen, and prefer a design
  in which it cannot happen again over a patch for the instance. When a
  sweep or a guard must still ship, the change names the cause it leaves in
  place and why that cause cannot be fixed where it arises.

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

<!-- rule:tk-n7r69z src:bead:tk-to8lt9, bead:tk-kwmyg3 (operator) adopted:2026-10-02 -->
- Express a wait or a gated hand-off as a graph edge — a blocked-by
  dependency on the prerequisites, plus a deferred-dispatch arm where a
  successor must auto-sling on the blocker's close — not a passive gc.hold
  note or a manual sling a later session must run. A gc.hold note still
  surfaces the bead in gc hook and bd ready as live demand; a blocked-by
  edge excludes it until the blocker lands, then self-clears.
{{- end }}
