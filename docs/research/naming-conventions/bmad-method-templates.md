# BMAD Method — document templates and recording locations

## Reference to prior round

This is the templates pass that complements
[bmad-method.md](./bmad-method.md), which covered directory layout,
filename conventions, lifecycle markers, and stated rationale. That
pass deliberately did not open the templates themselves. This pass
does — and adds the **output recording locations** that BMAD's
workflows write to.

Things established in the prior round and not re-covered here:
Diátaxis directory split, kebab-case filenames, `_STYLE_GUIDE.md`
underscore prefix, `removals.txt` deprecation registry, trunk-based
git lifecycle, and the skill phase-numbered structure (`1-analysis/`,
`2-plan-workflows/`, `3-solutioning/`, `4-implementation/`).

## Provenance table

Every template surveyed below was read from a single shallow clone of
`github.com/bmad-code-org/BMAD-METHOD`, default branch `main`, at
commit `e36f219` (committed 2026-05-01). All output paths reflect
that commit. To re-verify or detect drift, clone the repo and check
out that SHA.

| Doc-type | Producer (skill / concept / workflow step) | Source location | Surveyed at |
|----------|-------------------------------------------|-----------------|-------------|
| Product brief | `bmad-product-brief` (Phase 1-analysis) | `src/bmm-skills/1-analysis/bmad-product-brief/resources/brief-template.md` @e36f219 | 2026-05-06 |
| PR/FAQ | `bmad-prfaq` (Phase 1-analysis) | `src/bmm-skills/1-analysis/bmad-prfaq/assets/prfaq-template.md` @e36f219 | 2026-05-06 |
| Research report (domain) | `bmad-domain-research` (Phase 1-analysis/research) | `src/bmm-skills/1-analysis/research/bmad-domain-research/research.template.md` @e36f219 | 2026-05-06 |
| Research report (market) | `bmad-market-research` (Phase 1-analysis/research) | `src/bmm-skills/1-analysis/research/bmad-market-research/research.template.md` @e36f219 | 2026-05-06 |
| Research report (technical) | `bmad-technical-research` (Phase 1-analysis/research) | `src/bmm-skills/1-analysis/research/bmad-technical-research/research.template.md` @e36f219 | 2026-05-06 |
| Project doc index | `bmad-document-project` (Phase 1-analysis) | `src/bmm-skills/1-analysis/bmad-document-project/templates/index-template.md` @e36f219 | 2026-05-06 |
| Project overview | `bmad-document-project` (Phase 1-analysis) | `src/bmm-skills/1-analysis/bmad-document-project/templates/project-overview-template.md` @e36f219 | 2026-05-06 |
| Source-tree analysis | `bmad-document-project` (Phase 1-analysis) | `src/bmm-skills/1-analysis/bmad-document-project/templates/source-tree-template.md` @e36f219 | 2026-05-06 |
| Deep-dive doc | `bmad-document-project` (deep-dive mode) | `src/bmm-skills/1-analysis/bmad-document-project/templates/deep-dive-template.md` @e36f219 | 2026-05-06 |
| Project-scan state file (JSON) | `bmad-document-project` (workflow state) | `src/bmm-skills/1-analysis/bmad-document-project/templates/project-scan-report-schema.json` @e36f219 | 2026-05-06 |
| PRD | `bmad-create-prd` (Phase 2-plan-workflows) | `src/bmm-skills/2-plan-workflows/bmad-create-prd/templates/prd-template.md` @e36f219 | 2026-05-06 |
| UX design | `bmad-create-ux-design` (Phase 2-plan-workflows) | `src/bmm-skills/2-plan-workflows/bmad-create-ux-design/ux-design-template.md` @e36f219 | 2026-05-06 |
| Architecture decision | `bmad-create-architecture` (Phase 3-solutioning) | `src/bmm-skills/3-solutioning/bmad-create-architecture/architecture-decision-template.md` @e36f219 | 2026-05-06 |
| Epic + stories breakdown | `bmad-create-epics-and-stories` (Phase 3-solutioning) | `src/bmm-skills/3-solutioning/bmad-create-epics-and-stories/templates/epics-template.md` @e36f219 | 2026-05-06 |
| Project context | `bmad-generate-project-context` (Phase 3-solutioning) | `src/bmm-skills/3-solutioning/bmad-generate-project-context/project-context-template.md` @e36f219 | 2026-05-06 |
| Implementation readiness report | `bmad-check-implementation-readiness` (Phase 3-solutioning) | `src/bmm-skills/3-solutioning/bmad-check-implementation-readiness/templates/readiness-report-template.md` @e36f219 | 2026-05-06 |
| Story (workflow-driven) | `bmad-create-story` (Phase 4-implementation) | `src/bmm-skills/4-implementation/bmad-create-story/template.md` @e36f219 | 2026-05-06 |
| Spec (quick-dev flow) | `bmad-quick-dev` (Phase 4-implementation) | `src/bmm-skills/4-implementation/bmad-quick-dev/spec-template.md` @e36f219 | 2026-05-06 |
| Sprint status | `bmad-sprint-planning` / `bmad-sprint-status` (Phase 4) | `src/bmm-skills/4-implementation/bmad-sprint-planning/sprint-status-template.yaml` @e36f219 | 2026-05-06 |
| Brainstorming session | `bmad-brainstorming` (core-skills) | `src/core-skills/bmad-brainstorming/template.md` @e36f219 | 2026-05-06 |

