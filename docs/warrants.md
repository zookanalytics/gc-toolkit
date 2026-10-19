---
name: Warrants
description: The warrants in force. Each records something the pack keeps because Gas City does not ship the primitive it stands in for, with the upstream evidence, when that was last verified, the trigger that retires it, and the paths and keys it covers. Read it before adding a pack noun, and whenever a change touches a path an entry covers.
---

# Warrants

A pack noun needs a warrant ([foundation.md](foundation.md#boundaries)): a dated
record that names the Gas City primitive it stands in for and the trigger that
retires it. Other pack surface that stands in for a missing primitive, such as
a scheduled job doing what platform maintenance would, rests on the same dated
claim and is recorded the same way. This page holds every warrant in force.

## Scope

**Mandate.** The warrants in force: each claim that Gas City cannot express
something the pack needs, the pack surface the claim justifies, the upstream
evidence for it and when that was last verified, and the trigger that retires
it.

**Boundaries.** The rule and the tests that decide what needs a warrant are
[foundation.md](foundation.md#boundaries), and the arch check holds a change to
them ([review-arch.md](review-arch.md)). A pack noun missing from this page has
no warrant. The `warrant` bead the `dog` pool executes to stop a wedged session
shares only the word ([authority-map.md](authority-map.md)).

## An entry

- **Covers.** The paths and keys the warrant justifies. A change finds the
  warrants it touches by searching this page for the paths in its diff.
- **Stands in for.** The primitive Gas City does not ship.
- **Evidence.** Where upstream shows the primitive missing: a page of Gas City's
  or bd's documentation, or a symbol and file at a named upstream commit. Never
  one of this pack's `docs/gascity-*.md` pages, and never a fork.
- **Verified.** The date of the last verification and the upstream commits it
  read.
- **Retires when.** The trigger. When it fires, moving the pack onto the
  primitive is scheduled work.

## Keeping it true

- A change that adds a pack noun adds its entry.
- A change that touches a covered path re-verifies the entry against Gas City's
  current upstream documentation and updates Verified. When the trigger has
  fired, the change files the move onto the primitive instead of building
  further on the noun.
- A change that retires a noun removes its entry.

## Dolt reclaim

- **Covers.** `assets/scripts/dolt-reclaim.sh`, `orders/dolt-reclaim.toml`,
  [dolt-reclaim.md](dolt-reclaim.md).
- **Stands in for.** A scheduled garbage collection of a managed Dolt store that
  grows on disk below the compaction threshold, which the supervisor's store
  maintenance (`[maintenance.dolt]`) would run as `CALL DOLT_GC()`.
- **Evidence.** In `gastownhall/gascity`:
  - The supervisor runs store maintenance in observe-only mode. The Dolt
    operations connection and the backup runner are not wired, so neither the
    pre-GC snapshot nor `DOLT_GC` runs
    (`engdocs/contributors/dolt-maintenance.md`).
  - Scheduled `gc dolt compact` skips a store below the commit-count threshold
    (`docs/runbooks/dolt-compact.md`). A store stranded below it is reclaimed
    only by the operator-invoked `gc dolt compact --gc-only`
    (`docs/troubleshooting/dolt-bloat-recovery.md`).
- **Verified.** 2026-10-19, at `gastownhall/gascity` main 1e05ae624.
- **Retires when.** The supervisor wires `DOLT_GC`, and the maintenance doc
  drops its observe-only note.

## Priority following

- **Covers.** `assets/scripts/queue-priority.sh`,
  `assets/scripts/priority-lib.sh`, `orders/queue-priority.toml`, the
  `priority_shift` key, the `priority` verb of `assets/scripts/gc-helm.sh`, and
  [steering.md](steering.md#priority).
- **Stands in for.** A claim priority derived from the bead a bead follows, such
  as its epic.
- **Evidence.** Gas City offers ready work in canonical ready order, by the
  bead's own priority, then `created_at`, then id (`gc ready` in
  `docs/reference/cli.md`). bd's `ready` sorts by the bead's own priority by
  default. Neither one's documentation derives a priority from another bead.
- **Verified.** 2026-10-19, at `gastownhall/gascity` main 1e05ae624 and bd 1.3.1
  (c1c4b642a).
- **Retires when.** Gas City or bd ships an inherited or derived claim priority,
  or a work query can order by a parent's priority.

## gh write containment

- **Covers.** `assets/scripts/gh-origin-guard.sh`,
  `assets/scripts/gh-origin-guard-codex.sh`, `overlays/gh-origin-guard/`,
  [gh-origin-guard.md](gh-origin-guard.md).
- **Stands in for.** Scoping an agent's outbound writes to the repositories its
  rig owns.
- **Evidence.** Gas City's trust model covers which commands run and which
  secrets reach them, and nothing in it scopes where an agent's `gh` writes go
  (`docs/reference/trust-boundaries.md`). Its documentation describes no
  per-agent write scope.
- **Verified.** 2026-10-19, at `gastownhall/gascity` main 1e05ae624.
- **Retires when.** Gas City ships per-agent write scoping. A fine-grained token
  limited to the owned repositories may cover the origin half on GitHub's side,
  and the next re-verification checks that first.
