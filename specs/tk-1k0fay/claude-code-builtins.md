---
name: Claude Code Built-In Skills Catalog
description: Per-source survey of Claude Code's CLI-bundled skills (verify, code-review, security-review, run, init, schedule, loop, claude-api, etc.) for the gc-toolkit ecosystem-skills audit (tk-1k0fay).
---

# Claude Code Built-In Skills Catalog

## Provenance table

| Doc-type or artifact | Producer (skill / concept / workflow step that emits it upstream) | Source location (URL or repo path + commit SHA) | Surveyed at |
| ---|---|---|---|
| Built-in skills catalog (this document) | Claude Code CLI v2.1.150 bundled skills + commands reference | https://code.claude.com/docs/en/commands.md | 2026-05-24 |
| Skills documentation | Anthropic's Claude Code documentation | https://code.claude.com/docs/en/skills.md | 2026-05-24 |
| Code Review documentation | Anthropic's Claude Code documentation | https://code.claude.com/docs/en/code-review.md | 2026-05-24 |
| Public reference / demo skills repository (not the bundled-skill source) | anthropics/skills public repository — overlaps with the bundled catalog only for `claude-api`; the rest are reference/demo skills, not the implementations shipped in the CLI | https://github.com/anthropics/skills | 2026-05-24 |

## License / source ownership

Claude Code is Anthropic's official CLI tool. Built-in commands and
bundled skills ship under the Claude Code license (proprietary,
bundled with the CLI binary at
`/home/zook/.local/share/claude/versions/2.1.150`). The public
`anthropics/skills` repository is a separate codebase — primarily
reference/demo/public skills (source-available document-skills,
Apache 2.0 example-skills) — and is not the source of the CLI's
bundled skills. Of the bundled catalog, only `claude-api` clearly
overlaps with content published in that public repo; the rest of
the bundled skills (`/verify`, `/code-review`, `/batch`, etc.) are
proprietary to Anthropic and distributed as part of the Claude Code
binary.

## Skill format

