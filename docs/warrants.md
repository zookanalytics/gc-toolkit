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

- **Covers.** The paths and keys the warrant justifies.
  `tools/warrants-touched.sh` builds the list of warrants a branch touches from
  this line, and reads these forms:
  - A path in backticks from the top of the repository, or a link to a page in
    `docs/`. A change to the file, or to anything under a directory, touches the
    warrant.
  - A name in backticks followed by `key`, `keys`, `name`, `names` or `file`,
    and each name listed before it. A changed line that names it whole touches
    the warrant, in any file other than a markdown file, a test or `specs/`.
  - The `x` block of a path, a `# >>> x` fence in that file, or the `[x]` table
    of a TOML file. A change inside it touches the warrant, and a change
    elsewhere in the file does not.

  A file named for another part of it, such as a verb or a function, is listed
  on any change to it, and is touched only when the change reaches that part.
  The list prints the Covers line, so the author can read which part it names.
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
  further on the noun. `tools/lint.sh` prints the list at the polecat's
  self-review, with each entry's Verified date and whether the branch has
  updated it, and `tools/warrants-touched.sh --base origin/<base>` prints it at
  any time. The list judges nothing, and the arch check judges the
  re-verification.
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

## Suspended store backup

- **Covers.** `assets/scripts/suspended-store-backup.sh`,
  `orders/suspended-store-backup.toml`.
- **Stands in for.** A scheduled backup of a suspended rig's store that inherits
  the city's endpoint, which Gas City's `mol-dog-backup` order would run if its
  rig filter read the endpoint origin as well as the suspension.
