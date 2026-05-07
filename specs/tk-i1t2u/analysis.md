---
name: doc-spec v2 synthesis — convergence/divergence analysis
description: Structured comparison of three v2 doc-spec drafts (A/B/C) against the decisions.md anchor; identifies what is adoptable without further decision, where the drafts disagree (operator decision points), and what each draft uniquely contributes.
---

# v2 doc-spec synthesis — convergence/divergence analysis

Three independent v2 doc-spec syntheses (drafts A, B, C) merged on
`origin/main`. This analysis compares them against the directional
anchor `specs/tk-yiwfz/decisions.md` and against each other to
support the operator's adoption decision.

**Scope:** convergence/divergence/unique-to-one matrix plus a
faithfulness check and brief form notes. **Not in scope:** writing a
fourth draft, recommending which divergent position to adopt, or
re-surveying upstream platforms.

## 1. Provenance

| Draft | File | Lines | Author |
|-------|------|-------|--------|
| Anchor | `specs/tk-yiwfz/decisions.md` | 358 | operator + mechanik (2026-05-06) |
| A | `specs/tk-yiwfz.8/synthesis.md` | 499 | polecat `gc-toolkit.furiosa` |
| B | `specs/tk-yiwfz.9/synthesis.md` | 480 | (per bead notes; second polecat) |
| C | `specs/tk-yiwfz.10/synthesis.md` | 291 | codex |

All three drafts cite the anchor and the six surveys at
`docs/research/naming-conventions/{bmad-method, bmad-method-templates,
superpowers, gastown, spec-kit, kiro}.md`.

## 2. Convergence

Where all three drafts agree. Each row is adoptable without further
operator decision. References cite section names; line numbers omitted
to keep this stable across light edits.

