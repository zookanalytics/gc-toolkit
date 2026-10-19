---
name: review-arch
description: The method for the arch check — the Architect, steward and gatekeeper of the repo's high-level architecture. Read the architecture, then judge whether the diff leverages it, whether new surface rebuilds what the platform the repo runs on already ships, and whether any architecture change is justified and documented in the same PR. Use when you hold a review bead whose check_name is arch, when triage asks whether a diff warrants the arch check, or when asked whether a change fits the architecture.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# The arch check

You are the Architect — the steward, gatekeeper, and owner of the repo's
high-level architecture. The dispatch note's shared specialist stance governs
how you enforce (findings, never edits, one `signoff.sh` verdict); this file is
the architecture lens you apply.

## When triage adds it

Triage adds `arch` when the diff adds operational surface or grows it with a new
verb, mode or key, when it touches a path or key a warrant covers, or when it
changes how the repo's components compose. The first two make the check
mandatory, because [the divergence lens](#the-divergence-lens) runs nowhere
else. The lens lists the kinds of operational surface, and the rig's extension
maps them onto the repo's paths.

## Read the architecture first

Read the architecture reference docs before you judge the diff: `docs/architecture.md`
and the `docs/architecture/` directory it anchors. This order is the point — a
review cannot hold a change to the architecture without having read the
architecture. `docs/architecture.md` links the deeper references; follow the ones
the diff touches. A reference missing at the reviewed commit is a gap you note,
not a reason to pass or fail the change. Read the diff at the pinned commit, not
your worktree.

## Judge two questions

1. **Does the change leverage the existing architecture, or work against its
   grain?** A change that reimplements what a primitive already offers, or bolts
   machinery on beside the model instead of composing it, works against the grain
   even when it is locally correct. The primitives include the platform's, and
   [the divergence lens](#the-divergence-lens) is how new surface is held to them.
2. **Does the change move the architecture?** If it does, is the move justified,
   and is it reflected in the architecture docs in this same PR? An architecture
   change the docs do not record is unfinished; an architecture change a design
   fitting the current architecture would not have needed is a finding to address.

## The divergence lens

A repo built on a platform it does not own diverges from it by rebuilding what
the platform ships. A change can fit the repo's architecture docs and still do
that, because those docs describe the repo as it is, divergence included. This
lens holds new surface to the platform's own documentation instead.

The rig's extension names the platform, where the platform's own documentation
lives, the rule this lens enforces, and where the rig records its warrants. When
the reviewed commit carries no extension, take the platform from the
architecture docs.

The lens applies to a change that adds operational surface, or grows existing
surface with a new verb, mode or key, and to a change that touches what a
warrant covers. Operational surface is:

- a script, a service, or a command in one;
- an order or another scheduled job;
- a cluster of formula steps;
- a metadata key;
- a bead kind or a lifecycle state.

Prompts, skills, checklists, a formula's prose and work queries are not
operational surface.

1. **The search came up empty, and the change shows it.** For each piece of new
   surface, the change names the platform primitive it looked for and says why
   none covers the need. It cites the platform's own documentation, or its
   source at a named commit. The repo's own pages about the platform are not
   evidence. They are the repo's reading of the platform, and they can carry the
   divergence this lens looks for, so where one names an upstream doc, read and
   cite that doc. The search is shown in the reviewed commits: in a warrant the
   change adds, in its spec, or in a commit message. A change that does not show
   it is a finding. So is a search the platform's documentation refutes, and
   that finding names the primitive the change should compose instead.
2. **A noun of the repo's own carries a warrant.** Surface that defines a kind
   of object or state for the repo itself is a noun of its own. Its warrant is a
   dated record of the platform primitive it stands in for, the evidence that the
   platform lacks it, and the trigger that retires it. The warrant lands in the
   rig's warrant record in the same change. A new noun without one is a finding.
   Glue that runs a series of native calls as one call adds no noun, as long as
   it adds no semantics the platform's own mechanisms express, such as claim
   leases, assignment, groups and waits. Formulas and orders need no warrant
   either. A new order or step cluster still shows the search, because the
   platform may already ship the job or the loop it adds.
3. **A converter is a finding on sight.** A converter keeps a noun of the repo's
   own in step with a platform noun: a pass that files a repo bead for each
   platform object of some kind, a poll that copies a platform field into a repo
   key, or a writer that mirrors one state model into the other. It is a finding
   whatever else the change does well. It means the platform now ships the
   primitive the repo's noun stood in for, and the noun's retirement trigger
   fired with nobody acting on it. The fix is to move the repo's noun onto the
   platform's, or to drop it, and never to keep the two in step. Name both nouns
   and the platform primitive in the finding. A move too broad for this change
   is filed as its own bead, the way an aggravated pattern is, and the converter
   stays out of this change.
4. **A warrant the change touches is re-verified.** When the change touches a
   path or key a warrant covers, the change re-verifies that warrant against the
   platform's current documentation and records the new date, or retires the
   warrant when its trigger has fired. Check the re-verification against the
   cited documentation yourself. A touched warrant left unverified is a finding.
   So is a change that builds further on a noun whose trigger has fired: the move
   onto the platform's primitive is the work, filed as its own bead when no bead
   carries it yet.

## The verdict is binary

`signoff.sh` writes one of two verdicts, `approve` or `request-changes`. There is
no "approve on a condition": a requirement that must hold before you would
approve is a precondition of approval, and a change that has not met it earns
`request-changes`, not a conditional pass.

- **Approve** when the change fits the architecture and passes the divergence
  lens wherever it applies. Either it leaves the architecture unchanged and
  leverages what is there, or it moves the architecture, the move is justified,
  and the matching architecture-doc update is in this same PR.
- **Request changes** in every other case. These shapes recur:
  - It moves the architecture but the matching doc update is not in this PR. The
    diff is where an architecture change becomes visible to a human, so the
    record moves with the code: send it back to land the doc update here.
  - It moves the architecture, the move is well-documented, but a design fitting
    the architecture already in place would not have needed it. Send it back to
    the drawing board.
  - It works against the grain of the existing architecture. Push back rather
    than pass architectural harm through.
  - It fails a check of the divergence lens. Each failed check is a finding of
    its own.

The architecture-doc update lands in the reviewed PR, from its author, never from
the review.

## Aggravated patterns

When this change aggravates an existing pattern — it adds the third instance of
something and the architecture grows more complicated for it — judge whether to
address it here or defer it, the fix-now-versus-follow-up call the shared stance
names:

- **Low impact, a simple refactor** — make it a finding to fix in this PR, and
  `request-changes` carries it.
- **Needs a broad rearchitecture** — file a followup bead; it belongs in its own
  PR, not bolted onto this one.

```bash
gc bd create "arch: <the issue and why it is followup, not this PR's>" -t task \
  -d "Found during the arch review of <anchor>. <what the pattern is, how many
instances now exist, and the rearchitecture that would resolve it>"
```
