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
  `ready` sorts by the bead's own priority by default (`--sort` in bd's
  `docs/cli-reference/ready.md`). No `--sort` choice of `gc ready`, or of bd's
  `ready`, `list`, `query` or `search`, orders by a parent's priority. Gas City
  and bd copy a priority from another bead only when they create a bead: a
  sling pours its workflow at the priority of the bead it is slung on
  (`BeadPriorityOverride` in `internal/sling/sling.go`), and `bd swarm` creates
  its molecule at its epic's priority (bd's `cmd/bd/swarm.go`). Nothing updates
  the copy when the source's priority changes. Neither one's documentation
  describes a priority that follows another bead's.
- **Verified.** 2026-10-26, at `gastownhall/gascity` main 37bd09351,
  `gastownhall/gascity-packs` main dac12a4a8 and `gastownhall/beads` main
  2ef4df339 (`BuildReadyWorkOrder` in `internal/storage/sqlbuild/ready.go`
  orders the priority policy by the bead's own priority), with bd 1.3.2
  (9b65b9e19).
- **Retires when.** Gas City or bd ships an inherited or derived claim priority,
  or a work query can order by a parent's priority.

## gh write containment

- **Covers.** `assets/scripts/gh-origin-guard.sh`,
  `assets/scripts/gh-origin-guard-codex.sh`, `overlays/gh-origin-guard/`,
  [gh-origin-guard.md](gh-origin-guard.md).
- **Stands in for.** Scoping an agent's outbound writes to the repositories its
  rig owns.
- **Evidence.**
  - Gas City's trust model covers which commands run and which secrets reach
    them, and nothing in it scopes where an agent's `gh` writes go
    (`docs/reference/trust-boundaries.md`).
  - Its configuration gives an agent explicit `env`, which can carry a token,
    and no field of an agent or a rig limits where it writes (`Agent` and `Rig`
    in `docs/reference/config.md`). Its documentation describes no per-agent
    write scope.
  - In `gastownhall/gascity-packs`, the `github` pack's `comment-issue`,
    `push-branch` and `create-pr` commands write as a GitHub App installation,
    so GitHub holds those writes to the installation's repositories. It scopes
    no agent's own `gh`.
- **Verified.** 2026-10-26, at `gastownhall/gascity` main 37bd09351 and
  `gastownhall/gascity-packs` main dac12a4a8, and against GitHub's *Managing
  your personal access tokens* page, read the same day.
- **Retires when.** Gas City ships per-agent write scoping. A GitHub
  fine-grained token covers only part of the origin rule. GitHub refuses it a
  write outside its one owner's selected repositories, so a stranger's
  repository is held out on GitHub's side. It cannot reach a second owner's
  repositories, or one where its account is an outside collaborator, yet a
  rig's origin can sit under another owner's account and a city-scope agent
  owns every rig's origin. A token the rigs share also leaves each rig's agents
  free to write to the others' repositories, which the guard refuses.

## Prep worktree staging record

- **Covers.** The record that `stage --work` writes and `held` and `verify`
  read in `assets/scripts/refinery-workspace.sh`, a `gc-refinery-staged` file
  in the prep worktree's private git dir, and its readers: the
  `prep-staged-work` block of `formulas/mol-refinery-patrol.toml`, which takes
  the bead and branch the merge-push step acts for from it, and the prep
  worktree check in `assets/scripts/direct-merge-push.sh`.
- **Stands in for.** A worktree's ownership record, naming the bead and the
  branch that the refinery's detached prep worktree was staged for.
- **Evidence.**
  - In `gastownhall/gascity`, `gc worktree` records a worktree's bead and branch
    in its private git dir, and `gc worktree verify` checks them, only for a
    worktree with the bead's branch checked out on an attached HEAD, never
    detached, at a direct child of a per-rig root (`gc worktree` in
    `docs/reference/cli.md`). `Spec.validate` in `internal/worktree/worktree.go`
    also refuses a path inside a registered worktree, and the prep worktree
    lives in the rig checkout's git dir.
  - `gc worktree cleanup` refuses a dirty worktree and a HEAD not merged into
    its base, removes only the attempt whose id it is given, and has no force
    mode (`gc worktree cleanup` in `docs/reference/cli.md`). The refinery
    removes its prep worktree after a gate that can leave files in it and after
    a landing on the target, and it clears a leftover of an interrupted
    iteration without knowing which bead staged it.
  - With `auto_reap_closed_bead_worktrees`, the reconciler removes a per-bead
    worktree once its work bead is closed. With `auto_prune_worker_dir`, it
    removes a pool session's `worker_dir` once the session bead is closed
    (`DaemonConfig` in `docs/reference/config.md`). Each removal refuses a
    worktree with uncommitted changes or a stash, and each acts only under the
    city's `.gc/worktrees/` tree, where the reaper takes a worktree's bead from
    its directory name (`reapClosedBeadWorktrees` in
    `cmd/gc/bead_worktree_reaper.go`). Neither reaches the prep worktree.
  - No formula or order in Gas City's bundled `core` pack calls `gc worktree`.
    No pack in `gastownhall/gascity-packs` calls it either, and the gastown
    pack's `mol-refinery-patrol` stages every bead on one local `temp` branch
    and records nothing about which bead that branch holds.
  - In `gastownhall/beads`, `bd worktree create` checks out a branch in the
    worktree it adds and records no bead.
- **Verified.** 2026-10-27, at `gastownhall/gascity` main f11f48825520,
  `gastownhall/gascity-packs` main dac12a4a802c and `gastownhall/beads` main
  5011528b3ad5. The gastown pack was also read at 66c672b5ed00, the release
  Gas City pins (`PublicGastownPackVersion` in
  `internal/config/public_packs.go`).
- **Retires when.** Gas City can bind a detached worktree to a bead and remove
  the attempt that created it whatever state it is in, for example through
  `gc worktree`. The record's readers then move onto that primitive, and the
  record goes.

## Main lands only through a PR

- **Covers.** The rule in the `merge-strategy-resolve` block of
  `formulas/mol-refinery-patrol.toml` that resolves a bead which would land
  `direct` on the default branch to `mr`.
- **Stands in for.** A merge strategy set per target branch. With one, the
  default branch would take work only through a PR, whether or not its GitHub
  ruleset is on, while an integration branch takes its work `direct`.
- **Evidence.** In `gastownhall/gascity`, a rig carries one merge strategy,
  `default_merge_strategy`, which `gc sling` stamps on a bead routed into the
  rig when the caller passes no `--merge` (the `Rig` section of
  `docs/reference/config.md`). Sling takes the explicit `--merge`, then the
  bead's rig's default, then the agent's rig's, and reads no target branch
  (`SlingMergeStrategy` in `internal/sling/sling.go`). Neither the reference
  nor the code chooses a strategy by the branch a bead lands on.
- **Verified.** 2026-10-24, at `gastownhall/gascity` main 7cff3a265.
- **Retires when.** Gas City can set a merge strategy for a target branch, so the
  rule becomes a line of the rig's config.
