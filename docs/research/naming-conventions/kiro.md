# Kiro — document naming conventions

Survey of Kiro (kiro.dev), an agentic IDE from Amazon, with focus on
**output document types and where they get recorded**, plus a dedicated
deep-dive on Kiro's **Steering documents** concept.

## Provenance

| Doc-type                  | Producer (Kiro feature / concept) | Source location (URL / path)                                                                          | Surveyed at |
| ------------------------- | --------------------------------- | ----------------------------------------------------------------------------------------------------- | ----------- |
| Spec — `requirements.md`  | Specs (Feature)                   | https://kiro.dev/docs/specs/, https://kiro.dev/docs/specs/feature-specs/                              | 2026-05-05  |
| Spec — `design.md`        | Specs (Feature & Bugfix)          | https://kiro.dev/docs/specs/, https://kiro.dev/docs/specs/feature-specs/                              | 2026-05-05  |
| Spec — `tasks.md`         | Specs (Feature & Bugfix)          | https://kiro.dev/docs/specs/, https://kiro.dev/docs/specs/best-practices/                             | 2026-05-05  |
| Spec — `bugfix.md`        | Specs (Bugfix)                    | https://kiro.dev/docs/specs/bugfix-specs/                                                             | 2026-05-05  |
| Steering — `*.md`         | Steering                          | https://kiro.dev/docs/steering/                                                                       | 2026-05-05  |
| Steering — foundational   | Steering ("Generate Steering Docs") | https://kiro.dev/docs/steering/                                                                     | 2026-05-05  |
| `AGENTS.md`               | Steering (external standard)      | https://kiro.dev/docs/steering/                                                                       | 2026-05-05  |
| Skill — `SKILL.md`        | Agent Skills                      | https://kiro.dev/docs/skills                                                                          | 2026-05-05  |
| Power — `POWER.md`        | Powers                            | https://kiro.dev/docs/powers/, https://github.com/kirodotdev/powers                                   | 2026-05-05  |
| Hook — `*.kiro.hook`      | Agent Hooks                       | https://kiro.dev/docs/hooks/, https://kiro.dev/docs/hooks/types/, https://kiro.dev/docs/hooks/examples/ | 2026-05-05  |
| MCP config — `mcp.json`   | MCP Servers                       | https://kiro.dev/docs/mcp/, https://kiro.dev/docs/mcp/configuration/                                  | 2026-05-05  |
| Custom agent — `*.json`+`*.md` | Kiro CLI Custom Agents       | https://kiro.dev/docs/cli/                                                                            | 2026-05-05  |

The bead asks the question "where does each Kiro doc-type get recorded
by default" — every row above answers that for one Kiro feature.

## Source surveyed

- Docs site: https://kiro.dev/docs/ — surveyed 2026-05-05
- Pages read in full or in part:
  - `/docs/` (top-level index)
  - `/docs/specs/`, `/docs/specs/feature-specs/`, `/docs/specs/bugfix-specs/`,
    `/docs/specs/best-practices/`
  - `/docs/steering/` (full body, including inclusion-mode table, file-reference
    syntax, AGENTS.md compatibility note, foundational-files description)
  - `/docs/hooks/`, `/docs/hooks/types/`, `/docs/hooks/examples/`,
    `/docs/hooks/troubleshooting/`, `/docs/cli/hooks/`
  - `/docs/mcp/`, `/docs/mcp/configuration/`
  - `/docs/skills` (full)
  - `/docs/powers/`
  - `/docs/chat/`, `/docs/getting-started/first-project/`
- Real-repo `.kiro/` trees inspected (to verify documented paths and
  capture concrete file shapes the docs do not show):
  - `affaan-m/everything-claude-code/.kiro/` —
    `agents/` (CLI custom agents, JSON+MD pairs),
    `docs/`, `hooks/` (`.kiro.hook` JSON files), `scripts/`,
    `settings/`, `skills/` (each skill is a folder with `SKILL.md`),
    `steering/` (frontmatter-bearing markdown)
  - `awsdataarchitect/kiro-best-practices/.kiro/` —
    `hooks/`, `settings/`, `steering/`
- Community templates referenced (community-curated companion to the
  Kiro spec process — not first-party but quoted verbatim where the
  first-party docs are silent):
  - `jasonkneen/kiro/spec-process-guide/templates/`
    (`requirements-template.md`, `design-template.md`,
    `tasks-template.md`, `checklists.md`,
    `quick-spec-template.md`, `micro-spec-template.md`)

## Directory structure

Kiro stores all per-workspace context under a single top-level dotfile
directory, `.kiro/`, with parallel `~/.kiro/` for the global scope.
Observed layout (from `affaan-m/everything-claude-code` cross-checked
against doc paths):

```
.kiro/
├── specs/                          # Per-feature spec folders (docs)
│   └── <feature-name>/
│       ├── requirements.md         # or bugfix.md (bugfix variant)
│       ├── design.md
│       └── tasks.md
├── steering/                       # Persistent context markdown (docs)
│   ├── product.md                  # Foundational (auto-generated)
│   ├── tech.md                     # Foundational (auto-generated)
│   ├── structure.md                # Foundational (auto-generated)
│   ├── <area>.md                   # Custom (user-created)
│   └── AGENTS.md                   # External-standard variant (optional)
├── skills/                         # Agent Skills standard packages
│   └── <skill-name>/
│       ├── SKILL.md                # Required entrypoint
│       ├── scripts/                # Optional
│       ├── references/             # Optional
│       └── assets/                 # Optional
├── hooks/                          # Agent Hooks (JSON automation)
│   └── <hook-name>.kiro.hook       # JSON, .kiro.hook extension
├── settings/
│   └── mcp.json                    # MCP server configuration
├── agents/                         # CLI custom agents (observed in the wild;
│   ├── <agent-name>.json           #  JSON config + paired MD prompt)
│   └── <agent-name>.md
├── docs/                           # Project-internal docs (observed; not
│                                   #  a Kiro-defined concept — convention
│                                   #  picked by some users)
└── scripts/                        # Per-project utility scripts (observed;
                                    #  not a Kiro-defined concept)
```

Global counterpart (across all workspaces):

```
~/.kiro/
├── steering/                       # Workspace conflicts win over global
│   └── (same layout)
├── skills/
│   └── (same layout — workspace conflicts win)
└── settings/
    └── mcp.json
```

The docs explicitly call out workspace-vs-global precedence for steering
("Workspace steering takes priority when conflicts occur with global
steering") and for MCP ("workspace settings taking precedence" when the
two `mcp.json` files merge). Skills inherit the same rule.

