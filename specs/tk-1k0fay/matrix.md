---
name: Skill-Ecosystem Cross-Source Matrix
description: Cross-cutting comparison of seven AI-agent skill (and skill-adjacent) ecosystems by functional area, for the gc-toolkit ecosystem-skills audit (tk-1k0fay). Pure cataloging — see per-source files for full details.
---

# Skill-Ecosystem Cross-Source Matrix

This matrix indexes which functional areas each surveyed source
covers, with skill/command/molecule names as cell values. Functional
areas are grouped by category. Cells show the source's named
artifact(s) where coverage exists; `—` means the source ships no
named artifact in that area. **This is a coverage map, not an
evaluation.** Borrowing decisions are out of scope for this audit.

Per-source detail lives in the sibling files; click the column
header to jump.

| Column | Source | Per-source survey |
|---|---|---|
| SP | obra/superpowers — multi-harness "skills plugin" | [`superpowers.md`](superpowers.md) |
| BMAD | bmad-code-org/BMAD-METHOD — core + bmm modules | [`bmad-method.md`](bmad-method.md) |
| AN | anthropics/skills — Anthropic public skills repo | [`anthropic-skills.md`](anthropic-skills.md) |
| SK | github/spec-kit — Spec-driven development command set | [`spec-kit.md`](spec-kit.md) |
| KR | Kiro IDE — Steering documents (AWS/Kiro, proprietary) | [`kiro-steering.md`](kiro-steering.md) |
| GT | Gas Town — rigs/gascity examples (molecules + agents) | [`gas-town.md`](gas-town.md) |
| CC | Claude Code v2.1.150 — built-in bundled skills | [`claude-code-builtins.md`](claude-code-builtins.md) |

## Matrix

### Workflow / development lifecycle

| Functional area | SP (Superpowers) | BMAD | AN (anthropics/skills) | SK (Spec Kit) | KR (Kiro) | GT (Gas Town) | CC (Claude Code) |
|---|---|---|---|---|---|---|---|
| Brainstorming / idea exploration | `brainstorming` | `bmad-brainstorming`, `bmad-prfaq`, `bmad-advanced-elicitation` | — | — | — | `mol-idea-to-plan` (init/draft-prd phase) | — |
| Spec / PRD / product-brief authoring | (`brainstorming` writes a spec doc) | `bmad-prd`, `bmad-product-brief`, `bmad-prfaq`; deprecated shims (`bmad-create-prd`, `bmad-edit-prd`, `bmad-validate-prd`) | `doc-coauthoring` | `/speckit.specify`, `/speckit.clarify` | spec workflow (`requirements.md`/`bugfix.md` — adjacent, not steering proper) | `mol-idea-to-plan` (PRD draft + review legs) | — |
| Research (web / domain / market / technical) | — | `bmad-domain-research`, `bmad-market-research`, `bmad-technical-research` | `mcp-builder` (Phase 1 deep research within domain) | — | — | `mol-idea-to-plan` (research subagents during discovery) | — |
| Architecture / design doc generation | — | `bmad-create-architecture`, `bmad-generate-project-context`, `bmad-agent-architect` (Winston persona) | — | `/speckit.plan` (Phase 1: `data-model.md`, `contracts/`, `quickstart.md`) | — | `mol-idea-to-plan` (design-exploration step) | — |
| UX design planning | — | `bmad-ux`, `bmad-agent-ux-designer` (Sally persona) | — | — | — | — | — |
| Task list generation | — | `bmad-create-epics-and-stories`, `bmad-create-story`, `bmad-sprint-planning` | — | `/speckit.tasks` | — | `mol-idea-to-plan` (create-beads step → owned convoy + task beads) | — |
| Plan / task execution | `executing-plans`, `subagent-driven-development` | `bmad-dev-story`, `bmad-quick-dev`, `bmad-agent-dev` (Amelia persona) | — | `/speckit.implement` | — | `mol-polecat-work` | — |
| Mid-sprint course correction | — | `bmad-correct-course` | — | — | — | (rejection-resume on work bead via `metadata.rejection_reason`) | — |
| Retrospective | — | `bmad-retrospective` | — | — | — | — | — |
| Sprint planning / status | — | `bmad-sprint-planning`, `bmad-sprint-status` | — | — | — | — | — |
| Project documentation (brownfield) | — | `bmad-document-project` | — | — | (one of three foundational `structure.md`) | — | — |

