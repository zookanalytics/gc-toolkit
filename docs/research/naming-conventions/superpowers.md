# Superpowers — document naming conventions

## Source surveyed

- Repo: https://github.com/obra/superpowers (default branch `main`,
  surveyed at v5.0.7, 2026-03-31)
- Full file tree: 147 blobs, sampled in full via the GitHub contents API
- Files read in full: `README.md`, `CLAUDE.md`,
  `RELEASE-NOTES.md` (head), `.gitattributes`, `.gitignore`,
  `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`,
  `.codex-plugin/plugin.json`, `.codex/INSTALL.md` (head),
  `.opencode/INSTALL.md` (head), `.github/PULL_REQUEST_TEMPLATE.md`
  (head), `agents/code-reviewer.md` (head),
  `skills/writing-skills/SKILL.md` (full),
  `skills/using-superpowers/SKILL.md` (head),
  `skills/test-driven-development/SKILL.md` (head),
  `skills/test-driven-development/testing-anti-patterns.md` (head),
  `skills/systematic-debugging/CREATION-LOG.md` (head),
  `skills/systematic-debugging/{test-academic.md, test-pressure-1.md,
  find-polluter.sh}` (heads),
  `docs/{README.codex.md, README.opencode.md, testing.md,
  windows/polyglot-hooks.md}` (heads),
  `docs/plans/2025-11-22-opencode-support-design.md` (head),
  `docs/superpowers/plans/2026-01-22-document-review-system.md` (head),
  `docs/superpowers/specs/2026-01-22-document-review-system-design.md`
  (head), `AGENTS.md` (raw — to confirm symlink contents),
  `GEMINI.md` (full)
- Frontmatter only (just the `name`/`description` block) for all 14
  skill SKILL.md files: `brainstorming`, `dispatching-parallel-agents`,
  `executing-plans`, `finishing-a-development-branch`,
  `receiving-code-review`, `requesting-code-review`,
  `subagent-driven-development`, `systematic-debugging`,
  `test-driven-development`, `using-git-worktrees`, `using-superpowers`,
  `verification-before-completion`, `writing-plans`, `writing-skills`
- Filenames only (from the recursive tree): every other path under
  `tests/`, `hooks/`, `commands/`, `scripts/`, `assets/`,
  `.github/ISSUE_TEMPLATE/`, `.cursor-plugin/`, and the supporting
  files inside other skill directories not opened above
- Commit history sampled: `e4226df2`, `582264a5`, `f3083e55`, plus log
  for `docs/plans/` vs `docs/superpowers/plans/` to confirm migration
- File-mode metadata via the git tree API (to detect symlinks)

## Directory structure

The top of the tree is split across **plugin manifests, root agent-instruction
files, content directories, and supporting tooling**:

```
/
├── .claude-plugin/{plugin.json, marketplace.json}    # Claude Code plugin
├── .codex-plugin/plugin.json                          # Codex plugin
├── .cursor-plugin/plugin.json                         # Cursor plugin
├── .codex/INSTALL.md                                  # Codex install guide
├── .opencode/{INSTALL.md, plugins/superpowers.js}     # OpenCode loader
├── .github/{PULL_REQUEST_TEMPLATE.md, ISSUE_TEMPLATE/, FUNDING.yml}
├── README.md                # User-facing intro + install
├── CLAUDE.md                # Contributor guide (canonical)
├── AGENTS.md                # → CLAUDE.md (git symlink, mode 120000)
├── GEMINI.md                # @-references to skills/ (92 bytes)
├── CODE_OF_CONDUCT.md
├── LICENSE
├── RELEASE-NOTES.md         # Versioned changelog (v5.0.7, v5.0.6, …)
├── .gitattributes, .gitignore, .version-bump.json
├── package.json             # OpenCode npm install entry; very minimal
├── gemini-extension.json    # Gemini CLI extension manifest
├── agents/
│   └── code-reviewer.md
├── commands/                # Slash commands
│   ├── brainstorm.md
│   ├── execute-plan.md
│   └── write-plan.md
├── skills/                  # FLAT namespace, 14 skills
│   ├── brainstorming/
│   ├── dispatching-parallel-agents/
│   ├── executing-plans/
│   ├── finishing-a-development-branch/
│   ├── receiving-code-review/
│   ├── requesting-code-review/
│   ├── subagent-driven-development/
│   ├── systematic-debugging/
│   ├── test-driven-development/
│   ├── using-git-worktrees/
│   ├── using-superpowers/
│   ├── verification-before-completion/
│   ├── writing-plans/
│   └── writing-skills/
├── hooks/
│   ├── hooks.json           # Claude Code hook config
│   ├── hooks-cursor.json    # Cursor hook config (camelCase variant)
│   ├── run-hook.cmd         # Polyglot CMD/bash wrapper
│   └── session-start        # Bash entrypoint (no extension)
├── scripts/
│   ├── bump-version.sh
│   └── sync-to-codex-plugin.sh
├── tests/
│   ├── brainstorm-server/   # Real Node server tests
│   ├── claude-code/         # Headless Claude Code integration tests
│   ├── codex-plugin-sync/
│   ├── explicit-skill-requests/prompts/  # .txt prompt fixtures
│   ├── opencode/
│   ├── skill-triggering/prompts/
│   └── subagent-driven-dev/
│       ├── go-fractals/{design.md, plan.md, scaffold.sh}
│       └── svelte-todo/{design.md, plan.md, scaffold.sh}
├── docs/
│   ├── README.codex.md      # Codex installation + usage doc
│   ├── README.opencode.md   # OpenCode installation + usage doc
│   ├── testing.md           # Skill testing methodology
│   ├── windows/
│   │   └── polyglot-hooks.md
│   ├── plans/               # Legacy plans location (4 files, 2025-11 → 2026-01)
│   │   ├── 2025-11-22-opencode-support-design.md
│   │   ├── 2025-11-22-opencode-support-implementation.md
│   │   ├── 2025-11-28-skills-improvements-from-user-feedback.md
│   │   └── 2026-01-17-visual-brainstorming.md
│   └── superpowers/
│       ├── plans/           # Current plans location (4 files, 2026-01 → 2026-03)
│       │   ├── 2026-01-22-document-review-system.md
│       │   ├── 2026-02-19-visual-brainstorming-refactor.md
│       │   ├── 2026-03-11-zero-dep-brainstorm-server.md
│       │   └── 2026-03-23-codex-app-compatibility.md
│       └── specs/           # Paired design specs
│           ├── 2026-01-22-document-review-system-design.md
│           └── ... (one spec per plan, same date+slug, with -design suffix)
└── assets/{app-icon.png, superpowers-small.svg}
```

