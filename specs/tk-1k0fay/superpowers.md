---
name: Superpowers Skill Catalog
description: Per-source survey of the obra/superpowers skill ecosystem for the gc-toolkit ecosystem-skills audit (tk-1k0fay).
---

# Superpowers Skill Catalog

Survey of [`obra/superpowers`](https://github.com/obra/superpowers)
at commit
[`f2cbfbe`](https://github.com/obra/superpowers/tree/f2cbfbefebbfef77321e4c9abc9e949826bea9d7)
(latest on `main` as of 2026-05-24). The project ships as a
multi-harness "skills plugin" — same skills loaded into Claude
Code, Codex, Cursor, Gemini CLI, OpenCode, GitHub Copilot CLI, and
Factory Droid via per-harness manifests, with a Claude Code plugin
marketplace as the canonical distribution.

## Provenance

| Doc-type or artifact | Producer (skill / concept / workflow step that emits it upstream) | Source location (URL or repo path + commit SHA) | Surveyed at |
| --- | --- | --- | --- |
| Repo `README.md` | Top-level project description, install matrix, "Basic Workflow" ordering, skill library inventory | [`README.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/README.md) | 2026-05-24 |
| `LICENSE` | MIT license file, copyright Jesse Vincent 2025 | [`LICENSE @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/LICENSE) | 2026-05-24 |
| Plugin manifest (`plugin.json`) | Claude Code plugin descriptor (name, version 5.1.0, MIT, keywords) | [`.claude-plugin/plugin.json @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/.claude-plugin/plugin.json) | 2026-05-24 |
| Marketplace manifest (`marketplace.json`) | Development marketplace pointing at the local plugin | [`.claude-plugin/marketplace.json @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/.claude-plugin/marketplace.json) | 2026-05-24 |
| `AGENTS.md` / `CLAUDE.md` / `GEMINI.md` | Contributor guidelines for agents (shared 94%-rejection notice, PR template rules) | [`AGENTS.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/AGENTS.md), [`CLAUDE.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/CLAUDE.md), [`GEMINI.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/GEMINI.md) | 2026-05-24 |
| `hooks/hooks.json` | Claude Code `SessionStart` hook registration triggering on `startup|clear|compact` | [`hooks/hooks.json @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/hooks/hooks.json) | 2026-05-24 |
| `hooks/session-start` | Bash hook that injects `skills/using-superpowers/SKILL.md` content into the session and warns about legacy `~/.config/superpowers/skills` directories | [`hooks/session-start @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/hooks/session-start) | 2026-05-24 |
| `SKILL.md` schema definition | Documented inside `skills/writing-skills/SKILL.md` ("SKILL.md Structure" + Claude Search Optimization sections); refers to [agentskills.io/specification](https://agentskills.io/specification) for the full field list | [`skills/writing-skills/SKILL.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/SKILL.md) | 2026-05-24 |
| Skill directory listing | 14 top-level skills under `skills/`, each its own directory containing a `SKILL.md` plus optional supporting files | [`skills/ @ f2cbfbe`](https://github.com/obra/superpowers/tree/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills) | 2026-05-24 |
| Per-skill `SKILL.md` documents | Individual skill content (one per skill listed in the catalog below) | Linked per row in the [Skill catalog](#skill-catalog) | 2026-05-24 |
| Subagent prompt templates | Companion `.md` files dispatched as subagent prompts (e.g. `implementer-prompt.md`, `spec-reviewer-prompt.md`, `code-quality-reviewer-prompt.md`, `code-reviewer.md`, `spec-document-reviewer-prompt.md`, `plan-document-reviewer-prompt.md`) | e.g. [`skills/subagent-driven-development/implementer-prompt.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/subagent-driven-development/implementer-prompt.md) | 2026-05-24 |
| Skill supporting references | Heavy reference material kept in sibling files (e.g. `testing-anti-patterns.md`, `root-cause-tracing.md`, `defense-in-depth.md`, `condition-based-waiting.md`, `anthropic-best-practices.md`, `persuasion-principles.md`, `testing-skills-with-subagents.md`) | e.g. [`skills/systematic-debugging/root-cause-tracing.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/systematic-debugging/root-cause-tracing.md) | 2026-05-24 |
| Tool-mapping references | Per-harness tool name tables read by `using-superpowers` (`references/codex-tools.md`, `copilot-tools.md`, `gemini-tools.md`) | [`skills/using-superpowers/references/ @ f2cbfbe`](https://github.com/obra/superpowers/tree/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/using-superpowers/references) | 2026-05-24 |
| Per-harness adapters | Sibling plugin manifests / install docs for Codex, Cursor, Gemini, OpenCode | `.codex-plugin/`, `.cursor-plugin/`, `.opencode/`, `gemini-extension.json`, `docs/` (e.g. [`docs/README.opencode.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/docs/README.opencode.md)) | 2026-05-24 |

## License

MIT License, copyright "Jesse Vincent" 2025. File location:
[`LICENSE @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/LICENSE).
The plugin manifest also declares `"license": "MIT"` in
[`.claude-plugin/plugin.json`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/.claude-plugin/plugin.json).

## Skill format / schema

The schema is documented in
[`skills/writing-skills/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/SKILL.md)
and points to
[agentskills.io/specification](https://agentskills.io/specification)
as the authoritative spec.

### File layout

Each skill is its own directory under `skills/<skill-name>/`. The
directory contains:

- **`SKILL.md`** (required) — the entry point, with YAML
  frontmatter plus markdown body.
- **Optional supporting files** kept alongside `SKILL.md`:
  - Heavy reference material (100+ lines) split into separate `.md`
    files (e.g. `testing-anti-patterns.md`, `root-cause-tracing.md`).
  - Subagent prompt templates as standalone `.md` files (e.g.
    `implementer-prompt.md`).
  - Executable helpers (`.sh`, `.cjs`, `.js`, `.ts`) — e.g.
    `skills/brainstorming/scripts/start-server.sh`,
    `skills/writing-skills/render-graphs.js`.
  - Reference subdirectories like
    `skills/using-superpowers/references/{codex,copilot,gemini}-tools.md`.
- The skills namespace is **flat** — all 14 skills live directly
  under `skills/`, with no category subdirectories. The README's
  "What's Inside" section gives an editorial grouping (Testing /
  Debugging / Collaboration / Meta) but that grouping is not
  reflected in the directory structure.

### Frontmatter

YAML frontmatter with **two required fields**: `name` and
`description`. Total frontmatter capped at **1024 characters**.
From
[`skills/writing-skills/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/SKILL.md):

- `name`: letters, numbers, and hyphens only (no parentheses or
  special characters); typically gerund or verb-first
  (`writing-plans`, `using-git-worktrees`).
- `description`: third-person, MUST describe only WHEN to invoke,
  never WHAT the skill does. Recommended to start with "Use
  when...". Target under 500 characters. The skill explicitly warns
  that summarizing the workflow in the description causes models to
  follow the description and skip the body.
- Other fields from the upstream spec at
  [agentskills.io/specification](https://agentskills.io/specification)
  are permitted but no other field is used by any in-repo skill in
  this snapshot.

### Body sections

`writing-skills` prescribes the following structure for `SKILL.md`
bodies (variations exist — only `Overview` is universal across all
14 skills):

1. `# Skill Name` heading
2. `## Overview` — one or two sentences defining the core principle
3. `## When to Use` — bullets of symptoms + optional inline Graphviz
   flowchart for non-obvious decisions
4. `## Core Pattern` or `## The Process` — before/after comparison or
   step list
5. `## Quick Reference` — table for scanning
6. `## Implementation` — inline code or link to a sibling file
7. `## Common Mistakes` — failure modes
8. `## Real-World Impact` — optional concrete results

Discipline-enforcing skills (TDD, debugging,
verification-before-completion, writing-skills itself) additionally
include:

- An `## The Iron Law` block in a fenced code box ("NO PRODUCTION
  CODE WITHOUT A FAILING TEST FIRST", "NO FIXES WITHOUT ROOT CAUSE
  INVESTIGATION FIRST", "NO COMPLETION CLAIMS WITHOUT FRESH
  VERIFICATION EVIDENCE", "NO SKILL WITHOUT A FAILING TEST FIRST").
- A `## Red Flags` table — first column "Thought" or "Excuse",
  second column "Reality".
- The mantra **"Violating the letter of the rules is violating the
  spirit of the rules."**

### Hooks (Claude Code integration)

Defined in
[`hooks/hooks.json`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/hooks/hooks.json):

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|clear|compact",
        "hooks": [ { "type": "command",
                     "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start",
                     "async": false } ] }
    ]
  }
}
```

The hook script
([`hooks/session-start`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/hooks/session-start))
reads `skills/using-superpowers/SKILL.md` and injects it as
additional context at session start, fires on `startup`, `clear`,
and `compact`, and emits a migration warning if
`~/.config/superpowers/skills` exists. There is also a
Cursor-specific
[`hooks/hooks-cursor.json`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/hooks/hooks-cursor.json)
and a `run-hook.cmd` Windows shim.

### Skill-to-skill dependencies

Skills reference each other by name with explicit markers, never by
`@`-include (`@` would force-load and "burn context"). The
conventions documented in `writing-skills`:

- `**REQUIRED SUB-SKILL:** Use superpowers:test-driven-development`
- `**REQUIRED BACKGROUND:** You MUST understand superpowers:systematic-debugging`

The `superpowers:` prefix is the plugin namespace. Actual examples
seen in-repo:

- `executing-plans` ends by chaining into
  `superpowers:finishing-a-development-branch`.
- `brainstorming` terminates by invoking `writing-plans` and
  explicitly forbids any other follow-on skill.
- `subagent-driven-development` references
  `superpowers:finishing-a-development-branch` at the end of the
  per-task loop.
- `writing-skills` declares `superpowers:test-driven-development` as
  required background.

### Worked example (real frontmatter)

From
[`skills/test-driven-development/SKILL.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/test-driven-development/SKILL.md):

```markdown
---
name: test-driven-development
description: Use when implementing any feature or bugfix, before writing implementation code
---

# Test-Driven Development (TDD)

## Overview

Write the test first. Watch it fail. Write minimal code to pass.

**Core principle:** If you didn't watch the test fail, you don't know if it tests the right thing.

**Violating the letter of the rules is violating the spirit of the rules.**
```

## Skill catalog

All 14 skills under
[`skills/ @ f2cbfbe`](https://github.com/obra/superpowers/tree/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills).
The "When-to-invoke trigger" column quotes the skill's frontmatter
`description` field verbatim.

| Name | 1-line purpose | Path | When-to-invoke trigger (verbatim `description`) |
| --- | --- | --- | --- |
| `brainstorming` | Refine a rough idea into a written design spec through one-question-at-a-time dialogue and a hard gate against any coding before user approval. | [`skills/brainstorming/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/brainstorming/SKILL.md) | "You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation." |
| `dispatching-parallel-agents` | Dispatch one subagent per independent problem domain so unrelated failures investigate concurrently with isolated context. | [`skills/dispatching-parallel-agents/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/dispatching-parallel-agents/SKILL.md) | "Use when facing 2+ independent tasks that can be worked on without shared state or sequential dependencies" |
| `executing-plans` | Linear plan execution in a separate session with TodoWrite, used when subagent support is unavailable. | [`skills/executing-plans/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/executing-plans/SKILL.md) | "Use when you have a written implementation plan to execute in a separate session with review checkpoints" |
| `finishing-a-development-branch` | After tests pass, present merge/PR/keep/discard options and clean up the worktree. | [`skills/finishing-a-development-branch/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/finishing-a-development-branch/SKILL.md) | "Use when implementation is complete, all tests pass, and you need to decide how to integrate the work - guides completion of development work by presenting structured options for merge, PR, or cleanup" |
| `receiving-code-review` | Technical-rigor response pattern for review feedback; forbids "You're absolutely right!"-style performative agreement. | [`skills/receiving-code-review/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/receiving-code-review/SKILL.md) | "Use when receiving code review feedback, before implementing suggestions, especially if feedback seems unclear or technically questionable - requires technical rigor and verification, not performative agreement or blind implementation" |
| `requesting-code-review` | Dispatch a code-reviewer subagent with crafted context (base/head SHAs, plan, description) using the `code-reviewer.md` template. | [`skills/requesting-code-review/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/requesting-code-review/SKILL.md) | "Use when completing tasks, implementing major features, or before merging to verify work meets requirements" |
| `subagent-driven-development` | Execute a plan in-session by dispatching a fresh implementer subagent per task plus two-stage review (spec compliance, then code quality). | [`skills/subagent-driven-development/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/subagent-driven-development/SKILL.md) | "Use when executing implementation plans with independent tasks in the current session" |
| `systematic-debugging` | Four-phase root-cause method (Investigation → Hypothesis → Fix → Verification) gated by "NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST". | [`skills/systematic-debugging/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/systematic-debugging/SKILL.md) | "Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes" |
| `test-driven-development` | RED-GREEN-REFACTOR with the iron rule that any code written before a failing test must be deleted. | [`skills/test-driven-development/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/test-driven-development/SKILL.md) | "Use when implementing any feature or bugfix, before writing implementation code" |
| `using-git-worktrees` | Ensure work happens in an isolated workspace; detect existing isolation, prefer native worktree tools, fall back to `git worktree`. | [`skills/using-git-worktrees/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/using-git-worktrees/SKILL.md) | "Use when starting feature work that needs isolation from current workspace or before executing implementation plans - ensures an isolated workspace exists via native tools or git worktree fallback" |
| `using-superpowers` | Bootstrap skill injected at every `SessionStart` that teaches the model how to find and invoke other skills before responding. | [`skills/using-superpowers/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/using-superpowers/SKILL.md) | "Use when starting any conversation - establishes how to find and use skills, requiring Skill tool invocation before ANY response including clarifying questions" |
| `verification-before-completion` | Gate function that forbids "complete / fixed / passing" claims unless a fresh verification command was run and its output read in the current message. | [`skills/verification-before-completion/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/verification-before-completion/SKILL.md) | "Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always" |
| `writing-plans` | Turn an approved spec into a bite-sized (2-5 minutes per step) TDD-discipled implementation plan saved to `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`. | [`skills/writing-plans/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-plans/SKILL.md) | "Use when you have a spec or requirements for a multi-step task, before touching code" |
| `writing-skills` | TDD-for-skills: write pressure-test scenarios first, watch agents fail without the skill, then write the minimum skill text that makes them comply. | [`skills/writing-skills/SKILL.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/SKILL.md) | "Use when creating new skills, editing existing skills, or verifying skills work before deployment" |

## Representative skills (detailed)

### `using-superpowers` — the bootstrap

[`skills/using-superpowers/SKILL.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/using-superpowers/SKILL.md).
This skill is loaded automatically at every Claude Code
`SessionStart` by
[`hooks/session-start`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/hooks/session-start).
It is the only skill that ships with a `<SUBAGENT-STOP>` block
(telling subagents to skip the bootstrap if they were dispatched
with a specific task) and an `<EXTREMELY-IMPORTANT>` block
declaring "If you think there is even a 1% chance a skill might
apply to what you are doing, you ABSOLUTELY MUST invoke the skill."

Body sections include:
- "Instruction Priority" — explicit precedence order: user
  instructions (CLAUDE.md / GEMINI.md / AGENTS.md / direct requests)
  > Superpowers skills > default system prompt.
- "How to Access Skills" — per-harness invocation (`Skill` tool in
  Claude Code; `skill` in Copilot CLI; `activate_skill` in Gemini
  CLI).
- "Platform Adaptation" — references `references/copilot-tools.md`,
  `references/codex-tools.md`, `references/gemini-tools.md`.
- A Graphviz flowchart of the "user message → might any skill
  apply? → invoke → announce → create TodoWrite per checklist item
  → follow exactly" loop.
- A "Red Flags" rationalization table with 12 entries (e.g. "This
  is just a simple question" → "Questions are tasks. Check for
  skills.").
- "Skill Priority" rule: process skills (brainstorming, debugging)
  before implementation skills.
- "Skill Types" — rigid vs flexible.

Dependencies on other skills: it does not invoke any specific
downstream skill but references `brainstorming` (in its flowchart
entry "About to EnterPlanMode? → Already brainstormed? → Invoke
brainstorming skill").

Artifact it produces: none directly. It is a
system-prompt-shaping document and gates whether other skills get
invoked.

### `subagent-driven-development` — the production workflow

[`skills/subagent-driven-development/SKILL.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/subagent-driven-development/SKILL.md).
The "default" execution skill once a plan exists and the harness
supports subagents.

Opening prompt / hook: "Execute plan by dispatching fresh subagent
per task, with two-stage review after each: spec compliance review
first, then code quality review."

Body sections:
- "Why subagents" — explicit context-isolation rationale ("They
  should never inherit your session's context or history — you
  construct exactly what they need").
- "Continuous execution" — explicitly forbids pausing between tasks
  for human check-ins.
- "When to Use" with a 5-node decision flowchart vs.
  `executing-plans`.
- "The Process" — a large Graphviz flowchart showing the per-task
  subgraph: dispatch implementer → questions? →
  implements/tests/commits/self-reviews → spec reviewer → fixes →
  code quality reviewer → fixes → mark complete → loop or finish.
- "Model Selection" — explicit guidance to use the cheapest model
  that handles each role (mechanical implementer = cheap;
  integration = standard; architecture/review = most capable).
- "Handling Implementer Status" — four status codes (`DONE`,
  `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`) and how to
  respond to each.
- "Prompt Templates" — list of the three sibling prompt files.

Dependencies on other skills: chains into
`superpowers:finishing-a-development-branch` after the last task.

Sibling files this skill dispatches as subagent prompts:
- [`implementer-prompt.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/subagent-driven-development/implementer-prompt.md)
- [`spec-reviewer-prompt.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/subagent-driven-development/spec-reviewer-prompt.md)
- [`code-quality-reviewer-prompt.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/subagent-driven-development/code-quality-reviewer-prompt.md)

Artifact: committed code in the working branch, a complete
TodoWrite per task, and three sub-agent transcripts per task.

### `writing-skills` — the meta skill

[`skills/writing-skills/SKILL.md @ f2cbfbe`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/SKILL.md).
Defines the schema all other skills use.

Opening prompt: "**Writing skills IS Test-Driven Development
applied to process documentation.**"

Body sections:
- "TDD Mapping for Skills" — a table mapping each TDD concept (test
  case, RED, GREEN, refactor) to a skill-authoring step (pressure
  scenario, baseline behavior, draft SKILL.md, plug loopholes).
- "When to Create a Skill" / "Skill Types" (Technique / Pattern /
  Reference).
- "Directory Structure" — formalizes the
  `skills/skill-name/SKILL.md` + supporting-files layout.
- "SKILL.md Structure" with explicit frontmatter rules (name
  format, description = WHEN-only rule).
- "Claude Search Optimization (CSO)" — 4 sub-rules: rich
  description, keyword coverage, descriptive naming, token
  efficiency (with target word counts: <150 for getting-started,
  <200 for frequently-loaded, <500 otherwise).
- "Cross-Referencing Other Skills" — formal pattern (`**REQUIRED
  SUB-SKILL:** Use superpowers:foo`), explicit ban on `@`-include
  syntax.
- "Flowchart Usage" — when (and only when) to use Graphviz.
- "The Iron Law (Same as TDD)" — "NO SKILL WITHOUT A FAILING TEST
  FIRST" applies to creates and edits.
- "Testing All Skill Types" — distinct test approaches per skill
  type (discipline / technique / pattern / reference).
- "Bulletproofing Skills Against Rationalization" — references
  `persuasion-principles.md` (Cialdini, 2021; Meincke et al.,
  2025).
- "Skill Creation Checklist" — RED / GREEN / REFACTOR phases, each
  with explicit TodoWrite items.

Dependencies: declared `**REQUIRED BACKGROUND:**
superpowers:test-driven-development`, and points to sibling files
[`anthropic-best-practices.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/anthropic-best-practices.md),
[`persuasion-principles.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/persuasion-principles.md),
[`testing-skills-with-subagents.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/testing-skills-with-subagents.md),
[`graphviz-conventions.dot`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/graphviz-conventions.dot),
and
[`render-graphs.js`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/render-graphs.js).

Artifact: a new `skills/<name>/SKILL.md` plus pressure-test
transcripts (kept as e.g.
`skills/systematic-debugging/test-pressure-1.md`,
`test-pressure-2.md`, `test-pressure-3.md`).

## Notable conventions

- **Three-tier instruction priority, codified in the bootstrap
  skill.** User instructions in CLAUDE.md / GEMINI.md / AGENTS.md
  beat any Superpowers skill, which beats the default system prompt
  ([`using-superpowers` "Instruction Priority"](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/using-superpowers/SKILL.md)).
- **Bootstrap-by-hook, not by manifest.** Skills are not pre-loaded;
  the `SessionStart` hook injects only
  `using-superpowers/SKILL.md` and lets the model decide which
  other skills to invoke via the `Skill` tool. Matchers fire on
  `startup`, `clear`, and `compact` so the bootstrap survives
  `/clear` and context compaction.
- **Same skill content, per-harness adapters.** Sibling
  directories `.claude-plugin/`, `.codex-plugin/`,
  `.cursor-plugin/`, `.opencode/`, plus a top-level
  `gemini-extension.json` and `AGENTS.md` / `GEMINI.md` clones,
  mean one `skills/` tree is consumed by seven different harnesses.
  The `using-superpowers` skill detects the harness and adapts tool
  names via
  [`references/{codex,copilot,gemini}-tools.md`](https://github.com/obra/superpowers/tree/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/using-superpowers/references).
- **Flat skill namespace, editorial groups only in the README.**
  All 14 skills live directly under `skills/`. The README's Testing
  / Debugging / Collaboration / Meta grouping is not represented in
  the directory tree.
- **Iron-Law pattern for discipline skills.** Skills enforcing
  process rules (`test-driven-development`, `systematic-debugging`,
  `verification-before-completion`, `writing-skills`) all use the
  same triple-stanza recipe: a fenced "Iron Law" line + the mantra
  "Violating the letter of the rules is violating the spirit of the
  rules." + a "Red Flags" / rationalization table. `writing-skills`
  calls this a deliberate "bulletproofing against rationalization"
  pattern and references social-psychology research in
  `persuasion-principles.md`.
- **Description-is-trigger-only rule (CSO).** Skill descriptions
  describe ONLY when to invoke, never what the skill does. The
  rationale (from `writing-skills`) is that a
  workflow-summarizing description becomes a shortcut the model
  follows instead of reading the body — a discovery from real eval
  failures (the example given: a description mentioning "code
  review between tasks" caused agents to do one review instead of
  two).
- **Active-voice, verb-first naming.** Gerunds preferred for
  processes: `using-git-worktrees`, `writing-plans`,
  `executing-plans`, `dispatching-parallel-agents`,
  `requesting-code-review`, `receiving-code-review`,
  `using-superpowers`, `writing-skills`. Skill names use
  letters/numbers/hyphens only.
- **Cross-skill references use prose markers, never path
  includes.** The convention is `**REQUIRED SUB-SKILL:** Use
  superpowers:test-driven-development`, explicitly NOT
  `@skills/...` syntax. `@` would force-load and consume context.
- **Subagent dispatch is a first-class artifact.** Skills that
  dispatch subagents ship their prompts as sibling `.md` files
  (e.g. `implementer-prompt.md`, `spec-reviewer-prompt.md`,
  `code-quality-reviewer-prompt.md`, `code-reviewer.md`,
  `spec-document-reviewer-prompt.md`,
  `plan-document-reviewer-prompt.md`). The skill body is the
  orchestration logic, the prompt files are the subagent system
  prompts.
- **Heavy reference material is broken out, not inlined.** Sibling
  files like `testing-anti-patterns.md`, `root-cause-tracing.md`,
  `defense-in-depth.md`, `condition-based-waiting.md`, and
  `anthropic-best-practices.md` keep `SKILL.md` itself scannable
  while letting the model pull in details on demand.
  Token-efficiency budget targets are explicit (<150 / <200 / <500
  words).
- **Graphviz dot for decision flowcharts, only when decisions are
  non-obvious.** Multiple skills include inline `dot` blocks; the
  convention file
  [`graphviz-conventions.dot`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/graphviz-conventions.dot)
  plus
  [`render-graphs.js`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/skills/writing-skills/render-graphs.js)
  provide style rules and an SVG renderer. `writing-skills`
  explicitly forbids flowcharts for reference, code, or linear
  instructions.
- **Hard-gate idioms.** XML-style tags like `<HARD-GATE>` (in
  `brainstorming`), `<SUBAGENT-STOP>` and `<EXTREMELY-IMPORTANT>`
  (in `using-superpowers`), and `<Good>` / `<Bad>` (in
  `test-driven-development` and `writing-skills`) appear as
  recurring markup conventions.
- **Mandatory output paths.** Specs go to
  `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`; plans go to
  `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`. Both paths
  note "user preferences override this default."
- **Bite-sized task granularity.** `writing-plans` defines a
  2-5-minute-per-step rule: "Write the failing test" / "Run it to
  make sure it fails" / "Implement minimal code" / "Run tests" /
  "Commit" are each one step.
- **TDD-for-everything.** Both `test-driven-development` and
  `writing-skills` use the same RED-GREEN-REFACTOR ceremony;
  `writing-skills` extends it to documentation with pressure-test
  scenarios run via subagents.
- **No fork-style customization tolerated upstream.**
  [`AGENTS.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/AGENTS.md)
  declares a 94% PR rejection rate and explicitly refuses
  third-party dependencies, "compliance" rewrites, domain-specific
  skills, and fork-specific changes. The README states "we don't
  generally accept contributions of new skills."
- **Versioning.** Plugin version `5.1.0` is declared in
  [`.claude-plugin/plugin.json`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/.claude-plugin/plugin.json),
  with release notes tracked in
  [`RELEASE-NOTES.md`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/RELEASE-NOTES.md)
  and bump rules in
  [`.version-bump.json`](https://github.com/obra/superpowers/blob/f2cbfbefebbfef77321e4c9abc9e949826bea9d7/.version-bump.json).
