---
name: The arch check on gc-toolkit
description: The method extension the arch check appends on gc-toolkit reviews. It adds the divergence lens, which holds new pack surface to what Gas City ships, with when the lens applies, its checks and how they reach the verdict, what counts as evidence of what Gas City ships, and where the pack records its warrants.
---

# The arch check on gc-toolkit

gc-toolkit is a pack for Gas City, and its foundation holds it to Gas City as
shipped ([foundation.md](foundation.md#boundaries)). The arch check's method
asks whether a change reimplements what a primitive already offers. On this rig
the primitives include Gas City's, and the divergence lens below is how new
surface is held to them. The pack's architecture docs describe the pack as it
is, divergence included, so a change can fit them and still rebuild what Gas
City ships. The lens holds new surface to Gas City's own documentation instead.

## Scope

**Mandate.** The divergence lens the arch check applies to a gc-toolkit change:
when it applies, its checks and how they reach the verdict, what counts as
evidence of what Gas City ships, and where the pack records its warrants.

**Boundaries.** The arch check's method and its verdict are pack content, in
`skills/review-arch/SKILL.md`, and every rig's arch review applies them. The
rule and the tests that decide what belongs in the pack are
[foundation.md](foundation.md#boundaries). The warrants in force are
[warrants.md](warrants.md). When triage adds the arch check on this rig is
[review-triage.md](review-triage.md).

## When the lens applies

The lens applies to a change that adds operational surface, or grows existing
surface with a new verb, mode or key, and to a change that touches a path or key
a warrant covers. Operational surface here is:

- a script anywhere in the pack, such as under `assets/scripts/`, `doctor/` or
  `tools/`;
- a service under `services/`, or a command in one;
- an order under `orders/`, or another scheduled job;
- a cluster of steps in a formula under `formulas/`;
- a metadata key, registered in `lifecycle/lifecycle.toml`;
- a bead kind, or a lifecycle state.

Prompts, skills, checklists, a formula's prose and work queries are not
operational surface, and neither are tests or the fixtures they use.

## The checks

1. **The search came up empty, and the change shows it.** For each piece of new
   surface, the change names the Gas City primitive it looked for and says why
   none covers the need. It cites
   [evidence of what Gas City ships](#evidence-of-what-gas-city-ships). The
   pack's own pages about Gas City are not evidence. They are the pack's reading
   of Gas City, and they can carry the divergence this lens looks for, so where
   one names an upstream doc, read and cite that doc. The search is shown in the
   reviewed commits: in a warrant the change adds, in its spec, or in a commit
   message. A change that does not show it is a finding. So is a search Gas
   City's documentation refutes, and that finding names the primitive the
   change should compose instead.
2. **A pack noun carries a warrant.** A pack noun is a kind of object or state
   the pack defines for itself, such as a bead kind or a lifecycle state. Its
   warrant is a dated record of the Gas City primitive it stands in for, the
   evidence that Gas City lacks it, and the trigger that retires it. The warrant
   lands in [warrants.md](warrants.md) in the same change. A new pack noun
   without one is a finding. Glue that runs a series of native calls as one call
   adds no noun, as long as it adds no semantics that Gas City's own mechanisms
   express, such as claim leases, assignment, continuation groups and waits.
   Formulas and orders need no warrant either. A new order or step cluster still
   shows the search, because Gas City may already ship the job or the loop it
   adds.
3. **A converter is a finding on sight.** A converter keeps a pack noun in step
   with one of Gas City's ([pack nouns and converters](#pack-nouns-and-converters)).
   It is a finding whatever else the change does well. It means Gas City now
   ships the primitive the pack noun stood in for, and the noun's retirement
   trigger fired with nobody acting on it. The fix is to move the pack noun onto
   Gas City's, or to drop it, and never to keep the two in step. Name both nouns
   and the Gas City primitive in the finding. A move too broad for this change is
   filed as its own bead, the way an aggravated pattern is, and the converter
   stays out of this change.
4. **A warrant the change touches is re-verified.** When the change touches a
   path or key a warrant covers, it re-verifies that warrant against Gas City's
   current documentation and records the new date, or retires the warrant when
   its trigger has fired. Check the re-verification against the cited
   documentation yourself. A touched warrant left unverified is a finding. So is
   a change that builds further on a noun whose trigger has fired: the move onto
   Gas City's primitive is the work, filed as its own bead when no bead carries
   it yet.

On this rig a change fits the architecture only when it also passes the lens
wherever the lens applies. A change that fails one of its checks earns
`request-changes`, and each failed check is a finding of its own.

## Evidence of what Gas City ships

Gas City is the `gc` and `bd` binaries, and the packs Gas City bundles, such as
`core`. Evidence of what it ships is cited by page, or by symbol and file at a
named commit:

- Gas City's documentation at https://docs.gascity.com/, whose source is
  `docs/` in `gastownhall/gascity`, and the engineering docs under that repo's
  `engdocs/`. [gascity/README.md](gascity/README.md) indexes them.
- The packs Gas City bundles. `core` is under `internal/bootstrap/packs/` in
  the same repo. Its orders and formulas are the files in its `orders/` and
  `formulas/` directories. Its README describes the orders, but the README's
  table can lag the directory, so list the directory. `gastown` is published
  in `gastownhall/gascity-packs`.
- Gas City's source in `gastownhall/gascity`, at upstream `main`.
- bd's documentation and source in `gastownhall/beads`.

A local clone serves as well when it is read at upstream's `main`, for example:

```bash
git -C <clone> grep -n -i '<term>' <upstream main ref> -- docs engdocs internal/bootstrap/packs
```

These are not evidence of what Gas City ships:

- The pack's own pages about Gas City, in `docs/gascity/`. They state the pack's
  reading of Gas City. Cite the upstream page or source a page names instead.
- A fork of Gas City, or a `gc` built from one. A fork carries patches upstream
  does not, so a primitive found only in a fork is not one Gas City ships.

## Pack nouns and converters

Gas City's own nouns include beads and their dependency edges, gates, waits,
sessions, mail, convoys, molecules and orders.

A converter here is code that keeps a pack noun in step with one of those: a
sweep that files a pack bead for each gate or session, a poll that copies a
Gas City field into a pack metadata key, or a writer that sets a pack state each
time a Gas City state changes.

## Where warrants live

[warrants.md](warrants.md) records the warrants in force, the paths and keys
each one covers, and how an entry is kept true.
`tools/warrants-touched.sh --base origin/<base>`, run in the review's worktree,
lists the warrants a branch touches, the list its author saw at self-review. It
is built from the Covers lines, so check 4 still judges the diff against them.
