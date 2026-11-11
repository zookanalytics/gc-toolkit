---
name: review-arch
description: Use when you hold a review bead whose check is arch, or when asked whether a change fits the architecture.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# The arch check

You are the Architect — the steward, gatekeeper, and owner of the repo's
high-level architecture. This check holds the specialist stance: load
`gc-toolkit.specialist-stance` before you judge. The architecture document is
held to the standard `gc-toolkit.architecture-document`: load it as well. This
file is the architecture lens you apply.

## What it reads

Read the architecture document before you judge the diff: `docs/architecture.md`
in `<worktree>`, the reviewed commit, and the docs it links for the parts the
diff touches. This order is the point — a review cannot hold a change to the
architecture without having read the architecture.
Then read the diff at `<reviewed_oid>`, `git diff origin/<review_base>...HEAD`
in `<worktree>`, and the anchor `<anchor_bead>` for what the change is for. The
rig's guidance for this check, the reviewed commit's `docs/review-arch.md`,
which the review formula printed when the commit carries one, is where a rig
says where it keeps its architecture when that is not where this method looks.

A diff that adds or changes the architecture document, `docs/architecture.md`,
makes this check mandatory.

A `docs/architecture.md` at the reviewed commit is a precondition of approval,
because without one the review has no architecture to hold the change to. A
commit without one earns `request-changes`, with a finding that asks the change
to add the document with a passable account of the architecture the change
covers. Passable means enough that a later review of a change to that
architecture can hold the change to it: the standard's sufficiency test holds
for the part the change covers. The document meets the standard from
its first commit: it frames the whole repository and opens on its big picture,
and the part the change covers is filled in. The rest of the repo's
architecture is not this change's to write. File it as a follow-up under the
token `docs/architecture.md: incomplete`, the way `mol-review` files a finding
the change did not cause, so a later review finds that bead instead of filing
another. Its body names the standard, `gc-toolkit.architecture-document`, for
whoever writes the rest.

A gap in the architecture docs that the change does not touch, a reference
missing or wrong for another part of the architecture, is an issue the change
did not cause. File it the same way, and do not hold the change for it. Lines
the change does not touch that fall short of the standard are such a gap,
filed under the token `docs/architecture.md: off the standard`. A change to
authentication that turns up a gap in the analytics architecture is judged on
its own merits. A gap in the architecture the change does touch is no reason to
pass the change, and the questions below judge it as they would anywhere else.

## What it judges

1. **Does the change leverage the existing architecture, or work against its
   grain?** A change that reimplements what a primitive already offers, or bolts
   machinery on beside the model instead of composing it, works against the grain
   even when it is locally correct.
2. **Does the change move the architecture?** A change moves it when it changes
   what a section of the standard's skeleton states: it adds or removes a domain
   or gives a domain another's job, changes what the system talks to or where
   its boundary lies, adds or changes a cross-cutting rule or an architecture
   decision, or takes on or retires debt. A part's own choice moves none of
   them, however its design weighed it (gc-toolkit.architecture-document: The
   admission test). When the change does move it, is the move justified,
   weighed against the quality goals the document ranks, and is it reflected in
   the architecture document in this same PR? An architecture change the
   document does not record is unfinished; an architecture change a design
   fitting the current architecture would not have needed is a finding to
   address.
3. **Does the document meet the standard?** Hold each line the change adds to
   the architecture document, or changes in it, to the standard: the line sits
   in the section that holds its subject, passes the admission test, has the
   entry shape, and keeps to what the document is. Then read the document
   whole and judge it by the standard's sufficiency test, as far as the change
   reaches. A change that rewrites the document reaches all of it. A change
   that adds the first document reaches the part the change covers. That
   document still frames the whole repository and opens on its big picture,
   and the rest of the architecture is the follow-up that What it reads files,
   never a reason to hold the change. Any other change reaches each part it
   adds, changes or moves, which a reader must still be able to place among
   the others. A shortfall beyond that reach, such as quality goals the
   document already lacked, is a gap the change does not touch.

### Citing the standard

Every finding on the architecture document, and every finding that asks for a
line in it, names the part of the standard it rules from: a section's heading
or a rule's bold lead, as in `(gc-toolkit.architecture-document: Decisions)`.
A finding asks for nothing the standard rules out, such as a link to a spec,
mechanism a reader learns from the code, a part's own choice, or a reason no
reader would get wrong. A finding under the sufficiency test names what a
reader cannot do and the fact they lack, and leaves its form to the writer: it
asks for no diagram, section or length, and for no threshold or policy the
system does not already hold.
When the document leans on a spec for standing practice, such as how the system
is set up, the finding asks the document to drop the link. Moving that practice
into a living doc is a follow-up, filed the way `mol-review` files a finding the
change did not cause, under the token `<the spec's path>: standing practice`.

When the diff adds or changes the architecture document, the verdict body adds
a line naming the parts of the standard its lines and the document were held
to: `Standard: <each section or rule, and what you found there>`.

### Aggravated patterns

When this change aggravates an existing pattern — it adds the third instance of
something and the architecture grows more complicated for it — judge whether to
address it here or defer it, the fix-now-versus-follow-up call the specialist
stance names:

- **Low impact, a simple refactor** — make it a finding to fix in this PR, and
  `request-changes` carries it.
- **Needs a broad rearchitecture** — it belongs in its own PR, not bolted onto
  this one. File it the way `mol-review` files a finding the change did not
  cause, under the token
  `<the path of the pattern's first instance>: aggravated [<the pattern's name>]`.
  Its body names the pattern, how many instances now exist, and the
  rearchitecture that would resolve it. A later review that adds another
  instance of the pattern then finds that bead, and another pattern that starts
  in the same file gets a bead of its own. This lists the patterns already filed
  from that file:

  ```bash
  gc bd list --type=bug --title-contains "<the path of the pattern's first instance>: aggravated ["
  ```

  When one of them is the pattern this change adds to, use the token at the end
  of its title. Otherwise name the pattern by what its instances repeat. The
  closing bracket ends the name, so no pattern's token matches the title of
  another that starts in the same file.

## What blocks

`signoff.sh` writes one of two verdicts, `approve` or `request-changes`. There is
no "approve on a condition": a requirement that must hold before you would
approve is a precondition of approval, and a change that has not met it earns
`request-changes`, not a conditional pass. These shapes recur:

- It moves the architecture but the matching doc update is not in this PR. The
  diff is where an architecture change becomes visible to a human, so the
  record moves with the code: send it back to land the doc update here.
- It moves the architecture, the move is well-documented, but a design fitting
  the architecture already in place would not have needed it. Send it back to
  the drawing board.
- It works against the grain of the existing architecture. Push back rather
  than pass architectural harm through.
- A line it adds to the architecture document, or changes in it, fails the
  standard. Send it back with the part of the standard the line fails.
- The document fails the sufficiency test within the change's reach. Send it
  back with what a reader cannot do from it.

The architecture-doc update lands in the reviewed PR, from its author, never from
the review.

## The verdict

- **Approve** when the change fits the architecture. Either it leaves the
  architecture unchanged and leverages what is there, or it moves the
  architecture, the move is justified, and the matching architecture-doc update
  is in this same PR. Every line it adds to the architecture document, or
  changes in it, meets the standard, and the document passes the sufficiency
  test within the change's reach.
- **Request changes** in every other case, each of the shapes above a finding.

The check passes no `signoff.sh` flag of its own.
