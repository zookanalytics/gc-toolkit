---
name: Holistic-summary gate design (tk-6bji7k.8)
description: Why the required summary-vs-diff check lives in the mol-review rubric (pre-open and post-open) plus a convoy-graduation seed, and which merge paths it covers.
---

# Holistic-summary gate at the merge surface

## The gap

A PR's `## Summary` is authored once, by one agent, and nothing reconciles it
against the whole branch diff before the PR becomes the human-facing
merge-decision surface. `pr-open.sh` composes the body from one anchor's
`metadata.pr_summary`, falling back to the anchor's dispatch `description` and
then a placeholder when that is absent (`pr-open.sh:324-336`). No stage checks
that the published summary accounts for what the branch actually changed.

The review rubric already carries a summary check, but it is reachable on only
one path. `formulas/mol-review.toml`'s `review` step, under **The PR as
published**, tells the reviewer to read the PR page and flag a `## Summary`
that does not state what the diff does — then ends with "Pre-open there is no
page." The default merge path is codex **pre-open**: the review runs against
the branch before any PR exists, `pr-open.sh` publishes the summary verbatim
only after the gate goes green. So on the common path the summary that ships is
never the summary that was reviewed, because at review time the rubric skipped
it.

## The fix

The gate that already reads the full branch diff — the dispatched review — is
where the summary is checked, so the summary-holism requirement is a rubric
item on that review rather than a new stage.

**Both open-states, one obligation (`formulas/mol-review.toml`).** The **The PR
as published** rubric item requires the summary to holistically and currently
account for the entire branch diff in either state. Post-open the reviewer
reads the published page. Pre-open there is no page, so the reviewer reads the
anchor's `metadata.pr_summary` — the exact text `pr-open.sh` will publish — and
holds it to the same standard. An absent or empty pre-open `pr_summary` is
itself a finding, because the published body then falls back to dispatch text
or a placeholder, neither of which describes the diff. The finding locus is
`anchor <id> / pr_summary`, which survives the rebase a line number would not.
The two-lane quorum path inherits this: `mol-review-quorum-signoff.toml`
applies `mol-review.toml`'s "What to check" list verbatim.

**Convoy graduation seeds a summary (`convoy-graduate.sh`).** A graduated
integration convoy has no authored `pr_summary` — graduation stamps
`branch`/`target`/`merge_strategy`/`graduation` and nothing else — so its
published `## Summary` would fall back to the convoy bead's dispatch
description, and validation alone has nothing to validate. Graduation composes
a seed `pr_summary` from the members it lands: each member's title and, where
present, that member's own already-reviewed `pr_summary`. The seed is the union
of the parts; the pre-open review then validates that union against the
integrated diff, which is where cross-member interactions surface. The seed is
best-effort and never blocks graduation: an unreadable member list or bead
leaves the summary unset and the pre-open review flags the absence.

**The opt-out stays explicit (`mol-refinery-patrol.toml`).** The summary check
rides the dispatched review, so `check_set=none` — the gateless-by-choice
sentinel that skips review dispatch entirely (`gate-ensure.sh:572`) — opts out
of the summary check as well. That is stated where `check_set` is defined. The
default is `codex`, which is gated; `mr` is the only strategy with a PR and a
summary, and direct-merge work opens no PR.

## Boundary

This is content accountability: the summary is holistic and accurate.
Propagation — the published body tracking the anchor `pr_summary` after a
rework restamps it — is tk-t1130i (PR #810) and stays separate. There is no
`gc:pr-summary` marker in the tree; `pr-open.sh` composes the body fresh, and
the read-modify-write that preserves operator text is tk-t1130i's concern on
the publish path, not this one.
