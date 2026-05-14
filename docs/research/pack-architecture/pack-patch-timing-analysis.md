# Pack-Patch Timing Analysis — V2 Two-Surface System

> **Bead:** tk-0t1ip. **Surveyed:** 2026-05-11. **Author:** Polecat gc-toolkit.nux.
> Read-only verification of `spike-gc-toolkit-as-primary-pack.md`. No edits to gascity source.

## Provenance

| Artifact | Source | Surveyed at |
|---|---|---|
| `applyPackAgentPatches` (pack-level matcher) | `rigs/gascity/internal/config/pack.go@d11ee0e1:2149-2174` | 2026-05-11 |
| pack-level patch call site | `rigs/gascity/internal/config/pack.go@d11ee0e1:1388-1394` | 2026-05-11 |
| inner-import binding stamp | `rigs/gascity/internal/config/pack.go@d11ee0e1:1219-1226` | 2026-05-11 |
| city-import unconditional rebind | `rigs/gascity/internal/config/pack.go@d11ee0e1:605-611` | 2026-05-11 |
| city-level `ApplyPatches` (post-compose) | `rigs/gascity/internal/config/patch.go@d11ee0e1:218-258` | 2026-05-11 |
| `ApplyPatches` invocation in compose | `rigs/gascity/internal/config/compose.go@d11ee0e1:499-505` | 2026-05-11 |
| `AgentMatchesIdentity` (binding-aware match) | `rigs/gascity/internal/config/config.go@d11ee0e1:139-159` | 2026-05-11 |
| `ValidateAgents` (binding-blind uniqueness) | `rigs/gascity/internal/config/config.go@d11ee0e1:2621-2687` | 2026-05-11 |
| `checkPackAgentCollisions` (binding-aware) | `rigs/gascity/internal/config/pack.go@d11ee0e1:927-959` | 2026-05-11 |
| `resolvedPackNames` (auto-include dedup) | `rigs/gascity/internal/config/compose.go@d11ee0e1:1354-1404` | 2026-05-11 |
| `builtinPackIncludes` (auto-include policy) | `rigs/gascity/cmd/gc/embed_builtin_packs.go@d11ee0e1:60-87` | 2026-05-11 |
| V2 loader design: "Apply patches" step | `rigs/gascity/docs/packv2/doc-loader-v2.md@d11ee0e1:603-608` | 2026-05-11 |
| Wrapper-pack precedent (bare-name patch) | `rigs/gascity/examples/gastown/packs/gastown/pack.toml@d11ee0e1:27-30` | 2026-05-11 |
| Spike under verification | `docs/research/pack-architecture/spike-gc-toolkit-as-primary-pack.md` | 2026-05-11 |

The spike pinned its citations at gascity SHA `669586546a`; line numbers have shifted slightly. This analysis re-pins at current HEAD `d11ee0e1` and has verified every load-bearing claim still holds.

---

## TL;DR

- **Timing of `applyPackAgentPatches`:** INTENTIONAL. It is one of *two* patch surfaces, by design, and the bare-name-against-inner-stamp slice is the only sensible semantic at its place in the pipeline.
- **Lane-B-shaped move (gc-toolkit `[imports.gastown]` + bare-name `[[patches.agent]]`):** SAFE, conditional on the prerequisites in §3. Identity migration cost is unchanged from the spike's Lane B (`spike §2.4 step 5`).
- **Additive qualified-name patch (`name = "gastown.mayor"` inside an imported pack):** ADDITIVE and small (~20 LOC + tests). Recommend shipping it *before* the Lane-B-shaped move depends on it.

---

## The Two-Surface Patch System

There are **two distinct patch application passes** with different semantics. Conflating them is the source of every confusion in the spike.