Null results — looked for and did not find:
- ADR template (no `architecture-decision-record-template.md` or `adr-template.md`; the only architecture template is the workflow-document `architecture-decision-template.md`, which is project-wide, not per-decision)
- Retro template (`bmad-retrospective` skill exists but ships no template file in `src/bmm-skills/4-implementation/bmad-retrospective/`)
- Code-review report template (`bmad-code-review` skill exists but ships no template; report is structured by step files only)
- Filled-out example output for any template (no `examples/` dir, no `*-example.md`; the `sprint-status-template.yaml` self-describes as "EXAMPLE STRUCTURE" inside the file but is also the operative template)

## Sources surveyed

- Repo: `github.com/bmad-code-org/BMAD-METHOD` @ `e36f219c81b6010d4aae423ba12f49edb5b6e31a`, default branch `main`, head dated 2026-05-01
- All 20 template files listed in the provenance table, read in full
- `module.yaml` (`src/bmm-skills/module.yaml`) — defines the three configurable output base directories with their default values
- `SKILL.md` for each skill that produces an output (PRD, brief, story, epics, architecture, UX, sprint-status, project-context, document-project, quick-dev), to extract the **`## Paths`** section that maps the template to its actual output filename
- `step-01-clarify-and-route.md` from `bmad-quick-dev` to extract the spec-file slug-derivation rule

## Output document types — inventory

A configurable layer determines the **base directory** for each
output. Three configurable bases are defined in
`src/bmm-skills/module.yaml` (prompted at install, persisted in
`{project-root}/_bmad/bmm/config.yaml`):

| Variable | Module-yaml default | What lives here |
|----------|---------------------|-----------------|
| `planning_artifacts` | `{output_folder}/planning-artifacts` | Phase 1-3 outputs: brief, PR/FAQ, PRD, UX design, architecture, epics, research outputs (in `research/` subdir), sprint-change-proposal |
| `implementation_artifacts` | `{output_folder}/implementation-artifacts` | Phase 4 outputs: stories, sprint-status, quick-dev specs, deferred-work, test summaries |
| `project_knowledge` | `docs` (note: not under `{output_folder}`) | `document-project` outputs only (multi-file index, overview, architecture, component-inventory, development-guide, api-contracts, data-models, source-tree analysis) |

`{output_folder}` is a Core Config variable from BMAD's bootstrap
layer, not defined in `module.yaml`; it is the project-wide root for
generated artifacts. One outlier: `bmad-brainstorming` writes
*directly* to `{output_folder}/brainstorming/`, not to any of the
three module-defined bases. This appears to be vestigial — the
brainstorming skill is in `core-skills/`, not `bmm-skills/`, so it
predates the planning/implementation/knowledge tiering and never
adopted it.

The CHANGELOG records this as a deliberate split: *"Phase 1-3
Workflows: All planning workflows now use `planning_artifacts` folder
(default changed from `docs`) … Planning artifacts properly separated
from long-term documentation."*

The full skill-to-output map at commit `e36f219`:

| Skill | Output file | Variable |
|-------|-------------|----------|
| `bmad-product-brief` | `{planning_artifacts}/product-brief-{project_name}.md` (+ optional `…-{project_name}-distillate.md`) | (resolved in `prompts/finalize.md`) |
| `bmad-brainstorming` | `{output_folder}/brainstorming/brainstorming-session-{date}-{time}.md` (note: subdirectory under `{output_folder}`, not `{planning_artifacts}`) | `brainstorming_session_output_file` (resolved at start of `workflow.md`) |
| `bmad-prfaq` | `{planning_artifacts}/prfaq-{project_name}.md` (+ optional `…-{project_name}-distillate.md`) | (per step files) |
| `bmad-{domain,market,technical}-research` | `{planning_artifacts}/research/{type}-{research_topic_slug}-research-{date}.md` (note: lives under `{planning_artifacts}/research/`, not `{project_knowledge}`) | (per step files) |
| `bmad-document-project` | Multi-file write to `{project_knowledge}/`: `index.md`, `project-overview.md`, `source-tree-analysis.md`, `architecture.md`, `component-inventory.md`, `development-guide.md`, `api-contracts.md`, `data-models.md`, optionally `architecture-{part_id}.md`, `api-contracts-{part_id}.md`, etc. for multi-part projects, plus `.archive/project-scan-report-{timestamp}.json` | (per skill) |
| `bmad-create-prd` | `{planning_artifacts}/prd.md` | `outputFile` |
| `bmad-create-ux-design` | `{planning_artifacts}/ux-design-specification.md` | `default_output_file` |
| `bmad-create-architecture` | `{planning_artifacts}/architecture.md` (verified in `steps/step-01-init.md` and append calls in steps 02-07) | (per step) |
| `bmad-create-epics-and-stories` | `{planning_artifacts}/epics.md` (verified in `steps/step-01-validate-prerequisites.md`) | (per step) |
| `bmad-generate-project-context` | `{output_folder}/project-context.md` | `output_file` |
| `bmad-check-implementation-readiness` | (skill output; resolved per session) | (per step) |
| `bmad-create-story` | `{implementation_artifacts}/{story_key}.md` (e.g. `1-2-user-authentication.md`) | `default_output_file` |
| `bmad-dev-story` | (modifies the existing story file in place; no new file) | `story_file` |
| `bmad-quick-dev` | `{implementation_artifacts}/spec-{slug}.md` (e.g. `spec-3-2-digest-delivery.md`, `spec-gh-47-fix-auth.md`) | `spec_file` |
| `bmad-correct-course` | `{planning_artifacts}/sprint-change-proposal-{date}.md` | `default_output_file` |
| `bmad-qa-generate-e2e-tests` | `{implementation_artifacts}/tests/test-summary.md` | `default_output_file` |
| `bmad-sprint-planning` / `bmad-sprint-status` | `{implementation_artifacts}/sprint-status.yaml` | `sprint_status_file` |

