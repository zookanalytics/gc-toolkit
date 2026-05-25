---
name: BMAD-Method Skill Catalog
description: Per-source survey of the BMAD-METHOD skill ecosystem (core-skills and bmm-skills) for the gc-toolkit ecosystem-skills audit (tk-1k0fay).
---

# BMAD-Method Skill Catalog

## Provenance

Source repository:
[bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)
Default branch: `main`
Pinned commit SHA: `ee47e30cf6bffb00eddfba4f4943df40071a3388` (2026-05-23)
Surveyed at: 2026-05-24

| Doc-type or artifact | Producer (skill / concept / workflow step that emits it upstream) | Source location (URL or repo path + commit SHA) | Surveyed at |
| --- | --- | --- | --- |
| Repo license | Repo root | [`LICENSE` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/LICENSE) | 2026-05-24 |
| Repo README | Repo root | [`README.md` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/README.md) | 2026-05-24 |
| Contributor guidelines / commit prefix rules | Repo root | [`CONTRIBUTING.md` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/CONTRIBUTING.md) | 2026-05-24 |
| Repo conventions for agents working in repo | Repo root | [`AGENTS.md` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/AGENTS.md) | 2026-05-24 |
| External module registry | Repo root | [`bmad-modules.yaml` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/bmad-modules.yaml) | 2026-05-24 |
| Skill validation rules (LLM + deterministic) | `tools/skill-validator.md` + `tools/validate-skills.js` | [`tools/skill-validator.md` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/tools/skill-validator.md) | 2026-05-24 |
| Core module manifest | `src/core-skills/module.yaml` | [`src/core-skills/module.yaml` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/module.yaml) | 2026-05-24 |
| Core skills routing catalog (CSV) | `src/core-skills/module-help.csv` | [`src/core-skills/module-help.csv` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/module-help.csv) | 2026-05-24 |
| Core skills (12 skills) | `src/core-skills/<skill>/SKILL.md` | [`src/core-skills/` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills) | 2026-05-24 |
| BMM module manifest + agent roster | `src/bmm-skills/module.yaml` | [`src/bmm-skills/module.yaml` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/module.yaml) | 2026-05-24 |
| BMM skills routing catalog (CSV) | `src/bmm-skills/module-help.csv` | [`src/bmm-skills/module-help.csv` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/module-help.csv) | 2026-05-24 |
| BMM phase-1 analysis skills (8) | `src/bmm-skills/1-analysis/<skill>/SKILL.md` (incl. `research/*`) | [`src/bmm-skills/1-analysis/` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis) | 2026-05-24 |
| BMM phase-2 plan-workflows skills (7) | `src/bmm-skills/2-plan-workflows/<skill>/SKILL.md` | [`src/bmm-skills/2-plan-workflows/` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows) | 2026-05-24 |
| BMM phase-3 solutioning skills (5) | `src/bmm-skills/3-solutioning/<skill>/SKILL.md` | [`src/bmm-skills/3-solutioning/` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/3-solutioning) | 2026-05-24 |
| BMM phase-4 implementation skills (12) | `src/bmm-skills/4-implementation/<skill>/SKILL.md` | [`src/bmm-skills/4-implementation/` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation) | 2026-05-24 |
| Worked schema example (PRD workflow skill) | `src/bmm-skills/2-plan-workflows/bmad-prd/` | [`bmad-prd/SKILL.md` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/SKILL.md), [`customize.toml` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/customize.toml) | 2026-05-24 |
| Worked schema example (multi-step workflow with `steps/`) | `src/core-skills/bmad-brainstorming/` | [`bmad-brainstorming/SKILL.md` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-brainstorming/SKILL.md), [`workflow.md` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-brainstorming/workflow.md) | 2026-05-24 |
| Worked schema example (agent-persona skill) | `src/bmm-skills/1-analysis/bmad-agent-analyst/` | [`bmad-agent-analyst/SKILL.md` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis/bmad-agent-analyst/SKILL.md) | 2026-05-24 |

## License

**MIT License**, copyright 2025 BMad Code, LLC. Source:
[`LICENSE` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/LICENSE).

