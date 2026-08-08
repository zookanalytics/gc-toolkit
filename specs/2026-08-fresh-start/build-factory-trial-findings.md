---
name: Findings — build-factory trial (live run)
description: Findings relayed from the live build-factory trial run in the operator's city (brief bead tk-c31ou, conversation-spine brief). Numbering follows the trial session's own findings list; entries here are the ones relayed to the fresh-start branch so far. Verdict lands in gas-city-native.md when the run reaches the decompose judge point.
---

# Findings — build-factory trial (live run)

Run context: existing city, gc-toolkit rig; brief bead `tk-c31ou`
(conversation spine, per [build-factory-trial.md](build-factory-trial.md));
requirements stage bead `tk-ged72`. Numbering is the trial session's own;
gaps in the sequence are findings not yet relayed here.

## F4 — the launch warning is misleading, and the obvious correction is destructive

A warning at launch suggests the factory lacks context it in fact
receives: the **input convoy delivers the brief's referenced material even
though the rendered context does not show it** (observed: the
requirements-planner reading the converse prompt reference it could only
have found via the brief bead). The trap: an operator who trusts the
warning will over-correct, and the obvious correction —
`--var requirements_path=<doc>` — makes the factory **reuse that document
as the requirements artifact and skip the requirements stage entirely**,
silently destroying the trial's first checklist item (requirements
fidelity). The safe way to hand the factory extra context is
`--var context_path=<dir>`.

**Status:** real ergonomic trap, not fatal. **Upstream-PR candidate** (the
warning text should say the input convoy carries bead-referenced context,
and the var docs should distinguish `context_path` from the
stage-skipping `*_path` vars). Candidate recorded here per the
upstream-engagement doctrine; not yet filed.

## F8 — stage handoff is genuinely autonomous (the run's strongest positive so far)

`gc.run-operator` validated inputs, closed `prepare`, drained — and
`gc.requirements-planner` spawned on its own for the next stage, **no
keystroke between stages**. Each stage runs as a separate pooled session.
Two consequences:

- The runbook's "interrupt at decompose costs nothing" claim is
  **validated in practice**, not aspirational — stages are separate
  sessions over durable artifacts, so stopping between them is a clean
  boundary.
- This is the same demand-spawns-session mechanic the conversation spine
  bets on (turns as routed beads), observed working across a five-stage
  chain in production upstream code — indirect but real evidence for
  increment 2's core mechanism.
