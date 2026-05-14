# Gas City Pack/City v2 — What Shipped in 1.0

> Structural reference for Pack/City v2, the shape that landed with the
> 1.0 release (2026-04-21) and is current as of **1.0.1 (2026-04-22)**.
> The pre-release version of this doc tracked open issues; this version
> records what was resolved, what the final decisions were, and which
> quirks a mechanik should know when touching structural config.

---

## Why v2 existed

Gas Town → Gas City converted a directory-structured orchestrator into a
TOML-declared one, but kept a seam: **packs** were reusable pack directories
while a **city** was a top-level TOML file with inline `[[agent]]` blocks.
Composing a city from packs meant reconciling two different shapes.

V2 closes the seam: **a city IS a pack**. The city root has its own
`pack.toml` (schema 2). Pack content is discovered by convention, not by
listing. The result is that workspace imports, rig imports, and your own
city root all follow the same rules.

---

## What v2 actually changed

### `pack.toml` (schema 2) at the city root

Every v2 city root now has a `pack.toml`:

```toml
[pack]
name = "my-city"
schema = 2

[imports.gastown]
source = ".gc/system/packs/gastown"

[defaults.rig]
[defaults.rig.imports.gastown]
source = ".gc/system/packs/gastown"
```

`[imports.<name>]` replaces the old `city.toml` `[packs.<name>]`. A
binding name (the table key) is how other config references the import.
Sources can be local paths or `github.com/org/repo` with `version` +
optional `path`.

`[defaults.rig.imports.<name>]` is the v2 replacement for
`default_rig_includes` — applied to every rig that doesn't override it.

### Convention-based agent discovery

An agent is now a **directory** under `agents/<name>/`. The directory
name is the agent name; `agent.toml` has no `name` field. Prompts live
next to the config as `prompt.template.md`.

```
agents/
└── mayor/
    ├── agent.toml
    └── prompt.template.md
```

This applies to every pack: the city root, imported packs, and rig-local
packs. `[[agent]]` blocks in `city.toml` still load for crew, patches,
and one-offs, but the idiomatic shape is convention directories.

### `.gc/site.toml` — machine-local identity

v1 stored the workspace name and rig filesystem paths inside committed
`city.toml`. v2 splits them out:

```toml
# .gc/site.toml (machine-local, not committed)
workspace_name = "loomington"
workspace_prefix = "lx"

[[rig]]
name = "gc-toolkit"
path = "/home/zook/loomington/rigs/gc-toolkit"
```

```toml
# city.toml (committed, portable)
[[rigs]]
name = "gc-toolkit"
prefix = "tk"
```

`city.toml` now declares **logical** rigs (name + optional prefix +
options); `.gc/site.toml` maps those names to **physical** filesystem
paths. A committed `city.toml` works across machines without leaking
absolute paths or requiring per-host edits.

`gc register --name ALIAS` writes the machine-local alias here. It never
modifies `city.toml`.

### File naming

| V1 | V2 |
|----|----|
| `prompts/<name>.md.tmpl` | `agents/<name>/prompt.template.md` |
| `formulas/<name>.formula.toml` | `formulas/<name>.toml` |
| `orders/<name>/order.toml` | `orders/<name>.toml` |

The `.formula.` and `.order.` infixes were removed. The `.template.md`
suffix is the new template marker (a design decision on #582 — plain
`.md` is now allowed for literal content, and templates are explicit).

### Root city-pack commands and skills

A pack can now expose:

- **Commands**: `commands/<name>/run.sh` → runs as `gc <name>`
- **Skills**: `skills/<name>/SKILL.md` → surfaced via `gc skill list`
- **Template fragments**: `template-fragments/<name>.md` → usable as
  `{{ template "<name>" . }}` from prompts
- **Overlays**: `overlays/<name>/` → provider settings injection