The license file additionally carries a trademark notice covering
"BMad", "BMad Method", "BMad Core" (and casings/variants such as
BMAD, BMAD-METHOD), with details in
[`TRADEMARK.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/TRADEMARK.md).
Use of the software is MIT; use of the marks for derivative
branding is restricted — keep the trademark caveat visible when
citing BMAD's MIT status.

## Skill format / schema

BMAD adheres to the Agent Skills open standard
([agentskills.io/specification](https://agentskills.io/specification))
as documented in
[`tools/skill-validator.md` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/tools/skill-validator.md).
The validator file ships both the rule catalog (cited below) and an
explicit "Skill Spec Cheatsheet."

### Directory layout

A skill is a directory containing a required `SKILL.md` entrypoint
plus optional sibling resources. The conventional layout observed
across BMAD's named skills (44 total — 12 in `src/core-skills` and
32 in `src/bmm-skills`; see the catalog below for the breakdown):

```
<skill-dir>/                # directory name MUST equal SKILL.md frontmatter `name` (SKILL-05)
  SKILL.md                  # entrypoint — YAML frontmatter + markdown body (required)
  workflow.md               # optional — long-form workflow body when SKILL.md is a thin trampoline
  customize.toml            # optional — declares the `[workflow]` or `[agent]` override surface
  steps/                    # optional — micro-file step files (step-NN-description.md)
  references/               # optional — long-form reference docs loaded on demand (L3)
  assets/                   # optional — templates, HTML skeletons, checklists
  *.csv, *.md, *.html       # optional data and templates
```

### Frontmatter (L1 metadata, ~100 tokens)

Required fields per
[`skill-validator.md` rule catalog](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/tools/skill-validator.md):

- `name` (SKILL-02, SKILL-04, SKILL-05): must match regex
  `^bmad-[a-z0-9]+(-[a-z0-9]+)*$`, must equal the parent
  directory's basename, max 64 chars, no "anthropic"/"claude".
- `description` (SKILL-03, SKILL-06): max 1024 chars; should state
  both *what* the skill does AND *when* to use it (validator looks
  for "Use when" / "Use if" trigger phrases).

Step files (under `steps/`) must NOT carry `name:` or
`description:` frontmatter (STEP-06) — those are reserved for
`SKILL.md`. Step files must use names matching
`^step-\d{2}[a-z]?-[a-z0-9-]+\.md$` (STEP-01) and a workflow should
have between 2 and 10 step files (STEP-07).

### Body (L2 instructions, target <5k tokens / ~500 lines)

The cheatsheet says: "Keep SKILL.md under 500 lines." Body
sections that recur across BMAD skills (from observed SKILL.md
files):

- `# <Skill display title>` — H1 matching the skill's role.
- `## Overview` — purpose + role statement (sometimes labeled
  `**Goal:**` / `**Your Role:**` inline).
- `## Conventions` — boilerplate explaining path resolution: bare
  paths resolve from skill root, `{skill-root}` is the install
  dir, `{project-root}` is the project working dir, `{skill-name}`
  is the directory basename.
- `## On Activation` — numbered activation steps following a
  similar shape across skills (exact count varies; persona skills
  may extend it — e.g., `bmad-agent-analyst` has eight). The
  common backbone: (1) resolve customization via `python3
  {project-root}/_bmad/scripts/resolve_customization.py --skill
  {skill-root} --key workflow` (or `--key agent`), (2) execute
  `activation_steps_prepend`, (3) load persistent facts, (4) load
  config from `{project-root}/_bmad/bmm/config.yaml`, (5) greet
  `{user_name}` in `{communication_language}`, (6) execute
  `activation_steps_append`. See e.g.
  [`bmad-dev-story/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-dev-story/SKILL.md),
  [`bmad-prd/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/SKILL.md).
- `## Paths` — variables that point to external project paths
  (e.g. `sprint_status = {implementation_artifacts}/sprint-status.yaml`).
  Per PATH-04, intra-skill paths must NOT be variable-ized.
- `## Execution` / `## Discovery` / `## Finalize` — skill-specific
  body.
- For multi-step workflows: SKILL.md may be a trampoline (`Follow
  the instructions in ./workflow.md.`) and the real flow lives in
  `workflow.md` + numbered `steps/step-NN-*.md` files.

### L3 resources (unlimited, loaded on demand)

Validator cheatsheet defines progressive disclosure:

- **L1 metadata** (~100 tokens): `name` + `description` loaded at
  startup into system prompt.
- **L2 instructions** (<5k tokens): SKILL.md body loaded only when
  skill is triggered.
- **L3 resources** (unlimited): additional files + scripts
  loaded/executed on demand; script output enters context, script
  code does not.

References/assets live in `references/` and `assets/` subdirs.
Example:
[`bmad-prd/references/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/references)
holds `headless.md` (headless mode protocol) and `validate.md`
(validation rubric);
[`bmad-prd/assets/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/assets)
holds `prd-template.md`, `prd-validation-checklist.md`,
`validation-report-template.html`, `headless-schemas.md`.

### `customize.toml` override surface

Each customizable skill ships a `customize.toml` with either an
`[agent]` table (for persona skills) or a `[workflow]` table (for
workflow skills). The file carries a `DO NOT EDIT` banner —
operators override via either
`{project-root}/_bmad/custom/<skill-name>.toml` (team scope) or
`{project-root}/_bmad/custom/<skill-name>.user.toml` (personal
scope). Merge order: base → team → user, with structural rules:
scalars override, tables deep-merge, arrays of tables keyed by
`code` or `id` replace matching entries and append new entries,
other arrays append. Source:
[`bmad-prd/customize.toml` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/customize.toml).

Common `[workflow]` keys observed in `bmad-prd/customize.toml`:

- `activation_steps_prepend`, `activation_steps_append` —
  pre-/post-activation hooks (arrays of instructions or `skill:` /
  `file:` references).
- `persistent_facts` — facts the skill carries for the run;
  `file:` prefix loads referenced contents, plain strings are
  verbatim instructions.
- `on_complete` — instructions to run after workflow completion.
- `prd_template`, `validation_checklist_template`,
  `validation_report_template` — overridable asset paths.
- `prd_output_path`, `run_folder_pattern` — output destination.
- `finalize_reviewers`, `doc_standards`, `external_handoffs`,
  `external_sources` — extension registries.

### Worked schema example — `bmad-prd` SKILL.md frontmatter

From
[`src/bmm-skills/2-plan-workflows/bmad-prd/SKILL.md` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/SKILL.md):

```yaml
---
name: bmad-prd
description: Create, update, or validate a PRD. Use when the user wants help producing, editing, or validating a PRD.
---
```

The body opens with a one-paragraph role statement, then
`## Conventions`, `## On Activation` (six-step), `## Intent Modes`
(Create / Update / Validate), `## Discovery` (Brain dump → Stakes
calibration → Working mode → mode-scoped work), `## PRD
Discipline`, `## Reviewer Gate`, `## Finalize`. Sibling files:
`customize.toml`, `references/headless.md`, `references/validate.md`,
`assets/prd-template.md`, `assets/prd-validation-checklist.md`,
`assets/validation-report-template.html`,
`assets/headless-schemas.md`.

### Two-tier organization: `core-skills` vs `bmm-skills`

The two tiers are separate modules with separate `module.yaml`
files:

- **`src/core-skills/`** (module code `core`, name "BMad Core
  Module") — "Shared utilities across modules" (per
  [`src/core-skills/module.yaml` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/module.yaml)).
  Provides cross-cutting capabilities (review, brainstorming, doc
  indexing/sharding, advanced elicitation, party mode, customize,
  help router). All entries in the core CSV use phase `anytime` —
  they are not tied to lifecycle position.
- **`src/bmm-skills/`** (module code `bmm`, name "BMad Method") —
  "Full-lifecycle AI agile development: analysis, planning,
  architecture, implementation" (per
  [`src/bmm-skills/module.yaml` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/module.yaml)).
  Skills are partitioned into four numbered phase directories:
  `1-analysis/`, `2-plan-workflows/`, `3-solutioning/`,
  `4-implementation/`. Many bmm skills are tagged `anytime` in the
  CSV too, but the four phase folders structure a
  "scale-domain-adaptive" lifecycle flow.