A **single skill directory** is shallow and self-contained:

```
skills/<skill-name>/
├── SKILL.md              # Required entrypoint (uppercase, sorts to top)
├── <reference>.md        # Optional supporting reference files
├── examples/             # Optional sub-folder for example artifacts
├── references/           # Optional sub-folder (only in using-superpowers)
└── scripts/              # Optional sub-folder for shipped tools
```

Examples of how this fills out:

- `skills/brainstorming/`: `SKILL.md`, `spec-document-reviewer-prompt.md`,
  `visual-companion.md`, `scripts/{frame-template.html, helper.js,
  server.cjs, start-server.sh, stop-server.sh}`
- `skills/writing-skills/`: `SKILL.md`, `anthropic-best-practices.md`,
  `persuasion-principles.md`, `testing-skills-with-subagents.md`,
  `examples/CLAUDE_MD_TESTING.md`, `graphviz-conventions.dot`,
  `render-graphs.js`
- `skills/systematic-debugging/`: `SKILL.md`, `CREATION-LOG.md`,
  `condition-based-waiting.md`, `condition-based-waiting-example.ts`,
  `defense-in-depth.md`, `root-cause-tracing.md`, `find-polluter.sh`,
  `test-academic.md`, `test-pressure-1.md`, `test-pressure-2.md`,
  `test-pressure-3.md`
- `skills/using-superpowers/`: `SKILL.md`, `references/codex-tools.md`,
  `references/copilot-tools.md`, `references/gemini-tools.md`

## Filename patterns

**Pervasive convention: lowercase kebab-case `.md`.** Every body content
file uses lowercase, words separated by single hyphens, no dates, no
status, no version:

- Skill dirs: `test-driven-development/`, `using-git-worktrees/`,
  `verification-before-completion/`
- Skill supporting files: `condition-based-waiting.md`, `defense-in-depth.md`,
  `root-cause-tracing.md`, `testing-anti-patterns.md`,
  `anthropic-best-practices.md`, `persuasion-principles.md`,
  `spec-document-reviewer-prompt.md`, `code-quality-reviewer-prompt.md`
- Commands: `brainstorm.md`, `execute-plan.md`, `write-plan.md`
- Scripts: `bump-version.sh`, `sync-to-codex-plugin.sh`,
  `find-polluter.sh`, `start-server.sh`, `stop-server.sh`
- Docs sub-files: `polyglot-hooks.md`, `testing.md`

**Reserved/special filenames** that break the lowercase rule:

| Pattern              | Meaning                                                       |
| -------------------- | ------------------------------------------------------------- |
| `SKILL.md`           | **Required** entrypoint for every skill — the platform spec   |
|                      | mandates the exact case. Sorts to the top in `ls`.            |
| `CLAUDE.md`          | Claude Code agent instructions (project-level)                |
| `AGENTS.md`          | Cross-tool agent-instruction standard (here, a git symlink to |
|                      | `CLAUDE.md`)                                                  |
| `GEMINI.md`          | Gemini CLI agent-instruction standard (here, two `@./...`     |
|                      | references — see "Lifecycle markers" for the syntax)          |
| `README.md`          | Standard repo intro                                           |
| `CODE_OF_CONDUCT.md` | GitHub-recognised filename (underscore convention)            |
| `LICENSE`            | No extension — GitHub-recognised                              |
| `RELEASE-NOTES.md`   | Versioned changelog (note: dash, not underscore, not          |
|                      | `CHANGELOG.md`)                                               |
| `CREATION-LOG.md`    | One-off uppercase-with-dash file in `systematic-debugging/`,  |
|                      | documenting the skill's own extraction provenance             |

**Date-prefixed plan/spec filenames** are the project's only systematic
lifecycle convention. Format: `YYYY-MM-DD-<slug>.md`.

```
docs/superpowers/plans/2026-01-22-document-review-system.md
docs/superpowers/specs/2026-01-22-document-review-system-design.md
docs/superpowers/plans/2026-02-19-visual-brainstorming-refactor.md
docs/superpowers/specs/2026-02-19-visual-brainstorming-refactor-design.md
docs/superpowers/plans/2026-03-11-zero-dep-brainstorm-server.md
docs/superpowers/specs/2026-03-11-zero-dep-brainstorm-server-design.md
```

The plan and its paired spec share the **same date + slug**, with the
spec adding a `-design` suffix; their directory tells you whether
you're looking at the plan or the design.

The legacy `docs/plans/` directory uses a less-uniform variant:

```
docs/plans/2025-11-22-opencode-support-design.md
docs/plans/2025-11-22-opencode-support-implementation.md
docs/plans/2025-11-28-skills-improvements-from-user-feedback.md
docs/plans/2026-01-17-visual-brainstorming.md
```

The first two paired docs put `-design` and `-implementation` suffixes
on separate files in the *same* directory. The newer pattern moved each
half into its own dir.

**Skill names use active-voice or gerund.** From `writing-skills/SKILL.md`:

> Use active voice, verb-first:
> - ✅ `creating-skills` not `skill-creation`
> - ✅ `condition-based-waiting` not `async-test-helpers`

Real names follow this: `brainstorming/`, `executing-plans/`,
`writing-plans/`, `using-git-worktrees/`, `dispatching-parallel-agents/`,
`finishing-a-development-branch/`, `requesting-code-review/`,
`receiving-code-review/`, `subagent-driven-development/`,
`systematic-debugging/`, `test-driven-development/`,
`verification-before-completion/`, `using-superpowers/`. The one
non-gerund (`subagent-driven-development`) reads as an adjectival noun
phrase but stays verb-rooted.

**Test-scenario filename pattern** (in `systematic-debugging/`):

```
test-academic.md       # Comprehension / academic-style test
test-pressure-1.md     # Pressure scenario — production outage
test-pressure-2.md     # Pressure scenario — sunk cost
test-pressure-3.md     # Pressure scenario — exhaustion
```

Numbered series uses single-digit suffix (no zero-padding); the suffix
is the scenario family, not strict execution order.

**Cross-tool root-file conventions:**

- `CLAUDE.md`: regular file, 7574 bytes — the canonical contributor
  guide
- `AGENTS.md`: git symlink (mode `120000`, 9 bytes), target text =
  literal string `CLAUDE.md`
- `GEMINI.md`: regular file, 92 bytes, content is two lines:
  ```
  @./skills/using-superpowers/SKILL.md
  @./skills/using-superpowers/references/gemini-tools.md
  ```
  Gemini CLI expands `@./...` references at load time.

**Plugin-manifest filenames** are uniform across harnesses:
`plugin.json` in each `.<harness>-plugin/` directory; `.claude-plugin/`
also has `marketplace.json`. The Codex/OpenCode setups put their
install instructions in `INSTALL.md` files inside their dotfile dirs.

**Hook script extensions:**

```
hooks/session-start          # No extension — bash entrypoint
hooks/run-hook.cmd           # CMD wrapper that doubles as bash polyglot
hooks/hooks.json             # Claude Code hook config
hooks/hooks-cursor.json      # Cursor variant of the same config
```

The Cursor variant's `-cursor` suffix marks it as the same kind of file
for a different harness — same idea as the spec/plan `-design` suffix
but applied to JSON config.

**Mixed extensions in a skill directory** are accepted: `.md`, `.dot`,
`.ts`, `.js`, `.cjs`, `.html`, `.sh`, `.py`. The `writing-skills` dir
has all of them. No inferred convention for ordering.

## Doc-type taxonomy

Superpowers uses **directory placement as the primary doc-type signal**,
with one exception (the date-prefixed plan/spec files in
`docs/superpowers/`).

