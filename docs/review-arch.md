---
name: The arch check on gc-toolkit
description: The method extension the arch check appends on gc-toolkit reviews. For the divergence lens it names the platform the pack is held to, what counts as evidence of what Gas City ships and what does not, the pack's operational surfaces, and where the pack records its warrants.
---

# The arch check on gc-toolkit

gc-toolkit is a pack for Gas City, and its foundation holds it to Gas City as
shipped ([foundation.md](foundation.md#boundaries)). The arch check's divergence
lens enforces that rule. This page names what the lens reads on this rig.

## Scope

**Mandate.** What the divergence lens holds a gc-toolkit change to: the
platform, the evidence of what the platform ships, the pack's operational
surfaces, and where the pack records its warrants.

**Boundaries.** The arch check's method, the lens and the verdict are pack
content, in `skills/review-arch/SKILL.md`. The rule and the tests that decide
what belongs in the pack are [foundation.md](foundation.md#boundaries). The
warrants in force are [warrants.md](warrants.md).

## The platform

The platform is Gas City: the `gc` and `bd` binaries, and the packs Gas City
bundles, such as `core`. The pack's architecture docs say how the pack composes
Gas City. They are the pack's account of it, not Gas City's.

Evidence of what Gas City ships is cited by page, or by symbol and file at a
named commit:

- Gas City's documentation at https://docs.gascity.com/, whose source is
  `docs/` in `gastownhall/gascity`, and the engineering docs under that repo's
  `engdocs/`. [gascity-reference.md](gascity-reference.md) indexes them.
- The packs Gas City bundles. `core` is under `internal/bootstrap/packs/` in
  the same repo, where its README lists its orders and its `orders/` and
  `formulas/` directories hold them. `gastown` is published in
  `gastownhall/gascity-packs`.
- Gas City's source in `gastownhall/gascity`, at upstream `main`.
- bd's documentation and source in `gastownhall/beads`.

A local clone serves as well when it is read at upstream's `main`, for example:

```bash
git -C <clone> grep -n -i '<term>' <upstream main ref> -- docs engdocs internal/bootstrap/packs
```

These are not evidence of what Gas City ships:

- The pack's own `docs/gascity-*.md` pages. They state the pack's reading of
  Gas City. Cite the upstream page or source a page names instead.
- A fork of Gas City, or a `gc` built from one. A fork carries patches upstream
  does not, so a primitive found only in a fork is not one Gas City ships.

## Operational surface here

- a script anywhere in the pack, such as under `assets/scripts/`, `doctor/` or
  `tools/`;
- a service under `services/`, or a command in one;
- an order under `orders/`;
- a cluster of steps in a formula under `formulas/`;
- a metadata key, registered in `lifecycle/lifecycle.toml`;
- a bead kind, or a lifecycle state.

## Pack nouns and converters

A pack noun is a kind of object or state the pack defines for itself, such as a
bead kind or a lifecycle state. Gas City's own nouns include beads and their
dependency edges, gates, waits, sessions, mail, convoys, molecules and orders.

A converter here is code that keeps a pack noun in step with one of those: a
sweep that files a pack bead for each gate or session, a poll that copies a
Gas City field into a pack metadata key, or a writer that sets a pack state each
time a Gas City state changes.

## Where warrants live

[warrants.md](warrants.md) records the warrants in force, the paths and keys
each one covers, and how an entry is kept true.
