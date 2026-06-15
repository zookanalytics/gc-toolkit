---
name: Prior-art survey — architect roles (Roo Code, wshobson/agents, Martin Fowler)
description: Primary-source survey of strong "software architect" role definitions beyond BMAD — Roo Code's built-in Architect mode (plan-before-code, edit-restricted to markdown), wshobson/agents' backend-architect + ship-mate/architect subagents (deep-domain + strict plan-only boundaries), and Martin Fowler's "Who Needs an Architect?" (the canonical human stance). Comparative grounding for the gc-toolkit architect built in tk-ae96t.1.
---

# Prior-art survey — architect roles (beyond BMAD)

Two agentic-framework architect roles plus one canonical human role definition,
to triangulate what a *strong* architect persona looks like across very different
designs. Fetched from **live primary sources** on 2026-06-15 (raw GitHub + the
IEEE PDF), not training memory.

## Provenance

| # | Source | Used for | Verified |
|---|---|---|---|
| 1 | `raw .../RooCodeInc/Roo-Code/main/packages/types/src/mode.ts` (the `DEFAULT_MODES` Architect block; `src/shared/modes.ts` re-imports it) | Roo built-in Architect mode: roleDefinition, whenToUse, edit-restriction, customInstructions | 2026-06-15 |
| 2 | `raw .../wshobson/agents/main/plugins/backend-development/agents/backend-architect.md` | deep-domain architect subagent (philosophy, traits, ADRs, lane/defer) | 2026-06-15 |
| 3 | `raw .../wshobson/agents/main/plugins/ship-mate/agents/architect.md` | plan-only architect with explicit "Strict Boundaries" + escalation triggers | 2026-06-15 |
| 4 | `martinfowler.com/ieeeSoftware/whoNeedsArchitect.pdf` (IEEE Software, Jul/Aug 2003) | the canonical human architect stance | 2026-06-15 |

---

## A. Agentic-framework architect roles

### A1 — Roo Code built-in "🏗️ Architect" mode (source 1)

- **roleDefinition (verbatim):** *"You are Roo, an experienced technical leader
  who is inquisitive and an excellent planner. Your goal is to gather information
  and get context to create a detailed plan … which the user will review and
  approve before they switch into another mode to implement the solution."*
- **whenToUse:** *"when you need to plan, design, or strategize before
  implementation … breaking down complex problems, creating technical
  specifications, designing system architecture, or brainstorming."*
- **Scope by *capability*:** `groups: ["read", ["edit", { fileRegex: "\\.md$" }],
  "mcp"]` — reads anything, but **its write access is Markdown-only.** It is
  *structurally* prevented from editing production code; its output is plans.
- **Method (customInstructions):** gather context → ask clarifying questions →
  decompose into a todo list whose items are *"Clear enough that another mode could
  execute it independently"* → confirm with the user → *"switch to another mode to
  implement."* Explicit rules: prefer actionable lists over long docs; include
  Mermaid where it clarifies; *"Never provide level-of-effort time estimates."*

### A2 — wshobson/agents `backend-architect` (source 2)

- **Identity (verbatim):** *"You are a backend system architect specializing in
  scalable, resilient, and maintainable backend systems and APIs."* Frontmatter:
  *"Use PROACTIVELY when creating new backend services or APIs."*
- **Scope by *lane*, not file-type:** it runs *after* `database-architect`,
  *complements* `cloud-architect`/`security-auditor`/`performance-engineer`, and
  repeatedly **"defers"** out-of-scope concerns to those peers — bounded by role
  boundaries among a fleet of architects.
- **Core philosophy / traits (verbatim selections):** contracts-first API design;
  *"clear service boundaries based on domain-driven design"*; resilience patterns
  *"built in from the start"*; observability as a first-class concern; *"simplicity
  and maintainability over premature optimization"*; *"Documents architectural
  decisions with clear rationale and trade-offs"* — its Response Approach ends in
  *"Service diagrams, API docs, **ADRs**, runbooks."*

### A2′ — wshobson/agents `ship-mate/architect` (source 3) — the restricted planner