Filename patterns observable in this map:

- **Singular canonical files** for project-wide artifacts: `prd.md`,
  `architecture.md`, `epics.md`, `ux-design-specification.md`,
  `sprint-status.yaml`, plus the `document-project` set
  (`index.md`, `project-overview.md`, etc.). There is **one of
  each per project** — these are central, refreshed-in-place.
- **Project-name-keyed files** for project-wide artifacts that *also*
  carry a project-name segment for multi-project disambiguation:
  `product-brief-{project_name}.md`, `prfaq-{project_name}.md`,
  and their `…-distillate.md` siblings. Within a single project
  there is one of each, but the filename advertises the project
  name. (See **Central vs local documents** below for why this
  matters.)
- **ID-keyed files** for per-unit-of-work artifacts: stories use
  `{epic_num}-{story_num}-{slug}.md` (e.g.
  `1-2-user-authentication.md`); quick-dev specs use
  `spec-{slug}.md` and the slug *can* lead with the same
  `{epic_num}-{story_num}` prefix.
- **Date-keyed files** for time-bounded artifacts:
  `sprint-change-proposal-{date}.md`,
  `brainstorming-session-{date}-{time}.md`,
  `{type}-{slug}-research-{date}.md`,
  `.archive/project-scan-report-{timestamp}.json`.
- **Suffixed parallel files** for multi-part projects:
  `architecture-{part_id}.md`,
  `api-contracts-{part_id}.md`,
  `component-inventory-{part_id}.md`,
  `development-guide-{part_id}.md`. The `index.md` references all
  the part-suffixed files. This pattern only appears in the
  `bmad-document-project` outputs.

## Per-template detail

The five most representative templates, plus the JSON state schema
that anchors workflow resumability.

### 1. PRD — `bmad-create-prd`

**Source:** `src/bmm-skills/2-plan-workflows/bmad-create-prd/templates/prd-template.md`
**Output:** `{planning_artifacts}/prd.md` (singleton; one per project).

Frontmatter (pre-substitution):
```yaml
---
stepsCompleted: []
inputDocuments: []
workflowType: 'prd'
---
```

Body skeleton at template-time:
```markdown
# Product Requirements Document - {{project_name}}

**Author:** {{user_name}}
**Date:** {{date}}
```

That is the **entire body**. The PRD's actual structure (epics,
non-functional requirements, etc.) is *not* in the template — the
step files (`steps-c/step-01-init.md` … `step-12-complete.md`) build
the document by appending sections during workflow execution. The
SKILL's "Critical Rules" enforce this: *"Build documents by
appending content as directed to the output file."*

Frontmatter semantics:
- `stepsCompleted: []` — runtime state. After each step, the step
  file appends its identifier here. On resume, the workflow reads
  this array to know where to continue. Author-irrelevant.
- `inputDocuments: []` — runtime state. Step files record paths to
  documents (briefs, brainstorming notes) that informed each section.
- `workflowType: 'prd'` — author-fixed (the template ships with this
  literal). Disambiguates the file when scanned by other skills.

Cross-doc references: none in the template. References between PRD
and brief/architecture/epics are runtime: `bmad-create-story`
discovers files matching globs (`{planning_artifacts}/*prd*.md`,
`{planning_artifacts}/*architecture*.md`, `{planning_artifacts}/*epic*.md`)
rather than following frontmatter pointers.

### 2. Architecture decision — `bmad-create-architecture`

**Source:** `src/bmm-skills/3-solutioning/bmad-create-architecture/architecture-decision-template.md`
**Output:** `{planning_artifacts}/architecture.md` (singleton).

Frontmatter:
```yaml
---
stepsCompleted: []
inputDocuments: []
workflowType: 'architecture'
project_name: '{{project_name}}'
user_name: '{{user_name}}'
date: '{{date}}'
---
```

Body skeleton:
```markdown
# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._
```

Frontmatter semantics: same `stepsCompleted` / `inputDocuments` /
`workflowType` runtime triplet as the PRD, plus three
**author-substituted** fields (`project_name`, `user_name`, `date`).
The PRD has the same three values in body prose; architecture lifts
them into frontmatter so they can be read programmatically without
parsing the markdown body.

This is **not** an ADR template. The doc is a single project-wide
architecture document, not a per-decision record. BMAD ships no
ADR template — `removals.txt` does not list one as removed either,
so the absence is design, not regression.