`bmm-skills/module.yaml` additionally declares a named `agents:`
roster with six personas (`bmad-agent-analyst` Mary,
`bmad-agent-tech-writer` Paige, `bmad-agent-pm` John,
`bmad-agent-ux-designer` Sally, `bmad-agent-architect` Winston,
`bmad-agent-dev` Amelia). The core module declares no agent
roster.

External modules (TEA, BMB, CIS, GDS, WDS) live in separate repos
and are registered in
[`bmad-modules.yaml` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/bmad-modules.yaml);
they are out of scope for this survey.

### Validator rule catalog (summarized)

[`tools/skill-validator.md` @ ee47e30](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/tools/skill-validator.md)
enumerates 24 rules across 6 categories. The deterministic checker
`node tools/validate-skills.js` covers 12 rules; an LLM judgment
pass covers the rest.

- **SKILL-01..07** — SKILL.md existence, frontmatter (`name`,
  `description`), `name` format/match, body non-empty.
- **WF-03** — workflow.md frontmatter must hold only config or
  runtime variables (no intra-skill path variables).
- **PATH-01..05** — relative-path discipline for internal
  references; no `installed_path` variable (anti-pattern); external
  refs must use `{project-root}` or config vars; no path
  references into other skills' directories (encapsulation); no
  intra-skill path variables.
- **STEP-01..07** — step file naming, goal section required,
  `## NEXT` link required, HALT before any menu, no
  forward-loading future steps, no `name`/`description` in step
  frontmatter, step count 2-10.
- **SEQ-01..02** — no "skip step" instructions; no time estimates.
- **REF-01..03** — every `{variable}` must resolve; every file
  path must point to a plausible file; skill-to-skill references
  must use the verb "invoke" (not "read", "follow", "load",
  "execute"), canonical form `Invoke the \`skill-name\` skill`.

## Skill catalog

All 44 named skills enumerated across the two modules (12 core +
32 BMM). Phase column uses `core` for core-skills tier and `bmm-N`
(1-4) for bmm-skills tier. Triggers are quoted from each skill's
`description` frontmatter field (the "Use when..." clause where
present).

### Core-skills tier (12 skills) — `src/core-skills/`

| Tier | Name | 1-line purpose | Path | When-to-invoke trigger |
| --- | --- | --- | --- | --- |
| core | `bmad-advanced-elicitation` | Push the LLM to reconsider, refine, and improve its recent output. | [`src/core-skills/bmad-advanced-elicitation/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-advanced-elicitation) | "Use when user asks for deeper critique or mentions a known deeper critique method, e.g. socratic, first principles, pre-mortem, red team." |
| core | `bmad-brainstorming` | Facilitate interactive brainstorming sessions using diverse creative techniques and ideation methods. | [`src/core-skills/bmad-brainstorming/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-brainstorming) | "Use when the user says help me brainstorm or help me ideate." |
| core | `bmad-customize` | Authors and updates customization overrides for installed BMad skills. | [`src/core-skills/bmad-customize/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-customize) | "Use when the user says 'customize bmad', 'override a skill', 'change agent behavior', or 'customize a workflow'." |
| core | `bmad-distillator` | Lossless LLM-optimized compression of source documents. | [`src/core-skills/bmad-distillator/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-distillator) | "Use when the user requests to 'distill documents' or 'create a distillate'." |
| core | `bmad-editorial-review-prose` | Clinical copy-editor that reviews text for communication issues. | [`src/core-skills/bmad-editorial-review-prose/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-editorial-review-prose) | "Use when user says review for prose or improve the prose" |
| core | `bmad-editorial-review-structure` | Structural editor that proposes cuts, reorganization, and simplification while preserving comprehension. | [`src/core-skills/bmad-editorial-review-structure/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-editorial-review-structure) | "Use when user requests structural review or editorial review of structure" |
| core | `bmad-help` | Analyzes current state and user query to answer BMad questions or recommend the next skill(s) to use. | [`src/core-skills/bmad-help/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-help) | "Use when user asks for help, bmad help, what to do next, or what to start with in BMad." |
| core | `bmad-index-docs` | Generates or updates an index.md to reference all docs in the folder. | [`src/core-skills/bmad-index-docs/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-index-docs) | "Use if user requests to create or update an index of all files in a specific folder" |
| core | `bmad-party-mode` | Orchestrates group discussions between installed BMAD agents — each agent is a real subagent with independent thinking. | [`src/core-skills/bmad-party-mode/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-party-mode) | "Use when user requests party mode, wants multiple agent perspectives, group discussion, roundtable, or multi-agent conversation about their project." |
| core | `bmad-review-adversarial-general` | Cynical Review that produces a findings report. | [`src/core-skills/bmad-review-adversarial-general/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-review-adversarial-general) | "Use when the user requests a critical review of something" |
| core | `bmad-review-edge-case-hunter` | Walks every branching path and boundary condition; reports only unhandled edge cases (method-driven, not attitude-driven). | [`src/core-skills/bmad-review-edge-case-hunter/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-review-edge-case-hunter) | "Use when you need exhaustive edge-case analysis of code, specs, or diffs." |
| core | `bmad-shard-doc` | Splits large markdown documents into smaller, organized files based on level 2 (default) sections. | [`src/core-skills/bmad-shard-doc/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-shard-doc) | "Use if the user says perform shard document" |

### BMM tier phase 1 — analysis (8 skills) — `src/bmm-skills/1-analysis/`