| Surface | Declared in | Applied at | Matcher | Binding-aware? |
|---|---|---|---|---|
| **Pack-level** | inner pack's `pack.toml` `[[patches.agent]]` | inside `loadPack` recursion (`pack.go:1388`) | `applyPackAgentPatches` (`pack.go:2149`) — bare `Name` only when `Dir == ""` | NO |
| **City-level** (root) | root `pack.toml` or `city.toml` `[[patches.agent]]` | after full compose (`compose.go:501`) | `ApplyPatches → applyAgentPatch → AgentMatchesIdentity` (`patch.go:218`, `config.go:146`) | YES |

`doc-conformance-matrix.md:65` and `skew-analysis.md:250` list qualified-name patch targeting as 🟢 implemented. They are correct — but only about the *city-level* surface. The pack-level surface remains bare-name-only.

---

## Q1 — Is the pre-binding-stamp timing intentional?

**INTENTIONAL.**

The doc comment at `pack.go@d11ee0e1:2143-2148` is explicit:

> When a patch has `Dir == ""`, it matches by `Name` alone — this is the normal case for pack authors who don't know which rig will use their pack (agents are rig-stamped during recursive loadPack before patches run). When `Dir` is set, both `Dir` and `Name` must match.

A spike-era claim ("patches run before binding stamp") is *imprecise*. By the time pack-level patches fire at `pack.go:1388`, the agents being patched have ALREADY been binding-stamped by the inner-import loop at `pack.go:1219-1226`. What has *not* yet happened is the **outer city-import unconditional rebind** at `pack.go:605-611`. The matcher just doesn't care: it ignores `BindingName` entirely (`pack.go:2154-2167`).

Why the pack-level surface exists at this timing: an imported pack needs to patch agents it inherits via its OWN `[imports.<>]` (e.g., gastown patches the `dog` agent it gets from `[imports.maintenance]` — `examples/gastown/packs/gastown/pack.toml:27-30`). The patch must run inside the imported pack's `loadPack` scope so the patched fields propagate transparently to consumers. Moving this surface post-compose would either (a) duplicate the city-level surface (which already provides qualified targeting at that stage) or (b) require a third pass — pack-scoped, post-compose — which the design has no slot for and the conformance matrix does not propose.

The V2 design doc (`doc-loader-v2.md:603-608`) describes "Apply patches" as post-compose with qualified-name targeting — that is exactly what the city-level surface (`compose.go:499-505`) implements. The pack-level surface is the narrower in-recursion path; the design intent for it is bare-name and limited.

**Verdict: INTENTIONAL.**

---

## Q2 — What controls match-ambiguity?

The `applyPackAgentPatches` loop (`pack.go:2150-2173`) iterates the merged agent slice and BREAKS on the first match (`pack.go:2160`, `:2166`). No collision check. No ambiguity warning. Order of agents in the slice is deterministic: import processing order in `loadPack` is `sort.Strings(importNames)` (`pack.go:1162-1166`), then convention-discovered agents are appended after (`pack.go:1307` → `:1381`).

Scenarios for the planned move (gc-toolkit `[imports.gastown]`, gc-toolkit `[[patches.agent]] name = "mayor"`):

- **A. Single import provides `mayor`.** gastown's `mayor` is the only `Name == "mayor"` agent inside gc-toolkit's pack composition. Patch lands on it. ✅
- **B. Multiple imports provide `mayor`.** If gc-toolkit also imported `swarm` (which has its own `mayor`), alphabetical order picks gastown's `mayor`; swarm's `mayor` is silently NOT patched. **Hidden footgun**, addressed by Q4.
- **C. gc-toolkit defines own `agents/mayor/` AND imports gastown.** Import-discovered `mayor` is appended first, so the patch matches gastown's. But after the city-level rebind (`pack.go:610`), both `mayor` agents end up with `BindingName = "gc-toolkit"` and `Dir = ""`. `ValidateAgents` (`config.go:2631`) keys on `agentKey{dir, name}` — binding-blind — and errors `duplicate name`. So this combination doesn't compose at all (the empirical correction in `spike §appendix` captured the same failure). **Forced choice**: import-with-patch OR own-agent — never both for the same bare name.
- **D. Same-bare-name only across transitive (not direct) imports.** Same first-wins rule. No collision unless rebind collapses them at city level.

