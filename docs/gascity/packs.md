---
name: Gas City pack & formula authoring (platform facts)
description: What Gas City does with a pack and a formula that its own specs and guides leave unsaid — how a v2 step advances and a run ends, what processes workflow-finalize, when a check loop gets a fresh context, how a directory import goes live, how builtin pins resolve, and what a formula body can expand — each cited and dated. gc-toolkit's own authoring conventions on these are pack-authoring.md.
---

# Gas City pack & formula authoring

This page states Gas City behavior only: what the runtime does when it loads
a pack and runs a formula, where upstream's specs and guides do not already
say it. Each section names its evidence and the date it was read. The
upstream specs stay authoritative for the formats themselves, and
gc-toolkit's own conventions for writing its formulas, scripts and skills on
top of these facts are [pack-authoring.md](../pack-authoring.md).

## Scope

**Mandate.** Gas City's behavior when it loads a pack and runs a formula, as
far as upstream's specs and guides do not state it: how a graph.v2 step
advances and how a run ends, what processes a workflow's finalize bead, when
a check loop gets a fresh context, how a pack imported from a directory goes
live, how builtin pack pins resolve, and what a formula body can expand.

**Boundaries.** The full formats are upstream's specs, linked below and
indexed by [gascity/README.md](README.md). gc-toolkit's own
authoring conventions are [pack-authoring.md](../pack-authoring.md). Carrying
local fixes against `gascity` source is [fork-patching.md](../fork-patching.md).
Agent variants and session lifecycle are [gascity/agent-types.md](agent-types.md).

## What upstream's docs already say

Read these first; this page does not restate them. Coverage checked
2026-10-19 against `gastownhall/gascity` at `1e05ae624`.

