---
name: Personas epic — archived design record (tk-ae96t)
description: The archived design record of the personas-as-skill epic (tk-ae96t), concluded 2026-09-18 without shipping. Preserves the persona/agent model, the prior-art and mechanics research, and the architect persona's inert skill and formula definitions, for reference. Not implemented and not authoritative.
---

# Personas epic — archived design record (tk-ae96t)

> This is the archived design record of the personas-as-skill epic (**tk-ae96t**),
> concluded 2026-09-18 without shipping. It is preserved for reference. Nothing
> here is implemented, live in the tree, or authoritative.

The epic explored giving an LLM a role as a loadable skill. A persona is an
identity skill plus method-skills, each method invocable on its own; a persona
earns a standing, addressable agent only when work must be gated or patrolled
continuously, and otherwise stays a transient load. The architect is the persona
the epic built to test the model: an identity skill, a design method, and a
review method.

## Forward direction

The direction this leaves in place is an architect-type role that engages through
reviews, factored out incrementally. The review method is the entry point, run as
a step against a change rather than by a resident agent, and a standing architect
agent is taken up later only if continuous drift patrol or structural gating turns
out to be needed.

## What is here

- `personas.md` — the persona/agent model: a persona is a skill, the identity and
  methods split, persona versus agent, and the three layers (persona,
  distribution, orchestration).
- `tk-ae96t.1/` — the build record for the first architect persona, with its
  prior-art survey under `research/`.
- `tk-oe8o0/` — the landing record for the persona model, with five
  persona-system surveys under `research/`.
- `tk-ohrlc/` — the mechanics investigation (skill load paths, subagent skill
  loading, persona-process scoping, the assume-persona entry point) under
  `research/`.
- `reference/` — the architect persona's concrete expression, kept inert: the
  three skill bodies (`architect.skill.md`, `architect-design.skill.md`,
  `architect-review.skill.md`) and the review formula
  (`mol-architect-review.toml.txt`). They are renamed away from `SKILL.md` and
  `.toml` so no loader picks them up. They describe the persona; they define
  nothing live.

## Reading the recovered files

These files are recovered as written when the epic was live, from PR #166 (the
final iteration), so their internal links point at the paths the repo carried
then. The model doc they call `docs/personas.md` is `personas.md` here; the
skills and formula they name under `skills/` and `formulas/` are the inert copies
under `reference/`.
