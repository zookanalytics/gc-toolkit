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
  one of this pack's pages in `docs/gascity/`, and never a fork.
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
    only by an operator, either with `gc dolt compact --gc-only --only-db`
    against the live server or with the offline `dolt gc` procedure
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
- **Evidence.** Gas City offers ready work in canonical ready order: priority,
  then `created_at`, then id (`gc ready` in `docs/reference/cli.md`, and the
  routed-queue policy in `engdocs/architecture/dispatch.md`). The priority is
  the bead's own field (`readySortPriority` in `internal/beads/query.go`). bd's
  `ready` sorts by the bead's own priority by default. Neither one's
  documentation derives a priority from another bead.
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

## Converse reap

- **Covers.** `assets/scripts/converse-reap.sh`, `orders/converse-reap.toml`.
- **Stands in for.** Ending a manual session once the work it claimed has
  closed and nobody is attached.
- **Evidence.** In `gastownhall/gascity`, a manual session does not end when its
  work closes. It stays until it is closed or drained, and attaching wakes one
  that sleeps (`cmd/gc/compute_awake_set.go` 432-440, 583-594 and 668-693).
  No closer the controller runs on its own ends one because its work closed:
  the stale-session closers exempt a session that has started its
  conversation (`reapStaleSessionBeads`, `reapPreBootSessionBeads` and
  `cleanDeadRuntimeCorpse` in `cmd/gc/session_beads.go`, at 3057, 3237 and
  3500), and the core reaper prunes a session only once it has drained
  (`internal/bootstrap/packs/core/assets/scripts/reaper.sh` 69 and 1402-1404).
  A sitting cannot drain itself at its sign-off, because a drain destroys an
  attached operator's pane.
- **Verified.** 2026-10-26, at `gastownhall/gascity` 1e05ae624, beside a live
  `gc session list --state closed`.
- **Retires when.** Gas City ends a manual session once its claimed work has
  closed and nobody is attached.

## Accept's lock

- **Covers.** The acceptance lock of `assets/scripts/gc-helm.sh` accept: one
  `flock` file per bead, `accept-<rig>-<bead>.lock`, under the city's
  `.gc/runtime/packs/gc-toolkit`, held from Accept's live read to its last
  write.
- **Stands in for.** A launch that pours once per acceptance across a finished
  run: a `gc sling` that refuses a second root under a caller's key whatever
  the first root's status.
- **Evidence.** In `gastownhall/gascity`, a graph.v2 `gc sling <bead> --on
  <formula>` launches under a per-bead lock and refuses a second launch of the
  formula at the bead, exiting 3, only while a root an earlier launch poured is
  live (`internal/sling/sling_core.go` 544-641, the lock at 563 and the check at
  589; the terminal-root skip in `internal/sling/sling_attachment.go` 177; and
  `TestLiveConvoyTrackedWorkflowRootsSkipsTerminalRoots` in
  `internal/sling/sling_test.go` 3639-3691). Once that root has closed, the next
  launch pours again. No `gc sling` flag checks an earlier root by its title or
  by a key (`cmd/gc/cmd_sling.go` 145-160).
- **Verified.** 2026-10-22, at `gastownhall/gascity` 1e05ae624 and upstream
  340ed8581.
- **Retires when.** A Gas City launch can refuse a second root under a caller's
  key whatever the first root's status.
