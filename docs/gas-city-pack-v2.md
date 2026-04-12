# Gas City Pack/City v2 — Direction and Open Issues

> Working reference compiled from open `city-pack-v2` issues on
> gastownhall/gascity. Current as of 2026-04-12.
> Milestone: **1.0 (due 2026-04-21)**.

---

## Context

Gas City is undergoing its most significant structural change since the Gas Town
migration: **Pack/City v2**. The core idea is that a city IS a pack. Convention-based
directory layout replaces inline TOML agent blocks, prompts move to
`agents/<name>/prompt.template.md`, and the root of a city gets its own `pack.toml`
alongside `city.toml`. This unifies how packs and cities are authored, composed, and
distributed.

All 28 open `city-pack-v2` issues target the 1.0 milestone. They break into two
phases: **0.13.6** (the release that lands the merge wave) and **post-0.13.6**
(cleanup and polish before 1.0 GA).

---

## What's Changing (Pack/City v2 Model)

### The City-as-Pack Model

Today, a city has `city.toml` with `[[agent]]` blocks and a separate `packs/`
directory for reusable pack content. In v2:

- The **city root itself is a pack** with its own `pack.toml` (schema 2)
- Agents are discovered by **convention**: `agents/<name>/` directories
- Prompts use **file-based discovery**: `agents/<name>/prompt.template.md`
- Commands are discovered from `commands/<name>/run.sh` — including from the root city-pack
- `city.toml` shrinks to city-specific concerns (rigs, daemon, beads, providers)
- Pack content (agents, prompts, commands, formulas) lives in convention directories

### V2 City Layout (Target)

```
my-city/
├── pack.toml              # Root city-pack metadata (schema = 2)
├── city.toml              # City-specific config (rigs, daemon, providers)
├── agents/
│   ├── mayor/
│   │   └── prompt.template.md
│   └── worker/
│       └── prompt.template.md
├── commands/
│   └── hello/
│       └── run.sh
├── formulas/
│   └── orders/
├── .gc/                   # Runtime root (unchanged)
└── ...
```

Compare with the current (v1/legacy) layout where agents are defined inline in
`city.toml` as `[[agent]]` blocks and prompts live in a flat `prompts/` directory.

### Key Design Decisions (In Progress)

These are active design threads that shape how v2 will work:

| Decision | Issue | Status |
|----------|-------|--------|
| Template processing opt-in via `.tmpl` suffix | #582 | Under discussion for 0.13.6 |
| `packs.lock` loader contract for remote imports | #583 | Leaning toward ship-as-is, fuller pass later |
| `[agent_defaults]` as canonical name (drop `[agents]` alias) | #585 | Decided: stop documenting alias, remove later |
| `.formula.toml` / `.order.toml` infix removal | #586 | Decided: keep for merge wave, remove after |
| Rig path moves out of `city.toml` into `.gc/` | #588 | Design accepted for 0.13.6 |
| `workspace.name` retirement as checked-in identity | #600 | Post-0.13.6 design |
| `gc register --name` flag for local city alias | #602 | Accepted for 0.13.6 |

---

## Phase: 0.13.6 (Release Branch)

The 0.13.6 release lands the Pack/City v2 merge wave. These are the issues that
must be resolved before it ships.

### Critical Bugs (P1) — Must Fix

| Issue | Summary | Impact |
|-------|---------|--------|
| #601 | `gc register` rejects pack schema 2 cities | Blocks all v2 dogfooding |
| #602 | `gc register` needs `--name` flag for local city alias | Local naming pushed into checked-in config |
| #603 | `gc init` still emits the legacy scaffold | New cities learn the wrong shape |
| #604 | Root city-pack commands not exposed as CLI commands | `commands/` from root pack don't work |
| #605 | Runtime/register materializes legacy root `prompts/` in v2 cities | V2 cities grow unwanted legacy dirs |
| #608 | `gc agent add` writes legacy `[[agent]]` config | Conflicts with v2 direction |
| #609 | Root city-pack agents not discovered for prime/config | Convention agents invisible |
| #610 | `gc prime` falls back for convention-discovered agents | Discovered agents render wrong prompt |
| #613 | `gc session new` fails for managed Claude sessions in v2 cities | Session creation broken in v2 |

