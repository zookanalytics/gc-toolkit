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
| **Deterministic worker (no prompt loop)** | `prompt_mode = "none"` + `start_command` + `max_active_sessions`; no `[[named_session]]` | in effect — capped at `max_active_sessions = 1` | yes, demand-scaled from zero | yes — but through its own serve-loop query, not the hook tiers | control-dispatcher (bundled core pack) |
| **Thread (operator-spawned)** | agent with `work_query = "printf '[]'"` + `sling_query` that exits non-zero | no, N instances | never (work query is a stub) | no | mayor-thread, mechanik-thread |
| **Bead-host (per-bead thread)** | thread stubs + `wake_mode = "resume"` and a long `idle_timeout`; alias *is* the bead id | yes — one per work bead, by alias uniqueness | never; created on demand by `tools/gc-bead-host.sh` | no — it *grounds* itself as the bead's `assignee` instead | bead-host |
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
   └─ Dir / Scope                          (TOML: `scope = "city"|"rig"`, or omitted)
```

`scope` is a *three*-state axis, not two: `"city"`, `"rig"`, or
**omitted**. Omitted is not a synonym for either one — see
[Scope is tri-state](#scope-is-tri-state-omitted-is-not-city) below.

| String | Source | Where it appears |
|---|---|---|
| **Template** | `name = "..."` in `agent.toml`, or `template = "..."` in `[[named_session]]` | TOML, log lines |
| **QualifiedName** (a.k.a. "alias") | computed: `<dir>/<binding>.<template>` (or `<dir>/<template>` for non-imported, or just `<template>` if not scoped) | `gc session nudge`, `gc mail send`, `bd update --assignee`, `gc.routed_to` |
| **PoolName** | set during pool expansion — same as QualifiedName for pool *templates*; pool *instances* get `<qualified>-<N>` | `gc.routed_to` for pool workers |
| **Runtime session name** | `NamedSessionRuntimeName(city, workspace, qualifiedName)` | tmux pane title, `$GC_SESSION_NAME` |

Source for the computation: `NamedSession.QualifiedName()` in
`rigs/gascity/internal/config/config.go`, around the
`NamedSession` struct definition.

**Two of these are per-session; two are not.** `$GC_SESSION_ID`
(the session bead ID) and the runtime session name identify *this
session*. Template and QualifiedName identify the *agent* — and
the session's alias (the QualifiedName for a named singleton, the
per-instance alias for a pool worker), exported as both
`$GC_ALIAS` and `$GC_AGENT` (`internal/session/lifecycle.go`,
`RuntimeEnvWithSessionContext`), is the identity that `gc sling`,
`bd update --assignee`, `gc.routed_to`, and `gc mail send` all
address. That split is why duplicate sessions are a
*work-ownership* problem and not merely a cosmetic one: bead
ownership keys on the agent, not the session — see [duplicate
named-session via manual spawn](#duplicate-named-session-via-manual-spawn).

### Scope is tri-state: omitted is not city

`scope` on a pack-defined `[[named_session]]` or on an `agent.toml`
takes three states, and the config loader accepts all three
(`validateNamedSessions` and the agent-scope enum both allow
`"city"`, `"rig"`, **or empty**):

| `scope` | Instantiated |
|---|---|
| `"city"` | city expansion only — one identity per city, `Dir` is `""` |
| `"rig"` | rig expansion only — one identity per rig, `Dir` is the rig name |
| *omitted* | **unscoped — both contexts**: kept at city scope *and* stamped out once per rig |

Omitting `scope` is not a shorthand for `"city"`. An unscoped entry
in a **city-level** pack (city-root `includes = [...]`, or
`[imports.<binding>]`) materializes twice over: `filterNamedSessionsByScope`
keeps it in the city expansion (`Dir` empty), and
`expandCityImportedNamedSessionsForRigs` *also* stamps a copy with
`Dir = <rig>` for every rig — it skips only `scope = "city"`. So one
stanza yields both `<binding>.<template>` and
`<rig>/<binding>.<template>` for each rig. `expandCityImportedAgentsForRigs`
and `filterAgentsByScope` do exactly the same for `agent.toml` scope.
All four live in `rigs/gascity/internal/config/pack.go`.

Two qualifiers on the fan-out:

- It is skipped for any rig that declares the same import binding
  itself (`rigDeclaresImportBinding`) — that rig gets the session
  through its own import instead of a stamped copy.
- It applies to *city-level* packs only. In a **rig-level** pack
  (a rig's own `includes = [...]`, or `[rigs.imports.<binding>]`)
  an unscoped entry is kept by rig expansion alone, so there it
  does behave like `scope = "rig"`.

The JSON-schema tag is `jsonschema:"enum=city,enum=rig"` — it
enumerates only the two explicit values, so neither the generated
schema nor `docs/reference/config.md`'s enum column reveals the
third state. Read the `Scope` field doc comments in
`internal/config/config.go` instead. If you want one identity, say
which one: write `scope` explicitly.

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
scope = "city" | "rig"     # optional; omit = unscoped (BOTH contexts), not "city"
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
- **Unscoped** (`scope` omitted): you get *both* of the above from
  the one stanza — a city identity `<binding>.<identity>` plus a
  `<rig>/<binding>.<identity>` per rig. "At most one canonical
  session" then holds per resulting identity, not once overall — an
  unscoped stanza reserves N+1 identities, not one. See
  [Scope is tri-state](#scope-is-tri-state-omitted-is-not-city).

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
(ready, pre-assigned) work. They still skip Tier 3, but routing
work to a named singleton no longer requires hand-stamping the
assignee: `gc sling <singleton-qualified-name> <bead>` detects
the singleton target and stamps `assignee=<target>` alongside
`gc.routed_to`, so the bead surfaces via the singleton's Tier 2
(`bd ready --assignee`) query. `bd update <bead> --assignee` is
still valid and equivalent. See [Work routing](#work-routing) and
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

**Slot identities recur in every rig the binding serves.** A pool
binding imported into several rigs is stamped out once per rig (see
[Scope is tri-state](#scope-is-tri-state-omitted-is-not-city)), and
each rig's expansion allocates the same slot identities.

The **fully qualified** instance name does tell those apart — its
`<dir>` segment is the rig, as in `gc-toolkit/gc-toolkit.polecat-1`.
What recurs is everything *after* that segment: the agent base
(`{{.AgentBase}}`) and the `-<N>` slot suffix carry no rig, so the
bare `gc-toolkit.polecat-1` names a *different* live session in every
rig the pool serves.

That distinction matters because the rig-free part is what most
surfaces show you. The worktree path is templated
`work_dir = ".gc/worktrees/{{.Rig}}/polecats/{{.AgentBase}}"` — only
the `{{.Rig}}` segment varies — so an equivalent path exists under
every rig the slot has served, and those directories persist after
the work moves on. A worktree under rig R is therefore evidence that
the slot *once* served R, not that it is serving R **now**.

So a pool worker's **rig-free slot identity does not identify which
rig's store its work bead lives in**, and neither does the mere
existence of its worktree under a given rig. Only a **live**
session's `work_dir` names the rig it is currently serving. This cuts
both ways:

- **Benign direction.** A pool session reading `active` while *this*
  rig's store shows zero assigned or in-progress work is almost always
  serving another rig, with its work bead and worktree in that rig's
  store. Not a spawn storm, not a stuck worker — confirm by peeking
  which rig that live session's `work_dir` names.
- **Dangerous direction.** A liveness check that enumerates only one
  rig's sessions and matches them against a rig-free base returns "no
  owner" for a slot that is alive in another rig. That false-clean is
  what green-lights a destructive worktree prune. Build the liveness
  map **unscoped across all rigs** before calling any worktree
  ownerless, and key worktree cleanup on the live **`work_dir` path**,
  re-verified immediately before removal — never on "the identity is
  dead".

**The runtime session name is not rig-qualified either, so counting by
it conflates rigs.** The slot alias above is one recurring string; the
**runtime session name** — `$GC_SESSION_NAME`, and the `session_name`
field of `gc session list` — is a second, and it carries the **pack**
prefix rather than the rig. Every polecat is named
`gc-toolkit__polecat-<id>` (see [the four strings](#the-four-strings))
whether it serves the `gc-toolkit` rig or the `shutupandlisten` rig; the
`gc-toolkit__` segment names the pack it came from, not the rig it
works. The trap is that the rig-scoped **singletons** *are* rig-qualified
in their runtime name (`gascity--gc-toolkit__refinery`), so name-based
reasoning looks safe right up until it meets a pool.

The consequence here is **aggregation**, distinct from the liveness and
work-store cut above: tallying live sessions **by name** collapses every
rig's instances of a pool into one bucket and inflates the per-pool
count. Reading two polecats in `gc-toolkit` and two in `shutupandlisten`
— each rig exactly at a cap of 2 — as "4 in gc-toolkit, over cap" is the
near-miss this avoids. Aggregate on **`template`** instead: it *is*
rig-qualified (`gc-toolkit/gc-toolkit.polecat` vs
`shutupandlisten/gc-toolkit.polecat`), so it keeps the per-pool buckets
`gc session list` reports distinct. Both fields ride in the same record —
count the `template`, never the `session_name`.

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
nudge = "Run gc hook --claim --json now; if it returns work, execute the claimed formula immediately."
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

### Bead-host — a per-bead thread (wisp-backed)

The **bead-host** (`agents/bead-host/agent.toml`) is the resident
conversation for exactly one work bead. It is a thread by configuration —
the same never-matching-predicate pair, `work_query = "printf '[]'"` plus
a `sling_query` that exits non-zero — so it is operator-spawned only and
never a sling target. Three things separate it from `mayor-thread`:

- **The alias *is* the bead id.** A host's identity is
  `<binding>.<bead-id>` (`gc-toolkit.tk-d6imi`, `gc-toolkit.su-lou`);
  alias uniqueness is what buys the 1:1 host↔bead binding for free.
  Contrast the `-adhoc-<id>` suffix an ordinary thread instance gets.
- **`wake_mode = "resume"`, `idle_timeout = "8h"`.** On idle it
  *suspends* with the conversation intact rather than dying — the
  mayor-thread mechanism, held far longer.
- **Wisp-backed runtime session.** The controller names it
  `s-lx-wisp-<id>` — distinctly wisp-shaped, where every other session's
  runtime name is built from its workspace and template
  (`gc-toolkit__polecat-<id>`, `gc-toolkit__mayor`).

Hosts are created on demand by `tools/gc-bead-host.sh <bead-id>` (or the
Helm picker, a thin front door over the same tool) — a capability, not a
deployment. Any bead *can* get a host; few do. The bead↔session link is
metadata-only: `hosts_bead` on the session bead is the source of truth,
`host_session` / `host_session_name` on the work bead are caches.

A host **grounds** itself by writing its own runtime session name into
the hosted bead's `assignee` (`gc-bead-host.sh link`), because that
assignment is an awake-demand wake reason the reconciler honors across
drains. So a hosted bead reads as *assigned* — to a session name, not to
a configured agent identity.

Note the scope: `bead-host` declares `scope = "city"`, so its `Dir` is
empty and `QualifiedName()` returns the identity unprefixed — a host's
alias is **bare even when the bead it hosts belongs to a rig**. That
asymmetry against every rig-qualified session is a footgun in its own
right; see [the bare-alias
footgun](#a-bead-hosts-bare-alias-never-matches-a-rig-qualified-assignee).

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
specific patrol agent to act can be routed with `gc sling
<patrol-qualified-name> <bead>` — which stamps `assignee` for
singleton targets so the work surfaces via Tier 2 — or assigned
directly with `bd update --assignee <patrol-qualified-name>`
(Lane 2). Same rule as any named singleton.

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

## Variant E — Deterministic workers (no prompt loop)

A deterministic worker is an agent template carrying
`prompt_mode = "none"` and a `start_command`. The controller
materializes and scales it exactly as it does a pool worker, but the
session it starts runs a program, not a prompt loop — there is no
model behind it and no `gc hook`.

The bundled **core** pack ships one, so *every* city has one whether
or not the operator configured it: the **control-dispatcher**. Its
own `description` is "Deterministic compiler-v2 workflow control
worker", and the core `pack.toml` header calls it "the scope-local
control-dispatcher lane that handles formulas v2 control beads". It
executes the *control* beads of a graph.v2 workflow — the eight
`gc.kind` values (`retry`, `ralph`, `check`, `retry-eval`, `fanout`,
`drain`, `scope-check`, `workflow-finalize`) that ordinary workers
never execute themselves.

Take that list as exactly eight when triaging. It is
`beadmeta.ControlKinds`, whose behavior owner is the `ProcessControl`
switch in `internal/dispatch/runtime.go` — one case per member,
unknown kinds hard-error, and a lockstep test keeps the two in sync.
The core `graph-worker` prompt splits the same set across *two*
bullets: six kinds as "handled by the core-pack `control-dispatcher`
lane", and `retry`/`ralph` separately as "logical controller beads"
a worker "should not execute directly". Reading only the first
bullet under-counts the dispatcher's vocabulary by two — and a
routed `retry` or `ralph` bead misreads as an orphan for exactly the
same reason a `workflow-finalize` one does
([footgun below](#a-dispatcher-routed-control-bead-is-not-an-orphan)).

Source of record:
`internal/bootstrap/packs/core/agents/control-dispatcher/agent.toml`;
kind vocabulary in `internal/beadmeta/kindsets.go`.

### It is not an LLM agent

Everything else about this variant follows from this one fact:

```toml
# core pack: agents/control-dispatcher/agent.toml
# (start_command trace-log preamble elided)
description = "Deterministic compiler-v2 workflow control worker"
start_command = "sh -c '…; exec \"${GC_BIN:-gc}\" convoy control --serve --follow {{.Agent}}'"
prompt_mode = "none"
process_names = ["gc"]
max_active_sessions = 1
```

`prompt_mode = "none"` means no prompt is ever delivered
(`prompt_mode` is one of `arg`, `flag`, `none`). The `start_command`
`exec`s `gc convoy control --serve --follow <agent>` and
`process_names = ["gc"]` names what that pane actually runs: a
long-lived Go serve loop. It is *providerless* too —
`ApplyAgentDefaults` skips control-dispatcher agents when it fans out
the city's default `provider`, `default_sling_formula`, and
`upstream`, on the stated grounds that they are "infrastructure, not
work agents" (`rigs/gascity/internal/config/config.go`).

### Identity and scope

Declared with `max_active_sessions`, **not** `[[named_session]]`, so
it is pool-managed like [Variant B](#variant-b--pool-workers) — but
capped at a single instance (`max_active_sessions = 1`, and no
`min_active_sessions`, so it scales from zero on demand).
"Singleton" for this variant is an effect of that cap, not the
named-session contract.

Its `agent.toml` deliberately leaves `scope` **empty**, so the same
template expands at *both* city and rig scope — one dispatcher per
bead store that can own a workflow graph. QualifiedName then follows
the ordinary rule: `<rig>/core.control-dispatcher` for a rig
expansion, `core.control-dispatcher` for the city one. Selection is
exact-`Dir` (`PreferredDeterministicControlDispatcher`) and never
substitutes the city dispatcher for a rig scope, because the two read
different stores.

### Work routing visibility

It **does** consume routed work. Control beads reach it carrying
`gc.routed_to=<scope>/core.control-dispatcher` with `assignee` empty
— the same Lane 1 shape `gc sling` writes. (`gc.run_target` on a
formula step body is the compile-time precursor the stampers resolve
*into* `gc.routed_to`; it is how a recipe names a target for the
check and control-dispatch steps, where `assignee` can't be used. See
the `gc.run_target` section of
[gascity-routing-model.md](gascity-routing-model.md).)

What it does not use is the three-tier
[`Agent.EffectiveWorkQuery()`](#work-routing) the rest of this doc
describes. A worker with no prompt loop never runs `gc hook`; the
serve loop issues its own **control-ready** query, scanning both
`gc.run_target` and `gc.routed_to` routes `--unassigned` plus a set
of assignee candidates (including the legacy `workflow-control`
alias). Built in `cmd/gc/dispatch_runtime.go`; shape pinned by
`cmd/gc/dispatch_control_ready_test.go`.

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

Read that rule — and the `Routed work?` column in the
[variants table](#variants-at-a-glance) — as scoped to what a
*prompt-driven* session sees through `gc hook`. It is not "any
non-`ephemeral` lane can never receive routed work": a
[deterministic worker](#variant-e--deterministic-workers-no-prompt-loop)
has no hook at all, and its serve loop consumes `gc.routed_to` work
through a query of its own that this gate never touches.

Source: `Agent.EffectiveWorkQuery()` in
`rigs/gascity/internal/config/workquery.go`:

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
Deterministic workers (Variant E) are not a column either: they
address like the pool instances they are, except that the commands
which speak to a *prompt loop* — `nudge`, `peek` — have nothing to
speak to; see
[the inert-liveness footgun](#a-deterministic-workers-liveness-signals-are-structurally-inert).

The **Thread** column means an ordinary operator-spawned `-adhoc-<id>`
instance. A [bead-host](#bead-host--a-per-bead-thread-wisp-backed) is
thread-shaped by configuration but does **not** address like that column,
so read it as excluded there:

- **Spelling.** A host's alias *is* the bead id
  (`gc-toolkit.tk-d6imi`) with no `-adhoc-` suffix, and its runtime
  session name is `s-lx-wisp-<id>`. Wherever the Thread column says
  "adhoc alias" or "adhoc session name", substitute those two forms.
- **`gc session new` is not how a host is born.** It is created on
  demand by `tools/gc-bead-host.sh <bead-id>` (or the Helm picker over
  the same tool), which also writes the durable bead↔session link that a
  bare spawn would skip.
- **`bd update --assignee` on a hosted bead is grounding, not
  addressing.** The host writes its *own runtime session name* there
  because that assignment is an awake-demand wake reason.
- **Drain and kill do not stick while the bead has awake-demand.** For a
  `wake_mode = "resume"` host the reconciler revives it with the
  conversation intact, so a drain is a no-op-with-restart. A host is put
  down by ending the work — close or park the bead, or
  `gc-helm.sh takeaway --release` — which clears the wake reason first.

| Command | Named singleton | Pool worker | Thread (`-adhoc-`) |
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
| `gc sling <target> <bead>` | QualifiedName — stamps `assignee`+`gc.routed_to`, so Tier 2 surfaces it (Lane 1) | QualifiedName / PoolName (Lane 1) | ✗ — sling_query exits non-zero |
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

**Work ownership — there is no per-session bead ownership.** This
is the consequence that makes duplicates expensive rather than
merely untidy. A bead's `assignee` is a single identity string,
and for a named singleton that string is the *agent* identity —
its QualifiedName (see [the four strings](#the-four-strings)) — so
every live session of that agent that resolves it sees the same
bead. The hook's own sweep makes the split explicit: of `$GC_SESSION_ID`,
`$GC_SESSION_NAME`, `$GC_ALIAS` ([work routing](#work-routing)
Tier 1 / Tier 2, `internal/config/workquery.go`), only the first
two are per-session.

Concretely, once one agent has more than one live session:

- A handback or crash-recovery sweep — `bd list
  --status=in_progress --assignee=$GC_AGENT`, the idiom the patrol
  [startup discovery](#startup-discovery-4-tier) and most role
  prompts use — returns the **same** bead in **every** session.
  Each will try to drive and finalize it, and `bd` tells neither
  that a sibling is on it.
- **Deferred reminders route agent-wide, not to the session that
  set them.** Observed with duplicate keeper sessions: a queued
  `DONE` reminder for work one session owned fired into the
  canonical session's stream.
- `bd update --claim` does not close the gap. It is an atomic
  transition, not a lock — the same limitation as the
  [pool-instance race](#pool-instance-race-on-simultaneous-claim)
  below.

**Closing the bead is the de-facto mutex** — there is no other
one. Do the finalize promptly and close; a second session then
reads `status=closed` and stops. Two corollaries:

- **Re-read immediately before writing.** A top-of-session read
  goes stale the moment a sibling writes the same bead. Re-read
  for existing notes and finalize metadata, and append rather than
  replace, so you do not clobber a sibling's work.
- **Do not try to de-conflict with a nudge.** A nudge is
  best-effort and lands at the receiver's next boundary — possibly
  after the write it was meant to prevent.

**Detection.** `gc session list` shows both. The canonical alias
will be one; the manual one will have an `…-adhoc-<id>` suffix.

**Recovery.** `gc session close <one-of-them>` collapses to a
single live instance. Pick the one whose work-in-flight is less
important to preserve; absent that signal, converge on the
**canonical** — it is the stable identity, and long-running work
is safest on the session that will not be recycled out from under
it.

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

### Stamping only `gc.routed_to` on a named singleton strands the work

Named singletons run with `$GC_SESSION_ORIGIN=named`, which
skips the Tier 3 routed-pool query. A bead carrying *only*
`gc.routed_to=<singleton>` — e.g. from `bd update <bead>
--set-metadata gc.routed_to=<singleton-qualified-name>` — is
invisible to the singleton's hook, which runs only Tier 1 / Tier 2
(assignee match).

`gc sling <singleton-qualified-name> <bead>` is the safe path: it
detects the singleton target and stamps `assignee=<target>`
alongside `gc.routed_to`, so the bead surfaces via the singleton's
Tier 2 (`bd ready --assignee`) query. `bd update <bead> --assignee
<singleton-qualified-name>` (Lane 2) is the equivalent explicit
form. See [gascity-routing-model.md, Lane
1](gascity-routing-model.md#lane-1--gc-sling-target-bead-queue--template-routing)
and [Lane
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

### A dispatcher-routed control bead is not an orphan

A `Finalize workflow` bead — or any graph.v2 control bead — routed to
`<scope>/core.control-dispatcher` has no interactive session that
answers for it, so an orphan or ownership scan that resolves owners
by session liveness resolves it to **absent**. That is not evidence
of an orphan. It is dispatcher-gated work in a normal state, usually
still blocked behind its own open step chain, and the
[deterministic worker](#variant-e--deterministic-workers-no-prompt-loop)
takes it when that chain clears.

Recovering, reassigning, or closing such a bead is wrong, and closing
is the one that does real damage: a parked v2 control or step bead is
what holds its pre-routed downstream work back, so closing it
releases that work early — before the step it was gating finished.
Treat dispatcher-routed beads the way an orphan scan already treats
refinery and witness beads: infrastructure, skip.

### A deterministic worker's liveness signals are structurally inert

A `prompt_mode = "none"` session reads `state=active running=true`
while its `last_active` sits hours or days stale, and
`gc session peek` returns nothing meaningful. Neither is a symptom.
`last_active` tracks *pane output*, and a serve loop that does its
work in short-lived child processes never writes to the pane, so
nothing advances either signal after spawn. `gc session nudge` is
structurally a no-op for the same reason — no prompt loop consumes
the text, so it accumulates unsubmitted in the pane, where it reads
convincingly like a wedged agent sitting on a pending prompt.

Judge liveness from the **process**: the `gc convoy control --serve`
daemon is alive and its full argv is that serve command. Read the
argv, not the process's command name — that is just `gc`, forever,
by design; a deterministic worker is not a `claude`-backed session
and must never be benchmarked against one. Child count is not a
signal either, since the polls it forks are short-lived and zero
children at any given instant is normal. Never judge from
`last_active` or `peek`, and never file a stuck-agent warrant on
them.

### A bead-host's bare alias never matches a rig-qualified assignee

**Memory:** `reference-polecat-liveness.md` (§ "Bead-host aliases are
BARE; their bead assignees are RIG-QUALIFIED").

A [bead-host](#bead-host--a-per-bead-thread-wisp-backed) is city-scoped,
so its `Dir` is empty and `QualifiedName()` returns the identity with no
rig prefix: the alias is **bare** (`gc-toolkit.gc-z0vi2`) even when the
bead it hosts belongs to a rig. Every rig-bound session on the other side
— pool instance, rig-scoped singleton — is **rig-qualified**
(`gc-toolkit/gc-toolkit.nux`), because there `Dir` is non-empty and
`QualifiedName()` prepends it. Both halves are that one function
behaving as documented; the asymmetry is the *scope*, not a defect, and
there is nothing to fix.

It costs any scan that resolves a bead's owner by exact lookup into a
session map keyed on `id, name, session_name, alias, agent_name`. When
the bead's `assignee` was written rig-qualified, no key in that map
matches and a live owner resolves to **absent**:

```
assignee "gascity/gc-toolkit.gc-z0vi2" -> absent
alias    "gc-toolkit.gc-z0vi2"         -> active  (session s-lx-wisp-q5qbl)
```

Nothing downstream catches it: "absent after exact lookup" classifies as
orphaned for pool/ephemeral identities, and the skip rule exempts only
*configured infra* identities (refinery, witness). A bead-host is an
ephemeral work identity, so it falls through to source-delete + reopen —
yanking a bead out from under a live owner mid-work.

**Rule: an `absent` assignee is a lead, not a verdict.** Before
classifying one as orphaned, resolve it the way the shipped witness
recipe does — *exact first, then last segment, live wins*:

1. **The exact lookup stays authoritative.** A literal map-key hit
   stands even when a normalized retry would answer differently. That
   is how a genuinely dead session still gets recovered.
2. **On a miss, retry once on the last `/`-separated segment of *both*
   sides** — `${ASSIGNEE##*/}` as shell shorthand (`##`, not `#`: the
   part to drop runs to the **last** slash, not the first), compared as
   a whole segment and never as a suffix, so `toolkit.furiosa` does not
   alias onto `gc-toolkit.furiosa`. Both sides, because both directions
   are live in one city at once: a bead-host's bare alias against a
   rig-qualified assignee, and a pool worker's rig-qualified alias
   against a bare assignee.
