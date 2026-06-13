---
name: Personas
description: How gc-toolkit gives an LLM a role — a persona is a skill (identity plus process-skills), how a persona differs from a standing agent, and the three layers (persona, distribution, Gas City orchestration).
---

# Personas (gc-toolkit)

> How we give an LLM a role. The core is framework-agnostic; Gas City wraps it
> (last section). Mechanics — skill paths, subagent wiring, scoping — are a
> follow-up verified against current Claude Code docs, not assumed.

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
1. **Persona = the skill.** The content; framework-agnostic.
2. **Distribution = a generator.** Renders one canonical persona into each
   framework's skill location (.claude/skills/, OpenHands .agents/skills/, ...)
   and extracts invokable process-skills. Needed only for >1 target.
3. **Gas City = orchestration.** Which persona onto which bead, owns/knows
   resolved per rig, the gc.persona stamp, and the first-pass triage that reads
   persona descriptions to assign one to a bare bead.

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

## Mechanics (deferred — verify against current docs)
To fill next, against the latest Claude Code / skills docs rather than memory:
where skills load from (flat vs. nested), how subagents consume skills, the
persona-process scoping mechanism, and the assume-persona entry point.