| # | Convergent claim / rule | Evidence (A / B / C) |
|---|---|---|
| C1 | **Two reasons to exist**: tools-drop-output frustration AND gc-toolkit modelling its own rule. Both load-bearing; neither alone suffices. | A "Why this spec exists"; B "Why this spec exists"; C opening paragraphs |
| C2 | **AI-centric framing**: central/local-by-temporal-binding axis, *not* Diátaxis. | A "AI-centric framing, stated explicitly"; B "Why not Diátaxis"; C second paragraph |
| C3 | **Use-cases drive structure**: doc opens with a queries-readers-make table from which filing rules fall out. | A "The queries readers need to make"; B "Use-cases drive structure"; C "Reader Queries Drive the Layout" |
| C4 | **Two roots at repo root**: `docs/` (central) and `specs/` (local), not `docs/specs/`. | A "Two-root layout"; B "Two roots: `docs/` and `specs/`"; C "Two Roots" |
| C5 | **Central is authoritative; local is historical record.** Epistemic-status distinction grounds the no-archive rule. | A "Central is authoritative; local is historical record"; B "Two epistemic tiers"; C "Central Docs", "Local Specs" |
| C6 | **Central tier** (`docs/`): one file per concern, flat by default, refreshed in place, no bead-IDs. | A "Central tier — `docs/`"; B "Two epistemic tiers"; C "Central Docs: `docs/`" |
| C7 | **Bead-dir name = bead-id alone**, no descriptive suffix. | A "Local tier — `specs/`"; B "Directory name = bead-ID alone"; C "Local Specs" |
| C8 | **Files inside a bead dir are flat by default**; sub-dirs only when a workflow demonstrates need. | A "Local tier — `specs/`"; B "Files inside a bead dir are flat by default"; C "Local Specs" |
| C9 | **Fixed filenames are workflow-specific**, not universal mandates. Spec doesn't prescribe a master list. | A "Local tier — `specs/`"; B "Filenames inside bead dirs are workflow-specific conventions"; C "Local Specs" |
| C10 | **Frontmatter = `name` + `description` only.** Mandatory on spec docs, encouraged on central. | A "Frontmatter"; B "Frontmatter"; C "Frontmatter" |
| C11 | **Reject `inclusion`/`fileMatchPattern` (Kiro), `handoffs` (Spec Kit), and a `bead-id` field.** | A "Frontmatter — Not adopted"; B "Frontmatter — Not adopted"; C "Frontmatter" |
| C12 | **No archiving / no lifecycle-driven file movement.** Path is set at file-time and never changes from bead state. | A "What's deliberately not here"; B "No archiving"; C "Local Specs" |
| C13 | **Versioning is git**: no `-v<N>` suffix, no semver footer on principles, no sync-impact-report HTML comments. The v1 versioned-reference doc-type collapses. | A "What's deliberately not here"; B "Versioning is git"; C "Versioning" |
| C14 | **Timestamps**: default no; allowed only when content is genuinely temporal; not required, not promoted. | A "What's deliberately not here"; B "Timestamps: rare …"; C "Local Specs" |
| C15 | **Cross-doc references — three mechanisms**: markdown relative-path links, path-as-bead-anchor, `[Source: <path>#<section>]` citations. | A "Cross-doc references"; B "Cross-doc references"; C "Cross-Document References" |
| C16 | **Reject** as cross-doc defaults: numbered IDs within a doc, filename pairing by shared slug+date, glob discovery, live-file embed (`#[[file:<path>]]`). | A "Cross-doc references — Rejected"; B "Cross-doc references — Rejected"; C "Cross-Document References" |
| C17 | **Drafts in `specs/` are loose; central docs are deliberate.** Adoption PR lifts compact form into `docs/<topic>.md`; migration is a separate bead. | A "Drafting and adoption flow"; B "Drafting and adoption"; C "Drafting, Adoption, and Migration" |
| C18 | **Resolved Q1–Q9** answered identically (frontmatter shape, bead-IDs not in metadata, dates default-no, removals deferred, CHANGELOG/AGENTS deferred, escalation-doc-type dissolved, no remaining cross-source conflicts). | A "Resolved open questions"; B "Resolved questions (from v1)"; C "Resolved Decisions" |
| C19 | **Two genuinely open questions**: top-level `CLAUDE.md` for vendoring users; cross-bead query tooling over `specs/`. | A "Genuinely remaining open questions"; B "Genuinely open questions"; C "Remaining Open Questions" |
| C20 | **Provenance section** cites the decisions.md anchor and the six surveys; surveys carry upstream commit-SHA provenance, syntheses cite surveys not upstream directly. | A "Provenance"; B "Provenance"; C "Provenance" |

## 3. Divergence

Where the drafts differ. "Real?" column flags whether the divergence
is a substantive disagreement vs a phrasing/depth/scope choice. Each
row notes any anchor (decisions.md) text bearing on the choice.

