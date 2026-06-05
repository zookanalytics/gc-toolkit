---
name: Anthropic Public Skills Catalog
description: Per-source survey of the anthropics/skills repository — the canonical SKILL.md reference and skill inventory — for the gc-toolkit ecosystem-skills audit (tk-1k0fay).
---

# Anthropic Public Skills Catalog

## Provenance

Repository: [`anthropics/skills`](https://github.com/anthropics/skills)
— default branch `main`. Latest commit at survey time:
[`690f15cac7f7b4c055c5ab109c79ed9259934081`](https://github.com/anthropics/skills/commit/690f15cac7f7b4c055c5ab109c79ed9259934081)
(2026-05-19, "Add CMA claude-api skill updates (#1164)"). Repo
created 2025-09-22, 140k stars, topic `agent-skills`.

| Doc-type or artifact | Producer (skill / concept / workflow step that emits it upstream) | Source location (URL or repo path + commit SHA) | Surveyed at |
|---|---|---|---|
| Agent Skills specification (canonical, hosted) | agentskills.io project (external canonical spec) | https://agentskills.io/specification | 2026-05-24 |
| Agent Skills spec pointer file | `spec/` directory (anthropics/skills stub) | [`spec/agent-skills-spec.md`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/spec/agent-skills-spec.md) @ 690f15c | 2026-05-24 |
| Repo README | repo root | [`README.md`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/README.md) @ 690f15c | 2026-05-24 |
| Plugin marketplace manifest | `.claude-plugin/` (Claude Code plugin packaging) | [`.claude-plugin/marketplace.json`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/.claude-plugin/marketplace.json) @ 690f15c | 2026-05-24 |
| Skill template | `template/` directory | [`template/SKILL.md`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/template/SKILL.md) @ 690f15c | 2026-05-24 |
| Third-party notices | repo root (binary deps in skills) | [`THIRD_PARTY_NOTICES.md`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/THIRD_PARTY_NOTICES.md) @ 690f15c | 2026-05-24 |
| Apache-2.0 license file (per skill) | open-source skills (most of the catalog; see the License section for the list) | e.g. [`skills/algorithmic-art/LICENSE.txt`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/algorithmic-art/LICENSE.txt) @ 690f15c | 2026-05-24 |
| Proprietary license file (per skill) | source-available skills (`docx`, `pdf`, `pptx`, `xlsx`) | e.g. [`skills/docx/LICENSE.txt`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/docx/LICENSE.txt) @ 690f15c | 2026-05-24 |
| `skills/` root directory | catalog index of named skills | [`skills/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills) @ 690f15c | 2026-05-24 |

## License

The repository has **no top-level `LICENSE` file** — the GitHub API
returns `"license": null` for the repo. Licensing is per-skill:

- **Apache-2.0** for the majority of skills (open source). Verified
  at
  [`skills/algorithmic-art/LICENSE.txt`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/algorithmic-art/LICENSE.txt)
  — standard Apache License Version 2.0, January 2004 text. The
  same Apache-2.0 file is bundled in this list of skills:
  `algorithmic-art`, `brand-guidelines`, `canvas-design`,
  `claude-api`, `frontend-design`, `internal-comms`, `mcp-builder`,
  `skill-creator`, `slack-gif-creator`, `theme-factory`,
  `web-artifacts-builder`, `webapp-testing`.
- **`doc-coauthoring` has no `LICENSE.txt`** and no `license`
  frontmatter field — **licensing unclear; do not vendor without
  resolution.** Do NOT assume Apache-2.0 by analogy with the other
  example skills.
- **Proprietary / source-available** for the four document skills
  (`docx`, `pdf`, `pptx`, `xlsx`). Their `LICENSE.txt` files (e.g.
  [`skills/docx/LICENSE.txt`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/docx/LICENSE.txt))
  state: "© 2025 Anthropic, PBC. All rights reserved" and restrict
  extraction, reproduction, derivative works, distribution,
  sublicensing, and reverse engineering outside Anthropic's
  services agreement (Consumer or Commercial Terms of Service).
- The README explicitly frames this split: *"Many skills in this
  repo are open source (Apache 2.0). We've also included the
  document creation & editing skills … under the … `skills/pdf`, …
  `skills/pptx`, and … `skills/xlsx` subfolders. These are
  source-available, not open source."*

Third-party attribution lives in
[`THIRD_PARTY_NOTICES.md`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/THIRD_PARTY_NOTICES.md),
covering BSD-2-Clause `imageio` / `imageio-ffmpeg`, GPL-v3 `FFmpeg`,
and other bundled dependencies.

## Skill format / schema (THE CANONICAL REFERENCE)

The on-repo `spec/agent-skills-spec.md` is a one-line pointer:
*"The spec is now located at https://agentskills.io/specification"*.
The canonical spec lives on that external site. The README adds:
*"This repository contains Anthropic's implementation of skills for
Claude. For information about the Agent Skills standard, see
agentskills.io."* Anthropic has moved the spec to a multi-vendor
home.

### Directory structure (canonical, quoted from spec)

> A skill is a directory containing, at minimum, a `SKILL.md` file:
>
> ```
> skill-name/
> ├── SKILL.md          # Required: metadata + instructions
> ├── scripts/          # Optional: executable code
> ├── references/       # Optional: documentation
> ├── assets/           # Optional: templates, resources
> └── ...               # Any additional files or directories
> ```

### SKILL.md frontmatter — full schema

YAML frontmatter followed by Markdown body. Per the spec table:

| Field           | Required | Constraints                                                                                                       |
| --------------- | -------- | ----------------------------------------------------------------------------------------------------------------- |
| `name`          | Yes      | Max 64 characters. Lowercase letters, numbers, and hyphens only. Must not start or end with a hyphen.             |
| `description`   | Yes      | Max 1024 characters. Non-empty. Describes what the skill does and when to use it.                                 |
| `license`       | No       | License name or reference to a bundled license file.                                                              |
| `compatibility` | No       | Max 500 characters. Indicates environment requirements (intended product, system packages, network access, etc.). |
| `metadata`      | No       | Arbitrary key-value mapping for additional metadata.                                                              |
| `allowed-tools` | No       | Space-separated string of pre-approved tools the skill may use. (Experimental)                                    |

Per-field semantic rules (verbatim or near-verbatim from the spec):

- **`name`** — "Must be 1-64 characters; May only contain unicode
  lowercase alphanumeric characters (`a-z`, `0-9`) and hyphens
  (`-`); Must not start or end with a hyphen (`-`); Must not
  contain consecutive hyphens (`--`); **Must match the parent
  directory name.**" Invalid examples called out: `PDF-Processing`
  (uppercase), `-pdf` (leading hyphen), `pdf--processing`
  (consecutive hyphens).
- **`description`** — "1-1024 characters; Should describe both
  what the skill does and when to use it; Should include specific
  keywords that help agents identify relevant tasks." Good example
  given: `"Extracts text and tables from PDF files, fills PDF
  forms, and merges multiple PDFs. Use when working with PDF
  documents or when the user mentions PDFs, forms, or document
  extraction."` Poor example: `"Helps with PDFs."`
- **`license`** — "Specifies the license applied to the skill; We
  recommend keeping it short (either the name of a license or the
  name of a bundled license file)." Example: `license: Proprietary.
  LICENSE.txt has complete terms`.
- **`compatibility`** — Optional, 1-500 chars. Spec note: *"Most
  skills do not need the `compatibility` field."* Examples:
  `Designed for Claude Code (or similar products)`, `Requires git,
  docker, jq, and access to the internet`, `Requires Python 3.14+
  and uv`.
- **`metadata`** — "A map from string keys to string values;
  Clients can use this to store additional properties not defined
  by the Agent Skills spec; We recommend making your key names
  reasonably unique to avoid accidental conflicts." Example:
  `metadata:\n  author: example-org\n  version: "1.0"`.
- **`allowed-tools`** — "A space-separated string of tools that
  are pre-approved to run; Experimental. Support for this field may
  vary between agent implementations." Example: `allowed-tools:
  Bash(git:*) Bash(jq:*) Read`.

### Body conventions

> The Markdown body after the frontmatter contains the skill
> instructions. There are no format restrictions. Write whatever
> helps agents perform the task effectively.

Recommended sections (spec): step-by-step instructions; examples
of inputs and outputs; common edge cases. Spec also notes: *"the
agent will load this entire file once it's decided to activate a
skill. Consider splitting longer SKILL.md content into referenced
files."*

### Optional directory conventions

- **`scripts/`** — executable code. "Be self-contained or clearly
  document dependencies; Include helpful error messages; Handle
  edge cases gracefully. Supported languages depend on the agent
  implementation. Common options include Python, Bash, and
  JavaScript."
- **`references/`** — documentation loaded on demand. Examples
  named in spec: `REFERENCE.md`, `FORMS.md`, domain files
  (`finance.md`, `legal.md`). "Keep individual reference files
  focused. Agents load these on demand, so smaller files mean less
  use of context."
- **`assets/`** — "Templates (document templates, configuration
  templates); Images (diagrams, examples); Data files (lookup
  tables, schemas)."

### Cross-references between files

Spec on internal file references:

> When referencing other files in your skill, use relative paths
> from the skill root:
> ```markdown
> See [the reference guide](references/REFERENCE.md) for details.
>
> Run the extraction script:
> scripts/extract.py
> ```
> Keep file references one level deep from `SKILL.md`. Avoid
> deeply nested reference chains.

No formal cross-skill aliasing, prefix grouping, or dependency
declaration exists in the spec. Skills are flat namespace,
single-string `name`. Plugin grouping is performed in
[`.claude-plugin/marketplace.json`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/.claude-plugin/marketplace.json)
by listing skill directories under three plugins:
`document-skills`, `example-skills`, `claude-api`.

### Progressive disclosure (the core loading model)

Spec section quoted in full:

> Agents load skills *progressively*, pulling in more detail only
> as a task calls for it. Skills should be structured to take
> advantage of this:
>
> 1. **Metadata** (~100 tokens): The `name` and `description`
>    fields are loaded at startup for all skills
> 2. **Instructions** (< 5000 tokens recommended): The full
>    `SKILL.md` body is loaded when the skill is activated
> 3. **Resources** (as needed): Files (e.g. those in `scripts/`,
>    `references/`, or `assets/`) are loaded only when required
>
> Keep your main `SKILL.md` under 500 lines. Move detailed
> reference material to separate files.

(The `skill-creator` skill restates this as a "three-level loading
system": "Metadata (name + description) - Always in context (~100
words); SKILL.md body - In context whenever skill triggers (<500
lines ideal); Bundled resources - As needed (unlimited, scripts can
execute without loading)".)

### Validation

> Use the [skills-ref](https://github.com/agentskills/agentskills/tree/main/skills-ref)
> reference library to validate your skills:
>
> ```bash
> skills-ref validate ./my-skill
> ```

### Two verbatim examples

**Minimal (template)** —
[`template/SKILL.md`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/template/SKILL.md)
@ 690f15c:

```markdown
---
name: template-skill
description: Replace with description of the skill and when Claude should use it.
---

# Insert instructions below
```

**With license + multi-clause trigger description** —
[`skills/algorithmic-art/SKILL.md`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/algorithmic-art/SKILL.md)
@ 690f15c:

```markdown
---
name: algorithmic-art
description: Creating algorithmic art using p5.js with seeded randomness and interactive parameter exploration. Use this when users request creating art using code, generative art, algorithmic art, flow fields, or particle systems. Create original algorithmic art rather than copying existing artists' work to avoid copyright violations.
license: Complete terms in LICENSE.txt
---

Algorithmic philosophies are computational aesthetic movements that are then expressed through code. Output .md files (philosophy), .html files (interactive viewer), and .js files (generative algorithms).
...
```

## Skill catalog

17 skills under `skills/`, all at commit 690f15c. The `description`
column is the verbatim `description` frontmatter (the
when-to-invoke trigger).

| name | 1-line purpose | path | when-to-invoke trigger (verbatim `description`) |
|---|---|---|---|
| `algorithmic-art` | Generative p5.js art with seeded randomness | [`skills/algorithmic-art/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/algorithmic-art) | Creating algorithmic art using p5.js with seeded randomness and interactive parameter exploration. Use this when users request creating art using code, generative art, algorithmic art, flow fields, or particle systems. Create original algorithmic art rather than copying existing artists' work to avoid copyright violations. |
| `brand-guidelines` | Apply Anthropic brand colors + typography | [`skills/brand-guidelines/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/brand-guidelines) | Applies Anthropic's official brand colors and typography to any sort of artifact that may benefit from having Anthropic's look-and-feel. Use it when brand colors or style guidelines, visual formatting, or company design standards apply. |
| `canvas-design` | Visual art as PNG/PDF via design philosophy | [`skills/canvas-design/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/canvas-design) | Create beautiful visual art in .png and .pdf documents using design philosophy. You should use this skill when the user asks to create a poster, piece of art, design, or other static piece. Create original visual designs, never copying existing artists' work to avoid copyright violations. |
| `claude-api` | Build/debug/optimize Anthropic SDK apps | [`skills/claude-api/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/claude-api) | Build, debug, and optimize Claude API / Anthropic SDK apps. Apps built with this skill should include prompt caching. Also handles migrating existing Claude API code between Claude model versions (4.5 → 4.6, 4.6 → 4.7, retired-model replacements). TRIGGER when: code imports `anthropic`/`@anthropic-ai/sdk`; user asks for the Claude API, Anthropic SDK, or Managed Agents; user adds/modifies/tunes a Claude feature (caching, thinking, compaction, tool use, batch, files, citations, memory) or model (Opus/Sonnet/Haiku) in a file; questions about prompt caching / cache hit rate in an Anthropic SDK project. SKIP: file imports `openai`/other-provider SDK, filename like `*-openai.py`/`*-generic.py`, provider-neutral code, general programming/ML. |
| `doc-coauthoring` | Structured workflow for docs/proposals/specs | [`skills/doc-coauthoring/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/doc-coauthoring) | Guide users through a structured workflow for co-authoring documentation. Use when user wants to write documentation, proposals, technical specs, decision docs, or similar structured content. This workflow helps users efficiently transfer context, refine content through iteration, and verify the doc works for readers. Trigger when user mentions writing docs, creating proposals, drafting specs, or similar documentation tasks. |
| `docx` | Create/read/edit .docx files | [`skills/docx/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/docx) | Use this skill whenever the user wants to create, read, edit, or manipulate Word documents (.docx files). Triggers include: any mention of 'Word doc', 'word document', '.docx', or requests to produce professional documents with formatting like tables of contents, headings, page numbers, or letterheads. Also use when extracting or reorganizing content from .docx files, inserting or replacing images in documents, performing find-and-replace in Word files, working with tracked changes or comments, or converting content into a polished Word document. If the user asks for a 'report', 'memo', 'letter', 'template', or similar deliverable as a Word or .docx file, use this skill. Do NOT use for PDFs, spreadsheets, Google Docs, or general coding tasks unrelated to document generation. |
| `frontend-design` | Production-grade frontend with non-generic aesthetic | [`skills/frontend-design/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/frontend-design) | Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build web components, pages, artifacts, posters, or applications (examples include websites, landing pages, dashboards, React components, HTML/CSS layouts, or when styling/beautifying any web UI). Generates creative, polished code and UI design that avoids generic AI aesthetics. |
| `internal-comms` | Internal comms (3P updates, newsletters, FAQs, etc.) | [`skills/internal-comms/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/internal-comms) | A set of resources to help me write all kinds of internal communications, using the formats that my company likes to use. Claude should use this skill whenever asked to write some sort of internal communications (status reports, leadership updates, 3P updates, company newsletters, FAQs, incident reports, project updates, etc.). |
| `mcp-builder` | Build MCP servers (Py/TS) | [`skills/mcp-builder/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/mcp-builder) | Guide for creating high-quality MCP (Model Context Protocol) servers that enable LLMs to interact with external services through well-designed tools. Use when building MCP servers to integrate external APIs or services, whether in Python (FastMCP) or Node/TypeScript (MCP SDK). |
| `pdf` | All PDF operations (read, fill, merge, OCR, etc.) | [`skills/pdf/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/pdf) | Use this skill whenever the user wants to do anything with PDF files. This includes reading or extracting text/tables from PDFs, combining or merging multiple PDFs into one, splitting PDFs apart, rotating pages, adding watermarks, creating new PDFs, filling PDF forms, encrypting/decrypting PDFs, extracting images, and OCR on scanned PDFs to make them searchable. If the user mentions a .pdf file or asks to produce one, use this skill. |
| `pptx` | Slides/decks creation, parsing, editing | [`skills/pptx/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/pptx) | Use this skill any time a .pptx file is involved in any way — as input, output, or both. This includes: creating slide decks, pitch decks, or presentations; reading, parsing, or extracting text from any .pptx file (even if the extracted content will be used elsewhere, like in an email or summary); editing, modifying, or updating existing presentations; combining or splitting slide files; working with templates, layouts, speaker notes, or comments. Trigger whenever the user mentions "deck," "slides," "presentation," or references a .pptx filename, regardless of what they plan to do with the content afterward. If a .pptx file needs to be opened, created, or touched, use this skill. |
| `skill-creator` | Author, eval, and benchmark skills | [`skills/skill-creator/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/skill-creator) | Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a skill from scratch, edit, or optimize an existing skill, run evals to test a skill, benchmark skill performance with variance analysis, or optimize a skill's description for better triggering accuracy. |
| `slack-gif-creator` | Animated GIFs sized for Slack | [`skills/slack-gif-creator/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/slack-gif-creator) | Knowledge and utilities for creating animated GIFs optimized for Slack. Provides constraints, validation tools, and animation concepts. Use when users request animated GIFs for Slack like "make me a GIF of X doing Y for Slack." |
| `theme-factory` | Apply 10 preset themes to artifacts | [`skills/theme-factory/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/theme-factory) | Toolkit for styling artifacts with a theme. These artifacts can be slides, docs, reportings, HTML landing pages, etc. There are 10 pre-set themes with colors/fonts that you can apply to any artifact that has been creating, or can generate a new theme on-the-fly. |
| `web-artifacts-builder` | Multi-component claude.ai HTML artifacts (React/Tailwind/shadcn) | [`skills/web-artifacts-builder/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/web-artifacts-builder) | Suite of tools for creating elaborate, multi-component claude.ai HTML artifacts using modern frontend web technologies (React, Tailwind CSS, shadcn/ui). Use for complex artifacts requiring state management, routing, or shadcn/ui components - not for simple single-file HTML/JSX artifacts. |
| `webapp-testing` | Playwright-driven local webapp testing | [`skills/webapp-testing/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/webapp-testing) | Toolkit for interacting with and testing local web applications using Playwright. Supports verifying frontend functionality, debugging UI behavior, capturing browser screenshots, and viewing browser logs. |
| `xlsx` | Spreadsheet open/edit/create across .xlsx/.xlsm/.csv/.tsv | [`skills/xlsx/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/xlsx) | Use this skill any time a spreadsheet file is the primary input or output. This means any task where the user wants to: open, read, edit, or fix an existing .xlsx, .xlsm, .csv, or .tsv file (e.g., adding columns, computing formulas, formatting, charting, cleaning messy data); create a new spreadsheet from scratch or from other data sources; or convert between tabular file formats. Trigger especially when the user references a spreadsheet file by name or path — even casually (like "the xlsx in my downloads") — and wants something done to it or produced from it. Also trigger for cleaning or restructuring messy tabular data files (malformed rows, misplaced headers, junk data) into proper spreadsheets. The deliverable must be a spreadsheet file. Do NOT trigger when the primary deliverable is a Word document, HTML report, standalone Python script, database pipeline, or Google Sheets API integration, even if tabular data is involved. |

Plugin grouping per
[`.claude-plugin/marketplace.json`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/.claude-plugin/marketplace.json)
@ 690f15c:

- **document-skills**: `xlsx`, `docx`, `pptx`, `pdf` (all
  source-available)
- **example-skills**: `algorithmic-art`, `brand-guidelines`,
  `canvas-design`, `doc-coauthoring`, `frontend-design`,
  `internal-comms`, `mcp-builder`, `skill-creator`,
  `slack-gif-creator`, `theme-factory`, `web-artifacts-builder`,
  `webapp-testing`
- **claude-api**: `claude-api` (standalone)

Frontmatter field usage observed across the in-repo skills: every
SKILL.md uses `name` + `description`. Most skills declare
`license`; the exceptions are `doc-coauthoring` (which also has no
`LICENSE.txt` in its directory — licensing unclear) and
`skill-creator` (which bundles an Apache `LICENSE.txt` but omits
the frontmatter field). None of the surveyed skills use
`compatibility`, `metadata`, or `allowed-tools` frontmatter fields.

## Representative skills (3 detailed)

### `skill-creator` — meta-skill for authoring/evaluating skills

- **Path**:
  [`skills/skill-creator/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/skill-creator)
  @ 690f15c. `SKILL.md` is **485 lines**.
- **Frontmatter**: `name: skill-creator`. `description` covers
  create/modify/optimize/eval/benchmark/improve-description. No
  `license` field (Apache LICENSE.txt still bundled).
- **Opening hook**: *"A skill for creating new skills and
  iteratively improving them. At a high level, the process of
  creating a skill goes like this: Decide what you want the skill
  to do … Write a draft … Create a few test prompts and run
  claude-with-access-to-the-skill on them … Help the user evaluate
  the results …"* — followed by the canonical "Cool? Cool."
  marker.
- **Body sections** (verbatim): "Communicating with the user",
  "Creating a skill" (subsections: Capture Intent, Interview and
  Research, Write the SKILL.md, Skill Writing Guide → Anatomy of a
  Skill / Progressive Disclosure / Principle of Lack of Surprise /
  Writing Patterns), description-optimization loop, "How skill
  triggering works", "Apply the result", "Package and Present",
  "Claude.ai-specific instructions", "Cowork-Specific
  Instructions", "Reference files", closing reiteration of the
  core loop.
- **Cross-references**: This skill restates the canonical anatomy
  and progressive-disclosure model from the spec (re-quoted
  earlier). It also contains the explicit guidance: *"include both
  what the skill does AND specific contexts for when to use it. All
  'when to use' info goes here, not in the body."* and *"please
  make the skill descriptions a little bit 'pushy' [to combat
  under-triggering]."* It refers operators to the `claude` CLI and
  surfaces three runtime targets (Claude Code / Claude.ai / Cowork)
  with different mechanics for each.
- **Supporting files** under the skill directory:
  - `agents/grader.md`, `agents/comparator.md`, `agents/analyzer.md`
    — three subagent specs
  - `assets/eval_review.html`
  - `eval-viewer/generate_review.py`, `eval-viewer/viewer.html`
  - `references/schemas.md` — JSON shapes for `evals.json`,
    `grading.json`
  - `scripts/aggregate_benchmark.py`, `scripts/generate_report.py`,
    `scripts/improve_description.py`, `scripts/package_skill.py`,
    `scripts/quick_validate.py`, `scripts/run_eval.py`,
    `scripts/run_loop.py`, `scripts/utils.py`
- **Artifacts produced**: drafted SKILL.md files, benchmark JSON,
  HTML eval review report, packaged `.skill` archive.

### `pdf` — domain skill with progressive-disclosure pattern

- **Path**:
  [`skills/pdf/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/pdf)
  @ 690f15c.
- **Frontmatter**: `name: pdf`. `license: Proprietary. LICENSE.txt
  has complete terms`. Description is an action-list trigger
  ("reading or extracting text/tables, combining/merging,
  splitting, rotating, watermarks, fillable forms, OCR,
  encrypt/decrypt, extract images …").
- **Opening hook**: *"# PDF Processing Guide / ## Overview / This
  guide covers essential PDF processing operations using Python
  libraries and command-line tools. For advanced features,
  JavaScript libraries, and detailed examples, see REFERENCE.md.
  If you need to fill out a PDF form, read FORMS.md and follow its
  instructions."*
- **Body sections**: Quick Start, Python Libraries (pypdf with
  merge/split/extract-metadata/rotate, pdfplumber for text+tables),
  with explicit pointers off to `reference.md` and `forms.md`.
- **Supporting files**: `forms.md`, `reference.md`, plus `scripts/`
  with 8 Python tools — `check_bounding_boxes.py`,
  `check_fillable_fields.py`, `convert_pdf_to_images.py`,
  `create_validation_image.py`, `extract_form_field_info.py`,
  `extract_form_structure.py`, `fill_fillable_fields.py`,
  `fill_pdf_form_with_annotations.py`.
- **Artifacts produced**: extracted text/tables, modified PDFs,
  filled form PDFs, OCR'd PDFs.

### `mcp-builder` — workflow skill with phased process + reference layer

- **Path**:
  [`skills/mcp-builder/`](https://github.com/anthropics/skills/tree/690f15cac7f7b4c055c5ab109c79ed9259934081/skills/mcp-builder)
  @ 690f15c.
- **Frontmatter**: `name: mcp-builder`, `license: Complete terms in
  LICENSE.txt`. Description names both Python (FastMCP) and
  Node/TypeScript SDK paths.
- **Opening hook**: *"# MCP Server Development Guide / ## Overview
  / Create MCP (Model Context Protocol) servers that enable LLMs to
  interact with external services through well-designed tools. The
  quality of an MCP server is measured by how well it enables LLMs
  to accomplish real-world tasks."*
- **Body sections**: A four-phase workflow — Phase 1 Deep Research
  and Planning (modern MCP design notes; protocol docs sitemap
  pointer to `https://modelcontextprotocol.io/sitemap.xml`; SDK
  selection guidance preferring TypeScript), Phase 2 Implementation
  (project structure, input/output schemas, tool descriptions,
  annotations), Phase 3 Review and Test (code quality, MCP
  Inspector), Phase 4 (continued in references).
- **Cross-references**: Links to
  `./reference/mcp_best_practices.md`, `./reference/node_mcp_server.md`,
  `./reference/python_mcp_server.md`. Also instructs the agent to
  `WebFetch` external SDK READMEs at
  `raw.githubusercontent.com/modelcontextprotocol/{typescript,python}-sdk/main/README.md`.
- **Supporting files**: `reference/evaluation.md`,
  `reference/mcp_best_practices.md`,
  `reference/node_mcp_server.md`,
  `reference/python_mcp_server.md`; `scripts/connections.py`,
  `scripts/evaluation.py`, `scripts/example_evaluation.xml`,
  `scripts/requirements.txt`.
- **Artifacts produced**: scaffolded MCP server projects (Python or
  TS), evaluation harnesses for that server.

## Notable conventions

**Spec is delegated to agentskills.io.** The on-repo
`spec/agent-skills-spec.md` was emptied to a single redirect line;
the canonical spec now lives at
<https://agentskills.io/specification>, framed as a multi-vendor
"Agent Skills standard." The README explicitly says: *"This
repository contains Anthropic's implementation of skills for
Claude. For information about the Agent Skills standard, see
agentskills.io."*

**Two-field minimum frontmatter.** Across the in-repo skills,
`name` and `description` are universal; `license` is used by most
skills (with `doc-coauthoring` and `skill-creator` as the
exceptions that omit the field); `compatibility`, `metadata`,
`allowed-tools` are never used in this repo. The spec marks
`allowed-tools` as "Experimental — Support for this field may vary
between agent implementations."

**Triggering goes in the `description` only.** From `skill-creator`
SKILL.md: *"All 'when to use' info goes here, not in the body."*
And: *"please make the skill descriptions a little bit 'pushy'"* to
counter Claude's tendency to under-trigger skills. Real skill
descriptions show this — long, keyword-rich, often containing
explicit `TRIGGER when:` / `SKIP:` / `Do NOT trigger when` clauses
(see `claude-api`, `docx`, `pptx`, `xlsx`).

**Progressive disclosure as the structural axiom.** Three explicit
layers per the spec — metadata always-loaded (~100 tokens),
SKILL.md body on-activation (~5000 tokens / ≤500 lines), and
`scripts/` + `references/` + `assets/` on-demand. `skill-creator`
reinforces this anatomy and adds: *"Keep SKILL.md under 500 lines;
if you're approaching this limit, add an additional layer of
hierarchy along with clear pointers about where the model using the
skill should go next."*

**No cross-skill aliasing or prefixes; flat single-string
`name`s.** Grouping happens at the plugin layer in
[`.claude-plugin/marketplace.json`](https://github.com/anthropics/skills/blob/690f15cac7f7b4c055c5ab109c79ed9259934081/.claude-plugin/marketplace.json)
(document-skills, example-skills, claude-api). The spec explicitly
forbids consecutive hyphens and uppercase in names, and requires
`name` == parent directory name.

**Imperative voice / "Principle of Lack of Surprise."**
`skill-creator` writing rules: *"Prefer using the imperative form
in instructions"* and *"A skill's contents should not surprise the
user in their intent if described."*

**Three runtime targets called out by name.** `skill-creator`
explicitly branches behavior for Claude Code, Claude.ai, and
Cowork — noting which sub-features (subagents, browser, `claude
-p` CLI, `present_files` tool) are or aren't available in each.

**Tooling integration.** README documents `/plugin marketplace add
anthropics/skills` for Claude Code and points to
`https://docs.claude.com/en/api/skills-guide#creating-a-skill` for
the Claude API. Skills can also be uploaded to Claude.ai.
Validation tool is `skills-ref validate ./my-skill` from the
agentskills/agentskills repo.

**Bifurcated licensing in one repo.** Apache-2.0 for the majority
of demonstration skills (see the License section for the explicit
list); bespoke proprietary text for the four document skills
(`docx`, `pdf`, `pptx`, `xlsx`) that are *"source-available, not
open source"* per the README, framed as production-skill reference
implementations. `doc-coauthoring` is the lone skill with neither a
`license` frontmatter field nor a `LICENSE.txt` file in its
directory — its licensing is unclear and it should not be vendored
without explicit resolution from upstream.

**Heavy use of `scripts/office/schemas/`** in
`docx`/`pptx`/`xlsx`: vendored ISO-IEC29500-4_2016 OOXML XSD
schemas plus ECMA-fourth-edition OPC schemas plus Microsoft WML
schemas — illustrating the spec's "any additional files or
directories" allowance and the scale skills can reach when they
need precise validation. Each of the three document skills
(`docx`, `pptx`, `xlsx`) ships its own large vendored XSD tree
(dozens of `.xsd` files per skill at the pinned tree) alongside a
`soffice.py` driver.

**Commit-message style.** Sample latest commit: `"Add CMA
claude-api skill updates (#1164)"` — short conventional title
followed by a long multi-paragraph body and PR reference. Not
enforced via a `CONTRIBUTING.md` (none exists in the tree).

**Files outside the spec's named directories are fine.** Examples
in the inventory:
`claude-api/{python,typescript,go,java,php,ruby,csharp,curl}/…`
per-language doc trees, `claude-api/shared/` cross-language
reference layer; `theme-factory/themes/*.md`;
`internal-comms/examples/*.md`; `slack-gif-creator/core/*.py`
(rather than `scripts/`);
`web-artifacts-builder/scripts/shadcn-components.tar.gz`. The spec
sanctions this with: *"… ── Any additional files or directories"*.
