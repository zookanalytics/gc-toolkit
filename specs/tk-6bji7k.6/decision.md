---
name: Human-checkpoint materiality rule, and the review-round commit discipline
description: Decision record for tk-6bji7k.6. The merge gate stops requiring a human approval AT the head and instead asks whether the change since the approved commit is material; a sign-off stands across an immaterial change and a re-review is owed only on a material one. Materiality is a semantic judgment an agent issues, with a mechanical no-op fast path; the approval itself is never touched. The review-round commit discipline (fixups within a round, squash only between rounds) is what keeps the since-sign-off diff legible and the approved commit reachable for that judgment. Builds parts 3 and 4 of specs/tk-6bji7k.1/proposal.md.
---

# Human-checkpoint materiality rule

This builds two pieces of `specs/tk-6bji7k.1/proposal.md`: the materiality
rule for a standing human approval ("A standing approval and the live head"),
and the fixup-then-squash commit discipline for review rounds.

## What the merge gate did, and why it was wrong

`merge.sh` satisfied the `approval` gate only from an APPROVED review whose
`commit_id` equalled the live head (`select(.commit_id == $head)`). Any commit
after the approval — a rebase, a one-line fixup, a merge that only brought the
base current — dropped the approval, held the merge, and asked the operator to
approve again.

That is the SHA-binding the operator ruled out. GitHub reviews are not tied to
SHAs: an APPROVED verdict persists across pushes, the commit id on a review is
metadata rather than a binding, and dismiss-stale-on-push is off and stays off
because it makes routine rebases far harder than they earn. Requiring the
approval at the head re-reviewed a pure rebase and every trivial fixup, which is
not what the sign-off meant. `lane-state.sh` already reads a human approval
commit-agnostically (an approval "backs every lane… needs no such pin");
`merge.sh` was the one reader still binding it to the head.

## The rule

A standing human APPROVED review satisfies the `approval` gate wherever it was
given, as long as the change since the approved commit is not **material**. A
sign-off stands across a change that does not alter the reviewed diff in
substance; a re-review is owed only on a material change. The risk this guards
is a material rewrite shipping under an earlier sign-off — not an over-eager
reset. The approved commit is the base the change is measured from, never a
binding on the review's validity.

Materiality is a semantic question, so an agent judges it. `materiality.sh`
carries the mechanism:

- `classify` reads the standing approval's commit and the live head and returns
  one word: `none` (no standing approval), `at-head`, `immaterial` (the head
  adds no file change over the approved commit — the one case decided without a
  judgment), `stands` (an agent judged a content change immaterial and recorded
  it for this exact head), or `owed` (a content change no agent has cleared: a
  re-review is owed).
- `record` writes an agent's verdict, `approval_materiality =
  <stands|owed>@<approved-oid>..<head-oid>`, and is the only writer of that key.
  The verdict binds to the head it judged, so a later commit is unjudged and
  falls back to a fresh read.

`merge.sh` consults `classify` at the approval arm: `at-head`, `immaterial` and
`stands` satisfy the gate; `owed` and an unreadable answer hold the merge for
re-review and record `settled` so the row is the operator's. The human approval
is never written or dismissed by any of this — the city dismisses only its own
superseded machine `CHANGES_REQUESTED`, never a human verdict.

### Why this is not the machine-gate materiality skip that was declined

`specs/tk-w26b6/stale-gate-re-dispatch.md` declined a materiality skip for the
**machine** `check.<lane>` markers, on the ground that advancing a marker is
writing a gate verdict, which only `signoff.sh` may do (component-model I7). It
also ruled that if materiality were ever judged, it belongs in a verdict an
agent issues, not in a second writer bolted into the cadence.

This rule honours both. It governs the `approval` gate, which takes no
`check.*` marker and which `merge.sh` already evaluates on its own, so refining
that evaluation adds no second writer of a lane verdict. `approval_materiality`
is a distinct key, written only by `materiality.sh`, and only when an agent
issues the verdict — no reconcile pass promotes it. Machine lanes stay
commit-agnostic; this is the human gate's counterpart to *Green survives new
commits*, and only the human gate's.

## The review-round commit discipline

The materiality read stands on two properties the round's commit discipline
holds. Within a round a fix is a commit: the rework child merges its base in and
pushes a fast-forward, never a rebase, amend, or force-push. That keeps a
reviewer's inline comments anchored to the commits they were left on, and keeps
the approved commit reachable — the base `materiality.sh` measures against. A
rewrite that drops the approved commit off the branch answers `gone`, and the
merge then holds for a fresh look rather than merging a change it cannot weigh.

History is rewritten only between rounds, and only on the disposable feature
branch, never on a shared or integration branch that carries already-merged pull
requests. The land itself is one squash (`merge.sh --squash`), so a change
reaches its base as a single legible commit whatever the round count. The
within-round half is already enforced by the rework resume instruction
(`pr-facts.sh`); this records it as the discipline the materiality rule depends
on.

## Built here, and deferred

Built and tested: `materiality.sh` (`classify` and `record`), the `merge.sh`
approval-arm change, the `approval_materiality` registration in
`lifecycle/lifecycle.toml`, and the documentation in `docs/state-machine.md`.

Deferred to **tk-8c6na2**: the automatic dispatch of the agent judgment. When a
content change lands past a standing approval and no verdict is recorded,
`merge.sh` holds `owed` and surfaces `needs-review` — the same hold the old
`commit_id != head` produced, so there is no regression. Until the auto-dispatch
lands, the mechanical `immaterial`/`at-head` relief and the recorded-verdict
path both run, and an agent or the operator can clear a judged-immaterial change
with `materiality.sh record --verdict stands`. The cost of waiting is that a
trivial fixup after an approval still asks for a human re-review unless the
verdict is recorded by hand.
