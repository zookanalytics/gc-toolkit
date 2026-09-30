---
name: The PM check — design record
description: Why the pm review check is shaped as it is — the product lens (is it the right thing for the operator, can the operator decide), the peer-not-order-taker stance and its grounding in established product-management practice, the reference-docs convention applied (the PM stewards docs/product-goals.md), the generic-method-as-skill decision, and the delineation from the correctness and demo checks. Companion to specs/tk-3h9mzz/review-gates-foundation.md.
---

# The PM check

The `pm` check is the product lens the review-gates foundation
(`specs/tk-3h9mzz/review-gates-foundation.md`) left as a seam. It is a specialist
check filed under the same operator ruling as `arch` (tk-e4zrc5), and it lands as
content within the foundation's model: one index row, one generic-method arm, and
the reference documentation it reads. It needs no new dispatch or
merge-predicate mechanism — both already flow any check name.

## What it judges

The check is the product lens on a change, applied by a reviewer who stands in for
the operator as a peer to the author, not an order-taker. It carries two questions
and a stance, not a checklist:

- is it the right thing — does the change move the user problem its anchor states
  (the outcome), or a proxy of it that was easier to ship; and is that the right
  problem to be solving, even when the anchor named it;
- can the operator decide — can they accept or reject from the PR's summary,
  evidence, and any demo, without reconstructing the case.

The stance is the load-bearing part. A change can satisfy its bead's wording and
still be wrong, so the PM judges the intent the change serves and pushes back when
the diff does what it was told but not what the operator needs. That is what lets
the role raise the bar on what the city ships rather than ratify whatever was
built.

## Grounding

The lens draws on established product-management practice, so the method
represents the PM perspective rather than one author's first draft of it:

- The PM owns **value and viability** — is this worth shipping to the operator —
  while the correctness check owns feasibility, whether it is built right. This is
  the SVPG split of the four product risks (value, usability, feasibility,
  viability): the reviewer's job is the value question correctness does not ask.
  (Marty Cagan / Silicon Valley Product Group.)
- "The right thing, not a proxy" is **outcomes over output**: an outcome is a
  change in behavior that matters, and shipping a feature that stands in for it is
  the drift the check names. (Josh Seiden, *Outcomes Over Output*.)
- "Can the operator decide" is **working backwards from the customer who is not in
  the room**: the operator reads the PR the way a customer reads a launch, so the
  presentation must carry the value plainly enough to act on. (Amazon's
  working-backwards / PR-FAQ practice.)
- The peer-not-order-taker stance is Cagan's distinction between an **empowered
  product team** and a **feature team**, whose PM grooms a backlog to order and is
  measured on output. A reviewer who only asks "did they build what the bead said"
  is that order-taker; the check exists to keep the city's review from becoming
  one.

## Delineation from the other checks

The check does not re-review correctness: whether the summary mechanically
accounts for the diff is `correctness`'s bar, and a bug is `correctness`'s
finding. It does not touch a recording: the check index carries a separate `demo`
check that produces and grades the recording, dispatched by triage. The PM's only
demo concern folds into presentation — is this a change the operator needs to see,
and does the PR offer it — so a warranted-but-absent demo is a presentation
finding it names and points at the demo tooling, while the recording itself stays
`demo`'s. The PM owns the value question: is this the right thing, told so the
operator can see that it is. It never widens `check_set`; only triage adds a
check, including `pm` itself.

## The reference-docs convention, applied

The foundation sets the convention (`review-gates-foundation.md`, "The
reference-docs convention"): a specialist check reads reference documentation
before it judges. The `pm` check stewards `docs/product-goals.md` — the user
problems the city solves, the surfaces the operator watches, and what a
presentation the operator can act on looks like. It is read from the reviewed
commit, and any longer reference it cites is an ordinary repo doc it points to.
The check enforces through findings and never commits; drift it finds in its own
reference doc is maintenance it files.

## Why the generic method is a skill

The generic method is `skills/review-pm/SKILL.md`, named from the index and
summarized in the `review-dispatch-body.sh` arm, the same shape as `triage`. It
is deliberately not `docs/review-pm.md`: that name is the rig-extension slot the
dispatch body reads from the reviewed commit and appends to the generic method,
so the generic method cannot live there without the composition appending the
method to itself. A rig that wants to tighten the PM method for its own repo adds
`docs/review-pm.md`; the pack ships the generic method as the skill and the arm.
