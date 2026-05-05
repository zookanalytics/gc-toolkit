# Agent: refinery

**Status:** vendored
**Source:** `rigs/gascity/examples/gastown/packs/gastown/agents/refinery/` @ gascity `669586546a`
**Vendored at:** 2026-05-05
**Drift:** clean

## Goals

Per-rig merge-queue processor. Runs `mol-refinery-patrol` to take polecat output (branches, PRs, drafts) and integrate it into the rig's main branch. Handles merge conflicts, gates on review, runs CI checks. On-demand named session — wakes up when there's a merge to process, sleeps otherwise.

## Local changes

None.

## Notes

Rig-scoped, on-demand. Default merge strategy can be overridden per rig (e.g., signal-loom uses `GC_DEFAULT_MERGE_STRATEGY=mr` per `city.toml [[rigs.overrides]]`). Worktree setup uses `assets/scripts/worktree-setup.sh`; needs `[session] setup_timeout = "60s"` to not get killed (per `project_setup_timeout_60s`).