### Code quality

| Functional area | SP | BMAD | AN | SK | KR | GT | CC |
|---|---|---|---|---|---|---|---|
| Code review (correctness on diff) | `requesting-code-review`, `receiving-code-review` (+ `code-reviewer.md` subagent prompt) | `bmad-code-review` (parallel Blind Hunter / Edge Case Hunter / Acceptance Auditor) | — | — | — | (none; review-leg generic helper `mol-review-leg` could host one) | `/code-review` |
| Adversarial / edge-case review | (covered inside `subagent-driven-development` two-stage review) | `bmad-review-adversarial-general`, `bmad-review-edge-case-hunter` | — | — | — | — | — |
| Security review | — | — | — | — | — | — | `/security-review` |
| Debugging (root-cause) | `systematic-debugging` (+ `root-cause-tracing.md` reference) | `bmad-investigate` | — | — | — | — | `/debug` |
| TDD / test-first discipline | `test-driven-development` (+ `writing-skills` reuses RED-GREEN-REFACTOR for skill authoring) | — | — | — | — | — | — |
| Verification before claiming done | `verification-before-completion` | — | — | — | — | (`affected_tests_command` self-review gate in `mol-polecat-work`) | `/verify` |
| App launch / run / observe | (`verification-before-completion` infra) | — | `webapp-testing` (Playwright-driven) | — | — | — | `/run`, `/run-skill-generator` |
| QA / E2E test generation | — | `bmad-qa-generate-e2e-tests` | `webapp-testing` (Playwright) | — | — | — | — |
| Human-in-the-loop checkpoint review | — | `bmad-checkpoint-preview` | — | — | — | — | — |
| Cross-artifact consistency / coverage | — | `bmad-check-implementation-readiness` | — | `/speckit.analyze` (read-only) | — | — | — |
| Domain quality checklist ("unit tests for English") | — | (validator catalog SKILL-/STEP-/PATH- rules) | — | `/speckit.checklist` | — | — | — |

### Branch / merge / dispatch infrastructure

