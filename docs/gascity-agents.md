---
name: Gas City agent types (platform facts)
description: What Gas City's agent variants do where upstream's docs leave it unsaid or state it wrongly — scope expansion, what makes a named session desired and how a patch reaches it, what keeps a session up and what an assignment gives it, pool slots and session names, kill and close, the control-dispatcher, gc session new, nudge fences, and which fields name a bead's holder — each cited and dated. gc-toolkit's own agent conventions are pack-authoring.md.
---

# Gas City agent types

This page states Gas City behavior only: what the agent variants do where
upstream's docs do not already say it, or say it wrongly. Each section names
its evidence and the date it was read, and says where the city's gascity fork
differs from upstream main. How work is routed to an agent is
[gascity-routing-model.md](gascity-routing-model.md). gc-toolkit's own
conventions for its agents — where a rig-scoped agent runs, the patrol-wisp
cycle, how a scan resolves an owner or an address — are
[pack-authoring.md](pack-authoring.md).

## Scope

**Mandate.** The agent variants Gas City supports, and how each is
identified, started, kept up and ended, as far as upstream's docs do not state
it: the corners that surface only when the variants mix.

**Boundaries.** How work moves between agents is
[gascity-routing-model.md](gascity-routing-model.md), and how a session's
pane and idle clock end it is
[gascity-human-engagement.md](gascity-human-engagement.md#how-a-session-ends).
gc-toolkit's own agent conventions are [pack-authoring.md](pack-authoring.md).
Prompt-template authoring and any one agent's role are out of scope.

## What upstream's docs already say

Read these first; this page does not restate them. Coverage checked
2026-10-19 against `gastownhall/gascity` at `1e05ae624`.

- **The primitives**: agents, named sessions, pools and sessions —
  [tutorial 02](https://docs.gascity.com/tutorials/02-agents),
  [tutorial 03](https://docs.gascity.com/tutorials/03-sessions), and the
  `Agent` and `NamedSession` fields (`scope`, `mode`,
  `min_active_sessions`/`max_active_sessions`, `scale_check`, `work_dir`,
  `pre_start`, `wake_mode`, `nudge`) in the
  [config reference](https://docs.gascity.com/reference/config). `work_dir`
  and `pre_start` take the placeholders `session_setup` does (`Session`,
  `Agent`, `AgentBase`, `Rig`, `RigRoot`, `CityRoot`, `CityName`, `WorkDir`,
  `DefaultBranch`).
- **Identity**: the qualified name `<dir>/<binding>.<name>`, with `<dir>`
  empty at city scope; the persisted forms `<rig>/<name>` and `<name>`; a
  pool slot's `-N` identity; `GC_ALIAS` and `GC_AGENT` — the
  [pack spec](https://docs.gascity.com/reference/specs/pack-spec) §2.4, the
  [session model](https://github.com/gastownhall/gascity/blob/main/engdocs/design/session-model-unification.md)
  ("Token relationships by origin", "Canonical persisted identity forms"),
  and the [identity separator contract](https://docs.gascity.com/reference/specs/identity-separator-contract-v1)
  (`/` encoded as `--`, `.` as `__`).
- **`session_origin`** (`ephemeral`, `manual`, `named`) and which origins
  reach the routed tier — session model, "Sessions" and "Default
  `work_query`"; the exception for a session whose alias is its own target is
  [gascity-routing-model.md](gascity-routing-model.md#the-read-side-the-claim-predicate).
- **`mode = "always"` validation**: rejected with `sleep_after_idle`, and
  capped by `max_active_sessions` —
  [named configured sessions](https://github.com/gastownhall/gascity/blob/main/engdocs/design/named-configured-sessions.md),
  §3 and §8.
- **A duplicate named-session identity fails `gc start`** —
  [the gc start walkthrough](https://docs.gascity.com/troubleshooting/gc-start-walkthrough),
  §7.
- **Commands**: `gc agent` is configuration only, runtime operations live
  under `gc session` and `gc runtime`, `gc session close` stops the runtime
  and closes the bead, and `gc session pin` keeps a session awake —
  [CLI reference](https://docs.gascity.com/reference/cli).
- **The control-dispatcher** runs one per store that owns a workflow graph,
  and handles the graph.v2 control kinds —
  [dispatch architecture](https://github.com/gastownhall/gascity/blob/main/engdocs/architecture/dispatch.md),
  "Store-scoped control-dispatcher ownership", and
  [formula spec v2](https://docs.gascity.com/reference/specs/formula-spec-v2).

Upstream's docs contradict the code in places this page settles below. The
[system packs](https://docs.gascity.com/reference/system-packs) page says
the `core` pack ships no agents; it ships the control-dispatcher. The session
model says named sessions never get generic demand and that a `work_query`
no longer materializes one; the awake set still has both arms. And the pack
spec says patches address an imported agent by its qualified name; an agent
patch also matches a bare local name.

## Scope is tri-state: omitted is not city

`scope` takes `"city"`, `"rig"`, or nothing, and the JSON schema enumerates
only the first two. Omitted, an agent or `[[named_session]]` in a city-level
V2 import is kept at city scope **and** stamped out once per rig, except for a
rig that declares the same import binding itself, which gets its own copy
through that import. An old-style `includes` passes no binding, so every rig
gets a copy. In a rig-level pack an unscoped entry is kept by rig expansion
alone, and a `scope = "city"` entry is hoisted to city scope rather than
dropped. So one unscoped stanza can yield both `<binding>.<name>` and
`<rig>/<binding>.<name>` for each rig: write `scope` explicitly to get one
identity. The config reference states the both-contexts expansion for an
agent; the named-session case and the binding skip are in no upstream doc.

*Evidence:* `expandCityImportedAgentsForRigs`,
`expandCityImportedNamedSessionsForRigs`, `rigDeclaresImportBinding`,
`filterAgentsByScope` and `hoistCityScopedAgents` (`internal/config/pack.go`),
read at upstream `1e05ae624` and the fork `a319c2fd6` on 2026-10-19.

## Variant A — Named singletons (`[[named_session]]`)

### What makes an on-demand session desired

`mode = "always"` is desired every tick unless its agent is suspended or the
session is dependency-only. An `on_demand` named session is desired when one
of three arms fires:

- **Named demand**: an `in_progress` or ready open bead assigned to its
  identity or runtime name. This is the only arm that creates an `on_demand`
  session with no session bead yet.
- **Routed demand**: routed, unassigned work on its backing template, for a
  single-instance (canonical-singleton) backing pool only. This is the only
  named-session reason that also wakes a drained bead.
- **Its work query**: the backing template's `work_query` returns work — once
  the session bead exists.

When none fires, the session is simply not desired that tick. Other arms
belong to other origins or states (pending create, explicit wake, manual,
assigned work, scaled, min-active, reset pending); attachment, a pending
interaction, a ready wait and a pin override toward awake; idle sleep, a hold
and a quarantine suppress.

So an `on_demand` named session whose agent declares no `work_query`, with
nothing assigned to it or routed at it, never spawns — which makes patching an
`always` singleton a base pack declares to `mode = "on_demand"`, from
`city.toml`, the way to retire it without forking the pack.

*Evidence:* `computeAwakeSetKeyed` (`cmd/gc/compute_awake_set.go`),
`computeNamedSessionDemandOn` (`cmd/gc/build_desired_state.go`), read at
upstream `1e05ae624` and the fork on 2026-10-19.

### A named-session patch matches only qualified names, and a bad one fails the city

```toml
[[patches.named_session]]
dir = ""                       # "" targets a city-scoped singleton
name = "<binding>.<identity>"  # the canonical identity to patch
mode = "on_demand"
```

A `[[patches.named_session]]` target matches only import-qualified names:
`name` is compared to the stanza's qualified name, and `template` to its
qualified or template-qualified name, so a stanza a pack declares as
`template = "boot"` is reachable only as `<binding>.boot`, with `dir`
supplying a rig-scoped stanza's `<rig>/`. A `template` that matches more than
one session is an "ambiguous" error. An agent patch differs: it also matches
an agent by bare `dir` and `name`, ignoring the binding, and patches the first
match. Copying the agent block's targeting into a named-session patch matches
nothing.

An unmatched target fails the whole config load (`applying patches: …`), not
just that patch. A live reload keeps the previous config, so the agent being
patched keeps running under its old setting while orders that load config
fail and `gc sling` is rejected — which reads from outside as a patch that
silently did nothing. Check the load after any patch edit:

```bash
gc config show >/dev/null; echo $?   # 0, or the city is not loading its config
gc config show --validate
```

*Evidence:* `namedSessionPatchMatches`, `applyAgentPatch` and `ApplyPatches`
(`internal/config/patch.go`), the reload in `cmd/gc/city_runtime.go`, read at
upstream `1e05ae624` and the fork on 2026-10-19.

### An always-mode session cannot idle-sleep

The config loader rejects `mode = "always"` with a `sleep_after_idle` the
backing agent sets or inherits, and the reconciler's idle-sleep branch skips
always-mode sessions as well, so neither `sleep_after_idle` nor
`[session_sleep]` can throttle one: `mode` is the only lever. A template that
does not resolve disables the session with a warning rather than an error.

*Evidence:* `validateNamedSessions` and `ResolveSessionSleepPolicy`
(`internal/config/config.go`), `isAlwaysNamedSession`
(`cmd/gc/compute_awake_set.go`), read at upstream `1e05ae624` and the fork on
2026-10-19.

## What keeps a named session up

The reconciler keeps a session materialized only while it has a wake reason:

| Wake reason | Lasts | How |
|---|---|---|
| Work on the hook (a bead assigned to the session) | until the work is done | `bd update --assignee` |
| Routed demand at its name | while the demand stands, for an `on_demand` session on a singleton pool | `gc sling` |
| A pin | until unpinned | `gc session pin` |
| An explicit wake | until the next start clears it | `gc session wake` |
| An attach | only while attached | `gc session attach` |

So `gc session wake` starts a session but does not keep it up: its explicit
wake reason survives a wait hold and idle sleep until the session starts, and
then clears, so a session with no other reason drains again shortly after.
Wake also lifts an operator suspend and quarantine, cancels waits, creates a
named session's bead when needed, and exits 1 when the session will not
start. A pin targets **the** canonical session, the one whose alias equals its
qualified name in `gc session list`; pinning a canonical session that has not
started creates its bead so the reconciler can start it. A pin refuses a
demand-only singleton, and is ignored for a suspended, closed, drained,
dependency-only or wait-held row. An attach is ignored only under a wait hold,
and wakes even a drained row. A hold and a quarantine override all of them.

*Evidence:* `Store.WakeSession` (`internal/session/wait_store.go`),
`cmdSessionSetPin` and `SetPinAwake` (`cmd/gc/cmd_session_pin.go`),
`ComputeAwakeSet`, read at upstream `1e05ae624` and the fork on 2026-10-19.

## An assignment gives a named session no turn

Writing an assignee makes a bead claimable; it wakes nobody. A session claims
the bead the next time it runs `gc hook`, which it does when it has a turn: at
launch, when someone types, or when a nudge arrives. The controller's
pool-claim, continuation and execution backstops govern pool-managed sessions
only, an agent's `nudge` text is typed at launch, and the controller restarts
a live session onto a newly assigned bead only under `wake_mode = "fresh"` —
and not when the session already claimed the bead, still holds its previous
assigned bead open, or woke after that bead closed. Under `"resume"`, an idle
named session sits beside a claimable bead until something else gives it a
turn. Upstream's `work_ladder` does not change this: it paces open pool seats
only, under the opt-in v2 reconciler.

*Evidence:* the fresh-cycle restart in `cmd/gc/session_reconciler.go`
(`RequiresFreshCycle`), backstop `governs()` in `cmd/gc/idle_nudge.go` and
`cmd/gc/execution_backstop.go`, `ladderGoverns` (`cmd/gc/work_ladder_lane.go`,
upstream only), read at upstream `1e05ae624` and the fork on 2026-10-19.

## Variant B — Pool workers

**Slot identities recur in every rig the binding serves.** A pool binding
imported into several rigs is stamped out once per rig, and each rig's
expansion allocates the same slot identities. The fully qualified instance
name tells them apart — its `<dir>` is the rig — but the agent base and the
`-N` suffix carry no rig, so a bare slot name names a different live session
in every rig the pool serves, and an equivalent `work_dir` exists under every
rig the slot has served. Only a live session's `work_dir` names the rig it
serves now: build any liveness map across all rigs before calling a worktree
ownerless.

**A pool session's runtime name carries the pack prefix, not the rig.** With
no `tmux_alias`, a pool session's runtime name is the template's base name
with `.` encoded as `__`, plus `-<session bead id>`, whichever rig it serves;
a named session's runtime name encodes its whole identity, rig included.
Counting live sessions by runtime name therefore folds every rig's instances
of a pool into one bucket. Count by `template`, which is rig-qualified, in the
same `gc session list` record.

**Two instances can race for one bead.** The claim is atomic, so the loser
does not progress, but it may already have prepared a workspace. A bead whose
`metadata.work_dir` names a different worker is the sign: read the peer's
state before re-implementing.

**Killing a pool session releases or restarts it.** `gc session kill` marks
the session asleep with `sleep_reason=killed` (and a five-minute
`kill-pending` state), and the bead stays open. A killed pool seat with no
started or ready work has its unstarted routed claims released, is closed
with `close_reason=killed`, and is replaced by a fresh seat; one with started
work restarts in place; a seat holding a routeless direct task keeps its
slot. `gc session close` is the verb for a session that should be gone.

*Evidence:* `expandCityImportedAgentsForRigs` (`internal/config/pack.go`);
`PoolSessionName` (`cmd/gc/pool_session_name.go`) and
`NamedSessionRuntimeName`; `KillFencedReport` (`internal/session/kill_fence.go`)
and `isPoolSessionSlotFreeableInfo` (`cmd/gc/session_state_helpers.go`); read
at upstream `1e05ae624` and the fork on 2026-10-19.

## Variant E — Deterministic workers (no prompt loop)

A deterministic worker is an agent with `prompt_mode = "none"` and a
`start_command`: the controller materializes and scales it like a pool
worker, but the session runs a program, not a prompt loop. The `core` pack
ships one in every city, the **control-dispatcher**: its `start_command`
execs `gc convoy control --serve --follow {{.Agent}}` behind a `sh -c`
wrapper, `process_names = ["gc"]`, `max_active_sessions = 1` with no
minimum, and an empty `scope`, so it expands once per store. Agent defaults
(provider, `default_sling_formula`, skills and MCP) skip it, and selection is
by exact `Dir`, so a city dispatcher never stands in for a rig.

- **It consumes routed work through its own query, not `gc hook`.** Its serve
  loop reads `gc.routed_to` and `gc.run_target` routes unassigned — its
  qualified route, `<rig>/workflow-control`, and the binding-stripped
  `[<rig>/]control-dispatcher` — plus beads assigned to it, excluding epics and
  held or `human`-labeled beads, answered in process. It handles exactly the
  control kinds in `beadmeta.ControlKinds`: `retry`, `ralph`, `check`,
  `retry-eval`, `fanout`, `drain`, `scope-check` and `workflow-finalize`.
- **A bead routed to it is not an orphan.** An ownership scan that resolves
  owners by session liveness finds no interactive session behind it. That is
  dispatcher-gated work in a normal state, usually still behind its own open
  step chain, and closing it releases the work it gates early.
- **Its liveness signals are inert.** `last_active` tracks pane output, which
  a serve loop that works in child processes never writes, so it reads stale
  for hours while `running=true`; `gc session peek` shows nothing meaningful;
  and `gc session nudge` text is never consumed and sits in the pane. Judge it
  by the `gc convoy control --serve` process's argv.

*Evidence:* `internal/bootstrap/packs/core/agents/control-dispatcher/agent.toml`;
`ApplyAgentDefaults` and `PreferredDeterministicControlDispatcher`
(`internal/config/config.go`); `workflowServeControlReadyQueryForBeads` and
`tryControlReadyScan` (`cmd/gc/dispatch_runtime.go`); `ControlKinds`
(`internal/beadmeta/kindsets.go`); read at upstream `1e05ae624` and the fork on
2026-10-19. When the in-process read is unavailable, the fork's fallback reads
pages of 5,000 rows; upstream does one capped read.

## `gc session new` and the canonical session

`gc session new <template>` resolves a bare name only when exactly one agent
of that name is city-scoped or in the current rig (`GC_DIR` or the working
directory); it never searches other rigs and does not take pool-instance
names. Input containing `/` or `.` must match a qualified name exactly, and
inside a rig dotted input is tried as `<rig>/<input>` first. So outside a rig
a rig-scoped template needs `<rig>/<binding>.<template>`, and inside a rig an
unscoped city import exists twice and its bare name is ambiguous. A miss
prints `agent "<x>" not found in city.toml` with a did-you-mean, an
import-install hint, or the agent list.

What it creates depends on the template. For an unbound named session whose
name is the agent's own, `gc session new` without `--alias` claims the
canonical alias and runtime name, and is refused while the canonical session
is live. For a binding-imported named session, or with `--alias`, it creates
a separate `manual` session. A multi-session template with no `--alias` or
`tmux_alias` gets the session name `<bare-template>-adhoc-<10-char key>` and
no alias; a single-session template gets `s-<bead id>`.

*Evidence:* `resolveSessionTemplate` (`cmd/gc/cmd_session.go`),
`agentNotFoundMsg` (`cmd/gc/suggest.go`), `sessionNewAliasOwner` and
`sessionExplicitNameForNewSession` (`cmd/gc/cmd_session.go`),
`GenerateAdhocExplicitName` (`internal/session/names.go`), read at upstream
`1e05ae624` and the fork on 2026-10-19. The session model says a bare name
resolves against city scope plus the current rig when one config matches.

### Duplicate named-session via manual spawn

Session lookup resolves an exact id, then an open session name, then an open
alias, with no template fallback. The configured-named conflict guard fires
only when a live bead already holds the canonical runtime name or uses the
identity as its alias. A manual session under an ad-hoc name holds neither, so
a nudge to the canonical alias still materializes the canonical session beside
it, and two live sessions then serve one agent.

That is a work-ownership problem, not a cosmetic one. A named singleton's
bead `assignee` is the agent's identity, so every live session of the agent
that resolves it sees the same bead: a recovery sweep by assignee returns it
in each, each tries to drive it, and `bd update --claim` is an atomic
transition, not a lock. Closing the bead is the only mutex. Re-read before
writing, append rather than replace, and collapse to one session with
`gc session close` — converging on the canonical one, the identity that is not
recycled out from under long work.

*Evidence:* `resolveSessionID` (`internal/session/resolve.go`),
`resolveConfiguredNamedSessionID` and `errNamedSessionConflict`
(`cmd/gc/session_resolve.go`), read at upstream `1e05ae624` and the fork on
2026-10-19.

## Nudge fences: a queued nudge can die without a word

`wake_mode = "fresh"` bumps a session's `continuation_epoch` on every wake
after the first, and any wake mode bumps it while a conversation reset is
pending; the config loader warns, without failing, on `mode = "always"` with
`"fresh"`. A queued nudge is fenced to its target's session and epoch, and
the fence decides its fate at claim time:

- An item that names no session is admitted, unless it carries an epoch and
  the target has none.
- An item fenced to a session is admitted only for that session, or when that
  session is no longer live and the target is.
- A rejected item fails with `errNudgeSessionFenceMismatch` and is
  dead-lettered on its first attempt, with no retry and no word to the sender.
- A nudge sourced from a wait is withdrawn unless its wait is still ready.

So silence after a nudge is evidence about the queue before it is evidence
about the target, and a design that reads a nudge reply as proof of life can
condemn a healthy session. Prefer signals that need no reply — a bead's
`updated_at` advancing, pane text changing — and before concluding anything
from silence, check `gc nudge status` for the nudge's state.

*Evidence:* `shouldBumpContinuationEpoch` (`cmd/gc/session_wake.go`),
`IsAlwaysFreshWakeModeWarning` (`internal/config/config.go`),
`splitQueuedNudgesForTarget`, `refencedQueuedNudge` and
`blockedQueuedWaitNudgeReason` (`cmd/gc/cmd_nudge.go`),
`queuedNudgeClaimableForTarget` and `failedQueuedNudge`
(`cmd/gc/nudge_file_queue.go`), read at upstream `1e05ae624` and the fork on
2026-10-19. Upstream's CLI reference documents the queue and dead letters
(`gc nudge status`, `gc nudge drop`), not the fence.

## Which fields name a bead's holder

A bead's holder is not always its `assignee`. A workflow step carries none and
names its session in `metadata.gc.session_id`, which
`gc.session_affinity=require` pins it to; a workflow root names only
`metadata.gc.session_name`. The id is re-stamped on every claim, so it always
names the session actually holding the bead; the assignee and the session
name are labels a successor inherits, because pool work is assigned to the
slot and the slot stays live under its next occupant. Two listed sessions can
carry one key — a pool slot's agent name outlives each occupant, and when a
named session's create fails, Gas City hands its alias to the session that
replaces it — and `gc session list` lists the newest session first.

*Evidence:* read on the fork on 2026-08-31 and 2026-10-12, when gc-toolkit's
owner lookup was built on these fields; not re-read on 2026-10-19. The pack's
rule on them is [pack-authoring.md](pack-authoring.md#a-scan-resolves-an-owner-before-it-calls-one-absent).

## Refresh procedure

Each section's evidence line names what it was read from and when. Before
building on a section, re-read its symbols at current upstream main and in
this city's fork, and update the date with the reading; a fork-only behavior
is re-checked against upstream too. When upstream's docs come to state a
section's fact, replace the section with a line in "What upstream's docs
already say". A section that documents a defect with a tracked fix does not
belong here: it lives on its bead until the fix lands.
