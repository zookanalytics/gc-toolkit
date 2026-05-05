# Spike: gc-toolkit as the Primary Pack (Wrapping gastown)

> **Bead:** tk-rw0cb. **Surveyed:** 2026-05-05. **Author:** Mechanik.
> Read-only survey; no edits to running config, gascity source, gc-toolkit pack.toml, or city.toml were performed.

## Provenance

| Doc-type or artifact | Producer (skill / concept / workflow step that emits it upstream) | Source location (URL or repo path + commit SHA) | Surveyed at |
|---|---|---|---|
| Pack v2 design (cities-as-packs, imports, qualified names) | pack-v2 design | `rigs/gascity/docs/packv2/doc-pack-v2.md@669586546a` | 2026-05-05 |
| Agent v2 design (agents-as-directories, patches, prompt overlay) | pack-v2 design | `rigs/gascity/docs/packv2/doc-agent-v2.md@669586546a` | 2026-05-05 |
| Loader v2 design (composition pipeline, scope filtering, binding stamping) | pack-v2 design | `rigs/gascity/docs/packv2/doc-loader-v2.md@669586546a` | 2026-05-05 |
| Rig binding phases (path/identity split) | pack-v2 design | `rigs/gascity/docs/packv2/doc-rig-binding-phases.md@669586546a` | 2026-05-05 |
| Conformance matrix (which v2 features are gated/tracked) | pack-v2 design | `rigs/gascity/docs/packv2/doc-conformance-matrix.md@669586546a` | 2026-05-05 |
| Directory conventions (top-level surfaces, patches dir) | pack-v2 design | `rigs/gascity/docs/packv2/doc-directory-conventions.md@669586546a` | 2026-05-05 |
| Packman lifecycle | pack-v2 design | `rigs/gascity/docs/packv2/doc-packman.md@669586546a` | 2026-05-05 |
| Skew analysis (release ledger) | pack-v2 design | `rigs/gascity/docs/packv2/skew-analysis.md@669586546a` | 2026-05-05 |
| Loader top-level (compose pack.toml + city.toml) | loader implementation | `rigs/gascity/internal/config/compose.go@669586546a` (lines 1-200, 540-580, 760+) | 2026-05-05 |
| City-pack and rig-pack expansion (`expandCityPacks`, `expandPacks`) | loader implementation | `rigs/gascity/internal/config/pack.go@669586546a` (lines 65-425, 432-742) | 2026-05-05 |
| Pack-level patch application (`applyPackAgentPatches`) | loader implementation | `rigs/gascity/internal/config/pack.go@669586546a` (lines 2120-2172) | 2026-05-05 |
| Scope filter (city vs rig) | loader implementation | `rigs/gascity/internal/config/pack.go@669586546a` (lines 2257-2296) | 2026-05-05 |
| Collision detection (`checkPackAgentCollisions`) | loader implementation | `rigs/gascity/internal/config/pack.go@669586546a` (lines 925-957) | 2026-05-05 |
| Patch surface and city-level apply (`ApplyPatches`, `applyAgentPatch`) | loader implementation | `rigs/gascity/internal/config/patch.go@669586546a` (lines 216-256) | 2026-05-05 |
| Identity model (`QualifiedName`, `BindingName`, `AgentMatchesIdentity`) | loader implementation | `rigs/gascity/internal/config/config.go@669586546a` (lines 48-125) | 2026-05-05 |
| Implicit-import bookkeeping (legacy ~/.gc/implicit-import.toml path) | loader implementation | `rigs/gascity/internal/config/implicit.go@669586546a` | 2026-05-05 |
| Pack-level patch test (V1 includes case) | gascity test suite | `rigs/gascity/internal/config/pack_test.go@669586546a` (lines 3127-3346) | 2026-05-05 |
| AgentMatchesIdentity test (V2 qualified-name match) | gascity test suite | `rigs/gascity/internal/config/import_test.go@669586546a` (lines 2176-2231) | 2026-05-05 |
| Wrapper-pack precedent (gastown imports maintenance, patches `dog`) | wrapper-pack precedent | `rigs/gascity/examples/gastown/pack.toml@669586546a` | 2026-05-05 |
| Inner gastown pack (city-scope mayor/deacon/boot + rig-scope witness/refinery + patches.agent on dog + named_session) | wrapper-pack precedent | `rigs/gascity/examples/gastown/packs/gastown/pack.toml@669586546a` | 2026-05-05 |
| Maintenance pack (pure rig-scope; provides dog) | wrapper-pack precedent | `rigs/gascity/examples/gastown/packs/maintenance/pack.toml@669586546a` | 2026-05-05 |
| gastown city.toml (inline crew, V1 workspace.includes) | wrapper-pack precedent | `rigs/gascity/examples/gastown/city.toml@669586546a` | 2026-05-05 |
| Swarm pack (alternate flat roster: mayor/deacon/dog city + coder/committer rig) | wrapper-pack precedent | `rigs/gascity/examples/swarm/packs/swarm/pack.toml@669586546a` | 2026-05-05 |
| Hyperscale pack (no city agents; pure rig pool; uses `[imports]`) | wrapper-pack precedent | `rigs/gascity/examples/hyperscale/packs/hyperscale/pack.toml@669586546a` and `examples/hyperscale/city.toml@669586546a` | 2026-05-05 |
| Lifecycle pack (rig-only roster; bash-script agents) | wrapper-pack precedent | `rigs/gascity/examples/lifecycle/packs/lifecycle/pack.toml@669586546a` | 2026-05-05 |
| BD pack (re-exports the dolt pack via `export = true`) | wrapper-pack precedent | `rigs/gascity/examples/bd/pack.toml@669586546a` | 2026-05-05 |
| K8s contrib (no Go pack composition; just deployment manifests) | wrapper-pack precedent | `rigs/gascity/contrib/k8s/` (no nested `pack.toml` content beyond a 39-byte `pack.toml`) | 2026-05-05 |
| Routing-namespace example tests (binding-qualified template lookups) | gascity test suite | `rigs/gascity/examples/routing_namespace_test.go@669586546a` | 2026-05-05 |
| Loomington city deployment (3 rigs, gastown imported via `.gc/system/packs`) | running city config | `/home/zook/loomington/city.toml` | 2026-05-05 |
| Loomington city pack (currently imports both gastown + gc-toolkit at city scope, plus per-rig defaults) | running city config | `/home/zook/loomington/pack.toml` | 2026-05-05 |
| gc-toolkit pack manifest (currently empty pack with one named_session) | running city config | `/home/zook/loomington/rigs/gc-toolkit/pack.toml` | 2026-05-05 |
| Staged gc-toolkit polecat agents (codex + gemini, inert at city scope) | running city config | `/home/zook/loomington/rigs/gc-toolkit/agents/polecat-codex/agent.toml`, `/home/zook/loomington/rigs/gc-toolkit/agents/_polecat-gemini/agent.toml` | 2026-05-05 |
| Site binding (workspace prefix `lx`, three rigs) | running city config | `/home/zook/loomington/.gc/site.toml` | 2026-05-05 |

