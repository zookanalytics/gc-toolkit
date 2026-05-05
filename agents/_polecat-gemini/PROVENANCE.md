# Agent: polecat-gemini (DISABLED)

**Status:** staged-inert (parent dir prefixed with `_` so `agent_discovery.go` skips it)
**Source:** N/A (gc-toolkit-original; mirrors `polecat` shape)
**Drift:** N/A

## Goals

Same as `polecat-codex` but for the Gemini CLI provider. Staged for future enablement; not active in the roster today.

## Why we built this

Same provider-diversity rationale as polecat-codex. Filed alongside as a parallel option.

## How to enable

```
mv rigs/gc-toolkit/agents/_polecat-gemini rigs/gc-toolkit/agents/polecat-gemini
gc reload
```

## Notes

Inert because `agent_discovery.go` skips directories prefixed with `_` or `.`. No runtime cost while disabled. When enabling, also write `PROVENANCE.md` referencing the same Codex notes adapted for Gemini.
