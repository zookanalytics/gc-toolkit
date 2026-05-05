# Note: dog is NOT in this directory by design

**Dog is provided by the auto-included maintenance pack** at
`.gc/system/packs/maintenance/agents/dog/` (re-materialized from the gc binary
embed on every `gc start`).

We tried to vendor `agents/dog/` into gc-toolkit during the Lane C cutover
2026-05-05 and hit the V2 validator gap: `cmd/gc/embed_builtin_packs.go`
unconditionally adds maintenance to the city's workspace.includes, so
maintenance.dog lands in `cfg.Agents` with `BindingName=""` (city-local). Our
gc-toolkit.dog (BindingName="gc-toolkit") collides on bare-name uniqueness in
`ValidateAgents` (`config.go:2548`, keys on `(Dir, Name)` not on
BindingName). Pack-level `[[patches.agent]]` from gc-toolkit can't reach the
auto-included maintenance.dog (patches only match within the same pack's
loaded agent list per `applyPackAgentPatches` in `pack.go:2147`), so we lose
the gastown wake_mode/work_dir patch behavior for dog.

## What we run with

- `dog` (bare name, no binding): scope=city, fallback=true, idle_timeout=2h,
  max_active_sessions=3 (from `.gc/system/packs/maintenance/agents/dog/agent.toml`)
- No `wake_mode = "fresh"` (was set by gastown's `[[patches.agent]]`; we no
  longer have that patch).
- No `work_dir = ".gc/agents/dogs/{{.AgentBase}}"` (same reason).

## When this becomes ownable

Either of the following upstream gascity changes would unblock vendoring dog:
1. `ValidateAgents` becomes binding-aware (keys on `(Dir, BindingName, Name)`).
2. `builtinPackIncludes` becomes opt-out or skips packs the user has shadowed.
3. Pack-level `[[patches.agent]]` learns to target qualified names from sibling
   packs (cross-pack patching).

Filed as part of the V2 conformance tracking in
`docs/research/pack-architecture/spike-gc-toolkit-as-primary-pack.md`
(Empirical correction section, 2026-05-05).