### 3. Epics + stories — `bmad-create-epics-and-stories`

**Source:** `src/bmm-skills/3-solutioning/bmad-create-epics-and-stories/templates/epics-template.md`
**Output:** `{planning_artifacts}/epics.md` (singleton).

Frontmatter (no `workflowType`):
```yaml
---
stepsCompleted: []
inputDocuments: []
---
```

Body skeleton:
```markdown
# {{project_name}} - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for {{project_name}}, decomposing the requirements from the PRD, UX Design if it exists, and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

{{fr_list}}

### NonFunctional Requirements

{{nfr_list}}

### Additional Requirements

{{additional_requirements}}

### UX Design Requirements

{{ux_design_requirements}}

### FR Coverage Map

{{requirements_coverage_map}}

## Epic List

{{epics_list}}

<!-- Repeat for each epic in epics_list (N = 1, 2, 3...) -->

## Epic {{N}}: {{epic_title_N}}

{{epic_goal_N}}

<!-- Repeat for each story (M = 1, 2, 3...) within epic N -->

### Story {{N}}.{{M}}: {{story_title_N_M}}

As a {{user_type}},
I want {{capability}},
So that {{value_benefit}}.

**Acceptance Criteria:**

<!-- for each AC on this story -->

**Given** {{precondition}}
**When** {{action}}
**Then** {{expected_outcome}}
**And** {{additional_criteria}}

<!-- End story repeat -->
```

Notable details:

- This is BMAD's first **structured-with-loops** template:
  `<!-- Repeat for each epic … -->` and `<!-- Repeat for each
  story … -->` are author-readable repeat directives, not Handlebars
  blocks. (Compare with `bmad-document-project`'s templates, which
  do use real Handlebars `{{#each}}`.) Two different "repeat"
  syntaxes coexist in the codebase for two different reasons:
  here it's author-guided, there it's renderer-driven.
- Epics carry a **deterministic numbering scheme**: `Epic {N}` and
  `Story {N}.{M}` (decimal, dot-separated). This becomes the
  identity that downstream `bmad-create-story` and
  `bmad-sprint-status` use as cross-doc anchors — see "Cross-doc
  reference scheme" below.
- Acceptance criteria are templated as Given/When/Then.

### 4. Story (workflow-driven) — `bmad-create-story`

**Source:** `src/bmm-skills/4-implementation/bmad-create-story/template.md`
**Output:** `{implementation_artifacts}/{story_key}.md` where
`story_key` = `{epic_num}-{story_num}-{title-slug}` (e.g.
`1-2-user-authentication.md`). One file per story.

**No frontmatter at all.** Status is in the body:

```markdown
# Story {{epic_num}}.{{story_num}}: {{story_title}}

Status: ready-for-dev

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a {{role}},
I want {{action}},
so that {{benefit}}.

## Acceptance Criteria

1. [Add acceptance criteria from epics/PRD]

## Tasks / Subtasks

- [ ] Task 1 (AC: #)
  - [ ] Subtask 1.1
- [ ] Task 2 (AC: #)
  - [ ] Subtask 2.1

## Dev Notes

- Relevant architecture patterns and constraints
- Source tree components to touch
- Testing standards summary

### Project Structure Notes

- Alignment with unified project structure (paths, modules, naming)
- Detected conflicts or variances (with rationale)

### References

- Cite all technical details with source paths and sections, e.g. [Source: docs/<file>.md#Section]

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
```

Notable details:

- **Status as body prose**, not frontmatter — `Status:
  ready-for-dev`. This is a deliberate departure from the
  workflow-driven planning docs (PRD, architecture, epics), which
  put runtime state (`stepsCompleted`, `inputDocuments`) in
  frontmatter. The story doc is human-and-tool-edited (dev,
  reviewer, retro), so its status is a first-class body section.
- **Cross-doc reference convention is explicit and embedded**:
  *"Cite all technical details with source paths and sections,
  e.g. `[Source: docs/<file>.md#Section]`."* This is the only
  template in BMAD that codifies a cross-doc reference syntax
  inline.
- The `Dev Agent Record` block (Agent Model Used / Debug Log /
  Completion Notes / File List) is metadata that the dev agent
  fills during/after implementation. It's the closest thing BMAD
  has to a "what did the agent actually do" audit trail per story.
- Story IDs are **numeric** (`{epic_num}.{story_num}`) in the
  body but use **dashes** (`{epic_num}-{story_num}-{slug}`) in the
  filename. The `bmad-create-story` SKILL parses both forms.

### 5. Spec (quick-dev) — `bmad-quick-dev`

**Source:** `src/bmm-skills/4-implementation/bmad-quick-dev/spec-template.md`
**Output:** `{implementation_artifacts}/spec-{slug}.md` (slug
derived from intent; if the intent references a tracking ID, the
slug leads with it — e.g. `spec-3-2-digest-delivery.md` or
`spec-gh-47-fix-auth.md`).

