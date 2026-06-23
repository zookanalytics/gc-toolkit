---
name: Personas
description: How gc-toolkit gives an LLM a role — a persona is a skill (an identity plus method-skills), how a persona differs from a standing agent, and the three layers (persona, distribution, orchestration).
---

# Personas (gc-toolkit)

> How we give an LLM a role. The core is framework-agnostic; Gas City wraps it
> (last section). The first persona built on this model is the **architect**.

## A persona is a skill
Making an LLM *take on a persona* is **loading a skill into its context** — the
skill mechanism already is the persona-loader. A persona is:

- **Identity** — a tight, always-on stance ("who I am," what I optimize for).
  Always loaded; if it's too big to always carry, tighten it.
- **Owns** — advisory: the project-relative artifacts it keeps current
  (e.g. `docs/architecture.md`). Nothing enforces it; the persona honors it.
- **Methods** — what it can *do*, each a **skill** of its own (e.g.
  `architect-review`), referenced by name. Each method-skill is self-contained:
  it bundles its own reference material and declares the files it reads. There is
  no separate "references" facet — that lives inside the skills that use it.

No tiering by default — every method is a skill. Add a private/inline method
only when something genuinely can't stand alone.

The persona-skill *is* the identity plus an index of its method-skills.

## Identity travels; owns resolve per project
The identity is portable (the architect works in any repo). What it owns and
reads is project-relative — the architect maintains *this* repo's
`docs/architecture.md`, whichever repo it's loaded in.

## A method is an ordinary skill
A persona's method-skills live in the generic skills directory like any other
skill — and that is what lets them be used wherever the work is:

- a **mol step** can invoke a method by name (e.g. `architect-review` as a step);
- a session that has worn the persona can engage them;
- a standing agent for the persona, if one exists, uses them too.

Skills are disclosed progressively: a method-skill in the generic directory is
*discoverable* everywhere (its name and one-line description) but only *loads*
its body when invoked. So a city-wide method does not bloat a plain worker's
context — the goal is to make a method available to whatever runs it without
forcing it into every session.

## Persona vs. agent
An **agent** is a persona *instantiated as a standing, addressable instance.*
Most persona use is transient or step-scoped — wear the identity or invoke a
method, work, release. A persona earns a standing agent only when it must
**gate** work or **patrol continuously**; otherwise there is nothing to keep
resident. (The architect has no standing agent today — its review method is
proven first as a mol step; see the last section.)

## Three layers
One persona, seen at three levels. Only the first always exists; the other two
are *concerns* that appear as you scale, each independent of how it's wired.

1. **Persona — the definition.** The portable content: who the role is and how
   it works. Framework-agnostic. This is the layer that always exists.
2. **Distribution — rendering.** Expressing that one canonical definition
   wherever a given tool expects to find it.
3. **Orchestration — binding to work.** Deciding which persona a given piece of
   work needs, resolving what it owns and reads *in the project at hand*, and
   recording the choice. The principle is framework-independent.

## Persona structure
A persona is a set of files in conventional locations. What goes where, and what
each part does:

| Path | What it is | What it does |
|------|------------|--------------|
| `skills/<persona>/SKILL.md` | the **identity** skill | the always-on stance; the entry point any session wears (`/<persona>`). City-wide. |
| `skills/<persona>-<method>/SKILL.md` | a **method-skill** | one thing the persona does (e.g. `architect-design`, `architect-review`). Invocable as a mol step or once the identity is worn. City-wide. |
| `docs/architecture.md` (and the like) | an **owned artifact** | a project-relative doc the persona keeps current. Advisory; the persona authors it when it first needs one. |
| `agents/<persona>/` + a `pack.toml` `[[named_session]]` | a **standing agent** | optional — only when the role must patrol or gate continuously. |

Two conventions make this work:

- **Grouping is by name, not directory.** Skill discovery is flat *within* one
  skills directory but spans *many*, so a persona's skills are grouped by naming
  convention (`architect`, `architect-design`, `architect-review`), not a nested
  tree.
- **The identity is always-on and tight; the methods load on demand.** That is
  the persona/worker split — a plain worker carries no method it never uses, yet
  any worker can invoke one when a step calls for it.

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

## In Gas City: the architect
The architect is the first persona built on this model:

- its **identity** is `skills/architect/` — city-wide, so any session can wear it
  (`/architect`);
- its **methods** are `skills/architect-design/` and `skills/architect-review/` —
  ordinary city-wide skills, so a mol step can run one directly;
- its first proof point is **`mol-architect-review`** — a formula whose step
  engages `architect-review`, exercising the method with no standing agent in the
  picture.

A standing `architect` agent (for drift patrol / structural gating) is a later
step, taken only if those continuous jobs are actually needed. The prior art the
persona was grounded in is in [`specs/tk-ae96t.1/`](../specs/tk-ae96t.1/README.md).