| Tier | Name | 1-line purpose | Path | When-to-invoke trigger |
| --- | --- | --- | --- | --- |
| bmm-1 | `bmad-agent-analyst` | Persona skill — Mary, strategic business analyst and requirements expert. | [`src/bmm-skills/1-analysis/bmad-agent-analyst/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis/bmad-agent-analyst) | "Use when the user asks to talk to Mary or requests the business analyst." |
| bmm-1 | `bmad-agent-tech-writer` | Persona skill — Paige, technical documentation specialist and knowledge curator. Multi-action (write, mermaid, validate, explain, update-standards). | [`src/bmm-skills/1-analysis/bmad-agent-tech-writer/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis/bmad-agent-tech-writer) | "Use when the user asks to talk to Paige or requests the tech writer." |
| bmm-1 | `bmad-document-project` | Document brownfield projects for AI context. | [`src/bmm-skills/1-analysis/bmad-document-project/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis/bmad-document-project) | "Use when the user says 'document this project' or 'generate project docs'" |
| bmm-1 | `bmad-prfaq` | Working Backwards PRFAQ challenge to forge product concepts. | [`src/bmm-skills/1-analysis/bmad-prfaq/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis/bmad-prfaq) | "Use when the user requests to 'create a PRFAQ', 'work backwards', or 'run the PRFAQ challenge'." |
| bmm-1 | `bmad-product-brief` | Create, update, or validate a product brief. | [`src/bmm-skills/1-analysis/bmad-product-brief/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis/bmad-product-brief) | "Use when the user wants help producing, editing, or validating a brief." |
| bmm-1 | `bmad-domain-research` | Conduct domain and industry research using current web data with verified sources. | [`src/bmm-skills/1-analysis/research/bmad-domain-research/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis/research/bmad-domain-research) | "Use when the user says wants to do domain research for a topic or industry" |
| bmm-1 | `bmad-market-research` | Conduct market research on competition and customers. | [`src/bmm-skills/1-analysis/research/bmad-market-research/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis/research/bmad-market-research) | "Use when the user says they need market research" |
| bmm-1 | `bmad-technical-research` | Conduct technical research on technologies and architecture. | [`src/bmm-skills/1-analysis/research/bmad-technical-research/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis/research/bmad-technical-research) | "Use when the user says they would like to do or produce a technical research report" |

### BMM tier phase 2 — plan-workflows (7 skills) — `src/bmm-skills/2-plan-workflows/`

| Tier | Name | 1-line purpose | Path | When-to-invoke trigger |
| --- | --- | --- | --- | --- |
| bmm-2 | `bmad-agent-pm` | Persona skill — John, product manager for PRD creation and requirements discovery. | [`src/bmm-skills/2-plan-workflows/bmad-agent-pm/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-agent-pm) | "Use when the user asks to talk to John or requests the product manager." |
| bmm-2 | `bmad-agent-ux-designer` | Persona skill — Sally, UX designer and UI specialist. | [`src/bmm-skills/2-plan-workflows/bmad-agent-ux-designer/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-agent-ux-designer) | "Use when the user asks to talk to Sally or requests the UX designer." |
| bmm-2 | `bmad-prd` | Create, update, or validate a PRD (single skill with three intent modes). | [`src/bmm-skills/2-plan-workflows/bmad-prd/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd) | "Use when the user wants help producing, editing, or validating a PRD." |
| bmm-2 | `bmad-create-prd` | DEPRECATED shim — consolidated into `bmad-prd` create intent (will be removed in v7). | [`src/bmm-skills/2-plan-workflows/bmad-create-prd/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-create-prd) | (deprecated; description marks it as such) |
| bmm-2 | `bmad-edit-prd` | DEPRECATED shim — consolidated into `bmad-prd` update intent (will be removed in v7). | [`src/bmm-skills/2-plan-workflows/bmad-edit-prd/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-edit-prd) | (deprecated) |
| bmm-2 | `bmad-validate-prd` | DEPRECATED shim — consolidated into `bmad-prd` validate intent (will be removed in v7). | [`src/bmm-skills/2-plan-workflows/bmad-validate-prd/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-validate-prd) | (deprecated) |
| bmm-2 | `bmad-ux` | Plan UX patterns and design specifications. Produces DESIGN.md + EXPERIENCE.md. | [`src/bmm-skills/2-plan-workflows/bmad-ux/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-ux) | "Use when the user says 'lets create UX design' or 'create UX specifications' or 'help me plan the UX'" |

### BMM tier phase 3 — solutioning (5 skills) — `src/bmm-skills/3-solutioning/`

| Tier | Name | 1-line purpose | Path | When-to-invoke trigger |
| --- | --- | --- | --- | --- |
| bmm-3 | `bmad-agent-architect` | Persona skill — Winston, system architect and technical design leader. | [`src/bmm-skills/3-solutioning/bmad-agent-architect/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/3-solutioning/bmad-agent-architect) | "Use when the user asks to talk to Winston or requests the architect." |
| bmm-3 | `bmad-check-implementation-readiness` | Validate PRD, UX, Architecture and Epics specs are complete and aligned. | [`src/bmm-skills/3-solutioning/bmad-check-implementation-readiness/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/3-solutioning/bmad-check-implementation-readiness) | "Use when the user says 'check implementation readiness'." |
| bmm-3 | `bmad-create-architecture` | Create architecture solution design decisions for AI agent consistency. | [`src/bmm-skills/3-solutioning/bmad-create-architecture/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/3-solutioning/bmad-create-architecture) | "Use when the user says 'lets create architecture' or 'create technical architecture' or 'create a solution design'" |
| bmm-3 | `bmad-create-epics-and-stories` | Break requirements into epics and user stories. | [`src/bmm-skills/3-solutioning/bmad-create-epics-and-stories/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/3-solutioning/bmad-create-epics-and-stories) | "Use when the user says 'create the epics and stories list'" |
| bmm-3 | `bmad-generate-project-context` | Create `project-context.md` containing critical rules, patterns, and guidelines AI agents must follow. | [`src/bmm-skills/3-solutioning/bmad-generate-project-context/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/3-solutioning/bmad-generate-project-context) | "Use when the user says 'generate project context' or 'create project context'" |

