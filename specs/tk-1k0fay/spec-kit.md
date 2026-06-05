---
name: Spec Kit Command Catalog
description: Per-source survey of github/spec-kit — a spec-driven-development command set (skill-adjacent) — for the gc-toolkit ecosystem-skills audit (tk-1k0fay).
---

# Spec Kit Command Catalog

| Doc-type or artifact | Producer (skill / concept / workflow step that emits it upstream) | Source location (URL or repo path + commit SHA) | Surveyed at |
| --- | --- | --- | --- |
| Repo root (default branch `main`) | github/spec-kit maintainers | https://github.com/github/spec-kit/tree/a08af08415432db2ae15b70e82400eaad9dbfd2f | 2026-05-24 |
| LICENSE | github/spec-kit (project root) | https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/LICENSE | 2026-05-24 |
| README.md | github/spec-kit (project root) | https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/README.md | 2026-05-24 |
| AGENTS.md (integration architecture) | github/spec-kit (project root) | https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/AGENTS.md | 2026-05-24 |
| spec-driven.md (SDD philosophy) | github/spec-kit (project root) | https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/spec-driven.md | 2026-05-24 |
| `templates/commands/*.md` (command definitions) | upstream maintainers; installed into the user's project via Specify CLI integrations | https://github.com/github/spec-kit/tree/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands | 2026-05-24 |
| `templates/spec-template.md`, `plan-template.md`, `tasks-template.md`, `constitution-template.md`, `checklist-template.md` | commands above (template-driven authoring) | https://github.com/github/spec-kit/tree/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates | 2026-05-24 |
| `scripts/bash/*.sh` and `scripts/powershell/*.ps1` (workflow helpers) | invoked by commands via `{SCRIPT}` token | https://github.com/github/spec-kit/tree/a08af08415432db2ae15b70e82400eaad9dbfd2f/scripts | 2026-05-24 |
| `src/specify_cli/integrations/` (Python CLI integration layer) | Specify CLI; lays commands into harness directories at install time | https://github.com/github/spec-kit/tree/a08af08415432db2ae15b70e82400eaad9dbfd2f/src/specify_cli/integrations | 2026-05-24 |
| `src/specify_cli/integrations/claude/__init__.py` (Claude Code skills integration) | Specify CLI (`SkillsIntegration` subclass) | https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/src/specify_cli/integrations/claude/__init__.py | 2026-05-24 |
| `src/specify_cli/integrations/base.py` (`SkillsIntegration` base class — `speckit-<name>/SKILL.md` layout) | Specify CLI base layer | https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/src/specify_cli/integrations/base.py | 2026-05-24 |

Pinned commit SHA: `a08af08415432db2ae15b70e82400eaad9dbfd2f`
(default branch `main`, committed 2026-05-22T19:00:32Z).

## License

MIT License, "Copyright GitHub, Inc.", at the repo root.

- File:
  [`LICENSE`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/LICENSE)
- Quoted opener: *"MIT License — Copyright GitHub, Inc. —
  Permission is hereby granted, free of charge, to any person
  obtaining a copy of this software and associated documentation
  files (the "Software"), to deal in the Software without
  restriction..."*
- GitHub API metadata reports SPDX id `MIT` for the repo.

## Command / artifact format (skill-adjacent)

