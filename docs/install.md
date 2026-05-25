# Installing gc-toolkit

> Reference for wiring `gc-toolkit` into a Gas City. Assumes a working
> Gas City install (`gc version` returns a version) and a city
> created with `gc init`.

This guide covers:

1. [Importing gc-toolkit](#1-importing-gc-toolkit) into a city
2. [Opting into sub-packs](#2-opting-into-sub-packs) (general pattern)
3. [`[[rigs.patches]]` — fragment injection](#3-rigs-patches--fragment-injection)
4. [Per-rig overrides](#4-per-rig-overrides) via `[[rigs.overrides]]`
5. [Verification](#5-verification)

For Gas City and pack/city v2 background, see
[`gascity-reference.md`](gascity-reference.md).

---

## 1. Importing gc-toolkit

`gc-toolkit` is a pack. A city imports it from a filesystem path or a
git remote, scoped either to a single rig or as a default for every
rig in the city.

### Per-rig import (most common)

Drop `gc-toolkit` somewhere reachable from the city root (the
convention is `rigs/gc-toolkit/`), then add the import to your
`city.toml`:

```toml
[[rigs]]
name = "my-rig"
prefix = "mr"

[rigs.imports.gc-toolkit]
source = "rigs/gc-toolkit"
```

`source` is resolved relative to the city root. The path can be a
checkout you manage yourself or a worktree.

### Remote git import

```toml
[rigs.imports.gc-toolkit]
source = "github.com/<owner>/gc-toolkit"
version = "v0.1.0"
```

`version` is required for git-backed imports. Run `gc import install`
to materialize the pack under `.gc/cache/`.

### Default import across every rig

If every rig in the city should pick up gc-toolkit, declare the
import once in the city pack's `pack.toml`:

```toml
# pack.toml (city root)
[defaults.rig]
[defaults.rig.imports.gc-toolkit]
source = "rigs/gc-toolkit"
```

Any per-rig `[rigs.imports.gc-toolkit]` in `city.toml` overrides the
default for that rig.

### What the import brings in

Importing gc-toolkit binds the following into the rig:

- **Agents** — `mechanik` (city-scoped session template), plus prompt
  overrides on gastown's `boot`, `deacon`, `mayor`, `refinery`, and
  `witness`.
- **Polecat fragment** — `polecat-convoys` appended to the polecat
  prompt for owned-convoy awareness.
- **Skills** — surfaced via `gc skill list` (e.g.,
  `gc-toolkit.handoff`, `gc-toolkit.session-title`).
- **Template fragments** — `operational-awareness`, `propulsion`,
  `polecat-convoys`, `cycle-recycle`, and others available to
  `inject_fragments_append` / `append_fragments`.

gc-toolkit transitively imports `gastown`, so the gastown roster
(boot, deacon, mayor, polecat, refinery, witness, dog) comes in
automatically. Do not also add `[rigs.imports.gastown]` — that would
double-import gastown's agents.

---

## 2. Opting into sub-packs

`gc-toolkit` ships **opt-in sub-packs** under `packs/<name>/`. A
sub-pack is a separate pack that ships alongside `gc-toolkit` but is
imported only by rigs that need it. Today there is one sub-pack:
`gascity-keeper`, for rigs maintaining a `gascity` fork.

### General pattern

Import a sub-pack on the rig that should run it, **in addition to**
the gc-toolkit import:

```toml
[[rigs]]
name = "my-rig"
prefix = "mr"

[rigs.imports.gc-toolkit]
source = "rigs/gc-toolkit"

[rigs.imports.gascity-keeper]
source = "rigs/gc-toolkit/packs/gascity-keeper"
```

Substitute the binding key and `source` for whichever sub-pack you
are wiring; the shape is the same.

A sub-pack typically ships:

- One or more agents (`agents/<name>/`)
- Formulas (`formulas/<name>.toml`)
- Template fragments (`template-fragments/<name>.template.md`)
- A `[[named_session]]` declaration for on-demand spawn

The fragments and agents become available to the importing rig once
the import lands. Fragments still need to be **wired** into existing
agents via `[[rigs.patches]]` — see the next section.

### Concrete example: `gascity-keeper`

The keeper-specific wiring snippet lives in the sub-pack itself:
[`packs/gascity-keeper/pack.toml`](../packs/gascity-keeper/pack.toml).
Copy that block into your `city.toml` under the rig that maintains
the fork. The snippet covers:

- `[rigs.imports.gascity-keeper]` import
- `[[rigs.patches]]` fragment-injection blocks for refinery and polecat
- A note on the resolved keeper identity

The sub-pack itself ships a `[[named_session]]` with
`scope = "rig"`, so the keeper is automatically spawnable in the
importing rig — no extra `[[named_session]]` block is required in
`city.toml`. Adding one duplicates the resolved identity.

The `gascity-keeper.` prefix is the **import binding** (the table
key under `[rigs.imports.gascity-keeper]`). `keeper` is the agent's
directory name inside the sub-pack. The keeper resolves to
`<rig>/gascity-keeper.keeper` after composition — confirm with `gc
config show`.

---

## 3. `[[rigs.patches]]` — fragment injection

`[[rigs.patches]]` is a post-composition hook scoped to one rig. The
most common use is **appending template fragments to an existing
agent's prompt** without forking the agent.

```toml
[[rigs.patches]]
agent = "refinery"
inject_fragments_append = ["rebase-conventions", "refinery-rebase-handling"]
```

The block goes inside the relevant `[[rigs]]` block. TOML table
arrays scope: every `[[rigs.patches]]` after a `[[rigs]]` header
applies to that rig only.

- `agent` — bare name of an agent provided by the import chain
  (gc-toolkit → gastown).
- `inject_fragments_append` — fragments to append. The named
  fragments must exist as `template-fragments/<name>.template.md`
  in some imported pack.

Other fields available on a patch block (subset most-used):

| Field | Purpose |
|-------|---------|
| `provider` | Override LLM provider |
| `prompt_template` | Replace the prompt template wholesale |
| `max_active_sessions` | Pool size override |
| `idle_timeout` | Idle timeout override |
| `wake_mode` | `"fresh"` or `"resume"` |
| `env` | Per-rig environment variables (as a sub-table) |

The complete patch-block field list is in
[`gascity-reference.md`](gascity-reference.md#configuration-reference).

### Resolution order

Fragments compose in import order:

1. Agent's base prompt (from the deepest import, usually gastown)
2. Pack-level `[[patches.agent]]` overrides (e.g. gc-toolkit's
   `inject_fragments_append = ["polecat-convoys"]` on the polecat)
3. City-level `[[rigs.patches]]` (this section)

`gc config explain` shows the provenance of every resolved field if
you need to debug a missing fragment.

---

## 4. Per-rig overrides

Where `[[rigs.patches]]` modifies the composed prompt or replaces
fields wholesale, `[[rigs.overrides]]` adjusts runtime/lifecycle
fields on a per-rig basis:

```toml
[[rigs]]
name = "my-rig"
prefix = "mr"

[rigs.imports.gc-toolkit]
source = "rigs/gc-toolkit"

[[rigs.overrides]]
agent = "refinery"
[rigs.overrides.env]
GC_DEFAULT_MERGE_STRATEGY = "mr"
```

Common override fields:

```toml
[[rigs.overrides]]
agent = "polecat"
provider = "gemini"
max_active_sessions = 10
idle_timeout = "30m"
wake_mode = "fresh"

[rigs.overrides.env]
RIG_SPECIFIC_VAR = "value"
```

### `[[rigs.patches]]` vs `[[rigs.overrides]]`

Both are scoped to one rig in `city.toml`. The pragmatic split:

- `[[rigs.patches]]` for **prompt composition** (fragments, prompt
  template replacement, provider).
- `[[rigs.overrides]]` for **runtime knobs** (pool size, idle
  timeout, env, wake mode).

Either form can carry env / pool fields — pick by intent rather than
mechanics. `gc config explain` resolves both.

### Refinery merge defaults

The refinery's `direct` merge default matches upstream gascity
expectations for fork-keeper rigs. Downstream cities that want
PR-default refinery output should set
`default_merge_strategy = "mr"` at the city level in `city.toml`.
All rigs in the city inherit the setting unless an individual rig
overrides it. Per-bead `metadata.merge_strategy` always wins over
the city/rig default. The gascity-keeper upstream-rebase workflow
uses different formulas (`mol-upstream-gc-rebase` etc.) and is
unaffected by this setting.

---

## 5. Verification

### `gc doctor`

After editing config, run:

```bash
gc doctor
```

A healthy install passes all required checks. Common first-time
failures:

| Failure | Cause | Fix |
|---------|-------|-----|
| `config-refs` | An import `source` path doesn't exist | Verify paths under `[rigs.imports.*]` |
| `pre-start-scripts` | An imported pack's script path doesn't resolve | Confirm the pack materialized; run `gc import install` for remote imports |
| `skill-collision` | Two packs ship a skill with the same name | `gc skill list --agent <name>` to identify; agent-scoped variant wins |

Run `gc doctor --verbose` for details on any failed check; `gc doctor
--fix` applies the canonical remediation where one exists.

### `gc config show`

Confirms the resolved agent list and which prompt templates are bound:

```bash
gc config show | grep -E '^\[\[agent\]\]|^name =|^prompt_template ='
```

Look for `mechanik` (gc-toolkit's city-scoped agent) and confirm the
patched gastown agents (`boot`, `deacon`, `mayor`, `refinery`,
`witness`) point at gc-toolkit's `patches/*-prompt.template.md`
files.

### `gc skill list`

Confirms the skills gc-toolkit exposes are visible to an agent:

```bash
gc skill list --agent <rig>/gc-toolkit.polecat
```

You should see `gc-toolkit.handoff` and `gc-toolkit.session-title`
alongside the `core.*` skills.

### Smoke test

```bash
gc start
gc session new mechanik
gc session attach mechanik
```

If the `mechanik` session comes up with the gc-toolkit prompt header,
the import composed correctly. For a sub-pack like `gascity-keeper`,
address the template by its fully-qualified `<rig>/<binding>.<template>`
form from the city root (or run from the rig directory / pass
`--rig <rig>`):

```bash
gc session new <rig>/gascity-keeper.keeper
gc session attach <alias>
```

---

## Gotchas

- **Sub-pack imports are rig-scoped.** Placing a sub-pack import at
  the city level (top-level `[imports.<sub-pack>]`) loads it into
  every rig, including ones that should not pick it up. Always
  declare sub-pack imports inside a `[[rigs]]` block.
- **`source` paths are city-root-relative.** A relative
  `source = "rigs/gc-toolkit"` resolves from the city root, not the
  rig root.
- **Rig names must have distinct first two letters.** The bead-prefix
  is auto-derived from the rig name; picking `gc` and `gascity` as
  rig names would clash. Use distinct prefixes (`prefix = "gc"`,
  `prefix = "gx"`) if you need similar names.
- **`pack.toml` vs `city.toml`.** Pack-level config (workspace
  defaults, transitive imports, `[global]` hooks) goes in `pack.toml`
  at the city root. Per-rig wiring (`[[rigs]]`, `[rigs.imports.*]`,
  `[[rigs.patches]]`, `[[rigs.overrides]]`) goes in `city.toml`.
- **Do not double-import gastown.** gc-toolkit imports gastown
  transitively. Adding `[rigs.imports.gastown]` on top causes
  duplicate agent definitions.
