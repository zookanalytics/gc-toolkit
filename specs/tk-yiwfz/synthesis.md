---
name: gc-toolkit File-Structure Synthesis
description: Where files belong in gc-toolkit — central authoritative `docs/` and local bead-keyed `specs/<bead-id>/`, with rules for filing, frontmatter, cross-doc references, and drafting flow.
---

# File-Structure Synthesis

## Why this spec exists

Two reasons, both load-bearing.

**Files end up everywhere.** Tools drop their output wherever convenient
— `.prd-reviews/`, `.specs/`, `.bmad-output/`, repo-root scratch files.
Once that practice sets in, no reader (human or AI) can answer "where
is X filed?" without grepping the whole tree. The remedy is a single
canonical layout that any author — human writing by hand, AI invoking
a workflow — can follow without thinking.

**gc-toolkit has to model the rule it asks others to follow.** This
spec is for gc-toolkit *itself* before it is for anyone vendoring the
pack. If we want downstream tools and agents to file where we say,
gc-toolkit has to demonstrate the discipline first. There is no
standing to ask otherwise.

The frustration alone would justify a layout. The self-discipline
makes that layout something we hold ourselves to before we publish
it.

## Use-cases drive structure

Most doc specs open by enumerating doc-types observed across reference
projects, then pick locations for each. That order produces a taxonomy
that fits the inventory and only incidentally fits the way readers
actually look up information.

This spec inverts the order: open with the queries readers (human and
AI) need to make, then derive filing rules so each query has one
obvious answer.

| Query | Reader | Filing rule it implies |
|---|---|---|
| "What is the architecture / convention / principle for X?" | human + AI | Central tier: predictable path under `docs/`, refreshed in place. |
| "What was decided in the work on bead Y?" | human + AI | Local tier: per-bead directory keyed by bead-ID. |
| "What's been researched on topic T?" | human + AI | Whichever tier the research lives in: cross-bead-query the local tier; cite where authoritative conclusions made it into central docs. |
| "What docs descend from epic E or bead B?" | AI + tooling | Bead-graph (via `bd dep`/`bd show`) plus filesystem prefix: every doc in `specs/B/` is part of B's tree. |
| "Why was decision D made?" | human | `git blame` → commit → bead reference → bead description. |
| "I need to file a new \<thing\>." | human + AI author | If it's durable and one-of-a-kind: central. If it's tied to a piece of work: local under that work's bead-ID. |
| "Loading context for task X." | AI | Frontmatter `description` is crisp enough that grep/cross-bead query returns the right set. |

The rules below fall out of this table. Each filing rule earns its
keep by answering at least one of these queries cheaply and
unambiguously.

## Two epistemic tiers: central authoritative, local historical

*Mnemonic: central is what's true; local is what was thought.*

The deepest distinction in this spec is not where docs *live* — it is
what docs *claim*.

**Central docs (`docs/`) are authoritative.** They speak what is true
*now*. Their job is to describe how gc-toolkit works today. If a
central doc is wrong, the doc is the bug, and the fix is to update
the doc. A reader (human or AI) can cite a central doc as ground
truth and act on it.

**Local docs (`specs/<bead-id>/`) are historical record.** They
capture what was thought, proposed, decided, or considered at a
moment of work. They may be wrong, outdated, never-pursued ideas,
abandoned threads, half-formed drafts. A reader **cannot** cite a
local doc as ground truth without first reading the bead's context
(current? superseded? abandoned? still in flight?). A decision
recorded inside a bead applies to that bead's scope only, and only
while known to be current.

Local docs are **relevant when linked-to**. The typical access
pattern is: "this change descends from bead Y" → read bead Y's local
docs to understand context → don't generalise from them. A current
authoritative central doc may link back to a closed bead's local docs
for the "why this is the way it is" history; that link is the entry
point, not a free-standing claim of truth.

This distinction grounds the no-archiving rule below: a closed bead
doesn't change the truth-status of its docs, because those docs were
*always* historical record, never authoritative. There is nothing to
"archive" because nothing was ever in an active state to begin with.