These surfaces work from the city root itself (since it's a pack), from
imported packs, and from rig-local packs. A previous v1 quirk
(commands at the root were invisible) is fixed.

### `[global]` in `pack.toml`

```toml
[global]
session_live = [
    "{{.ConfigDir}}/assets/scripts/tmux-bindings.sh {{.ConfigDir}}",
]
```

`[global]` applies session-wide hooks to every agent defined by the pack.
Gastown uses this to install tmux themes and keybindings on every session
without repeating the config per-agent.

### `[[patches.agent]]` / `[[patches.rig]]` / `[[patches.provider]]`

Post-composition overrides. Useful when importing a pack and tweaking
one field without forking the whole thing:

```toml
[[patches.agent]]
name = "dog"
wake_mode = "fresh"
work_dir = ".gc/agents/dogs/{{.AgentBase}}"
```

Patches run after imports are composed, so they override both
convention-discovered agents and inline `[[agent]]` blocks.

---

## Design decisions that landed

The 1.0 release resolved the major design questions. The final positions:

| Question | Decision | Rationale |
|----------|----------|-----------|
| Template processing opt-in? | Yes — `.template.md` suffix required | Plain `.md` is literal content. Templates are explicit. |
| `packs.lock` loader contract | Lock file written on `gc import install/upgrade`; checked by `gc import check` | Reproducible pack fetches, still fuzzy on tags |
| `[agent_defaults]` canonical name | Kept `[agent_defaults]`; `[agents]` alias dropped | Less ambiguity with `[[agent]]` |
| `.formula.` / `.order.` infix | Removed post-0.13.6 | Simpler naming |
| Rig path location | `.gc/site.toml` (not `city.toml`) | Separates machine-local from committed config |
| `workspace.name` | Retired as checked-in identity; lives in `.gc/site.toml` as `workspace_name` | Same reason — portability |
| `gc register --name` | Shipped; stored in site-bound registry | Local naming without editing committed config |
| `gc init` default shape | V2 (schema 2, convention directories, `.gc/site.toml`) | V1 still loads but new cities start v2 |
| `gc agent add` | Writes convention-based `agents/<name>/` | Aligns with v2 default |

---

## Migration path for v1 cities

```bash
gc import migrate --dry-run    # preview
gc import migrate              # rewrite in place
```

`gc import migrate` handles:
- Moving `workspace.includes` → `[imports]` in `pack.toml`
- Converting `[[agent]]` tables → `agents/<name>/` directories
- Relocating prompts, overlays, namepools into v2 shape
- Adding a `pack.toml` if the city didn't have one
- Moving `workspace.name` → `.gc/site.toml` `workspace_name`
- Moving `[[rigs]] path = "..."` → `.gc/site.toml` `[[rig]] path = "..."`

The migrator is idempotent and does not touch legacy-but-still-loadable
shapes that work fine (e.g. `[packs.<name>]` in `city.toml` — left alone
unless you ask for a rewrite).

Manual fallback checklist: see `gas-city-reference.md` → "V1 → V2 Migration".

---

## Backward compatibility (what still loads)

- **Inline `[[agent]]`** blocks in `city.toml` — preserved for crew
  members, one-off patches, or legacy cities
- **`[packs.<name>]`** in `city.toml` — still resolves to an import
- **Schema 1** packs — loaded in compatibility mode
- **`prompts/<name>.md.tmpl`** — still recognized, not required to rename
- **`formulas/<name>.formula.toml`** and `orders/<name>/order.toml` —
  still scanned; the new naming takes precedence when both exist
- **`[workspace] name`** in `city.toml` — if present, used; `.gc/site.toml`
  `workspace_name` takes precedence when both are set

The loader prefers v2 locations when there's a conflict, but will not
silently drop v1 content.

---

## Implications for gc-toolkit

### What we do in this pack now

- **`pack.toml` at toolkit root uses `schema = 2`** — this is the only
  supported schema for new content
- **Agent definitions live under `agents/<name>/`** with `agent.toml`
  and `prompt.template.md` — see `rigs/gc-toolkit/agents/mechanik/`
- **Formulas are `<name>.toml`** (no `.formula.` infix) under
  `formulas/` if we ship any
- **Orders are flat `<name>.toml`** under `orders/`
- **Template fragments go under `template-fragments/`** and are
  referenced as `{{ template "name" . }}`
- **Overrides for imported-pack agents** go in `[[patches.agent]]`,
  not pack forks

### Principles that still hold (pre-existing guardrails)

1. **Minimize gastown code changes** — divergence goes in gc-toolkit
2. **Design for per-rig variation** — use `[[rigs.overrides]]` or
   rig-local pack imports, not hardcoded forks
3. **Convention over configuration** — prefer rig-local `pack.toml`
   imports over inline `[[agent]]` blocks in `city.toml`

### New extension points

- **Commands**: drop scripts under `commands/<name>/run.sh` to add
  `gc <name>` subcommands for this toolkit's workflows
- **Skills**: write `skills/<name>/SKILL.md` to surface toolkit-specific
  reference docs to agents (shows up in `gc skill list`)
- **Packs**: the toolkit itself is an import (`[imports.gc-toolkit]`
  in the city's `pack.toml`). Nothing special — it's the same
  convention as any other pack.

---

## Quirks and edge cases a mechanik should know

- **Agent identity resolution**: when an agent is defined in multiple
  imported packs, the last import wins, then `[[patches.agent]]` on top.
  Use `gc config explain` to see which source supplied each field.
- **Prompt fragment collisions**: `template-fragments/foo.md` in two
  different imported packs both register as `{{ template "foo" . }}`.
  Last-import-wins. Qualify fragment names with the pack binding to
  avoid collisions (e.g. `{{ template "gastown.propulsion-mayor" . }}`).
- **Skill collisions**: `skills/<name>/SKILL.md` shares a namespace
  after being pulled to the agent's vendor sink (e.g. `.claude/skills/`).
  `gc doctor` surfaces collisions. Agent-scoped
  (`agents/<name>/skills/`) always wins over pack-level when present.
- **Named sessions are per-pack**: `[[named_session]]` in one pack does
  not implicitly extend another pack's named sessions. A city pack's
  `[[named_session]]` is the top-level roster.
- **`city_agents` is the partition key**: if you write a dual-scope
  pack, the `city_agents = ["mayor", ...]` field in its `pack.toml`
  controls which agents come through as city-scoped vs rig-scoped. Get
  this wrong and you'll spawn a city-scope agent inside each rig (or
  vice versa).
- **`.gc/site.toml` is authoritative for rig paths**: `gc rig add`
  writes both `city.toml` (logical rig) and `.gc/site.toml` (physical
  path). If you hand-edit, edit both.
- **The root city-pack can be nearly empty**: you don't have to define
  any agents at the city root — the imports carry the agents. `pack.toml`
  + `city.toml` with rigs and imports is enough.
- **`commands/` at the city root**: these become `gc <name>` globally
  for anyone inside the city. Don't shadow built-in `gc` subcommands.

---

## References

- `gas-city-reference.md` — complete Gas City surface (CLI, config, agent
  roles, runtime providers, migration, tutorials)
- `gc import --help` — current import command surface
- `gc config explain` — provenance annotations for every resolved field
- `gc doctor --verbose` — warnings for v1 artifacts that should migrate
- `.gc/system/packs/gastown/pack.toml` — reference v2 pack (imports,
  `[global]`, `[[patches.agent]]`, `[[named_session]]`)
- `.gc/system/packs/core/pack.toml` — minimal v2 pack (skills, shared
  prompt assets)