Frontmatter — *materially different shape* from anything else in
BMAD:
```yaml
---
title: '{title}'
type: 'feature' # feature | bugfix | refactor | chore
created: '{date}'
status: 'draft' # draft | ready-for-dev | in-progress | in-review | done
context: [] # optional: `{project-root}/`-prefixed paths to project-wide standards/docs the implementation agent should load. Keep short — only what isn't already distilled into the spec body.
---
```

Body has explicit token-budget instructions, semantic
human-vs-agent ownership markup, and delete-if-empty sections:

```markdown
<!-- Target: 900–1300 tokens. Above 1600 = high risk of context rot.
     Never over-specify "how" — use boundaries + examples instead.
     Cohesive cross-layer stories (DB+BE+UI) stay in ONE file.
     IMPORTANT: Remove all HTML comments when filling this template. -->

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent
**Problem:** ONE_TO_TWO_SENTENCES
**Approach:** ONE_TO_TWO_SENTENCES

## Boundaries & Constraints
**Always:** INVARIANT_RULES
**Ask First:** DECISIONS_REQUIRING_HUMAN_APPROVAL
**Never:** NON_GOALS_AND_FORBIDDEN_APPROACHES

## I/O & Edge-Case Matrix
<!-- If no meaningful I/O scenarios exist, DELETE THIS ENTIRE SECTION. -->
| Scenario | Input / State | Expected Output / Behavior | Error Handling |
| HAPPY_PATH | INPUT | OUTCOME | N/A |
| ERROR_CASE | INPUT | OUTCOME | ERROR_HANDLING |

</frozen-after-approval>

## Code Map
<!-- Agent-populated during planning. -->
- `FILE` -- ROLE_OR_RELEVANCE

## Tasks & Acceptance
**Execution:**
- [ ] `FILE` -- ACTION -- RATIONALE
**Acceptance Criteria:**
- Given PRECONDITION, when ACTION, then EXPECTED_RESULT

## Spec Change Log
<!-- Append-only. Populated by step-04 during review loops. -->

## Design Notes
<!-- If the approach is straightforward, DELETE THIS ENTIRE SECTION. -->

## Verification
<!-- If no build, test, or lint commands apply, DELETE THIS ENTIRE SECTION. -->
**Commands:**
- `COMMAND` -- expected: SUCCESS_CRITERIA
**Manual checks (if no CLI):**
- WHAT_TO_INSPECT_AND_EXPECTED_STATE
```

Notable design choices visible in the template:

- **Lifecycle status in frontmatter** (`status: draft |
  ready-for-dev | in-progress | in-review | done`). Distinct from
  `bmad-create-story/template.md` (status in body prose) and from
  PRD/architecture (no `status` field at all — those use
  `stepsCompleted` runtime arrays instead).
- **`type` enum** in frontmatter (`feature | bugfix | refactor |
  chore`) — the only BMAD template that classifies its content
  by change-type taxonomy.
- **Token budget written into the template** as a comment to the
  filling agent: *"Target: 900–1300 tokens. Above 1600 = high
  risk of context rot."* This is unique to quick-dev among the
  surveyed templates.
- **Semantic XML in markdown body**:
  `<frozen-after-approval reason="…">…</frozen-after-approval>`
  marks human-owned regions that must not be agent-edited after
  initial approval. No other BMAD template uses HTML/XML this way
  for ownership semantics.
- **Append-only audit trail in body**: `## Spec Change Log` is
  explicitly append-only and populated by review loop step-04 —
  the spec carries its own revision history rather than relying on
  git.
- **Delete-if-empty sections**: `## I/O & Edge-Case Matrix`,
  `## Design Notes`, `## Verification` are explicitly marked
  delete-rather-than-stub. *"Do not write 'N/A' or 'None'."*
  No other BMAD template has this rule.

The quick-dev spec is the most evolved template in BMAD's catalog
in that it tries to encode *advice for the filling agent* directly
in the template surface (token budget, ownership boundaries,
delete-if-empty). Other templates leave that advice in step files.

### 6. Project-scan state file (JSON) — `bmad-document-project`

**Source:** `src/bmm-skills/1-analysis/bmad-document-project/templates/project-scan-report-schema.json`
**Output:** `{project_knowledge}/project-scan-report.json`
(operational; archived to
`{project_knowledge}/.archive/project-scan-report-{timestamp}.json`
on workflow rerun).

Not a markdown template. A JSON Schema (`draft-07`) describing a
**resumability state file** that the workflow reads/writes
between steps. Required fields:

- `workflow_version` (string, e.g. `"1.2.0"`)
- `timestamps`: `{started, last_updated, completed}` (ISO 8601)
- `mode`: enum `initial_scan | full_rescan | deep_dive`
- `scan_level`: enum `quick | deep | exhaustive`
- `completed_steps`: array of `{step, status: completed|partial|failed,
  timestamp, outputs[], summary}`
- `current_step`: identifier for resume
- `findings` (high-level summaries; detailed findings purged after
  writing to output docs — explicit non-storage of detail to
  control context size)
- `outputs_generated`: array of file paths written
- `resume_instructions`: human-readable resume note
- `validation_status`: `{last_validated, validation_errors[]}`
- `deep_dive_targets`: array of `{target_name, target_path,
  files_analyzed, output_file, timestamp}` — only meaningful in
  deep-dive mode

