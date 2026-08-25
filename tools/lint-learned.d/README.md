# lint-learned.d — pack hygiene, not the learning system

These detectors are ordinary pack hygiene: a hardened rule has graduated OUT
of prompts INTO tooling. The learning system's ceiling-raising surface is the
operator profile + conventions pipeline (docs/feedback-learning.md).

One detector per hardened rule. Each executable here is the executable form
of a single learned convention that graduated out of prose — run by
`tools/lint-learned.sh` against changed files, exit 0 clean / 1 findings
(`<file>:<line>: <message>` lines). See
`specs/2026-08-learning-system/implementation-design.md` §8.

A detector lands via a `prompt-update: harden` PR that deletes the
corresponding prose bullet AND its anchor from the learned-conventions
fragment **in the same diff** — the rule is never stated twice and the
fragment shrinks as rules harden. The pattern bead records the detector as
its successor (metadata, e.g. `superseded_by` on the bead), so provenance
lives on the bead and the harden PR, not in the fragment.

Detectors retire the same way prose rules do: a challenge that finds the
rule no longer earns its keep produces a PR deleting the detector.

Non-executables here (`*.allow`, this README) are tuning data, not detectors.
