---
name: Prior-art survey — BMAD-METHOD Architect ("Winston")
description: Primary-source survey of the BMAD-METHOD Architect agent persona — the current skills-based "Winston" (customize.toml + SKILL.md) and the classic V4 persona-block (role/style/identity/focus/core_principles + commands + task/template dependencies), its "architecture spine" method, and what makes it strong. Grounds the gc-toolkit architect built in tk-ae96t.1.
---

# Prior-art survey — BMAD-METHOD Architect

BMAD-METHOD ("Breakthrough Method for Agile AI-Driven Development") defines AI
agent **personas** as the central abstraction. Its **Architect** ("Winston") is
the closest, strongest prior art for the gc-toolkit architect, so it gets its own
survey. Fetched from **live primary sources** on 2026-06-15 (raw GitHub +
in-repo docs), not training memory — the repo restructured recently and ships
**two** architect generations side by side.

## Provenance

| # | Source | Used for | Verified |
|---|---|---|---|
| 1 | `github.com/bmad-code-org/BMAD-METHOD` (default `main`, rel v6.8.0; `bmadcode/BMAD-METHOD` redirects here) | canonical repo | 2026-06-15 |
| 2 | `api.github.com/.../git/trees/main?recursive=1` + `.../trees/V4?recursive=1` | locate real file paths before fetch | 2026-06-15 |
| 3 | `raw .../main/src/bmm-skills/3-solutioning/bmad-agent-architect/customize.toml` | current Winston persona (name/title/role/identity/style/principles/menu) | 2026-06-15 |
| 4 | `raw .../main/src/bmm-skills/3-solutioning/bmad-agent-architect/SKILL.md` | current activation runtime (persona adoption + menu dispatch) | 2026-06-15 |
| 5 | `raw .../main/src/bmm-skills/3-solutioning/bmad-architecture/SKILL.md` | the `CA` "architecture spine" method | 2026-06-15 |
| 6 | `raw .../main/docs/reference/agents.md`, `docs/explanation/named-agents.md` | agent roster; 3-part Skill/named-agent/customize architecture | 2026-06-15 |
| 7 | `raw .../V4/bmad-core/agents/architect.md` | classic persona block (the format below) | 2026-06-15 |
| 8 | `raw .../V4/common/tasks/create-doc.md`, `.../V4/bmad-core/templates/architecture-tmpl.yaml` | the elicitation-driven method + architecture template section structure | 2026-06-15 |

---

## 1. The persona — two generations, same identity

### Current `main` (v6.8.0): a **skills-based** persona (source 3, 4, 6)

BMAD now ships each agent as a *3-part construct* (source 6): a **Skill**
(activation runtime), a **hardcoded named agent** (the fixed identity), and a
**`customize.toml`** (the tunable layer). The header of `customize.toml` states
*"Winston, the System Architect, is the hardcoded identity of this agent."* —
i.e. **identity is fixed/brandable; behavior is tunable.** Verbatim:

- **name/title:** `Winston` / `System Architect` (non-configurable); **icon** `🏗️`
- **role:** "Convert the PRD and UX into technical architecture decisions that
  keep implementation on track during the BMad Method solutioning phase."
- **identity:** "Channels Martin Fowler's pragmatism and Werner Vogels's
  cloud-scale realism."
- **communication_style:** "Calm and pragmatic. Balances 'what could be' with
  'what should be.' **Answers with trade-offs, not verdicts.**"
- **principles:** "Rule of Three before abstraction." · "Boring technology for
  stability." · "Developer productivity is architecture."
- **menu (only two items):** `CA` → produce *"the architecture spine: the
  invariants that keep independently-built units consistent"* (invokes the
  `bmad-architecture` skill); `IR` → *"Ensure the PRD, UX, Architecture and Epics
  and Stories List are all aligned"* (implementation-readiness check).

### Classic `V4`: the self-contained **persona block** (source 7)

The V4 format is one markdown file with a structured block — the shape worth
imitating for a portable identity:

```yaml
persona:
  role: Holistic System Architect & Full-Stack Technical Leader
  style: Comprehensive, pragmatic, user-centric, technically deep yet accessible
  identity: Master of holistic application design who bridges frontend, backend,
            infrastructure, and everything in between
  focus: Complete systems architecture, cross-stack optimization, pragmatic
         technology selection
  core_principles:
    - Holistic System Thinking — every component is part of a larger system
    - User Experience Drives Architecture — start with user journeys, work backward
    - Pragmatic Technology Selection — boring tech where possible, exciting where necessary
    - Progressive Complexity — simple to start, able to scale
    - Cost-Conscious Engineering — balance technical ideals with financial reality
    - Living Architecture — design for change and adaptation
```

Commands are `*`-prefixed (`*create-backend-architecture`, `*document-project`,
`*execute-checklist architect-checklist`, `*shard-prd`, …) and the agent declares
explicit **dependencies**: tasks (`create-doc`, `document-project`,
`execute-checklist`), templates (`architecture-tmpl.yaml` + brownfield/frontend/
fullstack variants), checklists (`architect-checklist`), data
(`technical-preferences`). The persona indexes its methods by name; the methods
live as separate, reusable files. **This is the persona = identity + an index of
method-files pattern, in prior art.**

## 2. The methods

- **"Architecture spine" (current, source 5).** The signature artifact fixes
  *only the invariants* that would let independently-built units diverge — *"the
  design paradigm, the boundary and dependency rules, how state is mutated, who
  owns shared data."* Structure that code can own later (full tree, exact data
  shape) is deliberately excluded as "seed." The inclusion test is sharp: *"If
  two units one level down built this independently, could they choose
  incompatibly? Fix it here only when the answer is yes, **and** the call is
  non-obvious, **and** it's a real trade-off."* Decisions become stable `AD-n`
  entries with `Binds`/`Prevents`/`Rule`; inherited parent-spine ADs are
  read-only.
- **Elicitation is mandatory; drafting is the anti-pattern (sources 5, 8).** V4's
  `create-doc` makes any `elicit: true` section a HARD STOP with required rationale
  (trade-offs/assumptions) and numbered 1–9 options. The current method defaults
  to a "Coaching path" and names the failure mode outright: *"A finished
  architecture produced from two quick questions is the failure mode, not the win
  — the elicitation is the value."*
- **Quality-gated, auditable output (sources 5, 7, 8).** Current runs keep an
  append-only **memlog** the spine is distilled from, plus a Reviewer Gate
  (deterministic lint + rubric + per-lens reviewer subagents); V4 backs this with
  the `architect-checklist` self-review. The template's last section is a
  "Checklist Results Report."

## 3. What makes BMAD's architect strong (distilled, sourced)

1. **STANCE — a pragmatic trade-off broker, not an oracle.** *"Answers with
   trade-offs, not verdicts"*; "boring technology"; channels Fowler. Its prime
   directive is downstream-implementability — *"keep implementation on track."*
   (3, 5)
2. **OWNS the planning→buildable-architecture bridge** and **validates alignment**
   across PRD/UX/architecture/epics (the `IR` check). It's the seam artifact. (3, 6)
3. **METHOD — invariants-first, not a document dump.** Pin only what would let
   units diverge; let code own the rest. A notably disciplined definition of what
   an architecture *should* fix. (5)
4. **METHOD — elicitation over drafting.** Human-in-the-loop is enforced
   structurally; the conversation, not the document, is the value. (5, 8)
5. **OWNS reproducible, quality-gated decisions** — memlog → `AD-n`
   (Binds/Prevents/Rule), checklist/reviewer gate, version-tracked. (5, 7, 8)
6. **Identity fixed, behavior tunable.** The 3-part Skill/named-agent/customize
   split makes "the Architect" a portable, brandable role an org can specialize
   without losing its core. This maps directly onto our *identity travels;
   owns/processes resolve per project*. (3, 6)
