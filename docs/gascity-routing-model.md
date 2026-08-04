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
| Lane 4 formula-sling field contract (`--on` attach vs standalone launch) | gastownhall/gascity | Attach routes the source and leaves the wisp root unrouted: `rigs/gascity/internal/sling/sling_core.go:482` (`molecule_id` on source) and the rationale comment at `:488-497`, citing gastownhall/gascity#2848; pinned by `TestOnFormulaAttachesAndRoutes` (`rigs/gascity/cmd/gc/cmd_sling_test.go:4105`, asserting source `gc.routed_to=mayor` at `:4129` and wisp-root `gc.routed_to` empty at `:4151`). Standalone launch routes the root instead: `slingFormula` finalizes on `mResult.RootID` (`sling_core.go:373`). Flags are mutually exclusive at `rigs/gascity/cmd/gc/cmd_sling.go:158`; `AttachFormula` leaves `IsFormula` false (`internal/sling/sling.go:326`) while `LaunchFormula` sets it true (`:305-309`). Reassign gate `shouldReopenForReassign` at `sling_core.go:303-305` with its rationale at `:296-302`, and the `Reassign` field comment at `internal/sling/sling.go:273-279`. Graph.v2 attach returns before routing: `sling_core.go:477-481` → `doStartGraphWorkflow` (`:645-683`). Verified current at upstream/main `1dbf0731e`. | 2026-07-23 |
| Pool demand counts routed **and unassigned** | gastownhall/gascity | `bdReadyPoolDemandShell` at `rigs/gascity/internal/config/workquery.go:41-43` (`bd ready --metadata-field "gc.routed_to=$target" --unassigned --exclude-type=epic`); the jq form applies the same `assignee == ""` filter at `workquery.go:586`. Verified current at upstream/main `1dbf0731e`. | 2026-07-23 |
| Claim predicate — `gc hook` tiers, `bd ready` semantics, built-in pool query | running `gc` binary + live city | Read off the **running implementation**, not from prose: `gc hook --help` ("Finds routed work using the agent's `work_query` config"); `gc bd ready --help` ("open issues with no active blockers", "Excludes in_progress, blocked, deferred, and hooked issues", `GetReadyWork` semantics); the built-in queries embedded in the `gc` binary — the assignee tiers loop `for id in "$GC_SESSION_ID" "$GC_SESSION_NAME" "$GC_ALIAS"` around `bd list --status=in_progress --assignee=<candidate>` (in-progress recovery) then `bd ready … --assignee=<candidate> --exclude-type=epic --json --limit=…` (ready assigned), and the routed tier is `bd ready --metadata-field "gc.routed_to=<target>" --unassigned --exclude-type=epic --json --sort oldest --limit=…` (offer) with the same filter at `--limit 0` counted (demand); Go-side helper symbols `UnassignedRoutedWork` / `UnassignedInProgressPoolWork`. The routed-tier shape is corroborated by this rig's own `proactive` agent, whose `work_query`/`scale_check` in the resolved city config (`gc config show`) are that same filter, adding only a `--db` pin and an enablement guard. `hold:<value>` convention observed as the live `gc doctor` checks `hold-label-routed-to` and `hold-label-conventions:<scope>`. Binary build `salvage/gc-c05nr-89e2e699f`. | 2026-07-23 |
| Instance-suffixed `gc.routed_to` normalized on the **demand read side only** | gastownhall/gascity | `17130b324` — "Normalize routed work instance names in demand matching (#4596)". Read side: `controllerDemandRouteTarget` (`rigs/gascity/cmd/gc/build_desired_state.go:1718`, rationale comment at `:1707-1717`), reached from `defaultScaleCheckCountsAndDemand` (`:1474`, invoked at `:735`) for every template in `defaultScaleTargets` — which is *not* only the no-custom-`scale_check` pools (`:446`, `:491`, `:567`): a custom-`scale_check` pool also gets this probe while cold (`isCold` at `:476`; append + `coldWakeTemplates` at `:633-637`), its contribution clamped to 1 (`:757-759`) and merged as a maximum against the custom count (`:766-768`); helper `agentutil.NormalizePoolRouteTarget` (`rigs/gascity/internal/agentutil/resolve.go:228`); coverage `TestDefaultScaleCheckCountsAndDemandNormalizesInstanceSuffixedRouteTarget` and `…LeavesUnmatchedInstanceSuffixAlone` (`cmd/gc/build_desired_state_test.go`). Offer side deliberately unchanged and exact-match: `bdReadyPoolDemandShell` (`rigs/gascity/internal/config/workquery.go:41`) with `$target` from `poolDemandTarget()` (`:157`), and `hookClaimMatchesRoute`'s raw `==` (`rigs/gascity/cmd/gc/cmd_hook_claim.go:1205`) over base-name route targets (`cmd/gc/cmd_hook.go:468`, `:685`). Write side, two distinct helpers: `032c1fbcd` (#3963) centralizes the **agent-derived** route identity as `agentutil.RoutedToIdentity` (`resolve.go:204`, collapse to `PoolName`), which the default sling query inlines rather than calls (`internal/config/workquery.go:532-536` — `internal/config` cannot import `agentutil`, which imports `config`); the **explicit-target-string** collapse is the separate `agentutil.NormalizePoolRouteTarget` (`resolve.go:228`), applied by sling's built-in routing path at `cmd/gc/cmd_sling.go:766`. Assigned-work companion `738f44732` (#4597): `cmd/gc/assigned_work_scope.go:156`, `cmd/gc/pool_desired_state.go:178`. Read in the `rigs/gascity` fork at `390624b0e`, whose adopted upstream base is `e6135a435` (#4847). | 2026-07-31 |
| `default_sling_formula` — a default formula on the target silently converts a bare `gc sling <target> <bead>` from Lane 1 into a Lane 4 attach | gastownhall/gascity + this city's config | Formula-branch predicate at `rigs/gascity/cmd/gc/cmd_sling.go:978` — taken when `IsFormula` is set, **or** `OnFormula` is non-empty, **or** `NoFormula` is unset and `Target.EffectiveDefaultSlingFormula()` is non-empty; the plain-routing predicate `missingBeadForceApplies` (`:1183`) carries the same condition inverted. Opt-out `--no-formula` ("suppress default formula (route raw bead)") at `:153`, mutually exclusive with `--formula` and `--on` at `:159-160`. Resolver `EffectiveDefaultSlingFormula` (own → inherited → empty) at `internal/config/config.go:3581`. Default-formula and `--on` share one attach pipeline, `attachFormulaToBead` — contract comment "graph-vs-legacy behavior is byte-identical across both entry points" — at `internal/sling/sling_core.go:479-497`. JSON `routed` is computed independently of any routing write at `cmd/gc/cmd_sling.go:1138`; payload keys at `:1090-1106`; `workflow_id` sourced from `result.WorkflowID` (`internal/sling/sling_core.go:730`, source-bead stamp at `:752`). `mol-polecat-work` is graph.v2 via `[requires] formula_compiler = ">=2.0.0"`, matching `graphV2Requirement` / `UsesGraphCompiler` (`internal/formula/requirements.go:14-16`, `:299`). That formula is **imported, not repo-local** — no path under this rig's `formulas/` resolves it, so cite the resolution contract rather than a local file: `gc formula show mol-polecat-work --json` reports the formula plus the `search_paths` it resolved through, and for this formula that is the imported gastown pack's `gastown/formulas/mol-polecat-work.toml:48-49` (materialized in the local pack cache under `~/.gc/cache/repos/<hash>/`). Its stable source is that pack at the fork's adopted pin `sha:33d3a430a67d1782ad364556cb566bdb01d0afe3` — recorded in `rigs/gascity/examples/gastown/packs.lock:5-6`, as `PublicGastownPackVersion` (`internal/config/public_packs.go:11`), and as the `go.mod` pseudo-version `v0.3.1-0.20260617013242-33d3a430a67d` (trailing 12 hex == the pin); the module copy at `$(go env GOMODCACHE)/github.com/gastownhall/gascity-packs@<pseudo-version>/gastown/formulas/mol-polecat-work.toml` is byte-identical to the cached one (`cmp`, 2026-08-02). City scope: `default_sling_formula = "mol-polecat-work"` in this city's `city.toml`, resolved onto every agent in `gc config show`. Stamp-don't-sling counterexample in this repo: `assets/scripts/check-set-heal.sh:355-357` (rationale comment) and `:393` (the direct `gc.routed_to` stamp); the script contains no `gc sling` call. Applies to a **targetless** `gc sling <bead>` too, and by the same predicate: `inferSling1ArgTarget` resolves only a target *string* (`cmd/gc/cmd_sling.go:244-252`), which the shared path turns into an agent (`:433`) and stores as `opts.Target` (`:463-464`) — the same field an explicit target fills — before the `:978` branch is reached, so the resolved default target decides the lane exactly as a typed one would. Read in the `rigs/gascity` fork at `390624b0e`. | 2026-08-02 |

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
- **Sets (graph.v2 formula):** *neither routing field, on either bead.*
  The graph launch path returns before the Lane 1 routing call
  (`internal/sling/sling_core.go:477-481` → `doStartGraphWorkflow`,
  `:645`), so the source bead gets `workflow_id` and **no
  `gc.routed_to` and no `assignee`**; the workflow root is promoted to
  `in_progress` in the **graph store** carrying `gc.source_bead_id`, and
  the per-step routing is stamped on the compiled recipe's steps
  (`internal/dispatch/control.go:1110`) rather than on the work bead.
- **CLI example:**
  ```bash
  gc sling gc-toolkit/gc-toolkit.polecat tk-abcde --on mol-polecat-work
  ```
- **Does NOT:** route the wisp root. This is the inverse of the
  standalone-launch shape below, and it is load-bearing rather than
  incidental — `TestOnFormulaAttachesAndRoutes`
  (`cmd/gc/cmd_sling_test.go:4105`) asserts both halves: the source bead
  ends with `gc.routed_to=<target>`, and the wisp root ends with
  `gc.routed_to` **empty**. The source comment is blunt about why
  (`internal/sling/sling_core.go:488-497`): the source "is the claimable
  unit of work, while the wisp root is deliberately left unrouted…
  Do not 'fix' this to wispRootID — it would orphan the work"
  (gastownhall/gascity#2848).

#### Reading a graph.v2 attach correctly — the duplicate-wisp trap

A work bead dispatched under a **graph.v2** formula shows `gc.routed_to`
absent *and* `assignee` null **while it is fully dispatched**. Per the
paragraph above that is the designed shape, not a stranded bead — so
"no routing fields" is not evidence that dispatch failed. Re-slinging on
that misreading pours a **second** wisp against the same bead, and the
two workers converge on one shared worktree.

To check whether such a bead is really dispatched, look at
`metadata.workflow_id` (graph.v2) or `metadata.molecule_id` (classic
attach) and resolve the wisp root it names — not the bead's own routing
fields.

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
`gc.routed_to=<target>` under Lane 1's contract. A wisp root carrying
`gc.routed_to`, with a title matching the formula name, is therefore
normal for a launch and wrong for an attach. Its graph.v2 variant
behaves like Lane 4's: the root is promoted in the graph store and no
`gc.routed_to` is written (`internal/sling/sling_core.go:363-368`).

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
  **graph.v2** variants are the exception: they write **no** `gc.routed_to`
  on either the work bead or the wisp root, so a bead under a graph.v2
  workflow is dispatched through the graph store and is deliberately absent
  from Tier 3 (see "the duplicate-wisp trap" above).

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