Claude Code uses the **Agent Skills** standard
(https://agentskills.io/) with Anthropic extensions for invocation
control and subagent execution.

### File location on disk

Skills reside in one of four scopes:

| Scope | Path | Applies to |
|---|---|---|
| Bundled (CLI) | Compiled into `/home/zook/.local/share/claude/versions/2.1.150` binary | Every session automatically |
| Enterprise | Managed settings (server-delivered) | All users in organization |
| Personal | `~/.claude/skills/<skill-name>/SKILL.md` | All user projects |
| Project | `.claude/skills/<skill-name>/SKILL.md` | Current project only |
| Plugin | `<plugin>/skills/<skill-name>/SKILL.md` | Where plugin is enabled |

Bundled skills are not stored as files on disk; they are compiled
into the Claude Code binary and loaded by the harness at session
startup.

### Structure example: User-defined skill

A custom skill follows this structure:

```
my-skill/
├── SKILL.md           # Main instructions with YAML frontmatter (required)
├── template.md        # Optional template for Claude to fill in
├── examples/
│   └── sample.md      # Optional example output showing expected format
└── scripts/
    └── helper.sh      # Optional script Claude can execute
```

### SKILL.md format

Every skill has a `SKILL.md` file with two parts:

**Part 1: YAML frontmatter** (between `---` markers). Note: the
Agent Skills standard requires both `name` and `description`. The
Claude Code skills docs treat frontmatter fields as optional and
recommend `description`; in practice a Claude Code skill that omits
`description` will still load but is not discoverable for
model-driven invocation. Treat the example below as a representative
superset of fields seen across the docs — not a required schema:

```yaml
---
name: skill-name
description: What the skill does and when to use it
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash Git Read
context: fork
agent: Explore
effort: high
when_to_use: Additional context for triggering
argument-hint: [argument-name]
---
```

**Part 2: Markdown instructions** — plain markdown content that
Claude follows when the skill runs. Can include dynamic context
injection with `` !`shell-command` `` (executed before Claude sees
the skill).

### Worked example: Run skill (bundled)

The `/run` skill is bundled and appears in Claude's command
palette, but its actual implementation structure would look like
this if exposed:

```yaml
---
name: run
description: Launch and drive this project's app to see a change working in the running app, not just in tests
when_to_use: When testing changes against a live running app instead of tests. Triggered when user runs /run or invokes verify workflow
allowed-tools: Bash Read Edit
disable-model-invocation: false
user-invocable: true
---

# Launch your app

Build and launch your project's app to test the changes:

1. Infer the project type (CLI, server, TUI, browser-driven)
2. Build from your README, package.json, or Makefile
3. Launch the app
4. Observe the result

If the app requires special setup (database, env file, graphical session),
use /run-skill-generator to record the recipe.
```

## Built-in skill catalog

The table below lists the commands marked **Skill** in the Claude
Code commands reference for v2.1.150 — 9 entries that are
prompt-based (Claude orchestrates the work). A separate set
(`/init`, `/review`, `/security-review`) is described in the skills
docs as available through the Skill tool but is not marked Skill in
the commands table; those are noted below the main table.

| Name | 1-line purpose | When-to-invoke trigger | Slash command? (Y/N) |
|---|---|---|---|
| `batch` | Orchestrate large-scale changes across a codebase in parallel (5-30 units) | When refactoring spans multiple independent files/modules | Y: `/batch <instruction>` |
| `claude-api` | Load Claude API reference material for project language + Managed Agents | When building/debugging Claude API / Anthropic SDK apps; auto-triggers on anthropic imports | Y: `/claude-api [migrate|managed-agents-onboard]` |
| `code-review` | Review the current diff for correctness bugs at adjustable effort level | Before shipping; checking diff for bugs; optional inline PR comments | Y: `/code-review [effort] [--comment] [target]` |
| `debug` | Enable debug logging and troubleshoot issues by reading session logs | When diagnosing runtime or configuration errors | Y: `/debug [description]` |
| `fewer-permission-prompts` | Scan transcripts for common read-only tool calls and add allowlist | When reducing permission prompt fatigue in repeat workflows | Y: `/fewer-permission-prompts` |
| `loop` | Run a prompt or slash command repeatedly on an interval or self-paced | For monitoring tasks, polling, or autonomous maintenance checks | Y: `/loop [interval] [prompt]` |
| `run` | Launch and drive project's app to see a change working | During development; testing changes against live running app | Y: `/run` |
| `run-skill-generator` | Teach `/run` and `/verify` how to build/launch from clean environment | When project has non-standard build process (database, env vars, multi-step launch) | Y: `/run-skill-generator` |
| `verify` | Build and run app to confirm code change does what it should | Before testing/shipping; verifying changes work against running app | Y: `/verify` |

Commands marked **Skill** in the commands table: see the list above.

**Available via Skill tool but not marked Skill in the commands
table** (described in the skills docs): `/init` (generate CLAUDE.md),
`/review` (review a pull request), `/security-review` (analyze
pending changes for security vulnerabilities). These appear in the
commands reference without the Skill marker but are documented as
Skill-tool-invocable. `/schedule` similarly ships as a command for
scheduled routines and is not marked Skill in the commands table.

## Representative skills (2-3 detailed examples)

### 1. `/code-review` (bundled skill)

**Opening prompt / invocation:**
User runs `/code-review` or `/code-review high` (with effort level)
or `/code-review low --comment` (inline PR comments).

**Purpose:**
Review the current git diff for correctness bugs, logic errors,
and security vulnerabilities at a configurable effort level. Lower
effort returns fewer, higher-confidence findings; higher effort
gives broader coverage and uncertain findings.

**Body sections (inferred from documentation):**
1. Read the current git diff with dynamic context injection
2. Review for: logic bugs, security vulnerabilities, broken edge
   cases, regressions
3. Report findings by severity (Important / Nit / Pre-existing)
4. Optionally post findings as inline PR comments with `--comment`

**Dependencies:**
- Bash tool (to read `git diff`)
- Git integration (to detect current branch and PR)
- GitHub CLI (gh) if posting comments
- Claude Code session context (to access .claude files, REVIEW.md,
  CLAUDE.md)

**Artifact produced:**
- Console report with severity-tagged findings
- (Optional) Inline GitHub PR comments with extended reasoning

**Frontmatter configuration (representative):**
```yaml
---
name: code-review
description: Review the current diff for correctness bugs at adjustable effort level. Use before shipping to catch logic errors, security vulnerabilities, and regressions.
when_to_use: When checking diff for bugs; before shipping; optional inline PR review
allowed-tools: Bash Git Read
disable-model-invocation: false
user-invocable: true
---
```

### 2. `/batch` (bundled skill)

**Opening prompt / invocation:**
User runs `/batch migrate src/ from Solid to React` (example
refactoring instruction).

**Purpose:**
Decompose a large codebase change into 5-30 independent units and
execute each in an isolated git worktree with its own subagent.
Each subagent implements, tests, and opens a PR.

**Body sections (inferred from documentation):**
1. **Research phase**: Scan codebase to understand scope
2. **Decompose phase**: Break work into independent units
3. **Plan phase**: Present plan for user approval
4. **Execute phase** (if approved): For each unit:
   - Create isolated worktree
   - Spawn subagent with unit-specific instructions
   - Run tests
   - Open PR
5. **Summarize phase**: Report results across all units

**Dependencies:**
- Git (for worktree creation and PR workflow)
- GitHub CLI (gh) for PR creation
- Bash tool for test execution
- Subagent infrastructure (forked agents)
- User approval before execution

**Artifact produced:**
- Multiple git worktrees in `.git/worktrees/`
- Multiple GitHub PRs (one per unit)
- Summary report linking all PRs

**Frontmatter configuration (representative):**
```yaml
---
name: batch
description: Orchestrate large-scale changes across a codebase in parallel. Researches scope, decomposes into 5-30 units, presents plan, then spawns subagent per unit in isolated worktree. Each runs tests and opens a PR.
when_to_use: For codebase-wide refactors, framework migrations, or changes affecting many files
context: fork
agent: Plan
allowed-tools: Bash Git Glob Read
disable-model-invocation: false
user-invocable: true
---
```

### 3. `/claude-api` (bundled skill)

**Opening prompt / invocation:**
User runs `/claude-api` (loads reference), `/claude-api migrate`
(upgrade model), or `/claude-api managed-agents-onboard`
(interactive walkthrough).

**Purpose:**
Load Claude API reference material for project language (Python,
TypeScript, Java, Go, Ruby, C#, PHP, cURL) and Managed Agents.
Also activates automatically when code imports `anthropic` or
`@anthropic-ai/sdk`. Supports model migration (`/claude-api
migrate`).

**Body sections:**
1. **Reference section**: Tool use, streaming, batches, structured
   outputs, common pitfalls for detected language
2. **Managed Agents section** (on request): Setup and usage for
   Managed Agents
3. **Migration section** (on `/claude-api migrate`): Interactive
   upgrade from older model versions to latest
   - Scan specified files
   - Ask which model to target
   - Update model IDs, thinking config, other parameters
   - Commit changes

**Dependencies:**
- Language detection (read package.json, requirements.txt, etc.)
- Bash (for git commits during migration)
- Read tool (for analyzing code imports and existing API usage)

**Artifact produced:**
- Loaded reference material in session context
- (Optional) Updated API calls in source files
- (Optional) New git commit with migration changes

**Frontmatter configuration (representative):**
```yaml
---
name: claude-api
description: Load Claude API reference material for project language and Managed Agents. Auto-triggers when code imports anthropic SDK. Supports /claude-api migrate for model upgrades.
when_to_use: When building/debugging Claude API apps; auto-triggers on anthropic/ai imports; when migrating to newer model versions
allowed-tools: Read Bash Edit Glob
disable-model-invocation: false
user-invocable: true
---
```

## Notable conventions

### How Claude Code distinguishes skill levels

- **Built-in commands**: Coded directly into the CLI binary (e.g.,
  `/help`, `/exit`, `/config`). Fixed behavior, not prompt-based.
- **Bundled skills**: Prompt-based, compiled into the binary,
  available in every session without installation. Marked **Skill**
  in commands reference.
- **User/Project/Plugin skills**: Stored as files, loaded
  dynamically from `~/.claude/skills/`, `.claude/skills/`, or plugin
  directories. Live-updated during sessions.

Bundled skills use the same skill mechanism as user-defined skills
but are pre-authored by Anthropic and distributed with the CLI.

### How the harness loads bundled skills

1. **At CLI startup** (`claude --version`: 2.1.150), the harness
   reads compiled skill definitions from the binary.
2. **Skill descriptions** are loaded into context automatically so
   Claude knows what's available.
3. **Skill content** (full body) loads only when invoked by the
   user or when Claude decides to use the skill.
4. **Skills persist in context** across turns after invocation;
   full content stays loaded until compaction or session end.
5. **Bundled skills cannot be edited** (they're in the binary), but
   user-defined skills in `~/.claude/skills/` or `.claude/skills/`
   override or supplement them.

### Integration with harness features

**settings.json / settings.local.json:**
- `skillOverrides` (object): Control visibility of skills in `/`
  menu and Claude's invocation context
  (on/name-only/user-invocable-only/off).
- `disableSkillShellExecution` (boolean): Disable shell injection
  (`` !`command` ``) in user/project/plugin skills (bundled skills
  unaffected).

**Hooks:**
- Skills can declare scoped hooks in their frontmatter (`hooks:`
  field).
- Hooks fire when a skill is invoked or completes (e.g., post-skill
  validation, cleanup).

**MCP integration:**
- Skills can list `allowed-tools` to grant permissions for
  MCP-based tools without per-use prompts.
- MCP servers can expose prompts that appear as commands (format:
  `/mcp__<server>__<prompt>`), separate from skills.

**Permissions:**
- Skill tool (`Skill(name)` or `Skill(name *)`) governs whether
  Claude can invoke skills programmatically.
- User can invoke any skill with `/skill-name` unless
  `disable-model-invocation: true` is set.
- `allowed-tools` in frontmatter grants pre-approval for listed
  tools while skill is active.

### Naming conventions

- **Kebab-case**: All skill names use lowercase letters, numbers,
  hyphens (e.g., `code-review`, `run-skill-generator`,
  `fewer-permission-prompts`).
- **Max 64 characters**: Skill directory/name length limited.
- **Namespacing**: Plugin skills use `plugin-name:skill-name`
  syntax to avoid conflicts.
- **Bundled skills**: No prefix; bundled skills live in a private
  namespace within the binary.

### Skill content lifecycle and context behavior

1. **Skill description**: Always loaded into context so Claude
   knows what's available (unless hidden with `user-invocable:
   false` or `skillOverrides: off`).
2. **Skill body**: Loaded only when invoked (user types `/name` or
   Claude decides to use it).
3. **Persistence**: Once loaded, skill content stays in context for
   the rest of the session.
4. **Compaction**: During auto-compaction, recent skill invocations
   are re-attached with first 5,000 tokens each, up to 25,000 tokens
   total budget across all skills. Older skills may be dropped.
5. **Substitution**: Inline `` !`command` `` placeholders are
   executed before Claude sees the skill content (preprocessing,
   not tool use). Output replaces the placeholder.

### Notable skill-harness behaviors

- **Dynamic invocation**: Claude decides when to use a skill based
  on its description and `when_to_use` field (unless
  `disable-model-invocation: true`).
- **Fork context**: Skills with `context: fork` run in an isolated
  subagent and do not have access to conversation history.
- **Agent selection**: `agent:` field specifies which subagent type
  (Explore, Plan, general-purpose, or custom) executes a forked
  skill.
- **Argument passing**: Skills accept arguments via `$ARGUMENTS`,
  `$ARGUMENTS[N]`, or `$0`/`$1` (named args with `arguments:`
  frontmatter).
- **Tool pre-approval**: `allowed-tools` grants permission for
  listed tools without per-use prompts when skill is active.
- **Tool search**: Skills can use MCP tool search to handle
  thousands of tools on demand.
- **Skill visibility override**: `/skills` menu (interactive
  picker) lets users hide/show skills; settings are saved to
  `skillOverrides` in `.claude/settings.local.json`.

## Additional notes

### Bundled skill source distribution

The bundled skills listed in this catalog are authored by Anthropic
and compiled into the Claude Code binary. They are not individually
stored as `.md` files on disk. The public `anthropics/skills`
repository (https://github.com/anthropics/skills) is a separate,
reference/demo/public catalog rather than the bundled-skill source —
of the bundled catalog, only `claude-api` clearly overlaps with
content in that public repo. The public repo's contents include:

- **Example skills** (apache-2.0): General patterns, creative
  tasks, test generation
- **Document skills** (source-available, closed): Docx, PDF, PPTX,
  XLSX manipulation

These public skills are reference implementations or examples; the
actual bundled skills in Claude Code v2.1.150 are the compiled
versions in the binary and are not, in general, drawn from this
repository.

### Skill invocation surface

All built-in skills listed are accessible via slash commands in
interactive Claude Code sessions:
- Type `/` to see the full menu
- Type `/<letters>` to filter
- `Enter` to invoke
- Slash commands work only at the start of a user message

### Non-skill commands

The Claude Code CLI also includes many built-in commands that are
not skills (e.g., `/help`, `/exit`, `/model`, `/effort`, `/context`,
`/compact`, `/mcp`, `/permissions`, `/resume`, `/rewind`, `/diff`,
etc.). Current official command docs list roughly ninety commands
total, with only the entries marked **Skill** being prompt-based;
the rest are hard-coded into the CLI and do not use the skill
mechanism. They appear in the same `/` menu but are clearly
distinguished in the commands reference.

### Tool availability to skills

Bundled skills have broad tool access by default:
- Bash (shell commands)
- Read, Edit, Glob (file operations)
- Bash, Git (version control)
- Web tools (where configured)
- MCP tools (if connected)

The `allowed-tools` frontmatter field grants additional
pre-approval for specific tools without per-use permission prompts.

## Manifest of CLI-bundled skills

Commands marked **Skill** in the commands reference (prompt-based,
Claude-orchestrated):

1. **`batch`** — Parallel large-scale refactoring across isolated
   worktrees
2. **`claude-api`** — Claude API reference + model migration
3. **`code-review`** — Correctness review with effort-level tuning
4. **`debug`** — Debug logging and session troubleshooting
5. **`fewer-permission-prompts`** — Permission allowlist generator
6. **`loop`** — Recurring task automation (interval or self-paced)
7. **`run`** — App launch and observation
8. **`run-skill-generator`** — Learn project build/launch recipe
9. **`verify`** — App testing against running instance

Documented as available through the Skill tool but not marked
**Skill** in the commands table:

- **`init`** — Generate CLAUDE.md project file
- **`review`** — Review a pull request
- **`security-review`** — Vulnerability scanning on diffs

Also shipped as commands (not marked Skill in the commands table):

- **`schedule`** — Scheduled routine creation (cron on Anthropic
  infra)

All are invocable via slash commands and callable by Claude in
appropriate contexts. None require external installation; all ship
with Claude Code v2.1.150 in the binary.