### Why not Diátaxis

Diátaxis (tutorials / how-to / reference / explanation) is a
human-centric framing — its categories partition docs by *which mode
of human learning is happening when the doc is read*. BMAD adopts it
verbatim for its user-facing site
[Source: docs/research/naming-conventions/bmad-method.md#directory-structure].

For a spec that has to serve human and AI readers together, the
relevant axis is not "what learning mode is this" but
**when does this doc enter the context window**. Central docs enter
on demand for any agent working in this codebase; they are
authoritative reference. Local docs enter only when the agent is
working a related bead or following a link from another doc; they
are work-history that informs *that* bead's decisions.

The central/local-by-temporal-binding split is closer to context-load
semantics than Diátaxis is, and is therefore the AI-friendlier choice.
That is why this spec adopts it.

## Two roots: `docs/` and `specs/`

Both at the repo root. **Not** `docs/specs/`.

```
<repo-root>/
├── docs/                  central, refreshed-in-place, authoritative
│   ├── file-structure.md
│   ├── principles.md
│   └── …
└── specs/                 local, bead-keyed, historical
    ├── tk-yiwfz/
    │   ├── decisions.md
    │   └── synthesis.md   (this file)
    └── tk-foo/
        ├── spec.md
        └── plan.md
```

Humans and AI go to `docs/` for durable reference, `specs/` for work
artifacts. Clean and predictable.

Three reasons converge on this shape:

1. **Cross-source convergence.** Spec Kit and Kiro — the two surveyed
   sources with the most-developed AI-driven workflows — both put
   per-feature work directly under `specs/`, not nested inside a
   broader docs tier. Spec Kit writes `specs/<NNN>-<short-name>/`
   [Source: docs/research/naming-conventions/spec-kit.md#output-document-types-—-inventory];
   Kiro writes `.kiro/specs/<feature-name>/`
   [Source: docs/research/naming-conventions/kiro.md#directory-structure].
   The two reference projects most invested in agentic
   per-feature workflows agree.

2. **Different rules want different roots.** Central docs are
   refreshed-in-place, carry no bead-ID, are durable, and are
   one-per-concern. Local docs are bead-keyed, write-once-evolve,
   carry flexible filenames, and accumulate. Putting both under one
   parent (`docs/specs/`) implies they share rules; putting them
   under separate roots makes the rule-shift explicit at the path.

3. **Spec-Kit-aware tools file into `specs/` without reconfiguration.**
   That eliminates exactly the friction this spec exists to remove. If
   gc-toolkit nested specs under `docs/`, every Spec-Kit-aware tool
   would need an override.

The repo therefore has two top-level buckets a reader (human or AI)
can name without ambiguity: `docs/` for *what is true*, `specs/<id>/`
for *what we did*.

This is a deliberate departure from Spec Kit's `.specify/` and Kiro's
`.kiro/` hidden-dir conventions. Their hidden dirs hold
toolkit-managed state alongside the user-edited specs; gc-toolkit
already separates runtime state into `.gc/`, so the docs-vs-runtime
boundary is already drawn at a different axis. Keeping `specs/`
visible matches the spec's ambition that any tool — Spec-Kit-aware
or otherwise — can find work in the obvious place.

## Inside `docs/`

The central tier hosts refreshed-in-place authoritative content: one
file per durable concern, flat at `docs/<topic>.md` by default —
`docs/file-structure.md`, `docs/principles.md`, `docs/architecture.md`,
and so on. Each file is kept current; the live doc is the truth.

Promote `docs/<topic>.md` to `docs/<topic>/<sub-topic>.md` only when
3–5 sibling sub-topics warrant a directory. The single
`docs/principles.md` becomes a `docs/principles/` directory only if
multiple sibling principle docs emerge, and the move happens then,
not pre-emptively.

**Design docs split.** Material that is durable and authoritative
("this is what a consult looks like") lives at central tier as
`docs/<topic>.md`. A work-iteration proposal — one bead exploring
shape and tradeoffs — lives at `specs/<bead-id>/proposal.md`. The
"design proposal" doc-type doesn't earn a standing central directory;
it splits according to which tier each instance belongs to.

**Notes are bead-tied.** A working note exists in service of some
piece of work; it goes under that work's bead-ID at
`specs/<bead-id>/`. There is no `docs/notes/` doc-type, and the
central tier is not the place for working notes.

**Research is bead-tied.** A research bead's outputs — surveys,
investigations, comparative analyses — are by definition tied to the
work that produced them. They go under `specs/<bead-id>/`. The
central tier is for refreshed-in-place authoritative conclusions; if
a bead's research drives an authoritative position, the position
graduates as a section of (or a new) `docs/<topic>.md`, while the
research itself stays at the bead. The central tier does not host
surveys or investigations.

**Bead-IDs do not appear in central docs.** Not in frontmatter, not
in body. Central docs are about the project as it is, not about the
bead that produced any given revision. Lineage lives in git history
(commit → PR → bead reference); the central doc itself states what
is true now.

## Inside `specs/`

### Default: bead-keyed directories

The canonical form is `specs/<bead-id>/`. Each bead that produces
filing creates its own directory; the bead IS the directory. This
is the gc-toolkit-native pattern, the one the rest of this spec is
built around, and the one that earns the
"path-as-bead-anchor" reference mechanism (see **Cross-doc
references** below).

### Accommodation: topic-or-feature directories

`specs/<topic-or-feature>/` is allowed for non-bead-tied local work:
contributors who haven't started a bead, vendoring users who don't
run the gc-toolkit bead workflow, pre-bead content waiting to be
adopted into a bead, and migration of historical content into the
new layout. Same flat-by-default rules apply inside.

The accommodation keeps the bead-keyed form canonical without making
the spec hostile to users who don't use beads, and matters
particularly for migrating pre-bead content into the layout this
spec describes.

### Directory name = bead-ID alone

`specs/tk-yiwfz/`, **not** `specs/tk-yiwfz-document-spec/`.

The bead-ID is the stable anchor. Bead titles drift as scope
clarifies; descriptive folder suffixes encode an early-bead title
that may no longer fit by the time the bead closes. A descriptive
suffix would force a rename whenever the bead's framing shifts and
break every external reference to the path. The bead-ID is fixed at
creation; let it carry the identity.

If a future workflow surfaces a concrete need for descriptive folder
names (e.g., feature folders that humans navigate by name more than
by bead), revisit. Until then: bead-ID only.

### Bead hierarchy: default flat, optional nesting

Bead dirs sit flat as siblings under `specs/`. The bead-ID
(`tk-yiwfz.4`) already encodes the parent reference; the filesystem
doesn't need to repeat it. `specs/tk-yiwfz/` and `specs/tk-yiwfz.4/`
flat is the default.

Optional nesting (`specs/tk-parent/{tk-parent.1/, tk-parent.2/}`) is
allowed when the parent–child relationship is durable and physical
co-location aids the reader. Example: four design alternatives
filed under one parent design-iteration bead, each a fully-fleshed
alternative with its own mockups; siblings under the parent dir aid
review.

The rule of thumb: if a reader landing on the parent dir should see
the children automatically because they're considered together,
nest. Otherwise stay flat.

### Files inside a bead dir are flat by default

Multiple proposal files, alternative mockups, scratch notes,
ad-hoc reviews — all sit at one level inside the bead directory.

```
specs/tk-design-iter/
├── proposal.md
├── mockup-1.html
├── mockup-2.html
├── notes.md
└── review-feedback.md
```

Don't force sub-directories for grouping. If a workflow eventually
demonstrates that nesting carries its weight, the workflow can
introduce it. The default is flat.

### Filenames inside bead dirs are workflow-specific conventions

Specific workflows converge on conventional filenames:
Spec-Kit-shaped feature work tends toward `spec.md`, `plan.md`,
`tasks.md`; a synthesis bead toward `synthesis.md`; a design bead
toward `proposal.md`. These conventions emerge for the workflows
that need them, and they are useful precisely because a workflow
knows what it expects to find.

This spec **does not prescribe a master list** of fixed filenames.
Naming a doc `spec.md` because "everyone names spec docs that"
beats inventing a slug; naming it `something-specific.md` because
the bead has many docs is also fine. We avoid defining things before
they need to be defined.

What is required: the doc's `description` frontmatter field has to
make the doc findable, since the filename is no longer a typing
convention. See **Frontmatter** below.

## Filename and path discipline

### Location is set at file-time

A doc's path is fixed when the file is written and never changes
based on lifecycle state. A bead's state — open, in-progress,
closed, abandoned — is the lifecycle marker. The bead carries that
signal; the filesystem does not duplicate it. A closed bead's docs
stay exactly where they were filed.

The convergent finding across surveyed sources — BMAD, Superpowers,
Kiro, Spec Kit all converge on no archive directory, with deletion
plus git history as the retirement path
[Source: docs/research/naming-conventions/bmad-method.md#doc-type-taxonomy]
— validates this practically; the central-vs-local epistemic
distinction explains why it is correct: a closed bead doesn't change
the truth-status of its docs (they were always historical record),
so there is nothing to archive *from*. A "stale" doc is just a doc
whose bead status the reader can check via tooling.

### Versioning is git

Docs roll forward. The live doc is the version; git history is the
revision trail. Filenames carry no version segment, principle docs
carry no semver footer, and amended docs carry no
sync-impact-report comments.

If a release-frozen snapshot is genuinely needed, address it by git
tag plus a pointer line in the live doc, not a duplicated file.
Gas Town's `gas-city-pack-v2.md` is a 1-of-6 case among the surveyed
sources
[Source: docs/research/naming-conventions/gastown.md#filename-patterns];
Spec Kit's constitution.md is the only surveyed source with a
built-in semver footer
[Source: docs/research/naming-conventions/spec-kit.md#constitution-—-constitutionmd-templatesconstitution-templatemd].
Inheriting either apparatus is overhead gc-toolkit doesn't currently
face the problem of, and the **versioned-reference doc-type** from
v1 collapses entirely.

### Timestamps: rare, only when content is genuinely temporal

Beads timestamp the work. Git timestamps the commits. Filesystem
timestamps duplicate that without adding sortability `ls` doesn't
already give.

**Default: no date in filenames.** The standard case has nothing to
gain.

**Allowed when the content is genuinely temporal.** A research bead
producing a snapshot of the state of upstream BMAD as of 2026-05-01
may use a timestamp in its output to pin the snapshot. The timestamp
is part of the doc's *meaning*, not a generic disambiguator.

**Not required, not promoted.** Don't reach for a date prefix as a
default; for almost every doc it is the wrong tool.

## Frontmatter

Frontmatter is `name` + `description` only — these two fields, no
others.

```yaml
---
name: <descriptive name>
description: <one-line discoverability hook>
---
```

- **Mandatory on local spec docs.** Filenames inside `specs/<bead>/`
  are flexible; the description carries the searchable text for
  cross-bead queries and is the discoverability hook tooling can
  rely on.
- **Strongly encouraged on central docs.** A topic-shaped filename
  can lie about what the doc covers; the description keeps that
  honest.

The `description` field is a **discoverability hook**, not a summary
of the doc's body. Superpowers' "Use when …" discipline for skill
descriptions
[Source: docs/research/naming-conventions/superpowers.md#well-named-patterns-with-reasoning]
documents the failure mode: when descriptions summarise the body, AI
agents follow the description instead of reading the body. For docs
this matters less directly, but the same instinct applies — write a
description that helps grep find the right doc, not one that
restates its content.

For spec docs the bead-ID is in the path; for central docs there is
no bead-ID at all (their lineage is in `git blame` → commit → bead
reference). Either way, frontmatter does not carry the bead-ID.

## Cross-doc references

Three reference mechanisms cover the cases this spec exhibits:
markdown relative-path links, path-as-bead-anchor for spec docs, and
`[Source: <path>#<section>]` citations for synthesis provenance.

### 1. Markdown relative-path links

For forward references between docs in the repo. The prevailing
convention; kept.

```markdown
See [decisions](../tk-yiwfz/decisions.md) for the directional calls
this synthesis anchors against.
```

### 2. Path-as-bead-anchor

For spec docs, the bead identity is in the path: a doc at
`specs/tk-foo/spec.md` is reachable by its path, and the bead-ID is
the directory name. No separate inline-citation convention is needed
for "this doc descends from bead X" — the path says it.

This is gc-toolkit's principal departure from the surveyed reference
projects, all of which converge on "path is the identifier"
[Source: docs/research/naming-conventions/bmad-method-templates.md#central-vs-local-documents].
The departure is justified: gc-toolkit's beads system already tracks
work units with stable global IDs, and not using those IDs would
forfeit gc-toolkit's strongest cross-doc anchor.

### 3. `[Source: <path>#<section>]` citations

When one doc draws facts from another and the reader benefits from
inline provenance, cite the source path and section anchor. Borrowed
from BMAD's story-template convention
[Source: docs/research/naming-conventions/bmad-method-templates.md#cross-doc-reference-scheme].

```markdown
The convergent finding across all surveyed sources is no archive
directory [Source: docs/research/naming-conventions/bmad-method.md#doc-type-taxonomy].
```

This document uses citations exactly that way, and so should any
synthesis or principle doc that aggregates facts from multiple
research surveys.

## Drafting and adoption

**`specs/` is loose. `docs/` is deliberate.**

A new bead can freely write just about anything into its
`specs/<bead-id>/` directory. The local tier is a workspace; drafts,
half-formed proposals, scratch notes, and dead ends are all
appropriate. The cost of filing a doc there is intentionally low —
that is what enables fluid work.

A central doc, by contrast, is committed to with the same care as
code. New entries to `docs/` arrive through review, not through
unilateral filing. The path the central tier intends:

1. **Draft in `specs/<bead-id>/`** until the operator and contributors
   agree the content is ready to claim authoritative status.
2. **Adoption PR** lifts the compact, distilled version into
   `docs/<topic>.md` and updates whatever discoverability surface
   needs to point at it (mechanik prompt, README, sibling docs).
3. **Migration of the existing tree** to the layout this spec
   describes is a separate bead with its own scope. It does not run
   inside this synthesis.

The asymmetry — loose drafts, deliberate central docs — is part of
the design, not a temporary compromise. It mirrors the
spec-→-code transition in software: cheap to explore, expensive to
commit.

## Open questions

These are not blocking adoption but warrant their own bead when the
need surfaces.

### Top-level `CLAUDE.md` for users vendoring gc-toolkit

gc-toolkit currently has `CLAUDE.md` files scoped to individual
agents (`agents/<name>/`). A repo-root `CLAUDE.md` aimed at users who
vendor gc-toolkit into their own city is a separate concern and
hasn't been written. When demand for one materialises, the question
of where it lives (root, `docs/`, or both via the
`AGENTS.md`-as-symlink pattern Superpowers uses
[Source: docs/research/naming-conventions/superpowers.md#filename-patterns])
becomes load-bearing.

### Cross-bead query tooling

With `description` as the discoverability hook for spec docs, a
gc-toolkit-specific wrapper that grep-walks `specs/*/*.md`
frontmatter and surfaces docs by description (or by bead status,
labels, dependencies) becomes useful. This is follow-on work, not
part of the spec itself.

### Code-adjacent documentation

A README inside a package describing its architecture, a `.md` file
sitting next to source code. Whether such docs live entirely in
source or as standalone markdown alongside code is an open question.
Deferred until a concrete case surfaces.

## Summary

If the document says what gc-toolkit believes now, file it in
`docs/` and keep it true. If the document records work, file it in
`specs/<bead-id>/` and preserve it as context. Everything else in
this spec exists to make that decision cheap, visible, and reliable
for both humans and AI agents.
