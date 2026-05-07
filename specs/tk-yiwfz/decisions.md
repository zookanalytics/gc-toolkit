---
name: Document Spec — Decisions
description: Directional calls captured from 2026-05-06 operator/mechanik conversation; anchors v2 synthesis at specs/tk-yiwfz/synthesis.md.
---

# Document Spec — Decisions

Captured from operator/mechanik conversation on 2026-05-06. These directional
calls anchor the v2 synthesis. The v1 synthesis at
`docs/principles/document-spec.md` (filed by polecat `gc-toolkit.furiosa` against
`tk-yiwfz.4`) provides the inventory and survey provenance; this document
records what *we decided to do with that inventory*.

## Why this work exists

Tools drop output wherever they like — `.prd-reviews/`, `.specs/`,
`.bmad-output/`. Files end up everywhere. This spec commits gc-toolkit to a
single canonical layout so that any tool (human or AI) generating a PRD,
spec, research note, or proposal files predictably, and a reader/agent
always knows where to look.

**The spec also commits gc-toolkit to its own rule.** To ask other tools
and agents to file consistently, gc-toolkit has to model that behaviour
first. This is a stance we take and hold ourselves to; without
self-discipline, we have no standing to ask anyone else to follow it.

That frustration plus that self-discipline are the spec's reason for
being; v2 should open with both plainly stated.

## Framing shifts from v1

### Strip existing-practice anchoring

v1 leaned on "matches existing gc-toolkit pattern" as load-bearing rationale
in spots where cross-source evidence alone didn't support it. That produced
positions like the `-v<N>` filename suffix (only Gas Town does it, 1-of-6
sources) and "Migration notes: zero moves, maximally non-disruptive" framed
as a virtue. **Zero moves is a tell, not a virtue** — it signals the synthesis
optimised for codification rather than rightness.

v2 re-derives each default purely from cross-source evidence plus
gc-toolkit's structural features (beads, packs, `.gc/` runtime). Migration
impact is reported as a fact (separate bead handles it), not framed as a
selling point.

### AI-centric, not human-centric

For AI consumers the relevant axis is *when does this doc enter the context
window* — closer to scope/temporal-binding/producer than to learning mode.
**Diátaxis (tutorials/how-to/reference/explanation) is human-centric** and is
the wrong frame for a spec serving human + AI together. The central/local
split (refreshed-in-place vs tied-to-work) is already on the AI-friendlier
axis; v1 just stated it for weaker reasons than it should have.

### Use-cases drive structure

v1 was inventory-first (what doc-types exist across 6 platforms). v2 should
be use-case-first: derive each filing rule from a query a reader (human +
AI) needs to make. Sketch of the use-cases section:

| Use-case | Reader | Filing rule it implies |
|---|---|---|
| "What's the architecture decision for X?" | human + AI | central tier, predictable path |
| "What's the spec for feature F?" | human + AI | local tier, bead-keyed |
| "What research has been done on T?" | human + AI | flat per-type, frontmatter `description` + grep |
| "What docs are in Epic E / bead B's tree?" | AI + tooling | bead-graph via tooling, bead-id is in the path |
| "Why was decision D made?" | human | git blame → commit → bead reference |
| "I need to file a new <type>" | human + AI author | predictable type/bead path, soft conventions |
| "Loading context for task X" | AI | descriptions are crisp enough that grep returns the right set |

## Structural decisions

### Two-root layout

```
<repo-root>/
├── docs/                 (central — durable, refreshed-in-place)
│   ├── principles.md
│   ├── architecture.md
│   ├── consult.md
│   └── ...
└── specs/                (local — bead-tied work)
    ├── tk-yiwfz/
    │   ├── synthesis.md
    │   └── research/
    │       ├── bmad-method.md
    │       └── ...
    ├── tk-design-iter/
    │   ├── proposal.md
    │   ├── tk-design-iter.1/
    │   │   ├── proposal.md
    │   │   └── mockup-home.png
    │   └── tk-design-iter.2/
    └── tk-foo/
        ├── spec.md
        └── plan.md
```

**Why `specs/` at repo root, not under `docs/`:**

- Spec Kit + Kiro convergence — the two surveyed sources with the
  most-developed AI-driven workflows both use `specs/` as the per-feature
  hub; neither nests under `docs/`.