| Functional area | SP | BMAD | AN | SK | KR | GT | CC |
|---|---|---|---|---|---|---|---|
| Worktree / branch isolation | `using-git-worktrees` | — | — | — | — | `mol-polecat-work` (workspace-setup step) | `/batch` (per-unit isolated worktree) |
| Branch finish / PR / merge handoff | `finishing-a-development-branch` | — | — | — | — | `mol-polecat-work` (submit-and-exit step) + `mol-refinery-patrol` | `/batch` (per-unit PR creation) |
| Merge queue / rebase / reject loop | — | — | — | — | — | `mol-refinery-patrol` (rebase → test → merge → reject-with-reason) | — |
| Subagent / parallel dispatch | `dispatching-parallel-agents`, `subagent-driven-development` | (parallel reviewers in `bmad-code-review`; subagent extraction in `bmad-prd`) | (skills' subagent fork-context via Anthropic spec extensions) | (`handoffs: send: true` chained dispatch) | — | `mol-idea-to-plan` (6+ parallel review legs per step) + `mol-review-leg` | `/batch` (5-30 unit subagents) |
| Multi-agent collaboration / "party mode" | — | `bmad-party-mode` (real subagents per persona) | — | — | — | — | — |
| Patrol loop / periodic monitoring | — | — | — | — | — | `mol-deacon-patrol`, `mol-witness-patrol`, `mol-refinery-patrol` | `/loop` |
| Periodic digest / activity summary | — | — | — | — | — | `mol-digest-generate` | — |
| Orphan/stuck-work recovery | — | — | — | — | — | `mol-witness-patrol` (recover-orphaned-beads step) | — |
| Cron / scheduled remote agent | — | — | — | — | — | (deacon `periodic-formulas` dispatches `mol-digest-generate` on cooldown) | `/schedule` |

### Skill ecosystem meta

| Functional area | SP | BMAD | AN | SK | KR | GT | CC |
|---|---|---|---|---|---|---|---|
| SKILL.md schema / spec authority | (defers to agentskills.io; documents schema in `writing-skills`) | (validator rules SKILL-01..07; defers schema to agentskills.io) | **CANONICAL** — spec lives at agentskills.io/specification; this repo is Anthropic's reference implementation | (not a SKILL.md ecosystem natively; installs commands AS `speckit-<name>/SKILL.md` via `SkillsIntegration`) | (not SKILL.md; uses its own `.kiro/steering/*.md` inclusion-mode frontmatter) | (not SKILL.md; uses TOML `mol-*.toml` schema for molecules) | (consumer of the same spec + Anthropic extensions: `disable-model-invocation`, `user-invocable`, `allowed-tools`, `context: fork`, `agent:`, etc.) |
| Skill authoring (meta-skill) | `writing-skills` (TDD-for-skills with pressure-test transcripts) | `bmad-customize`, `bmad-distillator` (compression for embedding) | `skill-creator` (eval/benchmark/improve-description loop) | — | — | — | — |
| Skill catalog / help router | (README "What's Inside" editorial groups) | `bmad-help` reads assembled `bmad-help.csv` per-module routing catalog | (plugin grouping in `.claude-plugin/marketplace.json`) | (`handoffs:` frontmatter on each command) | (foundational `product.md` + `tech.md` + `structure.md` always-loaded) | (`gc bd ready --metadata-field gc.routed_to=...`) | (`/` menu + `skillOverrides` in settings.json) |
| Customization / override layer | (`AGENTS.md` declares forks not accepted upstream — opposite stance) | `customize.toml` three-layer merge (base → team → user) via `_bmad/scripts/resolve_customization.py` | (no override system in spec) | template stack: `overrides/` → `presets/templates/` → `extensions/templates/` → core | workspace `.kiro/steering/` > global `~/.kiro/steering/` | (rig `formula_vars` overrides molecule `default`) | `skillOverrides` (settings.json), user-defined skills override bundled |
| Steering / always-loaded context | (instruction priority encoded in `using-superpowers` bootstrap) | (project-context.md from `bmad-generate-project-context`) | (no equivalent; description always-loaded but body on-demand) | `.specify/memory/constitution.md` (loaded by `/speckit.plan` Constitution Check gate) | **CENTRAL CONVENTION** — `inclusion: always` / `fileMatch` / `manual` / `auto` modes; AGENTS.md always-included | (agent prompt.template.md rendered into system prompt per role) | (CLAUDE.md in project root; auto-loaded) |
| Project constitution / governance | — | (project-context.md serves similar role) | — | `/speckit.constitution` (with semver, Sync Impact Report, propagation checklist) | (foundational `product.md` covers strategic governance) | — | — |
| Hooks / session-start injection | `hooks/hooks.json` (`SessionStart` on `startup|clear|compact`) + `hooks/session-start` (injects `using-superpowers/SKILL.md`) | — | (allowed-tools experimental field; no hook system in spec) | `.specify/extensions.yml` (`hooks.before_<cmd>` / `hooks.after_<cmd>`) | — | (boot agent owns city-scope startup; mayor city init) | settings.json `hooks` (SessionStart, PreToolUse, PostToolUse, etc.) |
| Recurring loop (poll/babysit) | — | — | — | — | — | (patrol-loop pattern: pour-next + burn-current per iteration) | `/loop` (interval or self-paced) |

### Artifact authoring (domain-specific skills)

| Functional area | SP | BMAD | AN | SK | KR | GT | CC |
|---|---|---|---|---|---|---|---|
| Documentation co-authoring | — | `bmad-agent-tech-writer` (write/mermaid/validate/explain/update-standards multi-action) | `doc-coauthoring` | — | — | — | — |
| Document operations — Word | — | — | `docx` | — | — | — | — |
| Document operations — PDF | — | — | `pdf` (with `forms.md`, `reference.md`, 8 scripts) | — | — | — | — |
| Document operations — PowerPoint | — | — | `pptx` | — | — | — | — |
| Document operations — Excel/CSV | — | — | `xlsx` | — | — | — | — |
| Frontend / UI design | — | — | `frontend-design`, `web-artifacts-builder` | — | — | — | — |
| Visual art / canvas / theming | — | — | `algorithmic-art`, `canvas-design`, `theme-factory`, `brand-guidelines` | — | — | — | — |
| Internal comms / status reports | — | — | `internal-comms` | — | — | — | — |
| Animated GIF (Slack) | — | — | `slack-gif-creator` | — | — | — | — |
| MCP server scaffolding | — | — | `mcp-builder` (Phase 0-4 workflow + Python/TS references) | — | — | — | — |
| Editorial review (prose / structure) | — | `bmad-editorial-review-prose`, `bmad-editorial-review-structure` | (covered in `doc-coauthoring`) | — | — | — | — |
| Doc indexing / sharding | — | `bmad-index-docs`, `bmad-shard-doc` | — | — | — | — | — |
| Distillation / lossless compression | — | `bmad-distillator` | — | — | — | — | — |

### Harness / runtime integration

| Functional area | SP | BMAD | AN | SK | KR | GT | CC |
|---|---|---|---|---|---|---|---|
| CLAUDE.md / project bootstrap | — | — | — | (Spec Kit installs commands and rewrites context-file CLAUDE.md per `ClaudeIntegration.context_file`) | — | — | `/init` |
| Permission allowlist tuning | — | — | (`allowed-tools` frontmatter, experimental) | — | — | — | `/fewer-permission-prompts` |
| API migration (model versions) | — | — | (`claude-api` skill has migration guidance) | — | — | — | `/claude-api migrate` |
| GitHub issue sync from tasks | — | — | — | `/speckit.taskstoissues` (requires `github/github-mcp-server`) | — | — | — |
| Managed Agents onboarding | — | — | (`claude-api` skill) | — | — | — | `/claude-api managed-agents-onboard` |
| Multi-harness portability | (Claude Code, Codex, Cursor, Gemini, OpenCode, Copilot, Factory Droid via per-harness manifests) | — | (Claude Code via `/plugin marketplace`; Claude.ai upload; Claude API direct) | (30+ harness integrations via `IntegrationBase` subclasses in `src/specify_cli/integrations/`) | (Kiro IDE only; reads AGENTS.md as cross-vendor interop) | (gascity-pack; consumable by any gc-toolkit-compatible rig) | (Claude Code only) |

### Coordination meta

| Functional area | SP | BMAD | AN | SK | KR | GT | CC |
|---|---|---|---|---|---|---|---|
| Persona / named agents | — | 6 named personas (Mary, Paige, John, Sally, Winston, Amelia) with literary voice descriptors | — | — | — | 6 runtime agent roles (mayor, deacon, boot, witness, refinery, polecat — *agents*, not *skill personas*) | — |
| Advanced elicitation / Socratic / red-team | — | `bmad-advanced-elicitation` | — | — | — | (reviewer-leg subagents in `mol-idea-to-plan`) | — |
| Receiving code-review feedback | `receiving-code-review` (anti-"You're absolutely right!" discipline) | — | — | — | — | — | — |
| Hard-gate / iron-law discipline patterns | (Iron Law in 4 skills + "Red Flags" rationalization tables) | (HALT-before-menu STEP-04; "Extract, don't ingest"; Conventional Commits gate) | (description-is-trigger-only rule from `skill-creator`) | (`/speckit.analyze` strictly read-only; `/speckit.implement` checklist gate) | (frontmatter strictness: "no blank lines before inclusion") | (drain-ack contract; "Idle Polecat Heresy" in polecat prompt) | (`disable-model-invocation` frontmatter) |
| Decision-log convention | — | (`.decision-log.md` in `bmad-prd`) | — | (Sync Impact Report in constitution; NEEDS CLARIFICATION markers in spec) | — | (work bead `metadata.rejection_reason` + `notes`; bead description = decision record) | — |
| Filing convention — per-feature/per-task directory | (`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`, `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`) | (`{output_folder}/<workflow>/...` from `customize.toml` paths) | — | **CANONICAL** — `specs/<NNN>-<slug>/` per-feature directory (the convention gc-toolkit's own `specs/<bead-id>/` mirrors) | `.kiro/specs/<feature>/{requirements,design,tasks}.md` | (worktrees scoped to bead `worktrees/<bead-id>/`; specs under `specs/<bead-id>/`) | — |

## Gaps

Functional areas no surveyed source covers (or only covers in
passing). These are open territory if gc-toolkit needed something
in the space — useful as a coverage-gap survey, not as a "must
fill" list:

- **Cost/budget tracking for agent runs.** No source ships a skill
  for tracking model spend per task, per workflow, or per
  feature. Some sources mention model selection (Superpowers'
  `subagent-driven-development` "Model Selection" section,
  `bmad-party-mode --model haiku`) but none track or report cost.
- **Eval-result regression detection across runs.** Anthropic's
  `skill-creator` benchmarks skills, but no source ships a skill
  that compares this-week's eval results to last-week's for the
  same skill or workflow, or that flags regressions in skill
  triggering accuracy over time.
- **Documentation freshness audit.** No source ships a skill that
  walks a `docs/` tree and flags pages whose content has drifted
  from the code they describe. (BMAD's `bmad-shard-doc` and
  `bmad-index-docs` are mechanical, not staleness-aware.)
- **License / dependency compliance scanning.** No source ships a
  skill for SBOM generation, license-text scanning, or
  vulnerable-dependency detection (separate from
  `/security-review` which targets source code).
- **Database migration authoring / review.** No source ships
  schema-migration-specific skills, even though several spec
  workflows produce `data-model.md` (Spec Kit) or schemas (BMAD).
- **Performance / load testing.** `webapp-testing` covers
  functional browser testing via Playwright; no source ships
  performance-budget, load-test, or profiling skills.
- **Localization / translation.** No skills for translating
  artifacts. BMAD has `{communication_language}` /
  `{document_output_language}` config keys but no skill that
  performs translation as a workflow.
- **Accessibility audit.** No source ships an a11y-specific skill,
  though `webapp-testing` could host one and `frontend-design`
  mentions accessibility in passing.
- **Visual diff / screenshot review.** `webapp-testing` captures
  screenshots; no source produces a skill that *compares* before/
  after screenshots and flags visual regressions.
- **Knowledge-graph / capability ledger.** Gas Town's polecat
  prompt mentions a "Capability Ledger" (the beads ledger), but
  no source ships a skill that *queries* it for trends or for
  agent-capability profiling.
- **Stakeholder mail / outbound external comms drafting.** BMAD's
  `internal-comms` covers internal; no source ships a customer-
  facing / external-stakeholder comms skill.
- **Data analysis (notebook / Jupyter).** Spreadsheet ops via
  `xlsx`; no notebook-grade exploratory analysis skill.
- **Compliance / audit-trail generation for regulated workflows.**
  No SOC-2-style audit-evidence-collection skill, though decision
  logs (BMAD, Spec Kit) and the bead ledger (Gas Town) approach
  the territory.

## Overlaps — areas where 3+ sources converge

These are the areas where multiple independent ecosystems have
independently arrived at a skill/command for the same purpose.
Convergence is evidence the pattern has been re-derived; it does
not by itself justify adoption.

### 1. Plan / task execution (5 sources)

- SP: `executing-plans`, `subagent-driven-development`
- BMAD: `bmad-dev-story`, `bmad-quick-dev`, `bmad-agent-dev`
- SK: `/speckit.implement`
- GT: `mol-polecat-work`
- (CC: `/batch` indirectly, parallel-unit decomposition + execute)

All five ship a "take an approved plan and execute it" workflow.
The execution strategies vary widely (Superpowers prefers fresh
subagent per task; Gas Town runs a polecat per work bead; Spec Kit
walks tasks.md sequentially; BMAD's `bmad-quick-dev` collapses
the whole pipeline into one skill; `/batch` decomposes into 5-30
independent units).

### 2. Code review (correctness) (3 sources)

- SP: `requesting-code-review`, `receiving-code-review`
- BMAD: `bmad-code-review` (with three parallel review layers)
- CC: `/code-review`

Three independent ecosystems ship a code-review skill on the
current diff. BMAD's parallel-layer approach (Blind Hunter / Edge
Case Hunter / Acceptance Auditor) and Superpowers' `code-reviewer`
subagent-prompt convention sit on either side of `/code-review`'s
effort-level dial.

### 3. Debugging / root-cause investigation (3 sources)

- SP: `systematic-debugging` (with `root-cause-tracing.md` reference)
- BMAD: `bmad-investigate`
- CC: `/debug`

All three ship discipline-shaped skills for diagnosing failures
*before* fixing. Superpowers and BMAD both enforce "investigate
before fix" rules; `/debug` is more harness-integrated (reads
session logs).

