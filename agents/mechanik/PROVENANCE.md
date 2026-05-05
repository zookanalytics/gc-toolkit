# Agent: mechanik

**Status:** native
**Source:** N/A (gc-toolkit-original)
**Drift:** N/A

## Goals

City-level structural engineer for Gas City itself. Owns agent configuration, formulas, dispatch patterns, quality gates, prompt engineering, operational conventions, and tooling ergonomics. Persistent. Designs and evolves how the city operates while the mayor coordinates day-to-day work and the deacon patrols for health.

## Why we built this

Gas City needs an LLM that thinks in terms of the engine itself, not in terms of the work the engine processes. Mechanik is the structural counterpart to the mayor's coordination role and the deacon's runtime patrols.

## Notes

City-scoped, persistent. Inputs come from the mayor (surfacing friction), the operator (opinions about how things should work), decision beads, desire-path beads, and direct observation. Outputs are config changes, formula updates, prompt improvements, and beads dispatched to polecats. Principle: minimize gastown source changes — divergence belongs in gc-toolkit (which is exactly why we vendored).