3. **A collision resolves toward life.** Baring the prefixes can collapse
   two cities' sessions onto one identity, so any candidate that is not
   `closed`/`archived` wins; only when *every* candidate is dead does the
   retry report a dead state. The retry can therefore turn `absent` into
   a live state but can never manufacture an orphan.

A step-2 hit means a live bead-host, not an orphan. The lookup ships in
`formulas/mol-witness-patrol.toml` between the `liveness-lookup` markers,
and `assets/scripts/liveness-lookup.test.sh` executes that snippet
extracted verbatim from the formula rather than a transcription of it —
so the rule above and the running code cannot drift apart silently.

Two things narrow the exposure without closing it:

- **Bare does not imply bead-host.** City-scoped singletons
  (`gc-toolkit.mayor`, `gc-toolkit.deacon`) carry bare aliases too — but
  *their* assignees are written bare as well, so the exact lookup hits.
  The hazard is the mismatch between the two sides, not bareness.
- **A grounded host is recognizable without any liveness lookup.**
  `gc-bead-host.sh link` writes the host's runtime session name into
  `assignee` and caches it as `metadata.host_session_name`, so the
  equality `metadata.host_session_name == assignee` identifies the bead
  structurally; `mol-witness-patrol.toml` skips on exactly that
  (regression-tested by `assets/scripts/host-bead-skip.test.sh`). That
  is the cheap first pass. The prefix-strip retry is what still catches a
  host whose assignee was written in some other form.

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
  (`internal/config/workquery.go`; currently three tiers; Tier 3
  gated by `$GC_SESSION_ORIGIN`).
