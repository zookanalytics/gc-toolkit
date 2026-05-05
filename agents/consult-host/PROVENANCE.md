# Agent: consult-host

**Status:** native
**Source:** N/A (gc-toolkit-original)
**Drift:** N/A

## Goals

Short-lived session whose only job is to host the overseer's conversation about a single consult bead. Spawned by concierge after the overseer engages a specific consult. Pool-managed (`min_active_sessions = 0`, `max_active_sessions = 10`); each instance dies when the consult is resolved.

## Why we built this

A single concierge can't simultaneously host many parallel consult conversations without context bleed. Hosting a consult is a focused, bead-grounded conversation — one host per bead keeps each conversation clean.

## Notes

City-scoped, ephemeral. `work_dir = ".gc/agents/consult-host/{{.AgentBase}}"` per-instance. Hooked via the consult bead the alias names.
