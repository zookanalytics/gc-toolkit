# Agent: polecat

**Status:** vendored
**Source:** `rigs/gascity/examples/gastown/packs/gastown/agents/polecat/` @ gascity `669586546a`
**Vendored at:** 2026-05-05
**Drift:** clean

## Goals

Transient worker agent. Spawned by the mayor (or by orders/slings) to execute a single bead's worth of work — research, code, drafts, syntheses — then exits. Each polecat gets its own git worktree. Pool-managed; multiple can run in parallel.

## Local changes

None.

## Notes

Rig-scoped. Pool sized via formula. Names drawn from `assets/namepools/minerals.txt`. Polecats execute; they don't decide architecture — see `feedback_polecats_do_research`. Native variants (`polecat-codex`) live alongside for non-Claude providers.
