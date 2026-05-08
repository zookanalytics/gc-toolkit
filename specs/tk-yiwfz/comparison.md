---
name: Document Spec — Comparative Analysis (Drafts A/B/C)
description: Convergence and divergence inventory across three v2 doc-spec drafts (A=tk-yiwfz.8, B=tk-yiwfz.9, C=tk-yiwfz.10), with verbatim quotes, singletons, and central-doc filename candidates. Inventory only — no winner pick, no synthesis.
---

# Document Spec — Comparative Analysis (Drafts A/B/C)

This document inventories what the three v2 doc-spec synthesis drafts agree on,
disagree on, and address uniquely. It does **not** pick a winner, name the
central doc, or propose new structural decisions. The downstream synthesis bead
will do that, informed by mechanik+operator conversation against this surface.

The drafts (clean rewrites against
[`decisions.md`](decisions.md), not edits of v1):

| Tag | Bead | Polecat | File | Lines |
|---|---|---|---|---|
| A | `tk-yiwfz.8` | `gc-toolkit.furiosa` (resumed) | [`synthesis.md`](../tk-yiwfz.8/synthesis.md) | 499 |
| B | `tk-yiwfz.9` | `gc-toolkit.slit` | [`synthesis.md`](../tk-yiwfz.9/synthesis.md) | 480 |
| C | `tk-yiwfz.10` | `gc-toolkit.ripley` (codex) | [`synthesis.md`](../tk-yiwfz.10/synthesis.md) | 291 |

## At-a-glance

**Draft A** is the most structurally explicit. It fronts the AI-centric
framing as a standalone section before the use-cases table, fronts a
9-row use-cases table, and consolidates rejections into a single
"What's deliberately **not** here" inventory of six items. It carries
the most detailed provenance section (full survey table with upstream
commit SHAs) and is the longest at 499 lines. Self-description:
*"gc-toolkit's filing rules for central reference docs and bead-tied
work artifacts; two-root layout, AI-centric framing, with cross-source
provenance from six platform surveys."*

**Draft B** is the most "design-tension explicit." It treats Diátaxis
as a "Why not Diátaxis" subsection rather than fronting it, foregrounds
the departure from `.specify/`/`.kiro/` hidden-dir conventions (which
neither A nor C discusses), draws out the discoverability-hook concept
with a Superpowers "Use when …" citation, and names the loose-vs-deliberate
asymmetry as design rather than compromise. 480 lines. Self-description:
*"Where files belong in gc-toolkit — central authoritative `docs/` and
local bead-keyed `specs/<bead-id>/`, with rules derived from reader
use-cases and cross-source convergence."*

**Draft C** is the most compact (291 lines, ~40% shorter than A or B). It
condenses the AI-centric framing into a single paragraph in the opening,
distributes rejections contextually rather than consolidating them, uses
Title Case section headers throughout, and is the only draft to close
with a *"Summary Rule"* paragraph the reader walks away with. It is also
the only draft that explicitly rejects `docs/research/` as a standing
central doc-type directory. Self-description: *"Clean v2 synthesis for
gc-toolkit central docs and bead-local specs."*

## Convergence

All three drafts agree on the following positions. These are settled —
the operator can read them as "this is what we're doing" and the
downstream synthesis will not relitigate them.

**Two-root layout.** `docs/` and `specs/` both sit at the repo root,
*not* `docs/specs/`. Each of the three states this prominently:

- A: *"Both roots sit at the **repo root**, not nested. This is the most
  load-bearing structural decision in the spec; the rest follows from it."*
- B: *"Both at the repo root. **Not** `docs/specs/`."*
- C: *"Do not use `docs/specs/`. `docs/` and `specs/` follow different
  rules and have different epistemic status, so they deserve different
  roots."*

**Two epistemic tiers (central authoritative, local historical).** Each
draft frames the central/local split as not just rule-set but truth-status:
central docs can be cited as ground truth; local docs require bead context
to interpret. This grounds the no-archiving rule.

- A: *"Central docs are authoritative. They speak what is true… Local
  docs are historical record. They capture what was thought, proposed,
  decided, or considered at a moment of work."*
- B: *"The deepest distinction in this spec is not where docs *live* —
  it is what docs *claim*."*
- C: *"Central docs state what is true now… Local docs are historical
  record. They record what was proposed, researched, considered, or
  believed during a piece of work."*