This is BMAD's only **structured (non-markdown) state file** that
ships with a JSON Schema. It's the persistence layer for the
workflow's execution-state, separate from the prose docs the
workflow produces. The schema's existence (and its `archive/`
rotation policy) is a stronger commitment to resumability than
anything else in BMAD's catalog.

## Cross-doc reference scheme

BMAD has *no* single uniform cross-doc reference convention.
Different document tiers use different mechanisms, each fit-for-purpose
for the way that tier is consumed:

### a) Numeric IDs as anchors (epic/story tier)

The most-used scheme. Epics and stories are identified by integer
hierarchy:

- Epic: `Epic {N}` (e.g. `Epic 1`)
- Story: `Story {N}.{M}` in body prose (`Story 1.2`), or
  `{N}-{M}-{slug}` in filenames (`1-2-user-authentication.md`)

The downstream `bmad-create-story` SKILL parses both forms
indifferently. `bmad-sprint-status.yaml` uses the dashed form as
keys: `1-2-user-authentication: ready-for-dev`. Epic-level keys
are `epic-{N}: backlog | in-progress | done`. Retrospective keys
are `epic-{N}-retrospective: optional | done`.

The same numbering anchors three artifacts: epics file (definition),
story file (per-story doc), sprint-status file (current state).
**The numbering is the join key** across the doc set.

### b) Path-and-section pointers (story → architecture/PRD)

The story template explicitly codifies one cross-doc pointer
syntax:

> Cite all technical details with source paths and sections, e.g.
> `[Source: docs/<file>.md#Section]`

This appears only in `bmad-create-story/template.md`. It's a
manual citation pattern (markdown link to a heading anchor),
not enforced by tooling. Used to point story docs back at the
architecture / PRD sections they implement.

### c) Glob-based discovery (planner artifacts → consumers)

The PRD, architecture, and epics docs do not point at each other
by ID. Instead, downstream skills discover them by **filename
glob**:

```
prd        : whole = {planning_artifacts}/*prd*.md,
             sharded = {planning_artifacts}/*prd*/*.md
architecture : whole = {planning_artifacts}/*architecture*.md,
               sharded = {planning_artifacts}/*architecture*/*.md
ux         : whole = {planning_artifacts}/*ux*.md,
             sharded = {planning_artifacts}/*ux*/*.md
epics      : whole = {planning_artifacts}/*epic*.md,
             sharded = {planning_artifacts}/*epic*/*.md
```

The glob scheme tolerates renames and language localization
(`prd-fr.md`, `prd.es.md`) and supports a "sharded" form: a
directory of fragments instead of a single file. The trade-off:
ambiguity if multiple matches exist, and no machine-checkable
"this PRD belongs to that brief" link.

### d) Multi-part suffix scheme (`bmad-document-project` only)

For multi-part projects, every doc gets a `-{part_id}` suffix:
`architecture-{part_id}.md`, `api-contracts-{part_id}.md`,
`development-guide-{part_id}.md`. The `index.md` then iterates
parts via Handlebars and links to all suffixed files. This is
the only BMAD doc family that uses suffix-based parallelism for
cross-references.

### e) `inputDocuments` frontmatter array (workflow-tracked tier only)

The workflow templates (PRD, architecture, UX, brainstorming,
research) carry `inputDocuments: []` in frontmatter. Step files
populate this with paths to docs the step consumed. It's runtime
provenance, not author-curated cross-references — it answers
"what did this workflow run read?" rather than "what does this
doc reference?". After workflow completion, the array is
trustworthy as a backward-pointing audit trail, but no skill
reads `inputDocuments` from another doc to resolve a forward
reference.

## Planning vs implementation split

BMAD's planning/implementation boundary is **structural and
file-system-level**, not just conceptual. It is enforced by the
output base-directory split defined in `module.yaml`:

```
{planning_artifacts}/        → Phase 1-3: brief, PR/FAQ, PRD,
                                 UX design, architecture, epics,
                                 research outputs (in research/),
                                 sprint-change-proposal
{implementation_artifacts}/  → Phase 4: stories,
                                 quick-dev specs, sprint-status,
                                 deferred-work, test summaries
{project_knowledge}/         → Long-lived knowledge:
                                 document-project outputs
                                 (multi-file)
{output_folder}/brainstorming/ → Brainstorming sessions (the one
                                 outlier — does not adopt any of
                                 the three module-defined bases)
```

The CHANGELOG explicitly justifies the split: *"Planning artifacts
properly separated from long-term documentation"* and the default
moved off `docs/` to drive that separation home.

Three observations on the split:

1. **Workflow phase ↔ output dir is roughly 1:1.** Phases 1-3
   write only to `planning_artifacts`. Phase 4 writes only to
   `implementation_artifacts`. The exception is
   `bmad-correct-course` (Phase 4) which writes a sprint-change
   proposal to `planning_artifacts` because it's amending the
   plan, not implementing.

2. **Templates differ in shape per side.** Planning templates
   tend to be **workflow-driven append-only** with
   `stepsCompleted: []` runtime state (PRD, architecture, UX,
   epics, brainstorming, research). Implementation templates
   tend to be **lifecycle-status driven** with explicit `status`
   in body or frontmatter (story: body prose; quick-dev spec:
   frontmatter enum). Different concerns drive different
   template shapes.

