# Gas City Reference Guide

> Compiled from docs.gascityhall.com and the github.com/gastownhall/gascity
> source. Current as of v0.14.0 (2026-04-12).

---

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [City Initialization (`gc init`)](#city-initialization)
4. [Configuration Reference (`city.toml`)](#configuration-reference)
5. [Beads Setup (Work Tracking)](#beads-setup)
6. [Agents & Packs](#agents--packs)
7. [The Gastown Pack (Role Reference)](#the-gastown-pack)
8. [Runtime Providers (Sessions)](#runtime-providers)
9. [Formulas, Molecules & Orders](#formulas-molecules--orders)
10. [Rigs (Project Registration)](#rigs)
11. [CLI Command Reference](#cli-command-reference)
12. [The Nine Concepts (Architecture)](#the-nine-concepts)
13. [Progressive Capability Model](#progressive-capability-model)
14. [Tutorials](#tutorials)
15. [Known Issues & Gotchas](#known-issues--gotchas)
16. [Gas Town → Gas City Migration](#gas-town--gas-city-migration)
17. [Example Cities](#example-cities)
18. [Pack/City v2 Roadmap](#packcity-v2-roadmap)

---

## Overview

Gas City is an **orchestration-builder SDK for multi-agent systems**. It extracts
the reusable infrastructure from Gas Town into a configurable toolkit with:

- **Declarative city configuration** via `city.toml`
- **Multiple runtime providers**: tmux, subprocess, exec, ACP, Kubernetes
- **Beads-backed work tracking**: tasks, mail, molecules, waits, convoys
- **Controller/supervisor loop**: reconciles desired state to running state
- **Packs, overrides, and rig-scoped orchestration** for multi-project setups

Written in Go (93.4%). MIT licensed. 242K+ lines of Go.

**Key difference from Gas Town**: Gas City is configuration-first. There are no
hardcoded role names in the SDK. All roles (mayor, deacon, polecat, etc.) are
defined in **packs** — reusable config directories. The SDK provides primitives;
packs provide behavior.

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
| pgrep | Always | Process detection | (included in macOS) |
| lsof | Always | Port detection | (included in macOS) |
| dolt | Always | Beads data plane | `brew install dolt` |
| bd | Always | Beads CLI | `brew install gastownhall/beads/beads` |
| flock | Always | File locking | `brew install flock` |
| Go 1.25+ | Source builds | Compilation | `brew install go` |

Homebrew installs all 6 runtime dependencies automatically (tmux, git, jq, dolt, bd, flock).

**Pinned versions** (from `deps.env`):
- Dolt: 1.85.0
- BD commit: 9d9d0e5
- BR (beads_rust): 0.1.20

### To skip Dolt/bd entirely
Set `GC_BEADS=file` or add `[beads] provider = "file"` to `city.toml`.
The file provider uses JSON on disk — suitable for tutorials and small setups.

---

## City Initialization

### Basic Flow
```bash
gc init ~/my-city        # Interactive wizard
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
gc init --from examples/gastown ~/my-city    # Copy gastown example directory
gc init --file my-config.toml ~/my-city      # Use custom TOML file
gc init --bootstrap-profile k8s-cell ~/pod   # Kubernetes container mode
```

### What `gc init` Creates

```
my-city/
├── city.toml              # Main configuration
├── .gc/                   # Runtime root (DO NOT commit)
│   ├── system/            # System-managed files
│   │   ├── packs/         # Built-in packs (gastown, maintenance, bd, dolt)
│   │   └── bin/           # System binaries (gc-beads-bd)
│   ├── cache/             # Pack fetch cache
│   │   ├── packs/
│   │   └── includes/
│   ├── runtime/           # Runtime state
│   ├── controller.lock    # Exclusive controller lock
│   ├── controller.sock    # Unix control socket
│   └── events.jsonl       # Event log
├── prompts/               # Prompt templates (9 defaults embedded)
├── formulas/              # Formula definitions (6 defaults embedded)
├── orders/                # Order definitions
├── scripts/               # Custom scripts
└── hooks/                 # Provider hook configs (claude.json, etc.)
```

### Init Steps (Internal)
1. Create runtime scaffold (`.gc/` directory tree)
2. Install Claude Code hooks (`hooks/claude.json` / `settings.json`)
3. Write default prompt files (9 embedded: mayor, worker, foreman, etc.)
4. Write default formula files (6 embedded: cooking, mol-do-work, etc.)
5. Write `city.toml`
6. Check provider readiness (login/auth probes)
7. Materialize `gc-beads-bd` script and built-in packs
8. Register city with supervisor

---

## Configuration Reference

### Top-Level `city.toml` Schema

```toml
# ─── WORKSPACE (required) ───────────────────────────────────────────
[workspace]
name = "my-city"                    # City name (required)
provider = "claude"                 # Default LLM provider
start_command = ""                  # Override provider command
includes = ["packs/gastown"]        # Pack directories to include
default_rig_includes = ["packs/gastown"]  # Default packs for new rigs
global_fragments = ["command-glossary"]   # Prompt fragments for all agents
install_agent_hooks = true          # Install provider hooks on init

# ─── AGENTS (required, at least one) ────────────────────────────────
[[agent]]
name = "mayor"                      # Unique identifier (required)
scope = "city"                      # "city" or "rig"
provider = "claude"                 # Override workspace provider
start_command = ""                  # Override provider command
prompt_template = "prompts/mayor.md"
prompt_mode = "arg"                 # "arg", "flag", or "none"
nudge = "Check hook and mail."      # Text sent after session ready
work_dir = ".gc/agents/mayor"       # Session working directory
overlay_dir = "overlays/default"    # Claude settings overlay
wake_mode = "fresh"                 # "fresh" (new session) or "resume"
suspended = false                   # Skip during reconciliation
idle_timeout = "1h"                 # Max inactivity before sleep
sleep_after_idle = ""               # Override idle sleep policy
pre_start = ["scripts/setup.sh"]    # Shell commands before session
session_setup = ["tmux cmd..."]     # Commands after session creation (supports templates)
session_setup_script = "scripts/theme.sh"
session_live = ["tmux cmd..."]      # Idempotent commands re-applied on config change
env = { KEY = "value" }             # Extra environment variables
min_active_sessions = 0             # Minimum live sessions
max_active_sessions = 1             # Maximum concurrent sessions (pool size)
scale_check = "script.sh"          # Shell command returning desired count
drain_timeout = ""                  # Max drain wait for this agent
namepool = "namepools/mad-max.txt"  # Names for pool instances
fallback = false                    # Can be overridden by same-named agent
depends_on = ["other-agent"]        # Start ordering
session = ""                        # "acp" for Agent Client Protocol
inject_fragments = ["fragment-name"]
attach = false                      # Auto-attach on create
description = ""                    # Human-readable description
default_sling_formula = ""          # Default formula when slung to this agent
work_query = ""                     # Override work discovery query
sling_query = ""                    # Override sling routing query
on_boot = ""                        # Shell command on session start
on_death = ""                       # Shell command on session close
install_agent_hooks = []            # Provider hook configs to install (e.g. ["claude"])
option_defaults = {}                # Default provider options (model, effort, permission_mode)

# ─── NAMED SESSIONS ─────────────────────────────────────────────────
[[named_session]]
template = "mayor"                  # Agent template to use
alias = ""                          # Short name for attach/nudge
scope = "city"                      # "city" or "rig"
mode = "always"                     # "always" or "manual"
title = ""                          # Human-readable session title
wake_mode = "resume"                # Override agent wake_mode for this session

# ─── RIGS ────────────────────────────────────────────────────────────
[[rigs]]
name = "myproject"                  # Unique identifier (required)
path = "/path/to/project"           # Absolute filesystem path (required)
prefix = ""                         # Override auto-derived bead ID prefix
includes = ["packs/gastown"]        # Pack directories
max_active_sessions = 10            # Rig-level session cap
default_sling_target = "polecat"    # Default target for gc sling
session_sleep = {}                  # Override idle sleep defaults
dolt_host = ""                      # Override city-level Dolt host
dolt_port = 0                       # Override city-level Dolt port
formulas_dir = ""                   # Rig-local formula overrides

[[rigs.overrides]]                  # Per-agent overrides (no pack forking)
agent = "polecat"
provider = "gemini"
idle_timeout = "30m"
max_active_sessions = 10

# ─── PROVIDERS ───────────────────────────────────────────────────────
[providers.my-custom]
command = "my-agent"
args = ["--flag"]
prompt_mode = "arg"                 # "arg", "flag", "none"
prompt_flag = "--prompt"
supports_acp = false
supports_hooks = false
ready_delay_ms = 0
ready_prompt_prefix = ""
resume_flag = "--resume"
resume_style = "flag"               # "flag" or "subcommand"
resume_command = ""                 # Template with {{.SessionKey}}
session_id_flag = "--session-id"
permission_modes = { auto = "--dangerously-skip-permissions" }
options_schema = {}                 # Configurable options (model, etc.)

# ─── BEADS (work tracking backend) ──────────────────────────────────
[beads]
provider = "bd"                     # "bd" (default), "file", or "exec:<script>"

# ─── SESSION (runtime provider) ─────────────────────────────────────
[session]
provider = ""                       # "" = tmux (default), "k8s", "acp", "subprocess", "exec:<script>"
setup_timeout = "10s"
startup_timeout = "60s"
socket = ""                         # Tmux socket name (defaults to workspace name)
nudge_ready_timeout = "10s"         # Timeout waiting for session ready before nudge
nudge_retry_interval = "500ms"      # Retry interval for nudge delivery
nudge_lock_timeout = "30s"          # Max time holding nudge lock
debounce_ms = 500                   # Session event debounce
display_ms = 5000                   # Session display duration
remote_match = ""                   # Hybrid provider remote matching pattern

[session.k8s]
namespace = "gc"
cpu_request = "50m"
mem_request = "128Mi"
cpu_limit = "200m"
mem_limit = "256Mi"
prebaked = false                    # Skip staging if image has city pre-installed

[session.acp]
handshake_timeout = "30s"
output_buffer = 1000

# ─── MAIL ────────────────────────────────────────────────────────────
[mail]
provider = ""                       # Default: beadmail (bead-backed)

# ─── EVENTS ──────────────────────────────────────────────────────────
[events]
provider = ""                       # Default: file-based JSONL

# ─── DOLT ────────────────────────────────────────────────────────────
[dolt]
port = 3307                         # Dolt SQL server port
host = ""                           # External Dolt host (empty = local)

# ─── DAEMON (controller settings) ───────────────────────────────────
[daemon]
patrol_interval = "30s"             # Reconciliation tick frequency
max_restarts = 5                    # Crash loop threshold
restart_window = "1h"               # Sliding window for restart counting
shutdown_timeout = "5s"             # Grace period before force-kill
wisp_gc_interval = "5m"             # Wisp garbage collection frequency
wisp_ttl = "24h"                    # Closed wisp retention
formula_v2 = false                  # Opt-in formula v2 graph workflow
drift_drain_timeout = "2m"          # Max drain wait during config-drift restart
probe_concurrency = 8               # Max concurrent bd subprocess probes
observe_paths = []                  # Extra Claude JSONL session dirs to watch

# ─── API ─────────────────────────────────────────────────────────────
[api]
port = 9443                         # HTTP API port (0 = disabled)
bind = "127.0.0.1"                  # Listen address
allow_mutations = false             # Required for non-localhost

# ─── FORMULAS ────────────────────────────────────────────────────────
[formulas]
dir = "formulas"                    # Formula directory

# ─── ORDERS ──────────────────────────────────────────────────────────
[orders]
skip = []                           # Order names to skip
max_timeout = "300s"
# [[orders.overrides]]              # Per-order setting overrides

# ─── CONVERGENCE ─────────────────────────────────────────────────────
[convergence]
max_per_agent = 2                   # Max active convergence loops per agent
max_total = 10                      # Max total active loops

# ─── SESSION SLEEP ───────────────────────────────────────────────────
[session_sleep]
interactive_resume = "4h"           # Idle timeout for interactive resume sessions
interactive_fresh = "1h"            # Idle timeout for interactive fresh sessions
noninteractive = "30m"              # Idle timeout for non-interactive sessions ("off" to disable)

# ─── CHAT SESSIONS ───────────────────────────────────────────────────
[chat_sessions]
idle_timeout = "4h"                 # Auto-suspend detached chat sessions

# ─── AGENT DEFAULTS ─────────────────────────────────────────────────
[agent_defaults]
model = ""                          # Default model for all agents
wake_mode = "fresh"
default_sling_formula = ""          # City-level default formula for agents
allow_overlay = true
allow_env_override = true

# ─── PATCHES (post-composition modifications) ───────────────────────
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
kind = "proxy_process"              # "workflow" or "proxy_process"
publish_mode = "private"            # "private" or "direct"
state_root = ""                     # Service state directory

# ─── PACKS (remote sources) ─────────────────────────────────────────
[packs.remote-pack]
source = "https://github.com/example/pack.git"
ref = "v1.0.0"
path = "pack"                       # Subdirectory within repo
```

### Template Variables (for session_setup, work_dir, etc.)
- `{{.Session}}` — session name
- `{{.Agent}}` — full agent name
- `{{.AgentBase}}` — base agent name (without pool index)
- `{{.Rig}}` — rig name
- `{{.RigRoot}}` — rig absolute path
- `{{.CityRoot}}` — city directory
- `{{.CityName}}` — city name
- `{{.WorkDir}}` — resolved working directory
- `{{.ConfigDir}}` — pack config directory (for script paths)

### Built-in LLM Providers (11)
`claude`, `codex`, `gemini`, `cursor`, `copilot`, `amp`, `opencode`, `auggie`, `pi`, `omp`, `sourcegraph`

Each has pre-configured: command, args, prompt mode, ready detection, process names,
permission modes, options schema (model, effort), resume support.

---

## Beads Setup

**This is the most common pain point for new users.**

### What Are Beads?
Beads are the **universal work unit**. Everything is a bead: tasks, mail, molecules,
convoys, epics. Each has ID, title, status (open/in_progress/closed), type, labels,
metadata, and dependencies.

### Three Bead Store Backends

| Backend | Config | IDs | Backend Tech | Best For |
|---------|--------|-----|-------------|----------|
| **bd** (default) | `provider = "bd"` | `bd-XXXX` | Dolt SQL server + `bd` CLI | Production, multi-agent |
| **file** | `provider = "file"` | `gc-N` | JSON file on disk | Tutorials, single-agent, no Dolt needed |
| **exec** | `provider = "exec:/path/to/script"` | varies | User-supplied script | Custom backends (SQLite, PostgreSQL, etc.) |

### Choosing a Provider

**For getting started quickly** (no Dolt/bd dependencies):
```toml
[beads]
provider = "file"
```

**For production** (default, requires dolt + bd + flock):
```toml
[beads]
provider = "bd"
```

**Via environment variable** (highest priority):
```bash
export GC_BEADS=file        # or "bd" or "exec:/path/to/script"
```

Priority: `GC_BEADS` env var → `city.toml [beads].provider` → `"bd"` default

### How Beads Init Works
1. `gc start` calls `startBeadsLifecycle()`
2. Starts backing service (Dolt for bd provider)
3. Initializes beads for the city root directory
4. For each rig: initializes beads in `<rig>/.beads/` directory
5. Installs agent hooks (Claude, Gemini, etc.)
6. Regenerates cross-rig routes

### Per-Rig Beads
Each rig gets its own `.beads/` directory with isolated bead IDs (using the rig's prefix).
The city root also has its own beads store for city-scoped work.

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

### ⚠️ CRITICAL BUG: Dolt Port Mismatch (#245)
Gas City injects `GC_DOLT_PORT` into tmux sessions, but `bd` reads `BEADS_DOLT_PORT`
(defaulting to 3307). **Workaround:**
```bash
export BEADS_DOLT_PORT=$GC_DOLT_PORT
```

---

## Agents & Packs

### What's a Pack?
A reusable directory containing agent definitions and supporting assets:
```
my-pack/
├── pack.toml          # Agent definitions + metadata
├── prompts/           # Prompt templates (.md.tmpl)
├── scripts/           # Session setup scripts
├── formulas/          # Formula definitions
│   └── orders/        # Scheduled orders
├── overlays/          # Claude settings overrides
├── doctor/            # Health check scripts
└── commands/          # Custom gc subcommands
```

### pack.toml Structure
```toml
[pack]
name = "my-pack"
schema = 1                          # Format version
city_agents = ["mayor", "deacon"]   # Which agents run at city scope (not per-rig)
includes = ["../other-pack"]        # Compose with other packs

[[agent]]
name = "worker"
scope = "rig"                       # "city" or "rig"
# ... same fields as [[agent]] in city.toml

[formulas]
dir = "formulas"

[[doctor]]
name = "check-deps"
script = "doctor/check-deps.sh"
description = "Verify dependencies"
```

### Dual-Scope Packs
`city_agents` controls partitioning:
- **City expansion** (`workspace.includes`): retains only listed agents with `dir=""`
- **Rig expansion** (`rigs[].includes`): excludes city agents, keeps only per-rig agents

### Including Packs
```toml
# City-level
[workspace]
includes = ["packs/gastown"]

# Rig-level
[[rigs]]
name = "myproject"
includes = ["packs/gastown"]

# Remote
[packs.remote]
source = "https://github.com/example/pack.git"
ref = "v1.0.0"
```

### Overriding Without Forking
```toml
[[rigs.overrides]]
agent = "polecat"
provider = "gemini"
idle_timeout = "30m"
max_active_sessions = 10
```

---

## The Gastown Pack

The flagship multi-agent orchestration pack. Three composable sub-packs:
- **gastown** — domain-specific coding workflow
- **maintenance** — generic infrastructure (dog pool, exec orders)
- **dolt** — Dolt database management

### Agent Roles

| Role | Scope | Pool | Metaphor | Purpose |
|------|-------|------|----------|---------|
| **Mayor** | City | Singleton (`max=1`) | Drive shaft | Global coordinator. Dispatches work via `gc sling`, manages rigs, handles escalations. CAN edit code directly. |
| **Deacon** | City | Singleton (`max=1`) | Flywheel | Town-wide patrol. Closes gates, checks convoys, monitors health, owns diagnostic signals. Silent when healthy (exponential backoff). |
| **Boot** | City | Singleton (`max=1`) | — | Deacon watchdog. Ephemeral — spawned fresh each tick. Answers: "is the deacon stuck?" |
| **Witness** | Rig | Singleton (`max=1`) | Pressure gauge | Per-rig work-health monitor. Core job: orphaned bead recovery. Also monitors refinery queue and stuck polecats. |
| **Refinery** | Rig | Singleton (`max=1`, on-demand) | Gearbox | Merge queue processor. Sequential rebase protocol. NEVER writes code — only merges. |
| **Polecat** | Rig | 0-5 | Piston | Transient workers in isolated worktrees. Follow strict formula: load → branch → implement → test → submit → exit. Named from Mad Max pool. |
| **Crew** | Rig | Named individuals | — | Persistent workers. Push directly to main. Long-lived identity. Declared inline in city.toml (not in packs). |
| **Dog** | City | 0-3 | On-demand piston | Infrastructure utility. Runs shutdown dance (3-attempt interrogation), JSONL export, stale wisp reaping. Zero mail. |

All singleton agents now have explicit `max_active_sessions = 1` and `wake_mode = "fresh"`
constraints. The polecat nudge references `gc hook` (checks assigned work first, then
routed pool work) rather than raw `bd` commands.

### Registering the Full Gastown Setup
```toml
# city.toml
[workspace]
name = "my-city"
provider = "claude"
includes = ["packs/gastown"]
global_fragments = ["command-glossary", "operational-awareness"]

[daemon]
patrol_interval = "30s"
max_restarts = 5
restart_window = "1h"
shutdown_timeout = "5s"

# Register a rig to activate per-rig agents
[[rigs]]
name = "myproject"
path = "/path/to/your/project"
includes = ["packs/gastown"]

# Optional: named crew member
[[agent]]
name = "wolf"
dir = "myproject"
prompt_template = "packs/gastown/prompts/crew.md.tmpl"
overlay_dir = "packs/gastown/overlays/crew"
idle_timeout = "4h"
pre_start = ["packs/gastown/scripts/worktree-setup.sh ..."]
```

### Gastown Exec Orders (Automated Maintenance)

| Order | Interval | What It Does |
|-------|----------|-------------|
| gate-sweep | 30s | Evaluate/close timer, condition, and GitHub gates |
| orphan-sweep | 5m | Reset beads assigned to dead agents back to pool |
| cross-rig-deps | 5m | Convert satisfied cross-rig dependency blocks |
| spawn-storm-detect | 5m | Detect beads in crash recovery loops |
| mol-dog-jsonl | 15m | Export Dolt DBs to JSONL git archive |
| mol-dog-reaper | 30m | Reap stale wisps, purge old data, auto-close stale issues |
| wisp-compact | 1h | TTL-based cleanup of expired ephemeral beads |
| prune-branches | 6h | Clean stale gc/* branches from all rigs |
| digest-generate | 24h | Generate daily activity digest |

---

## Runtime Providers

### Session Providers (How Agents Run)

| Provider | Config | Terminal | Attach | Nudge | Best For |
|----------|--------|----------|--------|-------|----------|
| **tmux** (default) | `provider = ""` | Full | Yes | Yes | Production, local dev |
| **subprocess** | `provider = "subprocess"` | None | No | No | CI, testing, headless |
| **exec** | `provider = "exec:<script>"` | Depends | Depends | Depends | Custom backends (GNU Screen, etc.) |
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
- Supports prebaked images (skip staging)
- Configure via `[session.k8s]` or env vars

### Switching Providers
```toml
# In city.toml
[session]
provider = "k8s"

# Or via environment
export GC_SESSION=exec:/path/to/script
```

### Per-Agent ACP Override
```toml
[[agent]]
name = "smart-worker"
session = "acp"    # This agent uses ACP even if city uses tmux
```

---

## Formulas, Molecules & Orders

### Formulas
TOML workflow templates defining multi-step work:

```toml
# formulas/my-workflow.formula.toml
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
- `mol-polecat-work` — Full polecat lifecycle (extends mol-polecat-base)
- `mol-deacon-patrol` — 6-step patrol iteration with exponential backoff
- `mol-witness-patrol` — 5-step patrol with orphan recovery
- `mol-refinery-patrol` — 7-step merge queue processing
- `mol-shutdown-dance` — 3-attempt interrogation protocol (60s→120s→240s)
- `mol-idea-to-plan` — 10-step planning pipeline with parallel review legs

### Formula Variables
```toml
[vars]
name = "world"                      # Simple variable with default

[vars.title]
description = "Task title"
required = true
default = "untitled"
enum = ["option1", "option2"]       # Restrict to allowed values
pattern = "^[a-z]+"                 # Regex validation
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
# Exit 0 = success, non-zero = retry

# Nested steps — parent as container
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
`required_vars`, and `evaluate_prompt` fields. Managed via `gc converge create <bead>`.
Limits controlled by `[convergence] max_per_agent` and `max_total` in config.

### Orders (Scheduled Dispatch)
```toml
# formulas/orders/my-order/order.toml
exec = "scripts/my-script.sh"    # OR formula = "my-formula"
pool = "dog"                     # Target agent (formula orders only)
gate = "cooldown"                # Gate type
interval = "5m"                  # Cooldown interval
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
gc rig add /path/to/project --include packs/gastown  # With pack
gc rig add /path/to/project --name foo --prefix fx   # Custom name/prefix
gc rig add /path/to/project --start-suspended   # Register without starting agents
gc rig list                                     # List registered rigs
gc rig default                                  # Show/set default rig
gc rig status                                   # Show rig status
gc rig suspend myproject                        # Pause rig agents
gc rig resume myproject                         # Resume rig agents
gc rig restart myproject                        # Restart rig agents
gc rig remove myproject                         # Unregister
```

### Rig Configuration in city.toml
```toml
[[rigs]]
name = "myproject"
path = "/home/user/myproject"
includes = ["packs/gastown"]
default_sling_target = "polecat"

[[rigs.overrides]]
agent = "polecat"
max_active_sessions = 3
idle_timeout = "1h"
```

---

## CLI Command Reference

### City Lifecycle
```bash
gc init <path>              # Initialize a new city
gc start [<path>]           # Start city under supervisor
gc stop [<path>]            # Stop city
gc restart [<path>]         # Restart city
gc status                   # City overview
gc suspend                  # Pause city (controller keeps running)
gc resume                   # Resume suspended city
gc doctor                   # Run diagnostic health checks
gc doctor --fix             # Auto-repair common issues
gc version                  # Show version
```

### Agent & Session Management
```bash
gc session list             # List all sessions (--state, --template, --json)
gc session attach <name>    # Attach to session terminal
gc session new <agent>      # Create session (--alias, --title, --no-attach)
gc session close <name>     # Graceful close
gc session kill <name>      # Force kill
gc session suspend <name>   # Pause session
gc session peek <name>      # View recent session output
gc session nudge <name> "text"  # Send text to session
gc session logs <name>      # View session logs (--tail N, -f to follow)
gc session wait <name>      # Create durable wait
gc session wake <name>      # Wake sleeping session
gc session reset <name>     # Reset session state
gc session rename <name>    # Rename a session
gc session prune            # Clean up stale sessions
gc session submit <name>    # Submit session work
gc agent list               # List configured agents
gc agent status             # Show agent status
gc agent describe <name>    # Describe agent config
gc agent suspend <name>     # Deactivate agent
gc agent resume <name>      # Reactivate agent
```

### Work Routing
```bash
gc sling [target] <bead-or-text>    # Route bead to agent
gc sling <agent> "prompt text"      # Create + route in one step
gc sling --formula <f> <agent> <id> # Route with formula
gc sling --dry-run ...              # Preview routing without creating
gc sling --no-convoy ...            # Skip auto-convoy creation
gc sling --merge ...                # Set merge strategy metadata
gc sling --owned ...                # Mark convoy as owned (no auto-close)
gc hook                             # Check for available work
gc hook --inject                    # Output hook results for injection
gc handoff [<target>]               # Hand off to another agent
gc nudge list                       # List deferred nudges
```

### Beads & Formulas
```bash
bd create "title"           # Create new bead
bd ready                    # List open beads
bd show <id>                # View details
bd close <id>               # Complete bead
gc formula list             # List available formulas
gc formula show <name>      # Display formula
gc formula cook <name>      # Instantiate formula
gc converge create <bead>   # Start convergence loop
```

### Mail
```bash
gc mail send <to> -s "subject" -b "body"
gc mail inbox               # View unread messages
gc mail read <id>           # Read message
gc mail reply <id> -b "reply text"
gc mail count               # Unread count
gc mail check               # Check without marking read
```

### Convoys & Orders
```bash
gc convoy create "name" [beads...] # Create work graph (auto-links beads)
gc convoy add <convoy> <bead>      # Link bead to convoy
gc convoy status <convoy>          # Check progress
gc convoy target <convoy> <branch> # Set target branch
gc convoy check                    # Reconcile auto-close for all convoys
gc convoy land <convoy>            # Manually land convoy
gc convoy stranded                 # Find open unassigned convoy beads
gc convoy list                     # List all convoys
gc order list                      # List configured orders
gc order show <name>               # Display full order definition
gc order check                     # Show which orders are due and why
gc order run <name>                # Manually trigger order (bypasses gate)
gc order history [name]            # View run history (all or specific)
```

### Configuration & Diagnostics
```bash
gc config explain           # Validate and inspect config with provenance
gc prime [agent]            # Output agent behavioral prompt
gc doctor                   # Run diagnostic health checks
gc doctor --fix             # Auto-repair common issues
gc trace show               # Show reconciler trace
gc trace tail               # Follow reconciler trace
gc trace start/stop         # Toggle tracing
gc trace reasons            # Show reconciliation reasons
gc trace cycle              # Show last reconciliation cycle
```

### Supervisor (Machine-Wide)
```bash
gc supervisor run            # Run supervisor in foreground
gc supervisor start          # Start background supervisor
gc supervisor stop           # Stop supervisor
gc supervisor status         # Check supervisor health
gc supervisor reload         # Reload all city configs
gc supervisor install        # Install launchd/systemd service
gc supervisor uninstall      # Remove launchd/systemd service
gc supervisor logs           # View supervisor logs
gc cities                    # List registered cities
gc unregister <path>         # Remove city from supervisor
```

### Waits (Durable Dependencies)
```bash
gc wait list                 # List active waits
gc wait inspect <id>         # Show wait details
gc wait cancel <id>          # Cancel a wait
gc wait ready <id>           # Mark wait as ready
```

### Runtime (Session-Internal)
```bash
gc runtime drain             # Signal session to drain
gc runtime drain-ack         # Acknowledge drain signal
gc runtime drain-check       # Check drain status
gc runtime undrain           # Cancel drain
gc runtime request-restart   # Request session restart
```

### Utilities
```bash
gc skill [topic]             # Curated references and guides
gc pack list                 # List installed packs
gc build-image               # Build prebaked container image
gc service list              # List workspace services
gc service doctor            # Check service health
gc service restart           # Restart services
gc converge create <bead>    # Start convergence loop
gc dashboard                 # Launch web UI
```

---

## The Nine Concepts

Gas City's architecture rests on **5 irreducible primitives** and **4 derived mechanisms**.

### Layer 0-1: Primitives

1. **Agent Protocol** — Start/stop/prompt/observe agents regardless of session provider.
   SDK manages lifecycle; prompt defines behavior. These concerns never cross.

2. **Bead Store** — Universal persistence substrate. Everything is a bead.
   Single `Store` interface with four implementations.

3. **Event Bus** — Append-only pub/sub log. Two tiers: critical (bounded queue)
   and optional (fire-and-forget). Immutable, monotonically increasing sequence numbers.

4. **Config** — TOML loading with progressive activation. Config IS the feature flag.
   No separate feature flag system.

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
1. **Atomicity** — Can it be decomposed into existing primitives? If yes, it's derived.
2. **Bitter Lesson** — Does it become MORE useful as models improve?
3. **ZFC** — Does Go handle transport only, with no judgment calls?

### Key Design Principles
- **GUPP**: "If you find work on your hook, YOU RUN IT." No confirmation, no waiting.
- **NDI**: Nondeterministic Idempotence — work (beads) is persistent; sessions are ephemeral.
- **ZFC**: Zero Framework Cognition — Go handles transport, not reasoning.
- **Bitter Lesson**: Every primitive must become MORE useful as models improve.

---

## Progressive Capability Model

You don't need to use everything. Gas City activates features based on what config
sections are present:

| Level | Config Required | What You Get |
|-------|----------------|-------------|
| 0-1 | `[workspace]` + `[[agent]]` | Agent + manual task tracking |
| 2 | `[daemon]` | Controller loop (auto-reconciliation) |
| 3 | `[[agent]]` with pool settings | Multiple agents + pool scaling |
| 4 | `[mail]` | Inter-agent messaging |
| 5 | Formula files + `[formulas]` | Formulas & molecules |
| 6 | `[daemon]` health fields | Health monitoring & patrol |
| 7 | `orders/` directories | Scheduled/triggered orders |
| 8 | All sections | Full orchestration |

**Start at Level 0-1 and add capabilities as needed.**

---

## Tutorials

Gas City ships 7 tutorials that form a progressive learning path. Each builds on
the previous.

### Tutorial 01: Cities and Rigs
Setup a city with `gc init`, choose a template (tutorial/gastown/custom), add a rig
with `gc rig add`, sling your first piece of work, and watch it complete with
`bd show <id> --watch`.

### Tutorial 02: Agents
Define custom agents in `city.toml` with `[[agent]]` blocks. Set provider, prompt
template, scope (city vs rig), and option defaults (model, permission_mode). Use
`gc prime <agent>` to preview the rendered prompt.

### Tutorial 03: Sessions
Two session modes: **polecats** (transient, spun up on demand, shut down when idle)
and **crew** (persistent named sessions via `[[named_session]]` with `mode = "always"`).
Key commands: `gc session list`, `gc session peek`, `gc session attach` (Ctrl-b d to
detach), `gc session nudge`, `gc session logs` (--tail N, -f to follow).

### Tutorial 04: Agent-to-Agent Communication
Agents communicate via **mail** (persistent, tracked, unread until processed) and
**slung work** (bead routing). No direct agent-to-agent connections — this ensures
session independence and crash safety. Hooks auto-inject pending mail as system
reminders via `gc mail check --inject`.

### Tutorial 05: Formulas
TOML workflow templates (`.formula.toml`) with steps, dependencies (`needs`),
variables (`{{name}}`), nested steps (`[[steps.children]]`), conditions, loops
(`[steps.loop] count = N`), and Ralph retry logic (`[steps.ralph] max_attempts = N`
with exec-based verification). Instantiate as wisps (ephemeral, via `gc sling --formula`)
or molecules (durable, via `gc formula cook`).

### Tutorial 06: Beads
The universal work primitive. Every bead has ID, title, status
(open/in_progress/blocked/deferred/closed), and type (task/message/session/molecule/
wisp/convoy). Supports labels (`bd label add`), metadata (`bd update --set-metadata`),
dependencies (blocks/tracks/related/parent-child/discovered-from), and convoys
(`gc convoy create`). Work discovery is pull-based: agent hooks query `bd ready` with
routing metadata.

### Tutorial 07: Orders
Gate-conditioned actions checked every controller tick (30s). Five gate types:
**cooldown** (interval since last run), **cron** (5-field schedule), **condition**
(shell exit code), **event** (system event with cursor), **manual** (explicit only).
Two action types: **formula** (dispatched to agent pool) and **exec** (shell script).
Override settings per-order in `city.toml` via `[[orders.overrides]]`. Order history
tracked as beads.

---

## Known Issues & Gotchas

### Critical (P1)

| Issue | Description | Status / Workaround |
|-------|------------|------------|
| #278 | Default `permission_mode` breaks autonomous sessions | Set explicit `permission_mode` |
| #140 | Wisp chain fragility — single crash permanently breaks patrol loop | Manual restart |
| #137 | Order dispatcher uses city-scoped store, ignoring rig scope | — |

**Recently fixed (v0.14.0):**
- ~~#286~~ Pool workers never spawn for `gc sling` routed work — fixed in PR #319
- ~~#135~~ Closed named session beads block session name reuse — fixed (cold-boot recovery bypass)
- ~~#139~~ No recovery for on-demand named sessions after quota exhaustion — fixed in PR #311
- ~~#119~~ Config-drift drains active sessions — fixed in PR #295 (`GC_DRAIN_ACK` env var + idle recovery)

### Setup Gotchas (Most Common New-User Issues)

| Issue | Description | Fix |
|-------|------------|-----|
| **#245** | **Dolt port env var mismatch** — `GC_DOLT_PORT` vs `BEADS_DOLT_PORT` | `export BEADS_DOLT_PORT=$GC_DOLT_PORT` |
| #304 | OpenCode provider sessions start but never process beads | Use claude or codex instead |
| #157 | `gc rig add` prompts for GitHub credentials on macOS | — |
| #200 | `gc sling inline` creates beads with city prefix instead of rig prefix | Use `bd create` + `gc sling` separately |
| #156 | Rig names must have distinct first two letters | Use distinct prefixes |

**Recently fixed (v0.14.0):**
- ~~#301~~ `gc init` generates incomplete `.gitignore` — now writes `.gc/`, `.beads/`, `hooks/`, `.runtime/` entries idempotently
- ~~#145~~ `ensure_metadata` overwrites `dolt_database` on every startup — now uses `jq //=` to only set when missing

### General Tips
- **Use `GC_BEADS=file` for initial setup** — avoids all Dolt/bd complexity
- **Run `gc doctor --fix`** after any config changes
- **The `.gc/` directory should never be committed** — add to .gitignore
- **Nudge before mail** — nudges are free; mail creates permanent Dolt commits
- **Start with the tutorial template** before jumping to gastown
- **Use `gc trace tail`** to debug reconciler behavior in real time
- **Use `gc skill <topic>`** for curated quick-reference guides

### Notable Changes in v0.14.0

- **Session model phase 2**: Major refactoring of session handling — named session
  materialization, session_live drift repair, wake state transitions, idle timeout
  reload all stabilized
- **Agent imports and qualified naming**: V2 qualified names through pool, API, and mail
- **Semantic session submit intents**: New `gc session submit` for session submission
- **Default sling formula**: `default_sling_formula` field on agents and `[agent_defaults]`
  for city-wide defaults
- **Probe concurrency**: `probe_concurrency` in `[daemon]` bounds concurrent bd probes
  (default 8), fixing contention on shared Dolt SQL servers
- **Config-drift recovery**: Drain uses `GC_DRAIN_ACK` env var instead of Ctrl-C;
  idle sessions recover automatically (PR #295)
- **Pool spawn fix**: Pool workers now correctly spawn for `gc sling`-routed work (#286)
- **Mayor dispatch**: Mayor prompts now use `gc sling` instead of raw `bd` commands
- **Deacon diagnostics**: Diagnostic signals centralized on the Deacon agent
- **Work query improvements**: Three-tier default query (in_progress assigned, ready
  assigned, routed_to unassigned); scale check includes formula-dispatched molecule beads

---

## Gas Town → Gas City Migration

### Concept Mapping

| Gas Town | Gas City | Key Change |
|----------|----------|-----------|
| Town config + role homes | `city.toml` + packs | Centralized declarative config |
| Named role types | Configured agents | No hardcoded roles in SDK |
| Plugin | Order (exec or formula) | Shell → exec orders; agent work → formula orders |
| Convoy | Convoy bead + sling/formulas | Still bead-backed, no special runtime layer |
| Dog | Exec order or pool agent | Prefer orders for shell tasks |
| Deacon watchdog | Controller + supervisor | Infrastructure as controller concerns |
| Path-based identity | Explicit config + metadata | No cwd-derived assumptions |
| `~/gt/` directory structure | `city.toml` + `.gc/` runtime | Directories are implementation details |

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
| nudge | session nudge / nudge | session nudge for live; gc nudge for deferred |
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
2. Study `city.toml` configuration system
3. Learn Orders (map plugins → orders)
4. Read Formulas & Molecules
5. Study `examples/gastown/city.toml` then `packs/gastown/pack.toml`

---

## Example Cities

Six example configurations ship in `examples/`:

| Example | Description |
|---------|-------------|
| **bd** | Beads integration setup |
| **dolt** | Dolt database management |
| **gastown** | Full multi-agent orchestration (the primary example) |
| **hyperscale** | Large-scale agent pool configuration |
| **lifecycle** | Agent lifecycle management patterns |
| **swarm** | Distributed multi-agent orchestration |

---

## Pack/City v2 Roadmap

Gas City is undergoing a major structural change for 1.0: **Pack/City v2**. The core
idea is that a city IS a pack — convention-based directory layout replaces inline TOML
agent blocks, prompts move to `agents/<name>/prompt.template.md`, and the city root
gets its own `pack.toml` (schema 2) alongside `city.toml`.

**See [gas-city-pack-v2.md](gas-city-pack-v2.md) for full details** including:
- V2 city layout and how it differs from the current model
- All open design decisions (template processing, packs.lock, naming, rig binding)
- 0.13.6 release blockers (18 issues) and post-0.13.6 cleanup (10 issues)
- Implications for pack authoring in this toolkit
- Timeline: 1.0 milestone due 2026-04-21

---

## Organization Repos (gastownhall)

| Repo | Purpose |
|------|---------|
| `gascity` | Main SDK/CLI |
| `beads` | Work-tracking data layer (bd CLI) |
| `homebrew-gascity` | Homebrew tap |
| `homebrew-beads` | Homebrew tap for beads |
| `gastown` | Original Gas Town (predecessor) |
| `gascity-packs` | Reusable configuration packs |
| `gascity-otel` | OpenTelemetry integration |
| `tmux-adapter` | Tmux runtime adapter |
| `community` | Community discussions |
| `website` / `docs` | Documentation |
| `overwatch` / `tim` / `wasteland` / `marketplace` | Supporting infrastructure |