### 4. Verification / app-launch (3-4 sources)

- SP: `verification-before-completion`
- AN: `webapp-testing` (browser-side)
- GT: `mol-polecat-work` self-review step (with affected-tests gate)
- CC: `/verify`, `/run`, `/run-skill-generator`

Convergence: don't claim "done" without evidence. Superpowers and
Gas Town encode the discipline; `/verify` and `webapp-testing`
provide the means.

### 5. Subagent / parallel dispatch (5 sources)

- SP: `dispatching-parallel-agents`, `subagent-driven-development`
- BMAD: parallel reviewers within `bmad-code-review`, `bmad-party-mode`
- AN: skills' `context: fork` extension
- SK: `handoffs: send: true` chained dispatch
- GT: `mol-idea-to-plan` (6+ parallel review-leg dispatches)
- CC: `/batch` (5-30 isolated worktree subagents)

Six sources ship some flavor of "fan work out to multiple
independent agents." The patterns vary (Superpowers
fresh-subagent-per-task; Gas Town named review legs; `/batch`
worktree-isolated PRs; Spec Kit chained slash-command handoffs;
BMAD's `bmad-party-mode` real subagents per persona).

### 6. Skill authoring / meta-skill (3 sources)

- SP: `writing-skills` (TDD-for-skills, pressure-test transcripts)
- BMAD: `bmad-customize` + `tools/skill-validator.md` rule catalog
- AN: `skill-creator` (eval/benchmark/improve-description loop)