### BMM tier phase 4 — implementation (12 skills) — `src/bmm-skills/4-implementation/`

| Tier | Name | 1-line purpose | Path | When-to-invoke trigger |
| --- | --- | --- | --- | --- |
| bmm-4 | `bmad-agent-dev` | Persona skill — Amelia, senior software engineer for story execution and code implementation. | [`src/bmm-skills/4-implementation/bmad-agent-dev/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-agent-dev) | "Use when the user asks to talk to Amelia or requests the developer agent." |
| bmm-4 | `bmad-checkpoint-preview` | LLM-assisted human-in-the-loop review — make sense of a change, focus attention where it matters, test. | [`src/bmm-skills/4-implementation/bmad-checkpoint-preview/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-checkpoint-preview) | "Use when the user says 'checkpoint', 'human review', or 'walk me through this change'." |
| bmm-4 | `bmad-code-review` | Review code changes adversarially using parallel review layers (Blind Hunter, Edge Case Hunter, Acceptance Auditor) with structured triage. | [`src/bmm-skills/4-implementation/bmad-code-review/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-code-review) | "Use when the user says 'run code review' or 'review this code'" |
| bmm-4 | `bmad-correct-course` | Manage significant changes during sprint execution; produce a Sprint Change Proposal. | [`src/bmm-skills/4-implementation/bmad-correct-course/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-correct-course) | "Use when the user says 'correct course' or 'propose sprint change'" |
| bmm-4 | `bmad-create-story` | Create a dedicated story file with all the context the agent will need to implement it later. Multi-action (create, validate). | [`src/bmm-skills/4-implementation/bmad-create-story/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-create-story) | "Use when the user says 'create the next story' or 'create story [story identifier]'" |
| bmm-4 | `bmad-dev-story` | Execute story implementation following a context-filled story spec file. | [`src/bmm-skills/4-implementation/bmad-dev-story/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-dev-story) | "Use when the user says 'dev this story [story file]' or 'implement the next story in the sprint plan'" |
| bmm-4 | `bmad-investigate` | Forensic case investigation with evidence-graded findings, calibrated to the input. Produces a structured case file. | [`src/bmm-skills/4-implementation/bmad-investigate/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-investigate) | "Use when the user asks to investigate a bug, trace what caused an incident, walk through unfamiliar code, or build a mental model of a code area before working on it." |
| bmm-4 | `bmad-qa-generate-e2e-tests` | Generate end-to-end automated tests for existing features. | [`src/bmm-skills/4-implementation/bmad-qa-generate-e2e-tests/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-qa-generate-e2e-tests) | "Use when the user says 'create qa automated tests for [feature]'" |
| bmm-4 | `bmad-quick-dev` | Unified intent-in / code-out workflow: clarify, plan, implement, review, present. | [`src/bmm-skills/4-implementation/bmad-quick-dev/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-quick-dev) | "Use when the user wants to build, fix, tweak, refactor, add or modify any code, component or feature." |
| bmm-4 | `bmad-retrospective` | Post-epic review to extract lessons and assess success. | [`src/bmm-skills/4-implementation/bmad-retrospective/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-retrospective) | "Use when the user says 'run a retrospective' or 'lets retro the epic [epic]'" |
| bmm-4 | `bmad-sprint-planning` | Generate sprint status tracking from epics; produce `sprint-status.yaml`. | [`src/bmm-skills/4-implementation/bmad-sprint-planning/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-sprint-planning) | "Use when the user says 'run sprint planning' or 'generate sprint plan'" |
| bmm-4 | `bmad-sprint-status` | Summarize sprint status, surface risks, recommend the next workflow action. | [`src/bmm-skills/4-implementation/bmad-sprint-status/`](https://github.com/bmad-code-org/BMAD-METHOD/tree/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-sprint-status) | "Use when the user says 'check sprint status' or 'show sprint status'" |

## Representative skills (3 detailed)

### 1. `bmad-prd` — workflow skill with full schema surface

Source:
[`SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/SKILL.md),
[`customize.toml`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/customize.toml).

**Opening prompt / hook (frontmatter):**

```yaml
---
name: bmad-prd
description: Create, update, or validate a PRD. Use when the user wants help producing, editing, or validating a PRD.
---
```

