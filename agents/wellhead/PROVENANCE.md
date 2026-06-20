# Agent: wellhead

**Status:** native
**Source:** N/A (gc-toolkit-original)
**Drift:** N/A

## Goals

The resident LLM for a single work bead — Phase 1 of the Bead-Universe
Operating Model (epic tk-q4xaj, design Key Component 1). A wellhead is a
per-bead conversation, created/suspended/resumed on demand, primed with
the bead's context-reachable universe, that the operator lands in to
"engage one piece of work at a time, fully, in the bead that *is* that
piece."

## Why we built this

The model makes the unit of engagement a *bead with a resident LLM*: a
board surfaces beads that need the operator, they pick a row, that bead's
host is created-or-resumed already primed with its universe, they ratify
or redirect in one move, and leave. Between visits the conversation is
suspended, not destroyed — re-opening resumes it.

This config is the binding spine (Phase 1). It is a per-bead session
config (alias = bead id → 1:1 for free) with `wake_mode = resume`
(carry the conversation; the mayor-thread mechanism) and a long
`idle_timeout` (suspend, don't die). The P0 spike (tk-oml75) proved the
resume mechanism carries a conversation across a ~15h cold gap and
recommended A2 (binding is the cheap metadata assembly; no durable-state
store), which this agent + tools/gc-wellhead.sh implement.

## Notes

City-scoped, on-demand, purely interactive. Never claims pool work
(`work_query` returns `[]`) and is never a sling target (`sling_query`
errors) — same never-matching-predicate pattern as mayor-thread. Created
by `tools/gc-wellhead.sh <bead-id>` (spawn-or-resume + durable
dual-link), or by the attention board picker (prefix+b /
`gc-attention.sh open`), a thin front door over the same tool.

The durable bead<->session link is metadata-only (no schema migration):
reverse `hosts_bead` on the session bead is the source of truth, forward
`host_session` on the work bead is an optional cache, and
`gc.session_lineage` is carried from day one. Full contract, schema, and
the operator confirmatory checklist: `specs/tk-husu6/binding-report.md`.
