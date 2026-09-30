---
name: The PM check — design record
description: Why the pm review check is shaped as it is — the product lens (right problem, meaningful presentation, demo warrant), the reference-docs convention applied (the PM stewards docs/product-goals.md), the generic-method-as-skill decision, and the delineation from the correctness and demo checks. Companion to specs/tk-3h9mzz/review-gates-foundation.md.
---

# The PM check

The `pm` check is the product lens the review-gates foundation
(`specs/tk-3h9mzz/review-gates-foundation.md`) left as a seam. It is a specialist
check filed under the same operator ruling as `arch` (tk-e4zrc5), and it lands as
content within the foundation's model: one index row, one generic-method arm, and
the reference documentation it reads. It needs no new dispatch or
merge-predicate mechanism — both already flow any check name.

## What it judges

The operator asked for a check that judges "does this solve the right user
problem and is it presented to the operator in a meaningful way, does it need a
demo." The method carries that as three questions and a lens, not a checklist:

- the right problem — does the change move the user problem its anchor states, or
  a proxy of it;
- meaningful presentation — can the operator decide from the PR's summary,
  evidence, and demo without reconstructing the case;
- the demo — does an operator-watched surface change warrant a demo, and is that
  need met.

## Delineation from the other checks

The check does not re-review correctness: whether the summary mechanically
accounts for the diff is `correctness`'s bar, and a bug is `correctness`'s
finding. It does not judge a recording's content: whether a demo proves what it
claims is `demo`'s. The PM owns the value question — is this the right thing, told
so the operator can see that it is — and where a warranted demo is missing it
files the gap and points at the demo tooling, leaving the recording's content to
`demo`. It never widens `check_set`; only triage adds a check, including `pm`
itself.

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
