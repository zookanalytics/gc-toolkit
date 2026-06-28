---
name: Gas City pack & formula authoring (gc-toolkit supplement)
description: The non-obvious decisions and traps when authoring gc-toolkit's own pack and formulas on the base Gas City packs — read before adding or changing a formula or pack.toml construct.
---

# Gas City pack & formula authoring

A curated, **non-obvious** supplement for building gc-toolkit's own pack and
formulas on top of the base Gas City packs. It does **not** restate the
upstream specs — it links them and captures only what bites. The canonical,
authoritative sources are:

- Formula contracts — [understanding-formulas](https://docs.gascity.com/guides/understanding-formulas) (guide), [formula-spec-v1](https://docs.gascity.com/reference/specs/formula-spec-v1), [formula-spec-v2](https://docs.gascity.com/reference/specs/formula-spec-v2), [specs index](https://docs.gascity.com/reference/specs)
- Packs — [understanding-packs](https://docs.gascity.com/guides/understanding-packs) (guide), [pack-spec](https://docs.gascity.com/reference/specs/pack-spec)

Read this in ~5 minutes, avoid every trap below, then follow the links for depth.

## Scope

**Mandate.** The non-obvious rules for authoring gc-toolkit's own pack and
formulas against the base Gas City packs — how to choose a formula contract,
how to opt into v2, and the `pack.toml` and pack-layering traps that bite —
synthesized from the canonical Gas City specs so a gc-toolkit builder is
guided to the right call.

**Boundaries.** Curated synthesis, not a copy of the specs: those are linked
and remain authoritative for the full format. This brief does not carry local
fixes against `gascity` *source* — that lifecycle is
[gascity-local-patching.md](gascity-local-patching.md) — and it does not index
the canonical documentation, which is
[gascity-reference.md](gascity-reference.md). It governs *how we author*, not
what any individual formula or pack *does*.

## 1. v1 and v2 are peers, not a ladder

This is the misconception to unlearn first, because it has already produced a
real mis-build here: treating formula **v2** as "newer / better / where we must
head" and **v1** as "legacy." It is not a version ladder. Upstream is explicit:
"v1 and v2 are peer contracts; both are supported. v1 is the **default**"
(formula-spec-v1, intro) and "they are peers, not a version ladder — each makes
a different thing the engine" (understanding-formulas, *Choosing a Compiler
Contract*).

Choose by **what the formula does**, not by version number:

- **v1** — the molecule is *data an agent works through* in its own session;
  the engine is the agent you sling to. Steps resolve at apply and then go
  inert; there is no runtime control flow. This is the right shape for
  prompt-driven coordination and patrol loops where one agent reads the steps
  and self-pours the next cycle.
- **v2** — a runtime-orchestrated **graph of independently-routable step beads**;
  the engine is the orchestrator. It buys `check` / `retry` / `drain` / `tally`,
  scope checks, a `workflow-finalize` sink, and per-step routing
  (`gc.run_target`) to many agents and scale-from-zero pools.

**For new orchestration work — default v2** (understanding-formulas, *Choosing a
Compiler Contract*): fan-out over a runtime-discovered set, multi-lane review
loops, orchestrator-driven check-until-pass, cross-agent step routing. For a
self-poured patrol loop, v1 is correct and v2's engine buys it nothing — which
is what gc-toolkit's patrol-style formulas are. The trap is reaching for v2
because it sounds more advanced; if no step ever needs to be independently
routed or re-checked by the engine, v2 is the wrong tool.

Two v1-only edges remain (neither a reason to *start* on v1): `gc converge`
accepts only v1 formulas, and v1 container-dependency semantics have a v2 gap
([gascity#3451](https://github.com/gastownhall/gascity/issues/3451)) — under v2,
enumerate the children you depend on explicitly in `needs`.

## 2. The v2 opt-in is `[requires] formula_compiler = ">=2.0.0"`

The canonical v2 declaration is exactly:

```toml
[requires]
formula_compiler = ">=2.0.0"
```

The older `contract = "graph.v2"` still parses but is **deprecated** — `gc
doctor` warns and tells you to switch (formula-spec-v2, *Conformance →
Opt-in surface* / *Deprecated surfaces*). No `[requires]` table at all means
**v1** (the default).

Graph-only constructs — `check`, `retry`, `drain`, `on_complete`, `tally`, and
reserved `gc.*` step metadata — require the v2 declaration; a formula that uses
them without it fails to compile. `formula_compiler` is the only `[requires]`
axis; an unknown axis is a hard error.

## 3. `phase = "vapor"` / root-only is legacy v1 — never pair it with v2

`phase` is "**legacy v1 materialization mechanics, not a v2 authoring
choice** … accepted for compatibility and **must not be used to design new
formulas**" (formula-spec-v2, *Top-Level Keys*). `phase = "vapor"` without a
pour compiles a **root-only** recipe: the step beads are never materialized.

So `[requires] formula_compiler = ">=2.0.0"` **on a `phase = "vapor"` /
root-only formula is self-contradictory** — you opt into the orchestrator and
then tell it to materialize only the root, so there are no step beads and no
`workflow-finalize` bead for the engine to run, and the workflow root never
self-closes through the engine's native path. (gc-toolkit hit exactly this: an
audit formula that declared the v2 compiler while keeping `phase = "vapor"`
re-hooked a polecat every cycle, because its root-only recipe had no
`workflow-finalize` bead for the engine to close. The fix is to drop the vapor
line and keep the v2 compiler — not the reverse.)

The reason the legacy hack existed: routing to a scale-from-zero pool needs a
**Ready-visible** surface, and a v1 molecule-container root is not Ready-visible
(`gc sling` rejects it), so `phase="vapor"`/root-only was the v1 workaround. A
**v2 workflow instead materializes independently routable, Ready-visible *step*
beads** that wake the pool without vapor; the workflow root itself depends on
`workflow-finalize` and stays blocked — **not** Ready-visible — while the
workflow runs.
Migrating to v2 is upstream's recommended remedy; the `phase="vapor"` alternative
named in the same error text is the legacy path, not a v2 option
(formula-spec-v2, *Conformance → Differences from v1*).

## 4. `until` loops (and friends) do not re-execute — "Accepted But Inert"

An `until` loop **runs exactly one iteration**. The compiler validates the
condition and writes a `loop:` label on the first body step, but **nothing in
the current runtime consumes it** — neither the v1 cook path nor the v2 control
dispatcher (formula-spec-v2, *Loops* and *Accepted But Inert*). For
orchestrator-driven re-execution, use a v2 `check` step (*Runtime → Check*).
gc-toolkit's patrols re-run by **self-pouring the next cycle**, not by `until`.

Treat the whole *Accepted But Inert* section as "parses, but no behavior" — do
not design around it:

- **gate `type` vocabulary** (`gh:run`, `gh:pr`, `timer`, `human`, `mail`) is
  doc-comment vocabulary only; no bundled watcher acts on it.
- **`waits_for` gate modes** — the `all-children` / `any-children` distinction
  is recorded but not interpreted by any dispatcher.
- **`vars.<name>.type`** (`string` / `int` / `bool`) is parsed but never
  enforced; only `required`, `enum`, and `pattern` are validated.

(Also note `until` does not use the `{{var}} == value` step-condition syntax —
it uses the runtime condition grammar, e.g. `probe.status == 'complete'`.)

## 5. Don't shadow base-pack artifact names

Pack artifacts resolve by **layer**: a higher-priority layer (your pack) with a
formula, prompt fragment, or asset of the **same name** as one in a base pack
**shadows** it (pack-spec, *Per-Directory Breakdown → `formulas/`* describes the
asset/formula layer resolution; *Loader → Naming And Collisions* covers agents).
The cost is silent: a shadowing copy **freezes the base pack's version of that
artifact**, so future upstream fixes to it are masked.

- **Audit by basename collision across layers**, not by reading `pack.toml` —
  an accidental same-name override does not appear in the manifest.
- **Agents are stricter than a shadow:** two agents that resolve to the same
  qualified name on the same surface **fail loading** outright — there is no
  fallback (pack-spec, *Naming And Collisions*). Imported agents are addressed
  by their binding-qualified name (`gastown.mayor`), not the bare local name.
- gc-toolkit's formulas are authored under pack-distinct `mol-*` names (no
  shadow). Preserve that: check the basename against the base packs before
  adding any formula, fragment, or script.

## 6. `pack.toml` authoring traps

Use the constructs in pack-spec's *Authoring Summary*; the ones that bite:

- **`schema = 2`, exact.** `[pack].schema` must be `2` for this pack format
  (pack-spec, *`[pack]`*).
- **Durable imports use `source` + `version`.** Declare dependencies as
  `[imports.<binding>]` with a `source` (required) and an optional `version`
  constraint/pin; durable identity is `source` + `version`. **Never** use
  `path`, `ref`, `commit`, or `hash` inside a public import table (invalid
  durable import TOML), and never persist a registry handle like `main:gascity`
  as `source` — handles are command-time lookups only (pack-spec,
  *`[imports.<binding>]`* / *Authoring Summary*).
- **`[[patches.agent]]` modifies, never creates.** A patch targets an existing
  agent by its bare local `name` (`dir = ""` in `pack.toml` matches by name
  before rig stamping) and **fails loading if the target doesn't exist**. Append
  to list fields with the `_append` variants — `inject_fragments_append`,
  `session_setup_append`, `pre_start_append`, etc. — never by re-declaring the
  agent (pack-spec, *`[[patches.agent]]`* / *Loader → Patches*).
- **Private files live under `assets/`.** Scripts, prompt fragments, and overlay
  trees referenced by a definition go under `assets/` (the loader resolves them
  only when referenced). There is **no top-level `scripts/`** directory — `gc
  doctor`'s `v2-scripts-layout` check flags one (pack-spec, *`assets/`*).
- **Banned / replaced in `pack.toml`** (the loader or `gc doctor` rejects these
  — see pack-spec, *Authoring Summary*):

  | Don't write | Use instead |
  |---|---|
  | `[[agent]]` (inline table) | `agents/<name>/agent.toml` + colocated prompt files |
  | `[formulas].dir` | the well-known `formulas/` directory |
  | `[pack].includes` | `[imports.<binding>]` |
  | `[agents]`, `[defaults.rig.imports]`, `[[patches.rigs]]`, `[[patches.providers]]` | city-level only (`city.toml`), not `pack.toml` |

## 7. `{{ .ConfigDir }}` resolves in prompts but is inert in formula bodies

Gas City expands `{{...}}` through **two different engines**, and writing the
prompt form in a formula silently no-ops the formula. Know which surface you
are authoring:

- **Prompts and template-fragments** (`*.template.md`, plus `session_setup` /
  `pre_start` commands) render through Go `text/template` with a populated
  context, so **dotted tokens resolve**: `{{.ConfigDir}}`, `{{.RigRoot}}`,
  `{{.WorkDir}}`. The `pre_start` example in
  [gascity-agents.md](gascity-agents.md)
  (`{{.ConfigDir}}/assets/scripts/worktree-setup.sh …`) relies on exactly this.
- **Formula / molecule step bodies** (`formulas/*.toml` `description`, and a
  step's `title` / `condition` / metadata) are expanded by **plain string
  substitution over a strict `{{name}}` pattern** — `[a-zA-Z_][a-zA-Z0-9_]*`,
  **no leading dot, no spaces** — with **no `text/template` pass at all**.
  Formula vars are that no-dot form (`{{base_branch}}`, `{{binding_prefix}}`,
  `{{event_timeout}}`). A step's `id` is **not** substituted — it is used
  verbatim as the bead's `Ref` / `gc.step_ref`, so it must be a literal.

So a dotted `{{ .ConfigDir }}` in a formula body never matches the var pattern:
it **survives literally and silently no-ops**. An
`[ -x "{{ .ConfigDir }}/assets/scripts/foo.sh" ]` guard written in a formula is
always false, and the script never runs.

**To call a pack script from a formula body, resolve at shell runtime via
exported env — never the token:**

```bash
"$GC_RIG_ROOT/assets/scripts/foo.sh"               # owning rig only (repo == pack)
"$GC_CITY_PATH/rigs/<pack>/assets/scripts/foo.sh"  # also resolves for importer rigs
```

`$GC_RIG_ROOT` points at the agent's own rig checkout, so it finds the script
only for the **owning** rig; the `$GC_CITY_PATH/rigs/<pack>/…` form is the
portable one, because every agent shares `$GC_CITY_PATH` (the city root) and the
script lives in the owning pack's tree under it. Do **not** reach for
`$GC_PACK_DIR` or `$GC_CONFIG_DIR` — they are populated only for order/command
execution and are **not exported to agent or worker sessions**, so a formula
that references them resolves an empty path.