3. **Project-knowledge is its own third bucket**, not a sub-tier
   of either side. Research outputs and `document-project`
   outputs (long-lived knowledge — what's *true* about the
   project, not what we *plan* or *do*) live in
   `{project_knowledge}` (default `docs/`). This is BMAD's
   answer to "where does the durable knowledge go?" — it's not
   in `planning_artifacts` (which churns per planning cycle)
   and it's not in `implementation_artifacts` (which churns per
   sprint).

## Central vs local documents

BMAD distinguishes central from local through **filename
identity**, not directory placement. Three classes emerge:

### Class A — Central, canonical singletons

One per project; filename has no varying segment. Refreshed in
place; old content overwritten or amended.

- `{planning_artifacts}/prd.md`
- `{planning_artifacts}/architecture.md` — planning-side decisions
- `{planning_artifacts}/epics.md`
- `{planning_artifacts}/ux-design-specification.md`
- `{implementation_artifacts}/sprint-status.yaml`
- `{project_knowledge}/index.md`
- `{project_knowledge}/project-overview.md`
- `{project_knowledge}/architecture.md` — long-lived as-built (note: same filename as the planning-side; different tier)
- `{project_knowledge}/source-tree-analysis.md`
- `{project_knowledge}/component-inventory.md`,
  `{project_knowledge}/development-guide.md`,
  `{project_knowledge}/api-contracts.md`,
  `{project_knowledge}/data-models.md` (when the project warrants
  them)

### Class B — Central, project-name-keyed

One per project, but the filename advertises the project name
(usually for cross-project distinguishability when artifacts get
copied between projects):

- `{planning_artifacts}/product-brief-{project_name}.md`
- `{planning_artifacts}/product-brief-{project_name}-distillate.md`
- `{planning_artifacts}/prfaq-{project_name}.md`
- `{planning_artifacts}/prfaq-{project_name}-distillate.md`

These behave like Class A within a single project — there is
exactly one product brief per project, refreshed in place — but
their filename shape signals that BMAD authors expected the file to
be circulated outside the project root, where the bare name
`product-brief.md` would be ambiguous.

### Class C — Local, write-once with varying filenames

Many per project; filename varies by ID, slug, or date; never
overwritten. The corpus accumulates.

- `{implementation_artifacts}/{story_key}.md` — one per story
  (e.g. `1-2-user-authentication.md`)
- `{implementation_artifacts}/spec-{slug}.md` — one per quick-dev
  unit of work (e.g. `spec-gh-47-fix-auth.md`,
  `spec-3-2-digest-delivery.md`)
- `{planning_artifacts}/sprint-change-proposal-{date}.md`
- `{output_folder}/brainstorming/brainstorming-session-{date}-{time}.md`
- `{planning_artifacts}/research/{type}-{slug}-research-{date}.md`
- `{project_knowledge}/.archive/project-scan-report-{timestamp}.json`
- `{implementation_artifacts}/tests/test-summary.md` (lives under
  a `tests/` subdir; filename is canonical, but the corpus grows
  per-test-run)

Stories progress through statuses (`backlog → ready-for-dev →
in-progress → review → done`) but the file itself persists.

**Decision rule observable from BMAD's choices:** Is there one of
these per project, or many?
- One, never circulated outside the project root → Class A
  (canonical singular filename).
- One, but expected to circulate → Class B (project-name-keyed).
- Many, growing over time → Class C (vary by ID/slug/date).

### Multi-part exception

`bmad-document-project` produces *per-part central* files —
`architecture-{part_id}.md` is canonical for that part. The
`{part_id}` suffix carries the identity that would otherwise put
the file in Class C. This is the only doc-family in BMAD that
needs a sub-rule on top of the three classes above.

## Project/feature scope unit

BMAD's scope hierarchy (from largest to smallest):

```
project          (one PRD, one architecture, one epics file)
  └── epic       (numbered: Epic 1, Epic 2, …)
       └── story (numbered within epic: Story 1.1, 1.2, …, plus
                  filename slug: 1-2-user-authentication.md)
            └── (no smaller unit; tasks are checkboxes inside the
                  story file, not separate docs)
```

Doc types per scope:

| Scope | Docs that attach to this scope |
|-------|-------------------------------|
| Project | brief, PR/FAQ, PRD, UX design, architecture, epics, sprint-status, project-context, document-project outputs (index, overview, source-tree, optional architecture/component-inventory/development-guide) |
| Epic | (no per-epic doc; epics are sections in `epics.md` and keys in `sprint-status.yaml`. Retrospective is per-epic but uses `epic-{N}-retrospective` *status* in `sprint-status.yaml`, not a separate doc — see null result above on retro template) |
| Story | story file (`{story_key}.md`) — one per story |

The notable absence: **no per-epic standalone doc.** Epics live as
sections inside the project-wide `epics.md` and as keys in
`sprint-status.yaml`. This keeps epic-level coordination
centralised; the trade-off is that a single epic can't be circulated
or reviewed as a standalone artifact without extracting it from
`epics.md`.

