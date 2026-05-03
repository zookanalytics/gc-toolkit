# BMAD Method — document naming conventions

## Source surveyed

- Docs site: https://docs.bmad-method.org/
- Source repo: https://github.com/bmad-code-org/BMAD-METHOD (default branch `main`,
  surveyed ~v6.6.0 era)
- Files read in full or in part:
  - `docs/_STYLE_GUIDE.md` (project-specific doc conventions)
  - `docs/index.md`, `docs/roadmap.mdx`, `docs/404.md`
  - `docs/explanation/{analysis-phase,quick-dev,why-solutioning-matters,established-projects-faq}.md`
  - `docs/how-to/{install-bmad,upgrade-to-v6}.md`
  - `docs/reference/{agents,workflow-map}.md`
  - `docs/zh-cn/explanation/` (locale-mirror sample)
  - `AGENTS.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `removals.txt`
  - `website/astro.config.mjs` (sidebar/i18n config — Starlight/Astro)
  - `tools/skill-validator.md`, `tools/validate-skills.js` (programmatic naming rules)
  - Skill samples: `src/core-skills/bmad-brainstorming/SKILL.md`;
    `src/bmm-skills/2-plan-workflows/bmad-create-prd/{SKILL.md,customize.toml,
    steps-c/step-*.md,templates/prd-template.md,data/*}`
  - Phase-directory scan: `src/bmm-skills/{1-analysis,2-plan-workflows,
    3-solutioning,4-implementation}/`

## Directory structure

The user-facing docs live under `docs/` and follow [Diátaxis](https://diataxis.fr/)
verbatim — four sibling directories, one per quadrant:

```
docs/
├── _STYLE_GUIDE.md           # Internal style reference
├── index.md                  # Landing
├── 404.md                    # Custom 404
├── roadmap.mdx               # Roadmap (MDX for components)
├── tutorials/                # Learning-oriented
│   └── getting-started.md
├── how-to/                   # Task-oriented (12 docs)
│   ├── install-bmad.md
│   ├── upgrade-to-v6.md
│   ├── shard-large-documents.md
│   ├── project-context.md
│   └── ...
├── explanation/              # Understanding-oriented (12 docs)
│   ├── analysis-phase.md
│   ├── why-solutioning-matters.md
│   ├── established-projects-faq.md
│   ├── project-context.md     # NB: same name as how-to/project-context.md
│   └── ...
├── reference/                # Information-oriented (6 docs)
│   ├── agents.md
│   ├── core-tools.md
│   ├── workflow-map.md
│   └── ...
├── cs/, fr/, vi-vn/, zh-cn/  # Locale mirrors — same tree, same filenames
```

The project-content layer (the BMAD framework itself, not the docs about it)
lives under `src/`:

```
src/
├── core-skills/              # Cross-cutting skills
│   ├── bmad-brainstorming/
│   │   ├── SKILL.md
│   │   ├── customize.toml
│   │   └── workflow.md
│   ├── bmad-shard-doc/
│   ├── module.yaml
│   └── module-help.csv
├── bmm-skills/               # BMM (BMad Method module) skills
│   ├── 1-analysis/           # Phase-numbered directories
│   │   ├── bmad-product-brief/
│   │   ├── bmad-prfaq/
│   │   └── research/         # Sub-grouping inside the phase
│   │       ├── bmad-domain-research/
│   │       ├── bmad-market-research/
│   │       └── bmad-technical-research/
│   ├── 2-plan-workflows/
│   │   └── bmad-create-prd/
│   │       ├── SKILL.md
│   │       ├── customize.toml
│   │       ├── data/
│   │       │   ├── prd-purpose.md
│   │       │   ├── domain-complexity.csv
│   │       │   └── project-types.csv
│   │       ├── steps-c/      # "c" = customizable step files
│   │       │   ├── step-01-init.md
│   │       │   ├── step-01b-continue.md
│   │       │   ├── step-02-discovery.md
│   │       │   ├── step-02b-vision.md
│   │       │   ├── step-02c-executive-summary.md
│   │       │   └── ... step-12-complete.md
│   │       └── templates/
│   │           └── prd-template.md
│   ├── 3-solutioning/
│   └── 4-implementation/
└── scripts/
```

Repo root has the conventional GitHub set: `README.md`, `CHANGELOG.md`,
`CONTRIBUTING.md`, `LICENSE`, `SECURITY.md`, `TRADEMARK.md`. Plus
`AGENTS.md` (the cross-tool standard for agent instructions, alongside
`.claude-plugin/`, `.augment/`). Translated READMEs use a suffix
convention: `README_CN.md`, `README_VN.md` — but only for two locales.

## Filename patterns

**Pervasive convention: kebab-case `.md`.** Every doc filename is lowercase
kebab-case, no dates, no status suffixes, no version numbers:

- `analysis-phase.md`, `quick-dev.md`, `workflow-map.md`
- `install-bmad.md`, `upgrade-to-v6.md`, `shard-large-documents.md`

**Filename matches the title.** The frontmatter `title:` is just the
prose form of the kebab-case slug:

```
analysis-phase.md           ↔ "Analysis Phase: From Idea to Foundation"
why-solutioning-matters.md  ↔ "Why Solutioning Matters"
established-projects-faq.md ↔ "Established Projects FAQ"
```

**Suffix-encoded subtypes.** A small set of intent suffixes is observable:

- `*-faq.md` — FAQ pages (`established-projects-faq.md`)
- `why-*-matters.md` — philosophy/rationale docs (`why-solutioning-matters.md`)
- `how-to/install-*.md`, `how-to/upgrade-to-*.md` — action-verb start

**Reserved/special filenames:**

| Pattern              | Meaning                                              |
| -------------------- | ---------------------------------------------------- |
| `_STYLE_GUIDE.md`    | Underscore prefix → meta/internal, sorts to top      |
| `404.md`             | Reserved by the static-site builder                  |
| `index.md`           | Landing page for a directory                         |
| `roadmap.mdx`        | Single MDX file — mixes JSX components with markdown |
| `SKILL.md`           | Always uppercase — skill entrypoint, sorts above other files |
| `customize.toml`     | Always lowercase, well-known sibling of `SKILL.md`   |
| `module.yaml`        | Module manifest at module root                       |
| `module-help.csv`    | Module-help data (CSV not Markdown)                  |
| `removals.txt`       | Plain text deprecation registry                      |

**Numbered step files** inside skills follow a strict pattern:

```
step-01-init.md
step-01b-continue.md
step-02-discovery.md
step-02b-vision.md
step-02c-executive-summary.md
step-03-success.md
...
step-12-complete.md
```

- Two-digit zero-padded number → lexical sort order = execution order
- Optional letter suffix (`01b`, `02b`, `02c`) → "interpolated" sub-step
  inserted after the parent without renumbering everything else
- Trailing kebab tag describes the step's purpose

**Skill names** are namespaced by an explicit module prefix: every skill
directory begins with `bmad-` (`bmad-brainstorming`, `bmad-create-prd`,
`bmad-domain-research`, `bmad-agent-dev`). Agent-skills additionally
embed the role: `bmad-agent-analyst`, `bmad-agent-architect`,
`bmad-agent-pm`, `bmad-agent-dev`, `bmad-agent-tech-writer`.

**Locale directories** mix BCP-47 and ISO-639-1 widths: `cs/`, `fr/`
(2-letter), `vi-vn/`, `zh-cn/` (region-tagged). The website config
(`website/astro.config.mjs`) names locales explicitly per-section in
the sidebar with translated labels.

## Doc-type taxonomy

BMAD distinguishes doc types through **directory placement**, not filename
suffix. The taxonomy is the directory structure:

| Type        | Where                  | Filename style         |
| ----------- | ---------------------- | ---------------------- |
| Tutorial    | `docs/tutorials/`      | kebab.md               |
| How-to      | `docs/how-to/`         | kebab.md (often verb-first) |
| Explanation | `docs/explanation/`    | kebab.md (often topic-noun, sometimes `why-*-matters.md` or `*-faq.md`) |
| Reference   | `docs/reference/`      | kebab.md (short noun)  |
| Roadmap     | `docs/roadmap.mdx`     | single MDX file        |

The style guide (`docs/_STYLE_GUIDE.md`) further refines explanation and
reference into sub-types — but **only the prose template differs**, not the
filename:

- Explanation sub-types: Index/Landing, Concept, Feature, Philosophy, FAQ
  (the FAQ sub-type does get a `*-faq.md` filename suffix; the others
  rely on the doc's content/structure to signal type)
- Reference sub-types: Index/Landing, Catalog, Deep-Dive, Configuration,
  Glossary, Comprehensive

**No "research" / "ideation" / "adopted" / "archival" tier exists in the
docs.** All of `docs/` is "adopted, ready-to-ship" reference material.
"Research" appears only inside the BMAD framework as a *workflow type*
(`bmad-domain-research`, `bmad-market-research`, `bmad-technical-research`)
that produces user-project artifacts — never as a directory in BMAD's own
docs.

For deprecation: BMAD uses `removals.txt` (a plain-text registry of
removed/renamed skill IDs) rather than an `archive/` directory:

```
# Removed agents (v6.2.0 - v6.2.2)
bmad-agent-sm
bmad-agent-qa
...

# Pre-v6.2.0 wrapper skills (module-prefixed naming, dropped in v6.2.0).
bmad-agent-bmm-analyst
bmad-agent-bmm-architect
...
```

## Lifecycle markers

**Frontmatter** (Starlight/Astro flavored YAML) is the only lifecycle-adjacent
metadata in docs:

```yaml
---
title: 'How to Upgrade to v6'
description: Migrate from BMad v4 to v6
sidebar:
  order: 4
---
```

Fields seen across the docs corpus: `title`, `description`, `sidebar.order`.
**There is no `status:`, `draft:`, `deprecated:`, or `version:` frontmatter
field.** Status is binary — if it's in `main`, it's published.

Lifecycle is signalled by other mechanisms:

| Mechanism                 | What it tracks                              |
| ------------------------- | ------------------------------------------- |
| `CHANGELOG.md`            | Per-release feature/fix/breaking entries with semver headers (`## v6.6.0 - 2026-04-28`) |
| Roadmap admonition in `index.md` | "🚀 V6 is Here and We're Just Getting Started!" — current major version |
| `roadmap.mdx`             | "In Progress" / future cards                |
| `removals.txt`            | Deprecation/rename registry — replaces an `/archive/` directory |
| Trunk-based git           | Every push to `main` auto-publishes to `npm` `next` tag; weekly cuts to `latest` (per CONTRIBUTING.md) |
| Workflow output frontmatter | `stepsCompleted: []`, `inputDocuments: []`, `workflowType: 'prd'` — runtime state, not doc lifecycle |

Locale parity: every translated dir (`cs/`, `fr/`, `vi-vn/`, `zh-cn/`) mirrors
the English filenames exactly. There is no "translation status" marker —
either the file exists in that locale or it doesn't. The CHANGELOG occasionally
notes which locale gained which translation in which release.

## Well-named patterns (with reasoning)

1. **Diátaxis directories as taxonomy.** `tutorials/`, `how-to/`,
   `explanation/`, `reference/` is enough to tell a reader what kind of
   doc they're about to read before they open it. The convention is named
   in the style guide and reinforced by the sidebar config. Reasoning: the
   *intent* of a doc rarely changes after authoring; the directory captures
   that durably and is grep-friendly.

2. **kebab-case + filename = title.** Removes the "what should I name this?"
   decision. If the slug doesn't make sense as a title, the doc probably
   doesn't have a clear focus yet. Reasoning: filename, URL, and prose
   title are kept in lockstep, so links remain stable and predictable.

3. **Numbered phase dirs (`1-analysis`, `2-plan-workflows`, ...).**
   Reading order is encoded in the path. Reasoning: when execution order
   matters and won't change, embedding it in the path beats relying on a
   sidebar config that can drift.

4. **Numbered step files with letter sub-suffixes (`step-02-discovery.md`,
   `step-02b-vision.md`, `step-02c-executive-summary.md`).** Lexical sort
   = execution order; letter suffix lets you insert a new step between
   existing ones without renumbering downstream. Reasoning: inflexible
   pure-numeric ordering forces churn-y renames; letter slots absorb
   future inserts.

5. **`SKILL.md` (uppercase) as the entrypoint.** Visually distinct from
   neighbouring lowercase files; sorts to the top in plain `ls`.
   Reasoning: humans and tooling can both find the entrypoint without
   guessing. The skill-validator deterministically requires this exact
   case (rule SKILL-01).

6. **`_STYLE_GUIDE.md` underscore prefix.** Sorts to the top, signals
   meta/internal. Reasoning: distinguishes "rules about the docs"
   from "the docs themselves" without inventing a parallel directory.

7. **Module-prefixed skill IDs (`bmad-*`).** All BMAD-shipped skills
   share the prefix; community modules are encouraged to use their own
   prefix. Reasoning: avoids collisions when multiple modules install
   into one project, and makes "show me all BMAD skills" a single grep.

8. **Suffix conventions for sub-types:** `*-faq.md` and `why-*-matters.md`
   are recurring enough to read as a convention even though only a small
   number of files use each. Reasoning: encodes intent in the filename
   when the directory alone isn't specific enough.

9. **Programmatic enforcement (`tools/validate-skills.js`,
   `skill-validator.md`).** A deterministic first-pass + an LLM-based
   inference pass with a published rule catalog (SKILL-01..07, WF-01..03,
   PATH-01..05, STEP-01..07, SEQ-01..02, REF-01..03). Reasoning: codified
   conventions are checked, not just hoped-for.

## Awkward patterns (with reasoning)

1. **Filename collision across directories: `how-to/project-context.md` vs
   `explanation/project-context.md`.** Same slug, two intents. Diátaxis
   permits this — same topic, different framings — but searches surface
   both, link-by-name is ambiguous, and tab titles in the rendered site
   collide. Cost: readers and tooling need full paths to disambiguate.

2. **Skill phase dirs mix order with semantics: `1-analysis`,
   `2-plan-workflows`, `3-solutioning`, `4-implementation`.** The number
   is the order; the word is the meaning. If a phase is renamed, the
   number stays — but cross-references that say "phase 2" instead of
   "plan-workflows" lose meaning silently. Trade-off taken: ordering
   benefits outweigh the dual-axis cost for a small fixed set of phases.

3. **Inconsistent depth under phase dirs.** Inside `1-analysis/`, most
   skills sit directly at `1-analysis/<skill>/`, but research-flavoured
   skills are nested at `1-analysis/research/<skill>/` (a one-off
   intermediate folder). The hierarchy isn't `phase → topic → skill`
   universally; it's `phase → skill` with a single sub-grouping
   exception. Cost: tools that walk this tree need special-casing.

4. **Locale-tag inconsistency.** `cs/`, `fr/` (2-letter ISO 639-1) versus
   `vi-vn/`, `zh-cn/` (BCP-47-style with region). Both work in
   Starlight, but mixing widths makes it easy to typo (`zh/` vs
   `zh-cn/`) and harder to script over.

5. **README locale convention diverges from docs locale convention.**
   `README_CN.md`, `README_VN.md` (suffix on the file, only two
   languages) versus `docs/zh-cn/`, `docs/vi-vn/`, `docs/cs/`, `docs/fr/`
   (locale dirs, four languages). Two different ideas of "translated
   content."

6. **`.mdx` for one file (`roadmap.mdx`) and `.md` for all others.**
   The extension hints at "this file uses JSX components." Reasonable —
   but readers who clone the repo and `cat` the file see raw component
   syntax, and `.md`-only renderers (some search indexers) may not
   handle it.

7. **Letter-suffix step-sub-numbering hits a soft cap.** `step-02b`,
   `step-02c` works fine; if a refactor needs to insert *between* `02b`
   and `02c`, the only options are renaming the rest, using `step-02bb`
   (ugly), or changing the parent step's number. The system tolerates
   churn-free expansion but not churn-free re-ordering.

8. **`AGENTS.md` at repo root looks like another vanilla doc.** It's the
   cross-tool standard for agent-tool instructions, but a reader who
   doesn't know the standard won't see a difference between `AGENTS.md`,
   `CONTRIBUTING.md`, and `SECURITY.md`. The convention's payload is
   external knowledge.

9. **`steps-c/` directory name is opaque.** The trailing `-c` apparently
   marks "customizable" (companion to `customize.toml`), but nothing in
   the directory itself explains the suffix. A `steps-customizable/`
   or commented `customize.toml` reference would explain itself.

## Stated rationale

Direct quotes from BMAD's own docs, paired with what the project says
they're optimizing for:

**On the Diátaxis adoption** (`docs/_STYLE_GUIDE.md`):
> This project adheres to the Google Developer Documentation Style Guide
> and uses Diataxis to structure content. Only project-specific conventions
> follow.

**On a few project-specific style choices** (same file, "Project-Specific
Rules" table):

| Rule                             | Reason given                          |
| -------------------------------- | ------------------------------------- |
| No horizontal rules (`---`)      | Fragments reading flow                |
| No `####` headers                | Use bold text or admonitions instead  |
| No "Related" or "Next:" sections | Sidebar handles navigation            |
| No deeply nested lists           | Break into sections instead           |

The style guide is a *short* document focused on the rules themselves,
with reasons captured as one-liners — terse, enforced by review.

**On trunk-based release flow** (`CONTRIBUTING.md`):
> Submit PRs to the `main` branch. We use trunk-based development. Every
> push to `main` auto-publishes to `npm` under the `next` tag. Stable
> releases are cut ~weekly to the `latest` tag.

This explains why doc lifecycle markers are minimal: the branch model is
the lifecycle. Files in `main` are published; nothing else exists in tree.

**On the deprecation registry** (`removals.txt`):
> Pre-v6.2.0 wrapper skills (module-prefixed naming, dropped in v6.2.0).
> Users upgrading from v6.0.x / v6.1.x had these installed and the cleanup
> never knew to remove them; they remained alongside the new self-contained
> skills causing duplicates and broken-file errors. See issue #2309.

A history of why each entry was added — the registry is itself documented.

**On the step-file architecture** (`SKILL.md` for `bmad-create-prd`):
> ### Core Principles
> - **Micro-file Design**: Each step is a self-contained instruction file
> - **Just-In-Time Loading**: Only the current step file is in memory —
>   never load future step files until told to do so
> - **Sequential Enforcement**: Sequence within the step files must be
>   completed in order, no skipping or optimization allowed
> - **State Tracking**: Document progress in output file frontmatter using
>   `stepsCompleted` array

This explains *why* steps live in separate files with numeric prefixes:
the numbering is part of the load-order contract, and isolating each step
reduces context cost.

**On programmatic enforcement** (`tools/skill-validator.md`):
> Run the deterministic first pass (see above) and note which rules
> passed... Apply every rule in the catalog below to every applicable
> file, **skipping rules that passed the deterministic first pass**.

The validator is structured as deterministic + inference passes, and the
rule catalog (SKILL-*, WF-*, PATH-*, STEP-*, SEQ-*, REF-*) is explicit.
Conventions are policed, not aspirational.

## Notes for the synthesis bead

Things worth surfacing when gc-toolkit decides its own conventions:

1. **BMAD has *no* research / ideation / adopted / archival tier in its
   docs.** Every doc in `docs/` is "adopted." This is informative as a
   null result: a mature, opinionated docs project can ship fine without
   that tier — research lives in PRs, issues, branches, and commit
   messages, and deprecation lives in a registry file. If gc-toolkit
   wants those tiers, the choice can't be justified by "BMAD does it";
   it has to be justified by gc-toolkit's own workflow.

2. **Directory = type, filename = topic.** BMAD's strongest move is
   making the directory the durable carrier of doc-type. Filenames
   stay short and topic-focused. Sub-types are encoded only when needed
   (`*-faq.md`, `why-*-matters.md`). If gc-toolkit follows this model, a
   `docs/research/`, `docs/ideation/`, `docs/adopted/` (or similar) split
   would be the BMAD-aligned shape — *not* prefix tags on filenames.

3. **A "single status" docs project is a real option.** BMAD only ships
   adopted docs. Research/ideation can live elsewhere (issues, beads,
   long-lived branches) and only enter `docs/` when stable. Trade-off:
   you lose the breadcrumb trail of how an idea matured; you gain a
   user-facing tree that's never confusing about what's authoritative.

4. **Worth borrowing literally**:
   - **`_STYLE_GUIDE.md` underscore convention** for meta-docs that
     describe the docs themselves.
   - **Numbered + letter-suffixed prefix** for any sequence-bearing
     docs (ADR drafts, migration steps, multi-stage proposals).
   - **`CHANGELOG.md` with semver-style headers** as the lifecycle
     ledger for any docs surface that has releases.
   - **Programmatic enforcement of conventions** — if gc-toolkit's
     conventions matter, building a small validator (the way
     `validate-skills.js` does) prevents drift far better than a prose
     style guide alone.
   - **`removals.txt` as a deprecation registry**, in lieu of (or
     alongside) an `archive/` directory. Easier to grep, harder to
     forget.

5. **Worth examining before borrowing**:
   - **Frontmatter minimalism** (only `title`, `description`, `sidebar.order`).
     gc-toolkit's needs may be richer — case studies want a "principle
     this illustrates" pointer; research notes might want a "studied at"
     date. Decide what frontmatter fields exist *before* writing many docs.
   - **Doc-type proliferation**: BMAD's style guide formally enumerates
     5 explanation sub-types and 6 reference sub-types but only the FAQ
     subtype gets a filename marker. Either commit to filename suffixes
     for every sub-type or accept that the filename can't fully classify
     the doc.

6. **Watch out for**:
   - **Cross-directory filename collisions** (`project-context.md` in
     two dirs). Either pick filenames that are globally unique inside
     `docs/`, or commit to "path is part of the identity" and accept
     that grep / link-by-name is ambiguous.
   - **Mixing two locale conventions** (suffix on README, dir for
     full docs). Pick one.

7. **Concrete-but-speculative pattern to consider**: gc-toolkit could
   pair (a) a directory-driven doc-type taxonomy à la BMAD with (b) a
   *single* explicit `status:` frontmatter field where doc-state actually
   varies (`draft | proposed | adopted | superseded`). BMAD avoids `status:`
   because their answer is always "adopted." gc-toolkit's answer probably
   isn't, given it explicitly wants research/ideation tiers.