| # | Topic | Draft A | Draft B | Draft C | Real? | Anchor bearing |
|---|---|---|---|---|---|---|
| D1 | **Use-cases table — row count and content** | 9 rows, including unique "What are gc-toolkit's principles?" and "Is this doc still authoritative?" | 7 rows; combines architecture/convention/principle into one query | 6 rows; phrases queries more abstractly ("What is true about gc-toolkit now?") | Phrasing/scope; A's "Is this doc still authoritative?" row is genuinely additional content (epistemic-status query) | Anchor's table has 7 rows; none of the three matches it exactly. A and B closer to anchor's level of specificity; C further abstracts. |
| D2 | **`docs/design/` and `docs/notes/` explicit no-rule** | States both explicitly: "No `docs/design/` as a standing directory" and "No `docs/notes/` doc-type" | Doesn't state either explicitly — implicit from "one file per concern" | Has principle ("Do not create standing central doc-type directories like `docs/design/` or `docs/research/` as defaults") but `docs/research/` not `docs/notes/` as example, and no explicit `docs/notes/` rule | Real (omission level): A is most faithful to anchor's explicit calls; B drops both; C generalises the principle but drops the specific examples | Anchor explicitly calls out **both** `docs/design/` and `docs/notes/` as drop/no-create. |
| D3 | **Bead-hierarchy nesting (default flat, optional nesting)** | Includes the rule with example `specs/tk-parent/{tk-parent.1/, tk-parent.2/}` and rule-of-thumb | Includes the rule, references decisions.md for example, includes rule-of-thumb | **Does not include** the bead-hierarchy nesting rule at all | Real (omission): C is missing an anchor-specified rule. The optional-nesting rule and rule-of-thumb are absent in C. | Anchor has its own section "Bead hierarchy: default flat, optional nesting" with an explicit example. |
| D4 | **Comparison with Spec Kit `.specify/` and Kiro `.kiro/` hidden-dir conventions** | Doesn't compare | Explicit paragraph naming the departure: "deliberate departure from Spec Kit's `.specify/` and Kiro's `.kiro/` hidden-dir conventions" — argues `.gc/` already separates runtime state | Mentions Kiro's `.kiro/` location as a fact in passing; no analytical departure framing | Phrasing/depth; B argues most fully | Anchor's "Two-root layout" rationale references Spec Kit and Kiro convergence, doesn't argue the hidden-dir vs visible-dir choice. B's framing is additive but not anchor-required. |
| D5 | **Discoverability-hook depth** | Describes `description` as the discoverability hook in one sentence | Adds a paragraph: description is *not* a body summary, citing Superpowers' "Use when …" failure-mode discipline | Calls it the "cross-bead discovery hook"; no failure-mode discussion | Phrasing/depth. B has the deepest treatment. | Anchor states "frontmatter `description` is the discoverability hook" without elaboration. B's elaboration is additive. |
| D6 | **"What's deliberately not here" structural device** | Has its own section bundling rejections (archive, version suffix, date prefix, constitution-versioning footer, sync-impact comments, top-level meta-doc index) | Distributes rejections across sections; no bundled "not here" section | Distributes rejections across sections; no bundled "not here" section | Real (form): different documents read differently. A's bundling makes rejection visible; B/C interleave with positive rules. | Anchor doesn't prescribe a structural device; both forms are anchor-compatible. |
| D7 | **No top-level meta-doc index for `docs/`** | Includes the rule (under "What's deliberately not here") | Doesn't address | Doesn't address | Real (content): A introduces a rule the anchor doesn't specify. See §5 faithfulness check — this is the only invention not grounded in decisions.md. | **Not in anchor.** A introduces it; B and C correctly omit. |
| D8 | **`docs/principles.md` → `docs/principles/` promotion threshold** | Explicit: promote at "3–5 siblings" | In Q1 row: "if the directory accumulates ≥3-5 sibling principles" | "do not create … `docs/principles/` directory by default" — no explicit threshold | Phrasing; A and B agree on threshold; C states the default but not the trigger | Anchor: "promote to `docs/principles/` directory only when 3–5 sibling principles warrant" — A and B match anchor exactly; C compresses. |
| D9 | **Adoption flow — step count and elaboration** | 4 explicit steps: drafts loose, operator review, adoption PR, migration separate bead. Elaborates "Migration impact is a fact, not a selling point." | 3 steps, similar substance, less elaboration | Combined into one section "Drafting, Adoption, and Migration" — no numbered steps but covers all three phases | Phrasing/depth; same substance. | Anchor has 4 numbered steps. A matches anchor structure most closely; B/C compress. |
| D10 | **Provenance section** | Provenance table with all six surveys + upstream commit-SHA/date columns | Bullet list of surveys, no upstream provenance details ("cited inline above") | Prose form with relative paths to surveys | Form choice; A is the most thorough. | Anchor has its own "Provenance" section listing the six surveys. A's table format is additive but doesn't conflict. |
| D11 | **Reading-mode mnemonic** | None | Explicit: "central is what's true; local is what was thought." | None | Phrasing additive; B-only. | Not in anchor; B's compression of the central/local distinction. |
| D12 | **Closing summary** | None — ends on "Provenance" | None — ends on "Provenance" | Has explicit "Summary Rule" section: "If the document says what gc-toolkit believes now, file it in `docs/`…" | Form choice; C-only. | Not anchor-specified. C's compression is consistent with anchor substance. |
| D13 | **`Spec-Kit hosts one workflow; gc-toolkit hosts many` reasoning** | Explicit paragraph explaining why fixed-filename-per-workflow doesn't fit gc-toolkit (multiple workflows simultaneously) | Doesn't include this reasoning | Doesn't include this reasoning | Phrasing/depth additive; A-only. | Anchor's "Local tier" section says "Fixed filenames are workflow-specific" but doesn't argue from "many workflows." A's reasoning is additive. |
| D14 | **Cross-source convergence callout for two-roots** | "Of the surveyed sources, the two with the most-developed AI-driven workflows agree on this shape" | "Spec Kit and Kiro — the two surveyed sources with the most-developed AI-driven workflows" | "the convergence is the separate specs workspace, not nesting specs under reference docs" | Phrasing; same point. | Anchor: "Spec Kit + Kiro convergence — the two surveyed sources with the most-developed AI-driven workflows." A and B match anchor phrasing; C abstracts. |
| D15 | **Drafts of asymmetry framing (loose vs deliberate)** | Stated as steps; no analogy | Adds: "It mirrors the spec-→-code transition in software: cheap to explore, expensive to commit." | "Treat central docs like code: be deliberate about docs, decide what belongs there, review it, and keep it current." | Phrasing additive; B's analogy and C's "treat like code" line are anchor-grounded ("Items in `docs/` are deliberate, like code") but worded differently. | Anchor: "Items in `docs/` are deliberate, like code." Both B and C echo this. |

