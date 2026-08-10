# lint-learned.d — hardened learned rules

One detector per hardened rule. Each executable here is the executable form
of a single learned convention that graduated out of prose — run by
`tools/lint-learned.sh` against changed files, exit 0 clean / 1 findings
(`<file>:<line>: <message>` lines). See
`specs/2026-08-learning-system/implementation-design.md` §8.

A detector lands via a `prompt-update: harden` PR that deletes the
corresponding prose bullet from the learned-conventions fragment **in the
same diff** — the bullet's anchor records `superseded_by: <detector name>`,
so the rule is never stated twice and the fragment shrinks as rules harden.

Detectors retire the same way prose rules do: a challenge that finds the
rule no longer earns its keep produces a PR deleting the detector.

Non-executables here (`*.allow`, this README) are tuning data, not detectors.