- **Different rules want different roots.** Central (refreshed-in-place,
  no bead-ID, durable, one-per-concern) and local (bead-keyed,
  write-once-evolve, flexible filenames) follow distinct rule sets.
  Same parent suggested same rules; different parents make the rule-shift
  explicit at the path.
- **Spec Kit-aware tools file into `specs/` without reconfiguration.** That's
  exactly the friction this spec exists to eliminate.
- **Two-bucket repo model.** Humans and AI go to `docs/` for durable
  reference, `specs/` for work artifacts. Clean and predictable.

### Central is authoritative; local is historical record

The deeper distinction between `docs/` and `specs/` isn't just rule-set —
it's epistemic status.

- **Central docs are authoritative.** They speak what is true. They
  describe how things actually work today. If a central doc is wrong,
  the doc is the bug, and the fix is to update the doc. A reader (human
  or AI) can cite a central doc as ground truth.
- **Local docs are historical record.** They capture what was thought,
  proposed, decided, or considered at a moment of work. They may be
  wrong, outdated, never-pursued ideas, abandoned threads, half-formed
  drafts. A reader **cannot cite a local doc as ground truth** without
  knowing the bead's context (current? superseded? abandoned?).
- **Local docs are relevant when linked-to.** "This change was made due
  to bead X" is the typical access pattern: read the bead's context,
  understand why the change was made, don't generalise from it. A
  decision recorded inside a bead applies to that bead's scope only,
  and only while known to be current.

This grounds the no-archiving rule below: a closed bead doesn't change
the truth-status of its docs (they were always historical record, never
authoritative), and a closed bead's docs may still be linked-to from a
current authoritative central doc as the "why this is the way it is"
context.

### Central tier (`docs/`)

- Single file per concern, refreshed-in-place
- Flat at `docs/<topic>.md` (no sub-directories by default)
- One `docs/principles.md` file today; promote to `docs/principles/`
  directory only when 3–5 sibling principles warrant
- **No `docs/design/` as a standing directory.** Design docs are either at
  central tier (durable topic — "this is what a consult looks like") or
  inside a bead dir (work-iteration proposal). The doc-type "design
  proposal" splits in two; it doesn't need its own central directory.
- No `docs/notes/` doc-type. All notes are bead-tied; file under
  bead+type.

### Local tier (`specs/`)

- Per-bead directory: `specs/<bead-id>/`. The bead IS the directory.
- **Files inside a bead dir are flat by default.** Multiple proposal
  files, alternative mockups, ad-hoc review docs (`mockup-1.html`,
  `mockup-2.html`, `notes.md`, etc.) all sit at one level. **Don't force
  sub-directories** for grouping. If a workflow eventually needs them,
  the workflow can introduce them.
- **Fixed filenames are workflow-specific, not universal mandates.**
  Specific workflows (or bead-types) may converge on conventional names —
  Spec Kit-shaped feature work tends toward `spec.md`, `plan.md`,
  `tasks.md`; a synthesis bead toward `synthesis.md`; a design bead
  toward `proposal.md`. These conventions emerge for the workflows that
  need them. The spec doesn't prescribe a master list. **We avoid
  defining things before they need to be defined.**
- **Frontmatter `description` is the discoverability hook.** With flexible
  filenames, the description carries the searchable text for cross-bead
  queries.

### Bead hierarchy: default flat, optional nesting

- **Default**: bead dirs sit flat as siblings under `specs/`. The bead-id
  (`tk-yiwfz.4`) already encodes the parent reference; filesystem doesn't
  need to repeat it. `specs/tk-yiwfz/` and `specs/tk-yiwfz.4/` flat is fine.
- **Optional nesting** when the parent–child relationship is durable AND
  physical co-location aids the reader. Example: 4 design alternatives
  under one parent design-iteration bead — `specs/tk-parent/{proposal.md,
  tk-parent.1/, tk-parent.2/, tk-parent.3/, tk-parent.4/}`. Each child is a
  fully-fleshed alternative with its own mockups; siblings under the parent
  dir aid review.
- **Rule of thumb**: if a reader landing on the parent dir should see the
  children automatically because they're considered together, nest.
  Otherwise stay flat.

### Bead directory naming: bead-id only

**The directory name is the bead-id alone — no additional identifiers
appended.** `specs/tk-yiwfz/`, not `specs/tk-yiwfz-document-spec/`.