The `bmad-quick-dev` spec is the only doc-type that doesn't fit
this hierarchy cleanly. A quick-dev spec **may** correspond to a
story (and lead its slug with the `{epic_num}-{story_num}` prefix)
or **may** correspond to an external tracker item (`gh-47-…`,
`jira-PROJ-123-…`) or **may** be standalone. The skill's
`step-01-clarify-and-route.md` performs "story-key resolution" at
runtime to attach a spec to a story when possible — but the spec
is structurally a peer of the story, not a child.

## Notes for the synthesis bead

Things worth surfacing for `tk-yiwfz.4` (the gc-toolkit
synthesis):

1. **Two output base directories beats one when the tiers churn at
   different rates.** BMAD's `planning_artifacts` /
   `implementation_artifacts` / `project_knowledge` triple is a
   pragmatic split — planning churns once per planning cycle,
   implementation churns once per sprint, project_knowledge churns
   once per major refresh. They have to live in different roots
   so each tier's churn doesn't pollute the others. gc-toolkit
   should at minimum decide whether its planning docs and its
   implementation docs share a root or not.

2. **The "central vs local" rule that emerges from BMAD's templates:**
   *one-per-project = canonical singular filename; many-per-project
   = filename varies by ID/slug/date.* This is a stronger rule
   than "central vs local" considered abstractly: it's enforceable
   ("does this filename have a varying segment?") and visible in
   `ls`. gc-toolkit could adopt this directly.

3. **Frontmatter shape varies by tier** in BMAD, and the variation
   is informative:
   - **Workflow-tracked planning docs** (PRD, architecture, UX,
     epics, brainstorming, research): `stepsCompleted` +
     `inputDocuments` + optional `workflowType`. Runtime state,
     no `status`.
   - **Lifecycle-tracked implementation docs** (quick-dev spec):
     `title`, `type`, `created`, `status`, `context`. Author/UX
     facts, with explicit lifecycle status enum.
   - **Story doc**: status is **body prose**, not frontmatter
     (because devs and reviewers edit the body, and the
     status-line is a visible body landmark).
   - **Reference docs** (document-project outputs): no
     frontmatter. Regenerated in full each run; nothing to
     persist between runs.
   gc-toolkit can pick one frontmatter shape per tier or unify
   them, but this is the kind of decision worth making explicitly.

4. **Cross-doc references via numbering, not links, when the IDs
   are stable.** BMAD uses `Epic {N}.Story {M}` as the durable
   join key across `epics.md`, story files, and `sprint-status.yaml`.
   Markdown links would break under rename; numeric IDs survive.
   gc-toolkit's bead system already provides stable IDs (`tk-yiwfz.5`)
   that play the same role — using bead-IDs as the natural anchor
   for local work is consistent with this BMAD pattern (and was
   already flagged in the synthesis bead's stop conditions).

5. **The `[Source: path#section]` citation pattern** that BMAD
   bakes into the story template is a lightweight, no-tooling
   convention that produces grep-able provenance. Worth borrowing
   for any gc-toolkit doc that synthesises from other docs (e.g.,
   a design doc citing principles, a story citing architecture).

6. **A JSON-Schema-anchored state file alongside markdown outputs.**
   BMAD's `project-scan-report.json` (with its archived rotations)
   is a textbook example of separating "what we wrote" from "what
   we did to write it" — the state file is operational, the
   markdown outputs are the deliverable. If gc-toolkit's
   workflows ever need resumability, this split is worth lifting:
   prose stays in markdown, machine state goes in JSON with a
   schema.

7. **Filename collision risk that BMAD avoids by tiering:** BMAD
   has *two* `architecture.md` files (one in `planning_artifacts`,
   one in `project_knowledge`) intentionally — one is the
   forward-looking decision document, one is the as-built
   reference. Same filename, different tier. This works because
   the tiers are structurally separated. gc-toolkit should expect
   the same shape: an `architecture.md` proposing change is not
   the same doc as an `architecture.md` describing the system, and
   forcing them into one location is the awkward outcome.

8. **Two repeat syntaxes in one codebase is a smell.** BMAD's
   epics template uses `<!-- Repeat for each epic … -->` (author
   guidance) while document-project templates use `{{#each project_parts}}`
   (Handlebars). Each form is appropriate for its renderer (or
   lack thereof), but a doc author looking at both can reasonably
   wonder if there's a third right answer. gc-toolkit should pick
   one repeat-form per tier and stick to it.

9. **Three identical research templates is a maintenance smell.**
   `bmad-{domain,market,technical}-research/research.template.md`
   are byte-identical except for `{{research_type}}` substituted at
   runtime. A shared template plus per-skill overrides would
   reduce drift risk. Worth flagging: when the templates start to
   resemble each other, the deduplication is usually overdue
   already.

10. **`status: draft | ready-for-dev | in-progress | in-review | done`**
    (quick-dev spec) and **`backlog | ready-for-dev | in-progress |
    review | done`** (sprint-status, both per-story and per-epic)
    are *almost* the same enum but not quite — the former has
    `draft` and `in-review` (with hyphen); the latter has
    `backlog` and `review` (no hyphen) and adds `contexted`
    (legacy, backward-compat). If gc-toolkit ends up with a
    lifecycle enum, the cost of multiple near-identical enums is
    visible here: code that reads both has to special-case both
    names, and a doc author has to guess which spelling applies
    to a given file.
