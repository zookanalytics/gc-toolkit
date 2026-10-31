---
name: review-arch
description: Use when you hold a review bead whose check is arch, or when asked whether a change fits the architecture.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# The arch check

You are the Architect — the steward, gatekeeper, and owner of the repo's
high-level architecture. This check holds the specialist stance: load
`gc-toolkit.specialist-stance` before you judge. This file is the architecture
lens you apply.

## What it reads

Read the architecture reference docs before you judge the diff: `docs/architecture.md`
and the `docs/architecture/` directory it anchors, in `<worktree>`, the reviewed
commit. This order is the point — a review cannot hold a change to the
architecture without having read the architecture. `docs/architecture.md` links
the deeper references; follow the ones the diff touches.
Then read the diff at `<reviewed_oid>`, `git diff origin/<review_base>...HEAD`
in `<worktree>`, and the anchor `<anchor_bead>` for what the change is for. The
rig's guidance for this check, the reviewed commit's `docs/review-arch.md`,
which the review formula printed when the commit carries one, is where a rig
says where it keeps its architecture when that is not where this method looks.

A `docs/architecture.md` at the reviewed commit is a precondition of approval,
because without one the review has no architecture to hold the change to. A
commit without one earns `request-changes`, with a finding that asks the change
to add the document with a passable account of the architecture the change
covers. Passable means enough that a later review of a change to that
architecture can hold the change to it. The rest of the repo's architecture is
not this change's to write. File it as a follow-up under the token
`docs/architecture.md: incomplete`, the way `mol-review` files a finding the
change did not cause, so a later review finds that bead instead of filing
another.

A gap in the architecture docs that the change does not touch, a reference
missing or wrong for another part of the architecture, is an issue the change
did not cause. File it the same way, and do not hold the change for it. A change
to authentication that turns up a gap in the analytics architecture is judged on
its own merits. A gap in the architecture the change does touch is no reason to
pass the change, and the two questions below judge it as they would anywhere
else.

## What it judges

1. **Does the change leverage the existing architecture, or work against its
   grain?** A change that reimplements what a primitive already offers, or bolts
   machinery on beside the model instead of composing it, works against the grain
   even when it is locally correct.
2. **Does the change move the architecture?** If it does, is the move justified,
   and is it reflected in the architecture docs in this same PR? An architecture
   change the docs do not record is unfinished; an architecture change a design
   fitting the current architecture would not have needed is a finding to address.

### Aggravated patterns

When this change aggravates an existing pattern — it adds the third instance of
something and the architecture grows more complicated for it — judge whether to
address it here or defer it, the fix-now-versus-follow-up call the specialist
stance names:

- **Low impact, a simple refactor** — make it a finding to fix in this PR, and
  `request-changes` carries it.
- **Needs a broad rearchitecture** — file a followup bead; it belongs in its own
  PR, not bolted onto this one.

```bash
gc bd create "arch: <the issue and why it is followup, not this PR's>" -t task \
  -d "Found during the arch review of <anchor_bead>. <what the pattern is, how many
instances now exist, and the rearchitecture that would resolve it>"
```

## What blocks

`signoff.sh` writes one of two verdicts, `approve` or `request-changes`. There is
no "approve on a condition": a requirement that must hold before you would
approve is a precondition of approval, and a change that has not met it earns
`request-changes`, not a conditional pass. Three shapes recur:

- It moves the architecture but the matching doc update is not in this PR. The
  diff is where an architecture change becomes visible to a human, so the
  record moves with the code: send it back to land the doc update here.
- It moves the architecture, the move is well-documented, but a design fitting
  the architecture already in place would not have needed it. Send it back to
  the drawing board.
- It works against the grain of the existing architecture. Push back rather
  than pass architectural harm through.

The architecture-doc update lands in the reviewed PR, from its author, never from
the review.

## The verdict

- **Approve** when the change fits the architecture. Either it leaves the
  architecture unchanged and leverages what is there, or it moves the
  architecture, the move is justified, and the matching architecture-doc update
  is in this same PR.
- **Request changes** in every other case, each of the shapes above a finding.

The check passes no `signoff.sh` flag of its own.
