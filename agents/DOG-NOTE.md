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
  (`cmd/gc/embed_builtin_packs.go:requiredBuiltinPackNames`); no builtin
  pack auto-includes dog.

## Why not vendored

Vendoring `agents/dog/` into gc-toolkit collides with the central dog on
bare-name uniqueness in V2 `ValidateAgents`, which is binding-blind. Dog
is appropriately central rather than worth fighting the loader over:
gc-toolkit owns the domain roster; the central utility pack owns the
housekeeping.

## When to revisit

If we ever need a dog variant with custom prompt or behavior specific to this
city (not just configuration via `[[patches.agent]]`), re-evaluate then.
Otherwise the current split is the right one.
