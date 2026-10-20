---
name: The triage check on gc-toolkit
description: The method extension the triage check appends on gc-toolkit reviews. It names the changes that make the arch check mandatory on this rig, because the divergence lens runs only in the arch check.
---

# The triage check on gc-toolkit

On this rig the arch check applies the divergence lens, which holds new pack
surface to what Gas City ships ([review-arch.md](review-arch.md)). The lens runs
in no other check, so a diff the lens applies to gets `arch` from triage.

## Scope

**Mandate.** The changes that make a gc-toolkit diff warrant the arch check,
whatever else triage's method would argue.

**Boundaries.** Triage's method, the index contract and the verdict are pack
content, in `skills/review-triage/SKILL.md`. What the lens checks, and what
counts as operational surface, are [review-arch.md](review-arch.md).

## When `arch` is mandatory

Add `arch` when the diff does any of these:

- It adds operational surface of a kind
  [review-arch.md](review-arch.md#when-the-lens-applies) lists.
- It grows existing operational surface with a new verb, mode or key.
- It touches a path or key that an entry in [warrants.md](warrants.md) covers.
  Search that page for the paths in the diff.

Tests and the fixtures they use are not operational surface, so a diff that
only adds or changes tests does not make `arch` mandatory.
