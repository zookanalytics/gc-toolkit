---
name: Gas City routing model (platform facts)
description: How Gas City delivers a bead to the session that acts on it, where upstream's docs leave it unsaid or state it wrongly — what the sling router writes, what the claim predicate reads back, how a graph.v2 pour routes its records, what holds a bead off the predicate, the bd guard that can refuse a detach, and the route the controller restores — each cited and dated. gc-toolkit's own dispatch conventions are deferred-dispatch.md.
---

# Gas City routing model

This page states Gas City behavior only: how a bead reaches the session that
acts on it, where upstream's docs do not already say it, or say it wrongly.
Each section names its evidence and the date it was read. Where the city's
gascity fork behaves differently from upstream main, the section says which
is which. gc-toolkit's own dispatch conventions — withholding a sling until
its blockers close, the notice a named-agent assignment owes, the load-context
guard in its work formula — are [deferred-dispatch.md](deferred-dispatch.md)
and [pack-authoring.md](pack-authoring.md).

## Scope

**Mandate.** How Gas City delivers a bead to the session that acts on it:
what each delivery form writes, what the claim predicate reads back, how a
graph.v2 pour routes the records it creates, what holds a bead off the
predicate, and the route the controller restores — as far as upstream's docs
do not state it, or state it wrongly.

**Boundaries.** Who the agents are — identity, variants, session lifecycle —
is [gascity-agents.md](gascity-agents.md). gc-toolkit's own dispatch
conventions are [deferred-dispatch.md](deferred-dispatch.md), and which hold a
pack component reaches for is invariant I1 in
[component-model.md](component-model.md). Upstream's reference material is
indexed by [gascity-reference.md](gascity-reference.md).

## What upstream's docs already say

Read these first; this page does not restate them. Coverage checked
2026-10-19 against `gastownhall/gascity` at `1e05ae624`, and bd 1.3.1's docs.

