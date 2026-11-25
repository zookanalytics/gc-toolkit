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
no warrant.

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

## The work formula's overrides

- **Covers.** `formulas/mol-polecat-work.toml`, `assets/scripts/work-gate.sh`,
  `assets/scripts/work-setup.sh`, `assets/scripts/work-enter.sh`,
  `assets/scripts/rig-checks.sh`, `assets/scripts/work-submit.sh`,
  `assets/scripts/work-lib.sh`, `assets/scripts/decline.sh`.
- **Stands in for.** Steps of core's polecat base and Gas Town's polecat formula
  that would do what the pack needs. The formula overrides five steps and inherits
  `implement`. Each override differs for a reason of its own:
  - `load-context` refuses a bead that is finished, parked, held by a wait as
    `gctk bead holds` answers, or in another live run, and ends the run by
    cancelling it with what releases the work on the work bead. Upstream's has no
    such gate. `gc sling` keeps one live run of a formula on a bead, and the gate
    reads the same record for what gets past it, a forced relaunch and a claimant
    with no poured workflow, so it adds no key and writes nothing to let a run
    through.
  - `workspace-setup` cuts the tree at `.gc/worktrees/<rig>/<bead>`, beside the
    agents' homes, where Gas City's claim cuts a bead's tree. Core's variants cut
    it in the agent's home, and Gas Town's under
    `.gc/worktrees/<rig>/artifacts/worktrees/`. A run's steps are claimed by
    different sessions, so the tree outlives the session that cuts it, and Gas
    City can remove a closed pool session's home with everything under it. The tree
    is recorded as `work_dir`, which Gas City's closed-bead reaper reads, where
    Gas Town's records `artifact_dir`, which no Gas City reader reads. It brings
    a rejected branch current by merge, where Gas Town's rebases it under an open
    PR, and waits behind a sibling.
  - `preflight-tests` runs the checks through `gctk rig`, so every polecat starting
    from one base shares one recorded run, keys a tracker on a stamp, and has the
    tracker it files sent to the rig's polecat pool. Core's runs each command raw
    per polecat, matches trackers by title and routes the one it files nowhere.
  - `self-review` is a bounded check loop over those records, whose last attempt
    asks a person through a human gate when a check is still red, where Gas
    Town's is one inline step.
  - `submit-and-exit` holds the anchor, the bring-current guard and the store-only
    exit, which are nouns of the merge and review subsystems. Once the handoff is
    written it removes the run's worktree with its local branch, as core's own
    variants remove theirs. Gas Town's detaches the tree and deletes the branch, so
    once a squash merge deletes origin's branch the tree sits on commits no ref
    reaches, and the controller's reaper never removes it.