| Where                              | Doc type                                          | Filename style                              |
| ---------------------------------- | ------------------------------------------------- | ------------------------------------------- |
| `skills/<name>/SKILL.md`           | Skill (process / technique / pattern / reference) | `SKILL.md` (mandatory)                      |
| `skills/<name>/<other>.md`         | Per-skill supporting reference                    | kebab-case                                  |
| `skills/<name>/examples/`          | Worked example artifacts                          | varies (often UPPER_SNAKE for samples)      |
| `skills/<name>/references/`        | Tool / platform reference tables                  | kebab-case (used in `using-superpowers/`)   |
| `skills/<name>/scripts/`           | Shipped executables                               | kebab-case + extension                      |
| `skills/<name>/test-*.md`          | Pressure / academic test scenarios                | `test-<kind>[-N].md`                        |
| `skills/<name>/CREATION-LOG.md`    | Skill provenance / extraction notes               | `CREATION-LOG.md` (one occurrence)          |
| `agents/<role>.md`                 | Agent definition (frontmatter-driven prompt)      | kebab-case                                  |
| `commands/<verb>.md`               | Slash-command definition                          | kebab-case verb                             |
| `hooks/`                           | Hook scripts and configs                          | kebab-case + extension; bare exec name OK   |
| `docs/superpowers/plans/`          | Implementation plan                               | `YYYY-MM-DD-<slug>.md`                      |
| `docs/superpowers/specs/`          | Design spec (paired with plan)                    | `YYYY-MM-DD-<slug>-design.md`               |
| `docs/plans/` (legacy)             | Older plans / specs                               | mixed `YYYY-MM-DD-<slug>[-design\|-implementation].md` |
| `docs/<harness>.md` (in `docs/`)   | Harness-specific install / usage docs             | `README.<harness>.md`                       |
| `docs/<topic>.md`                  | Cross-cutting reference (e.g. `testing.md`)       | kebab-case                                  |
| `docs/<platform>/`                 | Platform-specific reference                       | kebab-case `.md` inside                     |
| `tests/<area>/`                    | Test fixtures and runners                         | kebab-case dirs, `.sh`/`.txt`/`.test.js`    |
| Root `*.md` files                  | Repo-level (README, CLAUDE, AGENTS, GEMINI,       | UPPER or proper-noun, language-specific     |
|                                    | CODE_OF_CONDUCT, RELEASE-NOTES)                   |                                             |

Within `skills/<name>/SKILL.md`, the project recognises **three skill
sub-types** in the writing-skills doc:

> ### Technique  — Concrete method with steps to follow (condition-based-waiting, root-cause-tracing)
> ### Pattern    — Way of thinking about problems (flatten-with-flags, test-invariants)
> ### Reference  — API docs, syntax guides, tool documentation (office docs)

The sub-type is **prose-only** — it lives inside SKILL.md as section
content, never in the filename or directory.

**No research / ideation / adopted / archival tier exists.** Like
BMAD, Superpowers ships only "in-main, in-effect" content. There is
no `docs/drafts/`, no `docs/proposals/`, no `_archive/`. Plans are
the closest analog to "ideation," and they live in `docs/superpowers/
plans/` alongside the implementation that consumed them — not removed
when complete.

## Lifecycle markers

Superpowers uses **five distinct lifecycle mechanisms**, each tied
to a specific kind of artifact.

### 1. `RELEASE-NOTES.md` for the whole package

A single top-of-file changelog with semver-style headers and dated
sections:

```
## v5.0.7 (2026-03-31)
### GitHub Copilot CLI Support
- **SessionStart context injection** — ...
### OpenCode Fixes
- **Skills path consistency** — ...

## v5.0.6 (2026-03-24)
### Inline Self-Review Replaces Subagent Review Loops
...
```

Backed by `.version-bump.json` and `scripts/bump-version.sh` for
mechanical version bumps. The `package.json`, `.claude-plugin/plugin.json`,
`.codex-plugin/plugin.json`, etc. all carry the same `"version"` field
(`5.0.7` at survey time) — a single version flows through every
manifest.

### 2. Date prefix on plans and specs

`YYYY-MM-DD-<slug>.md` encodes "when this design / plan was authored."
The date is the lifecycle marker — there is no `status:` frontmatter,
no "DRAFT/ACCEPTED/SUPERSEDED" suffix, no per-document state machine.
A plan's date pins it in time; whether it was implemented is inferred
from the surrounding code.

### 3. Inline `**Status:**` headers (in some plans only)

The earliest plan, `docs/plans/2025-11-22-opencode-support-design.md`,
uses a body-prose status header:

```
# OpenCode Support Design

**Date:** 2025-11-22
**Author:** Bot & Jesse
**Status:** Design Complete, Awaiting Implementation
```

Newer plans in `docs/superpowers/plans/` mostly omit this. The status
field is **opt-in, prose-only, and inconsistent** — it never moved into
YAML frontmatter or into a structured registry.

