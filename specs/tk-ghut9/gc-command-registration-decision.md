# Decision: Should the bead-universe surface become a registered `gc` command / plugin?

- **Bead:** tk-ghut9 — "Decide: should the bead-universe surface become a registered gc command/plugin?"
- **Kind:** DECISION research / writeup. **No behavior change, no command implemented.**
- **Author:** gc-toolkit/gc-toolkit.slit (polecat)
- **Date:** 2026-06-10
- **Status:** Recommendation for operator decision

---

## Provenance

| Doc / artifact | Producer | Source location + SHA | Surveyed at |
|---|---|---|---|
| `gc` command-registration code | gascity (the `gc` binary) | `github.com/zookanalytics/gascity` @ `67a7cc74c` — `cmd/gc/cmd_commands.go`, `cmd/gc/main.go`, `cmd/gc/cmd_bd.go`, `internal/config/pack.go`, `internal/config/config.go`, `internal/config/command_discovery.go` | 2026-06-10 |
| Pack spec (authoritative) | gascity docs | `github.com/zookanalytics/gascity` @ `67a7cc74c` — `docs/specs/pack-spec.md` (esp. §1.2.11 Command Directory; the surfaces table; the `[[commands]]` legacy note) | 2026-06-10 |
| PackV2 command design notes | gascity engdocs | `github.com/zookanalytics/gascity` @ `67a7cc74c` — `engdocs/design/packv2/doc-commands.md` | 2026-06-10 |
| Live pack-command precedent | gascity `dolt` pack | `/home/zook/loomington/.gc/system/packs/dolt/commands/*/{command.toml,run.sh}` (materialized from the embedded `dolt` pack; pack.toml declares **no** `[[commands]]`) | 2026-06-10 |
| The 5 bead-universe scripts | gc-toolkit bead-universe v1 (#102) | `github.com/zookanalytics/gc-toolkit` @ `de92709` (`integration/bead-universe-v1`) — `assets/scripts/gc-attention.sh`, `assets/scripts/tmux-pick-attention.sh`, `tools/gc-bd-universe.sh`, `tools/gc-bead-host.sh`, `tools/gc-proactive.sh` | 2026-06-10 |
| Bead-universe design (Interface + Future directions) | bead-universe design run | `github.com/zookanalytics/gc-toolkit` @ `de92709` — `specs/bead-universe/design-doc.md` (§Interface L160–172; §Future directions L344–360) | 2026-06-10 |
| City import wiring | loomington city | `/home/zook/loomington/city.toml` (`[rigs.imports.gc-toolkit]`, `[rigs.imports.gascity-keeper]`); `rigs/gc-toolkit/pack.toml` | 2026-06-10 |

---

## TL;DR — Recommendation

**Phase it. Stay on path-invoke (a) for now; adopt pack subcommands (b) as the cheap, reversible intermediate the moment discoverability/ergonomics start to bite; reserve top-level `gc` commands (c) for after v1 is proven and judged worth upstreaming.**

Two findings drive this:

1. **The design already decided the spirit of this question.** `design-doc.md` §Future directions (operator notes, 2026-06-06) records: *"`gc-attention.sh` stays a shell script for v1 to prove points fast; once proven, step back and re-architect (e.g. the `gc attention` Go command the api leg sketched). **Prove-fast-then-evaluate — do not pre-build the robust version.**"* Path-invoke is a **deliberate** v1 choice, not an oversight; the top-level `gc` command is the acknowledged north star *after* the model proves out. v1 has been live ~4 days; it is not yet proven.

2. **There is a cheap middle option the design's binary "shell-script-now / Go-command-later" framing skipped: option (b).** PackV2 supports **declarative, script-backed pack commands** via the `commands/<name>/run.sh` directory convention — **no gascity Go changes required**. The `dolt` pack is the live, in-production precedent (`gc dolt sql`, `gc dolt health`, … are all `commands/*/run.sh` leaves). This buys discoverability + `--help` + tab-completion at near-zero cost and full reversibility.

**Smallest viable first step (only if we proceed now):** wrap the single most operator-facing verb — `gc-attention.sh` — as `gc <binding> attention` via one `commands/attention/{command.toml,run.sh}` leaf in a new `packs/bead-universe/` sub-pack (the `gascity-keeper` sub-pack is the precedent), with `run.sh` simply `exec`-ing the existing script so every current path-invoke caller keeps working unchanged. Reversible, ~an hour, and it directly tests whether `gc <pack> <cmd>` ergonomics are "good enough" or whether the design's top-level `gc attention` is worth the upstream lift.

**One hard caveat up front:** option (b) can **never** produce the design's exact names (`gc attention`, `gc bead-host`, `gc bd universe`). Pack commands are *always* nested under a mandatory binding segment — you get `gc <binding> attention`, not `gc attention`. And `gc bd universe` is unreachable by *any* option short of an upstream change to the external `bd` binary (or a gc-side passthrough interception). If the design's *exact* CLI surface is a hard requirement, only (c) delivers it — and `gc bd universe` is the hardest piece of (c). Details below.

---

## 1. What the bead asks

Today, four bead-universe surfaces are **path-invoked shell scripts**, not `gc` subcommands:

| Script (on `integration/bead-universe-v1` @ `de92709`) | Role | Name the design *wants* |
|---|---|---|
| `assets/scripts/gc-attention.sh` | cross-rig attention board + pick-a-row launcher (`board`/`open`/`flag`/`clear`) | `gc attention open/flag <bead>` |
| `tools/gc-bd-universe.sh` | emit a bead's "universe slice" (fed/fetchable/out tiers) | `gc bd universe <id> --slice` |
| `tools/gc-bead-host.sh` | spawn-or-resume a bead-host + write the durable binding | `gc bead-host <id>` |
| `tools/gc-proactive.sh` | proactive-via-slung-mol engine (`sling`/`scan`) | (no design name; assembles `gc sling`/`gc bd`/`gc session`) |
| `assets/scripts/tmux-pick-attention.sh` | tmux `prefix+b` board picker → calls `gc-attention.sh` | (a picker, not a CLI verb) |

The scripts' own headers state the constraint plainly. `gc-attention.sh`:

> *"it is NOT a registered gc subcommand. Pack commands bind under the pack name (`gc <pack> <cmd>`), so there is no top-level attention command — invoke this script (or the picker), not `gc`."*

The bead asks: should these become real `gc` commands/plugins, what are the options + trade-offs, and what's the smallest first step if we proceed.

---

## 2. How `gc` registers commands (the mechanism)

All citations gascity @ `67a7cc74c`.

### 2.1 Top-level commands are hardcoded in Go
Every top-level `gc` command (`start`, `init`, `bd`, `dashboard`, …) is registered by hand on the root cobra command in `newRootCmd` — `cmd/gc/main.go:239–299` (a long `root.AddCommand(newStartCmd(...), newInitCmd(...), …)` block). **A pack cannot add a new top-level command** (e.g. `gc attention`) without editing this Go source.

### 2.2 Pack commands exist — but always under a mandatory namespace
After the hardcoded commands, `registerPackCommands(root, …)` runs (`cmd/gc/main.go:304`). It discovers per-pack commands and groups them by `BindingName` (`cmd/gc/cmd_commands.go:21–47`). Two load-bearing facts from that code:

- **Empty binding ⇒ skipped entirely.** `if entry.BindingName == "" { continue }` (`cmd_commands.go:25–27`). A command with no binding is never registered.
- **Always nested, never top-level.** Each binding gets a namespace cobra command `Use: binding, Short: "Commands from the %s import"` (`cmd_commands.go:49–57`), and the leaves hang under it. There is **no** code path that promotes a pack command to the top level. So pack commands are *always* `gc <binding> <cmd>`.
- `BindingName` is the **import key**, set at V2 import-expansion time, not free-form (`internal/config/field_sync_test.go:54`: *"runtime-only, set during V2 import expansion, not user-configurable"*). A binding that collides with a core command name is skipped with a warning (`cmd_commands.go:38–43`).

Execution is a plain `exec.Command(scriptPath, args...)` with stdio wired through (`cmd/gc/cmd_commands.go:149–179`). Pack commands are **script wrappers**, not Go cobra functions.

### 2.3 Two ways to declare a pack command (both script-backed, no Go changes)
- **Preferred — the `commands/` directory convention.** Each directory under `<pack>/commands/` containing a `run.sh` is one command leaf; nested dirs imply nested command words (`internal/config/command_discovery.go:59–70`; `docs/specs/pack-spec.md` §1.2.11). An optional `command.toml` carries `description`, `command` (words; defaults to the dir path), and `run` (defaults to `run.sh`). `pack-spec.md` marks this **"preferred"** and says *"New packs should use … `commands/`."*
- **Legacy — `[[commands]]` in `pack.toml`.** `PackConfig.Commands []PackCommandEntry` (`internal/config/pack.go:56`); `PackCommandEntry{Name, Description, LongDescription, Script}` (`internal/config/config.go:1014–1025`); converted to the same internal `DiscoveredCommand` by `legacyPackCommands` (`internal/config/pack.go:2176–2204`). `pack-spec.md:188–189` flags `[[commands]]` as for *existing* packs only.

**The `dolt` pack proves this is real and in production.** Its `pack.toml` declares no `[[commands]]`, yet `gc dolt sql`, `gc dolt health`, `gc dolt cleanup`, … all work — each is a `commands/<verb>/{command.toml,run.sh}` leaf (e.g. `/home/zook/loomington/.gc/system/packs/dolt/commands/sql/run.sh`, which receives `GC_PACK_DIR`, sources the pack's `assets/`, and `exec`s `dolt … sql "$@"`). This is the exact shape option (b) would take.

### 2.4 `gc bd` is a pure passthrough — `gc bd universe` is special
`gc bd` is `DisableFlagParsing: true` and forwards **all** args verbatim to the external `bd` binary via `exec.Command(bdPath, bdArgs...)` (`cmd/gc/cmd_bd.go:70–109`, `188–300`). So `gc bd universe …` would forward to `bd universe …` — which only works if the **upstream `bd` binary** implements a `universe` subcommand (it does not today; `gc-bd-universe.sh`'s own header says so). The only gc-side alternative is to special-case `bd universe` before passthrough — the wrapper already does this for exactly two verbs, `heartbeat` (`cmd_bd.go:172`, `rewriteBdHeartbeatArgs`) and `release-if-current` (`cmd_bd.go:303`) — but that is itself a gascity Go change. **`gc bd universe` cannot be delivered by pack config; it needs an upstream `bd` change or a gascity passthrough-interception.**

### 2.5 What namespace would *these* commands land under?
The gc-toolkit pack is imported into every rig under the binding key `gc-toolkit` (`city.toml`: `[rigs.imports.gc-toolkit] source = "rigs/gc-toolkit"`). So commands placed in the gc-toolkit pack's own `commands/` dir would surface as **`gc gc-toolkit <cmd>`** (verbose). The cleaner alternative is a **dedicated sub-pack** imported under a short binding — exactly how `gascity-keeper` is wired (`city.toml`: `[rigs.imports.gascity-keeper] source = "rigs/gc-toolkit/packs/gascity-keeper"`). A new `packs/bead-universe/` imported as, e.g., `[rigs.imports.universe]` yields **`gc universe attention`**, `gc universe slice`, `gc universe host`, `gc universe proactive`.

---

## 3. The three options

### Trade-off matrix

| Dimension | (a) Keep path-invoke | (b) Pack subcommands `gc <binding> <cmd>` | (c) Top-level `gc` commands / plugin |
|---|---|---|---|
| **Upstream Go change?** | None | **None** (pack config only) | **Yes** — gascity `main.go`; `gc bd universe` also needs upstream `bd` |
| **Effort** | Zero | Low (per-verb `commands/<v>/{command.toml,run.sh}` + import wiring) | High (Go cmds + fork-carry/upstream + release coord) |
| **Discoverability / tab-completion** | None (not in `gc help`; no completion) | Good — namespace shows in `gc help`; cobra completion under `gc <binding> <TAB>` | Best — verbs at top level in `gc help` + completion |
| **`--help` integration** | Only the script's own `usage()`/`-h` | `gc <binding> <cmd> --help` from `command.toml`/`help.md` | Full native cobra `--help` |
| **Invocation ergonomics** | Long path: `{{.ConfigDir}}/assets/scripts/gc-attention.sh` | `gc universe attention …` (clean, but binding segment is mandatory) | `gc attention …` (the design's exact target) |
| **Exact design names?** | No | **No** — forced `gc <binding> attention`, never `gc attention`; `gc bd universe` impossible | Yes (incl. `gc bd universe`, the hardest piece) |
| **tmux picker call** | `…/gc-attention.sh open <bead>` | `gc universe attention open <bead>` | `gc attention open <bead>` |
| **Back-compat for path callers** | N/A (is the baseline) | Trivial — `run.sh` `exec`s the existing script; old paths stay as shims → zero caller churn | Same — Go cmd can shell out to the script during transition |
| **Reversibility** | — | High (delete the pack/leaves) | Low (Go + release in flight) |
| **Fits design's "prove-fast, don't pre-build"** | Yes (the v1 intent) | Mostly — light, reversible, not "the robust version" | No — premature until v1 is proven |

### (a) Keep path-invoke — status quo
- **Effort:** zero. This is exactly what v1 ships and what the design intended for the prove-fast phase.
- **Cost:** no discoverability (nothing in `gc help`), no shell completion, `--help` only if the script implements it (`gc-attention.sh` does have a usage header; the `tools/*` scripts are more internal). Operators/agents must know the path.
- **Who calls them today (the surface a migration must preserve):** `gc-attention.sh` ← `agents/bead-host`, `agents/proactive`, `tmux-pick-attention.sh`, `formulas/mol-first-reaction.toml`, fixtures, + operator/`prefix+b`. `gc-bd-universe.sh` ← `agents/proactive`, `mol-first-reaction.toml`, fixtures. `gc-bead-host.sh` ← `agents/bead-host/agent.toml`, `gc-attention.sh`, `gc-bd-universe.sh`, fixtures. `gc-proactive.sh` ← `agents/proactive/agent.toml`, `mol-first-reaction.toml`, fixture. All reference scripts **by path** — so any migration either keeps the paths as shims or updates these ~handful of call sites.

### (b) Register as pack subcommands — `gc <binding> <cmd>`
- **Effort:** low, no Go changes. For each verb, add `commands/<verb>/{command.toml,run.sh}` to a pack; wire the pack's import binding. `dolt` is the working template.
- **Namespace choice:** new `packs/bead-universe/` sub-pack under a short binding (`gc universe attention|slice|host|proactive`) — clean, isolated, `gascity-keeper`-style — or reuse the existing gc-toolkit binding (`gc gc-toolkit attention`, verbose). Recommend the sub-pack.
- **Gains:** discoverability in `gc help`, `gc <binding> <TAB>` completion, `gc <binding> <cmd> --help`. The board/open/flag/clear verbs of `gc-attention.sh` map naturally to `gc universe attention [open|flag|clear|board]` (or sub-leaves).
- **Limits:** the binding segment is **mandatory** — you cannot get `gc attention`/`gc bead-host`; `gc bd universe` is out of reach (see §2.4). It is *near* the design's intent, not *at* it.
- **Migration cost:** low. Make each `run.sh` `exec` the existing script (keep scripts where they are) → all current path-invoke callers keep working untouched; migrate call sites to the `gc <binding> <cmd>` form opportunistically. Fixtures (`tools/attention-surface-fixture.sh`, etc.) can gain a thin assertion that the command form resolves.
- **Reversibility:** high — remove the import + the `commands/` leaves and you're back to (a).

### (c) Full plugin / top-level commands — `gc attention`, `gc bead-host`, `gc bd universe`
- **Effort:** high. `gc attention` and `gc bead-host` need new `newAttentionCmd`/`newBeadHostCmd` registered in gascity `cmd/gc/main.go:239–299`. `gc bd universe` needs either an upstream `bd` `universe` subcommand or a gascity passthrough-interception in `doBd` (`cmd_bd.go:172–186`-style). Either way these are **upstream gascity (and possibly `bd`) changes**, carried as fork patches or upstreamed — and the gc-toolkit fork already runs rebase machinery against gascity (see `pack.toml` header + `packs/gascity-keeper/`), so each carried patch is ongoing rebase surface.
- **Gains:** the design's exact ergonomics — top-level verbs, native `--help`, completion, `gc bd universe` reachable.
- **Cost/risk:** highest effort, release coordination, lowest reversibility, and it contradicts the design's explicit "do not pre-build the robust version" until v1 is proven. The Go commands can still shell out to the existing scripts during transition, so back-compat itself is not the obstacle — the obstacle is committing upstream effort before the model has earned it.

---

## 4. Recommendation + smallest viable first step

**Recommendation: phased, demand-driven.**

- **Now → (a).** Keep path-invoke. It is the design's intended v1 posture and v1 is not yet proven (~4 days live). Don't spend on CLI ergonomics the running system hasn't yet asked for.
- **When ergonomics bite → (b).** The first time the operator (or an agent prompt) is annoyed at typing/discovering a path, do the cheap pack-subcommand wrap. It's reversible and needs no upstream work. This is the option the design's binary framing skipped and is the right "middle gear."
- **Only once v1 is proven and the exact surface is wanted → (c).** Promote to top-level Go commands (and tackle `gc bd universe`) when the model has earned the upstream investment — matching the design's own stated end-state (`gc attention` Go command).

**Smallest viable first step (if we choose to move at all):** a **one-command (b) pilot**:

1. Create `packs/bead-universe/pack.toml` (`schema = 2`, `name = "bead-universe"`).
2. Add `packs/bead-universe/commands/attention/run.sh` that `exec`s the existing `assets/scripts/gc-attention.sh "$@"` (resolve via `GC_PACK_DIR`/`{{.ConfigDir}}`), plus a one-line `command.toml` (`description = "Cross-rig attention board + pick-a-row launcher"`) and a `help.md`.
3. Wire the import in `city.toml` under a short binding (e.g. `[rigs.imports.universe] source = "rigs/gc-toolkit/packs/bead-universe"`), giving **`gc universe attention …`**.
4. Leave `gc-attention.sh` and all its callers (incl. `tmux-pick-attention.sh`, `prefix+b`) exactly as they are — the script is still the implementation; the new command is sugar over it.

Pick `attention` first because it is the **operator-facing, human-typed** verb (the board); the `tools/*` scripts are agent/formula-internal and benefit far less from a CLI face. The pilot is ~an hour, fully reversible, touches no behavior, and yields a concrete read on whether `gc <pack> <cmd>` ergonomics satisfy the operator — the exact signal needed to decide if (c)'s upstream cost is justified.

**Do not, in the first step:** reach for (c), or migrate the agent/formula call sites, or touch `gc bd universe`. Those are downstream of the "is the pack-subcommand form good enough?" answer the pilot exists to produce.

---

## 5. Answers to the bead's explicit sub-questions

1. **How `gc` registers plugin/pack commands; can top-level be added; is `gc bd universe` feasible?** Pack commands are script-backed and discovered from `commands/<v>/run.sh` (preferred) or `[[commands]]` (legacy) — **no Go change** — but are **always** nested as `gc <binding> <cmd>` (empty binding ⇒ skipped; `cmd_commands.go:25–57`). **Top-level commands cannot be added by a pack** (hardcoded in `main.go:239–299`). **`gc bd universe` is not feasible via pack config** — `gc bd` passes through to the external `bd` binary (`cmd_bd.go`), so it needs an upstream `bd` subcommand or a gascity passthrough-interception.
2. **The three options + trade-offs (discoverability, `--help`, ergonomics, migration, tmux picker, back-compat):** see §3 matrix + prose. Headline: (a) zero-cost/zero-affordance; (b) low-cost, real discoverability/`--help`/completion, but a mandatory binding segment and no `gc bd universe`; (c) exact design surface but upstream Go (+`bd`) cost and lowest reversibility.
3. **Recommendation + smallest first step:** phase (a)→(b)→(c); if moving now, pilot **`gc <binding> attention`** as a single `commands/` leaf that `exec`s the existing script, in a new `packs/bead-universe/` sub-pack, with zero caller churn. See §4.

---

*No code or behavior was changed by this bead. This document is analysis only.*
