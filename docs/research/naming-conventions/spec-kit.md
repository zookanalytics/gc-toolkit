# Spec Kit — document templates and recording locations

Survey of **GitHub Spec Kit** (github.com/github/spec-kit), the open-source
toolkit for **Spec-Driven Development (SDD)**, with focus on **output
document types and where they get recorded**.

## Provenance

All sources surveyed at upstream commit
`0f2655181400defdac6904a9461f58a7416d4d72`
("feat: improve catalog submission templates and CODEOWNERS (#2401)").
Default branch `main`.

| Doc-type                                | Producer (Spec Kit command / mechanism)             | Source location (path inside `github/spec-kit`)                                          | Surveyed at |
| --------------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------- | ----------- |
| Feature spec — `spec.md`                | `/speckit.specify` slash command                    | `templates/spec-template.md`, `templates/commands/specify.md`                            | 2026-05-05  |
| Implementation plan — `plan.md`         | `/speckit.plan` slash command                       | `templates/plan-template.md`, `templates/commands/plan.md`                               | 2026-05-05  |
| Tasks — `tasks.md`                      | `/speckit.tasks` slash command                      | `templates/tasks-template.md`, `templates/commands/tasks.md`                             | 2026-05-05  |
| Research — `research.md`                | `/speckit.plan` (Phase 0)                           | `templates/commands/plan.md`                                                             | 2026-05-05  |
| Data model — `data-model.md`            | `/speckit.plan` (Phase 1)                           | `templates/commands/plan.md`                                                             | 2026-05-05  |
| Quickstart — `quickstart.md`            | `/speckit.plan` (Phase 1)                           | `templates/commands/plan.md`                                                             | 2026-05-05  |
| Contracts directory — `contracts/`      | `/speckit.plan` (Phase 1)                           | `templates/commands/plan.md`, `templates/plan-template.md`                               | 2026-05-05  |
| Checklist — `checklists/<domain>.md`    | `/speckit.checklist` slash command                  | `templates/checklist-template.md`, `templates/commands/checklist.md`                     | 2026-05-05  |
| Spec quality checklist — `requirements.md` | `/speckit.specify` (validation step)             | `templates/commands/specify.md` step 7                                                   | 2026-05-05  |
| Constitution — `constitution.md`        | `/speckit.constitution` slash command               | `templates/constitution-template.md`, `templates/commands/constitution.md`               | 2026-05-05  |
| Command file (Markdown)                 | Command authoring (core/extension/preset)           | `templates/commands/*.md`                                                                | 2026-05-05  |
| Template file                           | Template authoring (core/extension/preset/override) | `templates/*.md`                                                                         | 2026-05-05  |
| Agent context file (`CLAUDE.md`/`AGENTS.md`/etc.) | `specify init` (per integration class)    | `src/specify_cli/integrations/*/__init__.py` (`context_file` attribute)                  | 2026-05-05  |
| Feature pointer — `feature.json`        | `/speckit.specify` step 3                           | `templates/commands/specify.md`                                                          | 2026-05-05  |
| Init options — `init-options.json`      | `specify init`                                      | referenced by `templates/commands/specify.md` for `branch_numbering`                     | 2026-05-05  |
| Extensions config — `extensions.yml`    | `specify extension add` / manual                    | referenced by every `templates/commands/*.md` "Pre-Execution Checks" block               | 2026-05-05  |
| Extension definition                    | Extension author                                    | `extensions/<id>/extension.yml` + `extensions/<id>/commands/*.md`                        | 2026-05-05  |
| Preset definition                       | Preset author                                       | `presets/<id>/preset.yml` + `presets/<id>/templates/` + `presets/<id>/commands/`         | 2026-05-05  |

The bead asks the question "where does each Spec Kit doc-type get recorded
by default" — every row above answers that for one Spec Kit mechanism.

## Sources surveyed

- Repository: `github/spec-kit` at commit
  `0f2655181400defdac6904a9461f58a7416d4d72` (cloned to
  `/tmp/spec-kit-survey/spec-kit/`).
- Files read in full or in part:
  - `spec-driven.md` — full text (the SDD methodology essay; the in-repo
    canonical statement of philosophy)
  - `README.md` — first 100 lines (overview, install, philosophy)
  - `AGENTS.md` — full text (how integrations are added)
  - `templates/spec-template.md` — full text
  - `templates/plan-template.md` — full text
  - `templates/tasks-template.md` — full text
  - `templates/constitution-template.md` — full text
  - `templates/checklist-template.md` — full text
  - `templates/vscode-settings.json` — full text
  - `templates/commands/specify.md` — full text
  - `templates/commands/plan.md` — full text
  - `templates/commands/tasks.md` — full text
  - `templates/commands/clarify.md` — full text
  - `templates/commands/checklist.md` — full text
  - `templates/commands/analyze.md` — full text
  - `templates/commands/constitution.md` — full text
  - `templates/commands/implement.md` — full text
  - `templates/commands/taskstoissues.md` — full text
  - `docs/quickstart.md` — full text
  - `docs/reference/core.md` — full text
  - `docs/reference/overview.md` — full text
  - `scripts/bash/setup-plan.sh` — full text
  - `scripts/bash/common.sh` — full text
  - `scripts/bash/create-new-feature.sh` — first 100 lines
- Directory listings inspected: `templates/`, `templates/commands/`,
  `docs/`, `docs/reference/`, `scripts/bash/`, `scripts/powershell/`,
  `extensions/`, `presets/`, `src/`.

## Output document types — inventory

Spec Kit's output documents fall into two clean tiers based on lifetime
and scope:

**A. Per-feature artifacts** — written into `specs/<NNN>-<short-name>/`
(or `specs/<YYYYMMDD-HHMMSS>-<short-name>/`). Each is single-piece-of-work
local; one set per feature directory.

**B. Project-wide artifacts** — written into `.specify/` (toolkit-managed
state) or the workspace root (agent-facing). Refreshed in place; one per
project.

Concrete files (with Spec Kit-defined defaults):

| Tier | File / dir                                              | Default location                                  | Producer                      | Format                                  |
| ---- | ------------------------------------------------------- | ------------------------------------------------- | ----------------------------- | --------------------------------------- |
| A    | `spec.md`                                               | `specs/<feature>/spec.md`                         | `/speckit.specify`            | Markdown (no frontmatter)               |
| A    | `plan.md`                                               | `specs/<feature>/plan.md`                         | `/speckit.plan`               | Markdown (no frontmatter)               |
| A    | `tasks.md`                                              | `specs/<feature>/tasks.md`                        | `/speckit.tasks`              | Markdown (frontmatter present)          |
| A    | `research.md`                                           | `specs/<feature>/research.md`                     | `/speckit.plan` Phase 0       | Markdown (no frontmatter)               |
| A    | `data-model.md`                                         | `specs/<feature>/data-model.md`                   | `/speckit.plan` Phase 1       | Markdown (no frontmatter)               |
| A    | `quickstart.md`                                         | `specs/<feature>/quickstart.md`                   | `/speckit.plan` Phase 1       | Markdown (no frontmatter)               |
| A    | `contracts/` (directory)                                | `specs/<feature>/contracts/`                      | `/speckit.plan` Phase 1       | Per-contract: API/event/grammar files   |
| A    | `checklists/<domain>.md`                                | `specs/<feature>/checklists/<domain>.md`          | `/speckit.checklist`          | Markdown (no frontmatter)               |
| A    | `checklists/requirements.md`                            | `specs/<feature>/checklists/requirements.md`      | `/speckit.specify` validation | Markdown (no frontmatter)               |
| B    | `constitution.md`                                       | `.specify/memory/constitution.md`                 | `/speckit.constitution`       | Markdown + version-line footer          |
| B    | `feature.json`                                          | `.specify/feature.json`                           | `/speckit.specify` step 3     | JSON (single key: `feature_directory`)  |
| B    | `init-options.json`                                     | `.specify/init-options.json`                      | `specify init`                | JSON (e.g., `branch_numbering`)         |
| B    | `extensions.yml`                                        | `.specify/extensions.yml`                         | `specify extension add` etc.  | YAML (declares hooks per command phase) |
| B    | Templates (`spec-template.md`, `plan-template.md`, etc.)| `.specify/templates/<name>-template.md`           | `specify init` (copies core)  | Markdown (mostly no frontmatter)        |
| B    | Command files (`speckit.<verb>.md`)                     | `.specify/templates/commands/*.md` (core), and `<integration-folder>/<commands_subdir>/*` (per integration: `.claude/commands/`, `.gemini/commands/`, etc.) | `specify init` per integration | Markdown / TOML / YAML                  |
| B    | Agent context file (e.g., `CLAUDE.md`, `AGENTS.md`)     | Workspace root or per-integration path            | `specify init` per integration | Markdown                                |
| B    | Extension definition                                    | `.specify/extensions/<id>/extension.yml` + `commands/` + `templates/` | `specify extension add`        | YAML + Markdown                         |
| B    | Preset definition                                       | `.specify/presets/<id>/preset.yml` + `templates/` + `commands/` | `--preset <id>` at init        | YAML + Markdown                         |

