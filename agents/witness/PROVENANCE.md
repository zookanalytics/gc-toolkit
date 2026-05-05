# Agent: witness

**Status:** vendored
**Source:** `rigs/gascity/examples/gastown/packs/gastown/agents/witness/` @ gascity `669586546a`
**Vendored at:** 2026-05-05
**Drift:** clean

## Goals

Per-rig work-health monitor. Runs `mol-witness-patrol` to detect orphaned wisps, stalled work, missing-bead-owner heuristics. Files warrants when work is degenerating in ways the deacon should investigate. Persistent per rig.

## Local changes

None.

## Notes

Rig-scoped, persistent. Known issues (track in memory):
- Idle-stall after pour despite formula fix (`project_gascity_witness_idle_stall`) — recurring, nudge to re-engage.
- Pour/burn race produces transient "no in_progress wisp" benign (`feedback_witness_wisp_pour_burn_race`).
- CWD blind spot when run via `.gc/agents/<rig>/witness` resolves to city not rig — pass `--rig=<rig>` (`project_witness_rig_scope_bug`, gc-7hi0o).
