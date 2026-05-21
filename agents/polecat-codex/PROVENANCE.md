# Agent: polecat-codex

**Status:** native (variant of polecat backed by a different provider)
**Source:** N/A (gc-toolkit-original; mirrors `polecat` shape)
**Drift:** N/A

## Goals

Pool of polecat workers backed by the Codex CLI provider (`provider = "codex"`) instead of the default Claude provider. Distinct `work_dir` keeps codex worktrees out of the default polecats/ tree. Otherwise mirrors the imported gastown `polecat` shape (rig-scoped, ephemeral, pre-start `worktree-setup.sh`).

The prompt is shared with gastown's polecat by reference (`prompt_template` points at the materialized gastown template), and `inject_fragments` mirrors the polecat patch in `pack.toml`. This keeps the two pools behaviourally aligned automatically — guidance added to the gastown polecat prompt (or to the gc-toolkit polecat patch) flows to both pools without a copy-paste step.

## Why we built this

Provider diversity. Some bead workloads benefit from Codex over Claude; rather than fork the polecat agent file, we ship a sibling pool with the provider switched and let the operator route work to whichever pool fits.

## Notes

Rig-scoped. Currently inert at city scope per the historical staging note (`project_polecat_codex_staged`) — was waiting on a gastown overlay that's now superseded by Lane C. Should activate cleanly post-cutover; verify in smoke test.