Why: meaningful names change as scope shifts; bead-IDs don't. If the
bead's subject evolves over the course of the work (which it often does),
a descriptive folder name forces a rename and breaks every external
reference to the path. The bead-id is stable; the bead's title can drift
inside the bead description without affecting the filesystem path.

**Revisit only if a concrete use-case demands descriptive folder names**
(e.g., feature folders that humans navigate by name more often than by
bead). For now: bead-id only.

### No file movement based on lifecycle

**Location is set at file-time and never changes based on lifecycle state.**

- Bead state (open / closed / archived) is the lifecycle marker.
- The file's path tells you what type of doc it is and which bead it
  belongs to; that information doesn't change when the bead closes.
- **No archive directory, no archive sweep, no "done docs go here."**
  A closed bead's docs stay exactly where they were filed.
- A "stale" doc (bead closed, no longer current) is just a doc whose bead
  status the reader can check via tooling.

### Versioning is git

- No `-v<N>` filename suffix on docs.
- No trailing semver line on principles.
- No sync-impact-report HTML comments per amendment.
- **Versioned-reference doc-type (#2 in v1) collapses.** If a release-frozen
  snapshot is genuinely needed, it's a git tag plus a pointer line in the
  live doc, not a duplicated file.

### Timestamps and dates: rare, only when content is about a point in time

- **Default: no date in filenames.** Beads timestamp the work; git
  timestamps commits. That's enough for the standard case.
- **Allowed when the content is genuinely temporal.** A bead doing
  research on the state of something at a specific point in time
  (e.g., "state of upstream BMAD as of 2026-05-01") may use a timestamp
  in its output to pin the snapshot. Valid when the timestamp is part
  of the doc's meaning, not a generic disambiguator.
- **Not required, not promoted.** Don't reach for a date prefix as a
  default; it almost always isn't the right tool.
- `docs/notes/` doc-type dropped; if a working note ever needs filing
  outside a bead, add the type then.

## Frontmatter

**Universal: `name` + `description` only.** That's it.

- **Mandatory on spec files** — filenames inside `specs/<bead>/` are
  flexible; description is the discoverability hook for cross-bead
  queries and tooling.
- **Strongly encouraged on central docs** — a topic title can lie about
  what the doc covers; description keeps that honest.

**Not adopted:**

- `inclusion` / `fileMatchPattern` (Kiro): too prescriptive, harder to
  manage; better solutions to the AI-loading-axis problem will emerge.
- `handoffs` (Spec Kit): beads capture handoffs.
- `bead-id` field: redundant for spec docs (bead is in the path);
  central docs don't carry bead-IDs at all (git blame is the trail).

## Cross-doc references

Under the new layout, the v1's 3-mechanism kit simplifies:

- **Markdown relative-path links** for forward references between docs
  (`[anchor text](relative/path.md)` or `(...md#section)`). Prevailing
  pattern, kept.
- **Path-as-bead-anchor** for spec docs: a doc at `specs/tk-foo/spec.md`
  is reached by its path; the bead identity is in the path. No separate
  inline-citation convention needed for "this doc descends from bead X" —
  the path says it.
- **`[Source: <path>#<section>]` citation** when one doc draws facts from
  another and inline provenance is useful. Borrowed from BMAD's
  story-template convention. Kept for synthesis docs aggregating facts
  from multiple research surveys.

**Rejected (carries over from v1):** numbered-IDs-within-doc (FR-001,
T###), filename-pairing-by-shared-slug+date, glob-discovery,
live-file-embed (`#[[file:<path>]]`).

## Resolved open questions (from v1)

| # | Question | Resolution |
|---|---|---|
| Q1 | Single versioned constitution file? | No. Single `docs/principles.md`; versioned by git. |
| Q2 | Hidden config dir for doc-state? | Deferred. Defaults are the contract; revisit if mapping use-case appears. |
| Q3 | Frontmatter shape? | `name` + `description` only. |
| Q4 | Bead-IDs in frontmatter or body? | Neither — bead-ID is in the path for spec docs. Central docs don't carry it. |
| Q5 | Date prefixes? | Default no — beads + git timestamp work. Allowed when content is genuinely temporal (e.g., "state of X as of date"). Not required or promoted. |
| Q6 | `removals.txt`? | Deferred. Beads can carry rename/remove load. |
| Q7 | Top-level `CHANGELOG.md` / `AGENTS.md`? | CHANGELOG deferred until release cadence. AGENTS.md for *this repo* is mechanik (the agent), not a doc. Top-level `CLAUDE.md` for users vendoring gc-toolkit is genuinely open, not blocking. |
| Q8 | `docs/escalation/` doc-type? | Dissolved. Just `specs/<bead-id>/` under the new model. |
| Q9 | Cross-source conflicts? | None remain after directional calls. |

## Newly surfaced (and resolved) questions

| # | Question | Resolution |
|---|---|---|
| Q-new-1 | When does bead-iteration work graduate to a central doc? | PR step with human review, analogous to spec → code. Decisions get codified in compact form in the central doc. State explicitly in v2. |
| Q-new-2 | Migration of existing tree to new layout? | Separate bead with specific guidance; out of scope for the spec itself. |
| Q-new-3 | Use-cases section in v2? | Yes — drives structure, opens the doc. |
| Q-new-4 | Cross-bead query tooling? | gc-toolkit-specific wrapper/helper, future work; non-blocking for adoption. |

## Drafting and adoption flow

1. v2 synthesis drafted at `specs/tk-yiwfz/synthesis.md` (this directory).
   Loose iteration there; "we can freely write just about anything into a
   specs/<bead> folder."
2. Operator review and revision until happy. Drafts in `specs/` are cheap.
3. Adoption PR commits the compact central version at
   `docs/document-spec.md` and updates agent discoverability (mechanik
   prompt, README pointers, etc.). Items in `docs/` are deliberate, like
   code.
4. Separate migration bead handles re-shaping the existing tree
   (`docs/principles/`, `docs/design/`, `docs/research/`) per the new
   layout.

## What v2 should do differently from v1

- **Open with two reasons**: the "files everywhere" frustration AND the
  self-discipline point (gc-toolkit modelling the rule it asks others to
  follow). Frame the structure as serving both.
- **Use-cases section drives structure**, not inventory. Open with the
  queries readers (human + AI) need to make.
- **Drop the "matches existing pattern" rationale** wherever it appears.
  Re-derive each default from cross-source evidence + gc-toolkit's
  structural features (beads, packs, `.gc/` runtime).
- **Drop the "Migration notes: zero moves" section** as a selling point.
  Migration is a fact handled by a separate bead, not a virtue.
- **State the AI-centric framing** explicitly. Diátaxis is a fine pattern
  for human-only docs; the central/local-by-temporal-binding axis is the
  AI-friendlier choice and that's why it's adopted.
- **State the central-vs-local epistemic distinction.** Central is
  authoritative (cite as truth, fix if wrong); local is historical
  record (relevant only when linked-to, requires bead-context to
  interpret). This grounds the no-archiving rule.
- **Per-bead-directory layout** for `specs/`, not per-doc-type.
- **`specs/` at repo root**, not `docs/specs/`.
- **Bead-dir name is the bead-id alone**, no descriptive suffix —
  meaningful names drift, bead-IDs don't.
- **Files inside a bead dir are flat by default.** No forced
  sub-directories for multi-doc series. Fixed filenames (`spec.md`,
  `plan.md`, `proposal.md`, etc.) are workflow-specific conventions, not
  universal mandates. Avoid defining things before they need to be
  defined.
- **Timestamps allowed when content is genuinely temporal** (e.g., a
  point-in-time survey snapshot), not as a generic disambiguator. Not
  required, not promoted.
- **Shrink the open-questions list** to what's genuinely open
  (top-level `CLAUDE.md` for vendoring, follow-on tooling work).
- **State the no-archive rule plainly**: location is set at file-time;
  bead state is the lifecycle; a closed bead's docs don't move.

## Provenance

- **Conversation**: 2026-05-06, operator + mechanik (`gc-toolkit.mechanik`).
- **v1 synthesis**: `rigs/gc-toolkit/docs/principles/document-spec.md`
  (polecat `gc-toolkit.furiosa`, bead `tk-yiwfz.4`). Stays at v1 location
  until migration bead.
- **Six surveys feeding both v1 and v2**:
  `rigs/gc-toolkit/docs/research/naming-conventions/{bmad-method,
  bmad-method-templates,superpowers,gastown,spec-kit,kiro}.md`. Stay at
  v1 location until migration.
