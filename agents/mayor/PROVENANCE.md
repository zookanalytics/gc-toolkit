# Agent: mayor

**Status:** vendored
**Source:** `rigs/gascity/examples/gastown/packs/gastown/agents/mayor/` @ gascity `669586546a`
**Vendored at:** 2026-05-05
**Drift:** clean

## Goals

Global coordinator for the city. Receives mail, surfaces friction from coordination work, dispatches polecats, fields requests from the operator (human) and other agents. Persistent. Opinions about how things should work get filtered through the mayor before becoming structural decisions handed to mechanik.

## Local changes

None.

## Notes

City-scoped, persistent. Single mayor per city. Inbound mail address is `gc-toolkit.mayor` (post-Lane C; was `gastown.mayor` pre-cutover). Concierge agent (native) routes citizen mail; mayor handles the actual coordination decisions.