For gastown's specific roster (`mayor / deacon / boot / witness / refinery / polecat / dog`), every bare name is unique across the import graph the spike contemplates. **No Scenario-B ambiguity arises for the actual proposed move** — but the qualified-name extension (Q4) is the only way to make this property *explicit* and survive a future second import.

---

## Q3 — Dual-load risk

The spike `§2.2` documented the failure when the city imports `gastown` *and* gc-toolkit also imports `gastown`: same agents reach two top-level bindings (`gastown.<x>` and `gc-toolkit.<x>`); `checkPackAgentCollisions` (binding-aware, keys on `QualifiedName`, `pack.go:941`) passes, but `ValidateAgents` (binding-blind, `config.go:2631`) rejects on `(Dir="", Name="<x>")` collision.

**For the planned Lane-B-shaped move**, the same failure recurs IF the city retains `[imports.gastown]`. **Prerequisite mitigation**: drop city `[imports.gastown]` before adding it to gc-toolkit's pack.toml.

**Maintenance auto-include risk:** `cmd/gc/embed_builtin_packs.go:72-87` auto-includes the `maintenance` pack at city scope. `compose.go:397-404` deduplicates against authored config via `resolvedPackNames` (`compose.go:1354-1404`), which **walks the import graph recursively** and computes the set of pack NAMES already reachable. If gc-toolkit → gastown → maintenance is in the authored graph, the auto-include hits `existingPacks["maintenance"] == true` and is SKIPPED. **No maintenance dual-load risk from this path.** The dedup is by pack NAME, not directory, so it survives different `source` paths pointing at the same logical pack.

**`transitive = false` risk:** `transitive = false` on gc-toolkit's `[imports.gastown]` would strip gastown's nested `[imports.maintenance]` (and thus `dog`), leaving a partial roster. **Do NOT use `transitive = false` for this move.**

**`packLoadCache` (`pack.go:976`)** dedups by absolute pack directory, but does not prevent re-insertion at multiple bindings — that's the dual-load mechanism itself. The cache is per-top-level expansion; it cannot help here.

**Verdict: SAFE** if and only if:

1. Drop `[imports.gastown]` from city `pack.toml` before adding `[imports.gastown]` to gc-toolkit's `pack.toml`.
2. Drop per-rig `[rigs.imports.gastown]` from `city.toml` (or replace with `[rigs.imports.gc-toolkit]` if rig-scope gastown agents should flow through gc-toolkit at rig level).
3. Leave gc-toolkit's `[imports.gastown]` as `transitive = true` (the default).
4. Do NOT introduce same-bare-name `agents/<x>/` shadows alongside the import — the validator rejects them (`§Q2 Scenario C`).

Identity migration cost is unchanged from the spike's Lane B (`spike §2.4 step 5`): every `gastown.<x>` runtime artifact (tmux session, bead `assignee` / `metadata.gc.routed_to`, mailbox, named-session template, mol formula `routed_to`) gets renamed to `gc-toolkit.<x>` at cutover. The city-level unconditional rebind at `pack.go:605-611` forces this rename regardless of whether the patch surface is bare-name or qualified.

---

## Q4 — Additive qualified-name pack-level patch?

**Today:** `[[patches.agent]] name = "gastown.mayor"` inside gc-toolkit's `pack.toml` fails. `applyPackAgentPatches` only compares the patch's `Name` field literally against `agents[j].Name` (`pack.go:2156`). No agent has `Name == "gastown.mayor"` — the loader's `validAgentName` (`config.go:25`) forbids dots in `Name`.

