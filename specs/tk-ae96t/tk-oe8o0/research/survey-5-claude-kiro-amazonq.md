---
name: Prior-art survey 5 — Claude Code, Kiro & Amazon Q
description: Full primary-source survey — Claude Code subagents + skills (scope ladder, progressive disclosure), Kiro steering inclusion modes (always / fileMatch / manual), and Amazon Q custom agents' resources globs + toolsSettings path scoping. Persisted from the mechanik-thread design session (2026-06-13); indexed by prior-art.md.
---

# Persona-system prior-art survey

## Provenance

| System | Mechanism / artifact | Source (URL + repo/path) | Surveyed at |
|---|---|---|---|
| Claude Code subagents | `.claude/agents/*.md` (+ `~/.claude/agents/`, plugin `agents/`) — YAML frontmatter + Markdown system prompt | https://code.claude.com/docs/en/sub-agents | 2026-06-13 |
| Claude Code Skills | `<skill>/SKILL.md` (+ bundled dir) — YAML frontmatter + body; Agent Skills open standard (agentskills.io) | https://code.claude.com/docs/en/skills ; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview | 2026-06-13 |
| Kiro steering | `.kiro/steering/*.md` (+ `~/.kiro/steering/`) — YAML frontmatter `inclusion` modes | https://kiro.dev/docs/steering/ | 2026-06-13 |
| Kiro specs | `.kiro/specs/{feature}/{requirements,design,tasks}.md` | https://kiro.dev/docs/specs/ | 2026-06-13 |
| Amazon Q Developer (CLI custom agents) | `.amazonq/cli-agents/*.json` — JSON schema | https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line-custom-agents-configuration.html ; verbatim config in https://github.com/aws/amazon-q-developer-cli/issues/2510 | 2026-06-13 |

Honesty notes: the AWS `docs.aws.amazon.com` pages are a JS-rendered SPA that returned only a title to WebFetch — the Amazon Q schema below is verified from (a) a verbatim user config in aws/amazon-q-developer-cli issue #2510 and (b) the AWS-docs search snippet, not from my own read of the rendered config-reference page. Kiro's `inclusion: auto` mode (with `name`/`description`) appeared in one community-sourced format spec but is **not** in the official kiro.dev steering page (which documents only `always`/`fileMatch`/`manual`); treat `auto` as unverified.

---

## 1. Claude Code subagents