**Summary of real disagreements** (rows flagged "Real" above):
D2 (`docs/design/`/`docs/notes/` explicit rules), D3 (bead-hierarchy
nesting), D6 ("What's deliberately not here" bundling), D7 (no
top-level meta-doc index for `docs/`).

D2 and D3 are **omissions** in C (and partially B). D6 is a **form**
choice. D7 is the only **content addition** in A not grounded in
the anchor.

## 4. Unique-to-one

Ideas/rules surfaced by only one draft. "Adopt-by-default?" notes
whether the omission in the other two looks intentional or accidental
based on anchor content.

| Source | Unique claim | Evaluation |
|---|---|---|
| **A** | "No top-level meta-doc index for `docs/`" rule | **Not in anchor.** Likely well-intentioned ("the directory listing is the index") but represents A introducing a rule beyond the anchor's scope. Operator call. |
| **A** | Provenance table with upstream commit-SHA + date columns | Additive form; consistent with anchor's call for "upstream commit-SHA provenance" carried by surveys. Useful as a binding-doc reference; B and C reasonably defer to the surveys' own provenance. |
| **A** | "What's deliberately **not** here" bundled section | Form choice. Makes rejections visible/un-relitigatable in one place. B and C distribute rejections; their distribution is also legitimate. |
| **A** | "Spec Kit hosts one workflow; gc-toolkit hosts many" reasoning for filename flexibility | Additive analytical content. Strengthens the "fixed-filenames-are-workflow-specific" rule. B and C state the rule without this argument. |
| **B** | Comparison with Spec Kit `.specify/` and Kiro `.kiro/` hidden-dir conventions | Additive. Useful for readers who know those tools. Anchor doesn't mention hidden dirs but the analysis is consistent with anchor. A and C don't address. |
| **B** | "description is *not* a body summary" + Superpowers' "Use when …" failure-mode reference | Additive. Useful guidance for *writing* descriptions. Anchor mentions discoverability hook without elaboration. A and C reasonably treat the rule as self-evident. |
| **B** | Reading-mode mnemonic: "central is what's true; local is what was thought." | Phrasing-level. Memorable compression of the central/local distinction. Easily portable to whichever final draft. |
| **B** | Spec-→-code asymmetry analogy for drafts vs central docs | Phrasing-level. Anchor's "Items in `docs/` are deliberate, like code" is the seed. |
| **C** | "Summary Rule" section as a one-paragraph crystallization | Form choice. Useful for a binding `docs/document-spec.md` that wants a memorable closer. A and B end on Provenance/open questions. |
| **C** | "AI and tooling" as the reader of cross-bead-research queries | Phrasing-level. A says "AI + tooling" similarly. Probably intended convergent. |
| **C** | Heaviest per-claim citation density (multiple `[Source: ...]` after single claims) | Form choice. Most rigorously sourced but visually noisier. A and B cite less densely. |