### 4. Frontmatter on skills (functional, not lifecycle)

Skill SKILL.md frontmatter has only two fields, both functional rather
than status-bearing:

```yaml
---
name: writing-skills
description: Use when creating new skills, editing existing skills, or verifying skills work before deployment
---
```

The `description:` field is a triggering condition that the harness
matches against the user's request. There is no `status:`, `draft:`,
`deprecated:`, `version:`, or `tested:` field. From `writing-skills/
SKILL.md`:

> Two required fields: `name` and `description`. Max 1024 characters
> total.

The agent definition file `agents/code-reviewer.md` adds `model: inherit`
to the frontmatter — same functional-not-lifecycle pattern.

### 5. Symlinks and `@`-references for "this file points to another"

`AGENTS.md` is a git symlink (mode `120000`) to `CLAUDE.md`. Cloning the
repo on a Unix filesystem creates an actual symlink; on Windows the
file appears as a 9-byte text file containing `CLAUDE.md`.

`GEMINI.md` uses Gemini CLI's `@<path>` syntax, which inlines the
referenced files at session-start:

```
@./skills/using-superpowers/SKILL.md
@./skills/using-superpowers/references/gemini-tools.md
```

Both mechanisms achieve "tool X uses canonical-doc Y" without
duplicating content. The git symlink represents textual identity; the
`@`-import represents composition.

### What's not a lifecycle marker

- **No archive directory.** Old plans in `docs/plans/` (2025-11 to
  2026-01) were *not* moved to `docs/superpowers/plans/` when that
  pattern emerged in 2026-01-22; the legacy directory remains in tree
  but has had no new files since 2026-01-17. There is no documented
  policy explaining the split.
- **No deprecation registry** like BMAD's `removals.txt`. If a skill is
  removed, it disappears from `main`; the `RELEASE-NOTES.md` entry is
  the only persistent trace.
- **No "this is in flight" marker.** A reader cannot tell from the file
  tree whether `docs/superpowers/plans/2026-03-23-codex-app-compatibility.md`
  is implemented or pending.

## Well-named patterns (with reasoning)

1. **`SKILL.md` (uppercase) as the entrypoint.** Mandatory across
   every skill, sorts to the top in `ls`, visually distinct from
   neighbouring lowercase reference files. Reasoning: humans, agents,
   and the platform's skill-discovery code can all find the right file
   without guessing. The `agentskills.io` specification mandates the
   exact case.

2. **Active-voice / gerund skill names.** `writing-skills`,
   `executing-plans`, `using-git-worktrees`, `dispatching-parallel-agents`.
   Reasoning (quoted from `writing-skills/SKILL.md`): "Use active voice,
   verb-first: ✅ `creating-skills` not `skill-creation`. ✅
   `condition-based-waiting` not `async-test-helpers`." Names are
   discoverable by what you're doing, not what taxonomy bucket the
   skill sits in.

3. **`YYYY-MM-DD-<slug>.md` for plans and specs.** Provides
   chronological sort + provenance + filesystem-stable identifier in
   one filename. Reasoning: a plan rarely needs renaming after the
   fact; the date is its identity. Reading the directory in `ls` order
   *is* reading the project's planning history.

4. **Paired plan + spec by shared date + slug.**
   `docs/superpowers/plans/2026-01-22-document-review-system.md`
   pairs with
   `docs/superpowers/specs/2026-01-22-document-review-system-design.md`.
   Reasoning: no metadata file, no cross-link, no sidecar — the
   filename *is* the join key. Linkage survives renames as long as both
   files rename together.

5. **`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` cross-tool pattern.**
   Same canonical contributor guide reaches three different agentic
   harnesses through three different mechanisms (regular file, git
   symlink, `@`-import). Reasoning: each agent runtime expects its own
   filename, and content needs to stay synchronised. Symlink + import
   both keep the textual source-of-truth in `CLAUDE.md`.

6. **Skill-internal flat layout with optional sub-folders.** A skill
   directory is a single namespace; reference files sit next to
   `SKILL.md` in flat space until the skill grows enough sub-content
   that `examples/`, `references/`, or `scripts/` is justified.
   Reasoning: small skills don't pay the directory-drilling cost; large
   skills (like `using-superpowers/` with three platform-tool refs) get
   structure when they need it.

7. **`description: Use when …` discipline.** 13 of the 14 skill
   descriptions begin with "Use when" and describe triggering
   conditions, not what the skill does (the lone exception is
   `brainstorming/`, which leads with `"You MUST use this before any
   creative work …"` — same intent, different rhetorical lever).
   Reasoning (from `writing-skills/SKILL.md`): "Testing revealed that
   when a description summarises the skill's workflow, Claude may
   follow the description instead of reading the full skill content."
   The format is enforced through the skill-authoring documentation
   and visibly governs the entire skills directory.

