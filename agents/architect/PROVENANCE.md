# Agent: architect

**Status:** native
**Source:** N/A (gc-toolkit-original)
**Drift:** N/A

## Goals

The standing-instance form of the **architect persona** — the first persona built
on the persona-as-skill model (`docs/personas.md`). Holds the shape of the system:
boundaries, contracts, who owns shared data, the cost of future change. Patrols for
architectural drift and gates/reviews structural changes. The persona's identity is
the portable `architect` skill; this agent is that persona instantiated as a
continuous, addressable owner — earned only because patrol and gate need one.

## Why we built this

Epic `tk-ae96t` (operator decision Path A, 2026-06-14): give every LLM role a
portable, reusable definition. The architect is the FIRST persona, and it SETS THE
CONVENTION every later persona follows — directory layout, identity-skill +
agent-local process-skills, and the persona-vs-agent distinction. Grounded in a
prior-art survey (BMAD-METHOD "Winston", Roo Code Architect mode, wshobson/agents,
Martin Fowler) — see `specs/tk-ae96t.1/`.

## How the persona is wired (Path A, native to Gas City)

- **Identity** = `skills/architect/SKILL.md` — city-wide, so any session can wear
  the persona transiently (`/architect`). The portable core.
- **Methods** = `agents/architect/skills/architect-design/` and
  `.../architect-review/` — **agent-local** skills. Gas City materializes
  agent-local skills only into this agent's session (city-wide ∪ agent-local;
  agent-local wins on collision). So the methods "ride with the persona" and never
  enter a plain worker's context — the native realization of the mechanics
  write-up's "process-skills ride with the persona; plain workers stay minimal."
- **Why not `skills:` preload + `skillOverrides`** (what tk-ohrlc's mechanics doc
  prescribed against Claude-native primitives): the `skills =` agent field is a
  deprecated tombstone (accepted but ignored; hard parse error in v0.16), and Gas
  City does not author `skillOverrides` into `.claude/settings`. Agent-local
  placement achieves the same scoping more cleanly and is the load-bearing
  mechanism here. This deviation-from-prescription is the kind of finding the
  post-implementation revisit of `docs/personas.md` captures.

## Notes

City-scoped, on_demand, fresh-per-engagement. Dormant by default (`work_query`
returns empty — never auto-spawns for pool demand); materializes on operator
pin/nudge or an architect-design/architect-review bead. Continuity lives in the
artifact it owns (`docs/architecture.md`), not in a warm session — which is why
`wake_mode = "fresh"`.

**Held for operator review** (not auto-merge): this is a strong first draft of the
first persona; the operator ratifies the convention before later personas follow it.

**Follow-ups (out of scope for this bead):**
- Rig-scoped architects across rigs via Gas City import (Layer 3) — the epic's
  "every rig gets an architect." Watch the importer phantom-agent sharp edge
  (memory: skill-scoping-imported-agents).
- The autonomous drift-patrol loop and architect-bead routing/dispatch (formulas).
- `docs/architecture.md` itself is intentionally NOT created here (the persona
  declares it as advisory owns; the architect authors it when it first designs).