**Bead-id-only directory naming.** `specs/tk-yiwfz/`, not
`specs/tk-yiwfz-document-spec/`. All three give the same rationale —
meaningful names drift, bead IDs don't.

- A: *"Meaningful names drift as scope evolves; bead-ids don't."*
- B: *"Bead titles drift as scope clarifies; descriptive folder
  suffixes encode an early-bead title that may no longer fit by the
  time the bead closes."*
- C: *"Meaningful names drift as work changes; bead IDs do not."*

**Files inside bead dirs flat by default.** No forced
`research/`/`proposals/`/`alternatives/` sub-directories; nest only
when a workflow demonstrates the need.

**Workflow-specific filenames; no master list.** All three explicitly
refuse to mandate `spec.md`/`plan.md`/`tasks.md` (or any other set) at the
spec level. Conventional names emerge per workflow.

- A: *"This spec does **not** prescribe a master list of canonical
  filenames; we avoid defining things before they need to be defined."*
- B: *"This spec **does not prescribe a master list** of fixed filenames…
  We avoid defining things before they need to be defined."*
- C: *"The document spec does not prescribe a master filename list before
  the workflow needs it."*

**Frontmatter: `name` + `description` only.** All three use these exact
two fields and no others. Mandatory on spec docs (because filenames are
flexible); encouraged on central docs.

**Frontmatter rejections.** All three reject `inclusion` /
`fileMatchPattern` (Kiro), `handoffs` (Spec Kit), and a `bead-id` field.
Same reasons cited.

**Three cross-doc reference mechanisms.** Same set, same order in all
three: (1) markdown relative-path links, (2) path-as-bead-anchor for spec
docs, (3) `[Source: <path>#<section>]` citations for synthesis-style
provenance.

**Cross-doc rejections.** All three reject within-doc numbered IDs
(`FR-001`, `T###`), filename pairing by shared slug+date (Superpowers),
glob discovery (BMAD `*prd*.md`), and live-file-embed (Kiro
`#[[file:<path>]]`).

**No archive directory.** Location is set at file-time and never changes
based on bead state. Bead status is the lifecycle marker, not the
filesystem.

**Versioning is git.** No `-v<N>` filename suffix, no semver trailing
line on principles, no sync-impact-report HTML comments. The
"versioned-reference doc-type" from v1 collapses entirely.

**Timestamps rare, only when content is genuinely temporal.** Default no
date in filenames; allowed when the content is *about* a moment in time
(e.g., "state of upstream BMAD as of 2026-05-01"). Not required, not
promoted.

**AI-centric framing; central/local-by-temporal-binding axis.** All three
explicitly reject Diátaxis as the primary axis and adopt the
when-does-this-doc-enter-context-window axis instead.

**Two reasons for the spec.** Frustration ("files everywhere") *and*
self-discipline (gc-toolkit modeling the rule it asks others to follow).
Both load-bearing.

**Drafting in `specs/` is loose; adoption to `docs/` is deliberate.**
Each draft frames this asymmetry as intentional.

**Migration is a separate bead.** Re-shaping the existing tree is out of
scope for the spec itself.

**Two genuinely-open questions.** Top-level `CLAUDE.md` for users
vendoring gc-toolkit; cross-bead query tooling over `specs/` frontmatter.
Same two in all three drafts.

**Resolved-question table (Q1–Q9).** All three render the same nine
resolutions with substantively the same answers.

## Divergence inventory

For each dimension below: each draft's choice in one sentence with a
short verbatim quote where the choice is most clearly stated, then the
implicit tradeoff. **No winner picked.**

### 1. Opening framing — explicit-tension vs prose-summary vs immediate-dive

- **A**: Section heading, two reasons in elaborate paragraphs, then an
  explicit tension paragraph: *"Neither reason alone is enough. The
  first reason without the second is 'please do as I say, not as I do.'
  The second reason without the first is internal hygiene with no
  external pull."*
- **B**: Section heading, two reasons in tight prose, closing line:
  *"The frustration alone would justify a layout. The self-discipline
  makes that layout something we hold ourselves to before we publish it."*
- **C**: No section heading; opens directly with *"Files end up
  everywhere: `.prd-reviews/`, `.specs/`, `.bmad-output/`."* and folds
  the rationale into the first paragraph.

**Tradeoff**: A makes the *tension* between the two reasons most
legible; B closes with a memorable single sentence; C is the easiest to
scan but does not foreground the tension.