**Adopted-only-if-operator-decides:**
- A's "no top-level meta-doc index" rule (D7) — a new rule beyond the
  anchor.
- A's "What's deliberately not here" structural device (D6) vs B/C's
  distributed rejections — form choice.
- C's "Summary Rule" closer — form choice.

**Likely safe to adopt regardless of which draft becomes canonical:**
- B's reading-mode mnemonic.
- B's discoverability-hook elaboration.
- A's provenance table format.

## 5. Faithfulness-to-anchor check

Each draft assessed for traceability to `decisions.md`.

**Draft A** — High faithfulness. All structural rules trace directly
to anchor sections. Anchor's "What v2 should do differently from v1"
checklist is reflected nearly point-for-point. **One drift:** "No
top-level meta-doc index for `docs/`" (D7) is a rule not in the
anchor. Mild invention; defensible as a corollary of "flat by default"
but anchor does not say it.

**Draft B** — High faithfulness. All rules trace to anchor. Several
elaborations beyond the anchor (Diátaxis sub-section, hidden-dir
comparison, discoverability-hook failure-mode discussion, spec-→-code
analogy) are framing extensions, not contradictions. No content
inventions or contradictions detected.

**Draft C** — Substantively faithful but with **two omissions** of
anchor-specified rules:

1. **Bead-hierarchy nesting rule absent** (D3). Anchor's "Bead
   hierarchy: default flat, optional nesting" section gives an
   explicit rule and example; C does not include this rule. A reader
   of C would not learn that optional nesting is allowed when a parent
   bead has co-considered design alternatives.
2. **`docs/notes/` doc-type drop not stated** (D2). Anchor explicitly
   says "No `docs/notes/` doc-type." C generalises to "Do not create
   standing central doc-type directories like `docs/design/` or
   `docs/research/`" — and `docs/research/` is not the
   anchor's example for that rule. The principle is preserved; the
   specific examples drift.

C's omissions are consistent with its tighter form (compressed for
brevity) but mean the final v2, if compressed from C alone, would
need these rules added back from anchor.

No draft contradicts the anchor. No draft proposes changes to it.
The faithfulness deltas are: A adds one rule beyond anchor; B
elaborates without adding rules; C omits two anchor-specified rules.

## 6. Length / clarity / form notes

**A (499 lines)** — Most exhaustive. Most cross-source citations.
Provenance table is the most thorough. Reads as "every rule
enumerated in its own bullet/section." Strongest as a reference text;
weakest as a compact binding doc.

**B (480 lines)** — Best prose quality of the three. The "Why not
Diátaxis" sub-section, the hidden-dir comparison, and the
discoverability-hook failure-mode paragraph are the deepest
analytical content. Reading-mode mnemonic is memorable. Slightly more
literary than A; rewards careful reading.

**C (291 lines)** — Tightest. Closest to the form of a final binding
`docs/document-spec.md`. "Summary Rule" closer is the kind of
crystallization a compact spec wants. Risk: omits two anchor-specified
rules (D2, D3); a compression from C alone would need to recover them.

**Compressibility for `docs/document-spec.md`:**

- **C** is closest to the target form already — minimal compression
  needed; one merge step would reinsert the missing rules.
- **A** has the most material to compress — every rule is enumerated,
  but compression is mechanical (drop subordinate justification,
  keep rule + brief why).
- **B** rewards a writer who values the analytical extensions;
  compression risks losing the elaborations that distinguish it.

**Cleanliness for a future binding doc** (subjective):

- **C** for "what's the final spec going to look like" — already in
  that shape.
- **A** for "what's the comprehensive reference" — most rules
  surfaced.
- **B** for "which one teaches a reader to *use* the spec" — best
  prose, deepest reasoning per rule.

The three drafts are not in conflict on substance. The remaining
operator decisions are the divergences flagged in §3 (especially D2,
D3, D6, D7) and the form choices flagged in §4.