**Powers** install into the same tree but the install-time documentation
was not specific about a fixed `.kiro/powers/` path on disk — they
register their MCP servers into `~/.kiro/settings/mcp.json` "under the
Powers section" and ship a `POWER.md` plus optional `mcp.json` and
optional steering/hook files.

## Filename patterns

**Lowercase-kebab-case markdown is pervasive for human-authored content.**
Steering files, spec body files, and skill supporting files all use
`<kebab-case>.md` with no date prefix, no version suffix, and no status
marker.

| Pattern                                      | Where                              | Meaning                                                                                                                                       |
| -------------------------------------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `requirements.md`, `design.md`, `tasks.md`   | `.kiro/specs/<feature>/`           | The three canonical files of every feature spec. **Fixed names, not configurable.**                                                           |
| `bugfix.md`, `design.md`, `tasks.md`         | `.kiro/specs/<bugfix>/`            | Bugfix variant — first file is `bugfix.md` instead of `requirements.md`; other two are unchanged.                                             |
| `<feature-name>/`                            | `.kiro/specs/`                     | Spec scope unit. Best-practices doc lists examples: `user-authentication/`, `product-catalog/`, `shopping-cart/`, `payment-processing/`, `admin-dashboard/`. |
| `product.md`, `tech.md`, `structure.md`      | `.kiro/steering/`                  | Foundational steering — pre-shipped, "included in every interaction by default."                                                              |
| `<descriptive-name>.md`                      | `.kiro/steering/`                  | Custom steering. Doc-suggested patterns: `api-rest-conventions.md`, `testing-unit-patterns.md`, `components-form-validation.md`.              |
| `AGENTS.md`                                  | `.kiro/steering/` or workspace root | External standard; lives next to custom steering files but cannot use inclusion modes (always loaded).                                        |
| `SKILL.md` (uppercase)                       | `.kiro/skills/<skill-name>/`       | Required entrypoint for every skill. Borrowed from the open Agent Skills standard. Sorts to top.                                              |
| `<skill-name>/`                              | `.kiro/skills/`                    | Skill folder. Required to match the `name` frontmatter field exactly: lowercase, numbers, hyphens only, max 64 chars.                         |
| `POWER.md` (uppercase)                       | (power package root)               | Required entrypoint for every Power.                                                                                                          |
| `<hook-name>.kiro.hook`                      | `.kiro/hooks/`                     | JSON config with `.kiro.hook` extension. Real names from one repo: `auto-format.kiro.hook`, `code-review-on-write.kiro.hook`, `tdd-reminder.kiro.hook`. |
| `mcp.json`                                   | `.kiro/settings/`, `~/.kiro/settings/` | MCP server config. Single, fixed name.                                                                                                    |
| `<agent>.json` + `<agent>.md`                | `.kiro/agents/` (CLI)              | Custom agents (CLI). Observed convention: paired JSON config and MD prompt sharing the basename.                                              |

**Two filename-case tiers.** Lowercase-kebab dominates for human content
and for anything user-created. Uppercase-with-`.md` is reserved for
*entrypoint* files defined by an external standard: `SKILL.md` (Agent
Skills), `POWER.md` (Kiro Powers), `AGENTS.md` (cross-tool agents
standard). The visual contrast is intentional — the entrypoint sorts to
the top of `ls` output and is unambiguous to readers.

**No date prefix on any Kiro-defined doc.** Unlike Superpowers'
`YYYY-MM-DD-<slug>.md` plans, Kiro never encodes time in filenames. A
spec's date lives in its `requirements.md` "Document Information"
section if at all (that field is a community-template convention, not
first-party). The first-party `requirements.md` has no
"Document Information" section and no date field documented.

**No status suffix on any Kiro-defined doc.** Specs do not get renamed
to `requirements-draft.md` → `requirements-final.md`; the same three
filenames persist through draft, in-progress, and complete states.

**Hook filename rule.** The `.kiro.hook` extension is doubled (the
`.kiro` part is meaningful to Kiro's discovery, not just decorative).
The basename is free-form kebab-case and *also* duplicates the value
of the `name` field inside the JSON.

## Doc-type taxonomy

Kiro defines six first-party doc-types plus one cross-tool standard it
supports. Directory placement is the primary signal of doc-type — like
Superpowers, the path tells you what kind of file you're looking at.

| Where                                | Doc type                                  | Filename style                            | Format            |
| ------------------------------------ | ----------------------------------------- | ----------------------------------------- | ----------------- |
| `.kiro/specs/<feature>/requirements.md` | Spec — Feature requirements (EARS)     | fixed `requirements.md`                   | Markdown          |
| `.kiro/specs/<feature>/design.md`    | Spec — Feature/bugfix design              | fixed `design.md`                         | Markdown + Mermaid |
| `.kiro/specs/<feature>/tasks.md`     | Spec — Implementation plan (checklists)   | fixed `tasks.md`                          | Markdown checkboxes |
| `.kiro/specs/<bugfix>/bugfix.md`     | Spec — Bugfix analysis                    | fixed `bugfix.md`                         | Markdown          |
| `.kiro/steering/<name>.md`           | Steering — workspace context              | kebab-case `<name>.md`                    | Markdown + YAML frontmatter |
| `~/.kiro/steering/<name>.md`         | Steering — global context                 | kebab-case `<name>.md`                    | Markdown + YAML frontmatter |
| `.kiro/skills/<name>/SKILL.md`       | Skill (Agent Skills standard)             | uppercase `SKILL.md` entrypoint           | Markdown + YAML frontmatter |
| (power package root)/`POWER.md`      | Power (Kiro-specific bundle)              | uppercase `POWER.md` entrypoint           | Markdown          |
| `.kiro/hooks/<name>.kiro.hook`       | Agent Hook (automation config)            | kebab-case + `.kiro.hook` extension       | JSON              |
| `.kiro/settings/mcp.json`            | MCP server registration                   | fixed `mcp.json`                          | JSON              |
| `~/.kiro/settings/mcp.json`          | MCP server registration (global)          | fixed `mcp.json`                          | JSON              |
| `.kiro/agents/<name>.{json,md}`      | CLI custom agent (paired files; observed) | kebab-case basename                       | JSON + Markdown   |
| Workspace root or `.kiro/steering/` `AGENTS.md` | External cross-tool agent file | fixed `AGENTS.md` (uppercase)             | Markdown          |

Two of those rows — `Skill` and `AGENTS.md` — explicitly inherit
external standards (the open "Agent Skills" standard and the
cross-tool `AGENTS.md` convention). Kiro chose to *adopt* them inside
`.kiro/`, not reinvent them. Powers, by contrast, are Kiro-specific.

**Three sub-types of "instruction-bearing markdown" coexist** and the
docs explicitly differentiate them (from the Skills page):

> "Skills are portable packages following an open standard…
> Steering is Kiro-specific context that shapes agent behavior…
> Powers bundle MCP tools with knowledge and workflows."

So `SKILL.md`, steering `.md`, and `POWER.md` are not interchangeable
even though they all look like "markdown that tells the agent how to
behave." The differences are loading model (always vs on-demand vs
keyword-activated), portability (open standard vs Kiro-specific), and
what they bundle (instructions vs context vs tools+context+workflows).

