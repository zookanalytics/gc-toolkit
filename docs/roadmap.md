# Roadmap

This document captures what gc-toolkit is *for* and where it's going. It is
intentionally light on implementation detail — those live in the individual
feature docs and beads. Expect this file to change as we learn what works.

## Purpose

gc-toolkit adds the roles, formulas, and workflows that shape **how a Gas
City decides what to build, and how it communicates that work back to the
humans reviewing it**, as a layer on top of gastown's production crew.

gastown is excellent at execution. What gastown does not yet opinionate is
the front of the pipeline (how ideas become plans) or the back of the
pipeline (how completed work gets presented in a form a human can absorb
in minutes). gc-toolkit is where we build both.

## What We Optimize For

**The scarce resource in AI-driven development is human time and attention,
not AI compute.** AI cycles are cheap; we should spend them liberally where
they save human cycles later. Every design decision in gc-toolkit should
pass that test.

This cuts two ways, and both sides must be strong:

1. **How the AI does the work.** Small composable pieces, parallel reviews,
   asynchronous research, pre-prepped context. When the human returns to a
   thread, the AI should already be informed — not starting from zero.
2. **How the AI communicates results to humans.** A giant dump of prose and
   diffs is not consumption-ready. Humans skim, look for flags, and defer
   on the rest. Work must be presented in a form a human can actually
   absorb in minutes.

An AI that generates excellent work but dumps it unfiltered on the human
wastes the gains. An AI that presents well but generates shallow work is
not worth the ceremony.

## Core Principles

1. **Human time is expensive; AI time is cheap.** Trade AI cycles for human
   cycles aggressively. If running five parallel agents saves one human
   back-and-forth, run the five.
2. **Eliminate wait states.** When a human files an idea and walks away,
   the system should be working in the background so the next conversation
   starts informed. Fewest possible human-AI round trips before a decision
   can be made.
3. **Continuous improvement; stagnation is not acceptable.** Structural
   problems must end in visible learning and improvement, not just a point
   fix. A routine bug fix with no broader payoff is fine. A process failure
   that leaves no lesson behind is not. Mechanik is the role that holds
   this bar.
4. **Durable state lives in durable locations.** Live knowledge that needs
   to reflect current reality has exactly one canonical home. Audit trails
   and historical records live elsewhere (see *Durable Locations* below).

## Practices

Practices are how we execute the principles. We are more confident about
some than others. The marker next to each indicates maturity:

- **[direction]** — we believe this is right but haven't built it yet
- **[explore]** — we have a hunch but need to learn more before committing

**[direction] Parallel AI review.** When a decision benefits from multiple
viewpoints, fan out to multiple agents rather than serializing. The cost is
small and the signal is better than any single agent produces.

**[direction] Asynchronous pre-prep.** When an idea is filed, the system
starts working immediately — quick follow-up questions, research threads,
candidate approaches — so the next human touchpoint starts informed rather
than from zero.

**[explore] High-bandwidth communication at boundaries.** At the end of a
meaningful chunk of work, the AI presents back to the human in a form
richer than a text summary. What that form is — a walkthrough, an
interactive view, something else — is open. The principle is that a human
should be able to understand a completed chunk in minutes, through a
channel that carries more bits per second than prose.

**[explore] Lens-based review.** Partition a change by concern
(architecture, UX, data, security, tests, …) and report per lens whether
anything changed and what to look at. The ideal signal is "no change in
this lens" — the human skips it entirely. We don't yet know the canonical
set of lenses or how to generate the per-lens view reliably. Needs digging.

The `[explore]` items will be fleshed out through ongoing conversation
between the human and mechanik, not by committing speculative detail here.
When a practice matures, it graduates to `[direction]` or lands in its
own design doc.

Other practices will emerge as we build. We will not lock in a practice
before we are confident we understand what it replaces.

## Durable Locations

A **durable location** is a single canonical place that always reflects the
*current* state of some concern. Think of a corporate strategy doc: if the
strategy changes, the doc changes; there is one place to look to know what
the strategy *is today*. Previous versions matter only where directly
relevant to the current state.

Durable locations are not audit trails. The history of *why* a decision was
made lives in the bead that made it and in git history. The durable
location reflects *what is true now*. These are different kinds of
knowledge, and we do not conflate them.