- **Evidence.** In `gastownhall/gascity`:
  - `internal/bootstrap/packs/core/formulas/mol-polecat-base.toml`: its
    `load-context` has no duplicate-dispatch gate, its `preflight-tests` runs
    `{{test_command}}` raw and files its tracker with a `gc bd create` that
    routes it nowhere, and its `workspace-setup` is a placeholder each
    variant overrides with a tree of its own. `mol-polecat-commit.toml` and
    `mol-scoped-work.toml` cut theirs with `git worktree add` at
    `$GC_DIR/worktrees/<bead>`, in the agent's home, and remove them with
    `git worktree remove` once the work is pushed.
  - `cmd/gc/session_worktree_prune.go`, `pruneAgentHomeWorktreeIfSafe`: once a
    pool session's bead closes, it removes the session's home with
    `WorktreeRemove(workerDir, true)`, a forced removal, after gates that read the
    home itself, its uncommitted work and its unpushed commits, so a tree nested
    in the home goes with it. `auto_prune_worker_dir` turns it off, and it is on
    when unset.
  - `cmd/gc/cmd_hook_worktree.go`: `gc hook --claim --worktree` cuts the claimed
    bead's tree at `<city>/.gc/worktrees/<rig>/<bead>` through
    `gc worktree ensure` ([gc hook](https://docs.gascity.com/reference/cli#gc-hook)).
  - `cmd/gc/bead_worktree_reaper.go`, `scanBorrowVetoReferences`: the reaper keeps
    a tree that a bead outside the terminal states names in `gc.work_dir` or
    `work_dir`.
  - `internal/worktree/worktree.go`, the owner `gc worktree` runs: `Cleanup`
    removes a tree only when its HEAD is merged into the base given, and
    `verifyProvenance` requires that base to be the one the tree was made from, so
    `gc worktree cleanup` cannot remove a tree at the handoff, before the merge.
    `rejectRegisteredWorktreeAncestor` refuses a path inside a registered worktree,
    so `gc worktree ensure` cannot make a tree inside an agent's home. The search
    is [specs/tk-1tfzr71.43/gas-city-search.md](../specs/tk-1tfzr71.43/gas-city-search.md).
  - `internal/formula/parser.go`, `mergeSteps`: a child step replaces its parent's
    whole, so an inherited step cannot gain metadata, and a step that needs
    `gc.continuation_group` must be overridden. The base declares none.
  - `internal/sling/sling_core.go`, `checkLegacySourceWorkflowConflict`, and
    `internal/sling/sling_attachment.go`, `liveConvoyTrackedWorkflowRoots`: a second
    live root of one formula on one bead is refused, unless `--force` skips the
    lookup, under the lock `withGraphV2SourceWorkflowLock` takes.
  In `gastownhall/gascity-packs`, `gastown/formulas/mol-polecat-work.toml` overrides
  `workspace-setup`, `self-review` and `submit-and-exit`, cuts its tree at
  `.gc/worktrees/<rig>/artifacts/worktrees/<bead>` and records it as
  `artifact_dir`, rebases a rejected branch, and at the handoff detaches the tree
  and deletes its branch.
- **Verified.** 2026-11-23, at `gastownhall/gascity` main 35e0a4c6fc31 and
  `gastownhall/gascity-packs` main 44b9db7168f6.
- **Retires when.** A step at a time. `load-context`: core's gate refuses finished,
  parked and held work and ends a run by cancelling it. `workspace-setup`: no end
  is planned for the merge resume, since the refinery brings every branch current
  by merge and never rebases one
  ([built-once-target.md](built-once-target.md#merge)). Its cut of the tree
  retires once the build a city runs carries `gc hook --claim --worktree` and the
  formula moves onto the tree the claim cuts.
  `preflight-tests` and `self-review`: Gas City ships a record of a check per
  commit. `submit-and-exit`: the merge and review nouns it holds retire, the
  bring-current guard among them with the old review path (`tk-1tfzr71.122`).

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
- **Verified.** 2026-11-23, at `gastownhall/gascity` main 572f981c6.
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

- **Covers.** `assets/scripts/queue-priority.sh`, whose `move` is the
  operator's priority move, `assets/scripts/priority-lib.sh`,
  `orders/queue-priority.toml`, the `priority_shift` key, and
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
  (`BeadPriorityOverride` in `internal/sling/sling.go`), a cook attached to a
  bead makes its whole sub-workflow at that bead's priority and takes none of
  its own (`newFormulaCookCmd` in `cmd/gc/cmd_formula.go`, whose flags name no
  priority and whose graph.v2 arm instantiates at the attach bead's priority,
  as `Attach` in `internal/molecule/molecule.go` does for a v1 formula), a
  fragment a running workflow adds takes its root's (`InstantiateFragment` in
  `internal/molecule/molecule.go`), and `bd swarm` creates its molecule at its
  epic's priority (bd's `cmd/bd/swarm.go`). Nothing updates the copy when the
  source's priority changes. Neither one's documentation describes a priority
  that follows another bead's.
- **Verified.** 2026-11-23, at `gastownhall/gascity` main 97c0c9b3b11b
  (`readySortPriority` in `internal/beads/query.go`, `BeadPriorityOverride` in
  `internal/sling/sling.go`, `Attach` and `InstantiateFragment` in
  `internal/molecule/molecule.go`, `newFormulaCookCmd` in
  `cmd/gc/cmd_formula.go`), and at `gastownhall/beads` main 786241099046 and
  bd 1.3.4 (`BuildReadyWorkOrder` in `internal/storage/sqlbuild/ready.go`
  orders the priority policy by the bead's own priority).
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
- **Verified.** 2026-11-23, at `gastownhall/gascity` main ffd9f6b0cb68 and
  `gastownhall/gascity-packs` main 44b9db7168f6. The config reference's
  `[github]` table declares pull-request monitors, whose `authors` allow-list
  scopes the pull requests a monitor acts on, and scopes no agent's writes.
  GitHub's *Managing your personal access tokens* page was read on 2026-11-20.
- **Retires when.** Gas City ships per-agent write scoping. A GitHub
  fine-grained token covers only part of the origin rule. GitHub refuses it a
  write outside its one owner's selected repositories, so a stranger's
  repository is held out on GitHub's side. It cannot reach a second owner's
  repositories, or one where its account is an outside collaborator, yet a
  rig's origin can sit under another owner's account and a city-scope agent
  owns every rig's origin. A token the rigs share also leaves each rig's agents
  free to write to the others' repositories, which the guard refuses.

## Accept's lock

- **Covers.** The acceptance lock of `gctk reaction accept`,
  `services/gctk/reaction/accept_lock.go`: one `flock` file per bead,
  `accept-<bead>.lock`, under the city's `.gc/runtime/packs/gc-toolkit`, held
  from Accept's live read to its last write.
- **Stands in for.** A launch that pours once per acceptance across a finished
  run: a `gc sling` that refuses a second root under a caller's key whatever
  the first root's status.
- **Evidence.** In `gastownhall/gascity`, a graph.v2 `gc sling <bead> --on
  <formula>` launches under a per-bead lock and refuses a second launch of the
  formula at the bead, exiting 3, only while a root an earlier launch poured is
  live (`withGraphV2SourceWorkflowLock` in `internal/sling/sling_core.go`, and
  `checkLegacySourceWorkflowConflict` there, which reads the live roots; the
  terminal-root skip of `liveConvoyTrackedWorkflowRoots` in
  `internal/sling/sling_attachment.go`). Once that root has closed, the next
  launch pours again. No `gc sling` flag checks an earlier root by its title or
  by a key, and `--scope-kind` with `--scope-ref` names a logical workflow
  scope, not a caller's key (`cmd/gc/cmd_sling.go`).
- **Verified.** 2026-11-20, at `gastownhall/gascity` main b31d0b1194.
- **Retires when.** A Gas City launch can refuse a second root under a caller's
  key whatever the first root's status.

## Main lands only through a PR

- **Covers.** The rule in `assets/scripts/refinery-land.sh`, the refinery's
  merge-push step, that resolves a bead which would land `direct` on the
  default branch to `mr`.
- **Stands in for.** A merge strategy set per target branch. With one, the
  default branch would take work only through a PR, whether or not its GitHub
  ruleset is on, while an integration branch takes its work `direct`.
- **Evidence.** In `gastownhall/gascity`, a rig carries one merge strategy,
  `default_merge_strategy`, which `gc sling` stamps on a bead routed into the
  rig when the caller passes no `--merge` (the `Rig` section of
  `docs/reference/config.md`). Sling takes the explicit `--merge`, then the
  bead's rig's default, then the agent's rig's, and reads no target branch
  (`SlingMergeStrategy` in `internal/sling/sling.go` 1161-1176). Neither the
  reference nor the code chooses a strategy by the branch a bead lands on. In
  `gastownhall/gascity-packs`, the gastown refinery's merge-push step takes the
  bead's `merge_strategy`, `direct` when it has none, and moves a `direct` bead
  to `mr` only when it names an `existing_pr`, whatever its target
  (`gastown/formulas/mol-refinery-patrol.toml` 674-704).
- **Verified.** 2026-11-20, at `gastownhall/gascity` main b31d0b119475 and
  `gastownhall/gascity-packs` main aa55b477d4c2.
- **Retires when.** Gas City can set a merge strategy for a target branch, so the
  rule becomes a line of the rig's config.

## A merged PR's refused close

- **Covers.** The `pull_request_merged_close_refused` name, the exception the
  landing order records when bd refuses to close a bead whose merge it
  verified. Its writers: `Refuse` in `services/gctk/pr/record/record.go`, and
  `refused`, `refusedMessage` and `closeRefused` in
  `services/gctk/pr/landing.go`.
- **Stands in for.** An escalation, on the bead's own pending record, of a
  merge the reconcile verified but whose close the store refuses.
- **Evidence.**
  - In `gastownhall/gascity-packs`, Gas Town's reconcile writes `mr_merged` on
    the still-blocked bead, and when `bd_close` fails it prints "merge verified
    but bead close failed; pending marker retained for retry" and returns, so
    its next run tries the close again. Its record has no value for the case,
    and it escalates nothing (`gastown/commands/pr-merge-reconcile/run.sh`
    709-723). Its escalations elsewhere in that file are mail to the mayor
    (`mail_mayor` at 40, called at 302, 404, 423 and 699).
  - In `gastownhall/beads`, an update that would close a bead with an open
    child or a live direct blocker returns `CloseOpenChildrenError` or
    `ErrCloseBlocked` to its caller unless it forces the close policy
    (`issueops/issueops.go` 573-578). bd's human gate
    (`bd gate create --type human`, `cmd/bd/gate.go` 1952) is the primitive the
    exception's gate composes.
  - A search of `gastownhall/gascity` and `gastownhall/beads` for a refused
    close finds no record of one kept on the bead for a person. What it finds
    in Gas City handles a refusal inside the closes Gas City makes itself, such
    as the autoclose sweep's retry of a convoy, wisp or molecule autoclose
    (`cmd/gc/autoclose_sweep.go` 21-22).
- **Verified.** 2026-11-23, at `gastownhall/gascity-packs` main 44b9db7168f6,
  `gastownhall/beads` main 786241099046 and `gastownhall/gascity` main
  ffd9f6b0cb68.
- **Retires when.** Gas Town's `pr-merge-reconcile` escalates a close it cannot
  make. The exception then moves onto what Gas Town records.

## Machine axis

- **Covers.** The `pr.machine`, `pr.machine_cause` and `pr.machine_reason`
  keys: `[machine_axis]` in `lifecycle/lifecycle.toml`, with its `machines`
  and `causes` lists, and the keys' entry in its `[metadata.pr_round_trip]`
  table. Their writer and their one reader: the "record the pass's own verdict
  on the anchor" section of `assets/scripts/gate-ensure.sh`, which records
  `pr.machine` alone and reads the cause beside a `blocked` verdict it finds
  there.
- **Stands in for.** A merge-readiness verdict kept on the bead whose pull
  request it is, which tells a block no automated actor will clear from a wait
  the city is acting on, with the block's cause as a value a reader keys on.
- **Evidence.**
  - In `gastownhall/gascity`, the `gc` binary's PR readiness monitor
    classifies an open PR from its draft flag, its merge state and its check
    rollup alone, so a `BLOCKED` PR that is no draft and has no failed check
    is `blocked` and actionable, a required check still running included (`classifyPullRequest` in
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
- **Verified.** 2026-11-23, at `gastownhall/gascity` main ffd9f6b0cb68,
  `gastownhall/gascity-packs` main 44b9db7168f6, and `gastownhall/beads` main
  786241099046.
- **Retires when.** Gas City records a pull request's merge readiness where a
  reader of the PR's own bead finds it, and tells a required check still
  running from a block, for example once its PR monitor reads the base
  branch's rules. The axis then moves onto that record.

## Saved GitHub read

- **Covers.** The `pr_github_read` key, declared as `githubReadKey` in
  `services/gctk/pr/read.go`, in the four parts `SavedRead` declares in
  `services/gctk/pr/saved.go`. Its one writer is the one-PR update, `update`
  and `save` in `services/gctk/pr/refresh.go`, which `Poll` there runs for each
  PR whose cheap signs moved (`gctk pr poll`, from `orders/pr-poll.toml`),
  `Compare` runs for each PR whose full read differs from it (`gctk pr compare`,
  from `orders/pr-compare.toml`), and `Refresh` runs for one PR
  (`gctk pr refresh`). Its readers are `FromStore` in
  `services/gctk/pr/read.go`, which `answerFromStore` in
  `services/gctk/internal/cli/prstatus.go` calls for `gctk pr status`, and
  `PRAnswers` in `services/gctk/listing/pr.go` calls from `Read` in
  `services/gctk/standing/standing.go`, which the rig board's read and
  `gctk bead stands` ask, the landing order, which finds
  and does its work from it and the store (`plan`, `seenPR` and
  `decideAtHead` in `services/gctk/pr/landing.go`, through `Reconcile` for
  `gctk pr reconcile`, from `orders/pr-reconcile.toml`), decides a merge on
  what the one-PR update saves once it has re-read the PR in full
  (`rereadAndDecide` there, through `Reread` in `services/gctk/pr/refresh.go`),
  takes each post the conversation keeps untaken as its own ask (`takePlans`,
  `untakenOn` and `take` in `services/gctk/pr/take.go`, which has the update
  read the conversation again through `RefreshConversation` in `refresh.go`),
  converts the old receipts on a bead whose saved read shows the PR open, and
  unsets them once the saved conversation shows no post they reach untaken
  (`unconvertible` and `unsetReceipts` in `services/gctk/pr/convert.go`, which
  has the update read the conversation again the same way), decides each owned
  PR's red checks and conflict from its checks, its merge state and its
  approvals (`redPlans`, `redOn` and `decideRed` in
  `services/gctk/pr/redchecks.go`, which has the update read the PR again
  through `Reread` once GitHub shows a re-run of its checks that the saved
  read lacks, `red` there), and compares each owned
  PR's saved labels with the ones the store derives (`labelPlans` in
  `services/gctk/pr/labels.go`), and the PR watch itself, which compares a
  PR's signs with the ones each part keeps and reads again a conversation part
  that holds no list of untaken posts or a checks part that holds no suites
  (`moved` in `services/gctk/pr/saved.go`), and the net's full read with each
  part's facts (`differs` there).
- **Stands in for.** A record of GitHub's facts about a pull request, kept on
  the bead that owns it, from which a display derives the PR's status in place
  of reading GitHub, from which the landing order finds and does its work, and
  against which a pass of the PR watch tells
  whether the PR moved or differs from it. The facts are the PR's node id, state, draft flag, head and merge
  state, its merge commit and time once it merged, the required checks at that
  head, each with the check suite that holds its result and its log, each check
  suite there, with its status, its creation time and the attempt of the GitHub
  Actions run behind it, the standing approvals, each with the commit it was given on, and
  requests for changes, each post that is feedback the city has not taken,
  with what its ask names it by, the review threads waiting on the city's
  answer and those unresolved, and the PR's labels, in four parts that each
  keep the instant their read was sent and the cheap signs read with it.
- **Evidence.**
  - In `gastownhall/gascity`, the `gc` binary's PR readiness monitor lists each
    open PR's number, title, URL, author, draft flag, merge state, base and head
    refs, head commit and the last commit's check rollup (`pullRequestsQuery`
    in `internal/githubmonitor/client.go`). It reads no review, review thread
    or comment, and no check's required flag. It writes what it finds as
    `github.*` keys on a repair bead it files for a PR it finds actionable
    (`ensureGitHubPRRepairBead` and `githubPRRepairVolatileMetadata` in
    `cmd/gc/cmd_github.go`), never on the bead that owns the PR. Only
    [gc github pr backfill](https://docs.gascity.com/reference/cli#gc-github-pr-backfill)
    runs it, and a monitor's
    [GitHubPRMonitor](https://docs.gascity.com/reference/config#githubprmonitor)
    entry declares a poll interval and a webhook secret, which no code outside
    the configuration package reads. No Go source there, tests aside, reads a
    pull request's reviews or review threads. The monitor's check rollup gives
    each check's name, status, conclusion and log, and no check suite, no
    suite's creation time and no Actions run's attempt.
  - A webhook rule hands one verified provider event to an order or a
    conversation and keeps no state of its own
    ([WebhookRule](https://docs.gascity.com/reference/config#webhookrule) in
    the configuration reference).
  - In `gastownhall/gascity-packs`, Gas Town's `pr-merge-reconcile` reads a
    PR's URL, number, state, head and base refs, head commit, merge time and
    merge commit (`gh pr view` in `gastown/commands/pr-merge-reconcile/run.sh`
    180-181), and writes only its record's own keys, such as `pr_state`,
    `observed_pr_head_sha` and `pr_reconcile_error`. No pack keeps GitHub's
    reviews or merge state for a PR on a bead, or its checks on the bead that
    owns the PR: the `pr-review` pack's `mol-pr-ci-diagnose` notes counts of a
    PR's checks from `gh pr checks` on its own run's root, with no required
    flag and no head (`pr-review/formulas/mol-pr-ci-diagnose.formula.toml`).
    The review keys packs write are about the reviews their own runs make or
    ask for, such as the `gascity` pack's `gc.github.review_outcome`.
  - In `gastownhall/beads`, `bd github sync` reads and writes issues, their
    sub-issues and blocking links, and their labels through bd's GitHub client
    (`internal/github/client.go`), and a `gh:pr` gate reads only a PR's state
    and title (`checkGHPRWithRunner` in `cmd/bd/gate.go`).
  - The search is [specs/tk-1tfzr71.134/gas-city-search.md](../specs/tk-1tfzr71.134/gas-city-search.md),
    the search for the parts, their signs and their one writer is
    [specs/tk-1tfzr71.149/gas-city-search.md](../specs/tk-1tfzr71.149/gas-city-search.md#the-one-pr-update-saves-githubs-side-on-the-bead-unit-1),
    read at `gastownhall/gascity` main 9a4b1e718, and the search for the
    untaken posts the conversation keeps is
    [specs/tk-1tfzr71.161/gas-city-search.md](../specs/tk-1tfzr71.161/gas-city-search.md#the-saved-reads-untaken-posts-unit-2),
    and for the check suites the checks keep, its
    [red checks](../specs/tk-1tfzr71.161/gas-city-search.md#red-checks-unit-5).
- **Verified.** 2026-11-25, at `gastownhall/gascity` main 944ef25f3b2b,
  `gastownhall/gascity-packs` main 44b9db7168f6, and `gastownhall/beads` main
  786241099046.
- **Retires when.** Gas City records the facts the rule reads, namely a pull
  request's reviews, the required checks at its head and its review threads,
  where a reader of the PR's own bead finds them, for example once its PR
  monitor reads them and writes them on the bead that owns the PR, once Gas
  Town's pending record carries them, or once a webhook receiver keeps them
  from GitHub's events. The saved read then moves onto that record.

## Approval withdrawal

- **Covers.** The `withdraw_head` key, declared in `services/gctk/pr/keys.go`,
  on the task a withdrawal is. Its writer: `Withdraw` in
  `services/gctk/pr/withdraw.go`, which the `withdraw` verb of
  `services/gctk/internal/cli/prcycle.go` runs. Its carrier is the landing
  order: `withdrawalsIn`, `approvalsIn`, `withCarry`, `carry`, `carryOne`,
  `readUnrouted` and `withoutHead` in the same file, which the order's run in
  `services/gctk/pr/landing.go` calls on each act that decides the record of a
  PR no ruling retired, on the act's own read of the PR's reviews and the
  history the rig's clone holds once the act fetches the PR's branch. It
  dismisses an approval only once the act's own reads of the PR's reviews and
  review threads show neither the approval's message nor an inline comment it
  carries as feedback the city has not taken (`unrouted` in
  `services/gctk/pr/feedback.go`), and closes a withdrawal once its read of the
  reviews after the dismissals shows none standing on a commit without the
  head. Once a ruling has retired the PR and
  the read the PR watch saved shows it closed, `decideRetired` in
  `landing.go` closes each withdrawal still open, since no approval it
  withdraws can merge a closed PR. Its reader for the review run:
  `WithdrawalFor` in `withdraw.go`, which the `output` verb of
  `services/gctk/internal/cli/reviewrun.go` reads to refuse a triage output
  that rules its head material before the withdrawal for that head is filed.
- **Stands in for.** A withdrawal of a pull request's approvals once a head
  changes what the PR does: an operation that dismisses each approval given on
  a commit without that head, and holds the PR's bead from merging until a read
  of the PR's reviews shows none standing.
- **Evidence.**
  - In `gastownhall/gascity`, no code dismisses a GitHub review or reads one.
    The PR readiness monitor reads each open PR's author, draft
    flag, merge state, branches, head and check rollup (`pullRequestsQuery` in
    `internal/githubmonitor/client.go`). A search of the repository for a
    dismissal finds a session's startup dialogs, mail and a dashboard note,
    and no review.
  - A dismissal can wait on the take, and GitHub can refuse it or not answer,
    so the withdrawal must last until a later pass carries it out. Gas City
    keeps no such wait for a write to an outside service: a failed order is not
    retried ("No retry on dispatch failure" in
    `engdocs/architecture/orders.md`), and `[steps.retry]` retries a step's
    attempt within its run (section 3.2 of
    `docs/reference/specs/formula-spec-v2.md`).
  - In `gastownhall/gascity-packs`, no pack dismisses a review. The
    `pr-review` pack posts one kind, a review that requests changes, from its
    `mol-adopt-pr` and `mol-pr-merge-only` formulas. Gas Town's
    refinery patrol and its `pr-merge-reconcile` read a PR through the pulls
    API and none of its reviews (`gastown/formulas/mol-refinery-patrol.toml`
    and `gastown/commands/pr-merge-reconcile/run.sh`) at packs main, and the
    patrol does the same at the pin Gas City bundles, which carries no
    `pr-merge-reconcile`. The approvals the `gascity` and `gastown` packs
    record are review workflows' verdicts on beads
    (`gascity/assets/scripts/checks/implementation-review-approved.sh` and
    `gastown/assets/scripts/checks/adopt-pr-review-approved.sh`), not GitHub
    reviews.
  - The search is the draft cycle and the withdrawal in
    [specs/tk-1tfzr71.108/gas-city-search.md](../specs/tk-1tfzr71.108/gas-city-search.md).
- **Verified.** 2026-11-23, at `gastownhall/gascity` main ffd9f6b0cb68, with
  the `gastown` pack it bundles at 66897e7132c9, and `gastownhall/gascity-packs`
  main 44b9db7168f6.
- **Retires when.** Gas City dismisses a pull request's approvals given before
  a head, or keeps a write to GitHub that a later pass carries out. The
  withdrawal then moves onto that operation.

## Asks

- **Covers.** The `review_checks` key, declared in
  `services/gctk/review/keys.go`, on the task an ask is. Its writer: `FileAsk`
  in `services/gctk/review/ask.go`, which the `ask` verb of
  `services/gctk/internal/cli/review.go` runs. Its readers, which know an ask
  by its shape: `isAsk`, `IsAsk`, `AsksOn` and `AsksIn` in the same file,
  `writers` in `services/gctk/pr/admit.go`, which leaves an ask out of a
  branch's other writers, and `refinery_ask` in
  `assets/scripts/refinery-lib.sh`, which applies the same rule to the beads
  the refinery reads. Its close: `Record` in
  `services/gctk/review/result.go`, which the loop's check runs through the
  `passed` verb's `--record`.
- **Stands in for.** A request held on a pull request's bead for the review run
  that works it: a change on the PR's branch, or a check at its next head, that
  no pool claims, so the run stays the branch's one writer, with the checks a
  later run must run.
- **Evidence.**
  - In `gastownhall/gascity`, the one request the PR monitor files on a pull
    request is its repair bead, which it routes and hands a workflow as it
    files it (`ensureGitHubPRRepairBead` and `attachGitHubPRRepairWorkflow` in
    `cmd/gc/cmd_github.go`, with `gc.routed_to` set in
    `githubPRRepairMetadata`), so a pool works it as a writer of its own.
  - In `gastownhall/gascity-packs`, a change a branch needs goes to a pool as
    well. Gas Town's refinery reopens a rejected work bead with its
    `rejection_reason` and routes it to the polecat pool
    (`gastown/formulas/mol-refinery-patrol.toml`, at packs main and at the pin
    Gas City bundles), and the `pr-review` pack's `mol-pr-iterate` is slung to
    a polecat to address one piece of a PR's feedback
    (`pr-review/formulas/mol-pr-iterate.formula.toml`).
  - A search of both repositories finds no record on a bead of the checks a
    later review must run.
  - The rest of an ask is native: a task bead, a blocks edge onto the PR's
    bead filed in the same create, the `branch` key the record declares, a
    discovered-from edge to the bead it came from, a blocks edge of its own
    onto each bead it waits on, filed in that create through bd's
    `--deps blocked-by` (`parseDepSpec` and `canonicalDependencyType` in
    `cmd/bd/create_deps.go`, at `gastownhall/beads` v1.3.4, 7ef2fd05eb0c),
    and no route or assignee.
    Gas City's sling stamps `gc.execution_routed_to` on a work bead whose
    workflow it started, clears its `gc.routed_to` and `gc.run_target`, and
    leaves the bead unassigned while the workflow's steps are claimed
    (`restampWorkBeadRouting` in `internal/sling/sling_core.go`, read at
    `gastownhall/gascity` main 6cf1cccd640d), so an ask carries neither route,
    and never the role key `task_kind` that a rework child carries. The search
    is asks in
    [specs/tk-1tfzr71.108/gas-city-search.md](../specs/tk-1tfzr71.108/gas-city-search.md).
- **Verified.** 2026-11-23, at `gastownhall/gascity` main ffd9f6b0cb68, with
  the `gastown` pack it bundles at 66897e7132c9, `gastownhall/gascity-packs`
  main 44b9db7168f6, and `gastownhall/beads` v1.3.4 (7ef2fd05eb0c), the bd
  the city runs.
- **Retires when.** Gas City files a request for a pull request's branch that
  the run already attached to the PR's bead works, with no pool to claim it,
  such as a PR monitor that hands its repair to that run. The ask then moves
  onto that request.

## Agent home provisioning

- **Covers.** `assets/scripts/worktree-setup.sh`.
- **Stands in for.** A Gas City owner for the worktree an agent's sessions start
  in, which `gc worktree ensure` would be if it provisioned a tree for an agent
  rather than for a bead.
- **Evidence.**
  - In `gastownhall/gascity`, `gc worktree ensure` requires `--bead`,
    `--store-ref` and `--generation`. Its postcondition is "the bead's uniquely
    named branch checked out on an attached HEAD", on a path that is a direct
    child of `--root`
    ([gc worktree](https://docs.gascity.com/reference/cli#gc-worktree)). A home
    serves many beads and outlives each of them. `Ensure` in
    `internal/worktree/worktree.go` verifies an existing tree and never moves it,
    and it writes no bead redirect and no excludes, so a home would still need
    this script for all of that.
  - Nothing else provisions one. `work_dir` and `pre_start` are the agent's own
    config ([Agent](https://docs.gascity.com/reference/config#agent)), and the
    daemon's `auto_prune_worker_dir` and `auto_reap_closed_bead_worktrees` only
    remove trees. No formula in the core pack calls `gc worktree`:
    `mol-polecat-commit` and `mol-scoped-work` cut their per-bead trees with
    `git worktree add`.
  - In `gastownhall/gascity-packs`, Gas Town's own polecat and refinery provision
    their homes the same way: `pre_start` runs
    `gastown/assets/scripts/worktree-setup.sh`, from which this script descends.
    This pack imports no pack it could call that copy from.
  - Nothing in Gas City brings a home to the default tip at each start. The
    agent-home cleanup (`cleanupClosedBeadAgentHomeWorktrees` in
    `cmd/gc/agent_home_worktree_cleanup.go`) moves a home only when it carries
    the worker-dir prune's `.worktree-stale` marker, sits on a branch that names
    a closed bead and has no uncommitted work.
  - Nothing in Gas City brings a failed `pre_start` to a person. The command's
    output goes into the start's error, which the controller and reconciler log
    ([Agent](https://docs.gascity.com/reference/config#agent), `pre_start`). Five
    failed wakes in a row hold the session for five minutes
    (`defaultMaxWakeAttempts` and `defaultQuarantineDuration` in
    `cmd/gc/session_types.go`), and a failed pending create also counts toward
    a startup-health episode (`recordStartupHealthFailure` in
    `cmd/gc/session_lifecycle_parallel.go`). An episode that reaches that count
    records one `session.startup_health_alert` event and one reconciler log line,
    both without the error (`emitStartupHealthAlert` in
    `cmd/gc/startup_health_backoff.go`), and nothing in Gas City acts on that
    event. The doctor check that lists episodes leaves the error out too
    (`startupHealthEpisodesCheck` in `cmd/gc/doctor_startup_health.go`), and
    `session.quarantined` has no emitter (`cmd/gc/cmd_analyze_reliability.go`).
    So the script reports a home it cannot sync through `patrol-finding.sh`, one
    report per home, which the next clean start clears.
  - The search, and each way this script differs from Gas Town's and why, are
    in its records:
    [specs/tk-1tfzr71.10/gas-city-search.md](../specs/tk-1tfzr71.10/gas-city-search.md);
    [specs/tk-eu1f6tm/gas-city-search.md](../specs/tk-eu1f6tm/gas-city-search.md)
    for when the script fetches, its retry of the add and its signal traps; and
    [specs/tk-p0fbvug/gas-city-search.md](../specs/tk-p0fbvug/gas-city-search.md)
    for the move of a home whose HEAD is a tip the default branch had before a
    rewrite.
- **Verified.** 2026-11-23, at `gastownhall/gascity` main dfd5200c3ee3 and
  `gastownhall/gascity-packs` main 44b9db7168f6.
- **Retires when.** Gas City provisions a tree bound to an agent, with a sync to
  the default branch, or Gas Town's agents stop running a script of their own at
  `pre_start`.

## Deferred dispatch residual

- **Covers.** `orders/deferred-dispatch.toml`, `services/gctk/arm`, whose
  verbs `gctk bead arm`, `gctk bead disarm` and `gctk bead start-armed` every
  caller of the arm runs, which holds the dispatch lock those verbs take on each
  armed bead and the title token `arm:<bead>@<armed at>` its start pours under,
  the `gc.dispatch_when_ready` keys, and
  [deferred-dispatch.md](deferred-dispatch.md).
- **Stands in for.** A dispatch that waits for its bead's blockers, pouring the
  bead's formula once nothing holds it, exactly once.
- **Evidence.** In `gastownhall/gascity`, nothing pours a formula on a bead once
  it is ready:
  - No core order or script calls `gc sling`. The bundled `core` pack's
    `cascade-nudge-on-blocker-close` order runs on `bead.closed`, re-reads the
    closes with `gc events --since`, and nudges each dependent no other blocker
    still holds with `gc session nudge`, and `nudge-on-route` nudges a routed
    bead's target. Neither pours
    (`internal/bootstrap/packs/core/assets/scripts/cascade-nudge-on-blocker-close.sh`,
    `nudge-on-route.sh`).
  - `gc sling` pours at once. Nothing in `internal/sling` reads a bead's
    readiness before the pour, and `validateExistingBeadInQuerier`
    (`internal/sling/sling_core.go`) checks only that the bead exists.
  - Its launch check refuses a second pour of a formula only while the first
    run is live (`checkLegacySourceWorkflowConflict` in
    `internal/sling/sling_core.go`, and its exit 3 in `cmd/gc/cmd_sling.go`), and
    nothing reports a run that has finished, so the start titles each pour with
    its token and searches it after an earlier attempt.
  - Upstream tracks the gap as open P1 bugs: #7163, a formula slung onto a
    blocked bead runs before its blockers close, and #8832, native execution
    admission loses current input readiness, whose fix is the open PR #8834.
- **Verified.** 2026-11-23, at `gastownhall/gascity` main 35e0a4c6fc, with
  #7163, #8832 and PR #8834 open and unmerged.
- **Retires when.** Gas City holds a poured workflow's steps until its input
  bead is ready (gastownhall/gascity#8832, which PR #8834 fixes, and #7163). The
  arm then becomes a plain `gc sling <pool> <bead> --on <formula>` at arm time,
  and the order, the dispatch lock, the title token, the cap and
  `doctor/check-armed-dispatch-owed` retire.

## Feedback patterns

- **Covers.** The `feedback-pattern` name, the `evidence_count`,
  `distinct_sources`, `first_seen`, `last_seen`, `promotion_hold`,
  `proposal_bead`, `proposal_carrier`, `proposal_action` and `remedy_note`
  keys, in the `[metadata.learning]` table of `lifecycle/lifecycle.toml`. Their
  writer: `formulas/mol-feedback-distiller.toml`. The pattern's lifecycle is in
  [feedback-learning.md](feedback-learning.md).
- **Stands in for.** A learning loop's decision about one recurring piece of
  agent feedback, kept as work. The record gathers the observations that report
  the feedback and keeps the evidence they add up to, such as how many distinct
  events and sources report it. It carries the decision to adopt a standing
  rule, to wait for more evidence or to dismiss the feedback, and it closes once
  resolved and reopens when the feedback recurs.
- **Evidence.**
  - In `gastownhall/gascity`, no order or formula of the bundled `core` pack
    reads agent feedback (its `orders/` and `formulas/` directories under
    `internal/bootstrap/packs/core/`). `gc prompt synth`, which writes a role's
    prompt, works from a meta-prompt and a baseline template and takes no
    feedback (`docs/reference/cli.md`).
  - In `gastownhall/beads`, what keeps knowledge holds no decision.
    `bd remember` stores a text that `bd prime` injects into each session
    (`rememberCmd` in `cmd/bd/memory.go`). The Memory Beads proposal (issue
    #5877, open) would add a Memory Bead, which never becomes ready, blocked,
    claimed, completed or closed (R1), keeps evidence and confidence as an
    application's metadata (R3), and leaves judging whether its content is
    true, duplicated or contradictory to tools outside bd (R30). Either could
    hold an adopted rule but not the decision to adopt it, and no memory type
    is in `internal/types/types.go`.
  - In `gastownhall/gascity-packs`, the packs that capture learnings keep one
    record per learning. compound-engineering's `ce-compound` skill writes or
    updates a solution doc, and gstack's skills log each learning to a
    per-project `learnings.jsonl`. Neither counts how often a piece of feedback
    recurs or decides whether it becomes a standing rule.
  - So a pattern is a task the distiller triages, and its lifecycle composes
    bd's own work states: the `deferred` status with a date (`bd defer
    --until`), a `blocks` edge onto its follow-up, `bd close`, and `bd reopen`.
    The search is
    [specs/tk-ltcv43q/gas-city-search.md](../specs/tk-ltcv43q/gas-city-search.md).
- **Verified.** 2026-11-20, at `gastownhall/gascity` main b31d0b119475, `gastownhall/beads`
  main 3a274fbf8f76 and `gastownhall/gascity-packs` main aa55b477d4c2.
- **Retires when.** Gas City ships a loop that decides agents' recurring
  feedback as work, with the evidence each decision rests on.

## Patrol findings

- **Covers.** `assets/scripts/patrol-finding.sh`, the one writer of a patrol
  finding, and the finding's keys in the `[metadata.patrol_findings]` table of
  `lifecycle/lifecycle.toml`.
- **Stands in for.** A keyed problem record: one record per situation a patrol
  or an order observes, which a report of the same situation finds again by
  its key and counts as a recurrence, and which stays until the problem is
  resolved.
- **Evidence.** In `gastownhall/gascity`, nothing keeps current state per
  problem key:
  - `gc mail send --dedup` suppresses a send while an unarchived message with
    the same key is in the same mailbox, and once that message is archived the
    next send alerts again (`newMailSendCmd`'s `--dedup` in
    `cmd/gc/cmd_mail.go`).
  - Core's `escalate.sh` keys an incident only to throttle its mail: with
    `--incident-key` an unchanged incident is not sent again inside a reminder
    window, `--resolve-incident` forgets it, and the state it keeps under
    `.gc/incidents` is best-effort
    (`internal/bootstrap/packs/core/assets/scripts/escalate.sh`).
  - `gc event emit` appends one event to the city's log and keeps no state per
    key (`cmd/gc/cmd_event_emit.go`).
  - A doctor result needs no such record, because the doctor order records
    each run as one event, whose newest is what doctor found last
    ([the search](../specs/tk-1tfzr71.158/gas-city-search.md#the-doctor-order-gctk-doctor-run-and-its-event)).
    So this entry covers the patrol finding alone.
- **Verified.** 2026-11-23, at `gastownhall/gascity` main ffd9f6b0cb68.
- **Retires when.** Gas City ships a keyed problem record: one record per key,
  which a recurrence finds and updates and which stays until it is resolved.

## Memory note waits

- **Covers.** `services/gctk/memory`, and the state it keeps for each memory
  directory under the city's `.gc/runtime/packs/gc-toolkit/memory-intake`: the
  list of the notes the distiller kept, each with the bead it waits on or the
  date it is next due, the text of each note it removed, and the names of the
  removed notes whose pointers did not all come out. It also covers the folder
  in each memory directory that holds each file the intake displaced.
- **Stands in for.** Agent memory kept as beads. A memory that is a bead has
  its versions, its writer and its links to work in the ledger, and bd keeps
  the text of one that is deleted. Claude Code keeps memory as files, so the
  pack keeps those records itself.
- **Evidence.**
  - In `gastownhall/gascity`, nothing reads or empties an agent's memory. No
    file outside the tests names `MEMORY.md`, auto memory or
    `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, and the audit of Gas Town's commits
    defers agent memory (`engdocs/archive/analysis/gastown-upstream-audit.md`,
    "22g. Agent memory").
  - In `gastownhall/beads`, a wait holds only an issue. `bd defer --until`
    snoozes an issue (`cmd/bd/defer.go`), and a dependency joins an issue to a
    bd id or an `external:<project>:<capability>` reference (`cmd/bd/dep.go`).
    A note is a file, which neither can hold. bd's own memory plane,
    `bd remember` (`rememberCmd` in `cmd/bd/memory.go`), keeps a key and a
    value that `bd prime` injects into every session, with no wait.
  - In `gastownhall/beads`, the Memory Beads proposal (issue #5877, open, at
    its Revision 4 of 2026-09-22) would keep agent memory as beads. It is a
    proposal with no implementation in bd: no memory type is in
    `internal/types/types.go`, and the graph CLI specification read beside it
    (issue #6703) is a draft whose memory commands run only in a preview built
    from `versioned-beads/beads`. It would replace what the pack keeps. A
    memory would be a bead of its own kind, outside readiness and closure
    (R1), and deleting one would keep its history (R5). A compact listing
    would find a memory and a recall would read the whole of one, with who
    changed it and when (R6, R7, R12), and `bd prime` would load no memory
    body (R8). A reference could name one exact version of a memory (R18), and
    a link could join a memory to work and carry metadata (R17). It would not
    replace the judging: a link never blocks readiness (R17), and bd leaves
    judging whether a memory is true, current or useful to tools outside it
    (R30), so the distiller would still judge each memory and decide when the
    work it waits on is done.
  - Claude Code keeps memory files out of its retention sweep: "`MEMORY.md`
    and topic files stay until you or Claude edits or deletes them"
    ([memory](https://code.claude.com/docs/en/memory), "Storage location"). It
    turns memory off only whole, for a session, a project or every project of a
    user ("Enable or disable auto memory").
  - The search is
    [specs/tk-zlot608.8/gas-city-search.md](../specs/tk-zlot608.8/gas-city-search.md).
- **Verified.** 2026-11-19, at `gastownhall/gascity` main f5302d1dcfd5 and
  `gastownhall/beads` main 3a274fbf8f76, with the Memory Beads proposal at its
  Revision 4. Claude Code's memory page as read on 2026-11-19.
- **Retires when.** bd ships memory as a kind of bead with links to work (the
  Memory Beads proposal, `gastownhall/beads` issue #5877). The move is then
  the city's Claude agents keeping their memory there in place of Claude
  Code's directory, with the judge's decisions on those beads and their links,
  and the list, the kept text and the read of Claude Code's directories
  retire.

## Mail wake

- **Covers.** `orders/mail-notify-on-send.toml`,
  `orders/mail-notify-on-reply.toml`, `orders/mail-notify-reconcile.toml` and
  `services/gctk/mail`, the pass they run, with the notify ledger and its lock
  that the pass keeps under the city's `.gc/runtime/packs/gc-toolkit`.
- **Stands in for.** A session's turn requested for its unread mail whoever
  sent it, as `--notify` requests one when the sender asks. The notify ledger
  stands in for the replay of a keyed `gc session nudge`, which Gas City gives
  only where its op journal records the nudge.
- **Evidence.** In `gastownhall/gascity`, only the sender can request the
  recipient's turn, and a keyed nudge is kept from being sent twice only where
  the op journal records it:
  - `gc mail send --notify` and `gc mail reply --notify` request it, one
    message at a time (`newMailSendCmd` and `newMailReplyCmd` in
    `cmd/gc/cmd_mail.go`).
  - The API's send and reply, which the dashboard uses, take no notify option
    (`humaHandleMailSend` and `humaHandleMailReply` in
    `internal/api/huma_handlers_mail.go`).
  - `gc mail check --inject` shows unread mail only in a turn something else
    starts (`cmdMailCheckWithFormat` in `cmd/gc/cmd_mail.go`).
  - `gc session nudge --key` answers a rerun under the same key with the first
    run's outcome only "while the op journal records this command"
    (`sessionNudgeKeyUsage` in `cmd/gc/cmd_session.go`). With no `[ops]` gate
    set, the journal records only over a SQLite sessions store, and over a
    store bd serves it records under no gate until bd's writes take
    `--if-revision` (`OpsConfig` in `internal/config/ops.go`). A city `gc init`
    makes keeps its sessions in a SQLite store by default, while an upgrade
    leaves an older city's sessions in its work ledger ("Your city's storage
    stays as it was" in `docs/getting-started/upgrading.md`). There a keyed
    nudge runs unrecorded, and a rerun nudges again (`newCLIOp` in
    `cmd/gc/op_record.go`).
  - Issue #1966, a design issue that is open, carries the maintainer ruling of
    2026-06-28 that coordinator sessions "wake on mail with a debounce", and no
    code implements it.
  - The search is
    [specs/tk-qpnzxnj/gas-city-search.md](../specs/tk-qpnzxnj/gas-city-search.md).
- **Verified.** 2026-11-23, at `gastownhall/gascity` main ffd9f6b0cb68.
- **Retires when.** A Gas City release requests a session's turn for its unread
  mail whoever sent it, as #1966 rules. The orders and the verb then retire,
  and each agent they list is woken by Gas City. Before that, once the city
  keeps its sessions in a store the op journal records, the notify ledger's
  move onto a keyed nudge is due.
