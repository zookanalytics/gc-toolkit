---
name: Gas City agent types
description: Reference for the agent variants Gas City supports — identity model, lifecycle, addressing, work routing, and the footguns each one has paid for. Companion to gascity-routing-model.md.
---

# Gas City agent types

This doc is the single-page reference for the agent *variants*
Gas City supports, and the contracts for addressing, spawning,
terminating, and routing work to each. Upstream Gas City tutorials
([02-agents](https://docs.gascityhall.com/tutorials/02-agents),
[03-sessions](https://docs.gascityhall.com/tutorials/03-sessions))
introduce the primitives. This doc consolidates the variants and
the corners that show up only when you mix them — `[[named_session]]`
duplicates, pool routing vs. assignee routing, thread instances vs.
canonical singletons, and the addressing form `gc session new`
actually accepts.

When in doubt about *routing* — `assignee` vs `gc.routed_to` vs
`--reassign` — read [gascity-routing-model.md](gascity-routing-model.md).
This doc covers *who* the agents are; that doc covers *how* work
moves between them.

## Scope

**Mandate.** The single-page reference for the agent *variants* Gas
City supports — what each one is, and how each is identified and run. It
captures the corners that surface only when those variants mix and the
footguns they have already cost.

**Boundaries.** This doc covers *who* the agents are, not *how* work
moves between them — the routing model is
[gascity-routing-model.md](gascity-routing-model.md). It does not cover
prompt-template authoring or any single agent's role behavior.

## Variants at a glance

| Variant | Configured by | Singleton? | Auto-spawned? | Routed work? | Examples |
|---|---|---|---|---|---|
| **Named singleton — `on_demand`** | `[[named_session]] mode = "on_demand"` | yes (per scope) | on first nudge or pre-assigned work | no — Tier 3 skipped | refinery, gascity-keeper |
| **Named singleton — `always`** | `[[named_session]] mode = "always"` | yes (per scope) | yes, kept alive | no — Tier 3 skipped | mayor, deacon, boot, witness, mechanik (gc-toolkit) |
| **Patrol (overlay)** | named singleton + patrol-cycle prompt (4-tier startup, pour-before-burn) | yes — runs as the underlying named singleton | yes, as underlying named | no — Tier 3 skipped; patrol wisps are produced, not consumed via routed queue | deacon, witness, refinery |
| **Pool worker** | `min_active_sessions`/`max_active_sessions`, optional `scale_check` | no, N instances | yes, scaled by demand | yes — Tier 3 fires for `ephemeral` origin | polecat, dog |
| **Thread (operator-spawned)** | agent with `work_query = "printf '[]'"` + `sling_query` that exits non-zero | no, N instances | never (work query is a stub) | no | mayor-thread, mechanik-thread |
| **Manual** | `gc session new <template>` | no — just a session_origin | no — operator initiates | depends on the agent's variant | any template invoked this way |

"Singleton" here means **at most one canonical session per scope**.
The runtime *attempts* to enforce singleton-ness, but the
guarantee is best-effort — see [gc-8p3dnt
footgun](#duplicate-named-session-via-manual-spawn) below.

## Identity model

Every agent has three identity strings the CLI cares about, plus
a runtime tmux-session name the controller assigns. Getting them
straight matters because `gc session nudge`, `gc mail send`,
`gc session new`, `bd update --assignee`, and `gc.routed_to`
each accept a *different* one of these forms.

### The four strings

```
                         binding name (import key)
                         │
   [scope dir]/[binding].[template]
   gc-toolkit / gc-toolkit . polecat
   │           │           └─ Template     (TOML: `template = "..."`)
   │           └─ BindingName              (TOML: `[rigs.imports.<key>]`)
   └─ Dir / Scope                          (TOML: `scope = "city"|"rig"`)
```

| String | Source | Where it appears |
|---|---|---|
| **Template** | `name = "..."` in `agent.toml`, or `template = "..."` in `[[named_session]]` | TOML, log lines |
| **QualifiedName** (a.k.a. "alias") | computed: `<dir>/<binding>.<template>` (or `<dir>/<template>` for non-imported, or just `<template>` if not scoped) | `gc session nudge`, `gc mail send`, `bd update --assignee`, `gc.routed_to` |
| **PoolName** | set during pool expansion — same as QualifiedName for pool *templates*; pool *instances* get `<qualified>-<N>` | `gc.routed_to` for pool workers |
| **Runtime session name** | `NamedSessionRuntimeName(city, workspace, qualifiedName)` | tmux pane title, `$GC_SESSION_NAME` |

Source for the computation: `NamedSession.QualifiedName()` in
`rigs/gascity/internal/config/config.go`, around the
`NamedSession` struct definition.

### Worked example — the gc-toolkit polecat

Pack file — the gastown pack's `agents/polecat/agent.toml`. The
gastown pack is consumed as a pinned module import
(`github.com/gastownhall/gascity-packs`, wired via `[imports.gastown]`
in `rigs/gascity/examples/gastown/pack.toml`), so its agent templates
live in the module rather than the city tree:

```toml
scope = "rig"
work_dir = ".gc/worktrees/{{.Rig}}/polecats/{{.AgentBase}}"
min_active_sessions = 0
max_active_sessions = 5
```

City imports it into the gc-toolkit rig (in `city.toml`):

```toml
[[rigs]]
name = "gc-toolkit"

[rigs.imports.gc-toolkit]
source = "rigs/gc-toolkit"
```

Resulting identities for the polecat pool in the gc-toolkit rig:

| String | Value |
|---|---|
| Template | `polecat` |
| BindingName | `gc-toolkit` |
| Dir / Scope | `gc-toolkit` (rig name) |
| QualifiedName | `gc-toolkit/gc-toolkit.polecat` |
| Pool instance names | `gc-toolkit/gc-toolkit.polecat-1`, `…-2`, … |
| Runtime tmux name | derived per-instance (`gc-toolkit-polecat-1`, …) |

The doubled `gc-toolkit/gc-toolkit.` reads odd because the **scope
dir** and the **import binding** happen to share a name in our
setup. They are different segments — see the
[gc session new template addressing](#gc-session-new-requires-the-fully-qualified-form)
footgun below for why this matters.

### Worked example — a city-scoped named singleton

```toml
# rigs/gc-toolkit/pack.toml
[[named_session]]
template = "mechanik"
scope = "city"
mode = "always"
```

| String | Value |
|---|---|
| Template | `mechanik` |
| Scope | `city` (no scope-dir prefix) |
| BindingName | `gc-toolkit` (import binding) |
| Dir | `""` (city scope leaves Dir empty) |
| QualifiedName | `gc-toolkit.mechanik` |

Verify live: `gc session list` shows the alias `gc-toolkit.mechanik` —
no leading `<dir>/` segment, because `NamedSession.QualifiedName()`
only prepends `Dir` when non-empty
(`rigs/gascity/internal/config/config.go`). Rig-scoped sessions get
the rig name as Dir (see the polecat example above); city-scoped
sessions do not.

## Variant A — Named singletons (`[[named_session]]`)

The named-singleton contract is "at most one of these is running."
Configured by adding a `[[named_session]]` stanza to a pack or
city config. Validated in `validateNamedSessions`
(`rigs/gascity/internal/config/config.go`).

```toml
[[named_session]]
template = "<agent-name>"  # required; references an agent template
name = "<override>"        # optional; overrides public identity
scope = "city" | "rig"     # default: "city"
mode = "on_demand" | "always"  # default: "on_demand"
```

### Identity

QualifiedName composes from `Dir` and `IdentityName` after import
expansion:

- **Rig-scoped** (`scope = "rig"`): Dir is the rig name, so
  QualifiedName is `<rig>/<binding>.<identity>` (e.g.,
  `gc-toolkit/gc-toolkit.witness`).
- **City-scoped** (`scope = "city"`): Dir is `""`, so QualifiedName
  is just `<binding>.<identity>` (e.g., `gc-toolkit.mechanik`,
  `gc-toolkit.mayor`).

`NamedSession.QualifiedName()` only prepends `Dir + "/"` when `Dir`
is non-empty; everywhere you address a city-scoped singleton (nudge,
mail, `--assignee`, `gc.routed_to`), use the bare
`<binding>.<identity>` form. See the worked examples above.

### Lifecycle

The controller's reconciler evaluates desired state every
`daemon.patrol_interval` (default 30s). For named singletons:

| Mode | Desired state when no work | Desired state when work appears |
|---|---|---|
| `on_demand` | not materialized (sleeping at most) | spawn the canonical session |
| `always` | spawn and keep alive, regardless of work | spawn and keep alive |

**Sleep policy.** `mode = "always"` is incompatible with
`sleep_after_idle` on the backing agent; the config loader rejects
the combination at validation time. Always-mode also cannot exceed
the agent's `max_active_sessions`. Both checks live in
`validateNamedSessions`
(`rigs/gascity/internal/config/config.go`).

**Termination.** Operator-driven: `gc session close <session-id>`
both stops the runtime AND closes the session bead atomically.
`gc session kill` stops the tmux pane but leaves the session bead
active, so the reconciler may restart it on its next patrol —
prefer `close` when you mean *done*. See [kill vs. close
footgun](#gc-session-kill-vs-close).

### Addressing

```bash
# Wake / send a nudge to a city-scoped canonical singleton.
gc session nudge gc-toolkit.mechanik "..."

# Mail to the canonical singleton.
gc mail send gc-toolkit.mechanik -s "..." -m "..."

# Direct work assignment (Lane 2 — see gascity-routing-model.md).
bd update tk-abcde --assignee gc-toolkit.mechanik

# Rig-scoped singletons keep the rig name as a prefix.
gc session nudge gc-toolkit/gc-toolkit.witness "..."
```

All four commands expect the **QualifiedName** form — the alias
shown in `gc session list`. The rule is the same for both scopes:
the address is exactly what `NamedSession.QualifiedName()` computes
(see [Identity](#identity)). Bare template names (without the
binding prefix) do not match; for the `gc session new` template form
see the [addressing footgun](#gc-session-new-requires-the-fully-qualified-form).

### Work routing visibility

Named singletons run their `gc hook` work query with
`$GC_SESSION_ORIGIN=named`. The Tier 3 routed-pool tier is gated
to `ephemeral` (or empty) origins only — named singletons see
only **Tier 1** (in-progress, crash recovery) and **Tier 2**
(ready, pre-assigned) work. Routing work to a named singleton
must use `bd update --assignee`, not `gc.routed_to`. See [Work
routing](#work-routing) and
[gascity-routing-model.md](gascity-routing-model.md) for the
lane breakdown.

### Examples in the wild

From the gastown pack's `pack.toml` (`github.com/gastownhall/gascity-packs`,
imported via `rigs/gascity/examples/gastown/pack.toml`):

```toml
[[named_session]]
template = "mayor"
scope = "city"
mode = "always"

[[named_session]]
template = "deacon"
scope = "city"
mode = "always"

[[named_session]]
template = "boot"
scope = "city"
mode = "always"

[[named_session]]
template = "witness"
scope = "rig"
mode = "always"

[[named_session]]
template = "refinery"
scope = "rig"
mode = "on_demand"
```

`refinery` is the lone `on_demand` in the gastown base — it's
expected to be up while a merge queue has work, otherwise allowed
to sleep. Everything else in the base set is `mode = "always"`.

## Variant B — Pool workers

A pool worker is an agent whose template carries
`min_active_sessions` / `max_active_sessions`, optionally with a
`scale_check` script the controller runs to size the pool. There
is no `[[named_session]]` declaration — each pool instance is a
distinct ephemeral session.

### Identity

Pool *template* QualifiedName: `<dir>/<binding>.<template>`
(e.g., `gc-toolkit/gc-toolkit.polecat`).

Pool *instance* names: `<qualified>-<N>` where N is a per-pool
slot index assigned by the controller during desired-state
expansion. Instances are ephemeral — they can die and be
respawned at a different N within the same template.

### Lifecycle

- **Spawn.** Controller's reconciler reads `scale_check` (if
  present) or applies `min_active_sessions`, clamps to
  `[min, max]`, then expands or contracts the live pool to match.
- **Claim.** Each instance picks up work via its `gc hook` query
  (see [Work routing](#work-routing) below).
- **Drain / scale-down.** When desired count drops below current
  count, the controller drains the excess instances. The instance
  finishes its current bead, calls `gc runtime drain-ack`, and
  exits; the controller does not interrupt mid-bead.
- **Termination per instance.** Workers terminate themselves at
  the end of their work cycle (e.g., polecat's done sequence ends
  with `gc runtime drain-ack && exit`). Operator can force with
  `gc session close <session-id>`.

### Addressing

Pool workers **do not have a canonical session** — there is no
"the polecat" to nudge. Address by:

| Want to... | Form |
|---|---|
| Reach a specific live instance | `gc session nudge <session-id>` or `<instance-name>` |
| Route work to the pool | `gc sling <pool-qualified-name> <bead>` → sets `gc.routed_to = <pool-name>` (Lane 1) |
| Pre-assign work to a specific instance | `bd update <bead> --assignee <instance-name>` (Lane 2) |

`gc mail send <pool-qualified-name>` writes a mail bead addressed
to the pool *template*; the underlying delivery routes it to the
pool inbox visible to any live instance, not to a specific
session.

### Work routing visibility

Pool instances run with `$GC_SESSION_ORIGIN=ephemeral`, so all
three hook tiers fire:

1. **Tier 1** — `bd list --status=in_progress
   --assignee=<my-id-or-name-or-alias>` (crash recovery)
2. **Tier 2** — `bd ready --assignee=<...>` (pre-assigned)
3. **Tier 3** — `bd ready --metadata-field
   gc.routed_to=<pool-qualified-name> --unassigned` (the routed
   pool queue — this is what `gc sling` writes to)

The Tier 3 target is the pool's QualifiedName (set as `PoolName`
during expansion), not the instance name — that is how
`gc sling gc-toolkit/gc-toolkit.polecat <bead>` reaches any free
worker in the pool.

### Examples in the wild

`polecat` (gastown base):

```toml
# gastown pack (github.com/gastownhall/gascity-packs): agents/polecat/agent.toml
scope = "rig"
wake_mode = "fresh"
work_dir = ".gc/worktrees/{{.Rig}}/polecats/{{.AgentBase}}"
nudge = "Run gc hook; it checks assigned work first, then routed pool work."
pre_start = ["{{.ConfigDir}}/assets/scripts/worktree-setup.sh {{.RigRoot}} {{.WorkDir}} {{.AgentBase}} --sync"]
idle_timeout = "2h"
min_active_sessions = 0
max_active_sessions = 5
```

`dog` (gastown base):

```toml
# gastown pack (github.com/gastownhall/gascity-packs): agents/dog/agent.toml
scope = "city"
idle_timeout = "2h"
min_active_sessions = 0
max_active_sessions = 3
```

## Variant C — Threads (operator-spawned only)

Thread agents are regular agents with their `work_query` and
`sling_query` stubbed so the controller never auto-spawns them
and `gc sling` never routes to them. They exist for operator-
initiated parallel reasoning at the same scope as a canonical
agent — e.g., a second mayor instance the operator nudges
through a focused planning task without disturbing the canonical
mayor's coordination state.

```toml
# rigs/gc-toolkit/agents/mayor-thread/agent.toml
work_query = "printf '[]'"
sling_query = "echo 'mayor-thread is operator-spawned only; not a sling target' >&2; exit 1"
```

### Identity

Thread agents inherit their canonical's scope (see [Threads do not
change agent scope](#threads-do-not-change-agent-scope) below) —
both checked-in thread agents (`mayor-thread`, `mechanik-thread`)
declare `scope = "city"`, matching their canonicals.

- Template name: `mayor-thread`, `mechanik-thread`, …
- Template QualifiedName: `<binding>.<template>` for city-scoped
  threads (e.g., `gc-toolkit.mayor-thread`); rig-scoped would prefix
  the rig name.
- Per-instance alias: `<binding>.<template>-adhoc-<id>` (city) or
  `<rig>/<binding>.<template>-adhoc-<id>` (rig). Verify via
  `gc session list`.
- Per-instance AgentBase: assigned at spawn, drives
  `work_dir = ".gc/agents/<template>/{{.AgentBase}}"` so parallel
  threads don't collide in their scratch dirs.

### Lifecycle

- **Spawn.** Operator runs
  `gc session new <scope>/<pack>.<thread-template>` with an
  optional name. Session metadata gets
  `session_origin = "manual"`.
- **Run.** The thread reads its prompt and follows operator
  nudges. It can send mail and read mail like any other agent,
  but its hook will never find auto-routed work.
- **Termination.** Operator-driven: `exit` from inside, or
  `gc session close <session-id>` from outside.

### Threads do not change agent scope

A thread runs at the same scope as its canonical counterpart.
A mayor-thread is city-scoped because mayor is city-scoped; a
hypothetical witness-thread would be rig-scoped. The
`<role>-thread` suffix marks the variant; it does **not** rebind
the scope.

### Addressing

```bash
# City-scoped thread (current mayor-thread / mechanik-thread).
gc session new gc-toolkit.mayor-thread --alias my-focus-thread
# spawns gc-toolkit.mayor-thread-adhoc-<id>, returns the session name

gc session nudge gc-toolkit.mayor-thread-adhoc-<id> "..."  # specific instance
gc mail send gc-toolkit.mayor-thread-adhoc-<id> -s "..." -m "..."
```

A rig-scoped thread (if one existed) would spawn from the
`<rig>/<binding>.<template>` form instead; see [gc session new
addressing footgun](#gc-session-new-requires-the-fully-qualified-form).

`gc sling <thread-qualified-name> <bead>` is explicitly rejected
by the thread's `sling_query` stub.

## Variant D — Patrol agents (overlay)

Patrol agents are **not** a distinct configuration variant. They
are named singletons (Variant A) whose prompt template adds a
patrol-wisp cycle on top of the standard lifecycle. Deacon,
witness, and refinery are the patrol agents in the gastown base —
each `[[named_session]]` declares them like any other singleton,
but their prompts (and the `propulsion-deacon`, `propulsion-witness`,
`propulsion-refinery` fragments in the gastown pack's
`template-fragments/propulsion.template.md`) implement the patrol
contract described below.

This is called out as its own variant because the contract has
substantial mechanics that pool workers and threads do not have,
and because regressions in this contract show up as
missed-MERGE_READY and stale-patrol incidents (`tk-fyzvk`,
`tk-6hm32`, `tk-yvtiv`).

### Patrol wisps

Each patrol cycle is a single bead — a **patrol wisp** — owned by
the agent. The wisp is created at cycle start, status flips through
`in_progress` while the agent works, and it is closed when the
cycle completes. The next cycle pours a fresh wisp before burning
the old one (**pour-before-burn**), so the agent always has a
discoverable hook.

Patrol wisps are **root-level**: they are not sub-beads of a
parent workflow molecule. Each cycle is its own root.

### Startup discovery (4-tier)

When a patrol agent starts (boot, restart, or recovery), it walks
four tiers before pouring a fresh wisp. The first tier that returns
work wins:

1. **In-progress wisp** — `bd list --status=in_progress
   --assignee=$GC_AGENT`. Crash recovery: pick up where you left
   off mid-cycle.
2. **Routed work bead** — `bd ready --has-metadata-key=branch
   --assignee=...`. Catches work that arrived during a
   cycle-recycle window (e.g., operator `/clear`).
3. **Open patrol wisp** — adopt the newest OPEN patrol wisp owned
   by this agent; close older duplicates as
   `orphaned cross-rotation`. Covers wisps that survived a
   rotation without being claimed.
4. **Fresh pour** — only when 1-3 are empty. Create a new patrol
   wisp and claim it `in_progress`.

This shape is enforced at pack-validate time by
`doctor/check-startup-discovery/`; if `gc doctor` flags a patrol
agent's prompt as missing tier 2 or 3, expect missed-MERGE_READY-
style stalls. The reference implementation lives in
`agents/refinery/prompt.template.md` and
`agents/deacon/prompt.template.md`.

### Lifecycle

Beyond what the underlying named singleton provides:

- **Restart-friendly.** A patrol agent can be killed mid-cycle
  without losing work — tier-1 recovers via the `in_progress`
  wisp. Use `gc runtime request-restart` (preferred) or
  `gc session reset` when a refresh is needed; `gc session kill`
  also works for patrols because the reconciler will respawn and
  the new instance will adopt the in-flight wisp via tier 1.
- **Handoff.** Patrols do not need explicit operator-driven
  handoff — the next cycle is the handoff. Closing the current
  wisp and the cycle-recycle behavior in the prompt template
  together carry the cadence.
- **Health.** Patrol freshness is checked by deacon's own patrol
  (`mol-deacon-patrol.toml`): a stale patrol wisp on witness or
  refinery surfaces as a deacon warning. The reconciler also
  surfaces patrol agents that are alive-but-stuck via
  `gc doctor` checks.

### Addressing

Same as the underlying named singleton — patrols use the same
QualifiedName (`<rig>/<binding>.<template>` for the rig-scoped
witness/refinery, `<binding>.<template>` for the city-scoped
deacon). See [Variant A — Named singletons](#variant-a--named-singletons-named_session).

### Work routing visibility

Same Tier 1 + Tier 2 gating as named singletons —
`$GC_SESSION_ORIGIN=named` skips Tier 3 routed pool. Patrol wisps
are *produced* by the patrol cycle itself (Tier 1 / Tier 2 hits),
not consumed from the routed pool. Outside work that needs a
specific patrol agent to act should use `bd update --assignee
<patrol-qualified-name>` (Lane 2), not `gc sling` — same rule as
any named singleton.

### Examples in the wild

- **Deacon** (`gc-toolkit.deacon`, city-scoped, `mode = "always"`):
  cross-rig gate checks, convoy dispatch, stuck-agent escalation.
  Patrol cycle: `mol-deacon-patrol.toml`.
- **Witness** (`<rig>/gc-toolkit.witness`, rig-scoped,
  `mode = "always"`): per-rig orphan worktree salvage, stuck polecat
  detection, missing-bead-owner surfacing.
- **Refinery** (`<rig>/gc-toolkit.refinery`, rig-scoped,
  `mode = "on_demand"`): merge queue processor; patrol cycle pours
  per merge-queue iteration.

## session_origin: ephemeral vs. manual vs. named

`session_origin` is metadata the runtime stamps on each session
based on how it was created. It is not configured per-agent — it
records the *birth path*.

| Value | Set by | Used for |
|---|---|---|
| `ephemeral` | controller spawned this session in response to demand (pool worker scaling up, on-demand named singleton waking) | Tier 3 routed-queue access (this is the only origin allowed to consume `gc.routed_to`) |
| `manual` | operator ran `gc session new <template>` | thread spawn, ad-hoc named-template spawn; **not** allowed to consume Tier 3 |
| `named` | controller spawned the canonical session for a `[[named_session]]` declaration | named singletons; **not** allowed to consume Tier 3 |

The Tier 3 gating is the practical effect to know:
**only `ephemeral` sees the routed pool queue.** If you create a
manual session against a pool template, its hook runs but won't
pick up `gc sling`-routed work. Route work to manual sessions
via `bd update --assignee` instead.

Source: `Agent.EffectiveWorkQuery()` in
`rigs/gascity/internal/config/config.go`:

```go
// Tier 3: ready unassigned routed to this config (shared routed queue).
// Only ephemeral sessions and controller probes consume generic config demand.
case "$GC_SESSION_ORIGIN" in
    ephemeral|"") ;;
    *) exit 0 ;;
esac
```

The empty-string branch covers controller probes (no session
context), which is how demand-driven spawn works: the reconciler
runs the same query without any `GC_SESSION_*` vars set,
"detects" the routed bead, and uses that as the signal to
materialize a new instance.

## Work routing

Three tiers, in order; the first non-empty result wins:

| Tier | Query | Who sees it | What it routes |
|---|---|---|---|
| 1 | `bd list --status=in_progress --assignee=<my-ids>` | every session | crash recovery — work this session was running before it died |
| 2 | `bd ready --assignee=<my-ids>` | every session | pre-assigned work (`bd update --assignee <me>`) |
| 3 | `bd ready --metadata-field gc.routed_to=<target> --unassigned` | only `$GC_SESSION_ORIGIN ∈ {ephemeral, ""}` | the routed pool queue (`gc sling <target>` writes here) |

`<my-ids>` is the union of `$GC_SESSION_ID` (the session bead
ID), `$GC_SESSION_NAME` (the tmux session name), and `$GC_ALIAS`
(the QualifiedName / configured identity). Hook checks all
three so work assigned via any of them is found.

`<target>` is the agent's QualifiedName (for non-pool agents) or
PoolName (for pool agents). Set during config expansion in
`Agent.EffectiveWorkQuery()`.

For the routing *mechanics* (when to use `gc sling`, when to use
`bd update --assignee`, when to use `--reassign`), read
[gascity-routing-model.md](gascity-routing-model.md). This doc
only covers *what each variant can see*.

## Command vs. variant matrix

The "address as" column gives the form you should pass to the
command. "✗" means the operation is not meaningful for the
variant (and either errors or is a no-op). Patrol agents
(Variant D) are not a separate column — they address identically
to named singletons (their underlying variant); see
[Variant D — Patrol agents](#variant-d--patrol-agents-overlay) for
the cycle-level mechanics that the matrix does not capture.

| Command | Named singleton | Pool worker | Thread |
|---|---|---|---|
| `gc session nudge <addr>` | QualifiedName | session-id or instance name | session name (e.g., `…-adhoc-<id>`) |
| `gc session new <template>` | QualifiedName — spawns a `manual`-origin session *alongside* the canonical, see [singleton footgun](#duplicate-named-session-via-manual-spawn) | QualifiedName — spawns an extra instance | QualifiedName + optional name |
| `gc session close <id>` | session bead ID (atomically stops runtime + closes bead) | session bead ID | session bead ID |
| `gc session kill <id>` | session bead ID (stops tmux only; reconciler may restart) | session bead ID | session bead ID |
| `gc session reset <id>` | session bead ID | session bead ID | session bead ID |
| `gc session wake <addr>` | session id or alias (QualifiedName works since alias == QualifiedName); **clears holds + requests a start — not a durable reason to stay up**, see [the keeper front-door](#the-gascity-keeper-front-door) | session id or instance alias — **not** the pool QualifiedName | session id or adhoc alias |
| `gc session pin <addr>` | session id or alias; durable awake hold (materializes the canonical if not yet started) | session id or instance alias | session id or adhoc alias |
| `gc session unpin <addr>` | session id or alias; removes the pin, reconciler re-applies wake/sleep | session id or instance alias | session id or adhoc alias |
| `gc session list` | shows canonical alias | shows each instance | shows each adhoc instance |
| `gc session peek <id>` | session bead ID | session bead ID | session bead ID |
| `gc session wait <id>` | session bead ID | session bead ID | session bead ID |
| `gc mail send <addr>` | QualifiedName | QualifiedName (pool inbox) or instance name | adhoc session name |
| `gc mail read <id>` | mail bead ID | mail bead ID | mail bead ID |
| `gc mail archive <id>` | mail bead ID | mail bead ID | mail bead ID |
| `gc mail reply <id>` | mail bead ID | mail bead ID | mail bead ID |
| `gc mail inbox` | reads `assignee=<my-ids>` | reads `assignee=<my-ids>` | reads `assignee=<my-ids>` |
| `bd update <bead> --assignee <addr>` | QualifiedName (Lane 2) | instance name (Lane 2; usually unwanted for pool work — prefer sling) | adhoc session name |
| `bd update <bead> --set-metadata gc.routed_to=<target>` | ✗ — singleton ignores Tier 3 | QualifiedName / PoolName (Lane 1) | ✗ — work_query stub ignores Tier 3 |
| `gc sling <target> <bead>` | ✗ — singleton ignores Tier 3 (use `bd update --assignee`) | QualifiedName / PoolName (Lane 1) | ✗ — sling_query exits non-zero |
| `gc runtime drain <addr>` | session id or alias | session id or instance alias (no pool-level drain — drain each instance, or shrink `max_active_sessions` in config) | session id or adhoc alias |

Pool-wide drain (`gc agent drain`) was removed when the runtime
ops (`drain`/`undrain`/`drain-ack`/`request-restart`) moved out
of `gc agent` into `gc runtime`. The remaining `gc agent`
subcommands are config-level only: `add`, `list`, `resume`, and
`suspend`. `gc agent list` enumerates **configured** agents from
the resolved city configuration (pass `--json` to inspect
routing fields like the effective `work_query` and
`sling_query`) — distinct from `gc session list`, which
enumerates **live** sessions. To drain a specific session, use
`gc runtime drain <session-id-or-alias>` as shown above.

## Known footguns

### Duplicate named-session via manual spawn

**Bead:** `gc-8p3dnt` (closed "watch-don't-fix" 2026-05-22).
Concrete incident: keeper-adhoc (`lx-7ttxx`) and canonical
keeper (`lx-bnngr`) both alive, processing the same signal.

A `[[named_session]] template = "X"` declaration is a
*best-effort* singleton, not a hard one. The runtime keys
session lookup by **alias**, not template. If a manual session
already exists under an adhoc alias backed by template X, a nudge
to X's canonical alias misses it and spawns a *second* session.

Code path: alias-keyed resolution at
`internal/session/resolve.go` (no template fallback), and no
creation-time validation in the manual path at
`cmd/gc/cmd_session.go`. The bead's reopen conditions enumerate
when this would become worth fixing structurally; until then,
the contract is documented here.

**Detection.** `gc session list` shows both. The canonical alias
will be one; the manual one will have an `…-adhoc-<id>` suffix.

**Recovery.** `gc session close <one-of-them>` collapses to a
single live instance. Pick the one whose work-in-flight is less
important to preserve.

**Avoidance.** Before `gc session new <named-template>`, check
`gc session list` for a live instance of the same template.
Don't manually spawn against a template that already has a
canonical live.

### `gc session new` requires the fully qualified form

**Memory:** `feedback_session_new_template_addressing.md`

`gc session new` does **not** accept bare template names or even
`<pack>.<template>` for templates declared at the city level. It
requires the fully-qualified scope-prefixed form:
`<scope>/<pack>.<template>`.

```bash
gc session new gascity-keeper --rig gascity
# ❌ "agent not found, did you mean gascity/claude?"

gc session new gc-toolkit.gascity-keeper --rig gascity
# ❌ "did you mean gascity/gc-toolkit.gascity-keeper?"

gc session new gc-toolkit/gc-toolkit.gascity-keeper --rig gascity
# ✓ session created
```

The doubled segment is real — the first is the scope dir (where
the city-level `[[named_session]]` lives), the second is the
import binding name that introduced the agent. They happen to
match in our setup. **The "did you mean" hint in the error
message is authoritative — use whatever it suggests verbatim.**

### `gc session kill` vs. `close`

| Command | Stops runtime? | Closes session bead? | Reconciler restart risk? |
|---|---|---|---|
| `gc session kill <id>` | yes | no — bead stays active | yes — reconciler may patrol-respawn |
| `gc session close <id>` | yes | yes — atomically | no |

When you mean "this session should be gone for good," use
`close`. `kill` is for "stop the runtime but I want the
controller to consider this session still desired and respawn
it." If you `kill` a named singleton whose bead is still active,
the next reconciler patrol will materialize it again.

### Named singletons cannot consume routed (`gc.routed_to`) work

Named singletons run with `$GC_SESSION_ORIGIN=named`, which
skips the Tier 3 routed-pool query. If you `gc sling
<singleton-qualified-name> <bead>`, the bead gets stamped with
`gc.routed_to` but the singleton's hook will not see it.

Use `bd update <bead> --assignee <singleton-qualified-name>`
(Lane 2) instead. See [gascity-routing-model.md, Lane
2](gascity-routing-model.md#lane-2--bd-update-bead---assignee-named-session-direct-named-session-delivery).

### Pool workers cannot consume routed work in manual sessions

Same gate, other side. If you `gc session new <pool-template>`
to start a manual debugging session against a pool worker, it
will run with `session_origin = "manual"` and **not** see
Tier 3. Work routed via `gc sling` won't reach the manual
session. Pre-assign with `bd update --assignee
<manual-session-name>` if you want it to pick up specific work.

### Sub-pack `[[named_session]]` + city-level declaration = duplicate identity

**Memory:** `project_gascity_keeper_config_break.md`

If a sub-pack ships its own `[[named_session]]` with `scope =
"rig"`, the city must **not** also declare the same identity at
the city level. The loader reports "duplicate identity" and
refuses to start.

Fix shape (per `project_gascity_keeper_config_break.md`): remove
the city-level `[[named_session]]`, add `[rigs.imports.<sub-pack>]`
to the importing rig, and rely on the sub-pack's own declaration
to materialize with `scope = "rig"`.

### Threads do not change agent scope

A `<role>-thread` variant runs at the same scope as its
canonical counterpart. `mayor-thread` is city-scoped because
`mayor` is city-scoped. The `-thread` suffix is a behavioral
mode, not a scope override.

### Pool-instance race on simultaneous claim

**Memory:** `feedback_parallel_polecat_race.md`

Under load, two pool instances can resolve their hook query
nearly simultaneously and both attempt to claim the same bead.
The atomic `bd update --claim` transition prevents the loser
from progressing, but the loser may already have set up a
worktree before discovering it lost the race.

**Detection.** A bead's `metadata.work_dir` pointing to a
different polecat than the one you're running in. Verify peer
state before re-implementing — they may already be working on
it.

## The gascity-keeper front-door

The **gascity-keeper** (`gascity/gascity-keeper.keeper`) is the
operator's single front-door for the forked upstream repos
(`gastownhall/gascity`). It runs `on_demand` **on purpose**:
whether it is up is itself the signal — keeper **up** means you are
in upstream-engagement mode (a rebase or sync is hot), keeper
**down** means you are not thinking about upstream. Presence *is*
state; there is no separate dashboard to check.

**Bring it up / dismiss it — from the `S` picker.** A drained
on_demand session has no pane, so you cannot reach it by switching
to a pane. The `S` session picker therefore carries a fixed entry,
next to `[ show all ]`, that pins or unpins the keeper:

- keeper unpinned → `[ ⚡ pin keeper ]` → pins it; it materializes
  (if it was down) and, on the next picker open, shows up as a
  navigable pane you switch to like any other agent.
- keeper pinned → `[ ✕ unpin keeper ]` → unpins it; it drains once
  idle.
- `[ keeper… ]` → the pin state could not be read in time (beads
  slow or unreachable). The entry still toggles — it re-checks on
  selection and refuses only if the state is still unknown.

The label tracks the **pin**, not mere liveness: a keeper that is up
only because work sits on its hook is unpinned and still shows
`[ ⚡ pin keeper ]` — pinning it then keeps it up once that work
finishes. That entry is the surface — you do not run `gc session`
verbs by hand. It is wired to
`assets/scripts/tmux-keeper-toggle.sh`, which owns the pin/unpin
call and the pin-state detection (it reads the keeper session
bead's `metadata.pin_awake`; tmux liveness cannot distinguish
pinned from merely-working).

**Talk to it, or give it work.** Pin only when you want to
*converse* — surface a rebase summary, refine a PR draft, ask an
upstream question. If you only need a *job done* (rebase, sync,
PR-prep), don't pin — hand it the work, which is itself a wake
reason; it materializes, runs, surfaces any questions back to you,
and drains on its own:

```bash
bd update <bead> --assignee gascity/gascity-keeper.keeper   # Lane 2
```

### Lifecycle background

`gc session wake` does **not** keep the keeper up: it clears holds
and requests a start, but is not itself a durable reason to stay
up, so the reconciler drains the session again shortly after — the
"no-wake-reason" you see in the logs. The reconciler keeps a
session materialized only while one of these holds:

| Wake reason | Durable? | How |
|---|---|---|
| Work on the hook (a bead `assignee`'d to the agent) | yes — until the work is done | `bd update --assignee`, `gc sling` |
| A pin | yes — until you unpin | the `S`-picker entry (or `gc session pin`) |
| An active attach | **no** — drops the moment you detach, even to hop tmux windows | `gc session attach` |

A pin is still genuinely on-demand — *you* chose the window — and
is **not** the always-live `mode = "always"` config (see
[Lifecycle](#lifecycle)). The pin targets **the** canonical
session, the one whose alias equals the QualifiedName in
`gc session list`; reaching for `gc session new` instead spawns a
separate `…-adhoc-<id>` thread *alongside* it (the [duplicate
named-session footgun](#duplicate-named-session-via-manual-spawn)).
You don't need to create it first — pinning a not-yet-materialized
canonical session creates its bead so the reconciler can start it.

## Refresh procedure

This doc lives in `docs/` (central, authoritative). It is **not**
auto-generated. When the underlying contracts change, update
this file in the same PR as the change.

Signals that this doc needs a refresh:

- A new `[[named_session]]` `mode` or `scope` value lands
  upstream (`internal/config/config.go:NamedSession`).
- A new tier or condition appears in `Agent.EffectiveWorkQuery()`
  (currently three tiers; Tier 3 gated by `$GC_SESSION_ORIGIN`).
- A new variant emerges — e.g., something that is neither
  `[[named_session]]`, pool, nor operator-spawned thread.
- A new gc-toolkit auto-memory entry describes a contract-level
  footgun (not a one-off incident).

To audit drift against upstream, diff `NamedSession` and
`Agent.EffectiveWorkQuery()` since the last refresh:

```bash
git -C rigs/gascity log --since='<last refresh>' \
  -p -- internal/config/config.go \
  | grep -E '^\+.*NamedSession|^\+.*WorkQuery'
```

The memory entries cited above are point-in-time observations.
If you find one stale (the symptom no longer reproduces, or the
fix has been merged), update the memory entry and adjust the
footgun section here in the same PR.
