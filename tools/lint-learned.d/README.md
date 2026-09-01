# lint-learned.d — pack hygiene, not the learning system

These detectors are ordinary pack hygiene: a hardened rule has graduated OUT
of prompts INTO tooling. The learning system's ceiling-raising surface is the
operator profile + conventions pipeline (docs/feedback-learning.md).

One detector per hardened rule. Each executable here is the executable form
of a single learned convention that graduated out of prose — run by
`tools/lint-learned.sh` over every tracked file, exit 0 clean / 1 findings
(`<file>:<line>: <message>` lines). See
`specs/2026-08-learning-system/implementation-design.md` §8.

## The admission test

A detector may state an invariant and nothing else: **every finding it can
produce is a defect, never a judgment call.** A rule that is only mostly true
produces findings a reasonable author will decline, and declined findings
either train people to ignore the runner or pile into a backlog nobody
clears. Either way the gate stops meaning anything.

Two questions settle a candidate before it is written:

- Is there a context where the flagged shape is correct? If there is, the
  rule is guidance, not an invariant.
- Does the candidate need exemption categories to be tolerable? A rule that
  must carve out cases to avoid being wrong is admitting it is not one.

Skipping the *documentation* of a hazard is different and is allowed: a
detector ignores its own directory and the specs describing the bug it hunts,
because that text states the rule rather than breaks it.

Guidance that fails the test is still real guidance. It belongs in the prose
that instructs agents — the operator profile and the learned-conventions
fragments — where an author reads it with the case in front of them.

The test is also why the runner reads the whole tree rather than a diff.
Scoping to changed files cannot make the codebase satisfy an invariant; it
only picks who gets told, and it turns every honest report that the rule does
not hold into a backlog item. A finding anywhere is a finding.

## Landing and retiring

A detector lands via a `prompt-update: harden` PR that deletes the
corresponding prose bullet AND its anchor from the learned-conventions
fragment **in the same diff** — the rule is never stated twice and the
fragment shrinks as rules harden. The pattern bead records the detector as
its successor (metadata, e.g. `superseded_by` on the bead), so provenance
lives on the bead and the harden PR, not in the fragment.

Detectors retire the same way prose rules do: a challenge that finds the rule
no longer earns its keep produces a PR deleting the detector. A detector that
fails the admission test retires on that ground alone, and the same PR puts
its content back into prose if the prose does not already carry it.

Non-executables here (this README) are data, not detectors.