- **Identity (verbatim):** *"You are a Senior Technical Architect … You work at
  the strategic level — you define the 'what' and 'how' before any code is
  written."*
- **"Strict Boundaries" (verbatim):** *"NO code implementation … NO direct file
  editing … NO deviations from the project's established patterns without flagging
  them explicitly. One task at a time."* It reads inputs, emits a numbered plan
  (files, steps, data flow, test plan, DoD), then *"Pause for human approval before
  implementation begins."* It defines **escalation triggers** (external contract
  changes, schema changes affecting existing data, auth/security changes, scope
  blow-ups, insufficient info) where it must *"write a clear question to the human
  and halt. Do not guess."*

## B. The canonical human stance — Fowler, "Who Needs an Architect?" (source 4)

- **What architecture IS** (Ralph Johnson, endorsed): *"the expert developers …
  have a shared understanding of the system design. This shared understanding is
  called 'architecture' … how the system is divided into components and how the
  components interact."* Distilled: *"Architecture is about the important stuff.
  Whatever that is."* and, finally, *"things that people perceive as hard to
  change."*
- **What the architect IS:** *"the person (or people) who worries about the
  important stuff."* Fowler contrasts **Architectus Reloadus** (makes all the
  decisions — the bottleneck he critiques) with **Architectus Oryzus** (the model
  he endorses), defined by *"intense collaboration"* — programs with developers,
  joins requirements sessions, explains technical consequences in non-technical
  terms.
- **The defining rule (verbatim):** *"the most important activity of Architectus
  Oryzus is to **mentor the development team, to raise their level** … an
  architect's value is inversely proportional to the number of decisions he or she
  makes."*
- **On irreversibility (verbatim):** *"one of an architect's most important tasks
  is to **remove architecture by finding ways to eliminate irreversibility in
  software designs.**"*

---

## Distilled — what makes a strong architect (sourced)

1. **STANCE — a technical leader/planner who works *before* code, *collaboratively*
   not commandingly.** "Excellent planner … before they switch into another mode to
   implement" (Roo); "define the 'what' and 'how' before any code is written"
   (ship-mate); but the strongest framing is *collaborative* — Fowler's Oryzus
   ("intense collaboration"), explicitly against the decide-everything Reloadus.
   (1, 3, 4)
2. **OWNS "the important stuff" — the hard-to-change, hard-to-reverse decisions.**
   Architecture = "the important stuff … things people perceive as hard to change."
   Operationally: **boundaries and contracts** ("clear service boundaries,"
   "contract-first"). (4, 2)
3. **OWNS the decision *rationale* as a durable artifact.** Strong architects record
   *why*: "clear rationale and trade-offs," "ADRs." Architecture is the team's
   *shared understanding*, so capturing it is core. (2, 4)
4. **METHOD — gather context + ask clarifying questions before planning.** "Do some
   information gathering … ask clarifying questions" (Roo); start from
   business/non-functional requirements (backend-architect); "Read All Inputs"
   (ship-mate). (1, 2, 3)
5. **METHOD — decompose into reviewable, independently-executable steps, then hand
   off.** Plan items "clear enough that another mode could execute it
   independently," then hand to implementation; "Pause for human approval." (1, 3)
6. **SCOPE is bounded and deferential — plan/review and hand off, don't do
   everything.** Enforced by *capability* (Roo: markdown-only edits; ship-mate: no
   code/edits) and by *lane* (backend-architect "defers" to peers; escalation
   triggers; "Do not guess"). This is the operational form of Fowler's "value is
   inversely proportional to the number of decisions." (1, 3, 2, 4)
7. **METHOD — raise the team's level and reduce irreversibility.** The
   highest-leverage activity is mentoring "to raise their level"; and "remove
   architecture by … eliminat[ing] irreversibility" — make the hard-to-change cheap
   to change. (4)

> Fidelity note: Roo's built-in Architect now lives in
> `packages/types/src/mode.ts` (`DEFAULT_MODES`), not `src/shared/modes.ts` (which
> imports it). All quotes are from the live raw files / IEEE PDF fetched
> 2026-06-15.