- A new variant emerges — e.g., something that is neither
  `[[named_session]]`, pool, nor operator-spawned thread.
- A new gc-toolkit auto-memory entry documents a *by-design* sharp
  edge — a contract-level consequence a consumer must account for
  permanently — and NOT a defect with a tracked fix. A defect (a
  bead id plus an "until <X> lands" expiry) is operational and
  self-expiring; it belongs in memory and the bead trail, never in
  this footgun section.

To audit drift against upstream, diff `NamedSession` and
`Agent.EffectiveWorkQuery()` since the last refresh:

```bash
git -C rigs/gascity log --since='<last refresh>' \
  -p -- internal/config/config.go internal/config/workquery.go \
  | grep -E '^\+.*NamedSession|^\+.*WorkQuery'
```

The two halves live in **different files**: `NamedSession` in
`internal/config/config.go`, the work-query shell codegen —
including `Agent.EffectiveWorkQuery()` — in
`internal/config/workquery.go`, where upstream moved it out of
`config.go`. Both paths must stay in the pathspec, and if either
symbol moves again the pathspec has to be widened *before* the
next audit is trusted: a pathspec that misses the file a symbol
now lives in fails **silently**, because an empty result is
indistinguishable from "upstream didn't change."

The footguns above are *by-design* sharp edges, not defects: each
documents a contract that holds on purpose (see the watch-don't-fix
reopen conditions on its bead). Remove one only when the underlying
contract genuinely changes — a design decision, surfaced as drift —
not as a "reap it when the fix merges" chore. A structural reference
does not track bug-fix lifecycles: a defect with a tracked fix is
operational, self-expires, and lives in memory and the bead/git
trail, never here.
