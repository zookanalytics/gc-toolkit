---
name: Gas City routing model
description: How `gc sling`, direct assignee, `gc sling --reassign`, and the `--on <formula>` attach differ — which fields each lane is supposed to set, per the PR #1736 ruling, and the claim predicate that reads those fields back.
---

# Gas City routing model: sling vs assignee vs `--reassign` vs `--on`

## Scope

**Mandate.** How work is routed to agents: how a bead reaches the worker
that will act on it, and — the doc's distinctive charge — which routing
field each delivery path is responsible for setting. It is the authority
on that field-level contract. That contract has a **read side** — the
claim predicate that decides which beads a worker is offered — and it is
documented here too: the fields mean only what the predicate makes them
mean.

**Boundaries.** This doc covers *how* work moves between agents, not
*who* the agents are — that's [gascity-agents.md](gascity-agents.md). It
defines the routing contract; it is not a command tutorial.

## Provenance

| Doc-type or artifact | Producer | Source location | Surveyed at |
| --- | --- | --- | --- |
| PR #1736 closing comment (maintainer ruling) | julianknutsen | https://github.com/gastownhall/gascity/pull/1736#issuecomment-4504727391 | 2026-05-21 |
| PR #1841 — `--reassign` flag (merged 2026-05-12) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/1841 (merge commit `44fcee6af60277f87aaa063f72dafeff7f705966`) | 2026-05-21 |
| `TestDoSling_Reassign_NoOpWhenAlreadyEmpty` | gastown source | `rigs/gascity/internal/sling/sling_test.go:3809` (added in `043e61ea6cb99a9f89657e292c9459be8620714c`, observed at upstream/main `19a0bb201eb6d1723a10eecdae20371bd8ceeb17`) | 2026-05-21 |
| Upstream tutorial `docs/tutorials/06-beads.md` — **superseded by PR #1736 ruling, not yet updated** | gastownhall/gascity | https://github.com/gastownhall/gascity/blob/19a0bb201eb6d1723a10eecdae20371bd8ceeb17/docs/tutorials/06-beads.md (last touched in `eac98595e701008087f7ee6acecbf55d5dca7794`) | 2026-05-21 |
| Upstream CLI reference (`--reassign` row only) | gastownhall/gascity | `rigs/gascity/docs/reference/cli.md:2789` at upstream/main `19a0bb201eb6d1723a10eecdae20371bd8ceeb17` | 2026-05-21 |
| `CrossStoreRouteError` cross-store route guard | gascity source | `rigs/gascity/internal/sling/sling_core.go:607` (`validateBuiltInRouteStoreReachable`), gated by `shouldValidateBuiltInRouteStoreReachable` (`sling_core.go:210`) — note its predicate omits the `!opts.Force` bypass that `shouldGuardCrossRig` (`sling_core.go:202`) carries, so `--force` does not relax it; error text at `internal/sling/sling.go:686`. Verified current at gascity/main `434d57656` (the singleton assignee-stamping change, last commit to touch the guard). | 2026-06-19 |
| PR #2779 — `gc.routed_to` made the sole persisted routing key; `gc.run_target` demoted to compile-time-only (merged 2026-06-01) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/2779 (commit `fb32be6941be7627aaf169809e31629f0baf6118`); definition in `engdocs/design/session-model-unification.md` | 2026-06-19 |
| PR #3670 — `feat: add default_sling_targets for multi-target random dispatch` (merged 2026-07-03) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/3670; field at `rigs/gascity/internal/config/config.go:645`, resolver at `rigs/gascity/cmd/gc/cmd_sling.go:291`. Verified current at gascity/main `4ff645484`. | 2026-07-16 |
| Lane 4 formula-sling field contract (`--on` attach vs standalone launch) | gastownhall/gascity | **Classic** attach routes the source and leaves the wisp root unrouted — the graph.v2 attach does **not**, it routes its workflow root (see the graph.v2 clause later in this row): `rigs/gascity/internal/sling/sling_core.go:563` (`molecule_id` on source) and the rationale comment at `:569-578`, citing gastownhall/gascity#2848; pinned by `TestOnFormulaAttachesAndRoutes` (`rigs/gascity/cmd/gc/cmd_sling_test.go:4178`, which attaches the *classic* `code-review` formula), asserting source `gc.routed_to=mayor` at `:4202` and wisp-root `gc.routed_to` empty at `:4224`. Standalone launch routes the root instead: `slingFormula` (`sling_core.go:366`) finalizes on `mResult.RootID` at `:405`, and its own graph branch (`:395`) hands off to `doStartGraphWorkflow` at `:396` before ever reaching that finalize. Flags are mutually exclusive at `rigs/gascity/cmd/gc/cmd_sling.go:158`; `AttachFormula` leaves `IsFormula` false (`internal/sling/sling.go:326`) while `LaunchFormula` sets it true (`:305-309`). Reassign gate `shouldReopenForReassign` at `sling_core.go:335` (called at `:138`) with its rationale at `:328-334`, and the `Reassign` field comment at `internal/sling/sling.go:273-279`. Graph.v2 attach returns *before* all of that classic routing and routes its **workflow root** instead: the `isGraph` branch of `attachFormulaToBead` (`sling_core.go:479`) spans `:487-533` and calls `doStartGraphWorkflow` (`:516`, defined at `:726`), with the root's `gc.routed_to` stamped at `internal/graphroute/graphroute.go:569`. Line references re-verified in the `rigs/gascity` fork at `390624b0e`. | 2026-08-02 |
| Pool demand counts routed **and unassigned** | gastownhall/gascity | `bdReadyPoolDemandShell` at `rigs/gascity/internal/config/workquery.go:41-43` (`bd ready --metadata-field "gc.routed_to=$target" --unassigned --exclude-type=epic`); the jq form applies the same `assignee == ""` filter at `workquery.go:586`. Verified current at upstream/main `1dbf0731e`. | 2026-07-23 |
| Claim predicate — `gc hook` tiers, `bd ready` semantics, built-in pool query | running `gc` binary + live city | Read off the **running implementation**, not from prose: `gc hook --help` ("Finds routed work using the agent's `work_query` config"); `gc bd ready --help` ("open issues with no active blockers", "Excludes in_progress, blocked, deferred, and hooked issues", `GetReadyWork` semantics); the built-in queries embedded in the `gc` binary — the assignee tiers loop `for id in "$GC_SESSION_ID" "$GC_SESSION_NAME" "$GC_ALIAS"` around `bd list --status=in_progress --assignee=<candidate>` (in-progress recovery) then `bd ready … --assignee=<candidate> --exclude-type=epic --json --limit=…` (ready assigned), and the routed tier is `bd ready --metadata-field "gc.routed_to=<target>" --unassigned --exclude-type=epic --json --sort oldest --limit=…` (offer) with the same filter at `--limit 0` counted (demand); Go-side helper symbols `UnassignedRoutedWork` / `UnassignedInProgressPoolWork`. The routed-tier shape is corroborated by this rig's own `proactive` agent, whose `work_query`/`scale_check` in the resolved city config (`gc config show`) are that same filter, adding only a `--db` pin and an enablement guard. `hold:<value>` convention observed as the live `gc doctor` checks `hold-label-routed-to` and `hold-label-conventions:<scope>`. Binary build `salvage/gc-c05nr-89e2e699f`. | 2026-07-23 |
| Instance-suffixed `gc.routed_to` normalized on the **demand read side only** | gastownhall/gascity | `17130b324` — "Normalize routed work instance names in demand matching (#4596)". Read side: `controllerDemandRouteTarget` (`rigs/gascity/cmd/gc/build_desired_state.go:1718`, rationale comment at `:1707-1717`), reached from `defaultScaleCheckCountsAndDemand` (`:1474`, invoked at `:735`) for every template in `defaultScaleTargets` — which is *not* only the no-custom-`scale_check` pools (`:446`, `:491`, `:567`): a custom-`scale_check` pool also gets this probe while cold (`isCold` at `:476`; append + `coldWakeTemplates` at `:633-637`), its contribution clamped to 1 (`:757-759`) and merged as a maximum against the custom count (`:766-768`); helper `agentutil.NormalizePoolRouteTarget` (`rigs/gascity/internal/agentutil/resolve.go:228`); coverage `TestDefaultScaleCheckCountsAndDemandNormalizesInstanceSuffixedRouteTarget` and `…LeavesUnmatchedInstanceSuffixAlone` (`cmd/gc/build_desired_state_test.go`). Offer side deliberately unchanged and exact-match: `bdReadyPoolDemandShell` (`rigs/gascity/internal/config/workquery.go:41`) with `$target` from `poolDemandTarget()` (`:157`), and `hookClaimMatchesRoute`'s raw `==` (`rigs/gascity/cmd/gc/cmd_hook_claim.go:1205`) over base-name route targets (`cmd/gc/cmd_hook.go:468`, `:685`). Write side, two distinct helpers: `032c1fbcd` (#3963) centralizes the **agent-derived** route identity as `agentutil.RoutedToIdentity` (`resolve.go:204`, collapse to `PoolName`), which the default sling query inlines rather than calls (`internal/config/workquery.go:532-536` — `internal/config` cannot import `agentutil`, which imports `config`); the **explicit-target-string** collapse is the separate `agentutil.NormalizePoolRouteTarget` (`resolve.go:228`), applied by sling's built-in routing path at `cmd/gc/cmd_sling.go:766`. Assigned-work companion `738f44732` (#4597): `cmd/gc/assigned_work_scope.go:156`, `cmd/gc/pool_desired_state.go:178`. Read in the `rigs/gascity` fork at `390624b0e`, whose adopted upstream base is `e6135a435` (#4847). | 2026-07-31 |
| `default_sling_formula` — a default formula on the target silently converts a bare `gc sling <target> <bead>` from Lane 1 into a Lane 4 attach | gastownhall/gascity + this city's config | Formula-branch predicate at `rigs/gascity/cmd/gc/cmd_sling.go:978` — taken when `IsFormula` is set, **or** `OnFormula` is non-empty, **or** `NoFormula` is unset and `Target.EffectiveDefaultSlingFormula()` is non-empty; the plain-routing predicate `missingBeadForceApplies` (`:1183`) carries the same condition inverted. Opt-out `--no-formula` ("suppress default formula (route raw bead)") at `:153`, mutually exclusive with `--formula` and `--on` at `:159-160`. Resolver `EffectiveDefaultSlingFormula` (own → inherited → empty) at `internal/config/config.go:3581`. Default-formula and `--on` share one attach pipeline, `attachFormulaToBead` — contract comment "graph-vs-legacy behavior is byte-identical across both entry points" — at `internal/sling/sling_core.go:479-497`. JSON `routed` is computed independently of any routing write at `cmd/gc/cmd_sling.go:1138`; payload keys at `:1090-1106`; `workflow_id` sourced from `result.WorkflowID` (`internal/sling/sling_core.go:730`, source-bead stamp at `:752`). `mol-polecat-work` is graph.v2 via `[requires] formula_compiler = ">=2.0.0"`, matching `graphV2Requirement` / `UsesGraphCompiler` (`internal/formula/requirements.go:14-16`, `:299`). That formula is **imported, not repo-local** — no path under this rig's `formulas/` resolves it, so cite the resolution contract rather than a local file: `gc formula show mol-polecat-work --json` reports the formula plus the `search_paths` it resolved through, and for this formula that is the imported gastown pack's `gastown/formulas/mol-polecat-work.toml:48-49` (materialized in the local pack cache under `~/.gc/cache/repos/<hash>/`). Its stable source is that pack at the fork's adopted pin `sha:33d3a430a67d1782ad364556cb566bdb01d0afe3` — recorded in `rigs/gascity/examples/gastown/packs.lock:5-6`, as `PublicGastownPackVersion` (`internal/config/public_packs.go:11`), and as the `go.mod` pseudo-version `v0.3.1-0.20260617013242-33d3a430a67d` (trailing 12 hex == the pin); the module copy at `$(go env GOMODCACHE)/github.com/gastownhall/gascity-packs@<pseudo-version>/gastown/formulas/mol-polecat-work.toml` is byte-identical to the cached one (`cmp`, 2026-08-02). City scope: `default_sling_formula = "mol-polecat-work"` in this city's `city.toml`, resolved onto every agent in `gc config show`. Stamp-don't-sling counterexample in this repo: `assets/scripts/check-set-heal.sh:355-357` (rationale comment) and `:393` (the direct `gc.routed_to` stamp); the script contains no `gc sling` call. Applies to a **targetless** `gc sling <bead>` too, and by the same predicate: `inferSling1ArgTarget` resolves only a target *string* (`cmd/gc/cmd_sling.go:244-252`), which the shared path turns into an agent (`:433`) and stores as `opts.Target` (`:463-464`) — the same field an explicit target fills — before the `:978` branch is reached, so the resolved default target decides the lane exactly as a typed one would. Read in the `rigs/gascity` fork at `390624b0e`. | 2026-08-02 |
| A `blocks` dep between **work** beads does not gate a formula dispatch | gascity source + live city | Blocking dependency types are exactly `blocks`/`waits-for`/`conditional-blocks` (`readyBlockingDependencyTypes`, `rigs/gascity/internal/beads/beads.go:433`, read via `IsReadyBlockingDependencyType` at `:441`); `step` is separately a `readyExcludeTypes` member (`:424`, "non-root formula steps; parent molecule is the actionable unit", #1039) — but graph.v2 workflows deliberately skip that coercion so their steps stay independently claimable (`internal/molecule/graph_apply.go:206-212`). The routed record under graph.v2 is the **workflow root**, not the work bead (though what a pool worker actually claims are the Ready-visible *step* beads — the pour promotes the root to `in_progress`, `cmd/gc/cmd_sling_test.go:4494`, and the compiler blocks it on `workflow-finalize`): the root persists `gc.routed_to` (#2763 / ga-eld2x — `internal/graphroute/graphroute.go:562-570`, pinned by `TestDecorateGraphWorkflowRecipe_RootStampsRoutedToForClaim` at `internal/graphroute/graphroute_test.go:412` and `cmd/gc/cmd_sling_test.go:4497-4501`) and keeps an executable type instead of the `Ready()`-excluded `molecule` when `gc.kind` is `workflow`/`wisp` (`graph_apply.go:166-170` via `preserveExecutableRootType`, `internal/molecule/molecule.go:1333-1340`). The work bead itself is left unrouted; under the current convoy-first attach it is linked only by membership in the synthetic input convoy the pour mints (`internal/graphv2/invocation.go:415-445`, tracked via `TrackItem`'s `convoy --tracks--> bead` edge, `internal/convoy/membership.go:36`), which the root names in `gc.input_convoy_id` (`internal/sling/sling.go:1520-1534`) — the `workflow_id`/`gc.source_bead_id` pointer pair is written only when the pour carries a source bead (`internal/sling/sling_core.go:741-755`, `graphroute.go:576-577`), and `cmd/gc/cmd_sling_test.go:4460` and `:4506` pin both as empty for a convoy-first attach. The root's own `blocks` edge is formula-internal — root → `workflow-finalize` (`internal/formula/compile.go:672-699`), never to the work bead's blockers. By contrast a *classic* attached wisp routes the source bead and leaves the wisp root unrouted (`sling_core.go:569-578`). graph.v2 stamps `gc.root_bead_id` on every non-root node (`graph_apply.go:219-223`) and connects each step to the root with a deliberately non-blocking `tracks` edge — rationale comment and emit at `:288-313`. Withheld delivery is parked at pour in `gc.deferred_routed_to`, `gc.deferred_execution_routed_to`, and — only for a node that has an assignee — `gc.deferred_assignee` (`deferGraphNodeRouting`, `graph_apply.go:320-329`), each promoted into its live counterpart (`gc.routed_to`, `gc.execution_routed_to`, `assignee`) on activation (`cmd/gc/convergence_store.go:213-240`, `internal/molecule/molecule.go:1399-1406`). The hook's in-progress tier applies the same blocking-type set to the candidate's *own* dependency rows (`internal/config/workquery.go:199-201`, "would strand every molecule step"), pinned by `TestInProgressTierIgnoresNonBlockingDependencyTypes` (`internal/config/workquery_inprogress_blocked_test.go:117`). Negative finding on the write side: no blocker check anywhere on the sling path — the dep walk it does run is cycle detection only (`internal/sling/sling_core.go:114` → `DetectCycle`, `internal/sling/cycle.go:36`); no non-test file in `internal/sling/` reads blocker state (`blocked` occurs there only in `*_test.go` fixtures), and its sole occurrence in `cmd/gc/cmd_sling.go` is the cross-rig routing guard (`:2115`). Behavioral confirmation 2026-08-02 in signal-loom: four beads, two `blocks` deps between them, `gc bd blocked` correct, all four slung molecules poured and claimed within ~2 min. Live confirmation of root routing 2026-08-02 in gc-toolkit: every open `gc.kind=workflow` root is `issue_type=task` carrying `gc.routed_to=gc-toolkit/gc-toolkit.polecat`, with its steps linked by `gc.root_bead_id` and the `workflow-finalize` control bead separately routed to `gc-toolkit/core.control-dispatcher`. Read in the `rigs/gascity` fork at `390624b0e`. | 2026-08-02 |

## The maintainer's ruling

From julianknutsen's PR #1736 closing comment, verbatim — the lead
sentence:

> `assignee` and `gc.routed_to` are not duplicates, and the default
> sling path should not generally stamp both.

And, verbatim, the decision list at the end of the same comment:

> - Do not merge this PR.
> - Keep `gc sling` as queue/template routing: `gc.routed_to=<target>`,
>   no `assignee` by default.
> - For named-session delivery, assign the named-session identity
>   directly: `bd update <bead> --assignee <named-session-identity>`.
> - Clean up the Gastown polecat/refinery formula and prompt text that
>   currently says to set both `assignee` and `gc.routed_to`; that is
>   bad hygiene and can become stale-route confusion later, even if the
>   current direct-assignee path still works.

The lanes below are the resulting model. Lanes 1–3 are the ruling's
direct subject; Lane 4 (the formula attach) is the fourth delivery path
that the ruling did not address but that the same field contract has to
answer for.

## The four lanes

### Lane 1 — `gc sling <target> <bead>`: queue / template routing

- **When to use:** routing a bead to a pool, queue, or template — the
  cases where any worker matching the target is acceptable. This is
  the default sling path and the dispatch shape used by mayor,
  mechanik, deacon, and refinery when handing work back to the
  polecat pool.
- **Sets:** `metadata.gc.routed_to=<target>`. For a **pool target**
  (an agent that supports instance expansion) it leaves `assignee`
  empty. For a **singleton target** (a named session — no instance
  expansion) it *also* stamps `assignee=<target>`, because the
  singleton's hook skips the Tier 3 routed-pool query and would
  otherwise never surface the bead. That singleton stamp automates the
  ruling's own "assign the named-session identity directly" step, so it
  refines rather than contradicts the "no `assignee` by default"
  decision quoted above.
- **Conditional on the target carrying no `default_sling_formula`.**
  The field contract above is Lane 1's only while that field is unset.
  A target that carries a default formula — including one that merely
  *inherits* it from city scope — silently turns a bare
  `gc sling <target> <bead>`, with no `--formula` and no `--on`, into a
  **Lane 4 formula attach**, and under a graph.v2 default formula that
  writes *neither* routing field. `--no-formula` is the opt-out that
  restores the shape above. This is not a corner case in a city that
  sets the field at city scope: see
  ["When a bare sling is silently Lane 4"](#when-a-bare-sling-is-silently-lane-4--default_sling_formula),
  which also covers why it is fatal for a bead that must be claimed
  directly.
- **Writes the *base* pool name, always.** Sling a pool **slot** —
  `gc sling gc-toolkit/gc-toolkit.polecat-2 tk-abcde` — and the stamped
  value is still the base `gc-toolkit/gc-toolkit.polecat`. A slot suffix
  is a load-balancing hint, not a hard pin, and it is collapsed on write
  by `agentutil.NormalizePoolRouteTarget` before the metadata is set
  (`rigs/gascity/cmd/gc/cmd_sling.go:766`; the default sling query
  applies the same `PoolName` collapse at
  `rigs/gascity/internal/config/workquery.go:532`, centralized by
  upstream #3963). This matters because the read side is exact-match:
  a suffixed value stamped by some *other* writer is structurally
  unclaimable — see
  ["Where they diverge"](#where-they-diverge-an-instance-suffixed-gcrouted_to).
- **CLI example:**
  ```bash
  gc sling gc-toolkit/gc-toolkit.polecat tk-abcde    # pool: gc.routed_to only
  gc sling gc-toolkit/gc-toolkit.mechanik tk-abcde   # singleton: gc.routed_to + assignee
  ```
- **Does NOT:** set `assignee` **for pool targets** — the reconciler
  picks an available worker from the pool by matching `gc.routed_to`.
  (Singleton targets are the exception just described: sling stamps
  the assignee so the named session's own hook surfaces the work.)
- **Cross-store boundary:** sling routes only *within a single bead
  store*. It refuses to route a bead that lives in one rig's `.beads`
  store to a target (pool or agent) in a *different* rig's store —
  failing with `gc sling: refusing cross-store route: …` — because Gas
  City keeps per-rig isolated Dolt stores. **`--force` does not override
  this:** that flag relaxes only the cross-*rig* name guard, not the
  cross-*store* reachability guard. To hand work to another rig's pool,
  re-file (create) the bead in the *destination* rig's store and sling
  it there; a cross-store sling left unguarded would silently wedge the
  target pool.

### Lane 2 — `bd update <bead> --assignee <named-session>`: direct named-session delivery

- **When to use:** the work must land on one specific named session
  (e.g., a polecat resuming its own bead, mechanik claiming its own
  wisp, mail addressed to a specific identity). When you write the
  named session's identity, you're saying "this work, this agent,
  no fan-out."
- **Sets:** `assignee=<named-session-identity>`. Leaves
  `gc.routed_to` empty.
- **CLI example:**
  ```bash
  bd update tk-abcde --assignee gc-toolkit/gc-toolkit.mechanik
  ```
- **Does NOT:** set `gc.routed_to`. The named session's hook query
  finds the work via assignee, not via routed metadata.

### Lane 3 — `gc sling <target> <bead> --reassign`: combined unassign + route

- **When to use:** park-then-handoff transitions — a human or named
  session was working on the bead, the work is now bouncing back to a
  pool. The single flag clears the prior assignee and routes in one
  step so the bead is never momentarily double-stamped. Added in
  PR #1841 (merged 2026-05-12) to make this transition atomic from
  the caller's perspective.
- **Sets:** `metadata.gc.routed_to=<target>` and clears the prior
  `assignee`. For a **pool target** the assignee stays empty after
  the clear. For a **singleton target** the Lane 1 singleton stamp
  still runs *after* the clear, so the net effect is "prior assignee
  cleared, `assignee=<target>` set."
- **CLI example:**
  ```bash
  gc sling gc-toolkit/gc-toolkit.polecat tk-abcde --reassign   # pool: clear, then gc.routed_to only
  ```
- **Does NOT:** re-assign to a *third party*. `--reassign` itself only
  ever clears the prior assignee — it never names a new one. For pool
  targets the result is *clear* + *route* with no assignee; for
  singleton targets the new `assignee=<target>` comes from the Lane 1
  singleton-stamp rule (the sling target itself), not from
  `--reassign`.

#### `--reassign` idempotency

`TestDoSling_Reassign_NoOpWhenAlreadyEmpty`
(`rigs/gascity/internal/sling/sling_test.go:3809`) pins the
contract: when `assignee` is already empty, `--reassign` is a no-op
on the assignee field — no error, no spurious update. Callers that
don't know the bead's prior state can pass `--reassign`
unconditionally and trust the routing call to be safe.

**One exception — a standalone formula launch.** The reassign reopen is
gated by `shouldReopenForReassign(opts) = opts.Reassign &&
!opts.IsFormula && !opts.DryRun`
(`rigs/gascity/internal/sling/sling_core.go:303`), so on a **standalone formula
launch** (`gc sling <target> <formula>`, Lane 4's second shape)
`--reassign` is a *guaranteed* no-op — not merely idempotent. That is
deliberate, and the guard's own comment
(`internal/sling/sling_core.go:296-302`) gives the reason: reassign
reopens `opts.BeadOrFormula`, which on a launch holds the *formula
name* rather than a bead ID, so honoring it would clear an unrelated
bead that happens to share the name, or fail the launch outright.
Passing `--reassign` unconditionally is still *safe* there; just don't
expect it to clear anything.

This exception does **not** extend to `--on`: an attach sets
`BeadOrFormula` to the real bead ID and leaves `IsFormula` false
(`internal/sling/sling.go:326`), so `--reassign` behaves exactly as it
does in Lane 3.

### Lane 4 — `gc sling <target> <bead> --on <formula>`: formula attach

- **When to use:** the bead needs a multi-step workflow (a *wisp*)
  driving it rather than a bare hand-off — the standard dispatch shape
  for `mol-polecat-work` and the doc-keeper audit formulas. `--on` and
  `--formula` are mutually exclusive
  (`rigs/gascity/cmd/gc/cmd_sling.go:158`); `--on` attaches a wisp to an **existing**
  bead, whereas `--formula` launches a formula that has no source bead.
- **Sets (classic, non-graph formula):** `metadata.molecule_id=<wisp-root>`
  on the **source bead**, then routes that **source bead** through
  exactly Lane 1's field contract (`gc.routed_to=<target>`, plus the
  singleton assignee stamp where the target is a named session). The
  **wisp root is deliberately left unrouted** so it is never
  independently claimed.
- **Sets (graph.v2 formula):** *neither routing field on the **source
  bead** — but the workflow root is routed.* The graph launch path
  returns before the Lane 1 routing call — the `isGraph` branch of
  `attachFormulaToBead` (`internal/sling/sling_core.go:487-533`) calls
  `doStartGraphWorkflow` at `:516` and returns at `:533` — so the source
  bead ends with **no `gc.routed_to` and no `assignee`**. The pour then
  mints a workflow root, promotes it to `in_progress` in the **graph
  store** (`PromoteWorkflowLaunchBead`, `sling_core.go:738`), and the
  graph decorator stamps `gc.routed_to=<target>` on that root — it is
  the record the claim path reads
  (`internal/graphroute/graphroute.go:562-570`, #2763 / ga-eld2x). Per-step routing is stamped on the compiled recipe's steps
  (`internal/dispatch/control.go:1110`) rather than on the work bead.
  The `workflow_id`/`gc.source_bead_id` pointer pair is written only
  when the pour carries a source bead (`sling_core.go:741-755`); the
  current convoy-first attach links through a synthetic input convoy
  instead. See ["A `blocks` dep between work beads does not hold a
  graph.v2 dispatch"](#a-blocks-dep-between-work-beads-does-not-hold-a-graphv2-dispatch)
  for the three records and how to walk between them.
- **CLI example:**
  ```bash
  gc sling gc-toolkit/gc-toolkit.polecat tk-abcde --on mol-polecat-work
  ```
- **Does NOT — *classic attach only*:** route the wisp root. This bullet
  qualifies the **"Sets (classic, non-graph formula)"** bullet above,
  **not** the graph.v2 one; under graph.v2 the workflow root *is*
  routed, as that bullet says. The scoping is
  structural rather than editorial: the attach path takes a graph.v2
  early return (`internal/sling/sling_core.go:487`, calling
  `doStartGraphWorkflow` at `:516` and returning at `:533`), so the whole
  legacy region that begins at `:535` — the `molecule_id` stamp (`:563`),
  the source-bead `finalize` (`:579`), and the unrouted wisp root — is
  reached only by a classic formula. (`:558`, inside that legacy region,
  is a second and narrower guard: it catches a wisp that materialized as
  a graph workflow even though the formula did not compile as one. It is
  not the branch that scopes this bullet.) For that classic path it is
  load-bearing rather than incidental: `TestOnFormulaAttachesAndRoutes`
  (`cmd/gc/cmd_sling_test.go:4178`), which attaches the *classic*
  `code-review` formula, asserts both halves — the source bead ends with
  `gc.routed_to=<target>`, and the wisp root ends with `gc.routed_to`
  **empty**. The source comment is blunt about why
  (`internal/sling/sling_core.go:569-578`): the source "is the claimable
  unit of work, while the wisp root is deliberately left unrouted…
  Do not 'fix' this to wispRootID — it would orphan the work"
  (gastownhall/gascity#2848).

  That comment carries an aside worth disarming, because read out of
  context it looks like it contradicts the graph.v2 bullet:
  `ApplyGraphRouting` "stamps no routing on an attached recipe
  (graphroute: sourceBeadID != "" early-return)". That early return is
  **also** classic-scoped — it sits inside the
  `!IsCompiledGraphWorkflow(recipe)` branch
  (`internal/graphroute/graphroute.go:625-628`). A *compiled* graph.v2
  recipe never reaches it; it falls through to
  `DecorateGraphWorkflowRecipe`, which stamps
  `gc.routed_to` on the root precisely so it is claimable
  (`graphroute.go:569`, whose own comment notes that without it a
  pool-routed root is "spawned-for by scale_check but never claimed by
  the worker, then idle-reaped" — #2763 / ga-eld2x).

#### Reading a graph.v2 attach correctly — the duplicate-wisp trap

A work bead dispatched under a **graph.v2** formula shows `gc.routed_to`
absent *and* `assignee` null **while it is fully dispatched**. Per the
paragraph above that is the designed shape, not a stranded bead — so
"no routing fields" is not evidence that dispatch failed. Re-slinging on
that misreading pours a **second** wisp against the same bead, and the
two workers converge on one shared worktree.

To check whether such a bead is really dispatched, resolve the root it
belongs to — not the bead's own routing fields. A classic attach names
its wisp root in `metadata.molecule_id`. A graph.v2 bead names nothing:
`metadata.workflow_id` is written only for the legacy source-workflow
shape and is empty under the current convoy-first attach, so an absent
`workflow_id` is not evidence either. Walk the `tracks` edge up to the
synthetic input convoy and find the root that names it in
`gc.input_convoy_id` — the lookup is spelled out in the containment
recipe under "A `blocks` dep between work beads does not hold a graph.v2
dispatch".

#### When a bare sling is silently Lane 4 — `default_sling_formula`

Lane 4 is not entered only by typing `--on`. A target may carry
`default_sling_formula`, and when it does, a bare
`gc sling <target> <bead>` — no `--formula`, no `--on` — is **not Lane 1
at all**. The formula branch is taken whenever

```go
opts.IsFormula || opts.OnFormula != "" ||
    (!opts.NoFormula && opts.Target.EffectiveDefaultSlingFormula() != "")
```

(`rigs/gascity/cmd/gc/cmd_sling.go:978`); the plain-routing predicate
`missingBeadForceApplies` (`:1183`) carries the same condition inverted.
From there the default-formula path and `--on` converge on one function,
`attachFormulaToBead`, whose contract comment states that
"graph-vs-legacy behavior is byte-identical across both entry points"
(`rigs/gascity/internal/sling/sling_core.go:479-497`). There is no
weaker "default formula" variant of Lane 4 — there is only Lane 4.

The field resolves permissively. `EffectiveDefaultSlingFormula`
(`rigs/gascity/internal/config/config.go:3581`) reads the agent's own
`default_sling_formula`, then the **inherited** value, then empty — so
an agent need not declare the field to be governed by it. This city sets
`default_sling_formula = "mol-polecat-work"` at **city scope** in
`city.toml`, which resolves onto every agent in `gc config show`. Here,
therefore, a bare `gc sling <target> <bead>` is **Lane 4 for every
target**. And `mol-polecat-work` is graph.v2 — it declares `[requires]
formula_compiler = ">=2.0.0"`, exactly the `graphV2Requirement` constant
that `UsesGraphCompiler` tests
(`rigs/gascity/internal/formula/requirements.go:14-16`, `:299`) — so
Lane 4's graph.v2 bullet applies in full: **neither routing field is
written on the bead.**

**Why this is fatal for a directly-claimed bead.** Most work beads do
not care: a graph.v2 wisp drives them, and the trap above is precisely
that their empty routing fields are correct. But a bead whose own
`gc.routed_to` *is* the offer predicate — a hand-filed codex review or
re-gate bead, which no wisp drives and which the pool must claim
directly — is destroyed by this, and silently. The sling reports
success:

```json
{"schema_version":"1","success":true,"routed":true,"workflow_id":"..."}
```

`routed: true` is not a claim that a routing field was written. It is
computed as `result.Routed > 0 || (!result.Idempotent &&
result.BeadID != "" && !result.DryRun)`
(`rigs/gascity/cmd/gc/cmd_sling.go:1138`), so it reports true on the
graph.v2 path that wrote no routing field at all. Exit code is 0,
nothing warns, and the bead ends with `gc.routed_to` empty — matching no
offer predicate, since [the read side](#the-read-side-the-claim-predicate)
is exact-match on that key. The bead sits forever.

**The rule: stamp it, don't sling it.** A bead that must be offered
directly gets `gc.routed_to` written directly —
`gc bd update <bead> --set-metadata gc.routed_to=<pool>` — and is never
slung. The generated path does exactly that and calls `gc sling` nowhere:
`check-set-heal.sh` stamps the review bead's other fields first and
writes `gc.routed_to` last, in its own call, for the reason its comment
gives — "`gc.routed_to` is what makes the bead claimable"
(`assets/scripts/check-set-heal.sh:355-357`, stamp at `:393`). Where a
sling is wanted anyway, `--no-formula` ("suppress default formula (route
raw bead)", `rigs/gascity/cmd/gc/cmd_sling.go:153`; mutually exclusive
with `--formula` and `--on` at `:159-160`) restores Lane 1's contract on
a target that carries a default.

**Read this together with the duplicate-wisp trap.** That subsection
teaches that absent routing fields are the *designed* shape for a
graph.v2 work bead. This is its other half: the same absence on a bead
meant to be claimed **directly** is always a bug. The two are told apart
by the same field — `metadata.workflow_id` / `metadata.molecule_id`. A
directly-offered bead should carry neither; if one is there, the bead
was slung when it should have been stamped.

#### Adjacent — standalone formula launch (`gc sling <target> <formula>`)

The other half of the `IsFormula` split, and the shape most often
confused with `--on`. Here there is no source bead, so the **wisp root
itself is the routed bead** — `slingFormula` finalizes on
`mResult.RootID` (`rigs/gascity/internal/sling/sling_core.go:373`), giving the root
`gc.routed_to=<target>` under Lane 1's contract. A *classic* wisp root
carrying `gc.routed_to`, with a title matching the formula name, is
therefore normal for a launch and wrong for an attach — but that tell
does not extend to graph.v2, whose root is routed either way. Its
graph.v2 variant behaves like Lane 4's: the sling path's own routing
call is skipped (`internal/sling/sling_core.go:363-368`) and the graph
decorator stamps `gc.routed_to` on the root instead
(`internal/graphroute/graphroute.go:562-570`).

#### Why assignee residue silently strands a routed bead

Pool demand does not count "routed" — it counts **routed *and*
unassigned**. The demand probe is
`bd ready --metadata-field "gc.routed_to=$target" --unassigned
--exclude-type=epic` (`rigs/gascity/internal/config/workquery.go:41-43`), and the jq
form applies the same `assignee == ""` filter
(`workquery.go:586`). So a bead that is correctly routed but still
carries a stale `assignee` is **invisible to `scale_check`**, and a
scale-from-zero pool never wakes for it. Nothing errors; the work just
sits. This is the field-contract reason Lane 3 exists — clearing the
assignee is not cosmetic tidying, it is what makes the bead countable
as demand.

### Adjacent — targetless sling resolution (`default_sling_target` / `default_sling_targets`)

All four lanes above name an explicit target. `gc sling <bead>` with
**no target argument** is also valid: `gc` resolves the target from the
bead's rig config and dispatches to it. Read the whole subsection as
**target selection first, lane decision second** — everything here
chooses *which target*, and that target then selects the lane exactly as
it would had you typed it. Two config fields feed the selection, and the
plural takes precedence:

- **`default_sling_targets`** (plural, `[]string`) — if non-empty, `gc`
  picks **one entry at uniform random** per dispatch and dispatches to
  that single target (detail below).
- **`default_sling_target`** (singular, string) — used only when
  `default_sling_targets` is empty.

The split is structural, not editorial. `inferSling1ArgTarget` returns a
target **string** (`rigs/gascity/cmd/gc/cmd_sling.go:244-252`, read at
the fork pin `390624b0e`); the common path then resolves it to an agent
(`:433`) and stores it as
`opts.Target` (`:463-464`) — the same field an explicit target fills, and
every lane branch is taken downstream of that. So the field contract of a
targetless sling is whichever lane the *resolved target* implies:

- **Resolved target carries no `default_sling_formula`** → Lane 1, whose
  contract applies unchanged: a **pool target** gets
  `metadata.gc.routed_to=<target>` and no `assignee`; a **singleton
  target** additionally gets `assignee=<target>` from the same
  singleton-stamp rule.
- **Resolved target carries `default_sling_formula`** — its own or one
  inherited from city scope → **Lane 4**, via the same formula-branch
  predicate an explicit target hits (`:978`); under a graph.v2 default
  formula that writes **neither routing field on the bead**.
  `--no-formula` suppresses the default and restores the Lane 1 shape
  above.

Targetless resolution therefore introduces no field behavior of its own
— it inherits the resolved target's. The two `default_sling_target*`
fields and `default_sling_formula` are adjacent in name and disjoint in
job: the former choose *which target*, the latter — read off **that
target**, never off this resolution step — chooses *which lane*. For why
the Lane 4 outcome is fatal for a bead that must be claimed directly, see
["When a bare sling is silently Lane 4"](#when-a-bare-sling-is-silently-lane-4--default_sling_formula).

The typical configuration points a rig's `default_sling_target` at that
rig's own polecat pool in `city.toml` — e.g. `default_sling_target =
"gc-toolkit/gc-toolkit.polecat"`, the shape the `binding_prefix`
defaults in gc-toolkit's doc-keeper audit formulas assume of every
importing rig. A bare `gc sling <bead>` then reaches that pool — but
*how* it arrives still depends on the pool's own effective
`default_sling_formula`. With that field unset, the bead itself lands on
the pool via `gc.routed_to` and the pool's demand-driven scale_check fans
out an ephemeral polecat to pick it up. With it set — as it is at city
scope in this city — the dispatch is a Lane 4 attach instead: under a
graph.v2 formula the bead carries no routing field and it is the *wisp*
that the pool sees. Neither shape is safe to assume; read the resolved
value (`gc config show`) for the target before predicting which you get.

- **CLI example:**
  ```bash
  gc sling tk-abcde                 # no target → resolves default_sling_target(s); lane per that target
  gc sling --no-formula tk-abcde    # same target, forced onto Lane 1 (gc.routed_to on the bead itself)
  ```

#### `default_sling_targets` (plural) — random multi-target dispatch

`default_sling_targets` was added by upstream PR #3670 (`feat: add
default_sling_targets for multi-target random dispatch`,
gastownhall/gascity, merged 2026-07-03); the field is
`default_sling_targets = ["rig/a", "rig/b"]` (`[]string`,
`rigs/gascity/internal/config/config.go:645`).

Behavior, read from the resolver
(`rigs/gascity/cmd/gc/cmd_sling.go:291`, verified at gascity/main
`4ff645484`):

- **Precedence over the singular.** The resolver tests
  `default_sling_targets` **first** and falls back to the singular
  `default_sling_target` only when the plural is empty — so when both are
  set, **the plural wins**.
- **Uniform-random pick.** When the plural is non-empty, `gc` selects
  **one** entry uniformly at random per dispatch
  (`rand.Intn(len(rig.DefaultSlingTargets))`) and dispatches to that
  single target; each entry is resolved exactly as a singular
  `default_sling_target` would be — including its lane, so a list whose
  entries differ in effective `default_sling_formula` is a list whose
  dispatch *shape* varies at random, not just its destination.
- **Empty-entry guard.** An empty string entry in the list is a hard
  error (`gc sling: rig %q has an empty entry in default_sling_targets`).

**When to reach for the plural.** A polecat pool already provides
demand-driven elasticity behind a *single* target — scale_check fans
out ephemeral polecats to queue depth — so the plural's static,
client-side random fan-out adds nothing for capacity behind one pool.
It earns its place only when dispatches should be spread across
*distinct named targets* (separate pools, or a mix of pools and named
sessions). Remember the precedence rule: a non-empty plural silently
supersedes a configured singular.

### Adjacent — `gc.run_target` (deprecated wire field; compile-time authoring hint)

`gc.run_target` still appears as metadata on individual template
steps inside graph.v2 formula files — e.g. `mol-review-quorum.toml`
sets it on each review lane and the synthesis step — so you *will*
see it there. But it is **not** a live, parallel routing field, and
it does not route anything at runtime. Upstream PR #2779
(`ga-eld2x`, merged 2026-06-01) made `gc.routed_to` the sole
*persisted* routing key that every runtime demand / claim / scale
reader consults, and demoted `gc.run_target` to a compile-time
recipe-authoring hint: it declares a step's intended config/pool
target for the steps where `assignee` can't be used (check and
control-dispatch steps), and the stampers resolve it **into**
`gc.routed_to` before the bead is persisted. So `gc.run_target` is
an authoring-time precursor to `gc.routed_to`, not a sibling routing
key alongside it — don't conflate the two when you see
`gc.run_target` in formula files. A bare `gc.run_target` left on a
stored bead is inert authoring provenance; `gc doctor --fix`
backfills `gc.routed_to` for any pre-migration workflow root that
still carries only the old field.

## The read side: the claim predicate

The four lanes above are the **write** side — which field (if any) each
delivery path sets. This is the **read** side: the predicate that decides
which beads a worker is actually offered. It belongs in this doc because the
routing fields mean only what this predicate makes them mean.

`gc hook` "finds routed work using the agent's `work_query` config"
(`gc hook --help`). The built-in query runs in tiers, and the tiers map
onto the lanes:

- **Tier 1 — in-progress recovery** (the read side of **Lane 2**).
  `bd list --status=in_progress --assignee=<candidate>`. The
  crash-recovery tier: it resumes work the session had already claimed and
  was mid-flight on when it died. It is deliberately **not** a `bd ready`
  query — `bd ready` excludes `in_progress` (see below), so in-flight work
  is invisible to it and has to be recovered with a plain `bd list`.
- **Tier 2 — ready assigned work** (also the read side of **Lane 2**).
  `bd ready --assignee=<candidate> --exclude-type=epic`. Pre-assigned work
  (`bd update --assignee <me>`) that is ready but not yet started.
- **Tier 3 — routed pool** (the read side of **Lanes 1 and 3**, and of
  **Lane 4's classic formula shapes** — the `--on` attach routes the
  *source* bead and the standalone launch routes the *wisp root*, both
  through Lane 1's `gc.routed_to` contract, so each is claimed here like
  any other routed bead).
  `bd ready --metadata-field "gc.routed_to=$target" --unassigned
  --exclude-type=epic`. A pool worker finds work here, and only here. The
  **graph.v2** variants are the exception, but a narrower one than "nothing
  is routed" — and the difference is best read as *which term of the
  filter* each record fails. The **work bead** fails the **routing** term
  outright: the pour leaves it unrouted, so no state it could ever be in
  makes it match. The **workflow root** is the opposite case — it carries
  `gc.routed_to=<target>` (`internal/graphroute/graphroute.go:562-570`),
  so it satisfies the routing term. It is the **routed record** of the
  dispatch — the record delivery is addressed to, and the one containment
  has to de-route. What it is *not* is the record a pool worker takes.
  Satisfying that one term is not the same as being returned by the
  query: Tier 3 is a `bd ready` read, so it applies every other term in
  the table below too, and under a compiled graph.v2 workflow the root
  fails two of them from the moment the pour returns. The pour promotes
  it to `in_progress` in the graph store (`PromoteWorkflowLaunchBead`,
  `internal/sling/sling_core.go:738`, whose post-pour status the pour's
  own test asserts at `cmd/gc/cmd_sling_test.go:4494`), a status `bd
  ready` excludes — and the compiler has already given it a `blocks`
  dependency **on** its own `workflow-finalize` control bead
  (`addWorkflowRootDeps`, `internal/formula/compile.go:672-699`: the root
  is the dependent, so it stays blocked until finalize closes and
  therefore completes last). Either one alone is disqualifying.

  What wakes the pool, and what the pool claims, is the **step** beads.
  graph.v2 skips the #1039 coercion to the `Ready()`-excluded `step`
  type, so compiled steps stay Ready-visible and independently routable
  (`internal/molecule/graph_apply.go:206-212`), and they carry their own
  routes — live, or withheld in `gc.deferred_routed_to` until activation
  (see "the duplicate-wisp trap" above). That is the same mechanism
  [gascity-packs.md](gascity-packs.md) describes from the
  formula-authoring side: a v2 workflow "materializes independently
  routable, Ready-visible *step* beads that wake the pool without vapor;
  the workflow root itself depends on `workflow-finalize` and stays
  blocked — **not** Ready-visible — while the workflow runs." The two
  docs state one model, not two. So read "the root is routed" as a claim
  about the **write** side alone; "a Tier 3 read returns the root right
  now" is a separate question about status and blockers, and for a
  compiled graph.v2 workflow the answer is no. (The one shape where the
  root gets no such blocker is the self-contradictory root-only-under-v2
  recipe gascity-packs.md §3 covers: it materializes no
  `workflow-finalize` bead for `addWorkflowRootDeps` to point at — the
  same missing piece that leaves its root unable to self-close through
  the engine.)

Tiers 1 and 2 both run for each of `$GC_SESSION_ID`, `$GC_SESSION_NAME`,
`$GC_ALIAS` in order, first non-empty result winning, and both match on
`assignee` — never on `gc.routed_to`. A named session finds its own work
through them; the pool finds its work only through Tier 3.

`bd ready` supplies the rest: it shows "open issues with no active
blockers" and "excludes in_progress, blocked, deferred, and hooked
issues" (`gc bd ready --help`). Spelled out, a bead is offered to a
**pool** worker when **all** of the following hold:

| Term | Requirement |
| --- | --- |
| status | `open` — `in_progress`, `blocked`, `deferred`, `hooked` are excluded |
| blockers | no active blocker (dependency-aware `GetReadyWork` semantics) |
| `gc.routed_to` | equals the pool target — **exact string match** on this offer side (the demand side normalizes an instance suffix; see below) |
| `assignee` | empty (`--unassigned`) |
| type | not `epic` (`--exclude-type=epic`) |

The `blockers` row carries a scope limit worth reading before you rely
on it. It is dependency-aware about **the bead the predicate reads** —
which, under a formula dispatch, is not the bead a human thinks of as
the work. "A `blocks` dep between work beads does not hold a graph.v2
dispatch" below covers that case.

### Offer and demand are one predicate, read two ways — for a base-name route

The same predicate backs both halves of the pool loop. They differ in
the *shape* of the answer, not in the terms:

- **Offer** (`work_query`) returns the matching beads as a sorted,
  limited list — what `gc hook` hands a live worker.
- **Demand** (`scale_check`) runs the identical filter at `--limit 0`
  and counts the rows — what the pool reconciler scales on.

Where both halves are the **shell probe**, that symmetry is structural
and deliberately enforced: one helper, `bdReadyPoolDemandShell`
(`rigs/gascity/internal/config/workquery.go:41`), builds the predicate
for both `EffectiveWorkQuery`'s Tier 3 (`workquery.go:417`) and
`EffectivePoolDemandQuery`'s count form (`workquery.go:566`), and both
resolve `$target` through the same `poolDemandTarget()`
(`workquery.go:157`) — the agent's `PoolName` when set, else its
`QualifiedName()`. The helper's own comment says diverging the two
"re-introduces the protocol-mismatch class."

So for the route values the delivery lanes actually write — always a
**base pool template name**, because sling's built-in routing paths
collapse a slot suffix on write (Lane 1) — "is this bead claimable?"
and "does this bead create pool demand?" have the same answer, and you
should not model them as two predicates that happen to agree.
[work-bead-state-machine.md](work-bead-state-machine.md) relies on
exactly this when it detaches a gating bead from both queues in one
move (`assignee=""` **and** `gc.routed_to=""`) — and that move stays
safe unconditionally, because an empty route matches nothing on either
side.

**The symmetry is a property of the value, not a law of the system.**
It breaks for an instance-suffixed route, which the next section covers.
Read it before you conclude that anything counted as demand is therefore
claimable.

#### Where they diverge: an instance-suffixed `gc.routed_to`

A route stamped with a live pool **slot** suffix — `<rig>/<pool>-1`
rather than `<rig>/<pool>` — is **never offered**. Whether it is still
counted as *demand* depends on the pool's `scale_check` configuration —
and on the common ones it is, so the pool scales for a bead no worker
can claim.

The offer side has no normalization anywhere along its path:

- Tier 3's shell probe is the exact-string
  `--metadata-field "gc.routed_to=$target"` with `$target` resolved to
  the base template (`workquery.go:41`, `:157`), so a suffixed bead is
  never even returned as a candidate.
- The Go-side claim gate compares raw strings —
  `routedTo == target` in `hookClaimMatchesRoute`
  (`rigs/gascity/cmd/gc/cmd_hook_claim.go:1205`) — against route targets
  that are all base names (`cmd/gc/cmd_hook.go:468`, whose primary comes
  from `agentutil.RoutedToIdentity` at `cmd_hook.go:685`).

The demand side does normalize, but only on the controller's in-process
probe. For a pool that configures **no custom `scale_check`**
(gated on `!hasCustomScaleCheck`, `cmd/gc/build_desired_state.go:446`,
`:491`, `:567`), the controller does not run the shell probe at all — it
counts demand in-process in `defaultScaleCheckCountsAndDemand`
(`build_desired_state.go:1474`, invoked at `:735`), matching each ready
bead through `controllerDemandRouteTarget` (`:1718`), which passes every
routed-to candidate through `agentutil.NormalizePoolRouteTarget`
(`rigs/gascity/internal/agentutil/resolve.go:228`) before the
template-membership check. That collapses `<base>-N` to `<base>` for a
configured multi-session agent when `N` is a valid slot (≥1, and within
`max_active_sessions` when bounded); every other value passes through
unchanged. Upstream #4596 added this read-side normalization
deliberately, and its comment says so outright: such a candidate,
"whether written by `gc sling`'s own write-side normalization or by any
other writer, such as a direct `bd update --set-metadata` — still counts
as demand for the base template."

A custom `scale_check` does **not** displace that in-process probe
entirely. While such a pool is **cold** — `isCold`, meaning zero running
sessions *and* `min_active_sessions == 0` (`build_desired_state.go:476`)
— the controller appends the same default probe target for every active
store and marks the template in `coldWakeTemplates` (`:633-637`), so the
normalizing in-process count runs for it too. That contribution is then
clamped to 1 in the merge (`:757-759`) and folded in as a *maximum*
against the custom check's own count (`:766-768`). The code comment at
`:626-632` states the intent directly: the cold probe is a wake assist
that can only wake a sleeping pool, never override the authoritative
custom count while the pool is awake. (It is also gated on a real store
and on the pool not being a store-scoped control dispatcher.)

So there are three configurations, and none of them yields a claim:

- **Default `scale_check` (the normalizing path).** The bead counts as
  demand for the base template, so pool desired-size grows and a
  scale-from-zero pool wakes. The woken worker's Tier 3 query returns
  nothing — its probe is exact-match — so it claims nothing and drains.
  The bead is unchanged by the failed cycle: still `open`, unassigned,
  still routed, so it counts as demand again on the next reconcile. The
  pool wakes for work it structurally cannot be handed.
- **Custom `scale_check`, pool cold.** The cold-wake default probe
  normalizes the route, so demand is `max(<custom count>, 1)` and the
  pool wakes — one slot, however many such beads are queued. The woken
  worker still cannot claim the bead, for the same exact-match reason.
  Once it drains the pool is cold again and the probe re-fires: the same
  wake-for-unclaimable-work loop as above, throttled to one slot per
  cycle.
- **Custom `scale_check`, pool warm or `min_active_sessions > 0`.** The
  pool is never `isCold`, so no default probe runs for it and the custom
  check is the only counter. That check is caller-owned shell; unless it
  normalizes the suffix itself, the bead is invisible to *both* halves —
  symmetric, but silently dropped: nothing scales and nothing errors.

**Who writes a suffixed route.** Not `gc sling`: both of its write paths
collapse to the base pool identity before stamping, but through two
*different* helpers taking two different inputs, and the distinction
matters when tracing a stray route back to its writer.

- Given an explicit **target string**, the built-in routing path calls
  `agentutil.NormalizePoolRouteTarget` (`cmd/gc/cmd_sling.go:766`),
  which strips a valid `-N` slot suffix off a caller-supplied
  `<rig>/<pool>-2` (`resolve.go:228`).
- Given an **agent**, the route collapses to that agent's `PoolName`,
  which on a pool-instance copy is its base template's qualified name.
  #3963 centralized that rule as `agentutil.RoutedToIdentity`
  (`resolve.go:204`); the default sling query inlines it rather than
  calling it (`workquery.go:532-536`), because `internal/config` cannot
  import `agentutil` — `agentutil` already imports `config`, and its
  package comment says it was split out for exactly that reason.

A suffixed value reaches a bead only from some *other* writer — a direct
`bd update --set-metadata gc.routed_to=<pool>-1`, or a graph/formula
path that stamps a resolved instance name.

**How to unstick a bead in this state.** Rewrite the route to the base
pool name — `gc sling --no-formula <rig>/<pool> <bead>` (Lane 1 restamps
it, and its collapse is idempotent on a value that is already base; the
`--no-formula` is what keeps the repair *on* Lane 1 when the pool carries
a `default_sling_formula`, since a Lane 4 attach would rewrite no route
at all) or a direct
`bd update <bead> --set-metadata gc.routed_to=<rig>/<pool>`. Do not wait
for the pool to catch up; the offer side will not. This is the same
repair upstream already applies to the
bound→unbound migration, whose in-place route rewrite
(`canonicalizeLegacyBoundUnassignedRoutedWork`,
`build_desired_state.go:4168`) exists precisely because "the canonical
pool-demand probe …, the worker `work_query` …, and the claim predicate
… all match `gc.routed_to` against the canonical target by raw string."
The durable fix is at the write site — as
`NormalizePoolRouteTarget`'s own comment puts it, normalizing "at the
routing write site keeps slot-suffixed slings reachable by any slot."

### Metadata is not enforcement

Exactly one metadata key participates in the predicate: `gc.routed_to`,
matched via `--metadata-field`. No other key is read, and nothing scans
for a key whose *name* merely sounds like a hold.

The consequence is the non-obvious part. A bespoke park flag —
`rebase_hold=true`, `hold_reason="waiting on the rebase"`, and friends —
is **documentation, not enforcement**. A bead carrying one is still
`open`, still routed, still unassigned; it is therefore still offered,
and a hooked worker can still claim it. The metadata *explains* a hold.
It never *imposes* one.

The failure mode is silent and asymmetric, which is why it is worth
stating here rather than leaving implicit: stamping the flag produces no
error, so the agent that stamped it believes the bead is parked. The
only party who learns otherwise is the next worker — by claiming the
bead and starting the very work the flag was meant to prevent.

### A `blocks` dep between work beads does not hold a graph.v2 dispatch

A dependency edge is the other thing that looks like enforcement and
is not — not because the read side ignores dependencies, but because
under a formula dispatch it is reading a **different bead**.

Which bead the predicate reads depends on the lane:

- **Lanes 1–3, and Lane 4's classic attach.** The routed claimable unit
  *is* the work bead, so its blockers do gate it: `bd ready` will not
  offer a bead with an open `blocks` dep, and the demand probe will not
  count it. The `blockers` row means exactly what it says. For a classic
  attached wisp this is explicit: the source bead carries `gc.routed_to`
  *and* `molecule_id` and "is the claimable unit of work, while the wisp
  root is deliberately left unrouted"
  (`internal/sling/sling_core.go:569-578`, whose comment ends "Do not
  'fix' this to wispRootID — it would orphan the work").
- **graph.v2 (Lane 4's graph variant and the graph standalone launch).**
  Here the work bead is not routed at all: the **workflow root** is the
  routed record of the dispatch, and its Ready-visible **step** beads are
  what a pool worker actually claims (Tier 3 above). Three records are
  easy to conflate, and they carry different fields:

  | Record | Routed? | How it links |
  |---|---|---|
  | **source / work bead** — the bead you slung `--on` | **No.** The pour stamps no `gc.routed_to` on it | membership in a synthetic **input convoy** that `tracks` it; the `workflow_id` back-pointer is written only for the legacy source-workflow shape (`internal/sling/sling_core.go:741-755`) |
  | **workflow root** — minted by the pour | **Yes** — `gc.routed_to=<pool>` | `gc.input_convoy_id=<input convoy>` (`internal/sling/sling.go:1520-1534`); the root-only `gc.source_bead_id` back-pointer likewise exists only in the legacy shape (`internal/graphroute/graphroute.go:576-577`) |
  | **compiled step and control beads** | Sometimes — a control bead such as `workflow-finalize` carries its own `gc.routed_to`; a step's may instead be withheld in `gc.deferred_routed_to` | `gc.root_bead_id=<root>` (`internal/molecule/graph_apply.go:219-223`) plus one upward `tracks` edge to the root (`:288-313`) |

  The root being routed is not incidental, and it is the record most
  often misremembered as unrouted: #2763 / ga-eld2x made the root
  persist `gc.routed_to` — "the sole canonical delivery key the worker
  claim path reads" — precisely so that a pool-routed root is claimable
  rather than spawned-for and then idle-reaped
  (`internal/graphroute/graphroute.go:562-570`, pinned by
  `TestDecorateGraphWorkflowRecipe_RootStampsRoutedToForClaim`,
  `internal/graphroute/graphroute_test.go:412`, and by
  `cmd/gc/cmd_sling_test.go:4497-4501`). Its type is preserved rather
  than coerced to the `Ready()`-excluded `molecule` type whenever the
  root is `gc.kind=workflow` or `wisp`
  (`internal/molecule/graph_apply.go:166-170`, via
  `preserveExecutableRootType`, `internal/molecule/molecule.go:1333-1340`),
  so the `Ready()` *type* filter does not exclude it — its `in_progress`
  status and its own `blocks` edge to `workflow-finalize` still do, which
  is why a routed root is not something you will find sitting in a plain
  `bd ready` listing (see Tier 3 above). Its steps stay claimable for the
  same reason the root's type survives: graph.v2 skips the #1039 coercion
  to the excluded `step` type (`graph_apply.go:206-212`).

  What none of the three carries is an edge to the work bead's
  blockers. The root is *freshly minted*, so the `blocks` deps it has
  are the formula's own: the compiler emits root `--blocks-->`
  `workflow-finalize` so the root completes last (`addWorkflowRootDeps`,
  `internal/formula/compile.go:672-699`). None of them reaches the work
  bead, and a step's only upward edge is `tracks`, to that root. The
  links that *do* reach the work bead — `gc.input_convoy_id`, and in the
  legacy shape `gc.source_bead_id` / `workflow_id` — are metadata
  pointers, and no readiness query follows a metadata pointer. A
  `blocks` edge added between two *work* beads is therefore never on a
  path the read side walks.

Two independent reasons it cannot gate, either of which is sufficient:

- **`tracks` is not a readiness-blocking type.** The blocking set is
  exactly `blocks`, `waits-for`, `conditional-blocks`
  (`readyBlockingDependencyTypes`, `internal/beads/beads.go:433`, read
  through `IsReadyBlockingDependencyType` at `:441`); `parent-child` and
  `tracks` never block. The step→root edge is that way *on purpose* —
  the comment introducing it asks for "a non-blocking dependency" so a
  cascade delete still discovers the workflow "without making the
  workflow root a readiness blocker." The hook's in-progress tier
  applies the same type set to a candidate's own dependency rows
  (`internal/config/workquery.go:199-201`), and its rationale is blunt
  about the stakes: treating those edges as blockers "would strand every
  molecule step, since each carries a tracks/parent-child edge to its
  root" (pinned by `TestInProgressTierIgnoresNonBlockingDependencyTypes`,
  `internal/config/workquery_inprogress_blocked_test.go:117`).
- **Even a blocking type would be on the wrong bead.** Neither record
  the read side can return carries the work bead's deps. The routed
  record is the workflow root, whose dependency rows are the formula's
  own (root `--blocks-->` `workflow-finalize`), never the work bead's;
  the step beads the pool claims carry the formula's `blocks` edges to
  their siblings and a `tracks` edge up to that root, never to the work
  bead. A step's edges reach that root, not the work bead. The work
  bead is reachable only through metadata pointers — the root's
  `gc.input_convoy_id` to the convoy that tracks it, or in the legacy
  source-workflow shape `gc.source_bead_id` and the bead's own
  `workflow_id` — and no readiness query walks metadata pointers.

`tracks` records membership and ownership; it does not gate. That is the
same distinction that governs convoy membership edges, and it is why
"the dep graph says these are ordered" and "the delivery path will honor
that order" are separate claims.

**Nor does the write side hold it.** Nothing on the sling path checks
whether a bead is blocked before pouring. Sling *does* walk the dep
graph — but only to reject a cycle (`internal/sling/sling_core.go:114`
→ `DetectCycle`), never to look for an open blocker; no non-test file in
`internal/sling/` reads blocker state at all (the word "blocked" occurs
there only inside `*_test.go` fixtures), and that word's only occurrence
in `cmd/gc/cmd_sling.go` is the cross-rig routing guard (`:2115`). Sling a
blocked bead and the molecule pours immediately, routes the workflow
root, and a worker claims it.

**Observed** (2026-08-02, signal-loom). Four test-coverage beads were
filed with two `blocks` deps between them. `gc bd blocked` listed the
two blocked beads correctly — the dep graph itself was right. All four
were then slung; all four molecules poured and were claimed within about
two minutes, the two blocked ones included.

**What is test-pinned, and what is not.** The rule above is assembled
from constituent upstream tests plus that one live observation. No
upstream test exercises the whole path end to end, and the difference
matters if you are deciding how much weight this section carries:

- **Pinned upstream.** The blocking-type set
  (`readyBlockingDependencyTypes`, `internal/beads/beads.go:433`) and the
  hook's use of it
  (`TestInProgressTierIgnoresNonBlockingDependencyTypes`,
  `internal/config/workquery_inprogress_blocked_test.go:117`); the root's
  routing stamp
  (`TestDecorateGraphWorkflowRecipe_RootStampsRoutedToForClaim`,
  `internal/graphroute/graphroute_test.go:412`); and the pour's own
  shape — input-convoy two-key root lookup, root `in_progress`, root
  `gc.routed_to` (`cmd/gc/cmd_sling_test.go:4481-4501`).
- **Not pinned.** Nothing under `internal/sling/` or in
  `cmd/gc/cmd_sling_test.go` slings a *blocked* work bead and asserts
  that the pour and the claim happen anyway; the only `blocks` deps in
  sling's own tests are cycle-detection fixtures
  (`internal/sling/cycle_test.go:23`). The end-to-end step rests on the
  code path — sling reads no blocker state, as above — plus the single
  observation.
- **What would settle it.** An upstream test that files a `blocks` dep
  between two work beads, slings the blocked one, and asserts the
  workflow root is created and routed and its steps come back Ready.
  Until that exists, treat this as an operational rule backed by a
  verified mechanism and one reproduction, not as pinned behavior: the
  mechanism is safe to reason from, but a future upstream change could
  break it without turning any test red.

The operational contract that follows:

- **Sling only beads `gc bd blocked` does not list.** Sequencing lives
  in the *order you dispatch*, not in the dep graph. Filing the deps and
  then slinging everything at once dispatches the whole set.
- **If a blocked bead was already slung, you are racing the pool.**
  Containment means clearing delivery on *every* record the pour created
  — every workflow root and all of their descendants — not just the one
  you can see.

  Every delivery channel comes as a **live/deferred pair**: the live key
  is what the offer reads now, and its `gc.deferred_*` twin is *withheld*
  delivery that activation later promotes **into** the live key
  (`internal/molecule/graph_apply.go:320-329` defers;
  `cmd/gc/convergence_store.go:213-240` and
  `internal/molecule/molecule.go:1399-1406` promote). Clear only the live
  key and the record re-delivers itself the moment it activates. Three
  channels, five keys to clear:

  | Channel | Live key | Deferred twin |
  |---|---|---|
  | Pool routing — the minimum pair, on every poured record | `gc.routed_to` | `gc.deferred_routed_to` |
  | Execution routing | `gc.execution_routed_to` | `gc.deferred_execution_routed_to` |
  | Named-session assignee | `assignee` (a column, not metadata) | `gc.deferred_assignee` |

  Only the pool-routing pair is stamped on every record; the other two
  appear just on nodes the recipe routes for execution or pins to a named
  session (`deferGraphNodeRouting`, `graph_apply.go:320-329`, defers an
  assignee only when the node has one). Clear all five regardless — a key
  that was never set costs one no-op write, whereas guessing which nodes
  are singletons costs a containment failure.

  The live `assignee` is the one entry the script deliberately **reports
  instead of clearing**: once it is stamped, delivery has already
  happened and clearing it recalls nothing (see "De-routing does not
  recall work a worker already holds" below). Its deferred twin is the
  opposite case — `gc.deferred_assignee` has *not* delivered yet, so
  clearing it genuinely holds the record. Leave it behind and activation
  promotes it straight into `assignee`, handing the work to a named
  session after you believed the record was contained.

  Run the block below as a script rather than pasting it into a live
  shell — the guards `exit` instead of continuing on a root that never
  resolved.

  ```bash
  # 0. "Live" is every NON-CLOSED status, not just open/in_progress. This
  #    recipe exists precisely because you are racing an active dispatch,
  #    so a record is in scope unless it is terminal. `hooked` and
  #    `blocked` are bd's "wip" category and `pinned` its "frozen" one
  #    (internal/beads/native_dolt_store.go:116-121), and a graph node in
  #    `hooked` is exactly as live as one in `in_progress`
  #    (cmd/gc/cmd_graph.go:482). Filtering to `open,in_progress` silently
  #    drops a hooked root or step from BOTH the clear and the verify —
  #    and a verify that never looked at a record reports it as contained.
  LIVE=open,in_progress,hooked,blocked,deferred,pinned

  # 1. Resolve the workflow root(s) the pour created for this bead. Under
  #    the current convoy-first attach there is no pointer *pair* to
  #    follow: the bead carries no workflow_id and the root no
  #    gc.source_bead_id (both are written only when the pour carries a
  #    source bead — internal/sling/sling_core.go:741-755). The durable
  #    link is the synthetic one-item input convoy that `tracks` the
  #    bead (internal/graphv2/invocation.go:415-446, whose TrackItem
  #    adds convoy --tracks--> bead at internal/convoy/membership.go:36),
  #    named on the root as gc.input_convoy_id. The root lookup below is
  #    the same two-key match the pour's own test asserts
  #    (cmd/gc/cmd_sling_test.go:4481).
  #
  #    Collect EVERY tracking convoy, never just the first. The pour mints
  #    a fresh one unconditionally — CreateSingleItemInputConvoy calls
  #    store.Create with no reuse lookup (invocation.go:428) and closes it
  #    only on its own failure paths (sling_core.go:494, :531) — so a
  #    re-poured bead ends up tracked by one convoy per pour, each naming a
  #    different root. Selecting `.[0]` is the same multi-root collapse the
  #    note below warns about, one step earlier and harder to see: a root
  #    dropped here never reaches the clear in step 2 OR the verify in
  #    step 3, so the verify prints nothing and reads as contained.
  #
  #    The gc.kind=workflow term is exhaustive for this lookup, not a
  #    narrowing of it: a gc.kind=wisp root can never carry
  #    gc.input_convoy_id, so adding it here would match nothing. The
  #    compiler sets the two kinds on mutually exclusive branches —
  #    workflow when the recipe is graph.v2, wisp only when it is
  #    root-only and NOT graph.v2 (internal/formula/compile.go:351-356) —
  #    and the sole writer of gc.input_convoy_id on a poured root,
  #    stampGraphV2RootMetadata, runs only on the graph.v2 branch
  #    (internal/sling/sling.go:1318-1322, defined at :1520-1534).
  #    Root-only wisps are contained elsewhere, by shape:
  #      * ATTACHED wisp (`gc sling --on <bead>`): the WORK BEAD is the
  #        routed claimable unit and the wisp root is deliberately left
  #        unrouted (internal/sling/sling_core.go:569-578); an attached
  #        root-only wisp is additionally privatized out of Ready() with
  #        its gc.kind stripped (privatizeAttachedRootOnlyWisp,
  #        internal/sling/sling.go:1575-1585). Contain it by clearing the
  #        five delivery keys on the work bead itself — there is no root
  #        tree to walk, so step 1 resolving no root is the CORRECT answer
  #        for that shape, not a failed lookup.
  #      * STANDALONE wisp launch (`gc sling <formula>`, no --on): the
  #        wisp root is the routed record, but there is no work bead to
  #        walk from, so this recipe never reaches it. Find it directly
  #        (`gc bd list --metadata-field "gc.kind=wisp" --status "$LIVE"`)
  #        and clear the same five keys on it.
  CONVOYS=$(gc bd dep list <work-bead> --direction=up -t tracks --json \
    | jq -r '.[] | select((.issue_type // .type) == "convoy") | .id')
  ROOTS=$(for convoy in $CONVOYS; do
      gc bd list --metadata-field "gc.input_convoy_id=$convoy" \
        --metadata-field "gc.kind=workflow" --status "$LIVE" \
        --json --limit 0 | jq -r '.[].id'
    done)
  # Legacy source-workflow roots carry the pointer instead — UNION it in
  # rather than consulting it only when the convoy path came back empty. A
  # bead can be tracked by a real convoy AND still be running under a
  # legacy-shape workflow, and either lookup alone leaves the other root
  # routed. Filter it through the same non-closed rule step 0 uses, so a
  # long-since-closed legacy root cannot rejoin the set and report itself
  # as "not contained" forever.
  LEGACY=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.workflow_id // empty')
  [ -n "$LEGACY" ] && ROOTS=$(printf '%s\n%s\n' "$ROOTS" \
    "$(gc bd show "$LEGACY" --json \
       | jq -r '.[0] | select((.status // "") != "closed") | .id')")
  ROOTS=$(printf '%s\n' "$ROOTS" | awk 'NF' | sort -u)
  # Only the UNION being empty means no graph.v2 root exists. For a
  # graph.v2 pour that is a lookup failure and nothing below can contain
  # anything, so stop; for the wisp shapes noted above it is the expected
  # answer, and the containment target is the work bead (attached) or the
  # wisp root (standalone) itself.
  [ -z "$ROOTS" ] && { echo "STOP: no graph.v2 workflow root resolved — see the wisp note above before concluding nothing needs containing" >&2; exit 1; }
  # A re-pour leaves more than one live root. EVERY one of them is a
  # separate routed record with its own descendant tree, so all of them
  # go into the id set below — never just the first. Collapsing to one
  # root here is the failure this note exists to prevent: the extra roots
  # stay routed while step 3, verifying only the one you kept, prints
  # nothing and reads as "contained".
  [ "$(printf '%s\n' "$ROOTS" | wc -l)" -gt 1 ] && echo "NOTE: multiple roots: $ROOTS" >&2

  # 2. Build ONE id set — EVERY root plus every descendant of EVERY root
  #    — and clear all five delivery keys on each. The roots are in the
  #    set because they are the routed records; the descendants because a
  #    step re-delivers itself from its deferred keys on activation.
  IDS=$( { printf '%s\n' "$ROOTS"
    for root in $ROOTS; do
      gc bd list --metadata-field "gc.root_bead_id=$root" \
        --status "$LIVE" --json --limit 0 | jq -r '.[].id'
    done; } | awk 'NF' | sort -u)
  for id in $IDS; do
    gc bd update "$id" \
      --set-metadata gc.routed_to="" \
      --set-metadata gc.deferred_routed_to="" \
      --set-metadata gc.execution_routed_to="" \
      --set-metadata gc.deferred_execution_routed_to="" \
      --set-metadata gc.deferred_assignee=""
  done

  # 3. Verify that SAME id set — every root included. A descendants-only
  #    query cannot prove containment: gc.root_bead_id is stamped on
  #    non-root nodes, so it comes back empty while a root itself is
  #    still routed or assigned. Check all five delivery keys plus the
  #    live assignee, and report a bead you could not read rather than
  #    skipping it — only a bead you actually read can be called
  #    contained. Verifying a NARROWER set than you cleared is the same
  #    bug as clearing a narrower set than exists: both print empty.
  #
  #    Decide readability in the SHELL, before jq. `gc bd show … | jq …`
  #    cannot report an unreadable bead by itself: when the show fails or
  #    prints nothing, jq receives no input, emits no row and exits 0 — the
  #    unreadable branch inside the filter never runs, and the bead reads as
  #    contained precisely because it could not be read. Only a non-empty
  #    document reaches jq below; the in-filter branch still covers the
  #    valid-JSON `[]` (bead genuinely absent).
  #
  #    Columns: ID, ASSIGNEE, gc.routed_to, FLAGS. FLAGS names every
  #    reason the row printed, and it is what you triage on — the row
  #    classes need DIFFERENT actions, and only some of them are fixed by
  #    re-running (see "Reading step 3's output" below). Without it a row
  #    flagged solely by a key this line does not print (any of the three
  #    execution/deferred keys) shows up as all dashes and reads as noise.
  for id in $IDS; do
    if ! shown=$(gc bd show "$id" --json 2>/dev/null) \
       || [ -z "$(printf '%s' "$shown" | tr -d '[:space:]')" ]; then
      printf '%s\t?\t?\tUNREADABLE\n' "$id"
      continue
    fi
    printf '%s' "$shown" | jq -r --arg id "$id" '
      def dash: if (. // "") == "" then "-" else . end;
      (if type == "array" and length > 0 then .[0] else {id: $id, unreadable: true} end)
      | . as $b
      | (["gc.routed_to", "gc.deferred_routed_to", "gc.execution_routed_to",
          "gc.deferred_execution_routed_to", "gc.deferred_assignee"]
         | map(select(($b.metadata[.] // "") != ""))) as $routing
      | (if ($b.assignee // "") != "" then ["assignee"] else [] end) as $claimed
      | (if ($b.unreadable // false) then ["UNREADABLE"] else [] end) as $unread
      | ($unread + $claimed + $routing) as $flags
      | select(($flags | length) > 0)
      | "\($b.id)\t\($b.assignee | dash)\t\($b.metadata["gc.routed_to"] | dash)\t\($flags | join(","))"' \
      || printf '%s\t?\t?\tUNREADABLE\n' "$id"
  done
  # That trailing `||` covers the third failure mode: output that arrives
  # but jq cannot parse (a raw control character in a bead's notes is the
  # usual cause). An UNREADABLE row is a false alarm you re-run; a silently
  # skipped bead is a containment claim you never earned.
  # Empty output = contained. Any row is still routed, still carries
  # withheld delivery, is already claimed (assignee), or is unreadable —
  # none of those is containment, and FLAGS says which, because the
  # classes need different actions.
  ```

  **Reading step 3's output.** Step 3 is not optional: the read in step 2
  and the writes that follow are not atomic, so a worker can claim
  between them. But "re-run until it comes back empty" is a valid stop
  condition only for the rows a re-run can actually change, and one class
  is not among them. Triage on the FLAGS column:

  - **Routing/deferred rows** (`gc.routed_to`, `gc.deferred_routed_to`,
    `gc.execution_routed_to`, `gc.deferred_execution_routed_to`,
    `gc.deferred_assignee`). Step 2 clears exactly these keys, so a row
    still carrying one means the record re-acquired delivery after you
    cleared it — a write raced the non-atomic read, or an activation
    promoted a deferred key. **Re-run steps 2 and 3.** These are the rows
    the loop is for, and for them "empty" is the right target. Re-run
    step 1 too if a re-pour could have added a root since.
  - **`assignee` rows.** Delivery has already happened, and step 2
    deliberately does *not* clear a live `assignee` — clearing it recalls
    nothing (see "De-routing does not recall work a worker already holds"
    below), so the script leaves it visible rather than erasing the
    evidence. **Re-running will never clear these**, and the loop does not
    converge while one is present: waiting for empty output here is
    waiting forever. Contain them at the worker instead — peek the
    session named in the ASSIGNEE column (`gc session peek <session>`) to
    see what it is doing, stop it there, and write the hold into the work
    bead's `notes`, which is what a worker actually reads. A row flagged
    with **both** an assignee and a routing key still needs the re-run
    for its routing half.
  - **`UNREADABLE` rows.** These prove nothing either way. Re-run them;
    if one stays unreadable, read that bead directly — a raw control
    character in `notes` is the usual cause, and
    `gc bd show <id> --json | tr -d '\001-\010\013\014\016-\037' | jq .`
    gets past it.

  You are done when every remaining row is an `assignee` row you have
  handled at the worker — not necessarily when the output is empty, which
  for an already-claimed record it never becomes.

  **Never close these beads to contain them.** A force-closed step
  leaves an orphaned husk that re-runs as duplicate work. Clear the
  routing and leave the records open.
- **De-routing does not recall work a worker already holds.** Once the
  `assignee` is stamped, delivery has happened; clearing the routing
  fields only affects the next offer. This is "Metadata is not
  enforcement" again, one step later in the lifecycle.
- **The durable mitigation is the work bead's `notes`.** A "do not start
  until `<bead>` lands" line is what a worker actually reads, precisely
  because the dep graph is not consulted on the records the pour delivers
  — the routed root or the steps claimed off it — and the work bead's own
  deps are two metadata pointers away from all of them.

### How to actually hold a bead

Remove it from the predicate. The terms are a conjunction, so falsifying
any one is sufficient — but pick a term that covers the tier you care
about:

- **`gc.routed_to=""`** drops the bead out of Tier 3, so it is neither
  offered to the pool nor counted as demand. It does **not** cover the
  assignee tiers (1 and 2): an `assignee` left behind still surfaces the
  bead to that named session, so clear `assignee` too.
- **Status off `open`** (`blocked`, or `deferred` for a timed park)
  removes the bead from `bd ready`, which backs **Tiers 2 and 3** — so it
  is no longer offered as ready work to its assignee or to the pool.
  Tier 1 is a separate `bd list --status=in_progress` query, not `bd
  ready`; it matches only work a session already had in flight, so a bead
  parked before it is claimed was never in Tier 1 to begin with.
- **An open `blocks` dep** falsifies the `blockers` term — but only
  where the work bead is itself the routed claimable unit. It holds
  nothing under a graph.v2 formula dispatch, where the routed bead is
  the workflow root the pour just minted (previous section). Hold that
  case by not slinging until the blocker closes.

Two combinations are idiomatic, and they differ in intent:

- **`assignee=""` + `gc.routed_to=""`, status still `open`** — detached
  from both queues while still counting as unlanded work. This is the
  gating pattern in
  [work-bead-state-machine.md](work-bead-state-machine.md).
- **Clear `gc.routed_to` *and* set `status=blocked`** — the
  belt-and-braces park, for when the bead should not read as ready work
  at all.

Keep the explanatory metadata either way: a `hold_reason` is genuinely
useful *alongside* a real hold. It is only dangerous as a *substitute*
for one.

There is also a recognized label convention worth preferring over an
invented key — `hold:<value>` labels, which `gc doctor` checks against
the routing fields (`hold-label-routed-to`,
`hold-label-conventions:<scope>`). That those checks exist at all makes
the same point: the label records the intent, the routing fields do the
work, and the two have to be changed together.

## Note: upstream tutorial wording

`docs/tutorials/06-beads.md` (upstream) still says, at line ~389:

> Work is routed to an agent (via assignee or `gc.routed_to`
> metadata)

This conflates Lanes 1 and 2 as parallel routing paths. It is
superseded by the PR #1736 ruling and is expected to be updated by
upstream on its own schedule. Per the gc-toolkit
`upstream-engagement` posture, we do not pre-empt that update; this
local doc is authoritative inside gc-toolkit until upstream catches
up. The upstream `docs/reference/cli.md` already covers the
mechanical `--reassign` flag (one table row at `cli.md:2789`); it
does not cover the broader four-lane model.