## Per-template detail

### Spec — `requirements.md` (feature)

**First-party docs** describe the format only narratively: "captures
user stories, acceptance criteria … in structured notation," using
EARS — *Easy Approach to Requirements Syntax*. The single quoted
example from the docs:

```
WHEN a user submits a form with invalid data
THE SYSTEM SHALL display validation errors next to the relevant fields
```

**Frontmatter:** none documented. The first-party `requirements.md`
appears to be vanilla markdown without YAML frontmatter.

**Body sections:** the docs do not enumerate required sections.
Everything below this line comes from the **community-curated
template** (`jasonkneen/kiro/spec-process-guide/templates/requirements-template.md`),
which is not first-party but is the most-cited reference. Verbatim
section structure:

```
## Document Information
- **Feature Name**: [Your Feature Name]
- **Version**: 1.0
- **Date**: [Current Date]
- **Author**: [Your Name]
- **Stakeholders**: [List key stakeholders]

## Introduction
### Feature Summary
### Business Value
### Scope

## Requirements

### Requirement 1: [Requirement Title]
**User Story:** As a [role/user type], I want [desired functionality], so that [benefit/value].

#### Acceptance Criteria
1. WHEN [specific event or trigger] THEN [system name] SHALL [specific system response]
2. IF [condition or state] THEN [system name] SHALL [required behavior]
3. WHILE [ongoing condition] [system name] SHALL [continuous behavior]
4. WHERE [context or location] [system name] SHALL [contextual behavior]

#### Additional Details
- **Priority**: [High/Medium/Low]
- **Complexity**: [High/Medium/Low]
- **Dependencies**: [List any dependencies]
- **Assumptions**: [List any assumptions made]

## Non-Functional Requirements
### Performance Requirements
### Security Requirements
### Usability Requirements
### Reliability Requirements

## Constraints and Assumptions
### Technical Constraints
### Business Constraints
### Assumptions
```

Five EARS keywords are all in use across community templates: `WHEN`,
`IF`, `WHILE`, `WHERE`, with `SHALL` as the system-response verb. The
first-party docs only show `WHEN … SHALL`; the broader four-mood EARS
vocabulary appears in community guidance but is not contradicted by
first-party docs.

### Spec — `design.md`

**First-party docs:** "documents technical architecture, sequence
diagrams, and implementation considerations" — concretely, "system
architecture, sequence diagrams, data flow, error handling, and
testing strategy." No section schema is enforced by Kiro itself.

**Community template** (verbatim shape):

```
## Document Information
- Feature Name / Version / Date / Author / Reviewers
- Related Documents: [Link to requirements document]

## Overview
### Design Goals
### Key Design Decisions

## Architecture
### System Context           — includes a Mermaid graph block
### High-Level Architecture  — includes a Mermaid graph block
### Technology Stack         — table: Layer / Technology / Rationale

## Components and Interfaces
### Component 1: [Name]
  **Purpose**, **Responsibilities**, **Interfaces**
  (Input / Output / Dependencies), **Implementation Notes**
### Component 2: [Name]  ...
```

Mermaid is the diagram syntax (the template uses ` ```mermaid graph TB
… ``` ` blocks). No frontmatter.

### Spec — `tasks.md`

**Format is enforced enough that the IDE depends on it.** From the
search-result quote of Kiro's own guidance: top-level tasks must be
checkboxes themselves, hierarchy is "a maximum of two levels," and the
"Start task" button only appears when "task checkboxes are in the
correct format." Numbered checkbox-list items are the canonical shape:

```
# Implementation Plan
- [ ] 1. Task 1
- [x] 2. Task 2 (completed)
- [ ] 3. Task 3
```