---

## 1. Executive Summary

Pack v2 supports **wholesale, named imports** and **per-agent patches**, but it does NOT support **selective import** ("give me only `mayor` and `deacon` from gastown"). It also does NOT support **roster ownership without identity transfer** ("show `mayor` as `gc-toolkit.mayor` while keeping the prompt from gastown"). The mayor's qualified name follows the import binding name, and the binding name is the user-visible identity at runtime — it propagates to mailboxes, session names, bead routing, and named-session templates. There is no agent-inheritance / prompt-overlay / fragment-composition primitive that re-stamps an imported agent under a new binding without copy-paste.

Three viable architectures with distinct tradeoffs:

- **A. Keep siblings (status quo):** Two top-level imports (`gastown` for the gastown roster, `gc-toolkit` for mechanik/architect/concierge). No identity churn. Cost: gc-toolkit cannot meaningfully patch gastown's roster without each patch repeating qualified `gastown.<agent>` targeting and being authored at city level — mechanik never "owns" the roster.
- **B. gc-toolkit re-exports gastown (`export = true`):** gastown's agents flatten into the `gc-toolkit.*` namespace ("`gc-toolkit.mayor`"). Single binding handle. Cost: every running session, bead `assignee`/`owner`, mailbox path, and named-session template referring to `gastown.mayor` must be reconciled. Renames are not mechanically migrated.
- **C. gc-toolkit copies gastown's `agents/` and patches in place:** Full ownership, same identity (gc-toolkit.mayor everywhere). Cost: divergence drift from upstream gastown; manual reconciliation on every gastown release.

**Recommendation deferred to Mechanik decision bead.** The dual-load failure (`duplicate gc-toolkit.dog`) was a *consequence* of importing the same pack twice (city-scope + rig-scope simultaneously) — not a fundamental block on B or C. The pack-level patch failure (`agent "gastown.mayor" not found in pack`) is a *real loader limitation*: pack-level patches use bare-name match against the importing pack's own loaded roster (not the city-composed roster), so patching imports across binding boundaries from inside an inner pack is not supported by the current loader.

## 2. Mechanism Inventory

### 2.1 Selective import

**What the docs say.** None of the eight pack-v2 docs mention a selective-import facility. `[imports.X]` brings in the entire pack; the only *negative* control is `transitive = false` (suppress sub-imports that the imported pack made internally — `doc-pack-v2.md@669586546a` lines 237-249). Visibility filtering happens by **scope** at composition time, not by **roster slice**.