### Design Decisions (P1-P2) — Must Resolve

| Issue | Summary |
|-------|---------|
| #580 | Resolve `[agents]` field naming and defaultability before release |
| #582 | Decide whether `.tmpl` suffix required for template processing |
| #583 | Decide `packs.lock` loader contract for remote imports |
| #588 | Move rig path and machine-local rig binding out of `city.toml` |
| #595 | Validate `dog` and `maintenance` packaging in v2 model |

### Bug Fixes (P2) — Should Fix

| Issue | Summary |
|-------|---------|
| #606 | `bd` import binding shadow warning pollutes normal CLI use |
| #607 | `gc rig remove` emits unrelated deprecation warnings from other cities |
| #611 | Bundled packs still materialize deprecated order paths |

---

## Phase: Post-0.13.6 (Before 1.0 GA)

Cleanup, documentation, and design refinement after the merge wave lands.

### Design Work

| Issue | Summary | Priority |
|-------|---------|----------|
| #585 | Remove `[agents]` alias support entirely | P2 |
| #586 | Remove `.formula.` and `.order.` infixes from file naming | P2 |
| #587 | Restate multi-city rig and bead-state separation in v2 terms | P2 |
| #591 | Decide which packs become public starter/registry content | P2 |
| #592 | Reconcile bootstrap registry and implicit-import behavior | P2 |
| #600 | Retire `workspace.name` as checked-in city identity | P2 |

### Migration & Documentation

| Issue | Summary | Priority |
|-------|---------|----------|
| #589 | Migrate example cities and packs to v2 format | P2 |
| #590 | Publish current Pack/City v2 design doc, scrub stale refs | P2 |
| #593 | Scrub and refresh tutorials after v2 format settles | P3 |

### Technical Debt

| Issue | Summary | Priority |
|-------|---------|----------|
| #575 | Add `gc import check` for cache/materialization validation | P2 |
| #594 | Evaluate narrow follow-up for loader-side `packs.lock` reads | P3 |

---

## Implications for gc-toolkit

These changes affect how we build and configure packs in this toolkit:

### What to Track

1. **Schema version**: Our `pack.toml` currently uses `schema = 1`. When 0.13.6
   ships with schema 2 support, we'll need to evaluate migration. The migration
   doc referenced in #589 will be the operating checklist.

2. **Agent definition style**: We currently define agents with `[[agent]]` blocks
   in pack TOML. V2 moves to convention-based `agents/<name>/` directories with
   `prompt.template.md` files. The `gc agent add` command (#608) will also change.

3. **Prompt file naming**: Today prompts are `.md.tmpl` files in `prompts/`. V2
   moves them to `agents/<name>/prompt.template.md`. There's an open question
   (#582) about whether `.tmpl` suffix will be required for template processing —
   plain `.md` may become literal content only.

4. **Command discovery**: V2 exposes `commands/<name>/run.sh` from packs as CLI
   subcommands (#604). This is a new extensibility surface.

5. **Formula/order file naming**: The `.formula.toml` and `.order.toml` infixes
   will be removed post-0.13.6 (#586). Plan for simpler filenames.

6. **Rig binding**: Rig path moves out of `city.toml` into `.gc/` (#588). This
   affects how we document rig registration.

7. **Remote imports**: The `packs.lock` contract (#583) and `gc import check`
   (#575) affect how remote pack dependencies are resolved and validated.

### What's Safe Now

- The core city.toml schema (providers, beads, session, daemon, etc.) is stable
- Bead store interface and `bd` CLI are unchanged
- Formula/molecule/order runtime semantics are unchanged
- Session providers (tmux, k8s, acp, etc.) are unchanged
- The gastown agent roles (mayor, deacon, polecat, etc.) are unchanged in function
- CLI command surface is additive, not breaking (new flags, not removed commands)

---

## Timeline

| Date | Event |
|------|-------|
| 2026-04-11 | City-pack-v2 issues filed from dogfooding session |
| 2026-04-12 | Today — 18 issues in 0.13.6 phase, 10 post-0.13.6 |
| 2026-04-21 | 1.0 milestone due date |

The 1.0 release is 9 days away. The 0.13.6 release (which lands the v2 merge wave)
must ship before that, leaving time for the post-0.13.6 cleanup pass.
