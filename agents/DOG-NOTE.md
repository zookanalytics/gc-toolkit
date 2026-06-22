# Note: dog is owned by the imported gastown pack, not gc-toolkit

**Dog is intentionally provided by the imported gastown pack** at
`gastown/agents/dog/` (gastown's `pack.toml`: "This pack owns its dog pool").
Dog is shared housekeeping infrastructure — orphan sweeps, jsonl backups,
reaper, shutdown dance — that belongs in gastown's central city scope, not in
our domain-specific roster.

gc-toolkit owns the **domain crew** (mayor, deacon, boot, witness, refinery,
polecat). Dog is the **utility worker** that all packs use; it stays central.

## What we run

- `dog` (bare name, no binding): scope=city, idle_timeout=2h,
  max_active_sessions=3 (from gastown's `agents/dog/agent.toml`)
- Dog ships with the imported gastown pack, which owns the dog pool — no
  city-config edit needed. Required builtin packs are core/bd/dolt only
  (`cmd/gc/embed_builtin_packs.go:requiredBuiltinPackNames`); the maintenance
  pack that formerly auto-included dog is retired.

## Lane C history

We initially tried to vendor `agents/dog/` into gc-toolkit during the 2026-05-05
cutover. It collided with maintenance.dog on bare-name uniqueness in V2
`ValidateAgents` (which is binding-blind — see the spike doc empirical
correction). When we hit that, we recognized dog as appropriately central
rather than fight the loader. Cleaner outcome: gc-toolkit owns the domain
roster; the central utility pack owns the housekeeping. The architectural seam
matches the intent (maintenance provided that dog then; the imported gastown
pack owns it now).

## When to revisit

If we ever need a dog variant with custom prompt or behavior specific to this
city (not just configuration via `[[patches.agent]]`), re-evaluate then.
Otherwise the current split is the right one.