**Body section structure (H2 sequence):** `# BMad PRD` opening
role statement → `## Conventions` (path resolution rules) →
`## On Activation` (six-step numbered list; resolves customization
via `python3 {project-root}/_bmad/scripts/resolve_customization.py
--skill {skill-root} --key workflow`, runs prepend/append hooks,
loads persistent facts, loads config, greets in
`{communication_language}`, scans for misroute and offers
alternative skill if signal points elsewhere) → `## Intent Modes`
(three intent branches: **Create** binds `{doc_workspace}`, writes
`prd.md` + `.decision-log.md`; **Update** reconciles against
change signal; **Validate** critiques without changing, loads
`references/validate.md`) → `## Discovery` (Brain dump → Stakes
calibration → Working mode → mode-scoped work, with Research
subagents during discovery, Fast path vs Coaching path, Concern
scan, Form-factor probe, User Journeys captured not authored) →
`## PRD Discipline` (Essential Spine + Adapt-In Menu; "Extract,
don't ingest"; length scales with stakes) → `## Reviewer Gate`
(used by Validate intent and Finalize step 3; parallel subagents
write `review-{slug}.md` files, parent reads only summaries) →
`## Finalize` (eight numbered steps: decision-log audit → input
reconciliation → reviewer pass → triage open items → polish →
external handoffs → close → on_complete hook).

**Dependencies on other skills:** Mentioned in body as
alternatives via routing — `bmad-quick-dev`, `bmad-product-brief`,
`bmad-prfaq`, `bmad-workflow-builder`, `bmad-party-mode`,
`bmad-advanced-elicitation`, `bmad-help`, `bmad-ux`,
`bmad-create-architecture`, `bmad-create-epics-and-stories`.
`customize.toml` allows the operator to add `skill:` references in
`persistent_facts`, `doc_standards`, `finalize_reviewers`,
`external_handoffs` arrays.

**Artifacts produced:** `prd.md` (in
`{workflow.prd_output_path}/{workflow.run_folder_pattern}/`,
frontmatter carries `title`, `status: draft|final`, `created`,
`updated`), optional `addendum.md` (depth that doesn't fit the
PRD), `.decision-log.md` (canonical decision audit trail),
`review-{slug}.md` per reviewer subagent, `reconcile-{slug}.md`
per source input, optional HTML validation report via
`validation-report-template.html`.

**Supporting files:** `assets/prd-template.md`,
`assets/prd-validation-checklist.md` (judgment rubric, not
boolean), `assets/validation-report-template.html` (inline CSS, no
JS, uses native `<details>`), `assets/headless-schemas.md`,
`references/headless.md` (headless mode protocol),
`references/validate.md` (rubric walker prompt + synthesis
pipeline).

### 2. `bmad-brainstorming` — multi-step workflow with thin SKILL.md and `steps/` directory

Source:
[`SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-brainstorming/SKILL.md),
[`workflow.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-brainstorming/workflow.md).

**Opening prompt / hook (frontmatter):**

```yaml
---
name: bmad-brainstorming
description: 'Facilitate interactive brainstorming sessions using diverse creative techniques and ideation methods. Use when the user says help me brainstorm or help me ideate.'
---
```

**Body:** SKILL.md is a one-line trampoline: `Follow the
instructions in ./workflow.md.` This is the BMAD pattern for
skills whose flow is long enough to warrant external sharding. The
bulk of the L2 content lives in `workflow.md`.

**`workflow.md` structure:** Frontmatter (`context_file: ''` —
optional project-specific guidance file) → `# Brainstorming Session
Workflow` → `**Goal:**` / `**Your Role:**` / `**Critical
Mindset:**` (keep user in generative mode) / `**Anti-Bias
Protocol:**` (LLMs drift to semantic clustering — shift creative
domain every 10 ideas) / `**Quantity Goal:**` (100+ ideas before
any organization) → `## WORKFLOW ARCHITECTURE` (declares
micro-file architecture) → `## INITIALIZATION` (config load + path
setup) → `## EXECUTION` (dispatches to
`./steps/step-01-session-setup.md`).

**Steps:** Eight step files under `steps/`:

- `step-01-session-setup.md`
- `step-01b-continue.md` (variant — STEP-01 rule allows
  single-letter suffix for branches)
- `step-02a-user-selected.md`, `step-02b-ai-recommended.md`,
  `step-02c-random-selection.md`, `step-02d-progressive-flow.md`
  (four selection variants — branching step pattern)
- `step-03-technique-execution.md`
- `step-04-idea-organization.md`

**Dependencies on other skills:** None named in workflow.md. Loads
from `brain-methods.csv` (sibling data file) on demand.

**Artifacts produced:**
`{output_folder}/brainstorming/brainstorming-session-{{date}}-{{time}}.md`.
Double-curly braces `{{date}}`, `{{time}}` are templating
placeholders that survive into generated output (REF-01
exception).

### 3. `bmad-agent-analyst` — persona skill (Mary, Business Analyst)

Source:
[`SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis/bmad-agent-analyst/SKILL.md).

**Opening prompt / hook (frontmatter):**

```yaml
---
name: bmad-agent-analyst
description: Strategic business analyst and requirements expert. Use when the user asks to talk to Mary or requests the business analyst.
---
```

**Body section structure:** `# Mary — Business Analyst` →
`## Overview` (identity statement: "You are Mary, the Business
Analyst...") → `## Conventions` (path resolution) → `## On
Activation` (eight steps for this skill — persona skills can extend
the base activation skeleton; resolves customization with `--key
agent` instead of `--key workflow`; the `Adopt Persona` step
embodies persona from Overview AND layers customized
`{agent.role}`, `{agent.identity}`, `{agent.communication_style}`,
`{agent.principles}`; the greeting step prefixes `{agent.icon}` and
continues to do so throughout the session). Persona persists when
the user invokes other skills.

**Dependencies on other skills:** Tells user `bmad-help` is
available. The skill itself does not invoke other skills directly
— instead the persona stays active and the user invokes workflow
skills (the persona "layers" onto subsequent invocations).

**Artifacts produced:** No file artifacts. The skill produces a
maintained persona state and conversational output. The
`customize.toml` `[agent]` table is the override surface; the
canonical roster (Mary's `code`, `name`, `title`, `icon`, `team`,
`description`) lives in `src/bmm-skills/module.yaml` so other
skills (party-mode, retrospective, advanced-elicitation, help
catalog) can read descriptors to route, display, and embody
agents.

**Roster of personas:** Six total (from
`src/bmm-skills/module.yaml`):

- `bmad-agent-analyst` — Mary, Business Analyst, "Speaks like a
  treasure hunter narrating the find"
- `bmad-agent-tech-writer` — Paige, Technical Writer, "Speaks like
  the patient teacher you wish you'd had"
- `bmad-agent-pm` — John, Product Manager, "Speaks like a detective
  interrogating a cold case"
- `bmad-agent-ux-designer` — Sally, UX Designer, "Speaks like a
  filmmaker pitching the scene"
- `bmad-agent-architect` — Winston, System Architect, "Speaks like
  a seasoned engineer at the whiteboard"
- `bmad-agent-dev` — Amelia, Senior Software Engineer, "Speaks like
  a terminal prompt: exact file paths, AC IDs, and commit-message
  brevity"

## Notable conventions

These are conventions distinctive to BMAD's approach, distilled
from the surveyed files. Each citation pins to file + commit SHA.

### Phase-keyed organization

BMM skills live in four numbered phase directories
(`1-analysis/`, `2-plan-workflows/`, `3-solutioning/`,
`4-implementation/`) that match the documented agile lifecycle the
module advertises ("Full-lifecycle AI agile development: analysis,
planning, architecture, implementation" per
[`src/bmm-skills/module.yaml`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/module.yaml)).
The `phase` column in `module-help.csv`
([source](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/module-help.csv))
uses `1-analysis`, `2-planning`, `3-solutioning`,
`4-implementation`, or `anytime`. The core module always uses
`anytime`.

### Named-agent personas with literary personality

Six BMM persona skills (`bmad-agent-*`) define named characters
with explicit voice/tone descriptors in
`src/bmm-skills/module.yaml`. The roster format
([source](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/module.yaml))
carries `code`, `name`, `title`, `icon` (emoji), `team`,
`description` (which combines principles and a "Speaks like X"
simile). The persona is layered on top of customization
(`{agent.role}`, `{agent.identity}`, `{agent.communication_style}`,
`{agent.principles}` from `customize.toml`'s `[agent]` table) —
base persona is the canonical "Mary", but operators override
behavior.

### Three-level progressive disclosure

[`tools/skill-validator.md` cheatsheet](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/tools/skill-validator.md)
makes the token budget explicit: L1 metadata (~100 tokens, always
loaded), L2 instructions (<5k tokens, loaded on trigger), L3
resources (unlimited, loaded on demand). "SKILL.md under 500
lines" is the body-size hard guidance.

### "Invoke", not "read" — skill encapsulation as an enforced rule

REF-03 in the validator forbids file-oriented verbs ("read",
"follow", "load", "execute", "run") when referring to another
skill — canonical phrasing is `Invoke the \`skill-name\` skill`.
PATH-05 forbids any file-path reference into another skill's
directory. Together these rules treat skills as opaque units, not
as filesystems other skills can reach into.

### `customize.toml` override system with three-layer merge

Each skill carries a base `customize.toml` with `DO NOT EDIT`
banner; operators override via `_bmad/custom/<skill>.toml` (team)
and `_bmad/custom/<skill>.user.toml` (personal). Merge resolution
is performed by a Python script
`_bmad/scripts/resolve_customization.py`; structural rules are
`scalars override, tables deep-merge, arrays of tables keyed by
code or id replace matching entries and append new entries, other
arrays append`. The same `## On Activation` step-1 boilerplate
appears in every workflow and persona SKILL.md, including the
literal fallback procedure for when the script fails. Source:
[`bmad-prd/customize.toml`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/customize.toml),
[`bmad-dev-story/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-dev-story/SKILL.md).

### Reference-prefix vocabulary: `skill:`, `file:`, plain text

`persistent_facts`, `finalize_reviewers`, `doc_standards`,
`activation_steps_prepend` etc. accept arrays of three kinds of
entries (per `bmad-prd/customize.toml` comments):

- `skill:skill-name` — invoke another skill as a unit.
- `file:{project-root}/path/to/file.md` — load file contents as
  facts (glob supported).
- Plain text — verbatim agent instruction.

### Sharded multi-step workflows under `steps/`

Long workflows (`bmad-brainstorming`, `bmad-create-architecture`,
`bmad-create-epics-and-stories`, `bmad-create-story`,
`bmad-document-project`, `bmad-correct-course`, `bmad-quick-dev`,
others) ship SKILL.md as a thin trampoline that forwards to
`workflow.md`, which dispatches into `steps/step-NN-description.md`
files. Step file rules (STEP-01..07): zero-padded NN with optional
letter variant suffix, no `name`/`description` frontmatter
(STEP-06), goal section required, `## NEXT` link required (except
terminal), HALT before any menu (STEP-04), no forward-loading
(STEP-05), 2-10 steps total (STEP-07). Variant suffixes like
`step-01b-continue.md`, `step-02a-user-selected.md` are reserved
for branching paths.

### Routing via CSV catalog (`module-help.csv`)

Each module ships a `module-help.csv`
([core](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/module-help.csv),
[bmm](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/module-help.csv))
with columns
`module,skill,display-name,menu-code,description,action,args,phase,preceded-by,followed-by,required,output-location,outputs`.
The `bmad-help` skill
([source](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-help/SKILL.md))
reads the assembled catalog (`_bmad/_config/bmad-help.csv`) plus
rows tagged `_meta` (which carry a URL or path to module
documentation) to route users to the next skill. `menu-code` is a
2-3 letter shortcode (PRD, CR, DS, SP, etc.) presented in the help
UI. `preceded-by` / `followed-by` are soft routing hints;
`required=true` marks gating skills. `action` and `args` columns
enable a single skill to expose multiple invocations (e.g.,
`bmad-agent-tech-writer` exposes `write`, `mermaid`, `validate`,
`explain`, `update-standards` actions).

### Multi-action skills via `action` column

`bmad-agent-tech-writer` and `bmad-create-story` use the CSV
`action` column to expose multiple entry points under one skill
directory. Action invocation context is part of the response when
`bmad-help` recommends them (e.g., "tech-writer lets create a
mermaid diagram!" per the response-format rules in
[`bmad-help/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-help/SKILL.md)).

### Shared activation skeleton

Workflow and persona SKILL.md files share a similar `## On
Activation` shape but exact step counts vary by skill. The common
backbone: (1) resolve customization via the Python script, (2)
prepend hooks, (3) load persistent facts / adopt persona, (4) load
config from `{project-root}/_bmad/bmm/config.yaml`, (5) greet
`{user_name}` in `{communication_language}`, (6) append hooks.
Persona skills can extend this — e.g.,
[`bmad-agent-analyst`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/1-analysis/bmad-agent-analyst/SKILL.md)
runs an eight-step activation. Examples of skills following the
shape:
[`bmad-prd`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/SKILL.md),
[`bmad-dev-story`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-dev-story/SKILL.md).

### Language honoring throughout the run

The greet step explicitly says: "stay in
`{communication_language}` for every turn for the entire run, not
just the greeting." Documents are output in
`{document_output_language}` (separately configured). Chat-language
and doc-language are distinct config keys
([`src/core-skills/module.yaml`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/module.yaml)).

### Skill-level work modes: Fast path vs Coaching path

Multiple BMM skills (`bmad-prd`, `bmad-ux`, `bmad-product-brief`)
expose the same two-mode choice. Fast path batches gaps into 1-2
consolidated questions and drafts the full artifact with
`[ASSUMPTION]` tags. Coaching path walks the user through sections
together. Source:
[`bmad-prd/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/SKILL.md)
`## Discovery → Working mode`.

### Subagent extraction discipline ("Extract, don't ingest")

Workflow skills push source documents to subagents for extraction;
the parent assembles from compact returned summaries. Reviewers
and reconciliation each write their full review/extract to
`{doc_workspace}/review-{slug}.md` / `reconcile-{slug}.md` and
return only verdicts + top findings. The parent reads the full
file only when the user drills into a specific finding. Source:
[`bmad-prd/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/SKILL.md)
`## Reviewer Gate`, `## PRD Discipline`.

### Decision-log convention

`bmad-prd` (and likely peer planning skills) maintain a
`.decision-log.md` as "canonical memory and audit trail — every
decision, change, and override (including headless overrides) is
recorded there as the conversation unfolds." A separate
`addendum.md` holds user-contributed depth that doesn't fit the
main artifact. Source:
[`bmad-prd/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-prd/SKILL.md).

### Adversarial review pluralism

Three named review skills run in parallel under `bmad-code-review`:
Blind Hunter, Edge Case Hunter, Acceptance Auditor. The standalone
`bmad-review-edge-case-hunter` is "method-driven, not
attitude-driven" — "Never comment on whether code is good or bad;
only list missing handling." Distinct from
`bmad-review-adversarial-general`'s "Cynical Review". Sources:
[`bmad-code-review/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/4-implementation/bmad-code-review/SKILL.md),
[`bmad-review-edge-case-hunter/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-review-edge-case-hunter/SKILL.md).

### Conventional Commits with explicit type set

Per
[`AGENTS.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/AGENTS.md)
and
[`CONTRIBUTING.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/CONTRIBUTING.md):
Conventional Commits required, types `feat:`, `fix:`, `docs:`,
`refactor:`, `test:`, `chore:`. Commit message under 72 chars.
Each commit = one logical change. Trunk-based development on
`main`; every push auto-publishes to `npm` under the `next` tag,
stable cuts roughly weekly to `latest`.

### Skill validation gate before push

Per
[`AGENTS.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/AGENTS.md):
"Before pushing, run `npm ci && npm run quality` on `HEAD` in the
exact checkout you are about to push. `quality` mirrors the
checks in `.github/workflows/quality.yaml`." `npm run
validate:skills` is included in `quality` and runs the
deterministic skill-validator pass.

### Deprecated-skill shim pattern

`bmad-create-prd`, `bmad-edit-prd`, `bmad-validate-prd` are
explicit DEPRECATED stubs that "forward to `bmad-prd`" with the
appropriate intent. Each ships a SKILL.md whose `description`
starts with `'DEPRECATED — consolidated into bmad-prd ... - this
skill will be removed in v7'` and a body that explains they're
retained "as a thin compatibility shim so existing invocations by
name and `_bmad/custom/<old-name>.toml` override files keep
working." Sources:
[`bmad-create-prd/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-create-prd/SKILL.md),
[`bmad-edit-prd/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-edit-prd/SKILL.md),
[`bmad-validate-prd/SKILL.md`](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/bmm-skills/2-plan-workflows/bmad-validate-prd/SKILL.md).

### Multi-agent "party mode" via real subagents

`bmad-party-mode`
([source](https://github.com/bmad-code-org/BMAD-METHOD/blob/ee47e30cf6bffb00eddfba4f4943df40071a3388/src/core-skills/bmad-party-mode/SKILL.md))
spawns each agent as an independent subagent process via the
Agent tool, on the explicit theory that one LLM roleplaying
multiple characters produces converged "performative" opinions.
The `--solo` flag fallback roleplays all selected agents from one
LLM, but the default is real-subagent dispatch. The `--model` flag
forces a specific model (e.g. `haiku` for reactive rounds, default
for deep topics).

### Naming convention

All skills start with the `bmad-` prefix and are kebab-case
(SKILL-04 enforces). Directory name == frontmatter `name`
(SKILL-05 enforces). Persona skills follow the
`bmad-agent-<role>` sub-pattern (analyst, tech-writer, pm,
ux-designer, architect, dev). Research skills follow
`bmad-<domain>-research`. Skills that produce/edit/validate one
artifact often consolidate into one skill with intent detection
(`bmad-prd` covers create/update/validate); the older multi-skill
pattern (`bmad-create-prd`, `bmad-edit-prd`, `bmad-validate-prd`)
is being deprecated.

### Repo structure overview (for the survey's traceability)

- `src/core-skills/` — 12 skills + `module.yaml` + `module-help.csv`
- `src/bmm-skills/` — 32 skills across 4 phase folders +
  `module.yaml` + `module-help.csv`
- `src/scripts/` — installer-side scripts (out of scope for skill
  content)
- `tools/skill-validator.md` + `tools/validate-skills.js` —
  validation rule catalog + deterministic checker
- `bmad-modules.yaml` — external-module registry (5 official
  BMad-org modules: TEA, BMB, CIS, GDS, WDS — plus `automator`,
  marked experimental upstream)

External modules (Test Architect, BMad Builder, Creative
Intelligence Suite, Game Dev Studio, Whiteport Design Studio) are
separate npm packages registered in `bmad-modules.yaml` and were
not surveyed; this catalog covers only the in-tree `core` + `bmm`
skills.
