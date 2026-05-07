# gc-toolkit document spec

> **Status:** proposal. Not yet adopted. Adoption is the operator closing
> the parent `tk-yiwfz` with an explicit "yes, this default is adopted"
> decision. Until then this doc inventories options and recommends — it
> does not bind future authors.
>
> **Bead:** `tk-yiwfz.4` (this synthesis). **Inputs:**
> `tk-yiwfz.{1,2,3,5,6,7}` (six platform surveys under
> `docs/research/naming-conventions/`).
> **Surveyed at:** 2026-05-06. **Author:** polecat `gc-toolkit.furiosa`.

## Why this lives at `docs/principles/document-spec.md`

The bead's working default was `docs/principles/document-spec.md`. The
synthesis settles on that location for three reasons that the spec
itself argues for:

1. **`docs/<topic>.md` is gc-toolkit's existing pattern** for project-wide
   reference content (`gas-city-reference.md`, `gas-city-pack-v2.md`,
   `gascity-local-patching.md`, `roadmap.md`). A new spec describing how
   gc-toolkit's docs work belongs in that same flat tier — central,
   refreshed in place, one of its kind.
2. **`principles/` is a sub-tier**, not a separate root. The principle of
   *what counts as a doc-type* is itself a principle worth filing under
   `docs/principles/`. Future principle docs (style guide, naming rules,
   review discipline) sit alongside this one and don't pollute the flat
   reference tier.
3. **Spec Kit's `.specify/memory/constitution.md` argues for a single
   principles file**; BMAD's `_STYLE_GUIDE.md` argues for a single style
   doc. Both reference projects converge on "principles live in one
   well-known location, named by intent." `docs/principles/document-spec.md`
   is gc-toolkit's analogue, with the directory open for sibling principle
   docs.