Three independent skill ecosystems each ship a meta-skill for
authoring more skills. All three impose discipline on the
description-field's wording (Superpowers' "description = WHEN
only", BMAD's "Use when" trigger phrase requirement, Anthropic's
"include both what AND when").

### 7. Steering / always-loaded project context (4 sources)

- SK: `/speckit.constitution` → `.specify/memory/constitution.md`
  (loaded by `/speckit.plan` gate)
- KR: `inclusion: always` mode + foundational `product.md` /
  `tech.md` / `structure.md`
- GT: agent prompt templates rendered into system prompt per role
- CC: `CLAUDE.md` auto-loaded per project
- (BMAD adjacent: `bmad-generate-project-context` produces
  `project-context.md` as similar artifact)

Four (or five) sources ship some flavor of "load this context on
every interaction." Kiro's inclusion-mode is the most explicit
treatment; Spec Kit's constitution and Claude Code's CLAUDE.md are
narrower; Gas Town does it per-agent-role via prompt templates.

### 8. Filing convention — per-feature directory (4 sources)

- SP: `docs/superpowers/{specs,plans}/YYYY-MM-DD-<topic>.md`
- SK: `specs/<NNN-or-timestamp>-<slug>/{spec,plan,tasks}.md`
  (THE CANONICAL `specs/<feature>/` PATTERN)
