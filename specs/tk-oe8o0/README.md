---
name: Personas model — landing record (tk-oe8o0)
description: Work record for adopting docs/personas.md — the design-session rationale behind the persona/agent model, what landed where, and what was deferred. The lean published doc lives in docs/personas.md; this preserves the fuller reasoning.
---

# Personas model — landing record

This directory is the historical record for **tk-oe8o0**, which adopted the
persona/agent model as a central doc. The authoritative, lean statement is
[`docs/personas.md`](../../docs/personas.md); this record preserves the fuller
design-session rationale and the prior-art that the model draws on.

## Provenance

- **Design session:** mechanik-thread, 2026-06-13. The full doc draft and the
  architect example were converged there.
- **Status:** operator-blessed 2026-06-13; the prior HELD was lifted. The doc
  was landed verbatim as `docs/personas.md`.
- **Builds on:** the shipped bead-universe layer (bead-host / proactive agents,
  `mol-first-reaction`, `gc-attention.sh`).
- **Prior art:** five surveys, persisted provenance-stamped under
  [`research/prior-art.md`](research/prior-art.md) so adopted patterns stay
  auditable.

## The model (lean) — design rationale

The published doc is the lean form. The reasoning that produced it:

- **A persona IS a skill.** "Take on a persona" = load the skill.
  Framework-agnostic.
- **A persona = tight always-on IDENTITY + advisory OWNS + PROCESSES**, each a
  skill. References/knows fold INTO the process-skills (self-contained). No
  tiering by default; private/inline process only when required.
- **Identity is portable**; owns/knows resolve per deployment rig.
- **An AGENT = a persona instantiated as a standing/addressable instance** —
  earned only to GATE work or PATROL continuously; else transient load.
- **Curate skills per consumer (NOT global):** a persona's process-skills ride
  with the persona; only broadly-shared methods go top-level; a plain polecat
  stays minimal. (Avoids skill-bloat on simple workers.)
- **Three layers:** (1) persona = the skill; (2) distribution = a generator
  renders the canonical persona into each framework's skill location + extracts
  process-skills (only for >1 target); (3) Gas City orchestration =
  persona↔bead binding, rig-relative owns/knows, the `gc.persona` stamp, and the
  first-pass triage.

## Landing decisions

- **Adopted verbatim** as `docs/personas.md` (with the conventional
  `name`/`description` frontmatter the file-structure spec asks of central
  docs).
- **Discoverability:** the root `README.md` "Docs" list now points at
  `docs/personas.md`, per the file-structure adoption guidance (update the
  discoverability surface in the same PR).
- **Mechanics deferred.** The doc keeps a `## Mechanics (deferred)` stub. Filling
  it is a separate follow-up that must run a latest-knowledge verification pass
  (claude-code-guide / current Claude Code docs) covering skill load paths (flat
  vs. nested), subagent skill consumption, persona-process scoping, and the
  assume-persona entry point. It was deliberately NOT filled here.

## Cross-cutting takeaway from the prior art

The identity/owns split is validated prior art (CrewAI, MetaGPT). Treating
"owns" as a maintained-artifact contract is novel — no surveyed system has it.
The knows-inclusion idea is borrowable from Kiro/Cursor. And persona-adoption ==
skill-loading is the load-bearing observation: it is *why* a persona is a skill.
See [`research/prior-art.md`](research/prior-art.md) for the sourced surveys.
