---
name: The triage check on gc-toolkit
description: Use when you run the triage check on a gc-toolkit change, or when you want to know which specialist checks a gc-toolkit change is sure to get.
---

# The triage check on gc-toolkit

Triage's method adds a specialist check when the diff warrants one, and usually
adds none. On this rig some kinds of change always get a particular check. Each
section below names one such check, why it is mandatory and the changes that
make it so.

## Scope

**Mandate.** The changes that make a gc-toolkit diff warrant a specialist check,
whatever else triage's method would argue.

**Boundaries.** Triage's method, the index contract and the verdict are pack
content, in `skills/review-triage/SKILL.md`. What a check judges is set by that
check's own method and, where this rig keeps one, by this rig's guidance for it.

## When `arch` is mandatory

On this rig the arch check applies the divergence lens, which holds new pack
surface to what Gas City ships ([review-arch.md](review-arch.md)). The lens runs
in no other check, so add `arch` when the diff does any of these:

- It adds operational surface of a kind
  [review-arch.md](review-arch.md#when-the-lens-applies) lists.
- It grows existing operational surface with a new verb, mode or key.
- It touches a path or key that an entry in [warrants.md](warrants.md) covers.
  `tools/warrants-touched.sh --base origin/<the review's base>`, run in the
  review's worktree, lists those entries.

Tests and the fixtures they use are not operational surface, so a diff that
only adds or changes tests does not make `arch` mandatory.

## When `pm` is mandatory

The pm check judges a change against the product goals, the operator-side
reading of [foundation.md](foundation.md) in
[product-goals.md](product-goals.md). No other check judges a change against
them, so add `pm` when the diff changes the pack's behavior, which is what an
agent must do or what reaches the operator, in any of these:

- a skill's method;
- a formula's steps or prose;
- an agent prompt or a template fragment;
- a review check's method, or this rig's guidance for a check, such as this
  page;
- a doc that binds agents, such as `AGENTS.md` or [foundation.md](foundation.md).

An edit that changes neither what an agent must do nor what reaches the
operator, such as a mechanical refactor, a typo fixed or a link mended, does not
make `pm` mandatory, and neither do tests and the fixtures they use. A diff of
code alone, such as a script or a service, is left to triage's method.