- KR: `.kiro/specs/<feature>/{requirements,design,tasks}.md`
- GT: `worktrees/<bead-id>/` (work isolation) and `specs/<bead-id>/`
  (artifact filing; in gc-toolkit per `docs/file-structure.md`)

Spec Kit and Kiro converge exactly on `specs/<feature>/`. gc-toolkit
follows the same shape with bead-keyed names
(`specs/<bead-id>/`). Superpowers uses timestamp prefixes in
`docs/superpowers/`. The convergence on per-feature directories
(rather than per-doc-type or chronological-only) is striking.

### 9. Hooks / lifecycle integration (3 sources)

- SP: `hooks/hooks.json` (SessionStart on startup|clear|compact)
- SK: `.specify/extensions.yml` (before/after per command)
- CC: settings.json `hooks` (SessionStart, PreToolUse, PostToolUse,
  etc.)

Three independent harness-integration patterns. Superpowers and
Claude Code share the `SessionStart` hook name; Spec Kit's
extensions.yml runs hooks per command rather than per session
event.

### 10. Customization / override layer (4 sources)

- BMAD: `customize.toml` three-layer merge (base → team → user)
- SK: template stack (`overrides/` → `presets/` → `extensions/` →
  core)
- KR: workspace `.kiro/steering/` > global `~/.kiro/steering/`
- GT: rig `formula_vars` overrides molecule `default`
- (CC: `skillOverrides` in settings.json — narrower; visibility,
  not content override)

