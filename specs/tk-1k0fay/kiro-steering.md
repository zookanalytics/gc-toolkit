---
name: Kiro Steering Catalog
description: Per-source survey of Kiro's steering-documents convention (and adjacent spec workflow) for the gc-toolkit ecosystem-skills audit (tk-1k0fay).
---

# Kiro Steering Catalog

| Doc-type or artifact | Producer (skill / concept / workflow step that emits it upstream) | Source location (URL or repo path + commit SHA) | Surveyed at |
|---|---|---|---|
| Steering system (overview) | Kiro IDE — Steering feature | https://kiro.dev/docs/steering/ | 2026-05-24 |
| `product.md` (foundational steering doc) | Kiro "Generate Steering Docs" button (Steering panel) | https://kiro.dev/docs/steering/ | 2026-05-24 |
| `tech.md` (foundational steering doc) | Kiro "Generate Steering Docs" button (Steering panel) | https://kiro.dev/docs/steering/ | 2026-05-24 |
| `structure.md` (foundational steering doc) | Kiro "Generate Steering Docs" button (Steering panel) | https://kiro.dev/docs/steering/ | 2026-05-24 |
| User-authored steering doc (workspace) | User via Steering panel `+` button (scope: workspace) | https://kiro.dev/docs/steering/ | 2026-05-24 |
| User-authored steering doc (global) | User via Steering panel `+` button (scope: global) | https://kiro.dev/docs/steering/ | 2026-05-24 |
| `AGENTS.md` (interop steering directive) | External AGENTS.md standard, read by Kiro | https://kiro.dev/docs/steering/ | 2026-05-24 |
| Inclusion mode: `always` | Steering frontmatter on a steering doc | https://kiro.dev/docs/steering/ | 2026-05-24 |
| Inclusion mode: `fileMatch` | Steering frontmatter with `fileMatchPattern` | https://kiro.dev/docs/steering/ | 2026-05-24 |
| Inclusion mode: `manual` | Steering frontmatter on a steering doc | https://kiro.dev/docs/steering/ | 2026-05-24 |
| Inclusion mode: `auto` | Steering frontmatter with `name` + `description` | https://kiro.dev/docs/steering/ | 2026-05-24 |
| File-reference embed `#[[file:...]]` | Steering doc body syntax | https://kiro.dev/docs/steering/ | 2026-05-24 |
| Spec artifact: `requirements.md` | Kiro Specs workflow — Requirements phase | https://kiro.dev/docs/specs/ | 2026-05-24 |
| Spec artifact: `bugfix.md` | Kiro Specs workflow — Bug Analysis phase | https://kiro.dev/docs/specs/ | 2026-05-24 |
| Spec artifact: `design.md` | Kiro Specs workflow — Design phase | https://kiro.dev/docs/specs/ | 2026-05-24 |
| Spec artifact: `tasks.md` | Kiro Specs workflow — Tasks phase | https://kiro.dev/docs/specs/ | 2026-05-24 |
| Agent hook (related automation) | Kiro Hooks feature (Agent Hooks panel) | https://kiro.dev/docs/hooks/ | 2026-05-24 |

## License / source ownership

Kiro is a commercial AI IDE produced by Amazon / AWS. Per the Kiro
license page, "The Kiro IDE and CLI are proprietary software" and are
"licensed to you as 'AWS Content' under the AWS Customer Agreement or
other written agreement with us governing your use of AWS services,
and the AWS Intellectual Property License." Copyright is held by
"©2026 Amazon.com, Inc. or its affiliates."

Kiro itself is not open source (it incorporates open-source
components such as Chromium, Bun, and various LGPL-licensed
libraries, but the IDE/CLI is proprietary). The documentation site
does not declare a separate documentation license — only the
proprietary software license is stated. Documentation pages are
openly readable at `https://kiro.dev/docs/` but are not declared as
freely vendorable. Vendoring conventions are not established by
Kiro; the steering convention itself is a directory-and-frontmatter
pattern that can be modeled without copying Kiro's prose.

Source URLs:
- License: https://kiro.dev/license/
- Docs root: https://kiro.dev/docs/

## Steering doc format

A Kiro steering doc is a markdown file with optional YAML
frontmatter that declares an **inclusion mode** controlling when
Kiro loads the file into the agent's context.

**Location:**
- Workspace steering: `.kiro/steering/` at the project root (applies
  to that workspace only).
- Global steering: `~/.kiro/steering/` in the user's home directory
  (applies to all workspaces).
- Team steering: global files distributed via MDM solutions, Group
  Policies, or other download mechanisms placed into
  `~/.kiro/steering/`.