- **Definition format:** One Markdown file per agent with YAML frontmatter; the Markdown body **is** the system prompt. Loaded at session start. Also definable transiently via `--agents '<json>'` (same field set, `prompt` key replaces the body).
- **Portable identity:** Yes, strongly. The frontmatter `name` + `description` + body prompt are a self-contained role. Scope ladder: managed (org) > `--agents` (session) > `.claude/agents/` (project) > `~/.claude/agents/` (all your projects) > plugin `agents/` (lowest). User-scope and plugin distribution are the explicit portability paths ("Reuse configurations across projects"). Identity comes **only** from the `name` field, not the path.
- **Owned/managed files:** Not as a declared artifact list. The closest analog is `memory: user|project|local`, which grants a persistent dir (`~/.claude/agent-memory/<name>/`, etc.) the agent reads/curates across sessions (auto-injects first 200 lines of its `MEMORY.md`). That's owned *state*, not declared *outputs*.
- **Known/context files:** No glob/fileMatch inclusion. A non-fork subagent starts with a **fresh, isolated** context (system prompt + delegation message + CLAUDE.md hierarchy + git snapshot); it does not declare input file patterns. `skills:` can preload whole skills into context. Context-scoping is by isolation, not by declared globs.
- **Processes:** Bound via the prompt body plus `hooks` (`PreToolUse`/`PostToolUse`/`Stop`→`SubagentStop`) for lifecycle validation, and `skills:` for preloaded methods. No first-class "workflow" object.
- **Instantiation:** Transient by default — spawned per task via the Agent tool, runs in its own context window, returns only a summary. Tool grants: `tools` (allowlist) / `disallowedTools` (denylist), `Agent(type,…)` to gate which sub-subagents it may spawn, plus `permissionMode`, `model`, `maxTurns`, `mcpServers`, `effort`, `isolation: worktree`, `background`. **Addressable:** yes — `@agent-<name>` / `@"name (agent)"`, natural-language naming, or session-wide via `--agent <name>` (the agent's prompt replaces the default system prompt). Resumable by agent ID. It becomes "standing" only as a background task or via `--agent`.
- **Closeness:** Very close to the *standing/addressable-agent* end of your model (gate-work + patrol), with portable identity — but weak on declared owns/knows.
- **Worth borrowing:** The scope-precedence ladder (managed > session > project > user > plugin) and `Agent(type,…)` spawn-gating are a clean, ready-made model for "portable identity + who-can-invoke-whom."

## 2. Claude Code Skills

- **Definition format:** A directory with `SKILL.md` (YAML frontmatter + Markdown body) as the entrypoint, optionally bundling `scripts/`, `references/`, `assets/`, templates. Follows the **Agent Skills open standard** (cross-tool). Only `name`/`description` are meaningful-required (Claude Code makes both optional, defaulting `name` to the dir).
- **Portable identity:** Yes — this is the system's whole point ("create once, use automatically," "package domain expertise"). Same scope ladder as subagents (enterprise > personal `~/.claude/skills/` > project `.claude/skills/` > plugin). API/claude.ai variants package as zip/`skill_id`. Caveat: skills **do not sync across surfaces** (Code/API/claude.ai managed separately).
- **Owned/managed files:** Bundles owned artifacts (scripts/templates/references) that travel **with** the persona — the strongest "owns its artifacts" story here — but these are inputs/tools it carries, not project-relative outputs it maintains. No declared write-targets.
- **Known/context files:** No glob/fileMatch *auto-inclusion*. Instead: **progressive disclosure** — L1 metadata (name+description, always in prompt, ~100 tok) → L2 `SKILL.md` body on trigger → L3 bundled files read on demand via bash. Plus **dynamic context injection**: `` !`<cmd>` `` lines run and inline output before Claude sees the body (e.g. `!​`git diff HEAD``). Context is pulled by reference/command, not matched by file glob.
- **Processes:** This is the core — a skill *is* a packaged method/workflow (`context: fork` runs it in a subagent; `disable-model-invocation: true` makes it a deliberate `/command`).
- **Instantiation:** Transient and **non-addressable as an agent** — runs inline in the main conversation context (or a forked subagent). Tool grant: `allowed-tools: Read Grep` (space-separated; note the hyphenated spelling, distinct from subagents' comma `tools:`). Invoked by Claude automatically or by the user as `/skill-name`. Never "stands up" as an agent.
- **Closeness:** Closest to your *processes* + *portable identity* facets, and to the "loaded transiently" default — but deliberately the opposite of "standing/addressable."
- **Worth borrowing:** Progressive disclosure (3-level lazy load keyed off a cheap always-on description) + `!`cmd`` dynamic injection — directly model your *knows* facet as **pulled-on-demand** rather than glob-included, which scales context far better.

## 3. Kiro steering files

- **Definition format:** `.kiro/steering/*.md`, YAML frontmatter (triple-dash) carrying an `inclusion` mode. Three default foundational files: `product.md`, `tech.md`, `structure.md`.
- **Portable identity:** Weak. Files are workspace-specific (`.kiro/steering/`) or machine-global (`~/.kiro/steering/`); docs explicitly say they're "not inherently portable across projects." (And a known bug — issue #6171 — that global `~/.kiro/steering/` files don't inject regardless of mode.) These are *standards/context*, not an addressable role.
- **Owned/managed files:** None declared. Steering is read-only guidance Claude *consumes*; it doesn't declare artifacts it writes.
- **Known/context files:** **This is the standout match for your *knows* facet.** `inclusion` modes:
  - `always` (default) — loaded into every interaction;
  - `fileMatch` + `fileMatchPattern: "<glob>"` (single or array, e.g. `["**/*.ts","**/*.tsx"]`, `"app/api/**/*"`) — auto-included **only** when the active file matches the glob;
  - `manual` — pulled on demand via `#steering-file-name` in chat.

  This is exactly declared, glob-scoped context inclusion. (Reported flaky for extension-only patterns — issue #1643.)
- **Processes:** Not in steering itself. The **spec workflow** (separate, `.kiro/specs/{feature}/`) is the process layer: `requirements.md` → `design.md` → `tasks.md`, a 3-phase requirements→design→tasks→implementation flow, with tasks grouped into dependency "waves." Steering supplies durable standards *to* that workflow.
- **Instantiation:** Not an agent at all — purely context/guidance documents; transient per-interaction, never standing or addressable. No tool grants.
- **Closeness:** The purest expression of your *knows* (project-relative, glob-scoped, conditional) — and `manual`/`#ref` mirrors your "transient until summoned." But it has no identity/owns/agent facets.
- **Worth borrowing:** Adopt `inclusion: {always | fileMatch + fileMatchPattern | manual}` near-verbatim for your *knows* declaration — it's the cleanest existing schema for "read this context only when working on matching files," and the `always`/`fileMatch`/`manual` triad maps onto portable-core vs. project-scoped vs. on-demand context.

## 4. Amazon Q Developer (CLI custom agents)

- **Definition format:** One **JSON** file per agent in `.amazonq/cli-agents/` (local) or a global location; precedence local > global > built-in default. Generated via `/agent generate`; run via `q chat --agent <name>`.
- **Portable identity:** Yes — `name` + `description` + `prompt` define a reusable role, with local-vs-global scoping for cross-project reuse. Same two-tier (project/global) portability shape as the Claude systems.
- **Owned/managed files:** Not a declared output set. (`fs_write` capability + `toolsSettings.allowedPaths` bound *where* it may write, but it doesn't enumerate maintained artifacts.)
- **Known/context files:** **Yes, and closest to "declared inputs by glob."** `resources` is an array of `file://` URIs **with glob support**, e.g. (verbatim from issue #2510):
  ```json
  "resources": ["file://AmazonQ.md", "file://README.md", "file://.amazonq/rules/**/*.md"]
  ```
  These are statically loaded into context. Beyond static `resources`, **context `hooks`** inject *dynamic* context (e.g. run `git status` and feed the output in) — combining Kiro's glob-inclusion idea with Skills' command-injection idea in one schema.
- **Processes:** Via `prompt` + `hooks` (dynamic context / lifecycle). No separate workflow object.
- **Instantiation:** Transient per `q chat --agent` session. Tool grants are the richest here: `tools` (e.g. `["*"]`), `allowedTools` (auto-trust allowlist — names like `fs_read`, `execute_bash`, MCP tool names), `toolAliases`, `mcpServers` (inline command/args/env), and **`toolsSettings`** with fine-grained `allowedPaths`/`deniedPaths` (fs tools) and `allowedCommands`/`deniedCommands` (bash). Invoked by name on the CLI; not a continuously-addressable standing agent.
- **Closeness:** The most complete single-artifact match to your model — identity (`prompt`) + knows (`resources` globs + `hooks`) + tool grants in one declaration — just JSON instead of frontmatter+body, and transient-only.
- **Worth borrowing:** Two ideas: (1) `resources: ["file://…/**/*.md"]` as an explicit *static-include* glob list, paired with (2) `toolsSettings` path/command allow-&-deny lists for capability scoping finer than a tool allowlist — together they let one persona declare *knows* and bounded *owns*-write-scope side by side.

---

## Synthesis against your four facets

| Facet | Best prior art | How it's expressed |
|---|---|---|
| **(a) portable identity** | CC subagents / Skills / Q agents | Reusable `name`+`description`+prompt(body or `prompt`); user/global scope + plugin packaging for cross-project travel. Scope-precedence ladder (managed > session > project > user > plugin) is the reusable pattern. |
| **(b) owns (writes/maintains)** | *Weakest across the board* | No system declares output artifacts. Nearest: CC subagent `memory:` (owned state dir), Skills' bundled `scripts/templates` (owned carried assets), Q `toolsSettings.allowedPaths` (bounded write scope). **Gap to fill yourself.** |
| **(c) knows (declared inputs)** | **Kiro steering** + **Q `resources`** | Kiro `inclusion: fileMatch`/`fileMatchPattern` glob = conditional context; Q `resources: file://…/**/*.md` = static glob include; Skills' progressive disclosure + `!`cmd`` = pulled-on-demand. Three viable models: glob-conditional, static-glob, lazy-pull. |
| **(d) processes** | **Skills** (+ Kiro specs) | A Skill *is* a packaged method; Kiro specs give a requirements→design→tasks workflow with dependency waves; hooks bind lifecycle steps. |
| **transient → standing/addressable** | **CC subagents** | Default transient (spawn-summarize-return); becomes standing via `--agent`/background; addressable via `@agent-<name>` and resumable by ID. The only surveyed system that cleanly spans both. |

**Bottom line for your design:** No single prior-art system covers all four facets. Subagents own the *identity + transient↔standing/addressable* axis; Skills own *processes + portable-packaging + lazy context*; Kiro steering owns *declared, glob-scoped knows*; Amazon Q is the densest single schema (identity + glob-resources + dynamic hooks + fine-grained tool/path scoping). The unowned territory is **(b) declared owned/maintained artifacts** — every system gives you write *capability* or *scope*, none lets a persona declare the project-relative artifacts it *maintains*. That's the novel slot your model adds, and worth designing deliberately rather than borrowing.
