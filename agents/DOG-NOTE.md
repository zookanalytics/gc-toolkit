# Note: dog lives in maintenance, not gc-toolkit

**Dog is intentionally provided by the auto-included maintenance pack** at
`.gc/system/packs/maintenance/agents/dog/` (re-materialized from the gc binary
embed on every `gc start`). Dog is shared housekeeping infrastructure — orphan
sweeps, jsonl backups, reaper, shutdown dance — that belongs in maintenance's
central scope, not in our domain-specific roster.

gc-toolkit owns the **domain crew** (mayor, deacon, boot, witness, refinery,
polecat). Dog is the **utility worker** that all packs use; it stays central.

## What we run

- `dog` (bare name, no binding): scope=city, fallback=true, idle_timeout=2h,
  max_active_sessions=3 (from `.gc/system/packs/maintenance/agents/dog/agent.toml`)
- gc binary auto-includes maintenance via
  `cmd/gc/embed_builtin_packs.go:builtinPackIncludes` — no city-config edit
  needed.

## Lane C history

We initially tried to vendor `agents/dog/` into gc-toolkit during the 2026-05-05
cutover. It collided with maintenance.dog on bare-name uniqueness in V2
`ValidateAgents` (which is binding-blind — see the spike doc empirical
correction). When we hit that, we recognized dog as appropriately central
rather than fight the loader. Cleaner outcome: gc-toolkit owns the domain
roster; maintenance owns the housekeeping. The architectural seam matches the
intent.

## When to revisit

If we ever need a dog variant with custom prompt or behavior specific to this
city (not just configuration via `[[patches.agent]]`), re-evaluate then.
Otherwise the current split is the right one.