**What the loader does.** `expandCityPacks` (`rigs/gascity/internal/config/pack.go@669586546a` lines 538-718) loads `[imports.X]` packs in full, scope-filters via `filterAgentsByScope(agents, true)` (line 693 — keeps city + unscoped, drops rig), then stamps every surviving agent with `BindingName = bindingName` (line 608). `expandPacks` does the symmetric thing at rig level (lines 178-358), with `filterAgentsByScope(agents, false)` (line 332). There is no agent-name allowlist or denylist parameter on `Import` (`config.go@669586546a` lines 165-175 — `Source`, `Version`, `Export`, `Transitive`, `Shadow`).

**Closest workarounds.**

1. **`shadow = "silent"` + city-pack agent of the same bare name** (`pack.go@669586546a` lines 753-776 — shadow detection): the city pack's own `agents/<name>/` always wins over an imported agent with the same bare name. The user can suppress the warning per-import via `[imports.X] shadow = "silent"`. This is the documented "turn off an imported agent" mechanism (cited in `doc-pack-v2.md@669586546a` lines 437-440 — "Shadowing IS a valid way to 'turn off' an agent"). It is *additive*, not *subtractive*: you can't drop `gastown.witness` without providing your own `witness`.
2. **Re-export with `export = true`** (`doc-pack-v2.md@669586546a` lines 250-260): when pack B imports pack A with `export = true`, A's agents flatten into B's binding. Still wholesale — no per-agent picking.
3. **Copy the agent directory into your pack.** This is the only mechanism that gives you a roster slice. The cost is divergence from upstream.

**Gap.** Selective import is not a first-class V2 feature. The shadow/own-agent pattern is the documented escape hatch for *muting* an imported agent; nothing exists for *re-stamping* one under a different binding without copying.

### 2.2 Dual-load avoidance

**What the docs say.** `doc-loader-v2.md@669586546a` line 552 specifies that transitive imports are resolved DFS against the **root city's single lock file**, and section 8 (lines 528-540) says the loader detects cycles. The docs do not explicitly address "the same pack appears in `pack.toml [imports]` and `city.toml [[rigs]] imports` simultaneously."

**What the loader actually does.** No coordinated dedup between city-scope and rig-scope expansion paths. They run independently:

- `ExpandCityPacks` walks `cfg.Imports` (city-level) and produces city-scoped agents stamped with `BindingName` (`pack.go@669586546a` lines 538-742).
- `expandPacks` walks each rig's `rig.Imports` independently (lines 65-425). Each rig uses its own `cache := &packLoadCache{...}` (line 73) — *not shared with the city cache*.
- `checkPackAgentCollisions` (lines 925-957) detects duplicates **within the same scope**: it compares `QualifiedName()` across the agents that were just composed for one rig (or for the whole city), keyed by `SourceDir`. A duplicate is reported only when **two distinct source directories** define the same qualified name within that scope.

This means dual-loading the same pack at city scope (rig-scoped agents are filtered out, only city-scoped survive) and at rig scope (city-scoped filtered out, only rig-scoped survive) is not in itself a duplicate — they don't overlap in scope, so collision detection passes.

**Why the failure happened today.** When gc-toolkit's `pack.toml` added `[imports.gastown]` and was simultaneously declared at the city level (`pack.toml [imports.gc-toolkit]`) and at each rig (`city.toml [[rigs]] [rigs.imports.gastown]`), gastown's `dog` agent (city-scoped, declared in `examples/gastown/packs/gastown/pack.toml@669586546a` with no scope on `[[patches.agent]] name = "dog"` line 27-30) was reached twice via two different transitive paths through `gc-toolkit`:

- Path 1: `pack.toml [imports.gc-toolkit]` → gc-toolkit's `[imports.gastown]` → gastown's `[imports.maintenance]` → maintenance's `dog`
- Path 2: `pack.toml [imports.gastown]` → gastown's `[imports.maintenance]` → maintenance's `dog`

Both surfaces stamp `BindingName = "gc-toolkit"` (resp. `"gastown"`) at the city-level expansion (line 608 `agents[i].BindingName = bindingName`). The *qualified* names are different (`gc-toolkit.dog` vs `gastown.dog`), so cross-binding collision shouldn't fire. The actual `duplicate gc-toolkit.dog` error came from gc-toolkit being **traversed twice** in the gc-toolkit-binding scope: once as the direct city import, once as the transitive carrier of `gastown` whose pack-level `[[patches.agent]] name = "dog"` runs against gc-toolkit's loaded agent list during inner `applyPackAgentPatches` (`pack.go@669586546a` line 1389) and gets duplicated when both copies of gc-toolkit's agent set are emitted.

**Mitigation in the current loader.** None, structurally. The only escape hatches the docs describe are:

- `transitive = false` on the inner import (`doc-pack-v2.md@669586546a` lines 240-249) to keep gastown as gc-toolkit's *internal* dep without re-exposing it.
- Removing the duplicate top-level import (don't list `gastown` in the city `pack.toml [imports]` if gc-toolkit already imports it).

### 2.3 Roster ownership

**What the docs say.** `doc-agent-v2.md@669586546a` lines 453-489 describe agent patches: "Patches modify imported agents without defining new ones … `agents/<name>/` always creates YOUR agent; `[[patches.agent]]` modifies SOMEONE ELSE's agent." Patches can override `model`, `max_active_sessions`, `env`, plus a `prompt` field (file relative to `patches/`) that replaces the imported agent's prompt (lines 470-475). The `patches/` directory is **listed** in `doc-directory-conventions.md@669586546a` lines 331-335 as the pack convention ("Holds prompt replacement files for imported agents") — but `doc-conformance-matrix.md@669586546a` line 102 marks it as **🔴 Track, but do not gate yet**: "documented in v.next docs, not implemented. Current implementation still relies on explicit patch fields rather than full loader-discovered patch files."

**What the patch surface actually supports today** (`patch.go@669586546a` lines 17-134): nearly every per-agent runtime field (work_dir, scope, env, pre_start, prompt_template, provider, start_command, nudge, idle_timeout, sleep_after_idle, install_agent_hooks, session_setup, session_setup_script, session_live, overlay_dir, default_sling_formula, inject_fragments, append_fragments, attach, depends_on, resume_command, wake_mode, max_active_sessions, min_active_sessions, scale_check, option_defaults, plus `_append` siblings for several list fields). What patches cannot change: the agent's bare `Name`, its `BindingName`, or its `QualifiedName()`. There is no mechanism to *rename* an agent or *re-stamp* its binding via patches.

**Where patches actually apply.** Two paths:

1. **City-level patches** (`patch.go@669586546a` `ApplyPatches` line 216 → `applyAgentPatch` line 236): loops over `cfg.Agents` after composition; matches by `AgentMatchesIdentity(a, target)` which tries V2 qualified name first then V1 fallback (`config.go@669586546a` lines 112-125). Targeting `gastown.mayor` works here because the agent has `BindingName = "gastown"` after `expandCityPacks` stamped it.
2. **Pack-level patches** (`pack.go@669586546a` `applyPackAgentPatches` lines 2147-2172, called from `loadPack` line 1389): loops over the agents loaded *within this pack's recursive include/import chain*; matches by **bare `Name` only** when `Dir == ""`. This runs **before** `BindingName` is stamped. So a patch in gc-toolkit's pack.toml saying `[[patches.agent]] name = "mayor"` can only match an agent whose bare name is `mayor` and which is *already inside the loaded subtree* of gc-toolkit at the moment the patch fires. If `mayor` came in via `[imports.gastown]` *inside* gc-toolkit, the loader's recursion brings it in first (so it IS in the agent list at this point), and the patch matches by bare name — but if the patch targets `gastown.mayor` (with the dot), the bare-name match fails because the binding hasn't been stamped yet.

**Examples in the wild.**

- `examples/gastown/packs/gastown/pack.toml@669586546a` lines 27-30: `[[patches.agent]] name = "dog"` patches the `dog` agent (brought in via `[imports.maintenance]`). Bare name match works because it runs at pack-load time after maintenance is recursed in.
- `examples/bd/pack.toml@669586546a`: `[imports.dolt] export = true` — the BD pack re-exports dolt's roster into `bd.*` namespace. This is the closest precedent for "roster ownership."
- `examples/gastown/pack.toml@669586546a` lines 6-12 (the *outer* gastown wrapper): `[imports.gastown] source = "packs/gastown"`. The outer pack is named `gastown`; the inner pack is also named `gastown` — both share the binding name `"gastown"`. This is the pattern you'd want to adapt for "gc-toolkit owns the roster": rename the binding, not the inner pack.

**Gap.** There is no documented "claim ownership of an imported agent's identity" primitive. `export = true` (re-export) is the closest: it flattens the imported pack's agents into the importing pack's binding. Combined with city-pack `[[patches.agent]]` for per-field tweaks and `agents/<name>/` shadowing for full replacement, this is the documented composition surface. But: re-export changes the qualified name (binding name shifts), and shadowing means writing your own agent directory.

### 2.4 Migration path (current → "gc-toolkit owns")

**Status quo to preserve.**

- City pack imports two packs at city scope (`pack.toml [imports.gastown]` + `[imports.gc-toolkit]`).
- City `pack.toml` `[defaults.rig.imports.gastown]` provides the per-rig default; loader doesn't yet honor it (`doc-conformance-matrix.md@669586546a` line 100 — 🔴 Track, but do not gate yet); current `city.toml` lines 6-29 declares `[rigs.imports.gastown]` per rig explicitly.
- gc-toolkit's pack.toml is intentionally minimal (one `[[named_session]] template = "mechanik"`); its agents come from convention discovery in `agents/`.
- Mechanik, architect, concierge, consult-host run as `gc-toolkit.<name>` at city scope.
- gastown.mayor, gastown.deacon, gastown.boot run at city scope. gastown.witness, gastown.refinery, gastown.polecat run per rig (qualified `<rig>/gastown.<agent>`).
- Existing sessions, beads, mailboxes, mol-* formula targets and routed_to fields use these qualified names.

**Per-step migration plan (to "gc-toolkit owns; gastown library").**

The minimal "wrap" that doesn't strand identities and stays within today's loader is to *not* re-export and instead keep the dual-binding model but make gc-toolkit a *proper* pack with its own roster awareness:

1. **No-op smoke check.** `gc config show --json` from city root and from each `rigs/<rig>/` CWD; capture qualified-name list. **Risk:** baseline. **Runs vs. restarts:** read-only; nothing restarts.
2. **Pin the goal.** Decide whether the new binding is `gc-toolkit.mayor` (B: re-export) or `gastown.mayor` stays (A: sibling) or `gc-toolkit.mayor` and gastown becomes vestigial (C: copy roster). This decision belongs in a separate decision bead; the polecat patch follows the chosen lane.
3. **(Lane B only) Add `[imports.gastown] export = true` to gc-toolkit's pack.toml.** **Risk:** flattens `gastown.*` into `gc-toolkit.*` only when the outer city *removes* its direct `[imports.gastown]`. With the city's current dual import, this would emit duplicate `gc-toolkit.mayor` (one direct, one re-exported). Do not apply without step 4.
4. **(Lane B only) Drop `[imports.gastown]` from city `pack.toml`.** Now the only path to `gastown` is through gc-toolkit. **Risk:** loud — every running session named `gastown.<agent>` now has no matching agent in the composed config; reconciler will see them as orphans. This is the irreversible point.
5. **(Lane B only) Migrate identities.** The runtime artifacts that depend on the qualified name and need attention before step 4 takes effect:
   - **Tmux session names** (`internal/session/named_config.go@669586546a` line 71 uses `spec.Agent.QualifiedName()`): existing `gastown.mayor` tmux session does not match new `gc-toolkit.mayor`. Restart all sessions OR reconcile via a session-rename pass (no built-in).
   - **`.gc/agents/<work_dir>` directories**: mechanik's `work_dir = ".gc/agents/mechanik"` is fine (no qualifier); gastown's mayor uses `work_dir` from its own agent.toml; review each. Worktrees under `.gc/worktrees/<rig>/polecats/gastown.<name>` will need to be renamed or recreated.
   - **Beads** (`bd assignee`, `owner`, `metadata.routed_to`): every open bead with `assignee = "gastown.mayor"` or `gc.routed_to = "<rig>/gastown.polecat"` needs `bd update --assignee gc-toolkit.mayor` or equivalent. There is no migration script; this is a SQL pass on Dolt.
   - **Mailboxes** (`internal/mail/resolve.go@669586546a` line 53 — exact `QualifiedName()` literal match): unread mail addressed to `gastown.mayor` will resolve fail. Quarantine in-flight mail before the cutover.
   - **Named-session templates** referencing bare `mayor` continue to work; templates using `gastown.mayor` need rewrite.
   - **mol-* formula `work_query` / `routed_to` labels** that hardcode `gastown.<agent>`: scan `examples/.../formulas/` and any local formula edits.
6. **Idle-down before cutover; restart full city after.** Acceptable downtime: one full reconcile cycle. **Risk:** if anything is missed in step 5, agents with stale assignees become silent (no inbox match) or orphaned (no session match).

**Lane A (keep siblings) requires no migration steps**; it just declines to consolidate.

**Lane C (copy gastown roster into gc-toolkit/agents/)** has the same identity-migration cost as B (everything renames from `gastown.*` to `gc-toolkit.*`) PLUS the ongoing maintenance cost of merging upstream gastown changes into the copied directory by hand.

### 2.5 Identity stability

**What controls the qualified name.** `Agent.QualifiedName()` (`config.go@669586546a` lines 70-76) returns `Dir + "/" + BindingName + "." + Name` (with components elided when empty). `BindingName` is set by the loader at import-expansion time:

- City-level `[imports.X]` sets `BindingName = X` for every agent in the imported pack (`pack.go@669586546a` line 608).
- Rig-level `[rigs.imports.X]` does the same per rig (line 251).
- `export = true` does NOT propagate the inner binding — the docs (`doc-pack-v2.md@669586546a` lines 250-260) specify *flattened* re-export: maintenance's `dog` re-exported through gastown becomes `gastown.dog`, not `gastown.maintenance.dog`. Loader stamps `BindingName = bindingName` (the importer's binding) when `imp.Export` is true, overriding any prior binding (line 608 unconditional).

