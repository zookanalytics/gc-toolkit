# Gas City Reference Guide

> Compiled from docs.gascityhall.com and the github.com/gastownhall/gascity
> source. Current as of **v1.0.1 (2026-04-22)**.
>
> Pack/City v2 has landed — schema 2 packs, convention-based agent discovery,
> `.gc/site.toml` machine-local identity, and the new `gc import` command are
> the default. Legacy schema 1 artifacts still load for compatibility, but
> `gc init` emits the v2 shape and `gc import migrate` rewrites v1 cities.

---

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [City Initialization (`gc init`)](#city-initialization)
4. [V2 City & Pack Layout](#v2-city--pack-layout)
5. [Configuration Reference](#configuration-reference)
6. [Beads Setup (Work Tracking)](#beads-setup)
7. [Agents & Packs](#agents--packs)
8. [The Gastown Pack (Role Reference)](#the-gastown-pack)
9. [Runtime Providers (Sessions)](#runtime-providers)
10. [Formulas, Molecules & Orders](#formulas-molecules--orders)
11. [Rigs (Project Registration)](#rigs)
12. [Skills](#skills)
13. [CLI Command Reference](#cli-command-reference)
14. [The Nine Concepts (Architecture)](#the-nine-concepts)
15. [Progressive Capability Model](#progressive-capability-model)
16. [Tutorials](#tutorials)
17. [V1 → V2 Migration](#v1--v2-migration)
18. [Known Issues & Gotchas](#known-issues--gotchas)
19. [Gas Town → Gas City Migration](#gas-town--gas-city-migration)
20. [Example Cities](#example-cities)

---

## Overview

Gas City is an **orchestration-builder SDK for multi-agent systems**. It extracts
the reusable infrastructure from Gas Town into a configurable toolkit with:

- **A city IS a pack** (Pack/City v2) — `pack.toml` (schema 2) at the city root
  alongside `city.toml`, convention-based agent discovery under `agents/<name>/`
- **Declarative city configuration** via `city.toml` + `.gc/site.toml`
- **Multiple runtime providers**: tmux, subprocess, exec, ACP, Kubernetes, hybrid
- **Beads-backed work tracking**: tasks, mail, molecules, waits, convoys
- **Controller/supervisor loop**: reconciles desired state to running state
- **Pack imports, patches, and rig-scoped overrides** for multi-project setups

Written in Go. MIT licensed.

**Key difference from Gas Town**: Gas City is configuration-first. There are no
hardcoded role names in the SDK. All roles (mayor, deacon, polecat, etc.) are
defined in **packs** — reusable directories discovered by convention. The SDK
provides primitives; packs provide behavior.

---

## Installation

### Homebrew (Recommended)
```bash
brew install gastownhall/gascity/gascity
gc version
```

### From Source
```bash
git clone https://github.com/gastownhall/gascity.git
cd gascity
make install
gc version
```

### Runtime Dependencies

| Dependency | Required | Purpose | Install |
|------------|----------|---------|---------|
| tmux | Always | Session management | `brew install tmux` |
| git | Always | Version control | `brew install git` |
| jq | Always | JSON processing | `brew install jq` |
| pgrep | Always | Process detection | (included) |
| lsof | Always | Port detection | (included) |
| dolt | Always | Beads data plane | `brew install dolt` |
| bd | Always | Beads CLI | `brew install gastownhall/beads/beads` |
| flock | Always | File locking | `brew install flock` |
| Go 1.25+ | Source builds | Compilation | `brew install go` |

Homebrew installs the runtime dependencies automatically.

### To skip Dolt/bd entirely
Set `GC_BEADS=file` or add `[beads] provider = "file"` to `city.toml`.
The file provider uses JSON on disk — suitable for tutorials and small setups.

---

## City Initialization

### Basic Flow
```bash
gc init ~/my-city        # Interactive wizard (or --provider for non-interactive)
cd ~/my-city
gc start                 # Launches under machine-wide supervisor
```

### Templates (Interactive Wizard)

| Template | What You Get |
|----------|-------------|
| **tutorial** (default) | Single mayor agent, minimal config |
| **gastown** | Full multi-agent orchestration (mayor, deacon, boot, witness, refinery, polecat, dog) |
| **custom** | Empty workspace, one mayor, no provider — configure manually |

### Non-Interactive Init
```bash
gc init --provider claude ~/my-city          # Tutorial template with Claude
gc init --from examples/gastown ~/my-city    # Copy example city directory
gc init --file my-config.toml ~/my-city      # Use custom TOML file
gc init --bootstrap-profile k8s-cell ~/pod   # Kubernetes container mode
gc init --name my-city                       # Explicit workspace name
gc init --skip-provider-readiness            # Skip provider login probes
```

### What `gc init` Creates (V2 Shape)

```
my-city/
├── pack.toml              # Root city-pack metadata (schema = 2)
├── city.toml              # City-specific config (slim — rigs, daemon, providers)
├── agents/                # Convention-based agent definitions (optional at root)
├── commands/              # Command scripts exposed as `gc <cmd>` (optional)
├── formulas/              # Formula definitions (<name>.toml)
├── orders/                # Order definitions (<name>.toml)
├── scripts/               # Custom scripts
├── hooks/                 # Provider hook configs (claude.json, etc.)
└── .gc/                   # Runtime root (DO NOT commit)
    ├── site.toml          # Machine-local identity (workspace name, rig paths)
    ├── system/
    │   ├── packs/         # Built-in packs (core, gastown, maintenance, bd, dolt)
    │   └── bin/           # System binaries (gc-beads-bd)
    ├── cache/             # Pack fetch cache
    ├── runtime/           # Runtime state
    ├── controller.lock    # Exclusive controller lock
    ├── controller.sock    # Unix control socket
    └── events.jsonl       # Event log
```

### Init Steps (Internal)
1. Create runtime scaffold (`.gc/` tree)
2. Write `pack.toml` (schema 2) and `city.toml`
3. Write `.gc/site.toml` with `workspace_name` and derived `workspace_prefix`
4. Install provider hooks (`hooks/claude.json`, etc.) if applicable
5. Materialize built-in packs under `.gc/system/packs/` (core, gastown, maintenance, bd, dolt)
6. Seed `agents/<name>/` convention directories for the chosen template
7. Check provider readiness (login/auth probes) unless `--skip-provider-readiness`
8. Register city with supervisor

---

## V2 City & Pack Layout

### The city-as-pack model

A city root IS a pack. Its `pack.toml` declares `schema = 2` and can import
other packs. `city.toml` carries only city-specific concerns (rigs, providers,
daemon, beads, mail, dolt, etc.). Most agent/prompt/formula/order content lives
in pack directories discovered by convention.

```
city-root/
├── pack.toml              # [pack] schema=2 + [imports] + [defaults] + [global]
├── city.toml              # City-specific config
├── agents/                # Convention: agents/<name>/ per agent
│   └── mayor/
│       ├── agent.toml     # Agent config (no `name` field — derived from dir)
│       └── prompt.template.md
├── commands/              # Convention: commands/<name>/run.sh per subcommand
│   └── deploy/
│       └── run.sh
├── formulas/              # <name>.toml (no .formula. infix in v2)
├── orders/                # <name>.toml (flat files, no .order. infix)
├── skills/                # <name>/SKILL.md (shared help docs, surfaced via gc skill)
├── overlays/              # Provider settings overlays (e.g. .claude/settings.json)
├── template-fragments/    # Shared Go-template fragments (for prompt composition)
└── .gc/
    └── site.toml          # Machine-local identity and rig paths
```

### `pack.toml` (schema 2)

```toml
[pack]
name = "my-pack"
schema = 2
version = "0.1.0"           # Optional semantic version
city_agents = ["mayor"]     # Optional: restrict to city-scope when imported as workspace pack

[imports.other-pack]
source = "../other-pack"    # Local path or github.com/org/repo
version = "0.2.0"           # Required for git-backed imports

[defaults]
[defaults.rig]
[defaults.rig.imports.gastown]
source = ".gc/system/packs/gastown"  # Default imports applied to every rig

[global]
session_live = [            # Commands re-applied to every agent session
    "{{.ConfigDir}}/scripts/tmux-theme.sh {{.Session}} {{.Agent}}",
]

[[patches.agent]]           # Post-composition overrides
name = "dog"
wake_mode = "fresh"

[[named_session]]           # Declare named sessions for pack agents
template = "mayor"
scope = "city"
mode = "always"             # "always" or "on_demand"
```

### `agents/<name>/agent.toml`

No `name` field — the directory is the name. `scope` defaults to rig if the
pack is imported as a rig pack, city if imported as a workspace pack.

```toml
scope = "city"              # "city" or "rig"
wake_mode = "fresh"         # "fresh" or "resume"
work_dir = ".gc/agents/{{.Agent}}"
nudge = "Check your hook."
idle_timeout = "1h"
max_active_sessions = 1
pre_start = ["scripts/setup.sh"]
# ... all the same [[agent]] fields below, minus `name`
```

### `.gc/site.toml` — machine-local identity

Created by `gc init` / `gc register`, never committed. Holds the workspace
name, prefix, and rig filesystem paths — all previously in `city.toml`.

```toml
workspace_name = "loomington"
workspace_prefix = "lx"

[[rig]]
name = "my-project"
path = "/home/user/projects/my-project"

[[rig]]
name = "other-project"
path = "/home/user/projects/other"
```

This separates machine-local state from checked-in config. You can commit
`city.toml` + `pack.toml` to git without leaking absolute paths or
machine-specific names.

---

## Configuration Reference

### `city.toml` (v2 — slim)

The file is much smaller in v2. Most pack content has moved to `pack.toml` +
convention directories. `city.toml` now focuses on city-level runtime:

```toml
# ─── WORKSPACE (mostly optional in v2) ──────────────────────────────
[workspace]
# name = "..."                       # OPTIONAL — prefer .gc/site.toml workspace_name
provider = "claude"                  # Default LLM provider
start_command = ""                   # Override provider command
global_fragments = ["command-glossary"]  # Prompt fragments applied to all agents
install_agent_hooks = true           # Install provider hooks on init

# ─── AGENTS (optional in v2; prefer convention) ─────────────────────
# Inline [[agent]] blocks still work for crew members and one-off patches,
# but the preferred shape is agents/<name>/agent.toml under the city/pack root.
[[agent]]
name = "wolf"                        # Unique identifier (required for inline)
scope = "rig"                        # "city" or "rig"
dir = "myproject"                    # Rig name (for dir-scoped agents)
provider = "claude"                  # Override workspace provider
prompt_template = "agents/wolf/prompt.template.md"
prompt_mode = "arg"                  # "arg", "flag", or "none"
nudge = "Check hook and mail."
work_dir = ".gc/agents/wolf"
overlay_dir = "overlays/default"
wake_mode = "fresh"                  # "fresh" (new session) or "resume"
suspended = false
idle_timeout = "1h"
sleep_after_idle = ""                # Override idle sleep policy
pre_start = ["scripts/setup.sh"]
session_setup = ["tmux cmd..."]      # Commands after session creation (templates ok)
session_setup_script = "scripts/theme.sh"
session_live = ["tmux cmd..."]       # Idempotent commands re-applied on config change
env = { KEY = "value" }
min_active_sessions = 0
max_active_sessions = 1              # Pool size
scale_check = "script.sh"            # Shell command returning desired count
drain_timeout = ""
namepool = "namepools/mad-max.txt"
fallback = false
depends_on = ["other-agent"]
session = ""                         # "acp" for Agent Client Protocol
inject_fragments = ["fragment-name"]
attach = false
description = ""
default_sling_formula = ""
work_query = ""
sling_query = ""
on_boot = ""
on_death = ""
install_agent_hooks = []             # Provider hook configs to install
option_defaults = {}                 # Default provider options (model, effort, permission_mode)

# ─── NAMED SESSIONS ─────────────────────────────────────────────────
[[named_session]]
template = "mayor"
alias = ""
scope = "city"
mode = "always"                      # "always" or "on_demand"
title = ""
wake_mode = "resume"

# ─── RIGS (slim in v2) ──────────────────────────────────────────────
# Path no longer lives here — it's in .gc/site.toml under [[rig]].
[[rigs]]
name = "myproject"                   # Unique identifier (required)
prefix = ""                          # Override auto-derived bead ID prefix
suspended = false                    # Suspend the rig's agents
includes = ["packs/gastown"]         # Legacy; prefer rig-local pack.toml imports
max_active_sessions = 10
default_sling_target = "polecat"
session_sleep = {}
dolt_host = ""
dolt_port = 0
formulas_dir = ""

[[rigs.overrides]]                   # Per-agent overrides (no pack forking)
agent = "polecat"
provider = "gemini"
idle_timeout = "30m"
max_active_sessions = 10

# ─── PROVIDERS ───────────────────────────────────────────────────────
[providers.my-custom]
command = "my-agent"
args = ["--flag"]
prompt_mode = "arg"
prompt_flag = "--prompt"
supports_acp = false
supports_hooks = false
ready_delay_ms = 0
ready_prompt_prefix = ""
resume_flag = "--resume"
resume_style = "flag"                # "flag" or "subcommand"
resume_command = ""                  # Template with {{.SessionKey}}
session_id_flag = "--session-id"
permission_modes = { auto = "--dangerously-skip-permissions" }
options_schema = {}

# ─── BEADS, SESSION, MAIL, EVENTS, DOLT, DAEMON, API, etc. ─────────
[beads]
provider = "bd"                      # "bd" (default), "file", or "exec:<script>"

[session]
provider = ""                        # "" = tmux (default), "k8s", "acp", "subprocess", "exec:<script>", "hybrid"
setup_timeout = "10s"
startup_timeout = "60s"
socket = ""                          # Tmux socket name (defaults to workspace name)
nudge_ready_timeout = "10s"
nudge_retry_interval = "500ms"
nudge_lock_timeout = "30s"
debounce_ms = 500
display_ms = 5000
remote_match = ""

[session.k8s]
namespace = "gc"
cpu_request = "50m"
mem_request = "128Mi"
cpu_limit = "200m"
mem_limit = "256Mi"
prebaked = false

[session.acp]
handshake_timeout = "30s"
output_buffer = 1000

[mail]
provider = ""                        # Default: beadmail (bead-backed)

[events]
provider = ""                        # Default: file-based JSONL

[dolt]
port = 3307
host = ""                            # External Dolt host (empty = local)

[daemon]
patrol_interval = "30s"
max_restarts = 5
restart_window = "1h"
shutdown_timeout = "5s"
wisp_gc_interval = "5m"
wisp_ttl = "24h"
formula_v2 = true                    # Graph-based formula workflow (default in 1.0)
drift_drain_timeout = "2m"
probe_concurrency = 8
observe_paths = []

[api]
port = 9443
bind = "127.0.0.1"
allow_mutations = false              # Required for non-localhost

[formulas]
dir = "formulas"

[orders]
skip = []
max_timeout = "300s"
# [[orders.overrides]]               # Per-order setting overrides

[convergence]
max_per_agent = 2
max_total = 10

[session_sleep]
interactive_resume = "4h"
interactive_fresh = "1h"
noninteractive = "30m"               # "off" to disable

[chat_sessions]
idle_timeout = "4h"

[agent_defaults]
model = ""
wake_mode = "fresh"
default_sling_formula = ""
allow_overlay = true
allow_env_override = true

# ─── PATCHES (post-composition modifications) ───────────────────────
# Primarily in pack.toml, but also valid in city.toml.
[[patches.agent]]
dir = ""
name = "mayor"
provider = "codex"
idle_timeout = "2h"

[[patches.rig]]
name = "myproject"
# ... field overrides

[[patches.provider]]
name = "claude"
# ... field overrides

# ─── SERVICES (workspace-owned HTTP services) ────────────────────────
[[service]]
name = "dashboard"
kind = "proxy_process"               # "workflow" or "proxy_process"
publish_mode = "private"             # "private" or "direct"
state_root = ""

# ─── LEGACY: remote packs (superseded by pack.toml [imports]) ───────
# Prefer [imports.<name>] in pack.toml with `source = "github.com/..."`.
[packs.remote-pack]
source = "https://github.com/example/pack.git"
ref = "v1.0.0"
path = "pack"                        # Subdirectory within repo
```

### Template Variables (for session_setup, work_dir, etc.)
- `{{.Session}}` — session name
- `{{.Agent}}` — full agent name
- `{{.AgentBase}}` — base agent name (without pool index)
- `{{.Rig}}` — rig name
- `{{.RigRoot}}` — rig absolute path
- `{{.CityRoot}}` — city directory
- `{{.CityName}}` — city name (from site.toml)
- `{{.WorkDir}}` — resolved working directory
- `{{.ConfigDir}}` — pack config directory (for script paths)

### Built-in LLM Providers (11)
`claude`, `codex`, `gemini`, `cursor`, `copilot`, `amp`, `opencode`, `auggie`,
`pi`, `omp`, `sourcegraph`

Each has pre-configured: command, args, prompt mode, ready detection, process
names, permission modes, options schema (model, effort), resume support.

---

## Beads Setup

### What Are Beads?
Beads are the **universal work unit**. Everything is a bead: tasks, mail,
molecules, convoys, epics. Each has ID, title, status
(open/in_progress/blocked/deferred/closed), type, labels, metadata, and
dependencies.

### Three Bead Store Backends

| Backend | Config | IDs | Backend Tech | Best For |
|---------|--------|-----|-------------|----------|
| **bd** (default) | `provider = "bd"` | `<prefix>-N` | Dolt SQL server + `bd` CLI | Production, multi-agent |
| **file** | `provider = "file"` | `<prefix>-N` | JSON file on disk | Tutorials, single-agent |
| **exec** | `provider = "exec:/path/to/script"` | varies | User-supplied script | Custom backends |

### Choosing a Provider

**For getting started quickly**:
```toml
[beads]
provider = "file"
```

**For production** (default):
```toml
[beads]
provider = "bd"
```

**Via environment variable** (highest priority):
```bash
export GC_BEADS=file        # or "bd" or "exec:/path/to/script"
```

Priority: `GC_BEADS` env → `city.toml [beads].provider` → `"bd"` default

### How Beads Init Works
1. `gc start` calls `startBeadsLifecycle()`
2. Starts backing service (Dolt for bd provider)
3. Initializes beads for the city root directory
4. For each rig: initializes beads in `<rig>/.beads/`
5. Installs agent hooks (Claude, Gemini, etc.)
6. Regenerates cross-rig routes

### Per-Rig Beads
Each rig gets its own `.beads/` database with isolated bead IDs (the rig's
prefix). The city root also has its own beads store for city-scoped work.

### Common Beads Commands
```bash
bd create "your prompt"     # Create a new bead
bd ready                    # List open beads ready for work
bd show <id>                # View bead details
bd show <id> --watch        # Monitor progress
bd update <id> --claim      # Claim work atomically
bd close <id>               # Complete work
bd dolt push                # Push beads data to remote
```

### `gc beads` — topology and health
```bash
gc beads health             # Check beads provider health
gc beads city               # Manage canonical city endpoint topology
```

### `gc dolt` — direct data-plane management
```bash
gc dolt start               # Start Dolt server if not running
gc dolt status              # Check Dolt health
gc dolt logs                # Tail server log
gc dolt list                # List Dolt databases
gc dolt sql                 # Open interactive SQL shell
gc dolt cleanup             # Remove orphaned databases
gc dolt recover             # Recover from read-only state
gc dolt rollback            # List/restore migration backups
gc dolt sync                # Push databases to configured remotes
```

---

## Agents & Packs

### What's a Pack?
A reusable directory with agents and supporting assets. Two shapes:

**V2 (convention-based, preferred):**
```
my-pack/
├── pack.toml          # [pack] schema=2 + [imports] + [global] + [[named_session]]
├── agents/            # Convention discovery
│   └── worker/
│       ├── agent.toml
│       └── prompt.template.md
├── commands/          # Exposed as `gc <cmd>` when imported
│   └── hello/
│       └── run.sh
├── formulas/          # <name>.toml
├── orders/            # <name>.toml
├── skills/            # <name>/SKILL.md (surfaced via `gc skill`)
├── template-fragments/
├── overlays/          # Provider settings overrides
├── assets/            # Scripts, fragments, images
├── doctor/            # Health check scripts
└── namepools/         # Name lists for pool instances
```

**V1 (legacy, still loads):**
```
my-pack/
├── pack.toml          # [pack] schema=1 with inline [[agent]] blocks
├── prompts/           # <name>.md.tmpl flat files
├── scripts/
├── formulas/<name>.formula.toml
├── orders/<name>/order.toml
├── overlays/
├── doctor/
└── commands/
```

### `pack.toml` (schema 2)
```toml
[pack]
name = "my-pack"
schema = 2
version = "0.1.0"
city_agents = ["mayor", "deacon"]   # Which agents run at city scope (workspace import)
description = "..."

[imports.other-pack]                 # Pack imports (replaces [packs] in city.toml)
source = "../other-pack"             # Local path or github.com/org/repo
version = "0.2.0"
path = "subdir"                      # Optional subdirectory in source repo

[global]                             # Applied to all agents this pack defines
session_live = ["cmd ..."]

[[patches.agent]]                    # Post-composition overrides
name = "dog"
wake_mode = "fresh"

[[named_session]]                    # Materialized sessions
template = "mayor"
scope = "city"
mode = "always"

[formulas]
dir = "formulas"                     # Override default formula directory

[[doctor]]
name = "check-deps"
script = "doctor/check-deps.sh"
description = "Verify dependencies"
```

### Dual-Scope Packs
`city_agents` partitions a pack:
- **Workspace import** (city pack includes): retains only listed agents at city scope
- **Rig import** (rig-level pack): excludes city agents, keeps only rig-scoped agents

### Importing Packs

**In `pack.toml` (v2, preferred):**
```toml
[imports.gastown]
source = ".gc/system/packs/gastown"  # Local path

[imports.examples]
source = "github.com/org/packs"      # Remote git
version = "1.2.0"
path = "subdir"
```

**In `city.toml` (legacy `[packs]`, still loads):**
```toml
[packs.remote]
source = "https://github.com/example/pack.git"
ref = "v1.0.0"
```

### `gc import` — managing imports
```bash
gc import list                       # List imported packs
gc import add <source>               # Add an import
  --name <alias>                     # Local binding name override
  --version <constraint>             # Version constraint for git imports
gc import install                    # Install from pack.toml + packs.lock
gc import check                      # Validate installed state
gc import upgrade                    # Upgrade within version constraints
gc import remove <name>              # Remove an import
gc import why <name>                 # Explain why an import is present
gc import migrate [--dry-run]        # Rewrite v1 city into v2 shape
```

### Overriding Without Forking
```toml
# In city.toml or pack.toml
[[rigs.overrides]]
agent = "polecat"
provider = "gemini"
idle_timeout = "30m"
max_active_sessions = 10

[[patches.agent]]
name = "dog"
work_dir = ".gc/agents/dogs/{{.AgentBase}}"
wake_mode = "fresh"
```

---

## The Gastown Pack

The flagship multi-agent orchestration pack. Composable sub-packs:
- **core** — shared skills, pool-worker prompt, common assets
- **gastown** — domain-specific coding workflow (imports maintenance)
- **maintenance** — generic infrastructure (dog pool, exec orders)
- **bd** — Beads integration (auto-imported when `[beads] provider = "bd"`)
- **dolt** — Dolt database management (auto-imported with bd)

### Agent Roles

| Role | Scope | Pool | Metaphor | Purpose |
|------|-------|------|----------|---------|
| **Mayor** | City | Singleton (`max=1`) | Drive shaft | Global coordinator. Dispatches work via `gc sling`, manages rigs, handles escalations. CAN edit code directly. |
| **Deacon** | City | Singleton (`max=1`) | Flywheel | Town-wide patrol. Closes gates, checks convoys, monitors health, owns diagnostic signals. Silent when healthy (exponential backoff). |
| **Boot** | City | Singleton (`max=1`) | — | Deacon watchdog. Ephemeral — spawned fresh each tick. Answers: "is the deacon stuck?" |
| **Witness** | Rig | Singleton (`max=1`) | Pressure gauge | Per-rig work-health monitor. Core job: orphaned bead recovery. Also monitors refinery queue and stuck polecats. |
| **Refinery** | Rig | Singleton (`max=1`, on-demand) | Gearbox | Merge queue processor. Sequential rebase protocol. NEVER writes code — only merges. |
| **Polecat** | Rig | 0-5 | Piston | Transient workers in isolated worktrees. Follow strict formula: load → branch → implement → test → submit → exit. Named from Mad Max pool. |
| **Crew** | Rig | Named individuals | — | Persistent workers. Push directly to main. Long-lived identity. Declared inline in `city.toml` or a rig-local pack. |
| **Dog** | City | 0-3 | On-demand piston | Infrastructure utility. Runs shutdown dance (3-attempt interrogation), JSONL export, stale wisp reaping. Zero mail. |

All singleton agents ship with `max_active_sessions = 1` and
`wake_mode = "fresh"`. The polecat nudge references `gc hook` (which checks
assigned work first, then routed pool work).

### Registering the Gastown Setup (v2)

```toml
# pack.toml (city root)
[pack]
name = "my-city"
schema = 2

[imports.gastown]
source = ".gc/system/packs/gastown"

[defaults.rig.imports.gastown]
source = ".gc/system/packs/gastown"
```

```toml
# city.toml (city root)
[workspace]
provider = "claude"
global_fragments = ["command-glossary", "operational-awareness"]

[daemon]
patrol_interval = "30s"
max_restarts = 5
restart_window = "1h"
shutdown_timeout = "5s"

[[rigs]]
name = "myproject"
prefix = "mp"
# path lives in .gc/site.toml under [[rig]]
```

### Gastown Exec Orders (Automated Maintenance)

| Order | Interval | What It Does |
|-------|----------|-------------|
| gate-sweep | 30s | Evaluate/close timer, condition, and GitHub gates |
| beads-health | 30s | Beads provider health probe |
| dolt-health | 30s | Dolt data-plane health probe |
| dolt-remotes-patrol | 15m | Push beads data to configured remotes |
| orphan-sweep | 5m | Reset beads assigned to dead agents |
| cross-rig-deps | 5m | Convert satisfied cross-rig dependency blocks |
| spawn-storm-detect | 5m | Detect beads in crash recovery loops |
| mol-dog-doctor | 5m | Run `gc doctor` health sweep |
| mol-dog-phantom-db | 1h | Clean phantom Dolt databases |
| mol-dog-stale-db | 15m | Detect stale Dolt databases |
| mol-dog-jsonl | 15m | Export Dolt DBs to JSONL git archive |
| mol-dog-reaper | 30m | Reap stale wisps, purge old data |
| mol-dog-backup | 6h | Beads backup via Dolt |
| mol-dog-compactor | 24h | Dolt compaction / GC |
| wisp-compact | 1h | TTL-based cleanup of expired ephemeral beads |
| prune-branches | 6h | Clean stale gc/* branches from rigs |
| digest-generate | 24h | Generate daily activity digest |

---

## Runtime Providers

### Session Providers (How Agents Run)

| Provider | Config | Terminal | Attach | Nudge | Best For |
|----------|--------|----------|--------|-------|----------|
| **tmux** (default) | `provider = ""` | Full | Yes | Yes | Production, local dev |
| **subprocess** | `provider = "subprocess"` | None | No | No | CI, testing, headless |
| **exec** | `provider = "exec:<script>"` | Depends | Depends | Depends | Custom backends |
| **ACP** | `provider = "acp"` | None (JSON-RPC) | No | Yes | Agent Client Protocol |
| **K8s** | `provider = "k8s"` | tmux in pod | Yes (kubectl) | Yes | Kubernetes clusters |
| **hybrid** | `provider = "hybrid"` | Both | Both | Both | Mixed local+k8s |
| **auto** | (internal) | Both | Both | Both | Per-agent ACP routing |

### Tmux Provider Details
- Sessions created via `tmux new-session -d -s <name>`
- Per-city socket isolation via `[session] socket = "my-city"`
- Role-based color themes (gold=mayor, purple=deacon, teal=witness, etc.)
- Keybindings: `prefix-n` next, `prefix-p` prev, `prefix-g` agent menu
- Nudge locks serialize concurrent nudges per-session

### K8s Provider Details
- Each session = a K8s Pod with tmux inside container
- Native `client-go` (no kubectl for API calls)
- Supports prebaked images (skip staging) via `gc build-image`
- Configure via `[session.k8s]` or env vars

### Switching Providers
```toml
[session]
provider = "k8s"
```
```bash
export GC_SESSION=exec:/path/to/script
```

### Per-Agent ACP Override
```toml
[[agent]]
name = "smart-worker"
session = "acp"                      # This agent uses ACP even if city uses tmux
```

---

## Formulas, Molecules & Orders

### Formulas
TOML workflow templates defining multi-step work. File naming in v2 is flat
`<name>.toml` under `formulas/` (the `.formula.` infix was removed).

```toml
# formulas/my-workflow.toml
formula = "my-workflow"
description = "A multi-step task"
version = 1

[[steps]]
id = "setup"
title = "Setup workspace"
description = "Prepare the working environment"

[[steps]]
id = "implement"
title = "Do the work"
description = "Implement the changes for {{task}}"
needs = ["setup"]

[[steps]]
id = "verify"
title = "Verify results"
description = "Run tests and verify"
needs = ["implement"]
```

### Key Formulas (Gastown)

Visible with `gc formula list`:
- `mol-do-work` — Generic pool-worker scoped work formula
- `mol-scoped-work` — Scoped variant with explicit target/branch
- `mol-polecat-base` — Shared polecat step graph
- `mol-polecat-work` — Full polecat lifecycle (extends base)
- `mol-polecat-commit` — Commit-only variant for crew members
- `mol-deacon-patrol` — Patrol iteration with exponential backoff
- `mol-witness-patrol` — Patrol with orphan recovery
- `mol-refinery-patrol` — Merge queue processing
- `mol-shutdown-dance` — 3-attempt interrogation protocol
- `mol-idea-to-plan` — Planning pipeline with parallel review legs
- `mol-review-leg` — Single review pass sub-formula
- `mol-dog-jsonl`, `mol-dog-reaper`, `mol-dog-doctor`, etc. — Dog maintenance
- `mol-dolt-health`, `mol-dolt-remotes-patrol` — Dolt operations
- `mol-digest-generate` — Daily activity digest

### Formula Variables
```toml
[vars]
name = "world"                       # Simple variable with default

[vars.title]
description = "Task title"
required = true
default = "untitled"
enum = ["option1", "option2"]
pattern = "^[a-z]+"
```
Reference in steps as `{{name}}`. Pass at cook/sling time with `--var name=value`.

### Advanced Step Features
```toml
# Conditions — simple equality check
[[steps]]
id = "deploy"
condition = "{{env}} == staging"

# Loops — materialize N sequential iterations
[[steps]]
id = "batch"
[steps.loop]
count = 3
[[steps.loop.body]]
id = "process"
title = "Process batch {{i}}"

# Ralph — runtime retry with verification
[[steps]]
id = "build"
[steps.ralph]
max_attempts = 2
[steps.ralph.check]
mode = "exec"
path = "scripts/verify.sh"
timeout = "30s"

# Nested steps
[[steps]]
id = "backend"
[[steps.children]]
id = "api"
[[steps.children]]
id = "worker"
```

### Molecules & Wisps
- **Molecule**: Runtime instance of a formula (a bead tree). Independently trackable.
- **Wisp**: Ephemeral molecule (auto-GC'd after TTL). Lightweight.
- Instantiate molecule: `gc formula cook <formula> [--var key=val]`
- Instantiate wisp via sling: `gc sling --formula <formula> <agent> <bead>`

### Convergence Formulas
Special formula type for bounded iterative refinement. Uses `convergence = true`,
`required_vars`, and `evaluate_prompt` fields. Managed via `gc converge`:

```bash
gc converge create <bead>   # Start a convergence loop
gc converge list            # List active loops
gc converge status <id>     # Show loop status
gc converge iterate <id>    # Force next iteration (manual gate)
gc converge approve <id>    # Approve + close (manual gate)
gc converge retry <id>      # Retry a terminated loop
gc converge stop <id>       # Stop a loop
gc converge test-gate <id>  # Dry-run the gate condition
```
Limits via `[convergence] max_per_agent` and `max_total`.

### Orders (Scheduled Dispatch)
```toml
# orders/my-order.toml  (flat files, no .order. infix in v2)
[order]
description = "My scheduled action"
exec = "scripts/my-script.sh"        # OR formula = "my-formula"
pool = "dog"                         # Target agent (formula orders)
trigger = "cooldown"                 # Gate type
interval = "5m"
enabled = true
timeout = "60s"
```

**Gate Types:**
- `cooldown` — minimum interval since last run
- `cron` — 5-field cron schedule
- `condition` — shell command exits 0
- `event` — matching events after cursor
- `manual` — explicit `gc order run` only

---

## Rigs

### What's a Rig?
A rig is an external project directory managed by the city. Each rig gets:
- Its own `.beads/` database directory
- Per-rig agent instances (from rig-scoped pack agents)
- Isolated bead ID prefix
- Independent formula layers

### Managing Rigs
```bash
gc rig add /path/to/project                     # Register
gc rig add /path/to/project --include packs/gastown
gc rig add /path/to/project --name foo --prefix fx
gc rig add /path/to/project --start-suspended
gc rig add /path/to/existing --adopt            # Adopt existing .beads/
gc rig list                                     # List registered rigs
gc rig status                                   # Show rig status
gc rig suspend myproject                        # Pause rig agents
gc rig resume myproject                         # Resume rig agents
gc rig restart myproject                        # Restart rig agents
gc rig set-endpoint myproject                   # Set canonical endpoint ownership
gc rig remove myproject                         # Unregister
```

### Rig Configuration in `city.toml` (v2)
```toml
[[rigs]]
name = "myproject"
prefix = "mp"                        # Optional; auto-derived if omitted
includes = ["packs/gastown"]         # Optional; prefer rig-local pack.toml [imports]
default_sling_target = "polecat"
suspended = false
# path lives in .gc/site.toml under [[rig]]

[[rigs.overrides]]
agent = "polecat"
max_active_sessions = 3
idle_timeout = "1h"
```

### Rig paths in `.gc/site.toml`
```toml
[[rig]]
name = "myproject"
path = "/home/user/myproject"
```
The split keeps machine-local paths out of committed config.

---

## Skills

Skills are markdown help docs surfaced via `gc skill` and injected into agent
prompts. Introduced in 1.0 as part of the core pack.

Discovery:
- **City pack skills**: `skills/<name>/SKILL.md` under the city root
- **Imported pack shared skills**: binding-qualified (e.g. `core.gc-work`)
- **Agent-scoped skills**: `agents/<name>/skills/` for per-agent catalogs

Use `gc skill list` to see everything visible. The listing shows what's
available; use `gc doctor` to detect collisions. The materializer writes the
resolved set to `<scope-root>/.<vendor>/skills/` (e.g. `.claude/skills/`) on
`gc start`.

```bash
gc skill list                        # All visible skills
gc skill list --agent mayor          # Skills visible to a specific agent
gc skill list --session mayor-1      # Skills visible to a live session
```

Typical core skills that ship today: `core.gc-work`, `core.gc-city`,
`core.gc-rigs`, `core.gc-agents`, `core.gc-dispatch`, `core.gc-mail`,
`core.gc-dashboard`.

---

## CLI Command Reference

### City Lifecycle
```bash
gc init <path>              # Initialize a new city (v2 layout)
gc start [<path>]           # Start city under supervisor
gc stop [<path>]            # Stop city
gc restart [<path>]         # Restart city
gc status                   # City overview (--json for JSON)
gc suspend                  # Pause city (controller keeps running)
gc resume                   # Resume suspended city
gc reload                   # Reload config without restarting city/controller
gc doctor                   # Run diagnostic health checks (--fix, --verbose)
gc version                  # Show version
```

### Agent Config (Runtime moved to `gc session` / `gc runtime`)
```bash
gc agent add <name>         # Add an agent scaffold
gc agent suspend <name>     # Deactivate agent
gc agent resume <name>      # Reactivate agent
```

### Session Management
```bash
gc session list             # List sessions (--state, --template, --json)
gc session attach <name>    # Attach to session terminal
gc session new <agent>      # Create session (--alias, --title, --no-attach)
gc session close <name>     # Graceful close
gc session kill <name>      # Force kill
gc session suspend <name>   # Pause session
gc session peek <name>      # View recent session output
gc session nudge <name> "text"  # Send text to session
gc session logs <name>      # View session logs (--tail N, -f to follow)
gc session pin <name>       # Keep a session awake
gc session unpin <name>     # Remove wake pin
gc session wait <name>      # Register a dependency wait
gc session wake <name>      # Wake a session, clear holds
gc session reset <name>     # Restart fresh, preserve bead
gc session rename <name>    # Rename
gc session prune            # Close old suspended sessions
gc session submit <name>    # Submit with semantic delivery intent
```

### Runtime (Session-Internal, called by agents)
```bash
gc runtime drain             # Signal session to drain
gc runtime drain-ack         # Acknowledge drain
gc runtime drain-check       # Check drain status (exit 0 = draining)
gc runtime undrain           # Cancel drain
gc runtime request-restart   # Request controller restart (blocks until killed)
```

### Work Routing
```bash
gc sling [target] <bead-or-text>           # Route bead to agent
gc sling <agent> "prompt text"             # Create + route in one step
gc sling --formula <name> <agent> <id>     # Route with formula
gc sling --dry-run ...                     # Preview routing
gc sling --no-convoy ...                   # Skip auto-convoy creation
gc sling --no-formula ...                  # Suppress default formula
gc sling --merge mr|direct|local ...       # Set merge strategy
gc sling --owned ...                       # Mark convoy as owned
gc sling --nudge ...                       # Nudge after routing
gc sling --on <bead> ...                   # Attach formula wisp to bead
gc sling --force                           # Allow cross-rig routing
gc hook                                    # Check for available work
gc hook --inject                           # Hook-formatted output for injection
gc handoff [<target>]                      # Hand off to another agent
gc nudge status <session>                  # Show queued/dead-letter nudges
```

### Beads & Formulas
```bash
bd create "title"           # Create new bead
bd ready                    # List open beads
bd show <id>                # View details
bd close <id>               # Complete bead
gc formula list             # List available formulas
gc formula show <name>      # Display compiled formula
gc formula cook <name>      # Instantiate formula into bead store
gc converge create <bead>   # Start convergence loop
gc graph <bead-or-convoy>   # Dependency graph (--tree, --mermaid)
```

### Mail
```bash
gc mail send <to> -s "subject" -m "body"
gc mail inbox               # View unread messages
gc mail read <id>           # Read + mark read
gc mail peek <id>           # Read without marking
gc mail reply <id> -s "RE:" -m "reply"
gc mail archive <id>        # Archive (closes bead)
gc mail delete <id>         # Delete (closes bead)
gc mail mark-read <id>      # Mark a message read
gc mail mark-unread <id>    # Mark a message unread
gc mail thread <id>         # Show all messages in thread
gc mail count               # Unread count
gc mail check               # Check for mail (--inject for hook output)
```

### Convoys & Orders
```bash
gc convoy create "name" [beads...]  # Create work graph
gc convoy add <convoy> <bead>       # Link bead to convoy
gc convoy status <convoy>           # Progress
gc convoy target <convoy> <branch>  # Set target branch
gc convoy control <convoy>          # Execute control beads / run dispatcher
gc convoy check                     # Reconcile auto-close for all convoys
gc convoy land <convoy>             # Manually land owned convoy
gc convoy close <convoy>            # Close without landing
gc convoy delete <convoy>           # Close and optionally delete all beads
gc convoy delete-source <bead>      # Close workflows sourced from a bead
gc convoy reopen-source <bead>      # Reopen source bead after cleanup
gc convoy stranded                  # Find convoys with ready work but no workers
gc convoy list                      # List all convoys
gc order list                       # List configured orders
gc order show <name>                # Display full order definition
gc order check                      # Show which orders are due and why
gc order run <name>                 # Manually trigger order (bypasses gate)
gc order history [name]             # View run history
```

### Imports & Packs
```bash
gc import list                      # List imported packs
gc import add <source>              # Add an import (--name, --version)
gc import install                   # Install from pack.toml + packs.lock
gc import check                     # Validate installed state
gc import upgrade                   # Upgrade within version constraints
gc import remove <name>             # Remove an import
gc import why <name>                # Explain why an import is present
gc import migrate                   # Rewrite v1 city → v2 shape (--dry-run)
gc pack list                        # Show remote pack sources and cache
gc pack fetch                       # Clone missing / update existing remote packs
```

### Events
```bash
gc event emit ...                   # Emit an event to the city log
gc events                           # List events (API)
gc events --follow                  # Stream events (SSE)
gc events --type bead.created --since 1h
gc events --watch --type convoy.closed --timeout 5m
gc events --follow --after-cursor city-a:12,city-b:9
gc events --payload-match key=value
gc events --seq                     # Print current head cursor
```

### Skills
```bash
gc skill list                       # All visible skills
gc skill list --agent <name>        # Scope to agent catalog
gc skill list --session <id>        # Scope to live session
```

### Configuration & Diagnostics
```bash
gc config show                      # Dump resolved config as TOML
gc config explain                   # Resolved config with provenance
gc prime [agent]                    # Output agent behavioral prompt (--strict, --hook)
gc doctor                           # Run diagnostic health checks (--fix, --verbose)
gc trace status                     # Show trace arms and stream state
gc trace start <template>           # Start or extend tracing
gc trace stop <template>            # Stop tracing
gc trace tail                       # Follow trace records
gc trace show [--tick N]            # Show trace records
gc trace cycle <tick>               # Show cycle by tick id
gc trace reasons                    # Show reason codes observed
gc mcp list --agent <name>          # Show projected MCP catalog
gc mcp list --session <id>          # Live session projection
```

### Supervisor (Machine-Wide)
```bash
gc supervisor run            # Run supervisor in foreground
gc supervisor start          # Start background supervisor
gc supervisor stop           # Stop supervisor
gc supervisor status         # Check supervisor health
gc supervisor reload         # Trigger immediate reconciliation of all cities
gc supervisor install        # Install launchd/systemd service
gc supervisor uninstall      # Remove service
gc supervisor logs           # Tail supervisor log
gc cities list               # List registered cities
gc register [path] --name ALIAS   # Register a city (alias stored in site.toml)
gc unregister [path]         # Remove city from supervisor
```

### Waits (Durable Dependencies)
```bash
gc wait list                 # List active waits
gc wait inspect <id>         # Show wait details
gc wait cancel <id>          # Cancel a wait
gc wait ready <id>           # Mark wait as ready
```

### Dolt & Beads
```bash
gc dolt start                # Start Dolt server
gc dolt status               # Status
gc dolt logs                 # Tail log
gc dolt list                 # List databases
gc dolt sql                  # Interactive SQL shell
gc dolt sync                 # Push to configured remotes
gc dolt cleanup              # Remove orphaned databases
gc dolt recover              # Recover from read-only state
gc dolt rollback             # List/restore migration backups
gc beads health              # Check provider health
gc beads city                # Manage canonical city endpoint topology
```

### Services
```bash
gc service list              # List workspace services
gc service doctor            # Detailed service status
gc service restart <name>    # Restart a service
```

### Shell & Utilities
```bash
gc shell install             # Install completion hook in shell RC
gc shell remove              # Remove shell integration
gc shell status              # Show integration status
gc build-image [<path>]      # Build prebaked container image
gc dashboard                 # Launch web UI (or `serve`)
gc dashboard serve           # Start the web dashboard
gc bd ...                    # Run bd in the correct rig directory
gc gastown status            # Gastown-pack status command
```

---

## The Nine Concepts

Gas City's architecture rests on **5 irreducible primitives** and **4 derived mechanisms**.

### Layer 0-1: Primitives

1. **Agent Protocol** — Start/stop/prompt/observe agents regardless of session
   provider. SDK manages lifecycle; prompt defines behavior. These concerns
   never cross.

2. **Bead Store** — Universal persistence substrate. Everything is a bead.
   Single `Store` interface with four implementations.

3. **Event Bus** — Append-only pub/sub log. Two tiers: critical (bounded queue)
   and optional (fire-and-forget). Immutable, monotonically increasing sequence
   numbers.

4. **Config** — TOML loading with progressive activation. Config IS the feature
   flag. No separate feature flag system.

5. **Prompt Templates** — Go `text/template` in Markdown. All role behavior is
   user-supplied configuration. Zero hardcoded role names.

### Layer 2-4: Derived (Composed from Primitives)

6. **Messaging** — Mail = beads with type "message". Nudge = fire-and-forget text.

7. **Formulas & Molecules** — TOML workflow definitions → runtime bead trees.
   Wisps = ephemeral molecules. Orders = formulas with gate conditions.

8. **Dispatch (Sling)** — Find/spawn agent → select formula → create molecule →
   hook to agent → nudge → create convoy → log event.

9. **Health Patrol** — Ping agents, compare thresholds, publish stalls, restart
   with backoff. Erlang/OTP supervision model.

### Primitive Test (Before Adding New Primitives)
1. **Atomicity** — Can it be decomposed into existing primitives?
2. **Bitter Lesson** — Does it become MORE useful as models improve?
3. **ZFC** — Does Go handle transport only, with no judgment calls?

### Key Design Principles
- **GUPP**: "If you find work on your hook, YOU RUN IT." No confirmation, no waiting.
- **NDI**: Nondeterministic Idempotence — work (beads) is persistent; sessions are ephemeral.
- **ZFC**: Zero Framework Cognition — Go handles transport, not reasoning.
- **Bitter Lesson**: Every primitive must become MORE useful as models improve.

---

## Progressive Capability Model

You don't need to use everything. Gas City activates features based on which
config sections are present.

| Level | Config Required | What You Get |
|-------|----------------|-------------|
| 0-1 | `[workspace]` + one agent | Agent + manual task tracking |
| 2 | `[daemon]` | Controller loop (auto-reconciliation) |
| 3 | Pool settings (`max_active_sessions`) | Multiple agents + pool scaling |
| 4 | `[mail]` | Inter-agent messaging |
| 5 | Formula files + `[formulas]` | Formulas & molecules |
| 6 | `[daemon]` health fields | Health monitoring & patrol |
| 7 | `orders/` directory | Scheduled/triggered orders |
| 8 | All sections | Full orchestration |

**Start at Level 0-1 and add capabilities as needed.**

---

## Tutorials

Gas City ships 7 tutorials forming a progressive learning path.

### Tutorial 01: Cities and Rigs
Set up a city with `gc init`, choose a template, add a rig with `gc rig add`,
sling your first piece of work, watch it complete with `bd show <id> --watch`.

### Tutorial 02: Agents
Define agents via the v2 convention (`agents/<name>/agent.toml`). Set provider,
prompt template, scope, option defaults. Use `gc prime <agent>` to preview the
rendered prompt.

### Tutorial 03: Sessions
Two session modes: **polecats** (transient, spun up on demand) and **crew**
(persistent named sessions via `[[named_session]]` with `mode = "always"`).
Commands: `gc session list`, `peek`, `attach` (Ctrl-b d), `nudge`, `logs`, `pin`.

### Tutorial 04: Agent-to-Agent Communication
Agents communicate via **mail** (persistent, tracked, unread until processed)
and **slung work** (bead routing). No direct agent-to-agent connections. Hooks
auto-inject pending mail as system reminders via `gc mail check --inject`.

### Tutorial 05: Formulas
TOML workflow templates with steps, `needs`, variables (`{{name}}`), nested
steps (`[[steps.children]]`), conditions, loops (`[steps.loop] count = N`),
Ralph retry logic (`[steps.ralph] max_attempts = N`). Instantiate as wisps
(`gc sling --formula`) or molecules (`gc formula cook`).

### Tutorial 06: Beads
The universal work primitive. Every bead has ID, title, status
(open/in_progress/blocked/deferred/closed), and type
(task/message/session/molecule/wisp/convoy). Labels, metadata, dependencies
(blocks/tracks/related/parent-child/discovered-from), convoys.
Work discovery is pull-based: agent hooks query `bd ready` with routing metadata.

### Tutorial 07: Orders
Gate-conditioned actions checked every controller tick. Gate types:
**cooldown**, **cron**, **condition**, **event**, **manual**. Action types:
**formula** (dispatched to agent pool) and **exec** (shell script). Override
settings per-order in `city.toml` via `[[orders.overrides]]`. History tracked
as beads.

---

## V1 → V2 Migration

1.0 ships Pack/City v2 as the default shape. Existing v1 cities keep loading
for compatibility, but new features land in v2 first.

### What changed

| Area | V1 | V2 (1.0+) |
|------|-----|-----------|
| Pack schema | `schema = 1` | `schema = 2` |
| Pack imports | `[packs.<name>]` in `city.toml` | `[imports.<name>]` in `pack.toml` |
| City root pack | None — city.toml only | `pack.toml` at city root + `city.toml` |
| Agent declaration | `[[agent]]` blocks in TOML | `agents/<name>/` directories |
| Agent prompts | `prompts/<name>.md.tmpl` (flat) | `agents/<name>/prompt.template.md` |
| Formula files | `formulas/<name>.formula.toml` | `formulas/<name>.toml` |
| Order files | `orders/<name>/order.toml` | `orders/<name>.toml` (flat) |
| Rig paths | `[[rigs]] path = "..."` in `city.toml` | `[[rig]] path = "..."` in `.gc/site.toml` |
| Workspace name | `[workspace] name = "..."` | `workspace_name = "..."` in `.gc/site.toml` |
| City commands | N/A | `commands/<name>/run.sh` → `gc <cmd>` |
| Skills | N/A | `skills/<name>/SKILL.md` → `gc skill list` |

### Automatic migration

```bash
gc import migrate --dry-run         # Preview changes
gc import migrate                   # Rewrite v1 → v2
```

This walks `workspace.includes`, `[[agent]]` blocks, prompt files, overlays,
namepools, and moves them to v2 locations. Idempotent — safe to re-run.

### Manual migration checklist

1. Add `pack.toml` at city root with `schema = 2`
2. Move `workspace.name` → `.gc/site.toml` `workspace_name`
3. Convert `[packs.<name>]` → `[imports.<name>]` in `pack.toml`
4. For each inline `[[agent]]`, create `agents/<name>/agent.toml` (drop `name`)
5. Move each prompt from `prompts/<name>.md.tmpl` → `agents/<name>/prompt.template.md`
6. Rename `formulas/<name>.formula.toml` → `formulas/<name>.toml`
7. Flatten `orders/<name>/order.toml` → `orders/<name>.toml`
8. Move rig paths from `city.toml` → `.gc/site.toml`

### What still works in v2

- Inline `[[agent]]` blocks in `city.toml` (for crew members, patches, one-offs)
- `[packs.<name>]` in `city.toml` (superseded but still loads)
- Schema 1 packs (loaded in compatibility mode)
- Legacy file naming for formulas/orders/prompts (still recognized, but
  migrations go one-way)

---

## Known Issues & Gotchas

### Setup Gotchas (Most Common New-User Issues)

| Issue | Description | Fix |
|-------|------------|-----|
| **#245** | Dolt port env var mismatch — `GC_DOLT_PORT` vs `BEADS_DOLT_PORT` | `export BEADS_DOLT_PORT=$GC_DOLT_PORT` |
| #304 | OpenCode provider sessions start but never process beads | Use claude or codex |
| #157 | `gc rig add` prompts for GitHub credentials on macOS | — |
| #156 | Rig names must have distinct first two letters | Use distinct prefixes |

### Resolved in 1.0

- V2 merge wave (schema 2, convention agent discovery, `gc import`, `gc init` emits v2, rig paths out of `city.toml`, `workspace.name` retired, root city-pack commands work, convention-discovered agents visible to `gc prime`)
- Pool workers now correctly spawn for `gc sling`-routed work (#286)
- Closed named session beads no longer block session name reuse (#135)
- On-demand named sessions recover after quota exhaustion (#139)
- Config-drift no longer drains active sessions (#119)
- `gc init` writes a complete `.gitignore` (#301)
- `ensure_metadata` uses `jq //=` instead of overwriting (#145)

### General Tips
- **Use `GC_BEADS=file` for initial setup** — avoids Dolt/bd complexity
- **Run `gc doctor --fix`** after any config changes
- **The `.gc/` directory should never be committed** — in default `.gitignore`
- **Nudge before mail** — nudges are free; mail creates permanent Dolt commits
- **Start with the tutorial template** before jumping to gastown
- **Use `gc trace tail`** to debug reconciler behavior in real time
- **Use `gc skill list`** to discover curated quick-reference guides

### Notable Changes in 1.0 / 1.0.1

- **Pack/City v2 shipped**: schema 2 is the default; `gc init` emits the new
  convention shape; `gc import migrate` is the upgrade path for v1 cities
- **`.gc/site.toml`**: machine-local identity (`workspace_name`,
  `workspace_prefix`, rig paths) separated from checked-in config
- **`gc import` command family**: `add / install / check / upgrade / remove /
  why / migrate / list` replaces the old `[packs.<name>]` management
- **`gc reload`**: re-read config and process one reconcile tick without
  restarting the controller
- **`gc graph`**: dependency graph viewer with `--tree` and `--mermaid`
- **`gc events`**: rich event query/stream (filter by type, since, payload,
  watch, follow, cursor resume)
- **`gc event emit`**: explicit city event emission
- **`gc session pin/unpin/wait/submit`**: richer session lifecycle control
- **Core pack + `gc skill list`**: curated skill catalog (gc-work, gc-city,
  gc-rigs, gc-agents, gc-dispatch, gc-mail, gc-dashboard) surfaced to agents
- **Formula v2 default**: `[daemon] formula_v2 = true` is the baseline
- **`gc convoy control / delete / close / delete-source / reopen-source`**:
  richer convoy graph management
- **`gc converge approve / iterate / retry / stop / test-gate`**: manual-gate
  convergence controls
- **`gc dolt recover / rollback / sql / sync`**: direct data-plane tooling
- **`gc beads health / city`**: topology and health subcommands
- **`gc shell install/remove/status`**: completion hook management
- **`gc mcp list`**: projected MCP catalog inspector

---

## Gas Town → Gas City Migration

### Concept Mapping

| Gas Town | Gas City | Key Change |
|----------|----------|-----------|
| Town config + role homes | `city.toml` + `pack.toml` + packs | Centralized declarative config |
| Named role types | Configured agents | No hardcoded roles in SDK |
| Plugin | Order (exec or formula) | Shell → exec orders; agent work → formula orders |
| Convoy | Convoy bead + sling/formulas | Bead-backed, no special runtime layer |
| Dog | Exec order or pool agent | Prefer orders for shell tasks |
| Deacon watchdog | Controller + supervisor | Infrastructure as controller concerns |
| Path-based identity | `.gc/site.toml` + metadata | No cwd-derived assumptions |
| `~/gt/` directory structure | `city.toml` + `pack.toml` + `.gc/` runtime | Directories are implementation details |

### Command Mapping

| `gt` | `gc` | Notes |
|------|------|-------|
| install | init | Creates city |
| start / up | start | Starts under supervisor |
| down / shutdown | stop | Stops sessions |
| daemon | supervisor | Machine-wide runtime |
| status | status | City overview |
| dashboard | dashboard serve | Web UI |
| doctor | doctor | Health checks |
| config | config + city.toml | File-first |
| plugin | order | Controller automation |
| sling | sling | Direct mapping |
| handoff | handoff | Near-direct |
| convoy | convoy | Direct mapping |
| mail | mail | Near-direct |
| nudge | session nudge / nudge | `session nudge` for live; `gc nudge status` for deferred |
| agents | session + status | Generic sessions |
| bead / cat / show / close | bd | Bead CRUD |
| prime | prime | Direct mapping |

### Anti-Patterns to Avoid
- Exact `~/gt/...` directory structures
- Working-directory-derived identity
- New hardcoded role names in SDK code
- Plugin systems when orders suffice
- Special helper agents for shell commands (use exec orders)
- Duplicating durable state outside beads

### Fast Ramp Checklist
1. Read the Nine Concepts architecture doc
2. Study `pack.toml` + `city.toml` + `.gc/site.toml` layout
3. Learn Orders (map plugins → orders)
4. Read Formulas & Molecules
5. Study `examples/gastown/` (pack.toml + agents/ + city.toml) then
   `.gc/system/packs/gastown/`

---

## Example Cities

Example configurations ship in `examples/`:

| Example | Description |
|---------|-------------|
| **bd** | Beads integration setup |
| **dolt** | Dolt database management |
| **gastown** | Full multi-agent orchestration (primary example) |
| **hyperscale** | Large-scale agent pool configuration |
| **lifecycle** | Agent lifecycle management patterns |
| **swarm** | Distributed multi-agent orchestration |

---

## Organization Repos (gastownhall)

| Repo | Purpose |
|------|---------|
| `gascity` | Main SDK/CLI |
| `beads` | Work-tracking data layer (bd CLI) |
| `homebrew-gascity` | Homebrew tap |
| `homebrew-beads` | Homebrew tap for beads |
| `gc-core` | Core pack (skills, pool-worker prompt, shared assets) |
| `gc-registry` | Remote pack registry bootstrap |
| `gascity-packs` | Reusable configuration packs |
| `gascity-otel` | OpenTelemetry integration |
| `tmux-adapter` | Tmux runtime adapter |
| `gastown` | Original Gas Town (predecessor) |
| `community` | Community discussions |
| `website` / `docs` | Documentation |
| `overwatch` / `tim` / `wasteland` / `marketplace` | Supporting infrastructure |