Four sources ship layered-override systems for skill / command /
workflow customization. The merge semantics differ (BMAD's
"arrays-of-tables keyed by code or id" is the most-structured;
Kiro's straight precedence is the simplest).

### 11. Persona / role-shaped agents (2-3 sources)

- BMAD: 6 named personas (Mary, Paige, John, Sally, Winston, Amelia)
  with literary voice descriptors
- GT: 6 runtime agent roles (mayor, deacon, boot, witness, refinery,
  polecat — agents, not skill personas, but role-shaped)
- (SP adjacent: subagent prompts are role-shaped — implementer,
  spec-reviewer, code-quality-reviewer — but anonymous)

Two-and-a-half sources organize agent labor by named role. BMAD's
personas layer onto workflow skills (Mary stays "Mary" when she
runs the brainstorming skill); Gas Town's roles are runtime
agents bound to molecules. The two are structurally distinct but
functionally overlapping: both partition agentic work by named
role.

### 12. Recurring loops / patrol (3 sources)

- GT: `mol-deacon-patrol`, `mol-witness-patrol`, `mol-refinery-patrol`
- CC: `/loop`, `/schedule`
- (BMAD adjacent: `bmad-sprint-status` runs as a manual check, not
  on a loop)

Two ecosystems explicitly model recurring / cron-like work. Gas
Town's patrol pattern (pour-next-wisp + burn-current) is
distinctive: a self-pouring loop that survives crashes by always
leaving the next iteration's wisp assigned before burning the
current. Claude Code's `/loop` and `/schedule` cover the same
ground via the harness's session scheduler instead.

## Reading order

This matrix is a coverage map across sources. For per-source
detail, read the file linked in the column-header table at the top.
For Spec Kit's filing convention (which gc-toolkit's own
`specs/<bead-id>/` mirrors), see
[`spec-kit.md`](spec-kit.md) § "Filing convention". For Kiro's
inclusion-mode system (the most-distinctive single concept in
the survey), see [`kiro-steering.md`](kiro-steering.md) §
"Inclusion modes (THE CENTRAL CONVENTION)". For Gas Town's
adoptable-as-is column (the survey's explicit Gas Town ask), see
[`gas-town.md`](gas-town.md) § "Molecule catalog".