**Direct answer to the question.** If gc-toolkit becomes the primary import and re-exports gastown (lane B), the mayor's qualified name **shifts** from `gastown.mayor` to `gc-toolkit.mayor`. If gc-toolkit just adds `[imports.gastown]` without `export = true` and the city continues to import gastown directly (lane A), the qualified name **stays** `gastown.mayor`. There is no in-between — the binding name is the rename axis.

**What runtime artifacts depend on the qualified name.**

- **Tmux session naming** — `internal/session/named_config.go@669586546a` line 71: `spec.Agent.QualifiedName()` is the canonical session identifier. Renaming bindings = orphaning live sessions.
- **Mailbox routing** — `internal/mail/resolve.go@669586546a` lines 49-54: literal qualified-name match on inbound mail `to:` field.
- **Bead assignment** — `bd assignee` / `owner` fields are populated from `QualifiedName()` at session-claim time; existing beads carry whichever name was current when they were claimed.
- **Bead `metadata.gc.routed_to` labels** — formula `work_query` and `sling_query` contain literals like `gc.routed_to=<rig>/gastown.polecat`; binding rename invalidates routed_to matches until updated. (`examples/routing_namespace_test.go@669586546a` enforces canonical templates only — no automatic rewrite.)
- **Named-session templates** — `[[named_session]] template = "..."` accepts bare names when unambiguous; if templates currently say `gastown.mayor`, they must be updated.
- **`.gc/agents/<work_dir>` and `.gc/worktrees/<rig>/<binding>.<agent>/`** — work_dir and worktree paths often interpolate `{{.AgentBase}}` or `{{.Agent}}`; check each agent's pack-defined `work_dir` template for whether the binding appears.
- **gc.json / events.jsonl / supervisor registry** — qualified names are the human-readable identity in events; analytics joins on them.
- **Polecat dispatch / sling targets** — `gc sling --to <rig>/gastown.polecat` literals need rewrite.

