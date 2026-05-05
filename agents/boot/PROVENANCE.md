# Agent: boot

**Status:** vendored
**Source:** `rigs/gascity/examples/gastown/packs/gastown/agents/boot/` @ gascity `669586546a`
**Vendored at:** 2026-05-05
**Drift:** clean

## Goals

Watchdog for the deacon. Spawned fresh by the controller on each tick (`wake_mode = "fresh"`) to answer one question: **is the deacon stuck?** The controller knows whether the deacon process is alive; boot is the LLM that judges whether the deacon is *working* using domain knowledge of wisps, patrols, and mail state. Boot is stateless — narrow scope makes restarts cheap.

## Local changes

None.

## Notes

City-scoped, `max_active_sessions = 1`. Verdicts: do nothing / nudge / file warrant. Never restarts the deacon itself — that's the controller's job.
