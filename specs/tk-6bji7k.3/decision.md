---
name: Bot-flipped status PR labels — decision and design
description: Why gc-toolkit projects who-must-act-next (working / needs-review / needs-attention) onto the GitHub PR list with a workflow-owned "status:" label, the taxonomy, the signal it reads, and how the three tk-6bji7k.1 accommodations are built. Record of work on tk-6bji7k.3.
---

# Bot-flipped `status:` PR labels

## The problem

The city runs a PR through rework, re-review, and merge, but none of that state
shows on GitHub's pull request list. A person scanning the list cannot tell a PR
the city is still working from one waiting on their review from one stuck needing
them to unstick it, without opening each one. GitHub carries no native, filterable
signal for who must act on a PR next.

## The decision

Project the workflow's own state — who must act on a PR next — onto the PR list as
a workflow-owned, bot-flipped GitHub PR label from a mutually-exclusive `status:`
group. The three values are `status: working`, `status: needs-review`, and
`status: needs-attention`. The refinery already computes this state every pass, so
the label is a projection of what the city knows, not new bookkeeping.

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
tk-6bji7k.1's `self-checked`) is a new value, and mutual exclusion removes
whatever value it replaces without a redesign.

Each value answers one question — who must act on the PR next:

- **`status: working`** — the city holds the ball: a rework child stands on the
  reviewed commit, or an approved PR is merging. No human input needed.
- **`status: needs-review`** — settled at the current head: a human review or
  re-review of this commit is the next action.
- **`status: needs-attention`** — the city stopped without settling: a signoff-cap
  park, a merge or rebase hold, or an approved PR wedged with no live work. The
  ask is "unstick us", not "review the diff".

Precedence when inputs overlap: `needs-attention` > `working` > `needs-review`.

- **Prefix `status: `.** The colon-grouped prefix groups workflow-state labels on
  the list apart from human triage labels, following Rust's `S-`, Kubernetes'
  `do-not-merge/`, and the widespread colon-grouping convention. The separator is
  `: ` (colon-space), which GitHub renders and filters cleanly.
- **One shared colour for the group** (`GC_PR_STATUS_LABEL_COLOR`, default a
  blue), so the values read as one dimension.

## The signal it reads

The label reads the city's own state off the facts the refinery already stamps on
the anchor each pass — the `pr_posture` and `pr_merge_state`, the merge and rebase
holds — and the anchor's rework children. Precedence is `needs-attention` >
`working` > `needs-review`:

- **`needs-attention`** when the signoff round cap parked the anchor
  (`merge_hold=signoff_cap` paired with a `signoff_cap` gate), a merge or rebase
  hold stands on it, or the PR is approved but wedged (`pr_merge_state` BLOCKED)
  with no rework child in flight.
- **`working`** when an open rework child stands on the anchor
  (`task_kind=rework`, `anchor_bead=<anchor>`, not closed), or the PR is approved
  and merging (`pr_posture` approved, not BLOCKED).
- **`needs-review`** otherwise: settled at the head with no open rework — freshly
  opened gate-green, reworked and handed back (the child closed), or a review left
  non-blocking comments.

The `working`->`needs-review` flip rests on the rework child, which
`signoff.sh --verdict request-changes` files against the reviewed commit and which
closes when the fix lands, so it tracks the reviewed commit rather than a marker
that outlives a rewrite of it. That commit-scoping is why the flip reads the child
and not two signals it otherwise could:

- **Not GitHub's sticky `CHANGES_REQUESTED`.** It does not clear when a rework
  lands, so reading it would hold the label at `working` after the fix is handed
  back — the flip to `needs-review` would never come.
- **Not `check.<lane>=green` or `pr.machine=settled`.** A lane's `green` is
  commit-agnostic: nothing in the cadence compares it to the head, so it survives
  a rewrite of the reviewed commit (the live stale-green bug tk-4zsj1p). Reading
  it would let the label read settled over a commit no one re-reviewed.

`pr_posture` itself is read only to split the approved case (merging vs wedged)
and to name the awaiting-review states; the `changes_requested` value is never a
state trigger, so its stickiness cannot reach the label.

## The three accommodations

**(a) Never an approval.** The label answers who must act next and never asserts
that the machine may merge: `working` says the city is engaged (reworking or
merging), not that the merge gate is satisfied. Machine-readiness and CI stay on
`pr.machine` and the future draft flag. The two axes are consistent, not
redundant: an open rework child coincides with `pr.machine=progressing`, a
signoff-cap park with `pr.machine=wedged-*`. A `needs-review` label beside a
`progressing` machine axis (a non-rework blocker being worked) is the two axes
doing their separate jobs, which is the point of the two-signal model.

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
  the anchor's state, and sets it mutually-exclusively. Every GitHub write
  is pinned to the caller's resolved origin, the origin-pinning `pr-open.sh` and
  `pr-facts.sh` already apply; `gh-origin-guard.sh` guards agent-typed `gh`, not a
  script's own calls, so a label is never an approval and stays within the "city
  never approves PRs" policy.
- `pr-open.sh` sets the initial label when a PR is opened gate-green: a PR with no
  review yet is `needs-review`.
- `signoff.sh` flips the label on each verdict: request-changes to `working` (a
  rework child now stands on the anchor), the round-cap park to `needs-attention`,
  and an approve reconciles to the current state.
- `pr-facts.sh` reconciles the label every full pass, so a missed event
  self-heals. The flips and the reconcile derive from the same anchor state, so
  they never disagree.

## Deferred

These belong to tk-6bji7k.1 and its follow-ons, and the design leaves room for
them rather than building them:

- Opening PRs sooner, as drafts, as a WIP surface.
- Draft PRs as a CI-cost lever.
- The commit-reset human checkpoint, the self-checked stage, and Helm
  discoverability.
- Stacked PRs, which decompose a large change and are a different problem.