8. **`CREATION-LOG.md` (uppercase + dash).** Single-skill convention in
   `systematic-debugging/` capturing the extraction history of that
   skill. Reasoning: uppercase sorts to the top alongside `SKILL.md`,
   visually distinguishes "documentation about the skill" from "the
   skill itself." The pattern is light enough to add to any one skill
   without forcing it on the rest.

9. **Test scenarios shipped IN the skill directory** (`test-pressure-1.md`,
   `test-pressure-2.md`, `test-academic.md`). Reasoning: pressure tests
   are part of the skill's evidence base — moving them to `tests/`
   would break the "skill is one self-contained directory" invariant.
   The `test-` prefix prevents collision with content files.

10. **`RELEASE-NOTES.md` (uppercase, dash).** Distinct from a generic
    `CHANGELOG.md`. Reasoning: the file is read out loud in announcements
    ("see the v5.0.7 release notes") and tied to a public release cycle,
    not just a changelog of commits. Naming reflects the audience.

11. **Polyglot wrapper convention.** `hooks/run-hook.cmd` is valid
    syntax in both `cmd.exe` and `bash`. The `.cmd` extension wins on
    Windows (where extension determines interpreter), and the same file
    runs as bash on Unix. Reasoning (documented in `docs/windows/
    polyglot-hooks.md`): "Claude Code runs hook commands through the
    system's default shell"; one file beats two near-duplicates.

## Awkward patterns (with reasoning)

1. **Two parallel plan locations.** `docs/plans/` (4 legacy files,
   2025-11 → 2026-01) and `docs/superpowers/plans/` (4 current files,
   2026-01 → 2026-03). The migration was incremental — when the new
   convention emerged on 2026-01-22 (commit `582264a5`), old files were
   not relocated. There is no `README` in either directory explaining
   the split, no `MOVED` marker, and no commit message naming the new
   path as canonical. Cost: a reader inheriting the project can't tell
   whether `docs/plans/` is "old," "deprecated," or "for a different
   purpose."

2. **Two paired-doc patterns coexist.** The legacy `docs/plans/` uses
   `<slug>-design.md` and `<slug>-implementation.md` pairs in the *same*
   directory. The new `docs/superpowers/{plans,specs}/` uses `<slug>.md`
   and `<slug>-design.md` in *different* directories. Both styles are in
   tree; neither is documented as canonical. Cost: a contributor adding
   a new plan has to copy from a neighbour rather than refer to a
   convention.

3. **Inconsistent `**Status:**` header.** `docs/plans/2025-11-22-
   opencode-support-design.md` declares `**Status:** Design Complete,
   Awaiting Implementation`; `docs/superpowers/plans/2026-01-22-
   document-review-system.md` declares no status. Cost: status
   information is unreliable as a signal — its absence doesn't mean
   "no status," it could mean "the author didn't bother."

4. **`CREATION-LOG.md` exists in only one skill.** `systematic-debugging/
   CREATION-LOG.md` is a convention of one. The pattern doesn't
   generalise — you can't grep for `CREATION-LOG.md` to learn about any
   other skill. Cost: a useful convention is invisible because there's
   no second instance to confirm it.

5. **Test scenarios live in two places.** `skills/systematic-debugging/
   test-{academic,pressure-1,pressure-2,pressure-3}.md` are skill-local;
   `tests/skill-triggering/prompts/<skill>.txt` and
   `tests/explicit-skill-requests/prompts/<scenario>.txt` are repo-level.
   Both contain "scenarios that pressure-test agent behaviour." Cost: a
   reader looking for "all the tests" has to know to check both
   locations.

6. **Platform-specific READMEs live in `docs/`, not the root.**
   `docs/README.codex.md` and `docs/README.opencode.md` mimic the
   top-level `README.md` filename but cover only one harness each. The
   actual top-level `README.md` covers all harnesses generically. Cost:
   `README.codex.md` reads as "the Codex repo's README" rather than "the
   Codex-flavoured installation guide," which is what it is.

7. **Mixed casing on root files.** `README.md`, `CLAUDE.md`, `AGENTS.md`,
   `GEMINI.md`, `LICENSE`, `RELEASE-NOTES.md` (dash), `CODE_OF_CONDUCT.md`
   (underscore). Two punctuation styles for the multi-word names. Cost:
   minor — both are GitHub-recognised — but it makes the file list
   visually noisy.

8. **`AGENTS.md` as symlink confuses Windows users.** On a case-sensitive
   Unix filesystem the symlink is invisible to readers; on Windows
   without symlink support, the file appears as a 9-byte text file
   containing the literal string `CLAUDE.md`. Cost: a Windows user
   browsing the repo locally sees what looks like a placeholder, not the
   real instructions.