`/speckit.implement`, `/speckit.analyze`, `/speckit.clarify`, and
`/speckit.taskstoissues` are commands that **mutate existing per-feature
artifacts** (mainly `tasks.md` and `spec.md`) rather than producing
new doc-types. `/speckit.taskstoissues` additionally produces external
GitHub Issues — outside the filesystem entirely.

## Per-template detail

### Feature spec — `spec.md` (`templates/spec-template.md`)

**Frontmatter:** none. The template starts directly with the H1.

**Top-of-file metadata block** (immediately after the H1, formatted as
bold-key lines, not YAML):

```markdown
# Feature Specification: [FEATURE NAME]

**Feature Branch**: `[###-feature-name]`
**Created**: [DATE]
**Status**: Draft
**Input**: User description: "$ARGUMENTS"
```

Note: `**Status**: Draft` is the **only** lifecycle marker on any first-party
Spec Kit doc, and it is documented as a literal field — there is no
documented set of legal status values beyond this default.

**Mandatory body sections** (the template's section structure, preserved
in order, all marked `*(mandatory)*` in the template itself):

1. **User Scenarios & Testing** — one or more `### User Story N - <Title> (Priority: P1|P2|P3)` blocks, each containing:
   - `[Describe this user journey in plain language]`
   - `**Why this priority**:`
   - `**Independent Test**:`
   - `**Acceptance Scenarios**:` — numbered list of `**Given** … **When** … **Then** …` lines
   - **`### Edge Cases`** subsection with bullet questions (`What happens when …?`, `How does system handle …?`)
2. **Requirements**
   - `### Functional Requirements` — bullets numbered `**FR-001**`, `**FR-002**`, … using `System MUST` / `Users MUST be able to` phrasing
   - `### Key Entities *(include if feature involves data)*` — bullets per entity, each with role + key attributes
3. **Success Criteria** — `### Measurable Outcomes` — bullets numbered `**SC-001**`, `**SC-002**`, … each "technology-agnostic and measurable"
4. **Assumptions** — bullets capturing reasonable defaults

**Marker syntax for unresolved decisions:** `[NEEDS CLARIFICATION: specific question]`
inserted inline in any FR-### bullet (or elsewhere). The `/speckit.specify`
command caps these at **3 markers maximum** per spec.

**Marker syntax for incomplete sections:** `<!-- ACTION REQUIRED: ... -->`
HTML comments inserted by the template, which the LLM is expected to remove
once the section is filled.

**Cross-doc references this file emits:** none documented (the spec is
the upstream source). Downstream files (`tasks.md`) reference it by FR-###
and User Story labels (`US1`, `US2`).

**Real example** — none in-repo. The template file is the only spec-shaped
artifact shipped; no `examples/` directory.

### Implementation plan — `plan.md` (`templates/plan-template.md`)

**Frontmatter:** none. The template starts directly with the H1.

**Top-of-file metadata** (bold-key lines):

```markdown
# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]
**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`
```

The `**Spec**: [link]` field is the documented cross-reference back to
`spec.md` — implemented as a markdown link, not a stable ID.

**Body sections** (in order):

1. **Summary** — extracted from the feature spec
2. **Technical Context** — labeled paragraph block (`Language/Version`, `Primary Dependencies`, `Storage`, `Testing`, `Target Platform`, `Project Type`, `Performance Goals`, `Constraints`, `Scale/Scope`); unknowns are marked `NEEDS CLARIFICATION`
3. **Constitution Check** — `*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*` Gates determined from the project's `.specify/memory/constitution.md`
4. **Project Structure**
   - `### Documentation (this feature)` — fixed `text` block enumerating sibling files (`plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `contracts/`, `tasks.md`)
   - `### Source Code (repository root)` — three numbered "Option" trees (Single project / Web app / Mobile + API) of which the LLM picks one and deletes the others
   - `**Structure Decision**:` paragraph
5. **Complexity Tracking** — table of `Violation | Why Needed | Simpler Alternative Rejected Because` rows; **only filled when the Constitution Check has unjustified violations**

**Phase model** baked into the plan template's docstring:

| Phase | Outputs                                                |
| ----- | ------------------------------------------------------ |
| 0     | `research.md`                                          |
| 1     | `data-model.md`, `quickstart.md`, `contracts/`         |
| 2     | `tasks.md` (NOT created by `/speckit.plan` — left to `/speckit.tasks`) |

**Cross-doc references this file emits:** the `**Spec**:` link in the
metadata block; references to sibling files in the `Project Structure`
tree (which act as a static manifest of what `/speckit.plan` is expected
to have produced).

### Tasks — `tasks.md` (`templates/tasks-template.md`)

**Frontmatter:** YES — this is the only first-party template that ships
with YAML frontmatter:

```yaml
---

description: "Task list template for feature implementation"
---
```

(Note the blank line after `---`; it is part of the literal template file.)

**Top-of-file metadata block** (bold-key lines after the H1):

```markdown
# Tasks: [FEATURE NAME]

**Input**: Design documents from `/specs/[###-feature-name]/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: The examples below include test tasks. Tests are OPTIONAL - only include them if explicitly requested in the feature specification.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.
```

**Task line format — strictly enforced** by `templates/commands/tasks.md`:

```text
- [ ] [TaskID] [P?] [Story?] Description with file path
```

Components:
- `- [ ]` literal markdown checkbox (becomes `- [X]` or `- [x]` when complete)
- `T###` sequential ID, **execution order** (T001, T002, T003, …)
- `[P]` optional parallelizability flag (different files, no dependencies)
- `[US1]`, `[US2]`, … user-story label, **required for user-story phase tasks**, **forbidden** for Setup / Foundational / Polish phases
- Description ending with the exact file path

The `tasks.md` command file lists explicit `✅ CORRECT` / `❌ WRONG`
examples for the format, and includes a "Format validation" step in its
report.

**Phase structure** (the template is grouped into these phases):

| Phase                       | Story label | Purpose                                                          |
| --------------------------- | ----------- | ---------------------------------------------------------------- |
| 1: Setup                    | none        | Project initialization, basic structure                          |
| 2: Foundational             | none        | Blocking prerequisites — MUST complete before any user story     |
| 3+: User Story 1, 2, 3, …   | `[US1]`+    | One phase per user story in priority order; independently testable |
| N (final): Polish           | none        | Cross-cutting concerns                                            |

Each user-story phase has explicit **Checkpoint** lines marking the
"this story should be fully functional and testable independently" boundary.

**Sub-sections inside a user-story phase:**

- `### Tests for User Story N (OPTIONAL - only if tests requested) ⚠️`
- `### Implementation for User Story N`

The "tests are optional" treatment is itself a documented stance —
the template explicitly notes "Tests are OPTIONAL - only include them
if explicitly requested in the feature specification."

**Trailing sections** (project-wide, after the per-phase blocks):

- `## Dependencies & Execution Order`
- `## Parallel Example: User Story 1` — bash code block of `Task: "..."` lines
- `## Implementation Strategy` — three sub-headings (`### MVP First`, `### Incremental Delivery`, `### Parallel Team Strategy`)
- `## Notes`

**Lifecycle signal:** the checkbox state IS the per-task status.
`/speckit.implement` step 8 explicitly says "For completed tasks, make
sure to mark the task off as `[X]` in the tasks file."

**Cross-doc references this file emits:**
- `[US1]` etc. labels reference user-story numbers in `spec.md`
- File paths in task descriptions reference real source files (`src/models/user.py`, `tests/contract/test_X.py`)
- The metadata block references `spec.md` and `plan.md` by relative path

### Research, data-model, quickstart, contracts/ (Phase 0/1 outputs)

These four artifacts are documented in `templates/commands/plan.md`
and the `Project Structure` block of `templates/plan-template.md`,
but **none of them ship with a template file**. `/speckit.plan` is
expected to author them inline based on the documented format.

**`research.md`** — Phase 0 output. Format documented as:

```text
- Decision: [what was chosen]
- Rationale: [why chosen]
- Alternatives considered: [what else evaluated]
```

One section per researched unknown. The plan command says:
"For each NEEDS CLARIFICATION → research task; For each dependency →
best practices task; For each integration → patterns task."

**`data-model.md`** — Phase 1 output. Format documented as:
"Entity name, fields, relationships; Validation rules from requirements;
State transitions if applicable." No template; the LLM authors the
entity-by-entity layout.

**`quickstart.md`** — Phase 1 output. Documented as a "quickstart guide
capturing key validation scenarios." No template.

**`contracts/`** — Phase 1 output **directory**. Documented as:
"Identify what interfaces the project exposes to users or other
systems; Document the contract format appropriate for the project type."
Examples enumerated: "public APIs for libraries, command schemas for
CLI tools, endpoints for web services, grammars for parsers, UI contracts
for applications." Skipped if the project is "purely internal."

**Cross-doc references emitted:** all four are referenced by
`tasks.md` generation (the `tasks` command reads "data-model.md
(entities), contracts/ (interface contracts), research.md (decisions),
quickstart.md (test scenarios)" to derive tasks).

### Checklist — `<domain>.md` and `requirements.md` (`templates/checklist-template.md`)

**Frontmatter:** none. Template starts at the H1.

**Top-of-file metadata** (bold-key lines):

```markdown
# [CHECKLIST TYPE] Checklist: [FEATURE NAME]

**Purpose**: [Brief description of what this checklist covers]
**Created**: [DATE]
**Feature**: [Link to spec.md or relevant documentation]

**Note**: This checklist is generated by the `/speckit.checklist` command...
```

**Body** — sections grouped by `## [Category N]`, each containing
checkbox-numbered items:

```markdown
## [Category 1]

- [ ] CHK001 First checklist item with clear action
- [ ] CHK002 Second checklist item
- [ ] CHK003 Third checklist item
```

`CHK###` is the **globally incrementing** ID (continues across appends
to the same file). Checkbox state is the lifecycle signal — `[ ]`
incomplete, `[X]`/`[x]` complete.

**Filename convention:** **short, descriptive, kebab-case** based on the
domain — `ux.md`, `api.md`, `security.md`, `performance.md`, `test.md`.
The command explicitly enumerates these as canonical examples.

**Special checklist:** `requirements.md` — auto-generated by
`/speckit.specify` step 7 (Specification Quality Validation) into
`specs/<feature>/checklists/requirements.md`. This is the **only**
checklist with a fixed filename. Purpose: "Validate specification
completeness and quality before proceeding to planning." The
items are about the *requirements themselves* — completeness, clarity,
testability — not implementation behavior.

**Item-quality discipline** — `templates/commands/checklist.md`
devotes most of its body to "Unit Tests for English":

> "Checklists are **UNIT TESTS FOR REQUIREMENTS WRITING** — they
> validate the quality, clarity, and completeness of requirements in
> a given domain."
>
> ❌ NOT "Verify the button clicks correctly"
> ✅ CORRECT "Are visual hierarchy requirements defined for all card types? [Completeness]"

The trailing `[Completeness]`, `[Clarity]`, `[Consistency]`,
`[Coverage]`, `[Edge Cases]`, `[Measurability]`, `[Gap]`, `[Ambiguity]`,
`[Conflict]`, `[Assumption]`, `[Traceability]` markers are the
documented quality-dimension vocabulary.

**Cross-doc references emitted:** `[Spec §FR-001]`, `[Spec §NFR-2]` —
section pointers back to numbered requirements in `spec.md`.

### Constitution — `constitution.md` (`templates/constitution-template.md`)

**Frontmatter:** none. Starts at H1.

**Body sections** (template's section structure):

```markdown
# [PROJECT_NAME] Constitution

## Core Principles
### [PRINCIPLE_1_NAME]
[PRINCIPLE_1_DESCRIPTION]
### [PRINCIPLE_2_NAME]
[PRINCIPLE_2_DESCRIPTION]
…

## [SECTION_2_NAME]   ← e.g. "Additional Constraints" / "Security Requirements"
[SECTION_2_CONTENT]

## [SECTION_3_NAME]   ← e.g. "Development Workflow" / "Quality Gates"
[SECTION_3_CONTENT]

## Governance
[GOVERNANCE_RULES]

**Version**: [CONSTITUTION_VERSION] | **Ratified**: [RATIFICATION_DATE] | **Last Amended**: [LAST_AMENDED_DATE]
```

The template explicitly notes that "the user might require less or more
principles than the ones used in the template" — the principle-count
is not fixed.

**Versioning rules** (from `templates/commands/constitution.md`):
- `CONSTITUTION_VERSION` follows semver
- MAJOR — backward-incompatible governance/principle removals or redefinitions
- MINOR — new principle/section added or materially expanded guidance
- PATCH — clarifications, wording, typo fixes

**Sync Impact Report** — the constitution command prepends an HTML
comment at the top of `constitution.md` after each amendment, listing
version change, modified/added/removed sections, downstream templates
to re-check, and any deferred placeholders.

**Reference example** in the SDD essay (`spec-driven.md`): "The Nine
Articles of Development" — Article I (Library-First), Article II (CLI
Interface Mandate), Article III (Test-First Imperative,
NON-NEGOTIABLE), Articles VII & VIII (Simplicity / Anti-Abstraction),
Article IX (Integration-First Testing).

**Cross-doc references emitted:**
- `Article VII`, `Article VIII`, `Article IX` referenced by name from
  `templates/plan-template.md`'s Constitution Check phase gates
  (e.g., `#### Simplicity Gate (Article VII)`)

### Command files — `.specify/templates/commands/<name>.md`

Spec Kit's slash commands are themselves files. The core set in
`templates/commands/` is **9 files**: `analyze.md`, `checklist.md`,
`clarify.md`, `constitution.md`, `implement.md`, `plan.md`, `specify.md`,
`tasks.md`, `taskstoissues.md`. These get installed under
`<integration-folder>/<commands_subdir>/` for whichever AI-coding-agent
integration the project chose at `specify init` (e.g., `.claude/commands/`,
`.gemini/commands/`, `.github/prompts/` for Copilot, `.windsurf/workflows/`
for Windsurf).

**Frontmatter** is rich and load-bearing — surveyed across all 9 core
commands:

| Field         | Type   | Present in                                             | Semantics                                                            |
| ------------- | ------ | ------------------------------------------------------ | -------------------------------------------------------------------- |
| `description` | string | All 9                                                  | Single-line summary; shown in agent picker                           |
| `handoffs`    | list   | `specify`, `plan`, `tasks`, `clarify`, `constitution`  | Suggests downstream commands; each item: `label`, `agent`, `prompt`, optional `send: true` |
| `scripts`     | dict   | `analyze`, `checklist`, `clarify`, `implement`, `plan`, `tasks`, `taskstoissues` | `sh:` and `ps:` keys with the prerequisite script to run             |
| `tools`       | list   | `taskstoissues` only                                   | Specific tool requirements (e.g., `'github/github-mcp-server/issue_write'`) |

Real example (frontmatter from `templates/commands/specify.md`):

```yaml
---
description: Create or update the feature specification from a natural language feature description.
handoffs:
  - label: Build Technical Plan
    agent: speckit.plan
    prompt: Create a plan for the spec. I am building with...
  - label: Clarify Spec Requirements
    agent: speckit.clarify
    prompt: Clarify specification requirements
    send: true
---
```

`handoffs[].agent` references **another command name** (without the
`.md` suffix). It's the only cross-command-file reference scheme.

**File-naming convention:** core commands live as `<verb>.md` inside
`templates/commands/`. Once installed by an integration, they typically
become `speckit.<verb>.md` or `speckit-<verb>/SKILL.md` (depending on
the integration's `command_filename()` and `commands_subdir`). The
`speckit.` prefix is the **registered namespace**; extension commands
use `speckit.<extension-id>.<verb>.md` (e.g., `speckit.git.commit.md`,
`speckit.git.feature.md` from the `git` extension).

**Body** is the LLM-facing prompt — typically `## Pre-Execution Checks`,
`## Outline` / `## Goal` / `## Execution Steps`, `## Post-Execution Checks`.
The Pre/Post-Execution Check blocks all read `.specify/extensions.yml`
for hooks under `hooks.before_<command>` / `hooks.after_<command>` keys —
a uniform extension point.

**Argument substitution** — `$ARGUMENTS` for Markdown agents,
`{{args}}` for TOML/YAML agents, `{{parameters}}` for Forge. The
substitution is set per integration in `registrar_config["args"]`.

**Script substitution** — `{SCRIPT}` is replaced at install time with
the OS-appropriate script path (`scripts/bash/...sh` or
`scripts/powershell/...ps1`).

### Agent context files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, etc.)

**Producer:** `specify init` writes/updates a per-integration context
file. The path is set on the integration class:

| Integration  | Context file                          |
| ------------ | ------------------------------------- |
| Claude (CLI) | `CLAUDE.md` (workspace root)          |
| Gemini       | `GEMINI.md` (workspace root)          |
| Copilot      | `.github/copilot-instructions.md`     |
| Codex        | `AGENTS.md` (workspace root)          |
| Goose        | `AGENTS.md` (workspace root)          |
| Windsurf     | `.windsurf/rules/specify-rules.md`    |

The base integration setup creates or updates a managed Spec Kit
section inside that file (delimited by `<!-- SPECKIT START -->` /
`<!-- SPECKIT END -->` markers — referenced in `templates/commands/plan.md`
step 3 of Phase 1).

`/speckit.plan` Phase 1 step 3 explicitly says:
> "Update the plan reference between the `<!-- SPECKIT START -->` and
> `<!-- SPECKIT END -->` markers in `__CONTEXT_FILE__` to point to the
> plan file created in step 1 (the IMPL_PLAN path)"

So the agent context file is *also* a cross-doc reference site —
Spec Kit injects a pointer to the active feature's `plan.md` so the
agent loads it on each conversation.

### Configuration files — `.specify/feature.json`, `init-options.json`, `extensions.yml`

**`.specify/feature.json`** — written by `/speckit.specify` step 3:

```json
{
  "feature_directory": "specs/003-user-auth"
}
```

Single-key file. Acts as the **active-feature pointer** for all
downstream commands. `scripts/bash/common.sh:read_feature_json_feature_directory()`
parses it (with `jq` → `python3` → `grep`/`sed` fallback). Replaces
the older "infer feature from git branch name" path; now branch and
spec directory are independent.

**`.specify/init-options.json`** — referenced by `templates/commands/specify.md`
for `branch_numbering`:

```json
{ "branch_numbering": "sequential" }   // or "timestamp"
```

`sequential` (default) gives `001-…`, `002-…`. `timestamp` gives
`20260319-143022-…` — chosen for distributed teams to avoid collisions.

**`.specify/extensions.yml`** — uniform extension point referenced by
*every* core command's Pre/Post-Execution Checks block:

```yaml
hooks:
  before_specify:
    - { extension: …, command: …, optional: true|false, condition: …, prompt: … }
  after_specify: [...]
  before_plan: [...]
  after_plan: [...]
  before_tasks: [...]
  after_tasks: [...]
  before_implement: [...]
  after_implement: [...]
  before_constitution: [...]
  after_constitution: [...]
  before_clarify: [...]
  after_clarify: [...]
  before_analyze: [...]
  after_analyze: [...]
  before_checklist: [...]
  after_checklist: [...]
  before_taskstoissues: [...]
  after_taskstoissues: [...]
```

Each command runs a **dual hook check** (pre + post) against this file.
Hooks may be `optional: true` (suggested) or `optional: false` (mandatory,
auto-executed). The `condition` field is left to the HookExecutor — the
LLM is instructed not to evaluate it.

### Extension definition — `.specify/extensions/<id>/`

Bundle layout from in-repo extensions (`extensions/git/`,
`extensions/template/`, `extensions/selftest/`):

```
.specify/extensions/<id>/
├── extension.yml          # Manifest (name, version, hooks, commands provided)
├── config-template.yml    # Optional per-install config template
├── config.yml             # User-edited copy (after install)
├── README.md              # Required (`extensions/template/README.md` shows shape)
├── CHANGELOG.md           # Recommended
├── LICENSE                # Required
├── commands/
│   └── speckit.<extension-id>.<verb>.md   # E.g. speckit.git.commit.md
└── templates/             # Optional — ext-provided templates
```

The `git` extension (in-repo) ships 5 commands:
`speckit.git.validate.md`, `speckit.git.remote.md`,
`speckit.git.initialize.md`, `speckit.git.feature.md`,
`speckit.git.commit.md`. Naming pattern: `speckit.<ext-id>.<verb>.md`.

Resolution priority for templates is documented in
`docs/reference/presets.md` and implemented in `common.sh:resolve_template()`:
1. `.specify/templates/overrides/` (project-local)
2. `.specify/presets/<id>/templates/` (installed presets, sorted by priority)
3. `.specify/extensions/<id>/templates/`
4. `.specify/templates/` (core)

### Preset definition — `.specify/presets/<id>/`

```
.specify/presets/<id>/
├── preset.yml             # Manifest (id, version, priority, provides)
├── README.md
├── templates/             # Override templates
│   ├── spec-template.md
│   ├── plan-template.md
│   ├── tasks-template.md
│   ├── constitution-template.md
│   └── checklist-template.md
└── commands/              # Override commands (e.g. speckit.specify.md)
    ├── speckit.specify.md
    ├── speckit.plan.md
    └── ...
```

In-repo example presets: `presets/lean/`, `presets/scaffold/`,
`presets/self-test/`. Each can override any subset of templates and
commands; the `preset.yml` `priority` field decides resolution order
when multiple presets apply.

**Composition strategies** (from `common.sh:resolve_template_content()`):
preset templates can declare `strategy: replace | prepend | append | wrap`.
`wrap` requires a `{CORE_TEMPLATE}` placeholder. This is the documented
mechanism that lets a preset *layer onto* the core template instead of
replacing it.

## Cross-doc reference scheme

Spec Kit has **six distinct reference mechanisms**, each scoped to a
specific link relationship:

1. **Plan → Spec (markdown link).** `**Spec**: [link]` in plan.md's
   metadata block. By markdown link, not by stable ID.

2. **Tasks → User Stories (label).** `[US1]`, `[US2]`, … per-task
   labels reference the user stories in `spec.md` by their priority
   ordering (US1 = the P1 story, US2 = P2, …). Reordering user stories
   in spec.md silently breaks task traceability.

3. **Tasks → File paths (inline path).** Every task ends with the
   exact file path it modifies. The `tasks.md` command-file
   `Format Validation` step explicitly checks paths are present.

4. **Checklist → Spec section (anchor).** `[Spec §FR-001]`,
   `[Spec §NFR-2]` — the bracketed section pointers reference numbered
   requirements in `spec.md`. Reordering FR numbering breaks these.
   The convention is documented but not enforced by tooling.

5. **Plan → Constitution (article number).** `Article VII` /
   `Article IX` referenced in `plan.md`'s Phase Gates. Rename or
   renumber an article in `constitution.md` and the gate references
   silently rot.

6. **Command frontmatter → Other commands (handoff agent name).**
   `handoffs[].agent: speckit.plan` references another command file
   by its installed name. The `agent` value is a string, no resolution
   tooling beyond installed-command lookup.

**No bead-style ID system.** Spec scope units (`<NNN>-<short-name>/`
or `<YYYYMMDD-HHMMSS>-<short-name>/`) are addressed by their directory
name only. The directory name carries an ordinal *prefix* (NNN or
timestamp), but that prefix is not a stable global ID — it is local to
the project's `specs/` directory.

**No frontmatter `id:` field** anywhere — neither spec, plan, tasks,
research, data-model, quickstart, checklist, nor constitution carry a
stable identifier separate from their filename / path. The path *is*
the identifier.

**Stable in-doc identifiers within a file:**
- `FR-###` (functional requirements) in `spec.md`
- `SC-###` (success criteria) in `spec.md`
- `T###` (tasks) in `tasks.md`
- `CHK###` (checklist items) globally incrementing across appends to one checklist file
- `Article N` (constitution principles) — Roman or Arabic numeral, by convention

## Lifecycle markers

Spec Kit ships only **two** in-file lifecycle signals — far fewer than
its templates' richness might suggest:

1. **Checkbox state in `tasks.md`** — `- [ ]` is pending, `- [X]` /
   `- [x]` is complete. `/speckit.implement` step 8 explicitly
   instructs the LLM to flip this. Same convention applies to
   `checklists/<domain>.md` — all checklist items use the same checkbox
   discipline. This is the **only mechanical lifecycle signal Spec Kit
   reads from a doc.**

2. **`**Status**: Draft` in spec.md's metadata block** — a documented
   field with no documented vocabulary. The template ships it as
   "Draft" by default, but the legal set of follow-on values is not
   specified anywhere in the surveyed materials.

What Spec Kit *does not* ship for any first-party doc-type:
- No `version:` frontmatter on `spec.md`/`plan.md`/`tasks.md`/`research.md`/etc. (only `constitution.md` carries a version, in its trailing line)
- No `date:` or `created:` frontmatter (a `Created:` literal field appears in the spec.md metadata block but is not YAML)
- No filename suffixes like `-draft`, `-final`, `-deprecated`
- No archive directory or "removals.txt" log
- No "phase" frontmatter — the implementation phase is implicit from which files exist (`tasks.md` present ⇒ planning is done)

For `constitution.md`, the trailing `**Version**: X.Y.Z | **Ratified**:
YYYY-MM-DD | **Last Amended**: YYYY-MM-DD` line is a soft lifecycle
marker — the only one shipped on a *project-wide* doc.

## Central vs local documents

Spec Kit's tree splits cleanly into **central** (project-wide,
refreshed in place) and **local** (single piece of work,
write-once-then-evolved) by directory:

| Directory                                     | Central / local | Reasoning                                                                                                    |
| --------------------------------------------- | --------------- | ------------------------------------------------------------------------------------------------------------ |
| `specs/<feature>/`                            | **Local**       | Each feature directory is a discrete piece of work. Commands explicitly avoid mixing features here.          |
| `specs/<feature>/checklists/`                 | **Local**       | Per-feature checklists; one set per spec.                                                                     |
| `.specify/memory/constitution.md`             | **Central**     | Single project-wide principle file. Refreshed in place via `/speckit.constitution`.                          |
| `.specify/templates/`                         | **Central**     | Template files (and overrides) used across all features. One set per project.                                |
| `.specify/templates/commands/`                | **Central**     | Command files installed by `specify init`. One set per project.                                              |
| `.specify/feature.json`                       | **Central**     | Single active-feature pointer. Rewritten on each `/speckit.specify`.                                         |
| `.specify/init-options.json`                  | **Central**     | Single project-config file.                                                                                  |
| `.specify/extensions.yml`                     | **Central**     | Single project-wide hooks declaration.                                                                       |
| `.specify/extensions/<id>/`                   | **Central**     | Each extension is a long-lived install, not tied to a single piece of work.                                  |
| `.specify/presets/<id>/`                      | **Central**     | Same: a preset is a long-lived install.                                                                      |
| Workspace root: `AGENTS.md` / `CLAUDE.md` etc. | **Central**     | Single agent context file, refreshed in place.                                                               |
| Workspace root: `<integration-folder>/commands/` | **Central**     | Installed commands per integration; one set per project.                                                     |

`specs/` is the only "local" tier in the Spec Kit-defined doc set.
Everything else is central.

The **boundary criterion Spec Kit uses to decide central vs local**:
*Does this document describe an ongoing piece of work, or does it
describe the project's principles / configuration / agent behavior?*
The former goes in `specs/<feature>/`; the latter goes in `.specify/`
or workspace root.

There is no `_archive/`, no `docs/proposals/`, and no scratch
directory in the Spec Kit-defined layout. Once a feature directory
exists, it stays — and once a spec is "done" (all `tasks.md`
checkboxes flipped), the docs that drove it remain in `specs/`
indefinitely. Deletion is the only retirement path.

## Project / feature scope unit

The unit of work is a **feature**, materialised as a single directory
under `specs/`. The `spec-driven.md` essay explicitly equates the
two: "specifications drive implementation; the spec directory is
the planning + tracking *for* this feature."

**Feature directory naming:** two schemes, set by `branch_numbering`
in `.specify/init-options.json`:

| Mode (default = sequential) | Pattern                                | Example                            |
| --------------------------- | -------------------------------------- | ---------------------------------- |
| `sequential`                | `<NNN>-<short-name>` (3+ digits, expands beyond 999 automatically) | `001-user-auth`, `1234-payment-bug` |
| `timestamp`                 | `<YYYYMMDD>-<HHMMSS>-<short-name>`      | `20260319-143022-user-auth`         |

The numeric prefix is local to the project — there is no global
namespace, no UUID, no GitHub-issue-style cross-project ID. Two
projects with `001-user-auth` are distinct features.

**Per-feature doc count:** **6+ files plus a directory**, all under
`specs/<feature>/`:

```
specs/<feature>/
├── spec.md              # Always
├── plan.md              # Once /speckit.plan has run
├── tasks.md             # Once /speckit.tasks has run
├── research.md          # If Phase 0 found unknowns to resolve
├── data-model.md        # If feature involves data
├── quickstart.md        # Always (per plan.md template's manifest)
├── contracts/           # If feature exposes external interfaces
└── checklists/          # If /speckit.checklist or /speckit.specify ran
    ├── requirements.md  # Auto-generated by /speckit.specify validation
    └── <domain>.md      # Each /speckit.checklist invocation
```

**Short name discipline:** `templates/commands/specify.md` step 1
specifies "2-4 word short name … action-noun format when possible
(e.g., 'add-user-auth', 'fix-payment-bug')." Examples enumerated:
"user-auth", "oauth2-api-integration", "analytics-dashboard",
"fix-payment-timeout."

There is no notion of "epic" above feature, no notion of "story" as
a separate file — user stories live as numbered list items inside
`spec.md` under the User Scenarios & Testing section. The hierarchy is:

```
feature (= specs/<feature>/ directory)
├── 6+ docs as siblings, fixed filenames (spec/plan/tasks/research/data-model/quickstart)
├── checklists/ (per-domain)
└── numbered FR / SC / US / T / CHK identifiers within those docs
```

`/speckit.taskstoissues` can flatten tasks to GitHub Issues — bridging
the local feature scope to an external issue tracker — but the canonical
unit on disk is the feature directory.

## Planning vs implementation split

Both planning and implementation **tracking** live in the same feature
directory under `specs/<feature>/`. Implementation **code** lives
outside `specs/`, anywhere in the source tree.

The split is *temporal and per-file*:

- Planning artifacts: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `contracts/`
- Implementation tracking: `tasks.md` (checkbox state evolves)
- Implementation code: lives in actual source tree, referenced by
  full path inside each `tasks.md` task line

The feature directory is therefore "the planning + tracking *for*
this feature, not the code *of* this feature."

This is a **central design choice** — `tasks.md` does not move
when implementation begins; the same file evolves from "all `[ ]`"
to "all `[X]`" in place. `/speckit.implement` flips checkboxes and
commits source code in the same workflow but only the checkboxes
change inside `specs/`.

The phase ordering is enforced via three gating mechanisms:

1. **Constitution Check Gate** in `plan.md` — must pass before Phase 0
   research; re-check after Phase 1 design.
2. **Checklist completion gate** in `/speckit.implement` step 2 — if
   any `checklists/*.md` has incomplete items, halts and asks the user
   to confirm before proceeding.
3. **Tasks command's task-format validation** — if `tasks.md` items
   don't follow the `- [ ]` + `T###` + `[Story]` + path format, the
   IDE doesn't recognize them.

## Well-named patterns (with reasoning)

1. **`.specify/` is the single hidden top-level state directory.**
   All toolkit-managed state — templates, commands, constitution,
   extensions, presets, hooks config — lives under one path. Same
   pattern as `.kiro/`, `.vscode/`, `.cursor/`. Cost-of-discovery is
   one path; opt-in vs opt-out via `.gitignore` is a single decision.

2. **`specs/` (no leading dot) for per-feature docs.** Spec Kit
   distinguishes "toolkit-managed configuration" (hidden, `.specify/`)
   from "project-author-edited per-feature work" (visible, `specs/`).
   The visibility split reinforces that `specs/` is what humans
   review, edit, and merge; `.specify/` is what tooling owns.

3. **Feature directory carries an ordinal prefix.**
   `<NNN>-<short-name>` makes `ls specs/` sort chronologically by
   default and gives every feature a local short-id (`001`, `045`,
   `1234`) without inventing a separate ID space. The optional
   `timestamp` mode trades sortability across distributed teams for
   collision avoidance.

4. **Fixed filenames inside each feature directory.** `spec.md`,
   `plan.md`, `tasks.md`, `research.md`, `data-model.md`,
   `quickstart.md` — every feature is grep-able the same way; the
   IDE always knows where to look. The directory name is the
   namespace; the filenames don't need to be unique across features.

5. **`tasks.md` checkbox state IS the task lifecycle.** `- [ ]` /
   `- [X]` doubles as human display and machine-readable progress.
   Same idea as Kiro. Zero-overhead, no separate status field.

6. **`<commit_prefix>.<verb>.md` command-file convention.**
   `speckit.specify.md`, `speckit.plan.md`, `speckit.git.commit.md`.
   The `speckit.` prefix scopes the whole command namespace; the
   middle segment lets extensions add commands without colliding
   (`speckit.git.*`). Visually, `ls .specify/templates/commands/`
   gives a one-line catalog of every command in the project.

7. **`handoffs:` frontmatter in command files.** Commands declare
   their successor explicitly: `/speckit.specify` → `/speckit.plan`
   or `/speckit.clarify`; `/speckit.plan` → `/speckit.tasks`. The
   IDE renders these as one-click suggestions. Documents the
   workflow without needing a separate workflow-graph file.

8. **`description:` frontmatter is the universal command metadata.**
   Every command file carries a one-line description — used for
   command-picker UI, agent self-routing, and documentation
   generation. Required field; never optional.

9. **`FR-###` / `SC-###` / `T###` / `CHK###` numbering with hyphen and zero-padding.**
   Sortable as strings (`FR-001` < `FR-010` < `FR-100`), greppable
   as a fixed-shape pattern, and pronounceable in conversation
   ("FR-fifteen"). The four-character pad accommodates ~10× the
   templates' shipped examples without rework.

10. **Constitution carries semver in a trailing line, not frontmatter.**
    `**Version**: 2.1.1 | **Ratified**: 2025-06-13 | **Last Amended**: 2025-07-16`.
    Frontmatter would put the version above the H1 (visually de-emphasizing
    the title); a trailing line keeps the doc readable while still
    carrying machine-readable version state. The **only** doc-type
    with built-in semver.

11. **`Article N` plus thematic name for constitution principles.**
    `Article VII: Simplicity Gate` — both the number (stable, for
    cross-referencing) and the thematic name (for human reading).
    Templates reference articles by number; humans cite them by name.

12. **`<!-- SPECKIT START --> … <!-- SPECKIT END -->` markers in agent context files.**
    Spec Kit owns the contents between the markers; the user (or
    other tools) own everything else. Lets `CLAUDE.md` / `AGENTS.md`
    coexist with non-Spec-Kit agent instructions in the same file.

13. **`scripts: { sh: ..., ps: ... }` dual-script pattern.** Every
    command that needs a prerequisite script ships both bash and
    PowerShell variants; the `specify` CLI auto-selects per OS.
    `templates/commands/*.md` reference `{SCRIPT}` and the install-time
    transform substitutes the right path.

14. **Composition strategies for preset templates** (`replace`,
    `prepend`, `append`, `wrap`). Lets a preset *layer* onto the core
    template (e.g., add a section before the title) instead of
    forking the whole template. `wrap` requires `{CORE_TEMPLATE}` —
    a typed placeholder that fails fast when missing.

15. **Per-tier resolution priority for templates and commands.**
    `overrides → presets → extensions → core` — documented in
    `docs/reference/presets.md` with a Mermaid diagram. Same
    file-resolution-stack pattern recurs across templates, commands,
    and scripts.

## Awkward patterns (with reasoning)

1. **Phase 0 / Phase 1 outputs (research, data-model, quickstart, contracts/) ship without templates.**
   `templates/spec-template.md`, `plan-template.md`, `tasks-template.md`,
   `constitution-template.md`, `checklist-template.md` exist; `research-template.md`,
   `data-model-template.md`, `quickstart-template.md`, and
   `contracts-template/` do not. The LLM is expected to author them
   from the `templates/commands/plan.md` description alone. Cost: less
   structural enforcement on these four artifacts than on the templated five.

2. **`tasks.md` cross-references `spec.md` user stories by `[US1]`/`[US2]`/…
   labels indexed to priority order, not to a stable ID.** If you reorder
   user stories in `spec.md` (or insert one between US1 and US2),
   every task reference silently shifts. Same trap Kiro carries with
   `_Requirements: 1.2_`. There's no slug, no UUID.

3. **`Article N` references in `plan-template.md` are baked into the template, not derived from constitution.**
   The plan template literally writes `#### Simplicity Gate (Article VII)`
   and `#### Anti-Abstraction Gate (Article VIII)` — references to
   article numbers in the example constitution. If a project's actual
   constitution renumbers or renames articles, the plan template's gate
   labels go out of sync without any tooling signal.

4. **The `**Status**: Draft` field in `spec.md` has no documented vocabulary.**
   The template ships it; nothing tells you what other values are
   legal or what they mean. The spec quality checklist doesn't reference
   it. The rest of the workflow doesn't read it. Cost: looks like a
   lifecycle marker but isn't wired up to anything.

5. **Two paired artifacts inside `checklists/` follow different naming conventions.**
   `requirements.md` is fixed-name (auto-generated by `/speckit.specify`);
   every other checklist is `<domain>.md` (kebab-case, free-form).
   The asymmetry mirrors Kiro's `bugfix.md` vs `requirements.md` split
   for spec variants — a sibling-with-different-name pattern that
   forces consumers to special-case both.

6. **Frontmatter is opt-in across templates** — `tasks-template.md`
   ships YAML frontmatter; the other four templates do not. Producers
   reading the templates have to remember which one expects YAML and
   which one starts at H1. No documented reason for the asymmetry.

7. **`templates/plan-template.md` ships three "Option 1/2/3" project-structure trees that the LLM is expected to delete two of.**
   The template explicitly says "DELETE the unused options." This is
   delete-the-wrong-answers-style template authoring — works for an
   LLM but inverts the usual template discipline of "fill placeholders,
   don't remove them." A reader inheriting a half-edited plan can be
   confused about which option was actually picked.

8. **Markdown link `[link]` for Plan→Spec reference, no convention.**
   The spec.md metadata block writes `**Spec**: [link]` literally —
   the LLM is expected to substitute a relative-path link. No
   discipline on what kind of link (relative / absolute / GitHub URL).
   Two specs with the same link conventions can still rot differently.

9. **`feature.json` is a single-key file.** The whole purpose of the
   file is to hold one string (`feature_directory`). A 1-line
   `.specify/active-feature` would have done the same job; the JSON
   wrapping costs a parser dependency for what could be a `cat` /
   `read`.

10. **Constitution lives at `.specify/memory/constitution.md` but is referenced as `/memory/constitution.md` in some surfaces** (notably `templates/commands/plan.md` step 2 and the `analyze` command). The leading-slash form looks like a repo-rooted absolute path; the actual file is two levels deeper. Cost: a reader following the doc literally won't find the file. (`/speckit.constitution` correctly references `.specify/memory/constitution.md`; the inconsistency is cross-command.)

11. **No published "removed in vN" log for command files.** Presets
    can override commands; extensions can add them. There's no
    documented mechanism for a preset to *remove* a core command other
    than overriding it with a stub — and no convention for tagging
    a stub as "intentionally suppressed." Cost: a reader sees an
    empty `speckit.tasks.md` override and can't tell if it's a draft
    or a deliberate suppression.

12. **`__SPECKIT_COMMAND_*__` placeholder tokens leak into command file bodies.**
    `templates/commands/specify.md` step 7 contains literal
    `__SPECKIT_COMMAND_CLARIFY__` / `__SPECKIT_COMMAND_PLAN__` tokens
    (presumably substituted at install-time per integration). Until
    substituted they're an explicit "this is a placeholder" signal,
    but the reader of the in-repo template sees the raw tokens and
    has to mentally translate.

13. **`<!-- ACTION REQUIRED: ... -->` comments are visible in shipped templates and depend on the LLM removing them.**
    `spec-template.md` has 4+ such blocks. If the LLM forgets to delete
    one, the rendered spec includes an HTML-comment instruction in
    its visible markdown. No tooling check.

14. **Argument placeholder differs by integration (`$ARGUMENTS` vs `{{args}}` vs `{{parameters}}`).**
    A user reading `templates/commands/specify.md` in-repo sees
    `$ARGUMENTS`. After install for Gemini they should see `{{args}}`.
    The substitution is correct but the template-as-shipped doesn't
    look like the template-as-installed. Cost: reading the in-repo
    docs and reading an installed Gemini project's commands feel
    different.

## Stated rationale

Direct quotes from Spec Kit's docs, paired with what Spec Kit is
optimising for.

**On the spec being the source of truth, not code** (`spec-driven.md`):

> "Specifications don't serve code—code serves specifications. The
> Product Requirements Document (PRD) isn't a guide for implementation;
> it's the source that generates implementation. Technical plans aren't
> documents that inform coding; they're precise definitions that
> produce code."

This drives the central-vs-local split: the per-feature `spec.md`
is the authoritative artifact, and code is "the last-mile approach."

**On templates as constraints on the LLM** (`spec-driven.md`,
"Template-Driven Quality" section):

> "The true power of these commands lies not just in automation, but
> in how the templates guide LLM behavior toward higher-quality
> specifications. The templates act as sophisticated prompts that
> constrain the LLM's output in productive ways."

The template-files-as-prompts framing is the documented reason for the
strict format discipline (`FR-###` numbering, `[NEEDS CLARIFICATION]`
markers, the checkbox-`- [ ]` task format, etc.).

**On per-feature spec scope** (`spec-driven.md`, command examples):

> "**Automatic Feature Numbering**: Scans existing specs to determine
> the next feature number (e.g., 001, 002, 003, …, 1000 — expands
> beyond 3 digits automatically) … **Branch Creation**: Generates a
> semantic branch name from your description and creates it
> automatically … **Directory Structure**: Creates the proper
> `specs/[branch-name]/` structure for all related documents."

The `<NNN>-<short-name>` per-feature directory is documented as both
a specification scope unit and the natural git branch boundary.

**On the constitution as architectural DNA** (`spec-driven.md`):

> "At the heart of SDD lies a constitution—a set of immutable
> principles that govern how specifications become code. The
> constitution (`memory/constitution.md`) acts as the architectural
> DNA of the system, ensuring that every generated implementation
> maintains consistency, simplicity, and quality."

> "While principles are immutable, their application can evolve …
> Modifications to this constitution require: explicit documentation
> of the rationale for change, review and approval by project
> maintainers, backwards compatibility assessment."

This is why `constitution.md` is the only doc-type with versioning
(semver in trailing line) and the only doc with a built-in
sync-impact-report mechanism.

**On the test-first imperative** (`spec-driven.md`, Article III):

> "This is NON-NEGOTIABLE: All implementation MUST follow strict
> Test-Driven Development. No implementation code shall be written
> before: 1. Unit tests are written; 2. Tests are validated and
> approved by the user; 3. Tests are confirmed to FAIL (Red phase)."

But: `templates/tasks-template.md` ships test tasks as **OPTIONAL**
("Tests are OPTIONAL - only include them if explicitly requested in
the feature specification"). The constitution-template's example
treats Article III as MUST; the tasks-template's example treats
tests as opt-in. The two surfaces disagree by default — the
constitution wins via the analyze gate, but only if the project
adopts the example constitution.

**On checklists as "unit tests for English"** (`templates/commands/checklist.md`):

> "**CRITICAL CONCEPT**: Checklists are **UNIT TESTS FOR
> REQUIREMENTS WRITING** — they validate the quality, clarity, and
> completeness of requirements in a given domain."

> "If your spec is code written in English, the checklist is its
> unit test suite. You're testing whether the requirements are
> well-written, complete, unambiguous, and ready for implementation
> — NOT whether the implementation works."

Documents the explicit philosophical rejection of using checklists
as test cases. The `[Completeness] / [Clarity] / [Consistency] /
[Coverage] / [Measurability]` quality-dimension vocabulary is the
operational form of this stance.

**On extension hooks as a uniform extension point** (every command's
Pre/Post-Execution Checks block):

> "Filter out hooks where `enabled` is explicitly `false`. Treat
> hooks without an `enabled` field as enabled by default. … For each
> remaining hook, do **not** attempt to interpret or evaluate hook
> `condition` expressions … leave condition evaluation to the
> HookExecutor implementation."

Spec Kit deliberately separates "the LLM checks if a hook applies"
from "the runtime decides if a hook fires." Cost: the LLM has to
output instructions and let the runtime act, even when the LLM
could have known the answer. Benefit: hook semantics stay portable
across integrations.

**On `[NEEDS CLARIFICATION]` discipline** (`templates/commands/specify.md`):

> "**LIMIT: Maximum 3 [NEEDS CLARIFICATION] markers total** …
> Prioritize clarifications by impact: scope > security/privacy >
> user experience > technical details."

Cap-and-prioritize is the documented mechanism for keeping the
clarify loop bounded. The template embeds it as a hard constraint
on the LLM, not an aspirational guideline.

## Notes for the synthesis bead

Surfacing for gc-toolkit's default-location decision:

1. **Two-tier `.specify/` (toolkit state) vs `specs/` (per-feature work) is the cleanest hidden-vs-visible split surveyed.**
   gc-toolkit currently puts both runtime state (`.gc/`) and per-bead
   work in adjacent locations. Separating "what the harness owns"
   from "what the human/agent edits per piece of work" with a hidden
   prefix is a credible pattern. The `specs/` (visible) +
   `.specify/` (hidden) split makes the difference physically obvious
   to a `ls`.

2. **Feature directory with NNN/timestamp prefix is a strong pattern for per-piece-of-work artifacts.**
   `specs/<NNN>-<short-name>/` has all the properties bead-IDs aim
   for: locally unique, sortable by creation order, human-readable
   short-name appended. **The numeric prefix is local, not global**
   — that's the trade-off vs gc-toolkit's `tk-*` global IDs. A
   `specs/<bead-id>-<short-name>/` hybrid would borrow the directory
   discipline while keeping the global-ID property bead-IDs already
   provide.

3. **Six fixed-name files inside each feature directory (`spec.md`, `plan.md`, `tasks.md`, `research.md`, `data-model.md`, `quickstart.md`) is more files-per-scope than BMAD or Kiro.**
   The Spec Kit answer to "where does this artifact go?" is "in the
   feature directory, with a fixed name from this small set." It's
   denser per-feature but the names are predictable. gc-toolkit's
   per-feature work currently produces a smaller set
   (the bead description + research markdown + maybe a plan); if
   gc-toolkit grows toward Spec Kit's density, the `<verb>.md` filename
   pattern is worth borrowing.

4. **`/speckit.constitution` + `.specify/memory/constitution.md` is a credible model for gc-toolkit principle docs.**
   gc-toolkit already has `docs/principles/` (per the synthesis bead's
   working default). Adopting the constitution model adds: a single
   principles file (not a directory), built-in semver, a sync-impact-report
   convention for amendments, and explicit cross-doc references by article
   number. The trade-off is "principles split across many files" (current)
   vs "all principles in one versioned file" (Spec Kit) — the latter
   is easier to cite, the former is easier to evolve incrementally.

5. **The `.specify/extensions.yml` "uniform hook point" is worth borrowing.**
   gc-toolkit has hooks distributed across `.claude/settings.json`
   per-rig, deacon scripts, and ad-hoc agent instructions. A single
   YAML file declaring `before_<command>: [...]` / `after_<command>: [...]`
   for every Spec Kit-style action would centralise the policy. The
   "do not evaluate `condition` in the LLM, leave to runtime"
   discipline is itself worth borrowing — it keeps hook semantics
   portable.

6. **Checkbox state as the per-task lifecycle is identical to Kiro's pattern.**
   Both Spec Kit and Kiro converge on `- [ ]` / `- [X]` as the only
   in-file lifecycle signal for tasks. gc-toolkit's beads already
   have a status field (`open`/`in_progress`/`closed`/`blocked`/`escalated`),
   so the bead system is the gc-toolkit-native equivalent. The
   pattern to borrow: when a doc lists work items, use checkboxes,
   not a separate status field per item.

7. **`speckit.<namespace>.<verb>.md` for command files works because of the explicit prefix.**
   gc-toolkit's command-file-equivalents are spread across
   `~/.claude/commands/` (user-global) and `<rig>/.claude/commands/`
   (per-rig). A `gc.<namespace>.<verb>.md` convention with
   `gc.tk.*`, `gc.gascity.*`, `gc.dolt.*` would carry the same
   "namespace-aware" property. Spec Kit does this naturally because
   extensions claim a namespace; gc-toolkit could too.

8. **Templates that declare composition strategies (`replace`/`prepend`/`append`/`wrap`) are a richer model than gc-toolkit's current "override the whole file" approach.**
   gc-toolkit's per-rig template overrides currently follow the
   override-or-don't model. Spec Kit's `wrap` strategy with a
   `{CORE_TEMPLATE}` placeholder lets a rig-specific layer add
   pre/post content without forking. Worth considering for
   per-rig CLAUDE.md, agent prompts, and any other layered config.

9. **Two-tier filename case (`<lowercase>.md` for content, `UPPERCASE.md` for entrypoints) was Kiro's pattern; Spec Kit does NOT use it.**
   Spec Kit puts everything in lowercase-kebab (`spec.md`,
   `plan.md`, `tasks.md`, `constitution.md`). The exception is
   integration context files inherited from external standards
   (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`). For gc-toolkit:
   following Spec Kit's lowercase-everywhere is simpler than
   Kiro's two-tier rule and matches what gc-toolkit already does.

10. **No `id:` frontmatter, no UUID — path is the identifier — is now the convergent finding across all three "instruction-bearing markdown" reference projects** (Spec Kit, Kiro, Superpowers — and also BMAD per the prior survey). gc-toolkit choosing to attach bead-IDs to docs is a *departure* from all four. The trade-off is the same as before: portability (paths can move; bead-IDs are stable) vs simplicity (paths are obvious; bead-IDs need a registry, which gc-toolkit happens to have).

11. **No archive directory convention** — Spec Kit, Kiro, and Superpowers all converge here too. "Done" specs stay in `specs/`. If gc-toolkit wants a `docs/escalation/research/`-style ideation→adopted→archive tier, it remains a gc-toolkit-specific departure from all four reference projects.

12. **Constitution's "sync-impact report as HTML comment at top of file" is a clever in-place changelog pattern.**
    Each amendment prepends an HTML comment listing version delta,
    modified principles, downstream templates to re-check, and any
    deferred items. Equivalent to a per-file changelog, but lives in
    the file itself (not a separate `CHANGELOG.md` per principle
    file). For gc-toolkit principle docs, adopting this format would
    give principle docs a cheap drift-detection mechanism without
    needing a separate audit log.

13. **`tasks.md`'s strict format (`- [ ] T### [P?] [Story?] Description with file path`) is worth studying as a model for task-files-as-data.**
    The task format is rigid enough that the IDE parses it for
    progress display, dependencies, and parallel-execution markers.
    For gc-toolkit work-bead descriptions or per-rig task files, a
    similar parseable convention (with a documented format and
    explicit `✅ CORRECT` / `❌ WRONG` examples) would let tooling
    treat the markdown as semi-structured data without requiring
    YAML frontmatter on every item.

14. **`description:` as universal command metadata + `handoffs:` for the workflow graph is a documentation-and-execution duality worth noting.**
    Spec Kit's command files double as (a) the LLM prompt that
    executes the command and (b) the workflow graph (via `handoffs:`)
    that tells the IDE "after `/speckit.specify`, suggest
    `/speckit.plan` or `/speckit.clarify`." gc-toolkit's command
    files currently document but don't declare workflow successors;
    adding a `next:` or `handoffs:` field would let the harness
    auto-suggest the next command without baking the graph into
    a separate config file.

15. **Templates ship with `<!-- ACTION REQUIRED: ... -->` HTML-comment placeholders that the LLM is expected to remove.**
    Spec Kit's discipline is "the template carries inline guidance
    that gets deleted as it's filled in." This is a more readable
    (and more reviewable) alternative to YAML frontmatter for the
    "what should this section contain" question. For gc-toolkit
    docs that have a "fill in this section" cadence (e.g., research
    docs, escalation reports), worth borrowing.
