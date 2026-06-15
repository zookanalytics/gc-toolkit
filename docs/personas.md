---
name: Personas
description: How gc-toolkit gives an LLM a role — a persona is a skill (identity plus process-skills), how a persona differs from a standing agent, and the three layers (persona, distribution, Gas City orchestration).
---

# Personas (gc-toolkit)

> How we give an LLM a role. The core is framework-agnostic; Gas City wraps it
> (last section). The mechanics — skill paths, subagent wiring, scoping — are now
> settled (verified against current Claude Code docs) and proven by the first
> persona, the **architect**; see "Mechanics" at the end.

## A persona is a skill
Making an LLM *take on a persona* is **loading a skill into its context** —
the universally-adopted skill mechanism already is the persona-loader. A persona is:

- **Identity** — a tight, always-on stance ("who I am," what I optimize for).
  Always loaded; if it's too big to always carry, tighten it.
- **Owns** — advisory: the project-relative artifacts it keeps current
  (e.g. docs/architecture.md). Nothing enforces it; the persona honors it.
  Promoted to first-class metadata only when a real need appears.
- **Processes** — what it can *do*, each a **skill** of its own
  (architect-review), referenced by name. Each process-skill is
  self-contained: it bundles its own reference material and declares the files
  it reads. There is no separate "references" or "knows" facet — those live
  inside the skills that use them.

No tiering by default — every process is a skill. Add a private/inline process
only when something genuinely can't stand alone.

The persona-skill *is* the identity plus an index of its method-skills.

## Identity travels; owns/knows resolve per project
The identity is portable (architect works in any repo). What it owns and
reads is project-relative — the architect maintains *this* repo's
docs/architecture.md, whichever repo it's loaded in.

## Persona vs. agent
An **agent** is a persona *instantiated as a standing, addressable instance.*
Most persona use is transient — load, work, release. A persona earns a standing
agent only when it must **gate** work or **patrol continuously**; otherwise load
transiently. (In Gas City you bring attention to a *bead*, not an agent, so
"address the architect" mostly dissolves.)

## Keep skills curated, not global
Every process being a skill does NOT mean every skill loads into every agent —
that would bloat a plain worker with methods it never uses. So:
- a persona's process-skills **ride with the persona**, loaded when engaged;
- only **broadly-shared** methods (red-green) are top-level/always-discoverable;
- a plain worker carries only its minimal set.

## Three layers
One persona, seen at three levels. Only the first always exists; the other two are
*concerns* that appear as you scale, each independent of how it's wired.

1. **Persona — the definition.** The portable content: who the role is and how it
   works. Framework-agnostic. This is the layer that always exists.
2. **Distribution — rendering.** Expressing that one canonical definition wherever
   a given tool expects to find it. A concern only when you target more than one
   framework; with a single target it collapses to "author it where your tool
   reads it."
3. **Orchestration — binding to work.** Deciding which persona a given piece of
   work needs, resolving what it owns and reads *in the project at hand*, and
   recording the choice. The principle is framework-independent; in Gas City it
   takes the concrete form of a persona↔bead binding plus a first-pass triage that
   picks a persona from its description.

## Example
    ---
    name: architect
    description: Use when a change touches system structure, or a PRD needs an
      architectural review.
    ---
    # Architect
    ## Who I am
    I hold the shape of the system — boundaries, coherence, cost of future change.
    ## What I maintain
    - docs/architecture.md   (advisory)
    ## What I do
    - review -> the architect-review skill
    - design -> the architect-design skill

This sketch is now **built** — the architect is the first real persona: the
identity above lives in `skills/architect/`, its methods in `architect-design` /
`architect-review`, and its standing form in the `architect` agent. The prior art
it was grounded in is in [`specs/tk-ae96t.1/`](../specs/tk-ae96t.1/README.md).

## Mechanics (settled)
Settled against the current Claude Code docs (tk-ohrlc, verified 2026-06-14) and
then **proven by building the architect** (tk-ae96t.1). Full findings:
[`specs/tk-ohrlc/research/mechanics.md`](../specs/tk-ohrlc/research/mechanics.md).

- **Where skills load from.** A skill is a `<name>/SKILL.md` *directory*. Discovery
  is flat *within* one skills directory (no nested grouping) but spans *many* of
  them — so a persona's skills are grouped by **naming convention** (`architect`,
  `architect-design`, `architect-review`), not a directory tree.
- **How a standing instance carries its methods.** Its process-skills load into
  *its* context and no one else's. The chosen model is **Path A** — process-skills
  ride with the persona, plain workers stay minimal — over a per-persona plugin
  (overweight) or hiding every skill behind a manual command (too manual).
- **Scoping — the load-bearing bit.** "Ride with the persona, not global" needs a
  real mechanism. In Gas City the native one is **agent-local skills**: skills under
  `agents/<persona>/skills/` materialize only into that agent's session (the
  city-wide set ∪ the agent's own; agent-local wins). That keeps a persona's methods
  out of every plain worker's context *by construction* — cleaner than the
  Claude-native combo the findings first described (a `skills:` preload field, since
  deprecated in Gas City, plus a `skillOverrides` trim Gas City doesn't author). The
  portable **identity** skill stays city-wide on purpose: it's the "wear the
  persona" entry point any session can load.
- **Assuming a persona.** Transiently, load the identity skill (`/architect`) and
  it rides the session — the lens, not the methods: the `architect-design` /
  `architect-review` skills are agent-local, so a transient wearer reasons in
  those modes directly rather than loading them. As a standing instance, an agent
  definition *is* the persona — it wears the identity and has its process-skills
  materialized.

> The build added one lesson worth keeping: a framework may offer a *better* native
> scoping primitive than the generic mechanics suggest. Prefer it, and record the
> swap — here, agent-local skills replaced the preload-plus-overrides combo.
