---
name: Integration-target identification — label group and banner
description: Decision for tk-6bji7k.9. The integration-target marker is a sibling label group (`base: integration`), not a value added to the mutually-exclusive `status:` group, and it rides a standing body banner. Both are set at pr-open where the base is known.
---

# Integration-target identification: a sibling group, not a status value

An owned convoy's phase opens a child pull request into `integration/<convoy-id>`.
Approving that pull request mints the phase into the integration branch and leaves
`main` untouched, so it must be unmistakable that the pull request is a checkpoint,
not a merge to `main` ([specs/tk-6bji7k.1/proposal.md](../tk-6bji7k.1/proposal.md),
"Where a checkpoint lands"). Two surfaces carry that, both set at pr-open where the
base branch is known: a workflow-owned label on the pull request list, and a
standing body banner.

## The label is a sibling group, `base:`, not a `status:` value

The `status:` group answers one question — who must act on the pull request next —
and its values are mutually exclusive: `pr-status-label.sh set` removes every other
`status:` value when it writes one, and `pr-facts.sh` recomputes it every cadence
pass from the anchor's posture, holds, and rework children.

Where an approved change lands is a different, orthogonal question. A checkpoint
pull request is at once `status: needs-review` (a human should review this head)
and targeted at integration (approving it mints a phase). A shared
mutually-exclusive group cannot hold both at once, so folding the marker into
`status:` would force a false choice between "who acts next" and "where it lands."
The marker is therefore a **sibling group** with its own prefix, `base:`.

The two groups never touch: `pr-status-label.sh set` matches only labels under
`status: `, so it never removes a `base:` label, and `mark_base` only ever adds a
`base:` label, so it never disturbs `status:`.

The base marker is also **standing, not reconciled**. A pull request's base does
not change, so the label is set once at pr-open (where the base is known) and never
recomputed. That is why it does not join the `derive`/`reconcile` machinery that
keeps `status:` current every pass.

## The value

One value today: `base: integration`. A base under `integration/` is a convoy
checkpoint. A `main`-targeted pull request is the default and carries no `base:`
label — the absence of the marker is itself the "targets main" signal, so mainline
pull requests are not cluttered with a redundant label. The convoy id is not
encoded in the label (that would mint a label per convoy and clutter the list); it
rides the banner instead, and the board already records `merged_target`.

Detection reuses the predicate `convoy-graduate.sh` already applies to the same
concept: a target that `startswith("integration/")`.

## The banner

`pr-open.sh compose_managed` emits a standing banner at the top of the managed
`gc:pr-summary` region when the target is under `integration/`. It states that the
pull request merges into `integration/<convoy-id>`, that approving it mints this
phase while `main` does not move, and that the broader review runs at graduation.
Because it lives in the managed region, an adoption refresh re-splices it so it
stays correct, and pr-stack's own section is untouched.

Both surfaces are best-effort at the call site: a label or banner is not an
approval, and neither failure unwinds an opened pull request
(`assets/scripts/gh-origin-guard.sh` pins every GitHub write to the origin).
