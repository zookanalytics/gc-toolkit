# Agent: deacon

**Status:** vendored
**Source:** `rigs/gascity/examples/gastown/packs/gastown/agents/deacon/` @ gascity `669586546a`
**Vendored at:** 2026-05-05
**Drift:** clean

## Goals

City-wide patrol executor and judgment surface. Cycles through patrol wisps (`mol-deacon-patrol`) to detect ghost sessions, dolt zombies, /tmp inode leaks, wisp orphans, and other systemic issues. Files warrants when the situation requires structural intervention. Persistent — runs continuously across restarts.

## Local changes

None.

## Notes

City-scoped, persistent. Watched by `boot`. Pours `mol-deacon-patrol` on its own schedule. Should never end a turn idle (per `feedback_deacon_no_end_after_activate`) — keep cycling or call `gc runtime request-restart`.