- Precedence: "Kiro will prioritize the workspace steering
  instructions" when global and workspace files conflict.

**Frontmatter:**
Steering files use YAML frontmatter (triple-dash delimited) at the
very top of the file. The docs emphasize: "The inclusion
configuration must be the first content in the file, no blank lines
or content before it." The canonical shape is:

```yaml
---
inclusion: [mode]
---
```

Some inclusion modes require additional fields (e.g.,
`fileMatchPattern` for `fileMatch`, and `name` + `description` for
`auto`).

**Body conventions:**
Free-form markdown. Body content can include guidance, code
examples, before/after comparisons, and live-file embeds via
`#[[file:<relative_file_name>]]` syntax. The docs note best
practice is to "include contextual reasoning, not just rules" and
"provide code examples and comparisons."

**When it loads (inclusion modes):**
- `always` — loaded into every interaction automatically (default).
- `fileMatch` — loaded when files matching `fileMatchPattern` are
  touched.
- `manual` — loaded only when invoked via `#steering-file-name` or
  as a slash command.
- `auto` — loaded automatically when the user's request matches the
  `description`; also available as a slash command.

**Relationship to Kiro's "specs" workflow:**
Specs are feature/bug-scoped structured artifacts (a separate Kiro
feature). Per the docs, "Specs or specifications are structured
artifacts that formalize the development process for features and
bug fixes." Each spec generates three files: `requirements.md` (or
`bugfix.md`), `design.md`, and `tasks.md`. The specs documentation
does not explicitly describe interaction with steering files; the
steering documentation describes itself as the always-loaded
baseline ("forming the baseline of Kiro's project understanding"),
and specs sit on top as feature-scoped artifacts. Hooks (a third
Kiro feature) "can trigger before or after spec task execution," but
no equivalent steering-spec coupling is documented.

**Canonical structure per inclusion mode:**

`always` (default):
```yaml
---
inclusion: always
---

# Body content (markdown)
```

`fileMatch` (single pattern):
```yaml
---
inclusion: fileMatch
fileMatchPattern: "components/**/*.tsx"
---

# Body content (markdown)
```

`fileMatch` (multiple patterns):
```yaml
---
inclusion: fileMatch
fileMatchPattern: ["**/*.ts", "**/*.tsx", "**/tsconfig.*.json"]
---

# Body content (markdown)
```

`manual`:
```yaml
---
inclusion: manual
---

# Body content (markdown)
```

`auto`:
```yaml
---
inclusion: auto
name: api-design
description: REST API design patterns and conventions. Use when creating or modifying API endpoints.
---

# Body content (markdown)
```

**AGENTS.md variant:** Kiro also reads files named `AGENTS.md`
placed in `~/.kiro/steering/` or the workspace root. Per the docs,
AGENTS.md files "do not support inclusion modes and are always
included."