Spec Kit does **not** use `SKILL.md` files in the main
command/template tree; one exists under
[`.github/skills/add-community-extension/SKILL.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/.github/skills/add-community-extension/SKILL.md)
(a community-extension authoring skill).
Each command is defined as a single markdown file under
[`templates/commands/`](https://github.com/github/spec-kit/tree/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands).
The Specify CLI then "installs" these command files into the
user's project, transforming them into whatever native format the
chosen harness expects (slash-commands, TOML recipes, YAML recipes
— and for harnesses with skills support, into
`speckit-<name>/SKILL.md` directories per the
[agentskills.io](https://agentskills.io/specification) layout).
The Claude Code integration is exactly such a `SkillsIntegration`:
installed commands land at `.claude/skills/speckit-<name>/SKILL.md`
(see
[`src/specify_cli/integrations/claude/__init__.py`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/src/specify_cli/integrations/claude/__init__.py)
and
[`SkillsIntegration` in base.py](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/src/specify_cli/integrations/base.py#L1332)).

**Source command file structure** (every file in
`templates/commands/`):

1. **YAML frontmatter** with these recognized keys:
   - `description` — single-line summary (required; all 9 commands
     carry one).
   - `handoffs` — optional list of suggested next commands; each
     entry has `label`, `agent` (dotted command name e.g.
     `speckit.plan`), `prompt`, and optional `send: true` to
     indicate auto-dispatch. Used to render UI hand-off chips.
   - `scripts` — optional `sh` (bash) and `ps` (PowerShell)
     entries pointing at helper scripts under `scripts/bash/` and
     `scripts/powershell/`. The `{SCRIPT}` token in the body is
     substituted at runtime.
   - `tools` — optional list of MCP/tool gates (e.g.
     `taskstoissues.md` declares `tools:
     ['github/github-mcp-server/issue_write']`).
2. **`## User Input`** block fenced with `$ARGUMENTS` — what the
   user typed after the slash command.
3. **`## Pre-Execution Checks`** — every command checks
   `.specify/extensions.yml` for `hooks.before_<command>` entries
   (optional/mandatory) and emits a standardized "Extension Hooks"
   block before doing work.
4. **`## Outline`** (or `## Execution Steps` / `## Goal`) —
   numbered procedural instructions to the agent: parse `{SCRIPT}`
   JSON output, load context files, generate/update artifacts,
   report completion.
5. **Optional `## Phases` / `## Task Generation Rules` / `## Quick
   Guidelines`** — domain-specific extra guidance.
6. **`## Post-Execution Checks`** — symmetric
   `hooks.after_<command>` scan.

**Filing convention** — most spec-kit commands write into a
single per-feature directory; `constitution` is project-level (it
edits `.specify/memory/constitution.md`) and `analyze` is strictly
read-only (no file writes). See
[`templates/plan-template.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/plan-template.md)
for the plan skeleton. The canonical per-feature layout is:

```text
specs/[###-feature-name]/
├── spec.md              # /speckit.specify
├── plan.md              # /speckit.plan
├── research.md          # /speckit.plan (Phase 0)
├── data-model.md        # /speckit.plan (Phase 1)
├── quickstart.md        # /speckit.plan (Phase 1)
├── contracts/           # /speckit.plan (Phase 1)
├── tasks.md             # /speckit.tasks
└── checklists/          # /speckit.checklist  (also: /speckit.specify writes requirements.md here)
    └── requirements.md
```

Where `[###-feature-name]` is a 3-digit sequential prefix plus a
2–4-word slug (e.g. `003-user-auth`), or a
`YYYYMMDD-HHMMSS-<slug>` timestamp prefix if
`.specify/init-options.json` has `"branch_numbering": "timestamp"`.
The resolved feature directory is persisted to
`.specify/feature.json` so downstream commands can locate it
without depending on git branch name. The branch name and the spec
directory name are **independent** — quoting
[`templates/commands/specify.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/specify.md):
*"The spec directory name and the git branch name are independent
— they may be the same but that is the user's choice."*

Project-level (non-per-feature) artifacts also live under stable
paths:

- `.specify/memory/constitution.md` — produced/updated by
  `/speckit.constitution`.
- `.specify/templates/` — runtime template lookup root (overrides →
  presets → extensions → core, as documented in the README's
  "Making Spec Kit Your Own" section).
- `.specify/extensions.yml` — opt-in hook registry consulted by
  every command's pre/post-execution checks.

## Command catalog

All paths below are relative to repo root at SHA
`a08af08415432db2ae15b70e82400eaad9dbfd2f`.

| Command | Purpose | Input | Artifact produced | Path to definition |
| --- | --- | --- | --- | --- |
| `/speckit.constitution` | Create or update project governing principles; propagate changes across plan/spec/tasks templates | Principles or values (free-form `$ARGUMENTS`); existing `.specify/memory/constitution.md` template | `.specify/memory/constitution.md` (overwritten) + Sync Impact Report HTML comment | [`templates/commands/constitution.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/constitution.md) |
| `/speckit.specify` | Create feature spec from a natural-language description; allocate the feature directory | Feature description (`$ARGUMENTS`); optional `GIT_BRANCH_NAME`, `SPECIFY_FEATURE_DIRECTORY` | `specs/<NNN-or-timestamp>-<slug>/spec.md` + `checklists/requirements.md` + `.specify/feature.json` | [`templates/commands/specify.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/specify.md) |
| `/speckit.clarify` | Detect ambiguity in active spec and ask up to 5 targeted questions, recording answers back into `spec.md` | Optional focus areas (`$ARGUMENTS`); runs `scripts/bash/check-prerequisites.sh --json --paths-only` | Edits `spec.md` in place (Clarifications log section) | [`templates/commands/clarify.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/clarify.md) |
| `/speckit.plan` | Run the implementation-planning workflow against `spec.md` and `constitution.md`; emit design artifacts | Optional planning guidance (`$ARGUMENTS`); runs `scripts/bash/setup-plan.sh --json` | `plan.md` + `research.md` (Phase 0) + `data-model.md`, `quickstart.md`, `contracts/` (Phase 1) under the feature directory | [`templates/commands/plan.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/plan.md) |
| `/speckit.tasks` | Generate a dependency-ordered, user-story-grouped `tasks.md` from available design artifacts | Optional task-generation constraints (`$ARGUMENTS`); runs `scripts/bash/setup-tasks.sh --json` | `tasks.md` under the feature directory | [`templates/commands/tasks.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/tasks.md) |
| `/speckit.analyze` | Non-destructive cross-artifact consistency / coverage / constitution-conflict analysis across `spec.md`, `plan.md`, `tasks.md` | Optional focus areas; runs `scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks`; **strictly read-only** | Markdown analysis report emitted to chat (no file writes); proposes optional remediation requiring user approval | [`templates/commands/analyze.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/analyze.md) |
| `/speckit.checklist` | Generate a custom domain-specific quality checklist ("unit tests for requirements writing") for the feature | Domain/focus area (`$ARGUMENTS`); runs `scripts/bash/check-prerequisites.sh --json` | `specs/<feature>/checklists/<name>.md` (e.g. `ux.md`, `test.md`, `security.md`) | [`templates/commands/checklist.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/checklist.md) |
| `/speckit.implement` | Execute tasks in `tasks.md` against the codebase, gated by checklist completion | Optional implementation guidance / task filter (`$ARGUMENTS`); runs `scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` | Source code changes in repo; creates/verifies `.gitignore`, `.dockerignore`, etc. per project detection; marks tasks in `tasks.md` as complete | [`templates/commands/implement.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/implement.md) |
| `/speckit.taskstoissues` | Convert `tasks.md` entries into GitHub issues against the current git remote (gated to GitHub remotes only) | Optional filter/label (`$ARGUMENTS`); declares `tools: ['github/github-mcp-server/issue_write']` | GitHub issues created on the remote matching `git config --get remote.origin.url` | [`templates/commands/taskstoissues.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/taskstoissues.md) |

Total: nine command files (`analyze`, `checklist`, `clarify`,
`constitution`, `implement`, `plan`, `specify`, `tasks`,
`taskstoissues`). README classifies them as **Core**
(`constitution`, `specify`, `plan`, `tasks`, `taskstoissues`,
`implement`) and **Optional** (`clarify`, `analyze`, `checklist`).

## Representative commands (detailed)

### 1. `/speckit.specify` — entry point

- **Definition:**
  [`templates/commands/specify.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/specify.md).
- **Frontmatter highlights:** `description`, plus `handoffs` to
  `speckit.plan` (label "Build Technical Plan") and
  `speckit.clarify` (label "Clarify Spec Requirements",
  `send: true`). No `scripts` key — the command provides its own
  resolution logic in the body.
- **Invocation context loaded:** The literal user message after the
  dispatch token (`__SPECKIT_COMMAND_SPECIFY__`),
  `templates/spec-template.md` for section structure,
  `.specify/extensions.yml` for pre/post hooks, and (optionally)
  `.specify/init-options.json` for `branch_numbering`
  ("sequential" → `NNN-` prefix; "timestamp" →
  `YYYYMMDD-HHMMSS-` prefix).
- **Procedure:** (1) generate a 2–4-word slug from the description
  (e.g. `"add user auth"` → `user-auth`); (2) optionally let a
  `before_specify` hook create a git branch; (3) resolve
  `SPECIFY_FEATURE_DIRECTORY` to `specs/<prefix>-<slug>`;
  (4) `mkdir -p`, copy `templates/spec-template.md` to `spec.md`;
  (5) populate the spec from the description with at most 3
  `[NEEDS CLARIFICATION: ...]` markers (prioritized scope >
  security > UX > technical); (6) write `.specify/feature.json`
  with the resolved directory; (7) generate a
  `checklists/requirements.md` quality checklist and run it
  iteratively (max 3 passes) — if NEEDS-CLARIFICATION markers
  remain, present a multiple-choice table (A/B/C/Custom) to the
  user; (8) report `SPECIFY_FEATURE_DIRECTORY`, `SPEC_FILE`,
  checklist status, and the next-phase suggestion.
- **Output artifacts:** `specs/<feature>/spec.md`,
  `specs/<feature>/checklists/requirements.md`, and the persisted
  `.specify/feature.json`.
- **Dependencies:** None (this is the workflow entry point). The
  README's "Get Started" sequence puts `/speckit.constitution`
  before `/speckit.specify` so the constitution exists when
  planning later runs, but `/speckit.specify` does not load it.

### 2. `/speckit.plan` — design artifact generator

- **Definition:**
  [`templates/commands/plan.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/plan.md).
- **Frontmatter highlights:** `description`, `handoffs` to
  `speckit.tasks` (`send: true`) and `speckit.checklist`,
  `scripts: { sh: scripts/bash/setup-plan.sh --json,
  ps: scripts/powershell/setup-plan.ps1 -Json }`.
- **Invocation context loaded:** JSON from `{SCRIPT}` providing
  `FEATURE_SPEC`, `IMPL_PLAN`, `SPECS_DIR`, `BRANCH`; then reads
  `FEATURE_SPEC` (the spec), `/memory/constitution.md`, and
  `templates/plan-template.md` (copied into the feature dir by
  the setup script).
- **Procedure:** Fills the plan template's Technical Context
  (marking unknowns as `NEEDS CLARIFICATION`); runs the
  Constitution Check gate; **Phase 0** (research): generates
  `research.md` resolving NEEDS-CLARIFICATION items with a
  "Decision / Rationale / Alternatives" format; **Phase 1**
  (design): writes `data-model.md`, `contracts/`, `quickstart.md`;
  updates agent context via the integration's agent script;
  re-evaluates the Constitution Check post-design; **stops after
  Phase 2 planning** (does not generate `tasks.md`).
- **Output artifacts:** `specs/<feature>/plan.md`, `research.md`,
  `data-model.md`, `quickstart.md`, `contracts/<...>`.
- **Dependencies:** Requires `spec.md` (so `/speckit.specify` must
  have run); reads `constitution.md` if present; downstream
  `/speckit.tasks` consumes its outputs.

### 3. `/speckit.tasks` — task list generator

- **Definition:**
  [`templates/commands/tasks.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/tasks.md).
- **Frontmatter highlights:** `description`, `handoffs` to
  `speckit.analyze` (`send: true`) and `speckit.implement`
  (`send: true`), `scripts: { sh: scripts/bash/setup-tasks.sh
  --json, ps: scripts/powershell/setup-tasks.ps1 -Json }`.
- **Invocation context loaded:** JSON from `{SCRIPT}` providing
  `FEATURE_DIR`, `TASKS_TEMPLATE` (path to `tasks-template.md`),
  and `AVAILABLE_DOCS` (e.g. `research.md`, `contracts/`).
  Required reads: `plan.md`, `spec.md` (for user-story priorities
  P1/P2/P3). Optional reads: `data-model.md`, `contracts/`,
  `research.md`, `quickstart.md`.
- **Procedure:** Extract tech stack and user-story priorities; map
  entities and contracts to user stories; emit a tasks.md
  organized as **Phase 1: Setup → Phase 2: Foundational → Phase
  3+: one phase per user story (priority order) → Final Phase:
  Polish**; each task uses the strict checklist format `- [ ] [ID]
  [P?] [Story] Description` with repo-relative exact paths and a
  `[P]` marker for parallel-safe items; emit a Dependencies section
  showing user-story completion order plus parallel-execution
  examples per story; finish by reporting total task count,
  per-story count, parallel opportunities, MVP scope (typically
  User Story 1), and format-validation confirmation.
- **Output artifact:** `specs/<feature>/tasks.md`.
- **Dependencies:** Requires `plan.md` and `spec.md` in the feature
  dir. The `setup-tasks.sh` script enforces the plan.md
  prerequisite — it checks for `$IMPL_PLAN`, prints a "plan.md not
  found" error directing the user to run `/speckit.plan` first, and
  exits non-zero
  ([`scripts/bash/setup-tasks.sh`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/scripts/bash/setup-tasks.sh)).

## Notable conventions

- **Filing convention — `specs/<feature>/` per-feature
  directory.** Every artifact for a single feature lives under one
  `specs/<NNN-or-timestamp>-<slug>/` directory: `spec.md`,
  `plan.md`, `research.md`, `data-model.md`, `quickstart.md`,
  `contracts/`, `tasks.md`, and `checklists/`. The directory is
  allocated by `/speckit.specify` with a sequential `NNN` prefix
  (default) or a `YYYYMMDD-HHMMSS` prefix when
  `.specify/init-options.json` has
  `"branch_numbering": "timestamp"`. The resolved path is
  persisted to `.specify/feature.json` so downstream commands
  locate the directory without relying on git branch naming.
  Branch name and directory name are explicitly decoupled — see
  the comment in
  [`templates/commands/specify.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/specify.md):
  *"The spec directory name and the git branch name are
  independent."*

- **Workflow ordering — `constitution → specify → (clarify) →
  plan → tasks → (analyze) → implement`.** Encoded both
  prose-side in
  [README's "Get Started"](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/README.md)
  and machine-readable in each command's `handoffs:` frontmatter.
  The handoff graph (extracted from frontmatter):
  - `specify` → `plan` (label "Build Technical Plan") and →
    `clarify` (label "Clarify Spec Requirements", `send: true`).
  - `clarify` → `plan`.
  - `constitution` → `specify`.
  - `plan` → `tasks` (`send: true`) and → `checklist`.
  - `tasks` → `analyze` (`send: true`) and → `implement`
    (`send: true`).
  - `analyze`, `checklist`, `implement`, `taskstoissues` are
    terminal (no `handoffs:` declared).

- **`/speckit.analyze` is strictly read-only.** Body quote:
  *"STRICTLY READ-ONLY: Do not modify any files. Output a
  structured analysis report. Offer an optional remediation plan
  (user must explicitly approve before any follow-up editing
  commands would be invoked manually)."* The Constitution is
  declared "non-negotiable within this analysis scope" — any
  conflict is automatically CRITICAL.

- **`/speckit.implement` is gated by checklist completion.** It
  scans `FEATURE_DIR/checklists/*.md`, tallies `- [ ]` vs `-
  [X]/[x]` items, prints a status table, and halts with a yes/no
  prompt if any checklist is incomplete.

- **Extension hooks via `.specify/extensions.yml`.** Every command
  body opens with a "Pre-Execution Checks" section that reads
  `hooks.before_<command>` and closes with `hooks.after_<command>`.
  Each hook entry can be `optional: true/false` and may carry a
  `condition` (the command spec defers `condition` evaluation to a
  HookExecutor — the command itself never interprets the
  expression). Optional hooks render as advisory blocks; mandatory
  hooks render as `EXECUTE_COMMAND: ...` directives the agent must
  run before continuing. The `before_specify` hook is the
  documented integration point for git-branch creation —
  *"Branch creation is handled by the `before_specify` hook (git
  extension). Spec directory and file creation are always handled
  by this core command."*

- **Template stack with priority resolution.**
  [README "Making Spec Kit Your Own"](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/README.md)
  documents a four-level template lookup (highest priority first):
  `.specify/templates/overrides/` → `.specify/presets/templates/`
  → `.specify/extensions/templates/` → `.specify/templates/`
  (core). Templates are resolved at runtime; commands themselves
  are written into the harness directory at install time, with
  stacking by priority and automatic restoration on removal.

- **`{SCRIPT}` token and dual `sh`/`ps` script declarations.**
  Commands that need filesystem prep declare both shell variants
  in frontmatter (`scripts: { sh: ..., ps: ... }`) so Linux/macOS
  and Windows harnesses use the matching script. The helper
  scripts emit JSON the command parses. Helpers in this repo:
  - [`scripts/bash/create-new-feature.sh`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/scripts/bash/create-new-feature.sh)
  - [`scripts/bash/setup-plan.sh`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/scripts/bash/setup-plan.sh)
  - [`scripts/bash/setup-tasks.sh`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/scripts/bash/setup-tasks.sh)
  - [`scripts/bash/check-prerequisites.sh`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/scripts/bash/check-prerequisites.sh)
    (`--json`, `--require-tasks`, `--include-tasks`,
    `--paths-only` flags)
  - [`scripts/bash/common.sh`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/scripts/bash/common.sh)
    (shared `get_feature_paths`,
    `feature_json_matches_feature_dir`, `check_feature_branch`)
  - PowerShell mirrors under
    [`scripts/powershell/`](https://github.com/github/spec-kit/tree/a08af08415432db2ae15b70e82400eaad9dbfd2f/scripts/powershell).

- **Constitution propagation.**
  [`templates/commands/constitution.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/constitution.md)
  requires bumping a semver-style `CONSTITUTION_VERSION`
  (MAJOR/MINOR/PATCH), updating `LAST_AMENDED_DATE`, **and**
  running a consistency-propagation checklist that walks the
  installed project paths under `.specify/templates/plan-template.md`,
  `.specify/templates/spec-template.md`,
  `.specify/templates/tasks-template.md`, every file under
  `.specify/templates/commands/*.md`, and runtime guidance docs. It
  then
  prepends a "Sync Impact Report" HTML comment to the
  constitution listing modified principles, added/removed
  sections, templates updated (✅ / ⚠ pending), and deferred
  TODOs.

- **Harness installation as agent skills.** Spec Kit ships a
  Python CLI (`specify`, packaged from
  [`src/specify_cli`](https://github.com/github/spec-kit/tree/a08af08415432db2ae15b70e82400eaad9dbfd2f/src/specify_cli))
  with one integration subpackage per harness
  ([`src/specify_cli/integrations/`](https://github.com/github/spec-kit/tree/a08af08415432db2ae15b70e82400eaad9dbfd2f/src/specify_cli/integrations)).
  The
  [`SkillsIntegration` base class in `base.py`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/src/specify_cli/integrations/base.py#L1332)
  installs commands at
  `<folder>/<commands_subdir>/speckit-<name>/SKILL.md`, following
  *"the agentskills.io specification"*. The
  [Claude integration](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/src/specify_cli/integrations/claude/__init__.py)
  is one such `SkillsIntegration`: `key = "claude"`, `config =
  {"folder": ".claude/", "commands_subdir": "skills", ...}`,
  `registrar_config = {"dir": ".claude/skills", "format":
  "markdown", "args": "$ARGUMENTS", "extension": "/SKILL.md"}`,
  `context_file = "CLAUDE.md"`. The integration also injects
  per-command `argument-hint` frontmatter (e.g. `"Describe the
  feature you want to specify"` for `specify`) and a
  `_HOOK_COMMAND_NOTE` that tells Claude to map dotted command
  names like `speckit.git.commit` to hyphenated slash invocations
  like `/speckit-git-commit`. AGENTS.md lists alternate base
  classes: `MarkdownIntegration`, `TomlIntegration`,
  `YamlIntegration`, `SkillsIntegration`, plus direct
  `IntegrationBase` subclassing for fully custom outputs. README
  notes 30+ supported agents and points at `specify integration
  list` for the live list.

- **`$ARGUMENTS` substitution.** Every command body has a `## User
  Input` fenced block containing the literal `$ARGUMENTS`. The
  integration layer substitutes the user-typed text into this slot
  at invocation; see
  [`ClaudeIntegration` `registrar_config`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/src/specify_cli/integrations/claude/__init__.py)
  — `"args": "$ARGUMENTS"`.

- **Token-substitution for cross-command references.** Command
  bodies use placeholder tokens (e.g.
  `__SPECKIT_COMMAND_SPECIFY__`, `__SPECKIT_COMMAND_PLAN__`,
  `__SPECKIT_COMMAND_CLARIFY__`) instead of hardcoding the slash
  form, so the integration layer can rewrite to the
  harness-appropriate syntax (e.g. `/speckit.specify`,
  `$speckit-specify`, `/speckit-specify`) at install time.

- **Tools gating.** `/speckit.taskstoissues` is the only command in
  the catalog that declares `tools:` in frontmatter (`tools:
  ['github/github-mcp-server/issue_write']`). Its body adds two
  read-aloud CAUTION fences requiring that the git remote be a
  GitHub URL and that no issues be created in a repository other
  than the one matching `git config --get remote.origin.url`.

- **Independent-MVP user-story discipline.**
  `templates/spec-template.md` requires user stories to be
  PRIORITIZED (P1/P2/P3) and INDEPENDENTLY TESTABLE — *"if you
  implement just ONE of them, you should still have a viable
  MVP"*. `templates/tasks-template.md` carries this through: tasks
  are grouped by user story (US1/US2/US3), and the suggested MVP
  scope is "typically just User Story 1".

- **Checklist philosophy — "unit tests for English."**
  [`templates/commands/checklist.md`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/templates/commands/checklist.md)
  opens with: *"Checklists are UNIT TESTS FOR REQUIREMENTS
  WRITING — they validate the quality, clarity, and completeness
  of requirements in a given domain."* Explicitly **not** for
  verifying that implementations work. Checklist files live at
  `specs/<feature>/checklists/<name>.md` (e.g. `ux.md`, `test.md`,
  `security.md`, plus the `requirements.md` auto-generated by
  `/speckit.specify`).

- **Pyproject / Python entry point.**
  [`pyproject.toml`](https://github.com/github/spec-kit/blob/a08af08415432db2ae15b70e82400eaad9dbfd2f/pyproject.toml)
  declares the `specify-cli` package; users install via
  `uv tool install specify-cli --from
  git+https://github.com/github/spec-kit.git@vX.Y.Z` and run
  `specify init my-project --integration claude` (or `copilot`,
  `gemini`, etc.).