### 2. Diátaxis treatment — dedicated section vs labeled subsection vs single sentence

- **A**: Dedicated top-level section *"AI-centric framing, stated
  explicitly"* placed *before* the use-cases table; ~30 lines of
  argument including *"It is, however, **human-centric**. It classifies
  docs by *learning mode*…"*
- **B**: Labeled subsection *"Why not Diátaxis"* placed inside the *Two
  epistemic tiers* section; ~15 lines including *"Diátaxis… is a
  human-centric framing — its categories partition docs by *which mode
  of human learning is happening when the doc is read*."*
- **C**: Single sentence in the opening: *"Diátaxis is useful for human
  learning modes, and BMAD uses it directly for its user-facing docs,
  but gc-toolkit adopts the central/local-by-temporal-binding axis
  instead."*

**Tradeoff**: A foregrounds the framing decision as load-bearing; B
treats it as supporting the tier model; C assumes the reader doesn't
need much explanation and saves space.

### 3. Use-cases table — 9 rows vs 7 rows vs 6 rows

- **A**: 9 rows, including *"What are gc-toolkit's principles?"*,
  *"Loading context for task X"*, and *"Is this doc still
  authoritative?"*
- **B**: 7 rows; omits the principles-specific row and the
  *"authoritative?"* row, retains *"Loading context for task X"*.