Tasks can be **referenced by hierarchical ID** in chat ("execute task
0.1.1", "start task 0.1.1"). Kiro reads the checkbox state to display
in-progress / completed status in the IDE side-panel.

**Community template** shows the richer convention used in the wild —
phase headings, sub-tasks numbered as `4.1`, `4.2`, and a per-task
**`_Requirements: …_`** trailing italic line linking back to numbered
requirements in `requirements.md`:

```
## Implementation Plan

### Phase 1: Foundation and Setup

- [ ] 1. Set up project structure and development environment
  - Create directory structure for the feature
  - Set up build configuration and dependencies
  - _Requirements: [Reference specific requirements]_

- [ ] 2. Implement core data models and interfaces
  - Define TypeScript interfaces for all data models
  - _Requirements: [Reference specific requirements]_

### Phase 2: Core Business Logic

- [ ] 4. Implement core business logic components
- [ ] 4.1 Create [Component Name] service
  - Implement core business rules and validation
  - Add error handling and logging
  - _Requirements: [Reference specific requirements]_
```

This is the only place a spec's three docs cross-reference each other:
the `_Requirements:_` trailing line on each task entry. The reference
target is the **numbered list** in `requirements.md` — not a slug, not
a frontmatter ID — just the integer the requirement happens to have in
its file.

### Spec — `bugfix.md` (bugfix variant)

Bugfix specs follow "the same three-phase workflow as Feature Specs
(Requirements → Design → Tasks)" with `bugfix.md` standing in for
`requirements.md`. The acceptance-criteria format adds a third mood
specific to bug fixing — *unchanged behavior* / regression prevention:

```
Current Behavior (Defect):
  WHEN [condition] THEN the system [incorrect behavior]

Expected Behavior (Correct):
  WHEN [condition] THEN the system SHALL [correct behavior]

Unchanged Behavior (Regression Prevention):
  WHEN [condition] THEN the system SHALL CONTINUE TO [existing behavior]
```

Note `SHALL CONTINUE TO` as a regression-prevention modifier — a
Kiro-specific extension to the EARS vocabulary not seen in feature
specs.

### Skill — `SKILL.md`

Kiro adopts the open Agent Skills standard verbatim. **Required
frontmatter fields:**

```yaml
---
name: <lowercase-kebab-with-numbers, max 64 chars, must match folder name>
description: <when to use; matched against requests; max 1024 chars>
---
```

**Optional frontmatter fields:** `license`, `compatibility`, `metadata`.

A skill folder layout:

```
.kiro/skills/<skill-name>/
├── SKILL.md                # Required
├── scripts/                # Optional — runnable code
├── references/             # Optional — reference docs
└── assets/                 # Optional — non-code resources
```

Loading model: **progressive disclosure.** Discovery loads only
`name` + `description` at startup; activation loads the full
`SKILL.md` body when the request matches; execution then loads
`scripts/` etc. as needed.

A real example from `affaan-m/everything-claude-code/.kiro/skills/agentic-engineering/SKILL.md`:

```yaml
---
name: agentic-engineering
description: >
  Operate as an agentic engineer using eval-first execution, decomposition,
  and cost-aware model routing. Use when AI agents perform most implementation
  work and humans enforce quality and risk controls.
metadata:
  origin: ECC
---
```

The `description:` field begins "Operate as … Use when …" — exactly
the "Use when" discipline Superpowers documents.

### Power — `POWER.md`

Powers are *bundles* (rather than single files): one `POWER.md`
required, plus optional `mcp.json` and optional steering/hook files.
First-party docs describe `POWER.md` as "the steering file that tells
the agent what MCP tools it has available and when to use them" — i.e.
its body looks like a steering doc with an MCP-tool focus.

The Powers feature ships an installer that registers any MCP servers
into the global `~/.kiro/settings/mcp.json` "under the Powers
section" — so installing a Power mutates the user's MCP config rather
than living entirely under `.kiro/powers/`. The first-party docs do
not pin a canonical filesystem location for Powers.

### Hook — `*.kiro.hook`

JSON file. Schema (verified against
`affaan-m/everything-claude-code/.kiro/hooks/auto-format.kiro.hook`,
verbatim):

```json
{
  "name": "auto-format",
  "version": "1.0.0",
  "enabled": true,
  "description": "Automatically format TypeScript and JavaScript files on save",
  "when": {
    "type": "fileEdited",
    "patterns": ["*.ts", "*.tsx", "*.js"]
  },
  "then": {
    "type": "askAgent",
    "prompt": "A TypeScript or JavaScript file was just saved. If there are any obvious formatting issues (indentation, trailing whitespace, import ordering), fix them now."
  }
}
```

Top-level fields observed: `name`, `version`, `enabled`, `description`,
`when`, `then`. The `when.type` discriminator selects the trigger; the
`then.type` selects the action (`askAgent` for an agent prompt;
shell commands are also supported per docs but not in this example).

**Hook trigger types** (10, from `/docs/hooks/types/`):

1. Prompt Submit — user submits a prompt
2. Agent Stop — agent has completed its turn
3. Pre Tool Use — agent is about to invoke a tool
4. Post Tool Use — after agent invokes a tool
5. File Create — files matching patterns are created
6. File Save — files matching patterns are saved
7. File Delete — files matching patterns are deleted
8. Pre Task Execution — before a spec task begins execution
9. Post Task Execution — after a spec task completes
10. Manual Trigger — manually executed

Items 8/9 explicitly bridge Hooks ↔ Specs — the only first-party
mechanism that ties two doc-types together programmatically.

### MCP config — `mcp.json`

Schema verbatim from `/docs/mcp/configuration/`:

```json
{
  "mcpServers": {
    "server-name": {
      "command": "command-to-run-server",
      "args": ["arg1", "arg2"],
      "env": {
        "ENV_VAR1": "hard-coded-variable",
        "ENV_VAR2": "${EXPANDED_VARIABLE}"
      },
      "disabled": false,
      "autoApprove": ["tool_name1"],
      "disabledTools": ["tool_name3"]
    }
  }
}
```

Workspace `.kiro/settings/mcp.json` and global `~/.kiro/settings/mcp.json`
merge with workspace winning.

### Custom agent — `<name>.json` + `<name>.md` (CLI)

**Observed in the wild** in `affaan-m/everything-claude-code/.kiro/agents/`
but barely documented in the surveyed pages (CLI custom agents have
their own configuration-reference page that was not exhaustively read).
Convention: paired files sharing the basename. The `.json` carries
runtime config; the `.md` carries a frontmatter-only header plus the
agent system prompt.

JSON shape (verbatim from `architect.json`):

```json
{
  "name": "architect",
  "description": "...",
  "mcpServers": {},
  "tools": ["@builtin"],
  "allowedTools": ["fs_read", "shell"],
  "resources": [],
  "hooks": {},
  "useLegacyMcpJson": false,
  "prompt": "<full prompt body inline>"
}
```

MD shape (verbatim from `architect.md`):

```yaml
---
name: architect
description: Software architecture specialist for system design, scalability, and technical decision-making. Use PROACTIVELY when planning new features, refactoring large systems, or making architectural decisions.
allowedTools:
  - read
  - shell
---

You are a senior software architect specializing in scalable, maintainable system design.
…
```

The `.json` and `.md` overlap (both carry name, description, allowedTools,
prompt). This appears to be a community pattern of keeping a Markdown
view in sync with the JSON the CLI actually loads. Treat as
community-discovered, not first-party.

## Steering documents (Kiro-specific)

Steering is the Kiro feature most worth documenting in detail because
it is the doc-type that has no clean parallel in the BMAD or
Superpowers references already surveyed.

### What they are

Per the docs:

> "Steering gives Kiro persistent knowledge about your workspace
> through markdown files. Instead of explaining your conventions in
> every chat, steering files ensure Kiro consistently follows your
> established patterns, libraries, and standards."

In practice, steering is **agent-context-as-files**: each `.md` file
under `.kiro/steering/` becomes part of the agent's system context
according to a per-file inclusion rule. Steering files are *not* docs
the user reads — they are docs *about* the codebase, written for the
agent to consume.

### Where they live (filesystem location)

| Scope     | Location                       | Precedence rule                                      |
| --------- | ------------------------------ | ---------------------------------------------------- |
| Workspace | `.kiro/steering/`              | Wins on conflict with global                         |
| Global    | `~/.kiro/steering/`            | Loses on conflict; otherwise stacks with workspace   |
| AGENTS.md | `.kiro/steering/AGENTS.md` *or* workspace-root `AGENTS.md` | Always loaded; cannot use inclusion modes |

Steering files committed to the repo travel with the codebase; global
steering travels with the user across all their workspaces.

### How they're authored / by whom (or by what)

Three creation paths documented:

1. **IDE button** — Steering panel → `+` button.
2. **"Generate Steering Docs" button** — auto-creates the three
   foundational files (`product.md`, `tech.md`, `structure.md`) by
   scanning the workspace.
3. **Manual** — write a markdown file directly in the appropriate
   `.kiro/steering/` directory.

A "Refine" IDE action exists for workspace files (mentioned in docs
without further detail). The recommended discipline: "treat steering
changes like code changes — require reviews."

The author is therefore *either* the agent (when generated/refined) or
the human (when written directly), with no in-file marker
distinguishing the two.

### How they're consumed by Kiro / by users

The mechanism is the **`inclusion` frontmatter field**, which selects
one of four loading rules:

| Mode     | When loaded                                                                                  | Documented use case                       |
| -------- | -------------------------------------------------------------------------------------------- | ----------------------------------------- |
| `always` | Every interaction                                                                            | Core workspace standards                  |
| `fileMatch` | When the user is editing a file matching `fileMatchPattern`                               | Domain-specific guidance (e.g. `components/**/*.tsx` triggers a component-conventions file) |
| `manual` | Only when the user explicitly references the file in chat as `#<steering-file-name>` or via slash command | Occasional specialized context |
| `auto`   | When the request description matches the file's `description:` field; also via slash commands | Complex workflows                         |

Four-mode loading is the headline feature. By contrast, `AGENTS.md` is
"always included" with no opt-out — that's the price of the external
standard's portability.

Steering files can also embed **live workspace files** with the syntax:

```
#[[file:<relative_file_name>]]
```

For example, `#[[file:api/openapi.yaml]]` or
`#[[file:components/ui/button.tsx]]`. This makes steering able to point
at concrete files (the actual API contract, the actual reference
component) instead of restating their content. The reference resolves
at load time — if the file moves, the steering doc breaks.

### Lifecycle

- **No status frontmatter.** Files are not draft / published /
  deprecated.
- **No date or version field** in frontmatter.
- **Manual review discipline** is the documented lifecycle: "treat
  steering changes like code changes — require reviews."
- **Update windows:** docs suggest updating during sprint planning and
  on architecture changes.
- **Restructuring breakage:** "file references need testing after
  restructuring" — meaning the `#[[file:…]]` references can rot if the
  underlying paths move.

There is no `archive/` or `deprecated/` sub-directory convention.
Deletion is the only retirement path.

### How they differ from architecture / principles / other Kiro doc types

| Dimension       | Steering                              | Skill (`SKILL.md`)                | Power (`POWER.md`)                | AGENTS.md                          |
| --------------- | ------------------------------------- | --------------------------------- | --------------------------------- | ---------------------------------- |
| Scope           | Workspace conventions                 | Reusable instruction package      | Tools + workflows + knowledge     | Cross-tool agent instructions      |
| Portability     | Kiro-specific                         | Open standard (cross-IDE)         | Kiro-specific                     | External standard (cross-IDE)      |
| Loading         | 4 inclusion modes (always/fileMatch/manual/auto) | Progressive disclosure (name+description first, body on match) | Activated dynamically by keywords | Always loaded; no inclusion modes  |
| Bundles scripts? | No                                   | Yes (`scripts/`)                  | Yes (MCP tools)                   | No                                 |
| Discovery key   | Path under `.kiro/steering/`          | `name:` matching folder name      | Power install registry            | Filename `AGENTS.md`               |
| Per-file metadata | YAML frontmatter (`inclusion`, `fileMatchPattern`, `name`, `description`) | YAML frontmatter (`name`, `description`, optional `license`/`compatibility`/`metadata`) | YAML frontmatter (POWER.md) | None enforced                       |

The clearest distinction: **steering is workspace-owned context that
shapes how Kiro behaves *in this codebase*; skills and powers are
portable instruction units that travel between codebases.** AGENTS.md
is steering's portable cousin — same content shape, no inclusion-mode
control.

There is no separate "architecture" or "ADR" doc-type in Kiro. If you
want architecture docs, you author them as a steering file
(`structure.md` is the foundational one). Same for principles, coding
standards, conventions — all collapse into "a steering file with the
appropriate `inclusion` mode."

### Notable shape / template (frontmatter, body, examples)

**Frontmatter fields** (all optional, all in YAML between `---`
delimiters at file start):

| Field              | Type            | Required when           | Semantics                                                                 |
| ------------------ | --------------- | ----------------------- | ------------------------------------------------------------------------- |
| `inclusion`        | string          | Always present in practice | One of `always`, `fileMatch`, `manual`, `auto` (default if omitted: `always`) |
| `fileMatchPattern` | string or array | `inclusion: fileMatch`  | Glob pattern(s) for file paths that trigger this steering                  |
| `name`             | string          | `inclusion: auto`       | Identifier the agent uses to reference this steering                       |
| `description`      | string          | `inclusion: auto`       | When to include — matched against the user's request (Skills-style)        |

Documented frontmatter example:

```yaml
---
inclusion: fileMatch
fileMatchPattern: "components/**/*.tsx"
---
```

**Foundational file content** (auto-generated by "Generate Steering
Docs"):

| File           | Content                                                       |
| -------------- | ------------------------------------------------------------- |
| `product.md`   | Product purpose, target users, business goals                 |
| `tech.md`      | Frameworks, libraries, technical constraints                  |
| `structure.md` | File organization, naming conventions, architecture           |

These three "are included in every interaction by default, forming the
baseline of Kiro's project understanding." The default `inclusion`
mode for them is `always`.

**Real verbatim steering file** from
`affaan-m/everything-claude-code/.kiro/steering/coding-style.md`:

```markdown
---
inclusion: auto
description: Core coding style rules including immutability, file organization, error handling, and code quality standards.
---

# Coding Style

## Immutability (CRITICAL)

ALWAYS create new objects, NEVER mutate existing ones:
…

## File Organization

MANY SMALL FILES > FEW LARGE FILES:
- High cohesion, low coupling
- 200-400 lines typical, 800 max
…
```

Body is conventional markdown — prose, headings, code blocks, lists.
No required body sections; the only structural rule is "give the agent
context the way you'd brief a new engineer."

## Cross-doc reference scheme

Kiro has **three distinct cross-reference mechanisms**, each scoped to
a specific link relationship:

1. **Spec-internal back-reference (`tasks.md` → `requirements.md`).**
   Per-task italic trailing line: `_Requirements: 1.2, 3.4_`. The
   reference target is the **numbered list item** in
   `requirements.md` — by integer, not by slug or ID. If the
   requirements list reorders, all references break silently.

2. **Steering → live workspace file (`#[[file:<path>]]`).** Kiro
   resolves the path at load time and embeds the file content into the
   steering doc. Path is relative to workspace root. Breaks silently
   on file rename/move.

3. **Chat → steering file (`#<steering-file-name>`).** User-typed
   reference in the chat panel that pulls the named steering file
   into the current conversation. Also reachable via slash commands.
   Used by `inclusion: manual` files to opt them in for one
   conversation.

**No bead-style ID system.** Spec scope units (`<feature-name>/`
directories under `.kiro/specs/`) are addressed by their directory
name — no separate ID, no UUID, no project-key prefix. Two specs
with the same name in different workspaces are two different
specs; there is no global namespace.

**No frontmatter `id:` field** anywhere — neither steering files,
skills, powers, nor specs carry a stable identifier separate from
their filename / path. The path *is* the identifier.

## Lifecycle markers

Kiro is consistent with both BMAD and Superpowers in shipping **no
in-file lifecycle markers** for the doc-types it owns:

- No `status:` frontmatter on any first-party doc-type.
- No `version:` (except hooks, which carry one in JSON, and skills
  which can have an optional `compatibility:` field).
- No `date:` or `created:` frontmatter.
- No filename suffixes like `-draft`, `-final`, `-deprecated`.
- No archive directory or "removals.txt" log.

The single mechanical lifecycle signal Kiro reads from a doc is the
**checkbox state in `tasks.md`**: `- [ ]` is pending, `- [x]` is
complete. The IDE displays per-task progress live based on this. The
docs phrase it as "real-time status updates" — the file *is* the
state.

For specs as a whole, the docs mention a workflow that proceeds
*through* phases (Requirements → Design → Tasks) but provide no
file-level marker for which phase a spec is in. The presence of
`tasks.md` is the signal that a spec has reached the implementation
phase; the presence of `[x]` checkboxes is the signal that
implementation has begun.

For steering, the inclusion mode is sometimes used as a soft
lifecycle signal in practice (`inclusion: manual` for "experimental,
opt-in only"; promote to `inclusion: auto` once the description is
solid; promote to `inclusion: always` once it's load-bearing).
This is not documented as such — it is an emergent convention.

## Central vs local documents

Kiro's `.kiro/` tree splits cleanly into **central** (project-wide,
refreshed in place) and **local** (single piece of work,
write-once-then-frozen) by directory:

| Directory                  | Central / local | Reasoning                                                                                                       |
| -------------------------- | --------------- | --------------------------------------------------------------------------------------------------------------- |
| `.kiro/steering/`          | **Central**     | Persistent context, refreshed in place as the codebase evolves. `product.md` / `tech.md` / `structure.md` are the strongest "central" instances — there's only ever one of each. |
| `.kiro/skills/`            | **Central**     | Each skill is a reusable package, refreshed in place. Skill is keyed by name, not by occasion.                  |
| `.kiro/settings/mcp.json`  | **Central**     | Single configuration file; updated as servers come and go.                                                      |
| `.kiro/hooks/`             | **Central**     | Each hook is a long-lived automation rule, refreshed in place; not tied to a single piece of work.              |
| `.kiro/specs/<feature>/`   | **Local**       | Each spec is a discrete piece of work. Best-practices doc explicitly recommends one spec per feature, not a single project-wide spec. |

`.kiro/specs/` is the only "local" tier in the Kiro-defined doc set.
Everything else is central. There is no `_archive/`, no
`docs/proposals/`, no scratch directory — Kiro inherits the same
single-tier philosophy as BMAD and Superpowers for non-spec content.

The **boundary criterion Kiro uses to decide central vs local**:
*Does this document describe an ongoing piece of work, or does it
describe the codebase / agent's behavior?* The former goes in
`specs/<feature>/`; the latter goes in `steering/`, `skills/`,
`hooks/`, or `settings/`.

## Project / feature scope unit

The unit of work is a **spec**, which scopes to either a *feature* or
a *bug*. The best-practices doc is explicit:

> "We recommend creating multiple specs for different features for
> your project rather than attempting to just have a single one for
> your entire codebase."

Example feature names from the docs:
`user-authentication`, `product-catalog`, `shopping-cart`,
`payment-processing`, `admin-dashboard`. Naming convention:
**lowercase-kebab feature noun phrases**.

Per-spec doc count: **3 files** (or 3 with `bugfix.md` substituting
for `requirements.md`). All three live in the same flat directory —
no `requirements/`, `design/`, `tasks/` sub-folders. The directory
name is the scope unit, the filenames are the artifact within it.

There is no notion of "epic" above feature, no notion of "user story"
below feature *as separate files* — user stories live as numbered
list items inside `requirements.md`. The hierarchy is:

```
spec (= feature directory)
├── (3-4 docs as siblings, fixed filenames)
└── (numbered requirements / numbered tasks within them)
```

Hooks attach to spec scope at the task boundary (Pre/Post Task
Execution events) but not at the spec boundary directly.

## Planning vs implementation split

Both planning and implementation artifacts live **in the same spec
directory** under `.kiro/specs/<feature>/`. There is no separate
`docs/plans/` / `docs/implementation/` split as Superpowers has.

The split is *temporal and per-file* rather than *spatial*:

- Planning artifacts: `requirements.md`, `design.md`
- Implementation tracking: `tasks.md` (checkboxes track progress)
- Implementation code: lives in the actual codebase, outside `.kiro/`

The spec directory is therefore "the planning + tracking *for* this
feature, not the code *of* this feature." Code never lives in
`.kiro/specs/`.

This is a **central design choice**: a feature's three docs travel
together as a unit. You don't move `tasks.md` to a different
directory once implementation starts; the same `tasks.md` evolves
from "all `[ ]`" to "all `[x]`" in place.

## Well-named patterns (with reasoning)

1. **Single hidden top-level directory `.kiro/`.** All Kiro state — docs,
   config, skills, hooks, settings — lives under one path. Reasoning:
   one directory to add to `.gitignore` if you don't want to commit
   it (or to commit wholesale if you do); one path to migrate if you
   move tools; clear ownership boundary. Compare with VS Code's `.vscode/`
   and Cursor's `.cursor/` — same pattern.

2. **Workspace `.kiro/` mirrored by global `~/.kiro/`.** Identical
   sub-tree shapes (`steering/`, `skills/`, `settings/`) with
   workspace-precedence-on-conflict. Reasoning: users learn one layout
   and apply it twice. Per-workspace overrides Just Work without a
   separate "user vs project" config schema.

3. **Fixed three-file spec layout** (`requirements.md`, `design.md`,
   `tasks.md`). Reasoning: every spec is grep-able the same way; the
   IDE knows where to look for tasks; readers always know which file
   has which content. Cost of fixed names is zero because every
   feature directory is its own namespace.

4. **`.kiro.hook` double-extension for hooks.** The `.kiro` part is
   unambiguous to Kiro's discovery (anything ending `.kiro.hook`),
   the `.hook` part hints "this is a hook" to humans, and the
   basename can be anything kebab-case. Reasoning: one extension
   carries both the editor-syntax hint (JSON via `.hook` ≈ JSON
   convention) and the discovery key.

5. **`#[[file:<path>]]` reference syntax in steering.** The double-bracket
   wrapper is uncommon enough to never collide with normal markdown.
   The `file:` prefix is namespaced for future expansion (steering
   could later add `#[[skill:<name>]]` or `#[[spec:<name>]]` without
   ambiguity). Reasoning: future-proofed, parser-friendly, visually
   distinct from normal links.

6. **Inclusion modes as a 4-way enum, not bools.** `always` /
   `fileMatch` / `manual` / `auto` covers the meaningful loading
   strategies without exploding into a settings page. Reasoning: a
   single field with four named values is easier to teach than four
   booleans (which would allow contradictory combinations).

7. **`SKILL.md` and `POWER.md` as uppercase entrypoint filenames.**
   Both inherit the Agent Skills standard's `SKILL.md` convention.
   Sorts to top in `ls`; visually distinct from neighboring lowercase
   reference files. Reasoning: same as Superpowers — a folder is a
   namespace, the entrypoint should be obvious.

8. **`tasks.md` checkbox state IS the lifecycle.** `- [ ]` vs `- [x]`
   doubles as both human display and machine-readable progress. No
   separate "status field" needed; nothing to keep in sync.
   Reasoning: the simplest possible representation that covers both
   the user's view and the agent's view.

9. **Foundational vs custom steering distinction is purely
   convention** (`product.md` / `tech.md` / `structure.md` happen to
   exist by default; everything else is custom). Reasoning: Kiro
   doesn't need a registry — file presence is the signal. Removing
   the foundational files removes the foundational context; adding
   custom files adds custom context. Symmetric.

10. **Spec feature names are noun-phrase kebab-case**
    (`user-authentication`, `payment-processing`, `admin-dashboard`).
    Reasoning: maps directly to the user-facing feature label, makes
    the directory name self-explanatory in `ls .kiro/specs/`.

11. **`inclusion: auto` description discipline is the same "Use when …"
    discipline Superpowers documents for skills.** A steering file
    declared `inclusion: auto` exposes its `description:` to the
    agent's request-matching, so the description must read like a
    triggering condition, not a summary. Reasoning: Kiro doesn't
    document this explicitly but the mechanism is identical to Skills.

## Awkward patterns (with reasoning)

1. **First-party docs are markedly thin on file shapes.** The
   Specs page describes `requirements.md` / `design.md` / `tasks.md`
   without quoting any verbatim section structure or showing an
   example. Most concrete examples come from community templates
   (jasonkneen/kiro), which aren't first-party. Cost: a new user
   building a spec from kiro.dev alone has to guess the format.
   The IDE may generate the format implicitly, but readers of this
   research doc are reading docs, not driving the IDE.

2. **`tasks.md` cross-references `requirements.md` by raw integer
   only** (`_Requirements: 1.2, 3.4_`). If the requirements list
   reorders, every cross-reference breaks silently. There's no slug,
   no anchor, no UUID. Cost: refactoring `requirements.md` is a
   trap.

3. **The `<name>.md` companion to `<name>.json` for CLI custom
   agents** (observed in the wild) duplicates content — both files
   carry name, description, allowedTools, and the prompt body. The
   docs apparently treat the JSON as canonical, so the MD must be
   kept in sync manually. Cost: an undocumented community
   convention that creates a sync hazard.

4. **Powers don't have a documented filesystem location.** Skills go
   to `.kiro/skills/`, hooks to `.kiro/hooks/`, steering to
   `.kiro/steering/` — but the Powers docs don't pin a path. The
   install path is implicit ("Kiro automatically registers the MCP
   server in your `~/.kiro/settings/mcp.json`") rather than the
   bundle's home directory being named. Cost: undiscoverable on
   disk; users must rely on the IDE for management.

5. **AGENTS.md can live in two places** (workspace root *or*
   `.kiro/steering/`), and "always included" with no inclusion mode.
   Cost: a workspace-root `AGENTS.md` is invisible from the
   `.kiro/steering/` panel; users can be surprised that it's
   loaded. The split-location convention exists to honor the
   external standard but creates two places to look.

6. **Two paired-doc patterns coexist for specs and bugfixes.** Feature
   spec uses `requirements.md` + `design.md` + `tasks.md`; bugfix spec
   uses `bugfix.md` + `design.md` + `tasks.md`. The variant-by-first-
   filename pattern is asymmetric — the bug version doesn't share its
   filename with the feature version, but both call the second file
   `design.md`. Cost: cross-spec scripts have to handle "either
   `requirements.md` or `bugfix.md`" branching.

7. **No date or version field in steering frontmatter** despite the
   doc explicitly recommending "treat steering changes like code
   changes — require reviews." A reader looking at a steering file
   has no in-file evidence of when it was last meaningfully revised
   short of `git log`. Cost: drift between intended and actual
   recency is invisible from the file.

8. **Hook trigger names diverge between docs and config.** Docs use
   "Pre Tool Use" / "File Save" (display names with spaces); JSON
   config uses `preToolUse` / `fileEdited` (camelCase, sometimes a
   different stem entirely — note `fileEdited` vs the doc's "File
   Save"). Cost: constructing a hook by hand requires translating
   between display and config naming.

9. **`agents/`, `docs/`, `scripts/` sub-directories under `.kiro/`
   appear in user repos but are not part of Kiro's documented
   layout** (CLI custom agents are documented separately; the others
   are pure user convention). Cost: a reader inheriting a `.kiro/`
   tree can't tell which sub-directories are Kiro-defined and which
   are conventions of the previous owner.

10. **Best-practices doc says "version-controlled" without prescribing
    a `.gitignore` policy.** Some teams commit `.kiro/` (so steering
    travels with the repo), others gitignore it (treating it as
    user-local IDE state). Cost: no canonical answer means each team
    re-litigates this on day one.

11. **Spec phase progression is implicit from file presence.** "Has
    `tasks.md` been created yet?" is the only signal that planning
    is done and implementation has started. No frontmatter, no log
    file, no marker. Cost: a half-finished design (`design.md`
    exists but is incomplete) is indistinguishable on disk from a
    done design.

## Stated rationale

Direct quotes from Kiro's docs, paired with what Kiro is optimising for.

**On steering's purpose** (`/docs/steering/`):

> "Steering gives Kiro persistent knowledge about your workspace
> through markdown files. Instead of explaining your conventions in
> every chat, steering files ensure Kiro consistently follows your
> established patterns, libraries, and standards."

**On loading-mode discipline** (same page, paraphrased through the
inclusion-mode table): every steering file declares its loading
strategy explicitly so users can balance "always-on context" against
"context-window budget."

**On per-feature spec scope** (`/docs/specs/best-practices/`):

> "We recommend creating multiple specs for different features for
> your project rather than attempting to just have a single one for
> your entire codebase. This approach allows you to work on features
> independently without conflicts and maintain focused, manageable
> spec documents."

**On EARS as the requirements format** (`/docs/specs/feature-specs/`):

> "WHEN [condition/event] THE SYSTEM SHALL [expected behavior]"

The benefits the docs claim for EARS are clarity, testability,
traceability, and completeness — i.e. requirements written this way
are easier for the agent to translate into testable acceptance
criteria.

**On Skills vs Steering vs Powers** (`/docs/skills`):

> "Skills are portable packages following an open standard…
> Steering is Kiro-specific context that shapes agent behavior…
> Powers bundle MCP tools with knowledge and workflows."

The trichotomy is explicit: same surface (markdown with frontmatter),
three different loading models and portability stories.

**On AGENTS.md compatibility** (`/docs/steering/`):

> "AGENTS.md files are in markdown format, similar to Kiro steering
> files; however, AGENTS.md files do not support inclusion modes and
> are always included."

Kiro accepts the external standard while making the trade-off
explicit: portability across tools costs you the inclusion-mode
control you'd get from a native steering file.

**On hooks bridging into specs** (`/docs/hooks/types/`):

> "Pre Task Execution — Triggers before a spec task begins execution"
> "Post Task Execution — Triggers after a spec task completes execution"

The only documented mechanism that ties hooks to specs is the per-task
boundary, not the per-spec boundary. Kiro is choosing the *task* as
the unit of automation, not the *spec*.

## Notes for the synthesis bead

Surfacing for gc-toolkit's default-location decision:

1. **The `.kiro/` "single hidden top-level directory" pattern is
   different from the BMAD / Superpowers convention of using
   `docs/` and `src/skills/`.** It's a credible third option for
   gc-toolkit: a `.gc/` tree that holds all gc-toolkit-managed
   docs (escalation research, principles, ADRs, plans). gc-toolkit
   already has `.gc/` for runtime state — extending it to also hold
   gc-toolkit-managed docs would unify "machine state" and "agent-
   facing docs" but might surprise users who expect docs in `docs/`.

2. **Three-file flat spec directories (`requirements.md` / `design.md`
   / `tasks.md`) is a strong pattern for gc-toolkit's per-feature
   work.** It maps cleanly onto the planning-then-implementation arc.
   The bigger decision: do gc-toolkit specs live under `docs/specs/`,
   `.kiro/specs/`-style under `.gc/specs/`, or alongside the bead
   that drives them? Beads already track work — a per-bead `specs/`
   directory might collapse the spec-vs-bead-id question.

3. **Steering's four inclusion modes are the most novel idea here.**
   gc-toolkit doesn't currently have a "loaded conditionally based on
   what file you're editing" mechanism for principle / convention
   docs. If gc-toolkit ships principles, steering-style inclusion
   could be valuable — but it requires every consumer (every agent
   harness) to honor the field. Worth examining whether to adopt
   `inclusion:` as a frontmatter convention even if only one or two
   harnesses currently understand it.

4. **`AGENTS.md` is a real cross-tool standard.** gc-toolkit already
   ships `CLAUDE.md` files; adding `AGENTS.md` as either a real file
   or a symlink (Superpowers' approach) buys cross-IDE compatibility
   for free. Worth bundling with the synthesis output.

5. **Steering's `#[[file:<path>]]` live-file embed is worth
   considering.** gc-toolkit's principles or rationale docs that
   reference real source files could embed them this way and avoid
   restating-then-staling. The downside is renaming the embedded
   file silently breaks the doc — same trap Kiro carries.

6. **Tasks-by-checkbox lifecycle is concrete and minimal.** If
   gc-toolkit ever ships planning-doc artifacts that humans and
   agents share, "checkbox state IS the status" is cheaper than any
   frontmatter scheme. Already used informally in many gc-toolkit
   docs; could be formalised.

7. **Two-tier scope (workspace `.kiro/` vs global `~/.kiro/`) with
   workspace-precedence is worth borrowing for any gc-toolkit
   convention that spans both rig-local and user-global state.**
   gc-toolkit's `~/.claude/` ↔ rig-`.gc/` distinction is the
   analog; the precedence rule (workspace wins on conflict) is the
   pattern to make explicit.

8. **Foundational doc trio (`product.md` / `tech.md` /
   `structure.md`) is a tight default starter set.** If gc-toolkit
   ships an `init` skill that scaffolds a new rig's docs, three
   foundational files is a reasonable starting bundle (whatever they
   end up being called). The "auto-generate from workspace scan"
   path is worth considering for gc-toolkit's own bootstrap.

9. **No `id:` frontmatter, no separate UUID — path is the
   identifier.** Both Superpowers and Kiro converge here. gc-toolkit
   wanting to use bead-IDs (`tk-*`) as cross-doc identifiers is a
   *departure* from both reference projects, not a borrow. The
   trade-off is portability (paths can move; bead-IDs are stable)
   vs simplicity (paths are obvious; bead-IDs require a registry).

10. **Kiro's "no archive directory" convention matches BMAD and
    Superpowers.** All three reference projects converge on
    "in-main = adopted; deletion is the only retirement path." If
    gc-toolkit wants a research / ideation / adopted / archival
    tier (its existing `docs/escalation/research/` suggests yes),
    this is a *gc-toolkit-specific departure* from all three
    surveyed projects — worth flagging in the synthesis.

11. **Markdown + YAML frontmatter is the universal substrate.** All
    three surveyed projects (BMAD, Superpowers, Kiro) use
    `---YAML---` frontmatter on instruction-bearing docs. The
    fields differ but the format is identical. gc-toolkit can
    safely commit to "all gc-toolkit doc-types use YAML
    frontmatter" without departing from any reference project.

12. **Hook JSON with `when` / `then` discriminated unions is a
    cleaner config schema than ad-hoc YAML.** If gc-toolkit ships
    automation rules, the `{when: {type, …}, then: {type, …}}`
    shape is portable and well-typed. Worth borrowing for any
    declarative-trigger config gc-toolkit needs.