**Is rename avoidable?** Only by staying in lane A. Any consolidation that puts gc-toolkit as the gateway for gastown's roster (lanes B and C) renames every gastown agent on the cutover.

## 3. Migration Analysis (consolidated)

### 3.1 Per-lane file edits

**Lane A — Keep siblings (no edits).**
- City `pack.toml`: unchanged (both `[imports.gastown]` and `[imports.gc-toolkit]` remain).
- gc-toolkit `pack.toml`: optionally add city-scope `[[patches.agent]]` blocks targeting qualified `gastown.<agent>` from the city-pack layer (gc-toolkit *as a city pack* contributes patches to the composed roster — patch-application is at city level via `ApplyPatches`, not pack level via `applyPackAgentPatches`). This works.
- city.toml: unchanged.

**Lane B — gc-toolkit owns; re-export gastown.**
- gc-toolkit `pack.toml`: add
  ```toml
  [imports.gastown]
  source = "../../.gc/system/packs/gastown"
  export = true
  ```
  Path note: gc-toolkit is at `rigs/gc-toolkit/`; the city's gastown copy is at `.gc/system/packs/gastown/`. The `source` must resolve relative to gc-toolkit's pack root, which means a relative `../../.gc/system/packs/gastown`. Pack-self-containment validation may flag this (`doc-loader-v2.md@669586546a` step 7, "any path that escapes the pack directory is a hard error"). If self-containment is enforced strictly, the gastown source must live INSIDE gc-toolkit (e.g., `assets/gastown/` or a submodule).