Concretely: if an architectural decision is made in a bead, the bead is the
historical record of why. The durable location is `docs/architecture.md`,
which the architect role is responsible for keeping accurate. A reader
looking at `docs/architecture.md` should see today's architecture, not a
chronological log of everything that was ever considered.

### Canonical durable locations

The pack ships sane defaults. Rigs can override each location via pack
variables when their conventions differ — prescriptive but not forceful.

| Concern | Default path | Reflects |
|---------|--------------|----------|
| Architecture | `docs/architecture.md` | The architecture of the rig as it exists right now. |
| UX | `docs/ux.md` | The current UX/design language of the product. |
| Product brief | `docs/product-brief.md` | What the product is, its positioning, and its current goals. |

More locations will be added when a concern meets the bar: *recurring,
durable, better owned in one place than distributed*. We will not add
locations speculatively.

## The Pipeline

```
┌───────┐    ┌───────┐    ┌───────┐    ┌───────────┐
│  Idea │ ─▶ │ Spec  │ ─▶ │ Plan  │ ─▶ │   Beads   │ ─▶ Execute ─▶ Human review
└───────┘    └───────┘    └───────┘    └───────────┘
```

Each stage produces a reviewed artifact before the next begins. Human
involvement happens at strategic checkpoints, not as constant gates.
Architecture decisions thread through every stage and land in
`docs/architecture.md`.

Completed execution does not hand the human raw diffs and prose. It hands
them whatever we decide a high-bandwidth boundary handoff looks like. The
exact shape is one of the things we are building gc-toolkit to figure out.

## Roles

| Role | Scope | Status |
|------|-------|--------|
| **mechanik** | City-level structural engineer. Owns formulas, configs, dispatch patterns, quality gates, prompt engineering. **Primary duty: continuous improvement** — ensures structural problems end in visible learning, not just point fixes. | Shipped |
| **architect** | Planning-phase role. Owns the integrity of `docs/architecture.md`. Flags architecturally significant changes during planning, and again during the review/summary phase. Consulted during idea→plan. | Concept |

More roles will emerge as we discover them. Additions happen when a
responsibility is recurring, city-scoped, and not cleanly owned by any
gastown role.

## First Formulas (Planned)

Unordered, unprioritized, and intentionally small. The idea-to-plan rewrite
is the biggest lever and the most ambitious; everything else is smaller
and subject to change as we learn.

- **Idea-to-plan rewrite.** A replacement for `mol-idea-to-plan` shaped to
  our workflow: stronger pre-planning validation, architect consultation at
  design-fork questions, multi-stage review with real artifacts at each
  step, and architecture.md updates as first-class outputs.
- **Idea pre-prep.** Triggered on bead filing. Runs quick follow-up
  questions, does research, drafts candidate approaches, and attaches the
  findings to the bead so the next human touchpoint starts informed.

Everything else (back-of-pipeline presentation, lens-based review,
high-bandwidth handoff formats) is too under-specified to list yet. We
build the front of the pipeline first, learn what we learn, and let the
shape of the back emerge from real work.

## Operational Rules

Mechanical constraints on how we build. Distinct from the principles
above.

1. **Extend, don't fork.** gc-toolkit is an overlay on gastown. Divergence
   lives in gc-toolkit and overrides gastown via pack include order. We
   do not fork gastown itself.
2. **Observe before prescribing.** Understand the pattern before committing
   to the shape. One-off friction is not a reason to add structure.
3. **The engine must keep running.** Changes roll out incrementally. No
   structural change should require a simultaneous restart of every agent
   in every city that consumes this pack.

## Non-Goals

- **Replace gastown.** The execution crew stays in gastown. We add roles;
  we do not rebuild what gastown already has.
- **Be a dependency-free framework.** gc-toolkit assumes gastown is
  present. It is not a standalone pack.
- **Cross-model review matrices.** We may eventually want parallel reviews
  from different LLM families. That is a future decision; for now,
  parallelism within a single family is the assumption.

## Status

Early. The pack exists, mechanik lives inside it, no formulas have been
written yet. Expect this roadmap to keep changing as we learn.
