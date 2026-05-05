# Agent: concierge

**Status:** native
**Source:** N/A (gc-toolkit-original)
**Drift:** N/A

## Goals

City-level surface for consults. When specialists file a consult bead because their work needs the overseer's judgment, the concierge is the surface that makes the bead reach the overseer (push notifications), triages what's open, and routes the conversation to the right consult-host once the overseer engages.

## Why we built this

Consult beads needed a single human-facing surface so the operator (overseer) doesn't have to discover them by polling. Concierge does that translation: from "consult bead exists" to "overseer is notified and a conversation is hosted."

## Notes

City-scoped, persistent. Spawns `consult-host` instances per active conversation. Uses push notifications for time-sensitive consults.