- **C**: 6 rows with broader phrasings (*"What is true about
  gc-toolkit now?"*, *"What work produced this decision?"*).

**Tradeoff**: more queries surface more filing rules to derive (A);
fewer focus the table on the core access patterns (C); B sits between.

### 4. Hidden-dir convention departure — discussed vs not discussed

- **A**: Does not discuss `.specify/` or `.kiro/`.
- **B**: Substantial paragraph: *"This is a deliberate departure from
  Spec Kit's `.specify/` and Kiro's `.kiro/` hidden-dir conventions.
  Their hidden dirs hold toolkit-managed state alongside the
  user-edited specs; gc-toolkit already separates runtime state into
  `.gc/`, so the docs-vs-runtime boundary is already drawn at a
  different axis."*
- **C**: Does not discuss; only mentions Kiro uses `.kiro/`.

**Tradeoff**: B answers an obvious follow-up question ("Spec Kit and
Kiro hide their specs dir; why don't we?"); A and C let the choice
stand on the cross-source convergence argument alone.

### 5. Multi-workflow filename rationale — explicit vs brief vs brief

- **A**: Names the multi-workflow nature as the reason for refusing
  fixed filenames: *"gc-toolkit hosts multiple workflows simultaneously
  (Spec-Kit-shaped feature work, design iterations, synthesis beads,
  research surveys), so filename rigidity at the spec level would force
  every workflow into one shape."*
- **B**: Brief acknowledgment that filenames are workflow-specific; no
  multi-workflow rationale.
- **C**: Brief acknowledgment; no multi-workflow rationale.

**Tradeoff**: A explains *why* the convergence on `spec.md`/`plan.md`
in Spec Kit and Kiro doesn't transplant to gc-toolkit; B and C let the
"workflows converge on conventions" framing carry the argument.

### 6. Frontmatter discoverability-hook discussion

- **A**: Brief — notes mandatory on spec, encouraged on central; no
  guidance on *how to write* a description.
- **B**: Substantial paragraph: *"The `description` field is a
  **discoverability hook**, not a summary of the doc's body. Superpowers'
  'Use when …' discipline for skill descriptions documents the failure
  mode: when descriptions summarise the body, AI agents follow the
  description instead of reading the body."*
- **C**: Brief — same as A.

**Tradeoff**: B offers practical guidance to authors writing
descriptions and pre-empts the most common failure mode; A and C trust
the reader to infer.

### 7. Rejection enumeration — single inventory vs distributed

- **A**: Dedicated section *"What's deliberately **not** here"* with six
  consolidated rejections (archive directory, filename version suffix,
  date prefix, constitution-versioning footer, sync-impact-report HTML
  comments, top-level meta-doc index for `docs/`).
- **B**: Rejections distributed across *Filename and path discipline*
  (no archiving, versioning is git, timestamps), *Frontmatter > Not
  adopted*, and *Cross-doc references > Rejected*.
- **C**: Rejections distributed across *Versioning*, *Local Specs >
  Location is set*, *Frontmatter > Do not adopt*, and *Cross-Document
  References > Reject these as defaults*.

**Tradeoff**: A's single inventory is easiest to scan for *"what was
ruled out"*; B and C keep each rejection contextual to its topic, at
the cost of making "the full no-list" hard to assemble.

### 8. Standing central doc-type directories — `docs/research/` rejection

- **A**: Rejects `docs/design/` and `docs/notes/`. Does *not* explicitly
  address `docs/research/`. Existing `docs/research/naming-conventions/`
  placement deferred to migration bead.
- **B**: Same as A — rejects `docs/design/` and `docs/notes/`. Does *not*
  address `docs/research/`.
- **C**: Rejects both: *"Do not create standing central doc-type
  directories like `docs/design/` or `docs/research/` as defaults. A
  design/proposal or research note that belongs to work starts local. A
  compact adopted conclusion may later be written into a central topic
  doc."*

**Tradeoff**: C's flatter central tier matches its compact-form
philosophy and would relocate the existing research surveys to
`specs/`; A and B leave the question open for the migration bead. (See
**Singletons** — this is also a singleton, but worth surfacing here
because it's a structural divergence.)

### 9. `docs/<topic>/` promotion threshold and scope

- **A**: Principle-specific: *"single `docs/principles.md` file today;
  promote to `docs/principles/` directory only when 3–5 sibling
  principles warrant"*.
- **B**: Generalized: *"Promote `docs/<topic>.md` to
  `docs/<topic>/<sub-topic>.md` only when 3–5 siblings warrant a
  directory."*
- **C**: Cautious; principle-only and without a numeric threshold: *"do
  not create a versioned constitution or a `docs/principles/` directory
  by default."*

**Tradeoff**: A nails the threshold for the one current case; B
generalizes the pattern to any future topic; C avoids prescribing the
pattern at all.

### 10. Bead-hierarchy nesting (parent/child folders under one parent bead)

- **A**: Dedicated paragraph with rule-of-thumb: *"Bead hierarchy is
  flat too… Optional nesting (`specs/tk-parent/{tk-parent.1/,
  tk-parent.2/}`) is allowed when the parent–child relationship is
  durable and physical co-location aids the reader."*
- **B**: Brief, embedded in the flat-files-default discussion;
  references decisions.md for the example.
- **C**: Does not discuss bead-hierarchy nesting at all.

**Tradeoff**: A surfaces nesting as a real choice the reader may face;
B defers to decisions.md for the worked example; C drops the topic in
the interest of compactness.

### 11. Citation path style — repo-root vs relative-from-spec

- **A**: Repo-root paths, e.g.,
  `[Source: docs/research/naming-conventions/bmad-method.md#…]`.
- **B**: Repo-root paths, same form as A.
- **C**: Relative paths from the spec file, e.g.,
  `[Source: ../../docs/research/naming-conventions/bmad-method.md#…]`.

**Tradeoff**: repo-root paths are stable if the doc moves and read
clearly without knowing the doc's location (A, B); relative paths
render correctly from the doc's *current* location and match the
convention the body links use (C), at the cost of breaking under
relocation.

### 12. Drafting and adoption flow — list vs list+prose vs prose

- **A**: Four numbered steps (drafts in `specs/`, operator review,
  adoption PR, migration is separate bead).
- **B**: Three numbered steps + an explicit prose framing of the
  asymmetry: *"The asymmetry — loose drafts, deliberate central docs —
  is part of the design, not a temporary compromise."*
- **C**: Mostly paragraph form: *"Drafts in `specs/` are loose by
  design… Adoption is deliberate… Migration of the existing tree is
  separate work."*

**Tradeoff**: A walks the reader through the steps as a procedure; B
names the design tension and places it before the procedure; C
narrates the same content as flowing prose.

### 13. Closing — provenance vs provenance vs Summary Rule

- **A**: Ends with the *Provenance* section (no final summary).
- **B**: Ends with the *Provenance* section (no final summary).
- **C**: Ends with a *Summary Rule* paragraph: *"If the document says
  what gc-toolkit believes now, file it in `docs/` and keep it true. If
  the document records work, file it in `specs/<bead-id>/` and preserve
  it as context. Everything else in this spec exists to make that
  decision cheap, visible, and reliable for both humans and AI agents."*

**Tradeoff**: A and B trail off into provenance metadata; C lands a
memorable rule the reader walks away with, at the cost of one more
section the binding form would have to keep current.

### 14. Provenance section depth

- **A**: Detailed; full table of all six surveys with file paths and
  upstream commit-SHA + date provenance (`@ 0f26551 (2026-05-05)` etc.).
  Also references the v1 synthesis bead and polecat by name.
- **B**: Compact prose with relative-path references to the surveys; no
  upstream commit details.
- **C**: Compact prose at high level; says the surveys "carry the
  upstream commit-SHA provenance" without restating it.

**Tradeoff**: A enables fact-checking against upstream from inside the
synthesis; B and C trust the surveys' own provenance metadata and keep
the section short.

### 15. Section-header style

- **A**: Sentence-case (lowercase) headers throughout.
- **B**: Sentence-case (lowercase) headers throughout.
- **C**: Title Case headers (e.g., *Reader Queries Drive the Layout*,
  *Two Roots*, *Central Docs: docs/*).

**Tradeoff**: minor; pure stylistic preference. Title Case scans
slightly more like a book chapter list; sentence-case reads as a
flowing technical document.

### 16. Length / density

- **A**: 499 lines; thorough.
- **B**: 480 lines; thorough but tighter.
- **C**: 291 lines; ~40% shorter than A or B.

**Tradeoff**: A and B retain rationale paragraphs that C drops (e.g.,
the multi-workflow filename argument; the two-bucket-model framing;
the explicit Diátaxis section). C reads faster; A and B answer more
follow-up questions in-line.

## Singletons

Points only one draft addresses. Worth surfacing because either (a) the
silent drafts considered the point and dropped it, or (b) only one
draft thought of the point and it may be worth incorporating.

### Draft A only

- **Single consolidated *"What's deliberately not here"* section** with
  six rejections in one place. The other two drafts distribute
  rejections contextually.
- **Reading-mode mnemonic**: *"central is what's true; local is what was
  thought."* Single-line summary that neither B nor C provides.
- **"Two-bucket repo model" as a labeled justification** in the
  two-root layout discussion (*"Humans and AI go to `docs/` for durable
  reference, `specs/` for work artifacts. Clean and predictable."*).
- **Explicit rejection of a top-level meta-doc index for `docs/`**:
  *"No top-level meta-doc index for `docs/`. The directory listing is
  the index."* Neither B nor C discusses this.
- **Full provenance table** with upstream commit SHAs, dates, and
  source-repo paths for all six surveys.

### Draft B only

- **Labeled *"Why not Diátaxis"* subsection** that critiques Diátaxis
  on the specific axis of "what mode of human learning is happening."
  A and C each treat the rejection but neither labels it as a discrete
  question.
- **Departure from `.specify/`/`.kiro/` hidden-dir conventions**
  discussed explicitly (*"gc-toolkit already separates runtime state
  into `.gc/`, so the docs-vs-runtime boundary is already drawn at a
  different axis."*). Neither A nor C raises this question.
- **"Discoverability hook, not a summary"** discussion citing
  Superpowers' *"Use when …"* failure mode for skill descriptions.
  Practical writing guidance neither A nor C provides.
- **Explicit naming of the loose-vs-deliberate asymmetry as design,
  not compromise**: *"The asymmetry — loose drafts, deliberate central
  docs — is part of the design, not a temporary compromise."*
- **AGENTS.md-as-symlink pattern** (Superpowers) mentioned as a
  candidate location-shape for a future top-level `CLAUDE.md`. Neither
  A nor C surfaces this option.
- **Generalized `docs/<topic>/` promotion pattern** (any topic, not
  just principles).

### Draft C only

- **Closing *"Summary Rule"* paragraph** that crystallises the spec
  into one sentence-pair. Neither A nor B closes this way.
- **Explicit rejection of `docs/research/` as a standing central
  doc-type directory** (*"Do not create standing central doc-type
  directories like `docs/design/` or `docs/research/` as defaults. A
  design/proposal or research note that belongs to work starts local."*).
  This is a structural decision that A and B leave open / defer to
  migration. **Open question raised but not resolved in any draft**:
  if `docs/research/` is rejected as a default, where do the existing
  research surveys at `docs/research/naming-conventions/*.md` belong?
- **Title Case section headers** throughout — purely stylistic but a
  visible difference.
- **Citation paths in relative-from-spec form** (`../../docs/...`)
  rather than repo-root form. Matches the body's relative-link
  convention; differs from A and B.
- **Most compact form overall**, achieved by dropping rationale paragraphs
  rather than by trimming positions.

## Open name candidates for the central doc

Operator flagged `document-spec.md` as probably not the right filename
for the binding central form. (All three drafts use `document-spec.md`
as a placeholder.) Candidate names below, drawn from how each draft
frames what the doc actually covers; the spec covers (1) two-root
filing rules, (2) frontmatter conventions, (3) cross-doc reference
conventions, (4) drafting/adoption flow. **No pick made — the
downstream synthesis bead resolves this with operator input.**

| Candidate | One-line rationale |
|---|---|
| `docs/documents.md` | Broadest noun-form name; topic = "documents." Risk: ambiguous between *"a list of documents"* and *"rules about documents."* |
| `docs/filing.md` | Action-oriented, matches Draft B's framing *"Where files belong in gc-toolkit."* Risk: narrows to filing; understates frontmatter / citation / adoption rules. |
| `docs/document-layout.md` | Foregrounds the two-root structural decision (*"the most load-bearing structural decision"* per Draft A). Risk: layout is one of four areas covered. |
| `docs/document-conventions.md` | Captures the rule-set scope (filing + frontmatter + citations + adoption) without claiming spec authority. Risk: longer than the alternatives. |
| `docs/documentation.md` | Broadest name covering "how documentation works in gc-toolkit." Risk: invites scope creep into writing-style / tone, neither of which this spec covers. |
| `docs/repo-docs.md` | Scope-clear ("docs in this repo") and short. Risk: mildly redundant with the parent dir name. |

Open question the candidate set surfaces: should the central doc be
named for what it *prescribes* (filing, layout, conventions) or for
what it *covers* (documents, documentation)? The drafts' own
self-descriptions split — A leans "rules + layout + framing"; B leans
action ("where files belong"); C leans structure ("central docs +
bead-local specs"). The downstream synthesis can use those framings to
narrow.

## Out of scope (carry-over)

Per [`decisions.md`](decisions.md) and the parent bead `tk-yiwfz`,
the following are explicitly out of scope for the spec itself and
remain so for the downstream converged synthesis:

- **Migration of the existing tree** to the new layout — separate bead
  with specific guidance. The spec defines the target; it does *not*
  carry the file-list or rename plan.
- **Agent-role ownership** of doc maintenance, refresh cadence, or
  authorship (mechanik vs polecats vs human). Not addressed by any draft.
- **Workflow / lifecycle process** for moving a doc from draft → review
  → adoption. The drafts describe the flow at a high level (drafts in
  `specs/`, operator review, adoption PR, migration bead) but do not
  prescribe a process — that lives in workflow tooling, not the doc spec.
- **Bead-ID attachment policy beyond what's already stated.** All three
  drafts settle: bead-ID is in the *path* for spec docs; central docs
  do not carry bead-IDs at all (provenance is git blame → commit → bead
  reference). No additional attachment forms are entertained.
- **Top-level `CLAUDE.md` for users vendoring gc-toolkit.** Genuinely
  open in all three drafts; non-blocking for adoption. The spec can
  accommodate either choice; a separate bead resolves it when the need
  surfaces.
- **Cross-bead query tooling** over `specs/` frontmatter (the
  gc-toolkit-specific wrapper that grep-walks `specs/*/*.md` for
  description-based discovery). Genuinely open in all three drafts;
  follow-on work, non-blocking.

## Provenance

- **Anchor**: [`specs/tk-yiwfz/decisions.md`](decisions.md) — directional
  calls captured 2026-05-06.
- **Drafts compared**: [`specs/tk-yiwfz.8/synthesis.md`](../tk-yiwfz.8/synthesis.md),
  [`specs/tk-yiwfz.9/synthesis.md`](../tk-yiwfz.9/synthesis.md),
  [`specs/tk-yiwfz.10/synthesis.md`](../tk-yiwfz.10/synthesis.md).
- **v1 reference** (context only):
  [`docs/principles/document-spec.md`](../../docs/principles/document-spec.md).
- **Six platform surveys** (referenced by the drafts, not re-cited
  here): `docs/research/naming-conventions/{bmad-method,
  bmad-method-templates, superpowers, gastown, spec-kit, kiro}.md`.
- **This bead**: `tk-yiwfz.11`. Filed by mechanik on operator request to
  close the gap between the three draft polecats (closed 2026-05-07)
  and the downstream converged synthesis. **Inventory only — no winner
  pick, no filename pick, no synthesis.**