- **Evidence.** In `gastownhall/gascity`:
  - `mol-dog-backup.sh` in the dolt pack it bundles
    (`examples/bd/dolt/assets/scripts/`) keeps only the rigs whose `suspended` is
    false. Its comment gives two reasons: a bd call restarts a suspended scope's
    retired proxy and Dolt, and nothing writes to the scope. An `inherited_city`
    rig has no rig-local Dolt (`docs/runbooks/managed-city-endpoints.md`), and the
    design page says a rig sharing the city's proxy root is not stopped on its
    own and that deliberate touches still reach a suspended rig
    (`engdocs/design/beads-proxied-local-default.md`, "Suspension is quiescence").
  - Nothing changes that filter from outside the script. `GC_BACKUP_DATABASES`
    narrows among the scopes the order already chose. An `OrderOverride` sets an
    order's scheduling fields and exec env, not its exec
    (`docs/reference/config.md`). A city's local order of the same name replaces
    the pack's entirely (`docs/tutorials/07-orders.md`, "Order layering"), which
    would carry a copy of the whole backup.
  - A rig-scoped order cannot do it, because the controller skips an order that
    targets a suspended rig (`orderRigSuspended` in `cmd/gc/order_dispatch.go`).
  - `gc dolt sync` pushes committed branches to a database's remotes, not to its
    backup (the dolt pack's `commands/sync/run.sh`). The supervisor's store
    maintenance snapshots only the city's store, and its backup runner is not
    wired (`engdocs/contributors/dolt-maintenance.md`).
  - A search of its issues and pull requests finds no report of a suspended rig's
    store going without a backup. No pack in `gastownhall/gascity-packs` runs a
    backup of its own: its one mention of `mol-dog-backup` is Gas Town's patrol
    reporting that the order may have failed.
  - No command gives a read of a rig's endpoint origin. `gc rig list --json` and
    `gc rig status --json` leave it out (`RigListItem` in `cmd/gc/cmd_rig.go`,
    `RigStatusRig` in `cmd/gc/cmd_status.go`). A writer's dry run prints it only
    as preview text: `gc rig set-endpoint --dry-run`, whose `--json` form has no
    field for it (`printRigEndpointDryRun` in `cmd/gc/cmd_rig_endpoint.go`,
    `rigEndpointJSON` in `cmd/gc/management_json.go`), and the `use-managed` and
    `use-external` verbs of `gc beads city` (`printCityEndpointDryRun` in
    `cmd/gc/cmd_beads_city.go`). A doctor warning about a split store names it in
    passing (`activeBDStore` in `internal/doctor/checks.go`). So the script
    carries a copy of `beads_config_value` from the bd pack
    (`examples/bd/assets/scripts/gc-beads-bd.sh`). The dolt pack and
    `schemas/wisps-composite-index/common.sh` carry the same function because
    they ship independently, and a test holds the copies equal
    (`cmd/gc/gc_beads_bd_config_value_test.go`). That test does not reach this
    copy.

  In `gastownhall/beads`, auto-backup stays off on a shared server, and its
  documentation says to run `bd backup` explicitly there
  (`docs/cli-reference/backup.md`), which this pass does. Only `bd backup sync`
  writes `.beads/dolt-backup-state.json` (`updateDoltBackupState` in
  `cmd/bd/backup_dolt.go`), the file Gas City's `scanDoltBackupFreshness` and
  `BulkDeleteSafe` judge (`internal/doctor/checks_bd_backup_freshness.go`).
  `bd config get` reads a `gc.*` key from the store and not from the file
  (`IsYamlOnlyKey` in `internal/config/yaml_config.go`), so it cannot report the
  origin either.
- **Verified.** 2026-10-31, at `gastownhall/gascity` main 6f5e14c2f,
  `gastownhall/gascity-packs` main 0b0d96250 and `gastownhall/beads` main
  6ebaacba8.
- **Retires when.** `mol-dog-backup` backs up a suspended rig whose store inherits
  the city's endpoint.

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
  [gh-origin-guard.md](gh-origin-guard.md), and the guard's wiring, which
  carries the `gh-origin-guard` or `gh-origin-guard-codex` name: the overlay
  stanzas in pack.toml, the hook in the work-context and cycle-recycle overlays,
  and each Codex agent's `pre_start`.
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

## Converse reap

- **Covers.** `assets/scripts/converse-reap.sh`, `orders/converse-reap.toml`.
- **Stands in for.** Ending a manual session that outlives the conversation it
  held: a stop that did not take, a conversation another path closed, or one a
  sitting cut short handed back to the operator's queue.
- **Evidence.** In `gastownhall/gascity`, a manual session does not end when its
  work closes. It stays until it is closed or drained, and attaching wakes one
  that sleeps (`cmd/gc/compute_awake_set.go` 432-440, 583-594 and 668-693).
  No closer the controller runs on its own ends one because its work closed:
  the stale-session closers exempt a session that has started its
  conversation (`reapStaleSessionBeads`, `reapPreBootSessionBeads` and
  `cleanDeadRuntimeCorpse` in `cmd/gc/session_beads.go`, at 3057, 3237 and
  3500), and the core reaper prunes a session only once it has drained
  (`internal/bootstrap/packs/core/assets/scripts/reaper.sh` 69 and 1402-1404).
  A sitting drains itself once its conversation closes, and `gc-helm dismiss`
  stops the session that held the conversation it closes, so nothing in the
  controller ends a session either of them missed.
- **Verified.** 2026-10-26, at `gastownhall/gascity` 1e05ae624, beside a live
  `gc session list --state closed`.
- **Retires when.** Gas City ends a manual session once its claimed work has
  closed.

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
  live (`internal/sling/sling_core.go` 544-724, the lock at 563 and the check at
  589; the terminal-root skip in `internal/sling/sling_attachment.go` 177; and
  `TestLiveConvoyTrackedWorkflowRootsSkipsTerminalRoots` in
  `internal/sling/sling_test.go` 3639-3691). Once that root has closed, the next
  launch pours again. No `gc sling` flag checks an earlier root by its title or
  by a key (`cmd/gc/cmd_sling.go` 145-160).
- **Verified.** 2026-10-26, at `gastownhall/gascity` main e2671dc4d.
- **Retires when.** A Gas City launch can refuse a second root under a caller's
  key whatever the first root's status.

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

## Machine axis

- **Covers.** The `pr.machine`, `pr.machine_cause` and `pr.machine_reason`
  keys: `[machine_axis]` in `lifecycle/lifecycle.toml`, with its `machines`
  and `causes` lists, and the keys' entry in its `[metadata.pr_round_trip]`
  table. Their writers: `recordMachine`, `recordBlocked` and `handleBlocked`
  in `services/gctk/internal/cli/merge.go`, which `assets/scripts/merge.sh`
  runs, and the "record the pass's own verdict on the anchor" section of
  `assets/scripts/gate-ensure.sh`. The readers of the causes: package
  `services/gctk/prstatus`, and the helm board's machine reads in
  `services/helm/internal/board/derive.go`.
- **Stands in for.** A merge-readiness verdict kept on the bead whose pull
  request it is, which tells a block no automated actor will clear from a wait
  the city is acting on, with the block's cause as a value a reader keys on.
- **Evidence.**
  - In `gastownhall/gascity`, the `gc` binary's PR readiness monitor
    classifies an open PR from its draft flag, its merge state and its check
    rollup alone, so every `BLOCKED` PR is `blocked` and actionable, a
    required check still running included (`classifyPullRequest` in
    `internal/githubmonitor/monitor.go`). It reads no branch rule, review
    thread or approval, and it records its class on a repair bead it files
    (`ensureGitHubPRRepairBead` in `cmd/gc/cmd_github.go`), not on the bead
    whose PR it is. Only `gc github pr backfill` runs it (`gc github pr
    backfill` in `docs/reference/cli.md`, and `GitHubPRMonitor` in
    `docs/reference/config.md`).
  - The one state dimension Gas City reads as a bead label is `hold`, for
    its dispatch holds `hold:mayor` and `hold:external`
    (`engdocs/contributors/hold-label-conventions.md`, and
    `DispatchHoldLabels` in `internal/beadmeta/hold_labels.go`). Its other
    label reads are flags and markers, such as a convoy's `owned`
    (`convoyStillAutocloses` in `cmd/gc/cmd_convoy.go`), and none of them is
    a verdict tied to a head.
  - In `gastownhall/beads`, labels as state keep one value per dimension,
    read on its own, with an event bead as its history (*Labels as State
    Cache* in `docs/core-concepts/labels.md`). `bd set-state` refuses an
    empty value, and no state command removes a dimension (`setStateCmd`
    and `runSetState` in `cmd/bd/state.go`), so a cause could not be
    cleared when the verdict it qualifies moves on. A custom status (*Custom
    Statuses and Types* in `docs/reference/configuration.md`) would take the
    place of the bead's own status.
  - In `gastownhall/gascity-packs`, no pack reads a branch's rules or a
    check's required flag, and none records why a PR cannot merge as a value
    a reader keys on. The `gastown` pack's `pr-merge-reconcile` records a PR's
    lifecycle in `pr_state`, a key of its own.
  - The search is [specs/tk-blloeo/gas-city-search.md](../specs/tk-blloeo/gas-city-search.md).
- **Verified.** 2026-10-28, at `gastownhall/gascity` main b25b49f33e37,
  `gastownhall/gascity-packs` main 5bf643ca55bd with the packs Gas City
  bundles at 66c672b5ed00, and `gastownhall/beads` main e46de42b3c59.
- **Retires when.** Gas City records a pull request's merge readiness where a
  reader of the PR's own bead finds it, and tells a required check still
  running from a block, for example once its PR monitor reads the base
  branch's rules. The axis then moves onto that record.

## Owed status label clear

- **Covers.** The `status_label_clear_owed` key, in the
  `[metadata.pr_status_label]` table of `lifecycle/lifecycle.toml`. Its
  writers: `clearStatusLabel` in `services/gctk/internal/cli/merge.go`, and
  `clear_status_label` in `assets/scripts/pr-facts.sh`. Its reader: the
  "retry the status: label clears that terminal records still owe" section of
  `assets/scripts/pr-facts.sh`.
- **Stands in for.** A retry of a failed write to an outside service, kept
  until a later pass lands it.
- **Evidence.**
  - In `gastownhall/gascity`, a failed order is not retried ("No retry on
    dispatch failure" in `engdocs/architecture/orders.md`), and
    `[steps.retry]` retries a formula step's attempt within its run (section
    3.2 of `docs/reference/specs/formula-spec-v2.md`). Gas City keeps no
    outbox or retry queue that a pack can hand a write to an outside
    service. Its usage facts retry a failed write with a marker of their
    own: a fact whose sink fails leaves the session bead's
    `usage_compute_emitted_at` marker unset for the next reconcile tick
    (`emitComputeFactForBead` in `cmd/gc/usage_compute.go`).
  - In `gastownhall/gascity-packs`, a pack that retries such a write keeps a
    marker of its own: the `gastown` pack's `pr_reconcile_pending` key, and
    the `oversight-rig` pack's `delivered` label.
  - The search is [specs/tk-blloeo/gas-city-search.md](../specs/tk-blloeo/gas-city-search.md).
- **Verified.** 2026-10-28, at `gastownhall/gascity` main b25b49f33e37 and
  `gastownhall/gascity-packs` main 5bf643ca55bd.
- **Retires when.** Gas City ships a retry that a pack can hand a failed write
  to an outside service, such as an outbox that a later pass drains.

## Unanswered review threads

- **Covers.** The `pr.unanswered_threads` key, in the
  `[metadata.pr_round_trip]` table of `lifecycle/lifecycle.toml`. Its writer:
  `recordUnansweredThreads` and `unansweredThreads` in
  `services/gctk/internal/cli/merge.go`, which `assets/scripts/merge.sh` runs.
  The definition it counts by: `gc_thread_awaits_answer` in
  `assets/scripts/pr-post.sh`, which reads a thread's posts through
  `live_comments` in `assets/scripts/review-dismissal.sh` and sets aside a post
  carrying the reaction the write-back in `assets/scripts/pr-facts.sh` marks a
  handled post with (`WB_RESOLVED_REACTION`). Its readers:
  `unansweredFeedback` in package `services/gctk/prstatus`,
  `gctk pr-status derive` in `services/gctk/internal/cli/prstatus.go`, and
  `phaseFacts` in the helm board's `services/helm/internal/board/derive.go`.
- **Stands in for.** A record of a pull request's review threads kept on the
  bead whose pull request it is, which says whether review feedback still
  waits on an answer.
- **Evidence.**
  - In `gastownhall/gascity`, the `gc` binary's pull request readiness monitor
    reads each open PR's draft flag, merge state, head and check rollup
    (`pullRequestsQuery` in `internal/githubmonitor/client.go`, and
    `classifyPullRequest` in `internal/githubmonitor/monitor.go`), and records
    its class on a repair bead it files. No source under `cmd/`, `internal/` or
    `examples/`, tests aside, reads a pull request's reviews, review threads or
    review comments.
  - A webhook rule hands one verified provider event to an order or a
    conversation and keeps no state of its own
    ([WebhookRule](https://docs.gascity.com/reference/config#webhookrule) in
    the configuration reference).
  - In `gastownhall/beads`, the example formula `gh-pr-review` tells the agent
    running it to check for unresolved review threads, and records none
    (`examples/formulas/gh-pr-review.formula.toml`).
  - In `gastownhall/gascity-packs`, no pack reads whether a review thread is
    resolved or answered. The `compound-engineering` pack's
    `ce-pr-comment-resolver` agent is handed a thread to fix or answer, and
    keeps no record of it.
  - The search is [specs/tk-iydyiup/gas-city-search.md](../specs/tk-iydyiup/gas-city-search.md).
- **Verified.** 2026-10-28, at `gastownhall/gascity` main b25b49f33e37 with
  the `gastown` pack it bundles at 66c672b5ed00, `gastownhall/gascity-packs`
  main 5bf643ca55bd, and `gastownhall/beads` main e46de42b3c59.
- **Retires when.** Gas City records a pull request's review threads where a
  reader of the PR's own bead finds them, for example once its readiness
  monitor reads review threads, or a webhook receiver keeps their state from
  GitHub's review thread events. The count then moves onto that record.