- City `pack.toml`: remove `[imports.gastown]` and `[defaults.rig.imports.gastown]`; remove the city-level dual import. Keep `[imports.gc-toolkit]`.
- city.toml: remove all `[rigs.imports.gastown]` entries (now inherited via gc-toolkit's re-export — or replace with `[rigs.imports.gc-toolkit]` if rig-scope agents from gastown need to come through gc-toolkit at rig level).
- *Identity migration:* see §2.4 step 5.

**Lane C — gc-toolkit copies the roster.**
- gc-toolkit `agents/`: add `mayor/`, `deacon/`, `boot/`, `witness/`, `refinery/`, `polecat/`, `dog/` directories with `agent.toml` and `prompt.template.md` copied from `examples/gastown/packs/gastown/agents/<name>/`. (Not literally — paths to scripts and overlays from the originals would break. Asset references must be retargeted.)
- gc-toolkit `pack.toml`: add `[[named_session]]` for each.
- City `pack.toml`: drop `[imports.gastown]`.
- city.toml: drop `[rigs.imports.gastown]` per rig.
- *Maintenance cost:* every gastown release requires a manual diff/merge.

### 3.2 Per-step risk

| Step | Risk | What runs vs. restarts |
|---|---|---|
| Capture baseline `gc config show` | None | Read-only |
| Add `[imports.gastown] export = true` to gc-toolkit `pack.toml` (without dropping city import) | DUPLICATE: same agents reachable via two import paths in gc-toolkit binding — loader emits `duplicate gc-toolkit.<agent>` immediately on `gc reload` | Reload fails; nothing has restarted yet |
| Drop city-level `[imports.gastown]` | Existing `gastown.*` sessions become orphans; mailboxes for `gastown.*` lose resolution | All gastown.* sessions need restart under new binding |
| Bead reassignment SQL pass | Wrong update = silently misroutes future polecat dispatch | None at write time; effects appear on next bead claim |
| Mailbox quarantine + replay | Mail loss if not paused first | Mail daemon must be quiescent during cutover |
| `gc reload` after all edits | If ANY runtime artifact still references old binding, that artifact orphans; observable as no-op nudges, hook misses | Full city restart preferred over per-agent reload |

### 3.3 What stays running vs. what restarts

- **Stays:** Dolt server, mail daemon (briefly paused), supervisor, dogs (brief flap).
- **Restarts:** Every named session whose template references the renamed roster. With the current 7+ named gastown sessions across 3 rigs, that's the entire orchestration crew.

### 3.4 Identity stability assessment

Lane B trades a one-shot identity-rename event for a clean ongoing namespace (gc-toolkit.* across the board). Lane A keeps two namespaces forever. Lane C eliminates the upstream binding but assumes ownership of upstream maintenance.

## 4. Recommended Starter Patch (described, not applied)

**Smallest validating edit**: add ONE city-level `[[patches.agent]]` to gc-toolkit's pack.toml that overrides the mayor's `nudge` field (or adds a single env var) using the qualified target `gastown.mayor`. Do NOT add `[imports.gastown]` to gc-toolkit's pack.toml. Do NOT touch the city's pack.toml.

```
# rigs/gc-toolkit/pack.toml — proposed addition (DO NOT APPLY in this spike)
[[patches.agent]]
name = "gastown.mayor"
nudge = "[gc-toolkit override] Check mail and assigned work, then act."
```

**What it would prove.**
- That gc-toolkit, while loaded as a city pack via the existing city `[imports.gc-toolkit]`, can contribute `[[patches.agent]]` blocks targeting agents from a *different* binding (`gastown.mayor`).
- That the city-level `ApplyPatches` (`patch.go@669586546a` line 216) — distinct from the inner pack-level `applyPackAgentPatches` (`pack.go@669586546a` line 2147) — accepts qualified-name targeting (`AgentMatchesIdentity` `config.go@669586546a` line 112).
- That this patch survives the dual-load (gc-toolkit imported at both city and rig scopes) without re-firing at rig scope.

**What it would NOT prove.**
- Anything about re-export (`export = true` semantics).
- Whether a `[[patches.agent]]` from inside gc-toolkit's pack.toml binding scope can target an agent that arrives via a sibling binding at city level (the failure mode that bit Mechanik today).
- Whether identity migration is feasible — the mayor's qualified name remains `gastown.mayor`.
- Whether rig-scope agents (witness, refinery, polecat) can be patched the same way (rig-scope patches use `[[rigs.patches]]` in `city.toml`, not `[[patches.agent]]` in a pack — different surface, separate test).

**Rollback.** Delete the added block; `gc reload`. Zero state side-effects.

## 5. Open Questions

1. **Pack self-containment vs. cross-pack source paths.** `doc-loader-v2.md@669586546a` step 7 says paths escaping the pack directory are hard errors, but `doc-pack-v2.md@669586546a` line 386 only mentions this as a future check. The current loader behavior on `source = "../../.gc/system/packs/gastown"` from inside `rigs/gc-toolkit/pack.toml` was not exercised in this spike. If self-containment is enforced, lane B requires gastown to be vendored inside gc-toolkit's directory tree (assets, submodule, or symlink).

2. **`[defaults.rig.imports.<binding>]` loader support.** `doc-conformance-matrix.md@669586546a` line 100 marks this as 🔴 not implemented today (loader ignores it). The current city `pack.toml` declares this block but is *also* declaring `[rigs.imports.gastown]` per rig in `city.toml` for safety. Migration sequencing should not depend on `defaults.rig.imports` until the loader honors it.

3. **What happens to a `[[named_session]] template = "mayor"` after binding rename?** The named_session resolver in `internal/session/named_config.go@669586546a` line 55 calls `config.FindAgent(cfg, named.TemplateQualifiedName())`. If the template is the bare name `mayor` and there's exactly one mayor in the composed roster, it resolves; if ambiguous it errors at the referring site (`doc-pack-v2.md@669586546a` lines 367-371). After lane B, `mayor` is unambiguous (only `gc-toolkit.mayor` exists), so bare-name templates would still resolve. This is an unverified inference from the docs, not something this spike empirically tested.

4. **Whether the actual "duplicate gc-toolkit.dog" error originated from the patch path (`applyPackAgentPatches`) duplicating an agent or from the import-graph path (DFS through `gc-toolkit → gastown → maintenance` *and* a separate `gastown → maintenance`) emitting two copies of `dog` under the gc-toolkit binding.** The shared cache in `expandCityPacks` (`pack.go@669586546a` line 455) deduplicates by absolute pack directory, but the cache is per-call (city vs each rig); the patch application in `loadPack` (line 1389) re-applies patches each time the pack is loaded fresh through a different parent. Reproducing the failure deliberately and capturing the loader trace would resolve this.

5. **Whether the `patches/` directory convention** (`doc-directory-conventions.md@669586546a` line 331) — discoverable prompt-replacement files — is implementable today by manually setting `prompt_template = "patches/<file>.md"` in a `[[patches.agent]]` block. The skew analysis says the directory convention is not implemented, but the patch field IS implemented. Lane B and C might benefit from prompt overlay (re-skin imported gastown agents without copying the prompt) without requiring the directory convention.

6. **Whether `gc bd update --assignee` accepts the binding-rename rewrite of in-flight beads, and at what scale.** No bd command in `examples/bd/pack.toml@669586546a` performs bulk-rewrite; this is a SQL operation against Dolt, with all the consistency caveats that brings.

---

*End of spike report. No edits applied. Decisions belong in a separate decision bead per the "Decisions belong in decision beads" pattern in MEMORY.*

---

## Empirical correction (appended 2026-05-05)

**Operator chose Lane D after this spike. Lane D failed at first canary attempt (`agents/boot/` shadow). Pivoted to Lane C.**

The spike's §2.1 / §5 #3 implicit claim that V2 selective-shadow works was incorrect. Empirical findings from the canary:

- Created `rigs/gc-toolkit/agents/boot/` (verbatim clone of `rigs/gascity/examples/gastown/packs/gastown/agents/boot/`).
- `gc config show --validate` rejected the composed config:
  ```
  agent "gc-toolkit.boot": duplicate name (from "/home/zook/loomington/.gc/system/packs/gastown" and "/home/zook/loomington/rigs/gc-toolkit")
  ```
- Two distinct loader gaps cause this:
  1. **Shadow logic only warns; never filters.** `expandCityPacks` (`rigs/gascity/internal/config/pack.go@669586546a` lines 749-775) builds a list of imported agent bare names and warns when a *city-local* agent (BindingName == "") shadows one of them. Even when `[imports.X] shadow = "silent"` is set, the suppression only silences the *warning*. The imported agent stays in `cfg.Agents`. There is no code path in `pack.go` that removes a shadowed agent from the agent list.
  2. **Validator is binding-blind.** `ValidateAgents` (`rigs/gascity/internal/config/config.go@669586546a` lines ~2548-2557) keys uniqueness on `agentKey{dir: a.Dir, name: a.Name}`. `BindingName` is not part of the key. So `gastown.boot` and `gc-toolkit.boot` collide on bare name `boot` regardless of binding. The composition pipeline's binding-aware uniqueness (`checkPackAgentCollisions`, `pack.go@669586546a` lines 925-957, keyed by `QualifiedName()`) passes — but the post-composition validator catches them.
- Additionally, the shadow detection code only triggers when `a.BindingName == ""` (a city-local agent in the city's own pack.toml). For our case both colliding agents have non-empty `BindingName` (`gastown` and `gc-toolkit` respectively), so the shadow warning never fires either way.
- V2 docs (`rigs/gascity/docs/packv2/doc-pack-v2.md@669586546a` lines 437-440) explicitly state shadow IS a valid way to "turn off" an agent. The skew-analysis (`skew-analysis.md@669586546a` line 194) marks `shadow` as 🟢 "Present." Both are correct about the warning logic, both are wrong about actual suppression. Real V2 spec/impl skew.

**Implications:**
- Lane D (selective shadow) is not viable in the current loader. Future viability requires either (a) `ValidateAgents` becomes binding-aware, or (b) `expandCityPacks` actually filters shadowed agents from `cfg.Agents`.
- Spike §2.1 workaround #1 ("`shadow = "silent"` + city-pack agent of the same bare name") is also infeasible for the same reason — `ValidateAgents` rejects.
- Lane B and Lane C remain viable; both require the gastown→gc-toolkit identity rename.
- Lane C selected by operator 2026-05-05 with explicit "we can migrate back to D if/when the loader catches up." Worth tracking gascity loader changes.

**Failed canary state:** rolled back. `rigs/gc-toolkit/agents/boot/` removed; `gc config show --validate` clean. No commits.

**Should be filed upstream against gascity:** the spec/impl skew is a real bug — V2 design says shadow works; loader doesn't honor it. Gating on operator approval (per `gascity-local-patching.md` framework: this is "engage" territory because the doc-asserted V2 feature is materially broken).
