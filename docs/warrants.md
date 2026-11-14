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
  - `workspace-setup` brings a rejected branch current by merge, where Gas Town's
    rebases it under an open PR, and waits behind a sibling.
  - `preflight-tests` runs the checks through `gctk rig`, so every polecat starting
    from one base shares one recorded run, and keys a tracker on a stamp. Core's
    runs each command raw per polecat and matches trackers by title.
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
    `{{test_command}}` raw, and its `workspace-setup` is a placeholder each
    variant overrides with a tree of its own. `mol-polecat-commit.toml` and
    `mol-scoped-work.toml` cut theirs with `git worktree add` and remove them with
    `git worktree remove` once the work is pushed.
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
  `workspace-setup`, `self-review` and `submit-and-exit`, rebases a rejected
  branch, and at the handoff detaches the tree and deletes its branch.
- **Verified.** 2026-11-13, at `gastownhall/gascity` main dba20336e and
  `gastownhall/gascity-packs` main 1f6d8e41c.
- **Retires when.** A step at a time. `load-context`: core's gate refuses finished,
  parked and held work and ends a run by cancelling it. `workspace-setup`: no end
  is planned for the merge resume, since the refinery brings every branch current
  by merge and never rebases one
  ([built-once-target.md](built-once-target.md#merge)).
  `preflight-tests` and `self-review`: Gas City ships a record of a check per
  commit. `submit-and-exit`: the merge and review nouns it holds retire, the
  bring-current guard among them with the review loop (`tk-1tfzr71.22`).

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
- **Verified.** 2026-11-14, at `gastownhall/gascity` main 420b7bb65f and
  `gastownhall/beads` main 8cdfa796a (`BuildReadyWorkOrder` in
  `internal/storage/sqlbuild/ready.go` orders the priority policy by the bead's
  own priority), with bd 1.3.4 (7ef2fd05e).
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
- **Verified.** 2026-11-10, at `gastownhall/gascity` main f1f75f53c and
  `gastownhall/gascity-packs` main c6f0a9aa6. The config reference's `[github]`
  table declares pull-request monitors, whose `authors` allow-list scopes the
  pull requests a monitor acts on, and scopes no agent's writes. GitHub's
  *Managing your personal access tokens* page was read on 2026-11-05.
- **Retires when.** Gas City ships per-agent write scoping. A GitHub
  fine-grained token covers only part of the origin rule. GitHub refuses it a
  write outside its one owner's selected repositories, so a stranger's
  repository is held out on GitHub's side. It cannot reach a second owner's
  repositories, or one where its account is an outside collaborator, yet a
  rig's origin can sit under another owner's account and a city-scope agent
  owns every rig's origin. A token the rigs share also leaves each rig's agents
  free to write to the others' repositories, which the guard refuses.

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
  live (`internal/sling/sling_core.go`, the lock at 676 and the check at 702,
  `checkLegacySourceWorkflowConflict`, which reads the live roots at 2026; the
  terminal-root skip in `internal/sling/sling_attachment.go` 321;
  and `TestLiveConvoyTrackedWorkflowRootsSkipsTerminalRoots` in
  `internal/sling/sling_test.go` 3975-4027). Once that root has closed, the next
  launch pours again. No `gc sling` flag checks an earlier root by its title or
  by a key, and `--scope-kind` with `--scope-ref` names a city or rig scope, not
  a caller's key (`cmd/gc/cmd_sling.go` 148-169).
- **Verified.** 2026-11-08, at `gastownhall/gascity` main c7a45437f.
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
  (`SlingMergeStrategy` in `internal/sling/sling.go` 1156-1171). Neither the
  reference nor the code chooses a strategy by the branch a bead lands on. In
  `gastownhall/gascity-packs`, the gastown refinery's merge-push step takes the
  bead's `merge_strategy`, `direct` when it has none, and moves a `direct` bead
  to `mr` only when it names an `existing_pr`, whatever its target
  (`gastown/formulas/mol-refinery-patrol.toml` 674-704).
- **Verified.** 2026-11-12, at `gastownhall/gascity` main 603e7eeec and
  `gastownhall/gascity-packs` main 1f6d8e41c.
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
    (`issueops/issueops.go` 561-566). bd's human gate
    (`bd gate create --type human`, `cmd/bd/gate.go` 1952) is the primitive the
    exception's gate composes.
  - A search of `gastownhall/gascity` and `gastownhall/beads` for a refused
    close finds no record of one kept on the bead for a person. What it finds
    in Gas City handles a refusal inside the closes Gas City makes itself, such
    as the autoclose sweep's retry of a convoy, wisp or molecule autoclose
    (`cmd/gc/autoclose_sweep.go` 21-22).
- **Verified.** 2026-11-13, at `gastownhall/gascity-packs` main 1f6d8e41c,
  `gastownhall/beads` main 526c1c877 and `gastownhall/gascity` main cb9105579.
- **Retires when.** Gas Town's `pr-merge-reconcile` escalates a close it cannot
  make. The exception then moves onto what Gas Town records.

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
- **Verified.** 2026-11-13, at `gastownhall/gascity` main cb9105579667,
  `gastownhall/gascity-packs` main 1f6d8e41c5b0, and `gastownhall/beads` main
  526c1c877e26.
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
  handled post with (`WB_RESOLVED_REACTION`). Its reader is package
  `services/gctk/prstatus`: `RowFacts` reads it off the anchor and
  `unansweredFeedback` decides from it. `prstatus.Read` gathers it for
  `gctk pr status` in `services/gctk/internal/cli/prstatus.go` and for the
  helm board's beads source in `services/helm/internal/source/beads.go`.
- **Stands in for.** A record of a pull request's review threads kept on the
  bead whose pull request it is, which says whether review feedback still
  waits on an answer.
- **Evidence.**
  - In `gastownhall/gascity`, the `gc` binary's pull request readiness monitor
    reads each open PR's author, draft flag, merge state, head and check rollup
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
  - In `gastownhall/gascity-packs`, no pack keeps a record of which of a pull
    request's review threads wait on an answer. The `pr-review` pack's
    `mol-pr-iterate` formula checks whether the copilot comments it was slung
    to address are resolved, and records on its own run only whether that one
    signal cleared (`evidence.cleared`, in
    `pr-review/formulas/mol-pr-iterate.formula.toml`). The
    `compound-engineering` pack's `ce-previous-comments-reviewer` agent reads a
    PR's review comments for feedback the diff leaves unaddressed and returns
    findings, and its `ce-pr-comment-resolver` agent is handed a thread to fix
    or answer. Neither keeps a record of the thread.
  - The search is [specs/tk-iydyiup/gas-city-search.md](../specs/tk-iydyiup/gas-city-search.md).
- **Verified.** 2026-11-13, at `gastownhall/gascity` main cb9105579667 with
  the `gastown` pack it bundles at 66897e7132c9, `gastownhall/gascity-packs`
  main 1f6d8e41c5b0, and `gastownhall/beads` main 526c1c877e26.
- **Retires when.** Gas City records a pull request's review threads where a
  reader of the PR's own bead finds them, for example once its readiness
  monitor reads review threads, or a webhook receiver keeps their state from
  GitHub's review thread events. The count then moves onto that record.

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
    `cmd/gc/session_lifecycle_parallel.go`). Nothing sends the alert an episode
    marks pending (`RecordStartupFailure` in `internal/session/startup_health.go`),
    the doctor check that lists episodes leaves the error out
    (`startupHealthEpisodesCheck` in `cmd/gc/doctor_startup_health.go`), and
    `session.quarantined` has no emitter (`cmd/gc/cmd_analyze_reliability.go`).
    So the script reports a home it cannot sync through `patrol-finding.sh`, one
    report per home, which the next clean start clears.
  - The search, and each way this script differs from Gas Town's and why, are
    in two records:
    [specs/tk-1tfzr71.10/gas-city-search.md](../specs/tk-1tfzr71.10/gas-city-search.md),
    and [specs/tk-eu1f6tm/gas-city-search.md](../specs/tk-eu1f6tm/gas-city-search.md)
    for when the script fetches, its retry of the add and its signal traps.
- **Verified.** 2026-11-08, at `gastownhall/gascity` main 27a4857eabd5 and
  `gastownhall/gascity-packs` main 2a3b142e3fbd.
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
- **Verified.** 2026-11-14, at `gastownhall/gascity` main 420b7bb65f, with
  #7163, #8832 and PR #8834 open and unmerged.
- **Retires when.** Gas City holds a poured workflow's steps until its input
  bead is ready (gastownhall/gascity#8832, which PR #8834 fixes, and #7163). The
  arm then becomes a plain `gc sling <pool> <bead> --on <formula>` at arm time,
  and the order, the dispatch lock, the title token, the cap and
  `doctor/check-armed-dispatch-owed` retire.

## Quota-park nudging

- **Covers.** `assets/scripts/quota-park-nudge.sh`,
  `orders/quota-park-nudge.toml`, the nudge episode files under the city's
  `.gc/runtime/quota-park`, and
  [quota-park-recovery.md](quota-park-recovery.md).
- **Stands in for.** Waking a live session that sits idle under a provider's
  usage-limit banner once the limit resets.
- **Evidence.** In `gastownhall/gascity`:
  - The session reconciler classifies only a dead session's exit. A live
    session short-circuits the classification and is never classified
    (`ExitFacts.Alive` in `internal/session/lifecycle_exits.go`).
  - Its provider-screen lane runs for a dead crash candidate. A session whose
    process died on a provider's limit screen sleeps for a fixed 30 minutes,
    after which the quarantine clears (`checkRateLimitStability` in
    `cmd/gc/session_reconcile.go`, `defaultRateLimitQuarantineDuration` in
    `cmd/gc/session_types.go`). Nothing wakes or nudges a live session idle
    under the banner.
- **Verified.** 2026-10-28, at `gastownhall/gascity` main 221b1476dc10.
- **Retires when.** Gas City wakes a session parked on a provider's limit once
  the limit resets, or every provider the city runs resumes such a session by
  itself.

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
- **Verified.** 2026-11-12, at `gastownhall/gascity` main 1f0c10495b1c,
  `gastownhall/beads` main e51a90036718 and `gastownhall/gascity-packs` main
  1f6d8e41c5b0.
- **Retires when.** Gas City ships a loop that decides agents' recurring
  feedback as work, with the evidence each decision rests on.
