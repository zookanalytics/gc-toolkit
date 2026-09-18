---
name: First architect persona — build record (tk-ae96t.1)
description: Work record for tk-ae96t.1 — building the FIRST gc-toolkit persona (the architect) on Path A, grounded in a prior-art survey (BMAD "Winston", Roo Code Architect mode, wshobson/agents, Martin Fowler). Records what landed where, the key wiring decision (agent-local skills realize Path A natively, replacing the deprecated skills: preload + un-authored skillOverrides), and that this PR supersedes the held #123 (docs/personas.md) and #130 (mechanics findings). SUPERSEDED by tk-ae96t.2 (PR#166): the standing `architect` agent + agent-local method-skills were dropped for top-level city-wide method-skills + a proof-point mol (mol-architect-review); this file is retained as the Path A historical build record (its agents/architect/… and pack.toml paths are pre-rework and no longer in the tree).
---

# First architect persona — build record

> **⚠ Superseded by tk-ae96t.2 (PR #166).** This file is the original **Path A**
> build record. Path A shipped a **standing `architect` agent** with **agent-local**
> method-skills; the tk-ae96t.2 rework **dropped that shape**. What actually landed:
>
> - `skills/architect/SKILL.md` — identity skill, city-wide (kept from Path A)
> - `skills/architect-design/SKILL.md` — method-skill, **top-level** city-wide
> - `skills/architect-review/SKILL.md` — method-skill, **top-level** city-wide
> - `formulas/mol-architect-review.toml` — the proof-point mol (runs `architect-review`
>   as a step, with no standing agent)
> - **no** `agents/architect/` standing agent and **no** `pack.toml` named session
>
> The current persona contract is [`docs/personas.md`](../../docs/personas.md).
> **Everything below is the Path A record, kept for provenance — its
> `agents/architect/…` and `pack.toml` paths are pre-rework and are no longer in the
> tree.**

This directory is the bead-local record for **tk-ae96t.1**, which builds the
**first gc-toolkit persona — the architect** — on the persona-as-skill model
(`docs/personas.md`). It is the **post-implementation revisit** of that model: the
first build both *uses* the settled mechanics and *sharpens* the doc with what the
build learned. This first persona **sets the convention** every later persona
follows (directory layout, identity-skill + agent-local process-skills, the
persona-vs-agent distinction).

## Provenance

- **Parent epic:** `tk-ae96t` — the personas initiative. Operator decision
  **Path A** (2026-06-14): persona = subagent + process-skills that ride with the
  persona + a trim that keeps them out of plain workers; plugin (Path B) rejected
  as overweight; persona CONTENT kept framework-neutral (the Layer-2 distribution
  generator is deferred); cross-rig sharing is rig-scoped via Gas City import
  (Layer 3, NOT this bead).
- **Grounded in:** a prior-art survey under [`research/`](research/architect-prior-art.md)
  — BMAD-METHOD's Architect ("Winston"), Roo Code's Architect mode,
  wshobson/agents' backend-architect + ship-mate/architect, and Martin Fowler's
  "Who Needs an Architect?" — distilled into the seven traits the persona is built
  from. Mirrors how `tk-oe8o0` persisted its persona-system surveys.
- **Built on the settled mechanics:** [`specs/tk-ohrlc/research/mechanics.md`](../tk-ohrlc/research/mechanics.md)
  (the four "Mechanics" questions, verified against current Claude Code docs).

## What landed where (Path A — pre-rework)

> **Historical.** The `agents/architect/…` and `pack.toml` entries below are the
> **original Path A** shape. tk-ae96t.2 moved both method-skills to top-level
> `skills/`, removed the standing agent and its `pack.toml` session, and added
> `mol-architect-review`. The shape that actually shipped is the bulleted list in
> the banner at the top of this file.

**The persona (framework-neutral content; Claude/Gas-City specifics only in
packaging):**

- `skills/architect/SKILL.md` — the **identity** skill (city-wide). The portable
  "wear the architect" stance; declares advisory owns `docs/architecture.md`;
  indexes its methods.
- `agents/architect/skills/architect-design/SKILL.md` — **process-skill**
  (agent-local): settle structure — elicit first, pin only the invariants, record
  decisions + rationale.
- `agents/architect/skills/architect-review/SKILL.md` — **process-skill**
  (agent-local): assess a change against the system's shape; hunt drift.
- `agents/architect/{agent.toml,prompt.template.md,PROVENANCE.md}` — the
  **standing-agent** form (on_demand, city-scoped, dormant by default); wears the
  identity and has the process-skills materialized into its session only.
- `pack.toml` — registers the `architect` named session (`on_demand`).

**The model doc (this revisit):**

- `docs/personas.md` — "Mechanics (deferred)" filled from tk-ohrlc + the build;
  "Three layers" reframed to be about the concept, not specific paths (addresses
  the operator's inline comment on #123); the Example connected to the now-built
  architect.

## The key wiring decision (Path A, realized natively)

The mechanics write-up (tk-ohrlc) answered the scoping question against
**Claude-native** primitives: keep process-skills as normal project skills,
`skills:`-preload them into the persona-subagent, and trim them from plain workers
with `skillOverrides`. Building it surfaced that **Gas City has a better native
primitive**, so the realization diverges deliberately:

- **`skills:` preload is unavailable** — the `skills =` agent field is a deprecated
  tombstone (accepted but ignored; hard parse error in v0.16).
- **`skillOverrides` is not authored by Gas City** — it has no mechanism to write
  it into a session's `.claude/settings`.
- **Agent-local skills are the native answer.** Skills under
  `agents/<persona>/skills/` materialize *only* into that agent's session (the
  city-wide set ∪ the agent's own; agent-local wins on collision). So the
  architect's methods ride with it and stay out of every plain worker's context
  **by construction** — no preload field, no overrides trim needed. The portable
  **identity** skill stays city-wide on purpose (the transient "assume the
  persona" entry point).

This is exactly the kind of deviation the post-implementation revisit exists to
catch, and it is folded back into `docs/personas.md` "Mechanics".

> **A trade-off left for the operator:** the city-wide identity skill's description
> sits in plain workers' context (one line — the cost of the "assume the persona"
> affordance). If you'd rather hide even that, make the identity agent-local too,
> or add a `skillOverrides` entry (which today means a committed/local
> `.claude/settings` step, since Gas City doesn't author it).

## Supersedes #123 and #130

The operator asked for ONE complete PR (research + docs + first implementation
together). Neither held PR is on `main`; this PR **re-includes both** and adds the
architect build:

- **#123** (`polecat/tk-oe8o0`) — `docs/personas.md` (+ its updates here), the
  README personas line, and the persona-system prior-art surveys under
  `specs/tk-oe8o0/`.
- **#130** (`polecat/tk-ohrlc`) — the mechanics findings under `specs/tk-ohrlc/`.

Close #123 and #130 as superseded when this lands.

## Status

- **Build:** complete (2026-06-15). **Held** for operator review — this is a strong
  first draft; the operator ratifies the convention before later personas follow it.
- **Follow-ups (out of scope here):** rig-scoped architects across rigs via Gas City
  import (Layer 3 — watch the importer phantom-agent sharp edge); the autonomous
  drift-patrol loop + architect-bead routing; the Layer-2 distribution generator;
  later personas (PM, …); `gc.persona` triage/stamp. `docs/architecture.md` is
  intentionally not created here — the architect authors it when it first designs.
