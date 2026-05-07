---
name: gc-toolkit document spec v2 synthesis
description: Clean v2 synthesis for gc-toolkit central docs and bead-local specs.
---

# gc-toolkit Document Spec, v2 Synthesis

Files end up everywhere: `.prd-reviews/`, `.specs/`, `.bmad-output/`.
The first purpose of this spec is to make filing predictable enough
that a human or agent knows where to put a PRD, spec, proposal,
research note, or synthesis before writing it. The second purpose is
self-discipline: gc-toolkit has to model the rule it asks other tools
and agents to follow. Without that, it has no standing to ask anyone
else for a cleaner tree. [Source: ../tk-yiwfz/decisions.md#why-this-work-exists]

This is an AI-facing document spec as much as a human-facing one.
Diátaxis is useful for human learning modes, and BMAD uses it directly
for its user-facing docs, but gc-toolkit adopts the
central/local-by-temporal-binding axis instead: when should this
document enter the context window? Central docs are loaded as current
truth. Local docs are loaded only through the work context that makes
them meaningful.
[Source: ../tk-yiwfz/decisions.md#ai-centric-not-human-centric]
[Source: ../../docs/research/naming-conventions/bmad-method.md#doc-type-taxonomy]

## Reader Queries Drive the Layout

The layout starts from the questions readers need answered, not from a
catalog of document genres.

| Query | Reader | Filing rule |
| --- | --- | --- |
| What is true about gc-toolkit now? | Human and AI | Read `docs/<topic>.md`; central docs are authoritative and refreshed in place. |
| What work produced this decision? | Human and AI | Follow the central doc's links and citations to `specs/<bead-id>/`; local docs are historical context. |
| What did one bead propose, research, or decide? | Human and AI | Read `specs/<bead-id>/`, then interpret it with bead state and linked context. |
| What research already exists on this topic? | AI and tooling | Search `specs/` frontmatter descriptions and source citations; future query tooling can wrap that. |
| I need to file a new artifact. | Human and AI author | If it says current truth, file in `docs/`; if it belongs to work, file in `specs/<bead-id>/`. |
| Why was this rule adopted? | Human | Use relative links, `[Source: ...#section]` citations, and git blame to reach the work trail. |

These queries encode the central/local split decided after v1:
central files are for durable truth; local files are for bead-tied
history. [Source: ../tk-yiwfz/decisions.md#use-cases-drive-structure]
[Source: ../tk-yiwfz/decisions.md#central-is-authoritative-local-is-historical-record]

## Two Roots

gc-toolkit uses exactly two repository-root document buckets:

```text
<repo-root>/
├── docs/                  # central, authoritative, refreshed in place
│   ├── principles.md
│   ├── document-spec.md
│   └── <topic>.md
└── specs/                 # local, bead-keyed work record
    └── <bead-id>/
        ├── synthesis.md
        ├── proposal.md
        └── plan.md
```

Do not use `docs/specs/`. `docs/` and `specs/` follow different rules
and have different epistemic status, so they deserve different roots.
Spec Kit puts per-feature work in a visible repository-root `specs/`
bucket, while Kiro puts per-feature work in a dedicated specs bucket
under `.kiro/`; the convergence is the separate specs workspace, not
nesting specs under reference docs. Keeping `specs/` at repo root also
lets Spec-Kit-aware tools file into the expected path without
reconfiguration. [Source: ../tk-yiwfz/decisions.md#two-root-layout]
[Source: ../../docs/research/naming-conventions/spec-kit.md#central-vs-local-documents]
[Source: ../../docs/research/naming-conventions/kiro.md#central-vs-local-documents]

## Central Docs: `docs/`

Central docs state what is true now. A reader can cite them as truth.
If a central doc is wrong, the doc is the bug and the fix is to update
it. [Source: ../tk-yiwfz/decisions.md#central-is-authoritative-local-is-historical-record]

Central rules:

- `docs/` is flat by default: `docs/<topic>.md`.
- One file per durable concern, refreshed in place.
- Use `docs/principles.md` for principles today; do not create a
  versioned constitution or a `docs/principles/` directory by default.
- Do not carry bead IDs in central frontmatter or as body metadata.
  The work trail is git blame, commit messages, and explicit citations
  to local docs when the provenance matters.
- Do not create standing central doc-type directories like
  `docs/design/` or `docs/research/` as defaults. A design/proposal or
  research note that belongs to work starts local. A compact adopted
  conclusion may later be written into a central topic doc.

The flat central tier follows gc-toolkit's need for a small authoritative
surface, not v1's "minimal migration" argument. BMAD and Gas Town both
show durable docs being rolled forward in place; Spec Kit and Kiro put
project-wide principles/configuration outside their per-feature specs
buckets. [Source: ../tk-yiwfz/decisions.md#central-tier-docs]
[Source: ../../docs/research/naming-conventions/bmad-method-templates.md#central-vs-local-documents]
[Source: ../../docs/research/naming-conventions/gastown.md#lifecycle-markers]
[Source: ../../docs/research/naming-conventions/spec-kit.md#central-vs-local-documents]

## Local Specs: `specs/<bead-id>/`

Local docs are historical record. They record what was proposed,
researched, considered, or believed during a piece of work. They may be
right, wrong, superseded, abandoned, partial, or useful only because a
central doc links to them. A reader cannot cite a local doc as truth
without checking bead context. [Source: ../tk-yiwfz/decisions.md#central-is-authoritative-local-is-historical-record]

Local rules:

- The directory name is the bead ID alone: `specs/<bead-id>/`.
  Use `specs/tk-yiwfz/`, not `specs/tk-yiwfz-document-spec/`.
  Do not append a descriptive suffix. Meaningful names drift as work
  changes; bead IDs do not. [Source: ../tk-yiwfz/decisions.md#bead-directory-naming-bead-id-only]
- Files inside a bead directory are flat by default. Do not force
  `research/`, `proposals/`, `alternatives/`, or similar subdirectories
  just to make the tree look organized. A workflow can introduce a
  subdirectory when it has a concrete reason. [Source: ../tk-yiwfz/decisions.md#local-tier-specs]
- Fixed filenames are workflow conventions, not universal mandates.
  `spec.md`, `plan.md`, `tasks.md`, `proposal.md`, and `synthesis.md`
  are good names when a workflow has made them meaningful. The document
  spec does not prescribe a master filename list before the workflow
  needs it. [Source: ../tk-yiwfz/decisions.md#local-tier-specs]
- Location is set when the file is written and never changes because
  the bead changed state. There is no archive directory and no archive
  sweep. A closed bead's docs were already historical record; closing
  the bead does not make them more or less authoritative.
  [Source: ../tk-yiwfz/decisions.md#no-file-movement-based-on-lifecycle]
- Timestamps are not generic disambiguators. Use one only when the
  document is explicitly about a point in time, such as the state of
  upstream BMAD on May 1, 2026. They are allowed, not required, and
  not promoted as a default. [Source: ../tk-yiwfz/decisions.md#timestamps-and-dates-rare-only-when-content-is-about-a-point-in-time]

Spec Kit and Kiro both keep per-feature planning and implementation
tracking together in one spec directory; Superpowers keeps completed
plans/specs in place rather than archiving them; BMAD's local
many-per-project artifacts vary by ID, slug, or date because they are
work records rather than central truth. gc-toolkit adopts the same
"work bucket stays put" principle, but uses bead IDs instead of local
feature names, ordinal prefixes, or date-slugs. [Source: ../../docs/research/naming-conventions/spec-kit.md#project-feature-scope-unit]
[Source: ../../docs/research/naming-conventions/kiro.md#project-feature-scope-unit]
[Source: ../../docs/research/naming-conventions/superpowers.md#whats-not-a-lifecycle-marker]
[Source: ../../docs/research/naming-conventions/bmad-method-templates.md#central-vs-local-documents]

## Versioning

Versioning is git.

Do not add `-v<N>` suffixes to filenames. Do not add a semver trailing
line to principle docs. Do not add sync-impact-report HTML comments.
v1's "versioned reference" doc-type collapses into either a
living central doc or a git tag with a pointer from the living doc when
a release-frozen snapshot is genuinely needed. [Source: ../tk-yiwfz/decisions.md#versioning-is-git]

Gas Town has a versioned reference example and Spec Kit versions its
constitution, but neither pattern generalizes across the six sources.
BMAD and Superpowers use release notes/changelogs for package releases,
not per-doc version suffixes. [Source: ../../docs/research/naming-conventions/gastown.md#lifecycle-markers]
[Source: ../../docs/research/naming-conventions/spec-kit.md#lifecycle-markers]
[Source: ../../docs/research/naming-conventions/bmad-method.md#lifecycle-markers]
[Source: ../../docs/research/naming-conventions/superpowers.md#lifecycle-markers]

## Frontmatter

Use exactly two frontmatter fields:

```yaml
---
name: <human-readable name>
description: <one-line discovery description>
---
```

This frontmatter is mandatory for spec files because filenames inside
`specs/<bead-id>/` are intentionally flexible and `description` is the
cross-bead discovery hook. It is strongly encouraged for central docs,
where it helps a reader or search tool understand the file's coverage
without trusting the filename alone. [Source: ../tk-yiwfz/decisions.md#frontmatter]

Do not adopt `inclusion`, `fileMatchPattern`, `handoffs`, or a
`bead-id` field as part of this document spec. Kiro's steering
frontmatter is valuable for a Kiro-specific loading model, and Spec
Kit's command `handoffs` are valuable for command-palette workflow
suggestions, but gc-toolkit is not standardizing those semantics for
documents today. Superpowers and Kiro skills converge on
`name` + `description` as the discovery surface; that is the part
gc-toolkit adopts. [Source: ../../docs/research/naming-conventions/kiro.md#steering-documents-kiro-specific]
[Source: ../../docs/research/naming-conventions/spec-kit.md#command-files-specifytemplatescommandsnamemd]
[Source: ../../docs/research/naming-conventions/superpowers.md#frontmatter-on-skills-functional-not-lifecycle]
[Source: ../../docs/research/naming-conventions/kiro.md#skill-skillmd]

## Cross-Document References

Use three mechanisms:

1. Markdown relative links for ordinary navigation:
   `[text](relative/path.md)` or `[text](relative/path.md#section)`.
2. Path-as-bead-anchor for local docs: the path
   `specs/<bead-id>/<file>.md` is the bead anchor. Do not repeat the
   bead ID in frontmatter.
3. `[Source: <path>#<section>]` citations when one doc draws facts from
   another and provenance matters.

Reject these as defaults:

- Numbered IDs inside docs as cross-doc identity.
- Filename pairing by shared slug and date.
- Glob discovery as the primary resolution mechanism.
- Live-file embeds such as Kiro's `#[[file:<path>]]`.

The adopted set keeps the plain markdown behavior common across the
sources, borrows BMAD's explicit `[Source: ...#section]` citation for
synthesis work, and uses gc-toolkit's bead-keyed paths for local
history. The rejected set is either brittle under reordering (Spec Kit
`[US1]`, Kiro requirement numbers), redundant with bead IDs and git
timestamps (shared slug/date pairing), ambiguous at runtime (BMAD
globs), or harness-specific (Kiro live embeds). [Source: ../tk-yiwfz/decisions.md#cross-doc-references]
[Source: ../../docs/research/naming-conventions/bmad-method-templates.md#cross-doc-reference-scheme]
[Source: ../../docs/research/naming-conventions/spec-kit.md#cross-doc-reference-scheme]
[Source: ../../docs/research/naming-conventions/kiro.md#cross-doc-reference-scheme]
[Source: ../../docs/research/naming-conventions/superpowers.md#well-named-patterns-with-reasoning]

## Drafting, Adoption, and Migration

Drafts in `specs/` are loose by design: "we can freely write just about
anything" into a bead folder. A bead directory can hold rough research,
alternative proposals, temporary synthesis, screenshots, and notes while
the work is still being understood. That looseness is why local docs are
not authority. [Source: ../tk-yiwfz/decisions.md#drafting-and-adoption-flow]

Adoption is deliberate. The adoption PR writes the compact central
version at `docs/document-spec.md` and updates agent-discoverability
surfaces so future authors and agents can find it. Treat central docs
like code: be deliberate about docs, decide what belongs there, review
it, and keep it current.
[Source: ../tk-yiwfz/decisions.md#drafting-and-adoption-flow]

Migration of the existing tree is separate work. This spec says what
the target convention is; it does not sell the target by minimizing
moves, and it does not bundle the migration into the synthesis.
[Source: ../tk-yiwfz/decisions.md#strip-existing-practice-anchoring]
[Source: ../tk-yiwfz/decisions.md#drafting-and-adoption-flow]

## Provenance

This synthesis uses `../tk-yiwfz/decisions.md` as the authority for
directional defaults, the six survey files under
`../../docs/research/naming-conventions/` as cross-source evidence,
and `../../docs/principles/document-spec.md` as v1 context only. It
does not re-survey upstream projects; the survey files carry the
upstream commit-SHA provenance. Every cross-source claim above cites
the survey file it draws from, while every gc-toolkit-specific default
cites the decision record or the cross-source convergence that grounds
it. [Source: ../tk-yiwfz/decisions.md#provenance]
[Source: ../tk-yiwfz/decisions.md#what-v2-should-do-differently-from-v1]

## Resolved Decisions

| Question | Resolution |
| --- | --- |
| Q1: Single principles/constitution shape? | Use one `docs/principles.md` today. No constitution-versioning default. |
| Q2: Hidden config directory for doc-state? | Deferred. Defaults are the contract; no hidden config dir today. |
| Q3: Frontmatter shape? | `name` and `description` only. |
| Q4: Bead IDs in frontmatter or body? | Neither as metadata. For spec docs the bead ID is in the path; central docs do not carry bead IDs. |
| Q5: Timestamps? | Default no. Allowed only when the content is genuinely temporal. |
| Q6: `removals.txt`? | Deferred. Beads can carry removal and rename context for now. |
| Q7: `CHANGELOG.md` / `AGENTS.md`? | CHANGELOG deferred until release cadence. AGENTS.md for this repo is mechanik, not a document. |
| Q8: `docs/escalation/` doc-type? | Dissolved into the per-bead `specs/<bead-id>/` model. |
| Q9: Cross-source conflicts? | None remain after the directional decisions. |

[Source: ../tk-yiwfz/decisions.md#resolved-open-questions-from-v1]

## Remaining Open Questions

Two questions remain real but non-blocking:

- Whether gc-toolkit should provide a top-level `CLAUDE.md` for users
  vendoring gc-toolkit.
- What cross-bead query tooling should exist over `specs/`, likely as
  a gc-toolkit-specific wrapper rather than a raw convention.

[Source: ../tk-yiwfz/decisions.md#newly-surfaced-and-resolved-questions]

## Summary Rule

If the document says what gc-toolkit believes now, file it in `docs/`
and keep it true. If the document records work, file it in
`specs/<bead-id>/` and preserve it as context. Everything else in this
spec exists to make that decision cheap, visible, and reliable for
both humans and AI agents.