9. **`docs/plans/` named at the wrong scope.** The directory was
   apparently intended as a project-wide plans folder, but the actual
   contents are all about Superpowers itself. When the same author
   started a new plan they moved one level deeper to
   `docs/superpowers/plans/` to make room for hypothetical other
   sub-projects — but no other sub-project ever materialised. Cost: an
   extra `superpowers/` segment that does no work.

10. **`hooks/session-start` has no extension.** Sits next to
    `hooks/run-hook.cmd`. Reading the directory you can't tell that
    `session-start` is bash without `cat`-ing it. Cost: discoverability
    of the file's nature relies on convention rather than the filename.

11. **`SKILL.md` ALL-CAPS is platform-mandated but inconsistent with
    every other content file.** `SKILL.md` lives next to
    `condition-based-waiting.md`, `defense-in-depth.md`, etc. Visual
    contrast is intentional, but it's also a single exception to a
    project-wide lowercase rule. Cost: contributors writing new
    documentation may second-guess the case of any new "important" file.

## Stated rationale

Direct quotes / paraphrases from Superpowers' own docs, paired with what
the project says they're optimising for.

**On naming style** (`skills/writing-skills/SKILL.md`):

> ### 3. Descriptive Naming
> **Use active voice, verb-first:**
> - ✅ `creating-skills` not `skill-creation`
> - ✅ `condition-based-waiting` not `async-test-helpers`
>
> **Name by what you DO or core insight:**
> - ✅ `condition-based-waiting` > `async-test-helpers`
> - ✅ `using-skills` not `skill-usage`
> - ✅ `flatten-with-flags` > `data-structure-refactoring`
> - ✅ `root-cause-tracing` > `debugging-techniques`
>
> **Gerunds (-ing) work well for processes:**
> - `creating-skills`, `testing-skills`, `debugging-with-logs`
> - Active, describes the action you're taking

**On the `description:` discipline** (same file):

> **CRITICAL: Description = When to Use, NOT What the Skill Does**
>
> The description should ONLY describe triggering conditions. Do NOT
> summarise the skill's process or workflow in the description.
>
> **Why this matters:** Testing revealed that when a description
> summarises the skill's workflow, Claude may follow the description
> instead of reading the full skill content.

The "Use when ..." prefix is therefore a behavioural enforcement, not
just a stylistic convention.

**On flat-namespace skills** (same file):

> ## Directory Structure
>
> ```
> skills/
>   skill-name/
>     SKILL.md              # Main reference (required)
>     supporting-file.*     # Only if needed
> ```
>
> **Flat namespace** - all skills in one searchable namespace
>
> **Separate files for:**
> 1. **Heavy reference** (100+ lines) - API docs, comprehensive syntax
> 2. **Reusable tools** - Scripts, utilities, templates
>
> **Keep inline:**
> - Principles and concepts
> - Code patterns (< 50 lines)
> - Everything else

The flat namespace plus the size-based "split a file out" rule is the
reason each skill directory has so few files: nothing graduates to its
own file until it reaches a size threshold.

**On no `@`-references in cross-skill links** (same file):

> Use skill name only, with explicit requirement markers:
> - ✅ Good: `**REQUIRED SUB-SKILL:** Use superpowers:test-driven-development`
> - ❌ Bad: `@skills/testing/test-driven-development/SKILL.md` (force-loads, burns context)
>
> **Why no @ links:** `@` syntax force-loads files immediately,
> consuming 200k+ context before you need them.

This is interesting because `GEMINI.md` is *literally* an `@`-reference
file at the root. The rule is "no `@` links between skills" — using
them as a top-level cross-tool stub is treated separately.