- **Choosing a contract.** v1 and v2 are peer contracts, v1 is the default,
  and upstream recommends v2 for new work —
  [understanding formulas](https://docs.gascity.com/guides/understanding-formulas),
  "Choosing a Compiler Contract", and
  [formula spec v1](https://docs.gascity.com/reference/specs/formula-spec-v1).
  `gc converge` accepts only v1 formulas, and v1's container-dependency
  semantics have a v2 gap
  ([gascity#3451](https://github.com/gastownhall/gascity/issues/3451)): under
  v2, enumerate the children a step depends on in `needs`.
- **The v2 opt-in** is `[requires] formula_compiler = ">=2.0.0"`;
  `contract = "graph.v2"` is deprecated —
  [formula spec v2](https://docs.gascity.com/reference/specs/formula-spec-v2),
  "Opt-in surface" and "Deprecated surfaces".
- **`phase` and root-only recipes** are legacy v1 materialization mechanics,
  not a v2 authoring choice — formula spec v2, "Top-Level Keys". A root-only
  recipe materializes no step beads and no `workflow-finalize` bead, so a
  formula that declares the v2 compiler and keeps `phase = "vapor"` has no
  graph for the engine to run and no finalize to close its root.
- **Step outcomes** (`gc.outcome`, `gc.failure_class`, `gc.failure_reason`)
  and the check, retry and drain controls — formula spec v2, §3. A `check`
  step cannot carry an `assignee` — §3.1.
- **`until` runs once**, and the rest of the parsed-but-inert surface (gate
  `type` vocabulary, `waits_for` modes, `vars.<name>.type`) — formula spec v2,
  §4 "Accepted But Inert".
- **Layering and names.** A same-named formula, prompt or asset in a
  higher-priority layer shadows the lower one, two agents resolving to one
  qualified name fail loading, and fragment `define` names resolve across the
  loaded packs — formula spec v2 §1.1, and the
  [pack spec](https://docs.gascity.com/reference/specs/pack-spec) §1.3.2 and
  §2.5 "Naming And Collisions".
- **`pack.toml` authoring.** `[pack] schema = 2`, imports by `source` plus
  `version` and never `path`/`ref`/`commit`/`hash`, private files under
  `assets/`, no top-level `scripts/`, the city-only tables, and which legacy
  constructs the loader still accepts for compatibility — pack spec §1.1,
  §1.2 and "Authoring Summary".
- **Patches.** `[[patches.agent]]` modifies an existing agent and fails
  loading when the target is missing; list fields append through `_append`
  variants — pack spec §1.2.10 and §2.6. How a `[[patches.named_session]]`
  target matches is [gascity/agent-types.md](agent-types.md#variant-a--named-singletons-named_session).
- **Builtin packs.** Pinning a bundled source at any commit other than the
  binary's canonical pin makes it an ordinary remote import, and
  `gc doctor --fix` re-pins superseded bundled pins —
  [system packs](https://docs.gascity.com/reference/system-packs).
- **Formula variables** substitute as `{{key}}` into descriptions, titles,
  notes, assignee and metadata values — formula spec v2, §1.4.
- **Pack commands** register as `gc <binding> <command>` under the binding
  the city imports the pack as, and run with `GC_PACK_DIR` set to the root of
  the pack that defines them — pack spec §1.2.12, and
  [multi-agent engineering environment](https://docs.gascity.com/guides/multi-agent-engineering-environment),
  "Turn repeated operations into pack commands".

## A v2 step advances by closing its own step bead, not by `drain-ack`

Materialized step beads are ordinary beads wired together by `blocks` edges,
so closing one is what makes its dependents Ready. Nothing else advances the
graph, and the close carries the outcome
(`--set-metadata gc.outcome=pass --status=closed`; a failure adds
`gc.failure_class` and `gc.failure_reason`). The core pack's
`assets/prompts/graph-worker.md` carries the full outcome set, and
`formulas/mol-do-work.toml` the pass closure and the terminal
close-then-drain-ack ordering.

Neither environment variable those bodies use names the step a session is
executing. `$GC_BEAD_ID` is unset in the step-execution environment, so a
guarded close short-circuits and the step is never closed. `$GC_TRIGGER_BEAD_ID`
is not refreshed by `gc hook --claim`, so it still names the session's spawn
bead, and a close through it lands on another live session's step.
*Evidence:* observed on this city's fork, 2026-08-13.

**`gc runtime drain-ack` is a session verb, not a step verb.** It tells the
reconciler this session is finished; it closes no bead. A session that
drain-acks while still holding an open, assigned step bead is stranding work,
and the reconciler reads it that way: it emits
`session.drain_acked_with_assigned_work`, and once the episode ages past the
confirmation grace it unassigns and reopens the stranded bead so the pool can
reclaim it. The step returns to the pool, a fresh worker claims it, and the
workflow respawn-loops at its entry step. It presents as a routing or pool bug;
it is a missing `--status=closed`. Terminal steps close, then drain-ack.

Leaving a step `open` instead is the same loop by another door, because an
open step is claimable. Clearing `gc.routed_to` alone does not hold it either:
when a session drains, the runtime releases the `open` and `in_progress` work
assigned to it and stamps a `gc.run_target` fallback route only when the bead
is otherwise unrouted.

A root-only in-session wisp is the asymmetry that sets the trap. It runs every
formula step in one session, materializes no step beads and no
`workflow-finalize` bead, and so correctly drain-acks without closing anything;
its root is reaped off the work issue's closure instead, by walking
`gc.input_convoy_id` back to the tracking convoy. A materialized graph has no
such backstop — each step bead is a gate only its own body opens.

*Evidence:* `recordDrainAckAssignedWorkEvent` (`cmd/gc/session_reconciler.go`),
`repairStrandedPoolWorkerBead` and `unclaimWorkAssignedToRetiredSessionInfo`
(`cmd/gc/session_beads.go`), `collectInputConvoyWorkflowRoots`
(`cmd/gc/wisp_autoclose.go`), read at fork `c0571088c` on 2026-07-29. The
drain-ack event is in upstream's OpenAPI schema; the reopen is undocumented.

## A run is cancelled through the supervisor API

`POST /v0/city/{city}/runs/{run_id}/cancel` ends a molecule's run. It closes
the workflow root and every member that is not closed, a `blocked` one
included, with `gc.outcome=canceled`, blockers first, and runs none of them;
members with `gc.scope_role=teardown` are left alone. A session mid-step
finishes that step and idles. The call needs an `X-GC-Request: true` header
and answers 202 with the count it closed, 404 for an unknown run, and 409
when every root it matched is already closed. Nothing resumes a cancelled run.
Upstream ships no `gc` verb for it; `gc wait cancel` cancels a wait, not a run.

Two CLI verbs close workflow beads by other routes. `gc convoy delete <id>`
closes a root and every bead carrying its `gc.root_bead_id` with
`gc.outcome=skipped` (`--delete` removes them). `gc convoy delete-source
<bead>` finds roots by `gc.source_bead_id`, which a convoy-first graph.v2
root does not carry, so it reports nothing to close for one.

*Evidence:* `humaHandleRunCancel` (`internal/api/huma_handlers_runs.go`);
live probe of this city's supervisor, `gc` 1.4.3, 2026-10-13, and a
`delete-source` probe that matched no convoy-first root, 2026-10-07; upstream
documents the endpoint only in its
[OpenAPI schema](https://docs.gascity.com/reference/schema/openapi.json), and
the two convoy verbs in the [CLI reference](https://docs.gascity.com/reference/cli).

## `workflow-finalize` is dispatcher-processed, not self-firing

The `gc.kind = workflow-finalize` bead is a control bead. It sits inert until a
`gc convoy control --serve` loop picks it up and runs `processWorkflowFinalize`,
which closes the workflow root first and the finalize bead second. With no
serve loop ticking the root never closes, however correct the graph is, so a
Ready finalize bead with no dispatcher running is an operational hold, not a
wiring bug. `gc agent list` derives status purely from config, so `active`
means *configured and not suspended*, never *serving*.

`gc sling` creates the finalize bead unassigned and routed to the dispatcher
of the store the graph lives in — `gc.routed_to = <rig>/core.control-dispatcher`
for a rig graph, `core.control-dispatcher` for a city one — so an
assignee-only query misses it. The serve loop reads that route unassigned,
and separately reads control beads assigned to it:

```bash
# how a sling-created finalize bead in a rig graph is picked up
bd ready --metadata-field "gc.routed_to=<rig>/core.control-dispatcher" --unassigned --json
```

If the finalize bead comes back in that Ready set, the wiring is fine and the
workflow is purely dispatcher-gated: start the loop.

*Evidence:* `processWorkflowFinalize` (`internal/dispatch/runtime.go`), read
at fork `c0571088c` on 2026-07-29; present at upstream `1e05ae624` on
2026-10-19. The dispatcher itself is
[gascity/agent-types.md](agent-types.md#variant-e--deterministic-workers-no-prompt-loop).

## `[steps.check]` is fresh-context per iteration only if pool-routed

A check step's point over an in-session loop is that each iteration starts in
a fresh context, and that holds only when the iterations are routed to a pool.
The spec documents the run/check machinery without this condition, and nothing
errors, warns or validates when it is unmet. Routing is the only lever: a
check step cannot carry its own `assignee`, so sling the formula at a pool
target or set the step's `gc.run_target` to one.

- The predicate is `beadUsesMetadataPoolRouteWithConfig`
  (`internal/dispatch/control.go`): true when the attempt's routed target
  (`gc.execution_routed_to`, else `gc.routed_to`) resolves to a
  multi-session agent — a pool — or the bead still carries a legacy `pool:`
  label.
- A check loop's control bead is `gc.kind = ralph` (upstream's display text
  calls it a **check loop**). On a failed iteration the control handler clones
  the next one through `retryPreservedAssigneeWithConfig`
  (`internal/dispatch/ralph.go`): pool-routed, the assignee is cleared, session
  affinity cleared and pool labels stripped, so a different pooled worker
  claims it; otherwise the prior assignee is preserved and the same session
  takes iteration N+1 with iteration N still in its context window.
- `[steps.retry]` is a different path with a different failure mode. Its
  `retry-eval` control (`internal/dispatch/retry.go`) gates an explicit session
  recycle on the same predicate, and there the pooled path fails loudly — a
  missing `RecycleSession` callback or a pooled subject with an empty assignee
  are hard errors — recording `gc.retry_session_recycled = true` on success.
  The ralph path never sets that marker, and each clone strips it.
- Loop state is crash-safe either way. A dispatcher restart mid-append
  re-attaches to the iteration beads already created instead of cloning a
  second set: ralph resolves an existing partial attempt first, and
  `[steps.retry]` walks an explicit `gc.retry_state` of `spawning` → `spawned`.

*Evidence:* read at fork on 2026-07-22; `retryPreservedAssigneeWithConfig`
present at upstream `1e05ae624` and the fork on 2026-10-19.

## A directory-imported pack is live from the working tree, not from a merge

A pack imported by a plain directory path in `city.toml` is read from that
directory's working tree:

```toml
[imports.<binding>]
source = "<directory>"   # a path: no ref, no version
```

A URL import can be pinned with `version = "sha:…"`; this form has no such
knob, and no git ref is consulted, so nothing about a merge to `origin/main`
changes what is live until the working tree changes. (`gc import add` writes a
different form for a local path inside a git worktree: a `file://` repo source
locked to the current commit — [CLI reference](https://docs.gascity.com/reference/cli),
`gc import add`.)

The pack's convention directories — `agents`, `commands`, `doctor`,
`formulas`, `orders`, `template-fragments`, `skills` and `mcp` — are watched.
A file event pokes a rescan that diffs the order set by signature and logs
`orders reloaded: added|changed|removed <name>`. A reload that lands mid-sync
observes the intermediate state, so an in-place edit there is live surgery.
`gc order list` and `gc config show` re-parse disk, so they prove a file is on
disk and parses, not that the live supervisor picked it up; the supervisor log
line is that proof.

*Evidence:* `conventionDiscoveryDirNames` (`internal/config/revision.go`),
`rescanOrderDispatcher` and `orderSetChangeSummary` (`cmd/gc/city_runtime.go`),
read on 2026-08-10; the directory list and the log line are present at
upstream `1e05ae624` and the fork on 2026-10-19.

## Builtin pins track the `gc` binary

Builtin packs are never materialized into the city. They compose through the
same `[imports.<binding>]` declarations, but resolve from a user-global repo
cache that the running `gc` pre-seeds with its own embedded copy of each pack
at that pack's canonical pin — which is why they resolve offline, and why an
empty `.gc/system/` is correct rather than a broken install. The cache marker is
a content hash bound to the running binary, and every production config load
routes through `ensureBuiltinPacksForConfigLoad`, so a cold or evicted cache
self-heals on the next command after an upgrade.

- **A builtin pin advances only when a newer `gc` is installed**, so a builtin
  pin behind upstream HEAD is expected, not drift.
- **`gc doctor --fix` re-pins; `gc import install` does not.** The doctor's
  `packv2-import-state` check rewrites superseded bundled pins
  (`rewriteSupersededBundledPinsFS`). `gc import install` collects the declared
  imports, syncs `packs.lock` and installs what is locked, leaving the declared
  pin untouched; against a superseded pin it fetches that exact commit over
  the network.
- **`core` and `gastown` are different packs from different repos.** `core`
  is the bundled builtin — `gc-*` skills, default prompts, core formulas,
  orders, doctor checks, provider overlays — and ships no crew agents, but it
  is not agentless: it contributes the scope-local `control-dispatcher` lane
  (`core.control-dispatcher`). Upstream's system-packs page says `core` ships
  no agents; the core pack's own `agents/control-dispatcher/agent.toml` says
  otherwise. The crew (`mayor`, `deacon`, `polecat`, `refinery`, `witness`,
  `dog`, `boot`) is the `gastown` pack.
- `gc pack list`'s "No remote packs configured" describes the legacy
  remote-registry mechanism, is orthogonal to `[imports]`, and does not mean
  no packs are loaded.

*Evidence:* `cmd/gc/embed_builtin_packs.go`; `internal/builtinpacks/registry.go`
(`MaterializeSyntheticRepo`, `publicSubpathForPack`);
`cmd/gc/import_state_doctor_check.go`; the `core` pack under
`internal/bootstrap/packs/core/`. Verified against `gc` 1.4.1, built from fork
`3983cc049`, on 2026-08-13; `packv2-import-state` and the control-dispatcher
`agent.toml` present at upstream `1e05ae624` on 2026-10-19.

## A formula body gets no template pass

Gas City expands `{{...}}` through two different engines:

- **Prompts and template fragments** (`*.template.md`, plus `session_setup`
  and `pre_start` commands) render through Go `text/template` with a populated
  context, so dotted tokens resolve: `{{.ConfigDir}}`, `{{.RigRoot}}`,
  `{{.WorkDir}}`.
- **Formula and molecule step bodies** (`description`, and a step's `title`,
  `condition` and metadata) are expanded by plain string substitution over a
  strict `{{name}}` pattern — `[a-zA-Z_][a-zA-Z0-9_]*`, no leading dot, no
  spaces — with no `text/template` pass at all. A step's `id` is not
  substituted: it is used verbatim as the bead's `Ref` and `gc.step_ref`, so
  it must be a literal.

So a dotted `{{ .ConfigDir }}` in a formula body never matches the variable
pattern: it survives literally and silently no-ops, and a guard like
`[ -x "{{ .ConfigDir }}/assets/scripts/foo.sh" ]` written in a formula is
always false.

`GC_PACK_DIR` is set for order and pack-command execution and is not exported
to agent or worker sessions, so a formula body that references it resolves an
empty path. `GC_RIG_ROOT` (the agent's own rig checkout) and `GC_CITY_PATH`
(the city root) are in the session environment. Neither names the pack: a
step reaches it by running a pack command, which does get `GC_PACK_DIR`
([pack-authoring.md](../pack-authoring.md#step-text-and-skills-reach-pack-scripts-at-runtime)).
gc registers a pack's commands only for an import in the city root
`pack.toml`. A rig's `[rigs.imports.<binding>]` and `[defaults.rig.imports]`
register none, so in a city that imports a pack only per rig,
`gc <binding> <command>` answers `unknown command`.

A formula body can name the pack's binding through a var. `gc sling` adds
`rig_name`, `binding_name` and `binding_prefix` (the binding plus a dot) to
every pour, taken from the agent it routes to, and a `--var` the caller passes
wins. An order's pour adds none of them, so a formula an order pours gets the
var's declared default.

*Evidence:* read on 2026-06-28; on 2026-10-19 neither `internal/formula` nor
`internal/molecule` imports `text/template` at upstream `1e05ae624` or the
fork. Upstream documents the order and command variables (formula spec v2
§1.4; [orders tutorial](https://docs.gascity.com/tutorials/07-orders); pack
spec §1.2.12) but not the session environment. The routing vars were read on
2026-10-27 at the fork's `e03752646`, the installed gc's build:
`buildSlingFormulaVars` in `internal/sling/sling.go` adds them through
`addRoutingVar`, and `prepareOrderWispRecipe` in `cmd/gc/order_dispatch.go`
passes the order's vars alone. The command registration was read the same
day at the same build. In `internal/config/pack.go`, `expandCityPacks` adds a
city import's commands to `PackCommands`, while the `[rigs.imports]` loop in
`expandPacks` adds none. `engdocs/design/packv2/doc-commands.md` leans toward
keeping commands city-scoped. In a scratch city that imports gc-toolkit only
per rig, `gc <binding> scripts-dir` answered `unknown command`, and with the
city-level import added it named the pack.

## Refresh procedure

Each section's evidence line names what it was read from and when. Before
building on a section, re-read its symbols at current upstream main and in
this city's fork, and update the date with the reading. When upstream's
specs or guides come to state a section's fact, replace the section with a
line in "What upstream's docs already say".
