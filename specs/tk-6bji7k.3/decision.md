---
name: Bot-flipped status PR labels — decision and design
description: Why gc-toolkit projects rework-vs-ready onto the GitHub PR list with a workflow-owned "status:" label, the taxonomy, the signal it reads, and how the three tk-6bji7k.1 accommodations are built. Record of work on tk-6bji7k.3.
---

# Bot-flipped `status:` PR labels

## The problem

GitHub's `CHANGES_REQUESTED` review state is sticky. A push that answers the
review does not clear it, and neither does re-requesting review, so on the All
Pull Requests list a PR that was reworked and handed back reads the same as one
still being reworked. A scanner cannot tell "look at this again" from "leave it
alone." GitHub offers no native control that carries a current, filterable
"reworked, ready again" signal on that list.

## The decision

Project the workflow's own rework-vs-ready state onto the PR list as a
workflow-owned, bot-flipped GitHub PR label from a mutually-exclusive `status:`
group. Seed values are `status: in-rework` and `status: ready-for-review`. The
refinery already computes this state every pass, so the label is a projection of
what the city knows, not new bookkeeping.

## Why labels, and why bot-flipped

Bot-flipped labels are the only mechanism that puts a correct, current,
filterable rework/ready signal on the native PR list. The pattern is settled in
practice: Rust's triagebot flips `S-waiting-on-author` and `S-waiting-on-review`
on the review verdict and the author's response; Kubernetes Prow flips
`do-not-merge/*`; Mergify does the same by rule. Hand-maintained labels decay —
they go stale on a new push or a rebase, and a push races the label — so the
durable form is bot-flipped, driven by computed state.

Two alternatives were weighed and set aside. A status carried in the PR body or a
comment goes stale the way a PR body already does after a rework, and it makes a
reader open the PR to see it. Draft status is a separate, machine-axis signal
(see below), not a substitute for the human-attention label. The full evidence
survey — industry practice, GitHub-native mechanisms, and the draft-as-CI-lever
question — is recorded on tk-6ttx19's notes.

## The two-signal model, owned by tk-6bji7k.1

This label is the human-attention half of a two-signal model that
[tk-6bji7k.1's proposal](../tk-6bji7k.1/proposal.md) (PR #793) defines and
delegates the label taxonomy to. The model keeps two questions apart, because no
single GitHub control carries both:

- The **machine axis** — may an automated actor merge this — rides the (future)
  draft flag and the internally-computed `pr.machine`.
- The **human-attention axis** — should a person look at this — rides review
  posture and this workflow-owned label.

tk-6bji7k.1 owns the WIP/ready model, the draft-PR-as-surface recommendation, the
commit-reset checkpoint, and Helm discoverability. This bead owns the label
taxonomy and the projection onto the native PR list. The two beads edit the same
three scripts, so the label writer here is factored into one helper both halves
can share.

## The taxonomy

One `status:` label is set at a time; setting a value removes any other `status:`
value on the PR. The dimension is extensible: a future phase (for example
tk-6bji7k.1's `in-review` or `self-checked`) is a new value, and mutual exclusion
removes whatever value it replaces without a redesign.

- **Prefix `status: `.** The colon-grouped prefix groups workflow-state labels on
  the list apart from human triage labels, following Rust's `S-`, Kubernetes'
  `do-not-merge/`, and the widespread colon-grouping convention. The separator is
  `: ` (colon-space), which GitHub renders and filters cleanly.
- **Seed values `in-rework`, `ready-for-review`.**
- **One shared colour for the group** (`GC_PR_STATUS_LABEL_COLOR`, default a
  blue), so the values read as one dimension.

## The signal it reads

The label expresses the city's own rework state, which is the axis GitHub's
sticky posture cannot project:

- **`in-rework`** when an open rework child stands on the anchor
  (`task_kind=rework`, `anchor_bead=<anchor>`, not closed), or the anchor is
  parked by the signoff round cap (`merge_hold=signoff_cap`). Both mean changes
  are outstanding and the ball is in the author's court.
- **`ready-for-review`** otherwise: freshly opened gate-green, reworked and handed
  back (the child closed), awaiting a human review, or approved.

A rework child is filed against the reviewed commit by
`signoff.sh --verdict request-changes` and closes when the fix lands, so the flip
back to ready tracks the reviewed commit, not a marker that outlives it. This is
deliberately **not** derived from two other signals:

- **Not GitHub's `pr_posture`.** `changes_requested` is sticky, so deriving
  `in-rework` from it would never flip back after a rework — the exact failure
  this feature exists to fix.
- **Not `check.<lane>=green` or `pr.machine=settled`.** A lane's `green` is
  commit-agnostic: nothing in the cadence compares it to the head, so it survives
  a rewrite of the reviewed commit (the live stale-green bug tk-4zsj1p). Deriving
  `ready` from it would inherit that staleness.

## The three accommodations

**(a) Human-attention only.** The label reads the rework state and never asserts
that the machine may merge. Machine-readiness and CI stay on `pr.machine` and the
future draft flag. The label does not contradict the machine axis: an open rework
child coincides with `pr.machine=progressing`, and a signoff-cap park coincides
with `pr.machine=wedged-*`. A `ready-for-review` label beside a `progressing`
machine axis (a non-rework blocker being worked) is the two axes doing their
separate jobs, not a contradiction — which is the point of the two-signal model.

**(b) Commit-scoped ready signal.** The ready-vs-rework flip rests on the rework
child, which is scoped to the reviewed commit, rather than on `check.<lane>=green`.
The event-precise flips in `signoff.sh` sit after its gone-pin refusal, which
already refuses a verdict when the reviewed commit was rewritten away, so an
approve never flips to ready on a commit the reviewer did not see.

**(c) Draft-ready.** In `pr-facts.sh` the label projection sits above the
draft-skip, so it runs for every open PR. Today PRs open non-draft, so this is a
no-op difference; when tk-6bji7k.1 opens PRs as drafts early, the projection
already covers them and no code moves.

## Where it lives

- `assets/scripts/pr-status-label.sh` — the single writer of the `status:` label.
  It resolves the origin, ensures the group's labels exist, derives the value from
  the anchor's rework state, and sets it mutually-exclusively. Every GitHub write
  is pinned to the caller's resolved origin, the origin-pinning `pr-open.sh` and
  `pr-facts.sh` already apply; `gh-origin-guard.sh` guards agent-typed `gh`, not a
  script's own calls, so a label is never an approval and stays within the "city
  never approves PRs" policy.
- `pr-open.sh` sets the initial label when a PR is opened gate-green.
- `signoff.sh` flips the label on each verdict: request-changes and the cap park
  to `in-rework`, an approve that leaves no rework outstanding to
  `ready-for-review`.
- `pr-facts.sh` reconciles the label every full pass, so a missed event
  self-heals. `signoff.sh` and `pr-facts.sh` compute the value the same way, so
  the event flip and the reconcile never disagree.

## Deferred

These belong to tk-6bji7k.1 and its follow-ons, and the design leaves room for
them rather than building them:

- Opening PRs sooner, as drafts, as a WIP surface.
- Draft PRs as a CI-cost lever.
- The commit-reset human checkpoint, the self-checked stage, and Helm
  discoverability.
- Stacked PRs, which decompose a large change and are a different problem.