The flat option (`docs/document-spec.md`) was rejected because it would
force the next principle doc (whenever it's filed) to either move this
file *or* create the `principles/` directory anyway. Doing it now avoids
the rename cost.

## Scope

**In scope** (per bead acceptance criteria):

- Inventory matrix preserving provenance from all six surveys.
- gc-toolkit doc-type taxonomy with crisp definitions.
- Default file locations per type, with rationale.
- Central vs local split.
- Cross-doc reference options (with bead-IDs surfaced as a candidate, not
  pre-decided).
- Migration notes — which existing gc-toolkit docs would move.
- Open questions for operator review.

**Out of scope** (per bead — these are downstream decisions):

- *Agent-role ownership* (who writes/updates each doc-type).
- *Workflow / lifecycle process* (how a local doc flows back into a
  central doc).
- *Bead-ID attachment policy* (which doc types carry bead-IDs in
  frontmatter, which don't). This spec inventories the options; final
  policy is downstream.

## How to read the inventory matrix

Every row preserves the upstream survey's provenance: each cell points
back to the survey file (under `docs/research/naming-conventions/`) where
the fact was captured, and surveys themselves cite the upstream commit
SHA + path that they read. Cell entries are intentionally short — the
detail lives in the surveys, not here.

Six platform surveys feed the matrix:

| Survey | Source file | Upstream surveyed at |
|---|---|---|
| BMAD (naming) | `docs/research/naming-conventions/bmad-method.md` | `github.com/bmad-code-org/BMAD-METHOD` ~v6.6.0 era |
| BMAD (templates) | `docs/research/naming-conventions/bmad-method-templates.md` | `github.com/bmad-code-org/BMAD-METHOD` @ `e36f219` (2026-05-01) |
| Superpowers | `docs/research/naming-conventions/superpowers.md` | `github.com/obra/superpowers` v5.0.7 (2026-03-31) |
| Gas Town | `docs/research/naming-conventions/gastown.md` | `rigs/gascity/examples/gastown/` + `rigs/gc-toolkit/docs/` (in-tree) |
| Spec Kit | `docs/research/naming-conventions/spec-kit.md` | `github.com/github/spec-kit` @ `0f26551` (2026-05-05) |
| Kiro | `docs/research/naming-conventions/kiro.md` | `kiro.dev/docs/` + community templates (2026-05-05) |

Throughout the matrix, cells point to one of the six surveys for the
authoritative quotation. Where a row aggregates multiple surveys, the
provenance column lists each contributing survey.

## Inventory matrix — doc-types observed across the six sources

| Doc-type | Producer (platform mechanism) | Default location | Central/Local | Cross-doc reference scheme | Lifecycle marker | Provenance |
|---|---|---|---|---|---|---|
| **Reference manual (canonical)** | Hand-authored doc; rolled forward in place | BMAD: `docs/reference/<topic>.md` (Diátaxis quadrant). Gas Town: `<rig>/docs/<topic>.md` flat. Superpowers: `docs/<topic>.md` plus `docs/<harness>/<topic>.md`. Kiro/Spec Kit: no equivalent in the toolkit's own tree (their docs are user-edit context). | Central | Inter-doc markdown links; section anchors; sometimes glob discovery (BMAD) | Header date stamp ("Current as of v1.0.1") + body status prose | bmad-method.md (Diátaxis), gastown.md (line 87+), superpowers.md (`docs/` layout) |
| **Versioned reference (release-bound)** | Hand-authored snapshot tied to a version; new file per major | Gas Town: `<rig>/docs/<topic>-v<N>.md` (e.g., `gas-city-pack-v2.md`). Distinct from rolled-forward references. | Central | Body opens with release tag; older versions remain alongside | Filename version suffix; body opens with release date | gastown.md ("Filename version suffixes") |
| **Roadmap (living)** | Hand-authored ongoing plan | BMAD: `docs/roadmap.mdx` (single MDX). Gas Town: `<rig>/docs/roadmap.md` and/or top-level `SDK-ROADMAP.md`. Superpowers: not present (release-notes carries forward-looking content). | Central, singular | Markdown links + section anchors | None on the file; entries reflect status via prose | bmad-method.md, gastown.md (FUTURE.md / SDK-ROADMAP.md) |
| **Style guide / conventions** | Hand-authored project rules | BMAD: `docs/_STYLE_GUIDE.md` (underscore prefix sorts to top). Spec Kit: `.specify/memory/constitution.md` (single project-wide). Kiro: foundational steering trio (`product.md` / `tech.md` / `structure.md`). | Central, singular per concern | Articles cited by number (Spec Kit `Article VII`); sections by anchor | Spec Kit: trailing `**Version**: X.Y.Z` semver line; others: none | bmad-method.md, spec-kit.md, kiro.md (Steering) |
| **Brief / PR-FAQ** | Workflow command (BMAD `bmad-product-brief`, `bmad-prfaq`) | BMAD: `{planning_artifacts}/product-brief-{project_name}.md` (Class B project-name-keyed). | Central, project-name-keyed | Glob discovery (`*brief*.md`) by downstream skills; runtime `inputDocuments` frontmatter | None (`stepsCompleted` runtime array, not lifecycle) | bmad-method-templates.md (Class B) |
| **PRD (product requirements)** | BMAD `bmad-create-prd`. Spec Kit `/speckit.specify` (renamed: `spec.md`). Kiro: `requirements.md`. | BMAD: `{planning_artifacts}/prd.md` (Class A singleton). Spec Kit: `specs/<NNN>-<short-name>/spec.md`. Kiro: `.kiro/specs/<feature>/requirements.md`. | Spec Kit/Kiro: **Local** (per-feature). BMAD: **Central, singular**. | Spec Kit: `**Spec**: [link]` markdown link. Kiro: integer references from `tasks.md` (`_Requirements: 1.2_`). BMAD: glob discovery. | BMAD: `stepsCompleted` runtime. Spec Kit: `**Status**: Draft` body field. Kiro: presence of next file. | bmad-method-templates.md, spec-kit.md, kiro.md |
| **Architecture / design doc** | BMAD `bmad-create-architecture`. Gas Town `docs/design/<topic>.md`. Spec Kit: `plan.md` carries Technical Context + Project Structure; no separate architecture doc per feature. Kiro: `.kiro/specs/<feature>/design.md`. | BMAD: `{planning_artifacts}/architecture.md` (Class A). Gas Town: `<rig>/docs/design/<topic>.md`. Kiro: `.kiro/specs/<feature>/design.md`. | BMAD: **Central**. Gas Town: **Central** proposals (per concern, multiple). Kiro: **Local**. | Gas Town: prose `**Status:**` line; markdown links + bead-ID refs in body. BMAD: glob discovery. Kiro: runtime checkbox state in sibling `tasks.md`. | Gas Town: prose status; BMAD: stepsCompleted; Kiro: file presence | gastown.md (`docs/design/`), bmad-method-templates.md, kiro.md |
| **Plan (implementation)** | Superpowers `docs/<scope>/plans/`. Spec Kit `/speckit.plan`. | Superpowers: `docs/<scope>/plans/YYYY-MM-DD-<slug>.md`. Spec Kit: `specs/<feature>/plan.md`. | Superpowers: **Local**, dated. Spec Kit: **Local**, per feature. | Superpowers: paired `-design` spec by shared date+slug. Spec Kit: markdown link to `spec.md`; phase-gated references to constitution articles. | Superpowers: filename date is the only marker; some plans carry inline `**Status:**` (inconsistent). Spec Kit: phase progression by file presence. | superpowers.md (paired plan/spec), spec-kit.md |
| **Spec (paired with plan)** | Superpowers `docs/<scope>/specs/`. (Distinct from Spec Kit's `spec.md`.) | Superpowers: `docs/<scope>/specs/YYYY-MM-DD-<slug>-design.md` (paired by shared date+slug). | **Local**, dated | Filename pairing (same date+slug across `plans/` and `specs/`) | Date prefix + `-design` suffix | superpowers.md ("paired plan + spec") |
| **ADR / architecture decision record** | None of the six ship a per-decision ADR template. BMAD's `architecture.md` is project-wide, not per-decision. Superpowers folds decisions into `RELEASE-NOTES.md` with measured rationale. | (No native location across surveys.) | — | — | — | bmad-method-templates.md ("not an ADR template"), superpowers.md ("RELEASE-NOTES.md carries the architecture-decision-record load") |
| **Tasks / implementation plan** | BMAD `bmad-create-epics-and-stories` (epics+stories combined) + per-story files. Spec Kit `/speckit.tasks`. Kiro `tasks.md`. | BMAD: `{planning_artifacts}/epics.md` (project-wide singleton) + `{implementation_artifacts}/{epic_num}-{story_num}-{slug}.md` per story. Spec Kit/Kiro: `specs/<feature>/tasks.md`. | BMAD: epics central, stories local. Spec Kit/Kiro: **Local** per-feature. | BMAD: `Epic {N}.Story {M}` numeric anchors join `epics.md` ↔ story files ↔ `sprint-status.yaml`. Spec Kit: `T###` task IDs + `[US1]` story labels + inline file paths. Kiro: `_Requirements: 1.2_` italic trailing line. | All three: **checkbox state IS the lifecycle** — `- [ ]` pending, `- [X]` complete. | bmad-method-templates.md, spec-kit.md, kiro.md (convergent finding) |
| **Research / investigation note** | BMAD: `bmad-{domain,market,technical}-research`. Gas Town: `docs/escalation/research/r<n>-<topic>.md` and `v<n>-<topic>.md` (in-flight branch only). Spec Kit: `research.md` per feature. | BMAD: `{planning_artifacts}/research/{type}-{slug}-research-{date}.md` (Class C dated). Gas Town: `docs/escalation/research/r<n>-<topic>.md` (numeric prefix). Spec Kit: `specs/<feature>/research.md` (single per feature). | **Local**, accumulating | None on file; consumed by downstream skills via paths | None on file | bmad-method-templates.md (Class C), gastown.md, spec-kit.md |
| **Skill / capability package** | BMAD `src/.../bmad-<name>/`. Superpowers `skills/<name>/`. Kiro `.kiro/skills/<name>/`. | All three: `<root>/skills/<name>/SKILL.md` (uppercase entrypoint mandated by open Agent Skills standard). | **Central**, reusable | Frontmatter `name` + `description: Use when …`; cross-skill refs by name with explicit requirement markers (Superpowers explicitly forbids `@`-imports between skills). | None on file; presence in `main` = adopted | bmad-method.md, superpowers.md, kiro.md (convergent: open standard) |
| **Slash-command / workflow command** | Spec Kit `templates/commands/<verb>.md`. Superpowers `commands/<verb>.md`. Gas Town: `<pack>/commands/<name>/run.sh` + `help.md`. | Spec Kit: `.specify/templates/commands/speckit.<verb>.md` (namespaced). Superpowers: `commands/<verb>.md`. Gas Town: `<pack>/commands/<name>/`. | **Central** | Spec Kit: `handoffs:` frontmatter declaring next-command names; `description:` for picker UI. | None on file | spec-kit.md (handoffs), superpowers.md, gastown.md |
| **Steering / persistent agent context** | Kiro-specific: `.kiro/steering/<name>.md` with `inclusion:` frontmatter (`always`/`fileMatch`/`manual`/`auto`). | Kiro: `.kiro/steering/` (workspace) and `~/.kiro/steering/` (global). | **Central** | `#[[file:<path>]]` live-file embed; `#<file-name>` chat reference; chat slash-command activation. | None on file; `inclusion:` mode is informally used as a soft "in-flight → adopted" signal | kiro.md (full Steering deep-dive) |
| **Cross-tool agent context (`AGENTS.md`)** | External standard adopted by Superpowers (as symlink), Kiro (as steering variant), Spec Kit (per-integration target file). | Workspace root or `.kiro/steering/AGENTS.md`. | **Central**, singular | Body content is the contract; some integrations inject managed sections delimited by markers (Spec Kit's `<!-- SPECKIT START --> … <!-- SPECKIT END -->`). | None | superpowers.md, kiro.md, spec-kit.md |
| **Constitution / principles (versioned)** | Spec Kit `/speckit.constitution`. | Spec Kit: `.specify/memory/constitution.md`. | **Central**, singular | Articles by Roman numeral + thematic name (`Article VII: Simplicity Gate`); plan template references gates by article number. | **Trailing `**Version**: X.Y.Z \| **Ratified**: YYYY-MM-DD \| **Last Amended**: YYYY-MM-DD` semver line.** Sync-impact-report HTML comment at top after each amendment. | spec-kit.md (only doc-type with built-in semver) |
| **Hooks / automation config** | Kiro `.kiro/hooks/<name>.kiro.hook` (JSON). Spec Kit `.specify/extensions.yml` (YAML, declares `before_<command>`/`after_<command>`). Gas Town: hook scripts in `<pack>/hooks/` (legacy). | Kiro: `.kiro/hooks/`. Spec Kit: `.specify/extensions.yml` (uniform single file). | **Central** | Discriminated unions: Kiro `{when: {type, …}, then: {type, …}}`; Spec Kit `before_<command>: [...]`. | JSON `enabled: true/false` field | kiro.md, spec-kit.md |
| **Changelog / release notes** | BMAD `CHANGELOG.md` (semver-style headers). Superpowers `RELEASE-NOTES.md` (uppercase + dash). Spec Kit's constitution carries its own micro-changelog as the trailing version line. | Repo root: `CHANGELOG.md` or `RELEASE-NOTES.md`. | **Central**, append-only | Semver section headers (`## v6.6.0 - 2026-04-28`) | Format itself; new releases prepended | bmad-method.md, superpowers.md |
| **Deprecation registry** | BMAD `removals.txt` (plain text). Superpowers/Kiro/Spec Kit/Gas Town: none — deletion + git history is the trail. | Repo root: `removals.txt`. | **Central**, append-only | Plain-text list with rationale comments per entry | None | bmad-method.md (only project with this) |
| **Brainstorming / ideation** | BMAD `bmad-brainstorming`. Gas Town `docs/escalation/ideation.md`. | BMAD: `{output_folder}/brainstorming/brainstorming-session-{date}-{time}.md` (date+time keyed). Gas Town: `docs/escalation/ideation.md` (one per topic, single file per scope). | **Local**, dated or per-scope | Path | None | bmad-method-templates.md, gastown.md (escalation branch) |
| **Spec quality checklist** | Spec Kit `/speckit.checklist` and `/speckit.specify` validation. | Spec Kit: `specs/<feature>/checklists/requirements.md` (auto-generated, fixed name) + `<domain>.md` (per `/speckit.checklist` invocation). | **Local**, per feature | `[Spec §FR-001]` section pointers; `CHK###` IDs globally incrementing within file | Checkbox state | spec-kit.md ("unit tests for English") |
| **Powers / tool bundles** | Kiro-specific: `POWER.md` entrypoint + optional `mcp.json` + optional steering/hook files. | Kiro: filesystem location not pinned; installer registers MCP servers into `~/.kiro/settings/mcp.json` "under the Powers section." | **Central**, reusable | None native | None | kiro.md ("filesystem location not pinned") |

### Convergent vs divergent findings (summary)

**Convergent across all sources (worth adopting as defaults without
deliberation):**

- **Path is the doc-type signal.** Every source uses directory placement
  as the primary classifier; filename suffixes/prefixes are reserved for
  sub-types or sequencing inside a directory. (bmad-method.md,
  superpowers.md, gastown.md, kiro.md, spec-kit.md)
- **Markdown + lowercase-kebab-case for content names.** Universal across
  the five non-Gas-Town sources; Gas Town also uses kebab for content
  with `SCREAMING-KEBAB.md` reserved for top-level repo-recognised files.
- **`UPPERCASE.md` for entrypoints inherited from open standards.**
  `SKILL.md`, `POWER.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`. Visual
  contrast with surrounding lowercase content; sorts to top in `ls`. The
  exact case is mandated by external specifications (Agent Skills,
  cross-tool AGENTS).
- **Path is the identifier — no UUIDs, no `id:` frontmatter.** All five
  reference projects converge here. None has a separate stable ID system
  for docs. (Note: this is the axis where gc-toolkit *will* depart — see
  cross-doc references below.)
- **No archive directory; deletion + git is the retirement path.** BMAD,
  Superpowers, Kiro, Spec Kit all converge. Only BMAD adds a plain-text
  `removals.txt` registry — a lightweight, grep-friendly addition rather
  than an archive directory.
- **Single-tier "in main = adopted."** None of the five toolkits ship a
  `drafts/` or `proposed/` directory in their own user-facing docs. BMAD
  is explicit: every doc in `docs/` is "ready-to-ship reference material."
  *(gc-toolkit's existing `docs/research/` and the in-flight
  `docs/escalation/` are gc-toolkit-specific departures from this.)*
- **Checkbox state IS the per-task lifecycle** when a doc lists work
  items. Spec Kit, Kiro, BMAD-stories all converge. No separate per-item
  status field; `- [ ]` / `- [X]` doubles as human display and machine
  read.
- **YAML frontmatter (when used) is functional, not lifecycle.** When
  there's frontmatter, it carries author/agent metadata (`name`,
  `description`, `inclusion`, `handoffs`), not status enums. Status (when
  it exists at all) is body prose or filename.

**Divergent (decisions to make, surfaced as open questions below):**

- **Hidden `.<tool>/` config dir vs visible `docs/`.** Spec Kit
  (`.specify/`) and Kiro (`.kiro/`) put toolkit-managed state in a hidden
  dir, with per-feature work in a visible sibling (`specs/`). BMAD,
  Superpowers, and Gas Town keep everything in visible directories.
- **Per-feature doc count.** Kiro: 3 fixed-name files. Spec Kit: 6+ fixed
  names. BMAD: many doc-types per phase across `planning_artifacts/` and
  `implementation_artifacts/`. Superpowers: paired plan + spec. There is
  no convergence on density.
- **Constitution as one file vs principles as a directory.** Spec Kit
  collapses all principles into one versioned file; BMAD splits style
  rules across `_STYLE_GUIDE.md` plus other meta-files; Kiro uses its
  foundational steering trio.
- **Filename versioning style.** Gas Town: `-v<N>` filename suffix on
  release-frozen references. Superpowers: `YYYY-MM-DD-<slug>` date
  prefix on plans. Spec Kit: trailing `**Version**: X.Y.Z` semver line in
  body (constitution only). BMAD: rolled-forward `CHANGELOG.md`
  alongside non-versioned filenames.
- **Frontmatter shape.** Minimal: BMAD (`title`, `description`,
  `sidebar.order`); Superpowers (`name`, `description`). Rich: Spec Kit
  (`description`, `handoffs[]`, `scripts.{sh,ps}`, `tools[]`); Kiro
  (`inclusion`, `fileMatchPattern`, `name`, `description`).
- **Local-work scoping.** Spec Kit uses `<NNN>-<short-name>` ordinal
  prefix; Kiro uses bare `<feature-name>`; Superpowers uses
  `YYYY-MM-DD-<slug>`; BMAD uses `{epic_num}-{story_num}-{slug}` for
  stories.

The synthesis recommends defaults below that take the convergent
findings as baseline and pick a position on each divergent axis with
rationale.

## gc-toolkit doc-type taxonomy

Eleven doc-types are proposed, grouped by tier. Definitions are crisp
enough to assign a new doc to a type at authoring time; rationale and
location follow in the next section.

**Central tier — project-wide, refreshed in place. One per concern.**

1. **Reference manual** — A user-facing manual describing a piece of the
   pack (e.g., gc binary surface, pack/city structure, agent semantics).
   Rolled forward as the pack evolves; carries a "current as of" stamp
   in the body.
   *Examples (existing):* `gas-city-reference.md`, `gascity-local-patching.md`.
   *Sub-flavour:* the **agent brief** — the subset of reference manuals
   loaded routinely into agent prompts as context. Defined in
   `principles/agent-brief.md`.

2. **Versioned reference** — A snapshot of a reference tied to a specific
   release of the underlying surface. Filed when the surface ships and
   doesn't roll forward; old versions accumulate alongside the rolled
   reference.
   *Examples (existing):* `gas-city-pack-v2.md`.

3. **Roadmap (living)** — A single project-wide planning doc whose
   purpose is "open this and find where we are." Updated in place,
   never archived.
   *Example (existing):* `roadmap.md`.

4. **Principle** — A durable convention or rule about how gc-toolkit
   works (style, naming, document-spec-itself, code organisation).
   Rolled forward in place; sibling principles live alongside.
   *Examples (proposed):* this doc (`document-spec.md`), future
   `coding-style.md`, `naming.md`, `review-discipline.md`.

5. **Constitution / charter (optional, deferred)** — If gc-toolkit ever
   wants a single versioned principles file in the Spec Kit sense, it
   would live here. Open question — see below.

**Local tier — single piece of work, write-once and evolve in place
until the work is done. Many per project.**

6. **Design / proposal** — A concrete proposal to change something. Body
   carries `**Status:**` prose ("draft", "approved design", "implemented",
   "rejected") in the gc-toolkit current style. Survives after adoption
   as the historical record of the decision.
   *Examples (existing):* `docs/design/consult-surfacing.md`,
   `docs/design/consult-session-{feasibility,v2-impl}.md`.

7. **Research / investigation** — A survey, spike, or comparative
   investigation that informs a downstream decision. Write-once: the
   facts at the time-of-survey are pinned by the doc; later changes file
   a new doc rather than rewriting the old.
   *Examples (existing):* `docs/research/naming-conventions/*.md` (this
   bead's six inputs), `docs/research/pack-architecture/spike-*.md`.

8. **Feature work bundle** — A directory grouping the docs that drive a
   specific named effort (the "escalation" workstream is the live
   example; "document-spec adoption" is another). Holds process docs,
   research scoped to that feature, and (eventually) the artifacts that
   graduate out to the central tier.
   *Examples:* `docs/escalation/` (in-flight on a feature branch);
   could in future be `docs/<feature>/` for any multi-doc effort.

9. **Plan / spec (paired)** — A planning doc and its companion design
   spec, filed when an effort is large enough to warrant separating
   the "what we're going to do" from "how we're going to do it." Likely
   filed inside a feature work bundle (8) when the effort is large; or
   as siblings in `docs/design/` when standalone. **Distinct from
   "design / proposal" (6)** in that a plan/spec pair carries explicit
   sequencing and tasks; a proposal does not.
   *Examples:* potentially `docs/<feature>/plan.md` +
   `docs/<feature>/spec.md` for any large effort. **Not yet exemplified
   in tree.**

10. **Tasks / checklist** — A markdown checkbox list driving execution.
    Lives inside a feature work bundle or paired with a plan/spec.
    Checkbox state is the lifecycle. **Optional doc-type** — gc-toolkit
    already tracks task state in beads, so a markdown tasks file is
    redundant for routine work; reserved for cases where a human-readable
    task list adds value beyond beads.

11. **Working note (dated)** — A scratchpad-style note pinned to a date,
    kept for audit. Filename carries the date. Rare in current
    gc-toolkit; the existing example
    (`learning_mockup_review-20260430.md` at the gc-toolkit rig root,
    referenced in the Gas Town survey) demonstrates the doc-type but
    not a stable convention. Filing notes per-bead in bead descriptions
    is the gc-toolkit-native alternative; this doc-type exists in the
    taxonomy for the cases beads don't cover.

**Notable absences — doc-types this taxonomy does NOT include:**

- **No per-decision ADR doc-type.** None of the surveyed sources ship
  ADRs as a distinct doc-type — BMAD, Superpowers, and Gas Town all
  fold architecture decisions into either "design proposal" docs (6),
  release notes/changelogs, or principle docs (4). gc-toolkit follows
  suit. If a single architectural decision needs persistent capture,
  it goes in `docs/design/<topic>.md` (proposal) or `docs/principles/<rule>.md`
  (rule), not a separate `docs/adr/` directory.
- **No `skills/` doc-type.** gc-toolkit does not currently ship Agent
  Skills standard packages. If it ever does, the convergent
  `skills/<name>/SKILL.md` shape from BMAD/Superpowers/Kiro is the
  default; until then, the doc-type sits unadopted.
- **No `steering/` doc-type.** Kiro-specific. gc-toolkit's principle
  docs cover the same surface for the convention-shape needs;
  inclusion-mode loading isn't a feature gc-toolkit's harnesses
  currently honour.
- **No `archive/` directory.** Convergent finding across all sources;
  gc-toolkit follows.

## Default file locations per type

For each adopted doc-type, the default path and its rationale.
gc-toolkit ships as a Gas Town pack (it has `pack.toml`, `agents/`,
`commands/`, etc.); its docs live under `docs/` at the rig root.

| # | Doc-type | Default location | Filename style | Rationale |
|---|---|---|---|---|
| 1 | Reference manual | `docs/<topic>.md` (flat) | kebab-case `.md` | Matches existing pattern (`gas-city-reference.md`, `gascity-local-patching.md`). BMAD-aligned: directory carries the type, filename carries the topic. Flat tier keeps `ls docs/` legible. |
| 2 | Versioned reference | `docs/<topic>-v<N>.md` (flat) | kebab + `-v<N>` suffix | Matches existing `gas-city-pack-v2.md`. Gas Town's only convention for release-frozen docs; keeps it. |
| 3 | Roadmap (living) | `docs/roadmap.md` (singleton) | fixed `roadmap.md` | Matches existing. BMAD ships `docs/roadmap.mdx` as a singleton; gc-toolkit follows. |
| 4 | Principle | `docs/principles/<topic>.md` | kebab-case `.md` | New directory (created by this synthesis). Sub-tier of central; multiple principle docs sit alongside. Spec Kit's `constitution.md` is the closest analogue but argues for one-file; BMAD's `_STYLE_GUIDE.md` argues for one file *per concern*. The directory accommodates either: a single `document-spec.md` today, more files later. |
| 5 | Constitution (deferred) | `docs/principles/constitution.md` (if adopted) | fixed `constitution.md` | Open question. If gc-toolkit decides to consolidate principles into one versioned file (Spec Kit pattern), this is its location. Otherwise unused. |
| 6 | Design / proposal | `docs/design/<topic>.md` | kebab-case `.md` | Matches existing `docs/design/`. Body carries `**Status:**` prose line. Multiple design docs accumulate; old proposals stay as the historical record. |
| 7 | Research / investigation | `docs/research/<area>/<topic>.md` | kebab-case `.md`, optional `r<n>-` / `v<n>-` numeric prefix for ordered series | Matches existing `docs/research/naming-conventions/*` and `docs/research/pack-architecture/*`. The `<area>/` sub-directory groups related surveys; keeps the tree shallow. The `r<n>-` / `v<n>-` numeric-prefix convention from the in-flight escalation branch is the recommended discipline for ordered survey series. |
| 8 | Feature work bundle | `docs/<feature>/` | kebab-case directory name | Matches the in-flight `docs/escalation/` pattern. Top-level files in the bundle are process artifacts (`ideation.md`, `marching-orders.md`, `roadmap.md`, `selection-menu.md`); a `<feature>/research/` sub-folder holds research scoped to the feature. |
| 9 | Plan / spec (paired) | Inside a feature bundle: `docs/<feature>/plan.md` + `docs/<feature>/spec.md`. Standalone: `docs/design/<topic>.md` (collapse to design doc). | fixed `plan.md` / `spec.md` | Spec Kit-style fixed-name pair when scoped to a feature; collapses to a single design doc for smaller efforts. **Departure from Superpowers' `YYYY-MM-DD-<slug>.md` date-prefix pattern**: gc-toolkit beads already provide stable timestamping via `created_at`, so date-in-filename is redundant. |
| 10 | Tasks / checklist | Inside a feature bundle or paired: `docs/<feature>/tasks.md`. Standalone: not recommended (use beads). | fixed `tasks.md` | Spec Kit/Kiro convergent pattern: checkbox state IS the lifecycle. Reserved for human-shareable task lists; bead state remains the canonical work tracker for routine work. |
| 11 | Working note (dated) | `docs/notes/<YYYY-MM-DD>-<topic>.md` | `YYYY-MM-DD-<topic>.md` | New optional directory. Borrows Superpowers' date-prefix discipline. Used sparingly: bead descriptions are the preferred home for dated working notes. |

### Repo-root files (not under `docs/`)

By convention, certain files live at the rig root rather than under
`docs/`. This taxonomy adopts the convergent practice:

| File | Convention | Rationale |
|---|---|---|
| `README.md` | Repo entry; existing | GitHub-recognised |
| `LICENSE` | Existing | GitHub-recognised |
| `CHANGELOG.md` (proposed) | semver-style headers per release | BMAD/Superpowers convergent. gc-toolkit doesn't currently ship one; recommend adding when the pack starts cutting versioned releases. |
| `CLAUDE.md` (proposed) | Cross-tool agent context (canonical) | If gc-toolkit ships agent context for users vendoring the pack, this is the canonical location. Currently `CLAUDE.md` files exist *inside* `agents/<name>/` for per-agent prompts; a top-level `CLAUDE.md` would be a separate concern. |
| `AGENTS.md` (proposed) | Symlink to `CLAUDE.md` (Superpowers pattern) | Cross-tool compatibility. Free if `CLAUDE.md` exists. |
| `removals.txt` (deferred) | BMAD-style deprecation registry | Deferred. Adopt if/when gc-toolkit starts removing or renaming agent/command IDs and needs a grep-friendly migration trail. |

`pack.toml` and `city.toml` already carry header comments that act as
their README, per Gas Town convention. Keep this practice.

### Pack-internal directories (not docs)

These exist already and are out of scope for this spec; noted for
completeness:

```
agents/<name>/{agent.toml, prompt.template.md, …}   # Convention dirs
commands/<name>/{run.sh, help.md, …}                # Convention dirs
doctor/<check>/{run.sh, …}                          # Convention dirs
formulas/<name>.toml                                # mol-prefixed formulas
orders/<name>.toml                                  # Order files
template-fragments/<name>.template.md               # Reusable defines
assets/{namepools/, prompts/, scripts/}             # Static assets
```

## Central vs local split — the location pattern that distinguishes them

The synthesis adopts a path-based central/local distinction: **a path
visible to a quick `ls` shows a doc's tier without reading it**.

**Central docs** live at `docs/<topic>.md` (flat) or under a named
sub-directory whose purpose is a concern within the central tier
(`docs/principles/`, `docs/design/`).

- "Central" means: project-wide, refreshed in place, one of its kind
  for that concern. The doc's identity is the path; multiple authors
  edit the same file over time.
- Sub-directories under `docs/` (`design/`, `principles/`) carry a
  **type** and contain multiple sibling docs, each on its own concern.

**Local docs** live under `docs/research/<area>/` (research) or
`docs/<feature>/` (feature work bundles).

- "Local" means: tied to a single piece of work, write-once-and-evolve
  while in flight, kept after completion as the historical record.
- The directory name encodes the scope of the work
  (`docs/research/naming-conventions/`, `docs/escalation/`).
- Inside a local directory, sibling docs follow the doc-type fixed-name
  pattern when paired (`plan.md` + `spec.md` + `tasks.md`), or carry
  topic-specific kebab-case names with optional ordinal prefixes
  (`r1-toyota.md`, `v3-skeptic.md`).

**The decision rule for a new doc:**

> *Is this document refreshed in place over the project's lifetime, or
> is it tied to a specific piece of work?*
>
> - Refreshed-in-place → central tier (`docs/<topic>.md` or
>   `docs/<sub-tier>/<topic>.md`).
> - Tied-to-work → local tier (`docs/<feature>/<topic>.md` or
>   `docs/research/<area>/<topic>.md`).

Equivalent to BMAD's "is there one of these per project, or many?"
rule (bmad-method-templates.md, "Decision rule observable from BMAD's
choices"). A single canonical filename signals central; varying
filenames or directory grouping signals local.

**Naming corollary:** central docs use *topic* names that don't change
when the contents are rewritten (`gas-city-reference.md` stays named
that way as it rolls forward). Local docs use *concern* names that pin
the doc to its origin (`spike-gc-toolkit-as-primary-pack.md` pins to
the spike's question; renaming would obscure the historical record).

**Two-tier vs `.gc/` hidden split — why this proposal does NOT adopt
the Spec Kit/Kiro hidden-dir pattern.** Spec Kit's `.specify/` and
Kiro's `.kiro/` separate "toolkit-managed state" (hidden, machine-edited)
from "human-edited per-feature work" (visible). gc-toolkit already has
a `.gc/` directory for runtime state (worktrees, runtime packs,
session config). Extending `.gc/` to also hold docs would conflate two
distinct uses: machine state vs human-and-agent edit surface. Keeping
docs under `docs/` (visible) and runtime under `.gc/` (hidden) matches
how gc-toolkit already separates these concerns. **gc-toolkit
deliberately departs from Spec Kit/Kiro on this axis.**

## Cross-doc reference scheme — options inventory + recommendation

Six reference mechanisms appear across the surveys; gc-toolkit can
adopt any subset. The synthesis recommends a small kit (3 mechanisms)
that covers gc-toolkit's existing patterns plus the bead-ID anchor
that the parent bead flagged as worth surfacing.

### Options observed across the six surveys

| Mechanism | Used by | Strength | Weakness |
|---|---|---|---|
| **Markdown link to relative path** (`[gas-city-reference](../gas-city-reference.md)`) | Spec Kit (`**Spec**: [link]`), Gas Town (existing design docs), Kiro | Works in any markdown renderer; survives if both files move together | Breaks silently on rename; not greppable as a citation |
| **`[Source: <path>#<section>]` citation** | BMAD (`bmad-create-story/template.md`) | Greppable; visible as a citation in prose; lighter than a full link | Requires the section anchor stays stable |
| **Numbered identifiers within a doc** (`FR-001`, `T###`, `CHK###`, `Article VII`) | Spec Kit, BMAD (Epic.Story), Superpowers (none — uses dates) | Stable, sortable, pronounceable; survives reorder if the IDs are not tied to position | Brittle when the IDs *are* tied to position (Spec Kit's `[US1]` shifts on reorder; Kiro's `_Requirements: 1.2_` shifts on reorder) |
| **Bead-ID anchor** (gc-toolkit-specific: `tk-yiwfz`, `tk-yiwfz.4`) | Used informally already in gc-toolkit design docs (e.g., `consult-surfacing.md` references `tk-uac`) | Stable global IDs; survive file moves; tie a doc to its bead-tracked work history | Requires the reader to know about the beads system; not a self-contained citation |
| **Filename pairing by shared slug + date** (Superpowers `YYYY-MM-DD-<slug>.md` + `YYYY-MM-DD-<slug>-design.md`) | Superpowers | Pairing visible from `ls`; no metadata link to maintain | Two files must rename together; date is redundant when other timestamping exists |
| **Glob discovery** (BMAD: `{planning_artifacts}/*prd*.md`) | BMAD | Tolerates renames and language localisation | Ambiguous when multiple matches exist; needs runtime resolution |
| **Live-file embed** (Kiro `#[[file:<path>]]`) | Kiro Steering | Avoids restating-then-staling; embeds the source-of-truth | Breaks silently on rename; requires harness support |

### Recommended kit for gc-toolkit

Three mechanisms cover the use cases the existing tree exhibits, plus
the bead-ID anchor flagged by the parent bead:

1. **Markdown link to relative path** — for *forward references* between
   docs in the same project. Use `[anchor text](relative/path.md)` or
   `[anchor text](relative/path.md#section)`. Already the prevailing
   gc-toolkit pattern; recommend keeping it.

2. **Bead-ID anchor** — for any doc whose identity is tied to a piece of
   bead-tracked work. Reference the bead inline as a backtick-wrapped
   identifier (`` `tk-yiwfz` ``), with optional descent (`` `tk-yiwfz.4` ``).
   For a complete reference, pair the bead-ID with a one-line description
   of what the bead tracks (matching the `consult-surfacing.md` "Beads:"
   line pattern). The bead-ID is the **stable identity**; the path may
   move but `tk-yiwfz.4` always refers to the same logical work.

   *This is gc-toolkit's principal departure from the surveyed
   reference projects, all of which converge on "path is the
   identifier."* The departure is justified: gc-toolkit has a beads
   system that already tracks work units with stable global IDs; not
   using those IDs would forfeit gc-toolkit's strongest cross-doc anchor.

   **Open question (deferred to downstream policy):** which doc-types
   carry bead-IDs in frontmatter (`bead: tk-yiwfz.4`) vs body prose only?
   The synthesis surfaces both options without picking one.

3. **`[Source: <path>#<section>]` citation** — when one doc draws facts
   from another and the reader benefits from the provenance being
   greppable inline. Borrowed from BMAD's story-template convention.
   Particularly useful for principle docs and synthesis docs (this one)
   that aggregate facts from multiple research surveys.

**Reserved for specific cases:**

- **Numbered identifiers within a doc** (`FR-001`, `T###`, `CHK###`):
  adopt only if a doc-type formally needs structured cross-doc anchors
  to numbered items. Not a general gc-toolkit convention.
- **Filename pairing by shared slug + date**: rejected. gc-toolkit beads
  already timestamp work; the date prefix would be redundant.
- **Glob discovery**: rejected as a primary mechanism. gc-toolkit has
  fewer per-feature artifacts than BMAD; explicit refs are clearer than
  "find all `*spec*.md` in this directory."
- **Live-file embed** (`#[[file:<path>]]`): rejected. None of
  gc-toolkit's existing harnesses honour this; would be a feature
  gc-toolkit *adds*, not adopts.

### Bead-IDs and frontmatter — surfaced, not pre-decided

Per the bead's stop conditions: this synthesis *inventories* options for
attaching bead-IDs to docs but does not pre-decide which doc-types
carry them.

Two options:

- **A. Frontmatter field (`bead: tk-yiwfz.4`).** Machine-readable;
  greppable; allows tooling to build a doc↔bead map. Cost: every doc
  filing tool must remember to add the field; old docs need migration.
- **B. Body-prose convention** (e.g., a "Bead:" line near the top of
  the doc, as `consult-surfacing.md` does today). Survives without
  tooling; existing convention; cheap to retrofit. Cost: not as
  parseable.

**Recommended (deferred to downstream policy):** option B for current
gc-toolkit scope; revisit option A only when tooling demands a
machine-readable map.

## Migration notes — what would move under the proposed defaults

The migration impact is **small** because the proposed defaults largely
codify what gc-toolkit already does. Listing the existing docs and
where they'd land:

| Current path | Proposed path | Reason |
|---|---|---|
| `docs/gas-city-reference.md` | unchanged | Reference manual, type 1, central tier flat |
| `docs/gas-city-pack-v2.md` | unchanged | Versioned reference, type 2 |
| `docs/gascity-local-patching.md` | unchanged | Reference manual (process), type 1 |
| `docs/roadmap.md` | unchanged | Roadmap, type 3 |
| `docs/design/consult-surfacing.md` | unchanged | Design, type 6 |
| `docs/design/consult-session-feasibility.md` | unchanged | Design, type 6 |
| `docs/design/consult-session-v2-impl.md` | unchanged | Design, type 6 |
| `docs/research/naming-conventions/*.md` (six surveys) | unchanged | Research, type 7 |
| `docs/research/pack-architecture/spike-*.md` | unchanged | Research, type 7 |
| (this doc) `docs/principles/document-spec.md` | new file in new directory | Principle, type 4 |

**Net change:**

- One new directory: `docs/principles/`
- One new file: `docs/principles/document-spec.md` (this doc)
- Zero file moves
- Zero file renames
- Zero deletions

The proposal is **maximally non-disruptive**: it codifies existing
practice plus a small principles tier. No existing doc moves under
the proposed defaults.

**Existing patterns this spec implicitly endorses without enforcing:**

- `**Status:**` body prose lines on design docs (existing
  `consult-surfacing.md` style).
- "Beads:" body prose line for design docs that descend from bead
  work.
- "Current as of v<X> (<date>)" body line for reference manuals.
- `r<n>-` / `v<n>-` numeric prefixes for ordered survey series under
  `docs/research/<area>/` (in-flight on the escalation branch).
- Header comment block in every `pack.toml` and `city.toml` (Gas Town
  convention; non-doc but close-adjacent).

**Existing patterns this spec leaves room to revisit (out of scope for
this synthesis):**

- The single existing example of a dated working note
  (`learning_mockup_review-20260430.md` at the rig root, not yet on
  this branch — captured by the Gas Town survey). The taxonomy
  proposes `docs/notes/<YYYY-MM-DD>-<topic>.md` as the home; whether
  to migrate the existing example is downstream.

## Open questions — for operator review before adoption

The synthesis surfaces these questions rather than answering them.
Each is signalled as such with a tiebreaker recommendation if asked.

### Q1. Does gc-toolkit adopt a single versioned constitution file?

Spec Kit's `.specify/memory/constitution.md` is the only surveyed
source with a single versioned principles file. The pattern is rich:
semver in trailing line, sync-impact-report HTML comment per amendment,
articles cited by Roman numeral. Cost: every principle change requires
re-cutting the version line and writing the impact report.

**Tiebreaker recommendation if asked:** *not yet*. Adopt the
`docs/principles/<topic>.md` directory pattern (multiple files) for
now. Revisit constitution-style consolidation after the directory has
3-5 sibling principles and the cost of cross-principle drift becomes
visible. The directory shape leaves both options on the table; a
constitution file can subsume the per-file principles later.

### Q2. Does gc-toolkit adopt a hidden config dir (`.gc-toolkit/` or extending `.gc/`) for toolkit-managed doc-state?

Spec Kit (`.specify/`) and Kiro (`.kiro/`) use hidden top-level dirs;
BMAD, Superpowers, and Gas Town don't. gc-toolkit already has `.gc/`
for runtime state.

**Tiebreaker recommendation if asked:** *no*. Current `docs/` layout is
working; collapsing all of it under `.gc/` would conflate machine
state with human-and-agent edit surface. The two reference projects
that use a hidden dir (Spec Kit, Kiro) are workspace tools, not packs;
gc-toolkit's pack-shaped role is closer to BMAD's `docs/`-only layout.

### Q3. Does gc-toolkit adopt frontmatter on docs, and which fields?

All six surveyed sources use YAML frontmatter on at least one
doc-type, but the field shape varies (Spec Kit's `description` +
`handoffs` vs Kiro's `inclusion` vs BMAD's `title` + `description`).
gc-toolkit currently uses no frontmatter on its docs.

**Tiebreaker recommendation if asked:** *introduce frontmatter only on
specific doc-types when there's a tool that reads it.* Forcing
frontmatter on every doc creates maintenance cost; introducing it
when a harness or tool benefits keeps the cost-benefit honest.
Specific candidates: command files (Spec Kit's `description`,
`handoffs`); steering-style files if gc-toolkit ever adopts them.

### Q4. Bead-IDs in frontmatter or body prose?

Surfaced in cross-doc references above. **Tiebreaker recommendation
if asked:** body prose for now (option B), retrofit to frontmatter
(option A) only if tooling needs a machine-readable map.

### Q5. Date prefix on plans / dated working notes?

Superpowers uses `YYYY-MM-DD-<slug>.md` extensively; gc-toolkit's bead
system already timestamps work. The taxonomy reserves
`docs/notes/<YYYY-MM-DD>-<topic>.md` for the rare dated note but
doesn't recommend the pattern for plans (which the proposal scopes
inside feature bundles instead, with `plan.md`-style fixed names).

**Tiebreaker recommendation if asked:** *use the pattern only for
working notes, not for plans*. Beads already provide stable
timestamping; date-prefixing plans would duplicate that without adding
sortability that `ls` doesn't already give.

### Q6. Adopt `removals.txt` (BMAD-style deprecation registry) at the rig root?

Only BMAD ships one. Useful as a cheap migration trail when agent
names, command names, or formulas get renamed. gc-toolkit's beads
system can carry this load (a "gc-toolkit-removed" bead label is
trivial), but a plain-text registry is grep-friendlier.

**Tiebreaker recommendation if asked:** *defer*. Adopt only when
gc-toolkit accumulates two or three actual rename/remove migrations
that would benefit from a grep-friendly trail.

### Q7. Adopt a top-level `CHANGELOG.md` and/or `AGENTS.md` symlink?

Both BMAD and Superpowers ship `CHANGELOG.md` (and Superpowers ships
`RELEASE-NOTES.md`); both ship `AGENTS.md` (Superpowers as a symlink to
`CLAUDE.md`).

**Tiebreaker recommendation if asked:** *adopt when a release cadence
emerges*. gc-toolkit hasn't cut versioned releases yet; a `CHANGELOG.md`
without releases to chronicle is overhead. `AGENTS.md` as a symlink
costs nothing once a project-level `CLAUDE.md` exists; that's a
separate decision (currently `CLAUDE.md` files are scoped to
`agents/<name>/`, not the rig root).

### Q8. Which doc-type does the in-flight `docs/escalation/` exemplify?

The escalation branch (cited by the parent bead as a live test case)
shows `docs/escalation/{ideation,marching-orders,research-log,roadmap,
review-feedback,selection-menu}.md` plus `docs/escalation/research/`.
This taxonomy classifies it as **doc-type 8 (Feature work bundle)**.

The escalation branch *also* has `docs/escalation-foundation.md` at
the parent level — a central-tier doc that the work in `docs/escalation/`
descends from. The bundle pattern is therefore: *a central
"foundation" doc carries the durable claim; a same-name local
directory carries the work that produced and surrounds it.*

**Tiebreaker recommendation if asked:** *yes, formalise the bundle
pattern*. When a multi-doc effort exists, file under
`docs/<feature>/`; if a piece of the bundle graduates to central tier,
it lifts to `docs/<topic>.md` (or `docs/principles/<topic>.md`,
`docs/design/<topic>.md`, etc.) and leaves the bundle directory
intact as historical record.

### Q9. Conflicts between sources flagged for operator review?

Per the bead's stop conditions: "If two of the six sources clearly
conflict on a fundamental axis and the others don't break the tie:
surface the conflict, recommend a tiebreaker, but flag for operator
review before adoption."

**No fundamental two-vs-rest conflicts found.** The divergent axes
(hidden dir, per-feature density, frontmatter shape, filename
versioning) all show graduated positions across the sources, not
binary splits. The synthesis picks positions on each axis with
rationale; none is a tiebreaker call between conflicting reference
projects.

The closest to a conflict: **Spec Kit ships test tasks as OPTIONAL in
`tasks-template.md` while Spec Kit's example `constitution.md` calls
test-first NON-NEGOTIABLE.** This is internal to Spec Kit (one source)
rather than across sources. gc-toolkit doesn't currently face this
question; flagged for awareness if gc-toolkit ever ships a tasks
template that interacts with a constitution.

## Adoption checklist (for the operator)

If the operator adopts this spec by closing parent `tk-yiwfz` with
"yes, this default is adopted":

1. **No file moves required** under the proposed defaults (per
   migration notes above).
2. **Update operator-facing references** to point at this doc as the
   gc-toolkit document spec (e.g., from `roadmap.md`,
   `gas-city-reference.md`, or the rig-level `CLAUDE.md`-equivalent).
3. **Resolve open questions Q1–Q8** as separate downstream beads,
   filed against the relevant doc-type when the question becomes
   load-bearing (rather than pre-deciding now).
4. **Inform downstream tooling** if any (e.g., a future `gc doctor`
   check that validates doc-type placement against this spec).

This spec does not bind future authors until the operator adopts it.
Once adopted, deviations should file a follow-up principle doc
(`docs/principles/<exception>.md`) rather than silently diverge.

## Provenance footer

This synthesis was produced by polecat `gc-toolkit.furiosa` against
work bead `tk-yiwfz.4`, drawing on six platform surveys
(`tk-yiwfz.{1,2,3,5,6,7}` per the parent bead's blocked-by chain).
All upstream surveys are linked in the inventory matrix above; each
preserves its own commit-SHA-and-path provenance for the platform
material it documents.

**Surveyed at:** 2026-05-06
**Branch:** `polecat/tk-yiwfz.4-document-spec-synthesis`
**Parent bead:** `tk-yiwfz`
**Sibling synthesis inputs:**
- `tk-yiwfz.1` → `docs/research/naming-conventions/bmad-method.md`
- `tk-yiwfz.2` → `docs/research/naming-conventions/superpowers.md`
- `tk-yiwfz.3` → `docs/research/naming-conventions/gastown.md`
- `tk-yiwfz.5` → `docs/research/naming-conventions/bmad-method-templates.md`
- `tk-yiwfz.6` → `docs/research/naming-conventions/spec-kit.md`
- `tk-yiwfz.7` → `docs/research/naming-conventions/kiro.md`