Source: [https://kiro.dev/docs/steering/](https://kiro.dev/docs/steering/)

## Steering doc catalog

Kiro generates three canonical foundational steering docs via the
"Generate Steering Docs" button in the Steering panel. All three
load with `inclusion: always` by default — they are "included in
every interaction by default, forming the baseline of Kiro's project
understanding."

| Name | Purpose | When it applies | Path/file |
|---|---|---|---|
| `product.md` | "Defines your product's purpose, target users, key features, and business objectives." Helps Kiro understand the strategic reasoning behind technical decisions. | Always (every interaction) | `.kiro/steering/product.md` (workspace) or `~/.kiro/steering/product.md` (global) |
| `tech.md` | "Documents your chosen frameworks, libraries, development tools, and technical constraints." Influences Kiro's implementation suggestions toward your established stack. | Always (every interaction) | `.kiro/steering/tech.md` |
| `structure.md` | "Outlines file organization, naming conventions, import patterns, and architectural decisions." Ensures generated code integrates seamlessly with existing codebases. | Always (every interaction) | `.kiro/steering/structure.md` |
| User-created steering doc (workspace) | User-defined guidance for a single project. Created via Steering panel `+` button with descriptive filename. | Per inclusion mode in frontmatter | `.kiro/steering/<name>.md` |
| User-created steering doc (global) | User-defined guidance applied across all workspaces. | Per inclusion mode in frontmatter | `~/.kiro/steering/<name>.md` |
| `AGENTS.md` (interop) | AGENTS.md-standard directive file read by Kiro alongside steering. Always included; no inclusion-mode support. | Always | `.kiro/steering/AGENTS.md`, workspace root, or `~/.kiro/steering/AGENTS.md` |

The docs describe "Common Steering Strategies" — user-authored
domains typically include:
- API Standards (REST conventions, error formats, authentication
  flows)
- Testing Approach (unit/integration patterns, mocking strategies)
- Code Style (naming patterns, file organization, architectural
  decisions)
- Security Guidelines (authentication, data validation,
  vulnerability prevention)
- Deployment Process (build procedures, CI/CD pipeline details)

These are not canonical defaults shipped by Kiro — they are
categories of files the docs recommend users may create.

Source: [https://kiro.dev/docs/steering/](https://kiro.dev/docs/steering/)

## Inclusion modes (THE CENTRAL CONVENTION)

Kiro's distinctive contribution is the **inclusion-mode** system on
the YAML frontmatter of each steering file. Modes control how/when
steering content enters the agent's context. The four modes are:

### `always` (default)

```yaml
---
inclusion: always
---
```

Behavior: "Loaded into every interaction automatically." Suitable
for "core standards that should influence all code generation" —
workspace-wide standards, technology preferences, universal coding
conventions. This is the default mode for the three foundational
files (`product.md`, `tech.md`, `structure.md`).

Trade-off implied by docs: always-included content consumes context
budget on every interaction, so the docs recommend reserving this
mode for baseline conventions only.

### `fileMatch` (conditional)

```yaml
---
inclusion: fileMatch
fileMatchPattern: "components/**/*.tsx"
---
```

Behavior: "Automatically included only when working with matching
files." Reduces context noise by loading specialized guidance
contextually.

Patterns accept a single glob string or an array of patterns:
```yaml
fileMatchPattern: ["**/*.ts", "**/*.tsx", "**/tsconfig.*.json"]
```

Common pattern examples from the docs:
- `"*.tsx"` — React components
- `"app/api/**/*"` — API routes
- `"**/*.test.*"` — test files

### `manual` (on-demand)

```yaml
---
inclusion: manual
---
```

Behavior: "Available on-demand using `#steering-file-name` in
chat." Users can also "type `/` to see manual steering files as
slash commands." Best for "specialized workflows, troubleshooting
guides, or migration procedures" — content that is too narrow or
expensive to always-load.

Invocation forms:
- Hash reference in chat: `#api-standards`
- Slash command picker: typing `/` surfaces manual steering files

### `auto` (description-matched)

```yaml
---
inclusion: auto
name: api-design
description: REST API design patterns and conventions. Use when creating or modifying API endpoints.
---
```

Behavior: "Automatically included when requests match the
description." Requires `name` and `description` fields. Also
accessible as slash commands for explicit inclusion.

This mode is distinct from `fileMatch` in that the trigger is the
*user's request text* (matched against `description`) rather than
the *files in scope*.

### AGENTS.md exception

Files named `AGENTS.md` in `~/.kiro/steering/` or the workspace
root are "always included" and "do not support inclusion modes."
This is the interop hook for the cross-vendor AGENTS.md standard.

Source: [https://kiro.dev/docs/steering/](https://kiro.dev/docs/steering/)

## Representative steering docs (2-3 detailed)

The Kiro steering docs at `https://kiro.dev/docs/steering/` show
three representative patterns. Examples below reflect the
structural conventions documented; the
`https://kiro.dev/docs/steering/examples/` URL returned 404 at
survey time, so detailed example bodies beyond the snippets quoted
in the main steering doc are not available.

### 1. `product.md` — foundational, always-included

**Opening:** No required prose opening. Frontmatter at the top:
```yaml
---
inclusion: always
---
```
(Default; may also be omitted to fall back to always.)

**Body sections (per docs guidance):** product purpose, target
users, key features, business objectives.

**Inclusion mode:** `always` — loaded in every interaction.

**Artifact / behavior it produces:** Shapes the strategic reasoning
Kiro uses behind technical decisions. Per the docs, it "helps Kiro
understand the strategic reasoning behind technical decisions."

**Source:** [https://kiro.dev/docs/steering/](https://kiro.dev/docs/steering/)

### 2. A `fileMatch` steering doc — conditional / scoped to a file pattern

**Opening:** Frontmatter at the top:
```yaml
---
inclusion: fileMatch
fileMatchPattern: "components/**/*.tsx"
---
```

**Body sections (per docs guidance):** Domain-specific guidance for
React components. May include `#[[file:components/ui/button.tsx]]`
live-file embeds to anchor on the canonical component
implementation.

**Inclusion mode:** `fileMatch` — loaded only when files matching
`components/**/*.tsx` are in scope.

**Artifact / behavior it produces:** Conditional guidance Kiro
applies only when working in the matched scope, reducing context
noise on unrelated interactions.

**Source:** [https://kiro.dev/docs/steering/](https://kiro.dev/docs/steering/)

### 3. An `auto` steering doc (e.g., `api-design`) — description-matched on-demand

**Opening:** Frontmatter at the top, with required `name` and
`description` fields:
```yaml
---
inclusion: auto
name: api-design
description: REST API design patterns and conventions. Use when creating or modifying API endpoints.
---
```

**Body sections (per docs guidance):** REST conventions, error
formats, authentication flows. May embed live files via
`#[[file:api/openapi.yaml]]`.

**Inclusion mode:** `auto` — loaded automatically when the user's
chat request matches the description; also available as a slash
command for explicit invocation.

**Artifact / behavior it produces:** Specialized guidance that
surfaces both via natural-language matching against `description`
and via explicit slash-command invocation, blending the `fileMatch`
and `manual` patterns.

**Source:** [https://kiro.dev/docs/steering/](https://kiro.dev/docs/steering/)

## Notable conventions

- **The `.kiro/` directory convention.** Kiro establishes `.kiro/`
  at the workspace root as its project-level configuration root,
  with `.kiro/steering/` as the steering subdirectory. The mirror
  at `~/.kiro/steering/` provides per-user / cross-workspace
  defaults. The docs do not enumerate every subdirectory under
  `.kiro/`, but they establish `.kiro/steering/` as the steering
  location and reference accessing specs and hooks through the Kiro
  IDE panel rather than via filesystem paths (specs and hooks
  directory locations are not explicitly stated in the surveyed
  pages).

- **Specs vs. steering split.** Per the docs, specs are "structured
  artifacts that formalize the development process for features and
  bug fixes" (feature/bug-scoped, three files:
  `requirements.md`/`bugfix.md`, `design.md`, `tasks.md`). Steering
  is "persistent knowledge about your workspace" (project-wide,
  always-or-conditionally loaded). The two systems are documented
  as independent: specs do not reference steering, and steering
  does not reference specs in the surveyed material. Hooks (a third
  system) "can trigger before or after spec task execution" but the
  docs do not document hook-steering coupling.

- **User override of defaults.** Workspace steering takes
  precedence over global steering. Users can override the
  foundational `product.md`/`tech.md`/`structure.md` by editing the
  generated workspace files; the docs note these are generated via
  the "Generate Steering Docs" button and then user-editable. The
  "Refine" button is available for workspace files. Files become
  "immediately available across all Kiro interactions" after
  creation/edit.

- **Live file references in steering body.** Steering docs can
  embed live workspace files via `#[[file:<relative_file_name>]]`
  syntax (e.g., `#[[file:api/openapi.yaml]]`,
  `#[[file:components/ui/button.tsx]]`). This lets a steering doc
  cite canonical implementations rather than duplicate their
  content.

- **AGENTS.md interop.** Kiro reads the cross-vendor `AGENTS.md`
  standard from `~/.kiro/steering/` or the workspace root.
  AGENTS.md is always-included and does not support inclusion modes
  — it sits outside the four-mode system as a vendor-neutral
  fallback.

- **Slash-command surface.** Both `manual` and `auto` mode files
  appear as slash commands when the user types `/` in chat.
  `manual` files additionally support `#steering-file-name`
  hash-reference inclusion.

- **Frontmatter strictness.** The docs explicitly state: "The
  inclusion configuration must be the first content in the file, no
  blank lines or content before it." Any blank line or content
  above the frontmatter breaks inclusion parsing.

- **Best-practice guardrails (documented).** Keep files focused on
  one domain; use descriptive filenames; include contextual
  reasoning (the *why*) not just rules; provide code examples and
  before/after comparisons; never include API keys or sensitive
  data; treat steering changes like code changes requiring review.

- **Team distribution.** The docs reference Team Steering as global
  files distributed via MDM solutions, Group Policies, or other
  download mechanisms placed into `~/.kiro/steering/` — i.e.,
  enterprise distribution is a documented use case, not just
  per-user manual setup.

Sources:
- [https://kiro.dev/docs/steering/](https://kiro.dev/docs/steering/)
- [https://kiro.dev/docs/specs/](https://kiro.dev/docs/specs/)
- [https://kiro.dev/docs/specs/index](https://kiro.dev/docs/specs/index)
- [https://kiro.dev/docs/hooks/](https://kiro.dev/docs/hooks/)
- [https://kiro.dev/docs/](https://kiro.dev/docs/)
- [https://kiro.dev/license/](https://kiro.dev/license/)