**On zero dependencies and skill scope** (`CLAUDE.md`, "What We Will
Not Accept"):

> Superpowers is a zero-dependency plugin by design. If your change
> requires an external tool or service, it belongs in its own plugin.
>
> ### Project-specific or personal configuration
> Skills, hooks, or configuration that only benefit a specific project,
> team, domain, or workflow do not belong in core. Publish these as a
> separate plugin.

This explains why the `skills/` directory stays small (14 skills
total). The naming question "what should this skill be called?" is
preceded by the gating question "should this skill exist in core?"

**On lifecycle via release notes, not files**
(`RELEASE-NOTES.md`):

> ## v5.0.6 (2026-03-24)
> ### Inline Self-Review Replaces Subagent Review Loops
> The subagent review loop (dispatching a fresh agent to review
> plans/specs) doubled execution time (~25 min overhead) without
> measurably improving plan quality. … Self-review catches 3-5 real
> bugs per run in ~30s instead of ~25 min, with comparable defect rates
> to the subagent approach

Major skill-content changes are recorded with measured rationale in the
release notes — there is no `docs/decisions/`, `docs/adr/`, or per-doc
"history" frontmatter. The release notes carry the architecture-decision
record load.

**On platform compatibility** (`docs/windows/polyglot-hooks.md`):

> Claude Code plugins need hooks that work on Windows, macOS, and
> Linux. This document explains the polyglot wrapper technique that
> makes this possible.

The whole `docs/windows/` directory exists because of one specific
platform constraint. Naming a directory after the platform makes the
constraint explicit and discoverable.

## Notes for the synthesis bead

Things worth surfacing when gc-toolkit decides its own conventions:

1. **Like BMAD, Superpowers has *no* research / ideation / adopted /
   archival tier.** Plans are dated and live alongside the code they
   produced; specs are paired by filename. Status is implicit. Both
   reference projects converge on "single tier (in main = adopted)
   plus a date-prefixed planning folder." gc-toolkit wanting an
   explicit research/ideation/adopted tier is a *departure* from both
   reference projects, not a borrow.

2. **Date-prefixed `YYYY-MM-DD-<slug>.md` plus paired `-design` suffix
   is the strongest convention worth borrowing.** It gives gc-toolkit's
   `docs/escalation/` (and similar in-flight directories) a
   filesystem-native sort order, no separate metadata, and a stable
   join between paired files. The choice between
   `<slug>-design.md` (Superpowers' new style, separate dirs) vs
   `<slug>-design.md` + `<slug>-implementation.md` (Superpowers'
   legacy style, same dir) is itself a decision to make.

3. **`SKILL.md` uppercase entrypoint is mandatory — borrow the
   *pattern*, not the literal name.** If gc-toolkit ships any kind of
   "self-contained content unit with metadata," giving it a
   well-known, sorted-to-top, uppercase entrypoint filename is a
   strong move. Candidates: `MOLECULE.md`, `PRINCIPLE.md`, `ADR.md`.

4. **Active-voice naming generalises beyond skills.** The
   `creating-skills > skill-creation` rule could apply to any
   process-oriented doc gc-toolkit ships (e.g. `creating-rigs.md` >
   `rig-creation.md`, `escalating-blockers.md` > `escalation.md`).
   Worth adopting as a cross-cutting style rule for adopted docs.

5. **`CLAUDE.md` + `AGENTS.md` (symlink) + `GEMINI.md`
   (`@`-references) cross-tool pattern is worth borrowing for any
   gc-toolkit doc that needs to reach multiple agentic harnesses.**
   gc-toolkit already has `CLAUDE.md` files; the AGENTS-as-symlink
   pattern is essentially free if gc-toolkit ships docs into other
   harnesses.

6. **The legacy `docs/plans/` / current `docs/superpowers/plans/`
   split is a cautionary tale.** When a directory's purpose changes,
   *move the existing files* or write a one-line README explaining the
   split. Don't leave two parallel locations and trust readers to
   guess which is current. gc-toolkit will face the same question if
   `docs/escalation/` evolves.

7. **`description:` frontmatter discipline ("Use when …", triggering
   conditions only) is highly portable.** Whether gc-toolkit calls
   them skills, molecules, or formulas, the lesson — "Claude follows
   the description; never let it summarise the body" — is a hard-won
   finding worth respecting.

8. **`CREATION-LOG.md` is a one-off, but the *idea* is worth
   considering.** A per-doc lineage / extraction-history file gives
   readers a "why does this look the way it does" trail. If gc-toolkit
   ships principles or architecture docs that descend from research,
   a sibling `LINEAGE.md` (or frontmatter `derived-from:` field) could
   carry that load.

9. **No frontmatter `status:` is a real choice.** Both BMAD and
   Superpowers ship without one. The cost is "in-flight" docs are
   indistinguishable from "adopted" docs at a glance. The benefit is
   "no per-doc state machine to maintain." gc-toolkit's existing
   `docs/escalation/research/` strongly suggests an in-flight tier is
   useful here — which means gc-toolkit *will* depart from both
   reference projects on this axis.

10. **Skill-style "co-located reference files" (kebab-case `.md`
    siblings of `SKILL.md`) is a clean alternative to a sub-directory
    explosion.** If a gc-toolkit `principle/` or `architecture/` doc
    grows companion case studies, examples, or rationale, putting them
    as flat siblings (not in `examples/`, `cases/`, or `rationale/`
    sub-folders) keeps shallow trees. The "sub-folder only when ≥3
    files" rule from Superpowers is implicit but consistent.

11. **Worth examining before borrowing**: filename collision risk.
    Superpowers stays clean of cross-directory collisions because
    the date prefix on plans/specs makes every filename unique. BMAD
    has `how-to/project-context.md` vs `explanation/project-context.md`.
    gc-toolkit should decide whether file slugs are globally unique
    or path-qualified.

12. **Worth watching out for**: convention drift. Superpowers'
    `**Status:**` body header in early plans, dropped in later ones,
    is exactly the failure mode gc-toolkit will face if it adopts
    optional metadata. *Either* make a field required and validated,
    *or* don't have it.