**Proposed extension:** when `Dir == ""` and `Name` contains a `.`, split on the last dot and treat the prefix as a binding match, the suffix as the bare-Name match. Sketch (~20 LOC):

```go
for i, p := range patches {
    binding, bare := "", p.Name
    if p.Dir == "" {
        if dot := strings.LastIndex(p.Name, "."); dot >= 0 {
            binding, bare = p.Name[:dot], p.Name[dot+1:]
        }
    }
    found := false
    for j := range agents {
        if p.Dir == "" {
            if agents[j].Name != bare {
                continue
            }
            if binding != "" && agents[j].BindingName != binding {
                continue
            }
            applyAgentPatchFields(&agents[j], &patches[i])
            found = true
            break
        } else {
            // unchanged: Dir+Name match
        }
    }
    // unchanged: error on !found
}
```

**Additive vs. replacing? ADDITIVE.**

- Bare-name patches (no dot in `name`) match exactly as today; the new branch only fires when `name` contains a `.`.
- Qualified-name patches become a stricter form of bare-name match: same `Name`, also same `BindingName`. They resolve Scenario-B ambiguity (Q2) cleanly.

**Binding resolution semantics:** at pack-level-patch time, `BindingName` reflects the inner `[imports.<>]` stamp from `pack.go:1219-1226` — i.e., the binding key the importing pack itself declared. So `name = "gastown.mayor"` in gc-toolkit's pack.toml resolves against the `gastown` binding that gc-toolkit's own `[imports.gastown]` declared. That matches the operator's mental model and stays consistent with the city-level surface's behavior (`AgentMatchesIdentity` also keys on `BindingName`).

**No conflict with the existing `qualifiedNameFromPatch` helper** at `patch.go:549-554`: that helper concatenates `Dir + "/" + Name` (V1-style `dir/name`). The proposed extension treats the dot specifically and only when `Dir == ""`. The two patterns do not collide.

**Validator interaction:** `AgentPatch.Name` is not subjected to `validAgentName` (that regex applies to agent names, not patch target strings). The city-level patch surface already accepts dotted strings via `qualifiedNameFromPatch + AgentMatchesIdentity`. No validator changes required.

**Test coverage:** add 2-3 cases to `internal/config/pack_test.go`:
- Qualified-name patch hits the correct binding;
- Qualified-name patch with non-existent binding errors with explanatory message;
- Bare-name patch (no dot) continues to match the first occurrence (unchanged behavior).

**Scope estimate:** ~20 LOC of new logic in `applyPackAgentPatches`; ~30-50 LOC of new tests. Single PR; ~1-2 hours of focused work plus review prep. Risk: low. No existing pack uses dot-qualified pack-level patches (the loader rejects them today), so adding meaning in the freed namespace is purely additive.

**Recommendation: SHIP the additive qualified-name extension *before* the Lane-B-shaped move depends on it.** Without it, gc-toolkit's patches work for gastown's current roster but rely on unique-bare-name luck for disambiguation; future second imports could shadow patches silently. With it, gc-toolkit's pack.toml gets a documentable, precise patch surface that the conformance matrix can promote alongside city-level qualified patches.

---

## Summary Verdicts

| Question | Verdict |
|---|---|
| Pre-binding-stamp timing of `applyPackAgentPatches` | **INTENTIONAL** — pack-level is one of two surfaces; bare-name against post-inner-stamp / pre-city-rebind slice is the design |
| Bare-name Lane-B-shaped move (gc-toolkit `[imports.gastown]` + bare-name `[[patches.agent]]`) | **SAFE** with the four prerequisites in §Q3. Same identity-migration cost as spike Lane B |
| Additive qualified-name patch extension (`name = "gastown.mayor"` in an importer's `pack.toml`) | **ADDITIVE; SHIP** — ~20 LOC + ~30-50 LOC tests; resolves Q2 ambiguity footgun; should land before the Lane-B-shaped move is final |

---

*End of analysis. No edits applied to gascity source.*