- **The two delivery forms are distinct.** Generic pool demand is ready work
  with `assignee=""` and `gc.routed_to=<target>`; direct named-session
  delivery is `assignee=<named-session-identity>` with no route metadata, and
  the offer and the demand count share one predicate —
  [dispatch architecture](https://github.com/gastownhall/gascity/blob/main/engdocs/architecture/dispatch.md),
  "scale_check ↔ work_query correspondence", and the
  [session model](https://github.com/gastownhall/gascity/blob/main/engdocs/design/session-model-unification.md),
  "Default `work_query`".
- **The default sling query and work query**, including the work query's
  three tiers — [config reference](https://docs.gascity.com/reference/config),
  `Agent`, `sling_query` and `work_query`.
- **The sling flags** — `--on`, `--formula`, `--no-formula`, `--reassign`,
  `--force` — [CLI reference](https://docs.gascity.com/reference/cli),
  `gc sling`.
- **`default_sling_formula`** applies a formula through `--on` unless
  `--no-formula` is given, and **`default_sling_targets`** takes precedence
  over `default_sling_target` and picks one entry at random per dispatch —
  config reference, `Agent` and `Rig`.
- **The routed tier's order** is the reader's canonical ready order:
  priority, then `created_at`, then id — CLI reference, `gc ready`.
- **`gc.routed_to` is the one persisted routing key**; `gc.run_target` is a
  recipe hint the router resolves into it — session model, "`gc.run_target`",
  and [formula spec v2](https://docs.gascity.com/reference/specs/formula-spec-v2),
  §2.
- **The dispatch-hold labels** `hold:mayor` and `hold:external` filter what an
  agent should do and never which sessions exist, and are written with
  `bd set-state <bead> hold=<value>` —
  [hold-label conventions](https://github.com/gastownhall/gascity/blob/main/engdocs/contributors/hold-label-conventions.md).
- **A sling refuses a cross-store route** ("refusing cross-store route"),
  with city-scoped agents the exception —
  [understanding formulas](https://docs.gascity.com/guides/understanding-formulas),
  "Cook, Sling, or Order".
- **A graph.v2 pour's shape**: independently Ready-visible steps carrying
  `gc.root_bead_id`, a `tracks` edge from every non-root node to the root, and
  a one-item synthetic input convoy that tracks the work bead and is named on
  the root as `gc.input_convoy_id` — formula spec v2, §2, and
  [convoy-first formulas](https://github.com/gastownhall/gascity/blob/main/engdocs/design/convoy-first-formulas-and-drain-v0.md).
- **bd's blocked semantics**: a blocked parent blocks its children, and a
  closed issue never blocks — bd's `docs/core-concepts/dependencies.md` and
  `engdocs/INTERNALS.md`.

Upstream's docs disagree with each other, and with the code, in places this
page settles below. The dispatch architecture's invariant 10 and
`life-of-a-bead.md` still describe `--assignee` and `pool:` label sling
defaults; the config reference's `gc.routed_to` default is what the code does.
The session model calls a stored `gc.run_target` inert; the controller
restores routes from it. Formula spec v2 says in §0.2 that a workflow root
blocks on its `workflow-finalize`, and in §2 and §3.5 that the link is an
informational `tracks` edge; the code agrees with §2. And tutorial 06 still
words routing as "assignee or `gc.routed_to` metadata", two parallel paths,
where the dispatch architecture states the two forms are distinct.

## The sling router writes `gc.routed_to` and never `assignee`

The built-in sling router writes exactly one key, `gc.routed_to`, for a pool
target and a named-session target alike. A pool slot suffix (the `-N` of a
multi-session pool) collapses to the base pool name before the write; a name
that is itself a configured agent is never collapsed. The only assignee write
to an existing bead on the sling path is the `--reassign` clear. A graph pour
can set an assignee on the step beads it creates, and an agent with a custom
`sling_query` runs its own command instead of the router.

`--reassign` clears the prior assignee and resets an `in_progress` bead to
`open` in the same update, and it never names a new assignee. It does nothing
only when the bead is already open and unassigned, and it runs after the
idempotent short-circuit, so a bead already routed to the same target returns
before the reset unless `--force` is given. It is skipped on a standalone
formula launch (`gc sling <target> <formula>`), whose argument is a formula
name rather than a bead.

*Evidence:* `cliBeadRouter.Route` (`cmd/gc/cmd_sling.go`),
`NormalizePoolRouteTarget` (`internal/agentutil/resolve.go`),
`shouldReopenForReassign` and `reopenForReassignInStore`
(`internal/sling/sling_core.go`), read at upstream `1e05ae624` and the fork
`a319c2fd6` on 2026-10-19.

## The read side: the claim predicate

`gc hook` finds work through the agent's `work_query`. The built-in query's
tiers are in the config reference; what it leaves out:

- **The assignee tiers match three identities.** Tier 1 (in-progress
  recovery, a `bd list --status=in_progress`) and Tier 2 (ready assigned
  work, `bd ready --assignee`) each try `$GC_SESSION_ID`, `$GC_SESSION_NAME`
  and `$GC_ALIAS` in order, first non-empty result winning. Tier 2 passes no
  `--exclude-type=epic`, so an assigned epic is offered as owned work.
- **The routed tier excludes three labels.** It is
  `bd ready --metadata-field "gc.routed_to=$target" --unassigned
  --exclude-type=epic --exclude-label "hold:mayor" --exclude-label
  "hold:external" --exclude-label "human" --json --limit=20`, with no
  `--sort`, so a worker takes the first row it can claim in the reader's
  canonical order, priority first. `gc ready` documents the same set but
  applies no exclusion by default; there they are caller flags.
- **Only an ephemeral session, or one whose alias is the target, reads the
  routed tier.** The tier exits unless `$GC_SESSION_ORIGIN` is `ephemeral` or
  empty (the controller's own demand probe runs with no session context), or
  the session's `$GC_ALIAS` equals the probe target. A plain named session's
  alias is its qualified name, which is also its routed target, so it claims
  a bead routed to itself (`gc.routed_to=<its alias>`, `assignee=""`). A named
  session backed by a pool probes the pool name, which differs from its
  alias, so it stays out of its pool's routed queue, and a manual session
  with no alias never reaches the tier.
- **Routed demand wakes an on-demand named session.** The controller counts
  routed, unassigned demand on an `on_demand` named session backed by a
  canonical singleton pool as the wake reason `routed-demand`, which also
  wakes a drained session.

*Evidence:* `assignedReadyTierCommand`, `bdReadyPoolDemandShell` and
`PoolDemandServeRules.ShellArgs`, `poolDemandOriginGateScript` and
`namedSelfTargetAdmit` (`internal/config/workquery.go`); `HumanLabel`
(`internal/beadmeta/hold_labels.go`); `ComputeAwakeSet`
(`cmd/gc/compute_awake_set.go`); read at upstream `1e05ae624` and the fork on
2026-10-19. The self-target admission arrived in upstream #6180 on
2026-09-08, and the city's installed `gc` (`b7da5db00`) carries it.

### A route with a slot suffix is collapsed to the pool's base name

The offer side compares a bead's route to the worker's target as an exact,
case-sensitive string, or after decoding the session-name encoding (`--` for
`/`, `__` for `.`); it does no slot collapse. The controller's demand count
does: it passes each candidate route through `NormalizePoolRouteTarget`, and
a pass in the same tick writes the collapsed base route onto open, unassigned
beads routed at a live slot suffix, so such a bead becomes claimable rather
than counted as demand no worker can take. A pool with a custom `scale_check`
still gets the default probe while it is cold, clamped to one session,
except a store-scoped control dispatcher.

*Evidence:* `hookClaimMatchesRoute` and `hookRouteIdentitiesEqual`
(`cmd/gc/cmd_hook_claim.go`); `demandServableForTemplates`,
`routeCollapseRewriteTarget` and `collapseSlotSuffixedRoutedWork`
(`cmd/gc/demand_serve_predicate.go`); `coldWakeTemplates`
(`cmd/gc/build_desired_state.go`); read at upstream `1e05ae624` and the fork
on 2026-10-19.

## A graph.v2 attach routes the workflow root

`gc sling <target> <bead> --on <formula>` — or a bare sling whose target
carries a graph.v2 `default_sling_formula` — pours a workflow and routes it
differently from a plain sling:

- **The workflow root is the routed record.** The root gets
  `gc.routed_to` (its `gc.run_target` deleted), and the pour promotes it to
  `in_progress`, so a routed-tier read never returns it. The pool claims the
  root's Ready-visible step beads. The root is linked to its
  `workflow-finalize` step by a non-blocking `tracks` edge, so finalize does
  not block it.
- **The work bead gets `gc.execution_routed_to`**, a key no offer predicate
  reads. Upstream leaves any `gc.routed_to` the work bead already carried in
  place, so a bead an earlier plain sling routed stays claimable beside its
  workflow. The city's fork clears it, on the attach bead and on every member
  of the root's input convoy, so a workflow is the bead's one live dispatch
  surface.
- **A classic (non-graph) attach routes the work bead instead**, with the
  plain sling's contract, and leaves the wisp root unrouted, because the work
  bead is the claimable unit. A standalone launch (`gc sling <target>
  <formula>`) routes its root.
- **A second pour of the same formula over a bead a live workflow drives is
  refused** with `already has live workflow(s)` and exit code 3. The lookup
  walks from the bead to its tracking synthetic convoys and keeps the live
  roots with the same `gc.formula_name`, so a different graph.v2 formula over
  the same bead is not refused. `--force` skips that lookup (the legacy
  `gc.source_bead_id` check still refuses), and over a bare bead it mints a
  fresh convoy and root, so the second workflow runs beside the first.
- **A poured node withholds delivery** in `gc.deferred_routed_to`,
  `gc.deferred_execution_routed_to` and, for a node with an assignee,
  `gc.deferred_assignee`, each promoted into its live key when the node
  activates.
- **The sling's JSON `routed: true` is not a claim route.** It is computed as
  `result.Routed > 0 || (!result.Idempotent && result.BeadID != "" &&
  !result.DryRun)`, so it is true for an attach that wrote no claim route on
  the work bead.

So a bead meant to be claimed directly — whose own `gc.routed_to` is the
offer — must not be slung to a target that carries a graph.v2 default
formula without `--no-formula`: the sling wraps it in a workflow, and on the
fork it also loses its route.

*Evidence:* `ApplyGraphRouting` and `DecorateGraphWorkflowRecipe`
(`internal/graphroute/graphroute.go`); `attachFormulaToBead`,
`restampWorkBeadRouting` and `checkLegacySourceWorkflowConflict`
(`internal/sling/sling_core.go`); `PromoteWorkflowLaunchBead` and
`stampGraphV2RootMetadata` (`internal/sling/sling.go`);
`liveConvoyTrackedWorkflowRoots` (`internal/sling/sling_attachment.go`);
`addWorkflowRootDeps` (`internal/formula/compile.go`);
`deferGraphNodeRouting` (`internal/molecule/graph_apply.go`) and its
activation in `internal/molecule/molecule.go`; `slingJSONFromResult`
(`cmd/gc/cmd_sling.go`); read at upstream `1e05ae624` and the fork on
2026-10-19. The fork's route clear is `retireClaimRoute` and
`retireInputConvoyClaimRoutes`, which upstream does not have.

## A `blocks` dep between work beads does not hold a graph.v2 dispatch

Nothing on the sling path checks whether a bead is blocked. The dependency
walk a plain or default-formula sling runs is cycle detection only, and it is
skipped for `--formula`, `--on`, `--force` and `--dry-run`. Sling a blocked
bead and the molecule pours, routes its root, and a worker claims a step.

The claim predicate is dependency-aware only about the bead it reads, and
under a graph.v2 dispatch that is never the work bead: the pool reads the
root, which is `in_progress`, and the step beads, whose edges run to their
siblings and, by `tracks`, to the root. `tracks` is not a ready-blocking
type — the blocking set is exactly `blocks`, `waits-for` and
`conditional-blocks` — and the links that reach the work bead are metadata
pointers (`gc.input_convoy_id`, and on a legacy source-workflow root
`gc.source_bead_id`), which no readiness query follows. A plain sling and a
classic attach are different: there the work bead is the routed unit, and its
own blockers withhold it.

*Evidence:* `preflight` and `DetectCycle` (`internal/sling/sling_core.go`,
`internal/sling/cycle.go`); `readyBlockingDependencyTypes`
(`internal/beads/beads.go`); read at upstream `1e05ae624` and the fork on
2026-10-19 (the fork adds `ensureGraphWorkflowHasClaimableStep`, which checks
routing, not blocked state). A live reproduction on 2026-08-02 slung four
beads with two `blocks` deps between them, and all four molecules poured and
were claimed. No upstream doc and no upstream test states the end-to-end rule.

## What holds a bead off the predicate

The predicate's terms are a conjunction, so falsifying any one holds the
bead — for the tiers that term covers:

- **`gc.routed_to=""`** takes the bead out of the routed tier and out of
  pool demand. It leaves the assignee tiers: an `assignee` still offers the
  bead to that session.
- **A status other than `open`** takes it out of `bd ready`, which backs
  Tier 2 and the routed tier. Tier 1 reads only `in_progress` work a session
  already holds.
- **An open `blocks` dep** holds it only where the work bead is itself the
  routed unit (previous section).
- **A dispatch-hold label** (`hold:mayor`, `hold:external`) holds it from
  every hook path. The routed tier excludes the labels in its query, and the
  hook drops a held candidate on every path, `gc hook --claim` included;
  Tier 1 falls through to the ready tiers when its candidate is held. The
  assignee-scoped demand and liveness probes stay hold-transparent, so a held
  bead's owner still counts as existing. Only those label values hold —
  compared trimmed and case-insensitively — and a label that merely reads as
  a hold is ordinary work.
- **The label `human`** keeps a bead out of the routed tier's query, which
  excludes it beside the two hold labels.

`gc.routed_to` is the only metadata key the predicate reads. A key whose name
says hold — `hold_reason`, `rebase_hold` — holds nothing: the bead stays open,
routed and unassigned, and the next worker claims it.

The fork's route recovery (below) lacks the hold skip upstream added in
#7838, so on the fork a route can be restored onto a held bead.

bd's blocked flag adds what its docs leave out. A closed or pinned parent
never propagates it, and neither does an open parent that is not itself
blocked. A parent whose `defer_until` is in the future withholds its direct
children (not grandchildren) from `bd ready` unless deferred work is
requested. bd refuses a `blocks` edge from a parent onto its own descendant,
since the descendant would inherit the block it exists to lift.

*Evidence:* `PoolDemandServeRules.ShellArgs` (`internal/config/workquery.go`),
`filterUnreadyHookCandidates` (`cmd/gc/cmd_hook.go`, `cmd/gc/cmd_hook_claim.go`,
`cmd/gc/hook_cross_store.go`), `beadmeta.HasDispatchHold`,
`filterReadyByAssignee` (`cmd/gc/dispatch_control_ready.go`), read at upstream
`1e05ae624` and the fork on 2026-10-19; bd 1.3.1's `blocked_state.go` and
`ready_work.go` (`internal/storage/issueops/`), read on 2026-10-19.

## Clearing an assignee can be refused, and the refusal drops the whole update

bd refuses to change or clear the assignee of a bead another actor holds
`in_progress`:

> `cannot reassign <id>: held by "<holder>" (in_progress); coordinate with
> the holder (bd mail <holder>) — pass --force only if their claim is
> abandoned (crashed agent, expired lease), or use bd reclaim`

It does not refuse a claim (`--claim`), a compare-and-set (`--if-assignee`),
a holder that is the acting identity or the new assignee, a bead in any other
status, or a holder in `claim.pools`; `--force` overrides it. One `bd update`
carries every field edit, label edit, metadata edit and reparent for a bead
as a single atomic operation, so a refused id loses the permitted flags in
the same call too: nothing lands for it. Other ids in the same call still
update. The refusal is reported per id on stderr and exits 1.

The acting identity is `BEADS_ACTOR`. `gc` defaults it to `controller` in the
controller's own `bd` runners when the environment leaves it empty, so an
unattended sweep running as the controller is a stranger to every
session-held bead. Against a held bead, issue the route clear and the
assignee clear as separate calls, so the half that may land does.

*Evidence:* `validation.AssigneeNotStolen` (`internal/validation/issue.go`)
and `validateIssueReassignable` (`cmd/bd/update.go`) in bd 1.3.1, read on
2026-10-19; `applyControllerBdEnv` (`cmd/gc/bd_env.go`) at upstream
`1e05ae624` and the fork on 2026-10-19. A live probe on 2026-08-15 confirmed
the dropped batch.

## A stored `gc.run_target` is a route the controller restores

Upstream's session model calls a `gc.run_target` left on a stored bead inert
provenance. The controller reads it: route recovery restores `gc.routed_to`
from it on a kind-less work bead that carries a `gc.run_target` and no route,
and on a legacy workflow root while it is unexpanded. It skips a bead
mid-instantiation, one with a deferred route, one excluded from `Ready()`,
and (upstream only) one on a dispatch hold; the bead must be `open` and
unassigned, and the write is a compare-and-set. It runs at startup (phase
`startup-route-recovery`), on each tick for the beads the event feed named,
and as a full scan off the tick.

The fork adds one gate: it skips a bead a live graph workflow drives, failing
closed when it cannot tell, so a fork pour's route clear is not undone on the
next pass.

*Evidence:* `carriedPoolRoute` (`cmd/gc/route_recovery.go`),
`routeRecoveryLane.restoreRoute` (`cmd/gc/route_recovery_lane.go`),
`recoverUnroutedWorkRoutes`, `recoverUnroutedWorkRoutesDelta` and
`runRouteRecoveryBackstopLoop` (`cmd/gc/city_runtime.go`), read at upstream
`1e05ae624` and the fork on 2026-10-19; the fork's gate is
`liveGraphWorkflowDrivesBead`.

## The cross-store guard ignores `--force`

`--force` relaxes the cross-rig name guard, not the cross-store reachability
guard: the latter is skipped only for an agent with a custom `sling_query` or
with no config. To hand work to another rig's pool, file the bead in the
destination rig's store and sling it there.

*Evidence:* `shouldValidateBuiltInRouteStoreReachable` and
`shouldGuardCrossRig` (`internal/sling/sling_core.go`), read at upstream
`1e05ae624` and the fork on 2026-10-19.

## Refresh procedure

Each section's evidence line names what it was read from and when. Before
building on a section, re-read its symbols at current upstream main and in
this city's fork, and update the date with the reading; a section that names
a fork-only behavior is re-checked against upstream too, since the fork's
patches are upstream candidates. When upstream's docs come to state a
section's fact, replace the section with a line in "What upstream's docs
already say".
