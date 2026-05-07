---
name: gc-toolkit Document Spec — v2 Synthesis
description: Where files belong in gc-toolkit — central authoritative `docs/` and local bead-keyed `specs/<bead-id>/`, with rules derived from reader use-cases and cross-source convergence.
---

# Document Spec v2 — Synthesis

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
| "What's been researched on topic T?" | human + AI | Whichever tier the research lives in: cross-bead-query the central tier; cite the local tier from links and bead context. |
| "What docs descend from epic E or bead B?" | AI + tooling | Bead-graph (via `bd dep`/`bd show`) plus filesystem prefix: every doc in `specs/B/` is part of B's tree. |
| "Why was decision D made?" | human | `git blame` → commit → bead reference → bead description. |
| "I need to file a new \<thing\>." | human + AI author | If it's durable and one-of-a-kind: central. If it's tied to a piece of work: local under that work's bead-ID. |
| "Loading context for task X." | AI | Frontmatter `description` is crisp enough that grep/cross-bead query returns the right set. |

The rules below fall out of this table. Each filing rule earns its
keep by answering at least one of these queries cheaply and
unambiguously.

## Two epistemic tiers: central authoritative, local historical

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
│   ├── document-spec.md
│   ├── principles.md
│   └── …
└── specs/                 local, bead-keyed, historical
    ├── tk-yiwfz/
    │   └── decisions.md
    ├── tk-yiwfz.9/
    │   └── synthesis.md   (this file)
    └── tk-foo/
        ├── spec.md
        └── plan.md
```

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

## Inside `specs/<bead-id>/`

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
demonstrates that nesting carries its weight (e.g., four parallel
design alternatives that benefit from being co-located as
sub-bead directories under one parent design-iteration bead — see
[`specs/tk-yiwfz/decisions.md`](../tk-yiwfz/decisions.md) for the
example), the workflow can introduce them. The default is flat.

The rule of thumb: nest only when a reader landing on the parent dir
should see the children automatically because they're considered
together.

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

### No archiving

**Location is set at file-time and never changes based on lifecycle
state.**

A bead's state — open, in-progress, closed, abandoned — is the
lifecycle marker. The bead carries that signal; the filesystem does
not duplicate it. A closed bead's docs stay exactly where they were
filed.

No `archive/` directory. No `done/` sub-tier. No periodic sweep that
moves "stale" docs anywhere. The convergent finding across surveyed
sources — BMAD, Superpowers, Kiro, Spec Kit all converge on no
archive directory, with deletion + git history as the retirement path
[Source: docs/research/naming-conventions/bmad-method.md#doc-type-taxonomy]
— validates this; the central-vs-local epistemic distinction
explains why it is correct: a closed bead doesn't change the
truth-status of its docs (they were always historical record), so
there is nothing to archive *from*.

### Versioning is git

- **No `-v<N>` filename suffix on docs.** Gas Town's `gas-city-pack-v2.md`
  is a 1-of-6 case that v1 of this synthesis carried over as
  precedent
  [Source: docs/research/naming-conventions/gastown.md#filename-patterns];
  v2 drops it. If a release-frozen snapshot is genuinely needed, it
  is a git tag plus a pointer line in the live doc, not a duplicated
  file.
- **No trailing semver line on principles.** Spec Kit's
  constitution.md is the only surveyed source with a built-in semver
  footer
  [Source: docs/research/naming-conventions/spec-kit.md#constitution-—-constitutionmd-templatesconstitution-templatemd];
  gc-toolkit doesn't currently face the constitution-versioning
  problem and inheriting the apparatus is overhead.
- **No sync-impact-report HTML comments per amendment.** Same source,
  same reasoning.

The **versioned-reference doc-type** from v1 collapses entirely.

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
default; for almost every doc it is the wrong tool. The dropped
`docs/notes/` tier from v1 (which would have used
`docs/notes/<YYYY-MM-DD>-<topic>.md`) is one example of a place
where the timestamp would have been a generic disambiguator dressed
up as something more.

## Frontmatter

**Two fields. `name` and `description`.**

```yaml
---
name: <descriptive name>
description: <one-line discoverability hook>
---
```

That's it.

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

### Not adopted

- **`inclusion` / `fileMatchPattern` (Kiro).** Kiro's steering files
  use `inclusion: always | fileMatch | manual | auto` to control
  when the harness loads them
  [Source: docs/research/naming-conventions/kiro.md#filename-patterns].
  Adopting this would commit gc-toolkit to a specific
  context-loading model that is harness-specific (Kiro), and the
  problem it solves — "which docs enter the agent context when" —
  has better solutions emerging across the field. Don't bake one in
  prematurely.
- **`handoffs` (Spec Kit).** Spec Kit command files declare
  downstream commands in a `handoffs:` list
  [Source: docs/research/naming-conventions/spec-kit.md#command-files-—-specifytemplatescommandsname-md].
  gc-toolkit's beads system already captures handoffs (assignee
  changes, dependency edges); adding a duplicate frontmatter
  channel for them creates two truths.
- **`bead-id` field.** Redundant: spec docs encode the bead-ID in the
  path; central docs don't carry bead-IDs at all (their lineage is
  in `git blame` → commit → bead reference).

## Cross-doc references

Three mechanisms cover the cases this spec exhibits.

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

### Rejected

- **Numbered identifiers within a doc** (`FR-001`, `T###`,
  `CHK###`, `Article VII`)
  [Source: docs/research/naming-conventions/spec-kit.md#tasks-—-tasksmd-templatestasks-templatemd].
  Brittle when tied to position; redundant with bead-IDs as the
  durable join key. Adopt only inside a doc-type whose authors
  formally need stable cross-doc anchors to numbered items.
- **Filename pairing by shared slug + date** (Superpowers
  `YYYY-MM-DD-<slug>.md` ↔ `YYYY-MM-DD-<slug>-design.md`)
  [Source: docs/research/naming-conventions/superpowers.md#filename-patterns].
  Beads already timestamp the work; the date prefix is redundant,
  and pairing files by date+slug requires renaming both together.
- **Glob discovery** (BMAD `*prd*.md`)
  [Source: docs/research/naming-conventions/bmad-method-templates.md#cross-doc-reference-scheme].
  Ambiguous when multiple matches exist; explicit refs are clearer
  for gc-toolkit's per-bead-directory scope.
- **Live-file embed** (Kiro `#[[file:<path>]]`)
  [Source: docs/research/naming-conventions/kiro.md#filename-patterns].
  Requires harness support gc-toolkit doesn't have. Adopting it
  would mean *adding* a feature, not following a convention.

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

## Resolved questions (from v1)

| # | v1 question | Resolution |
|---|---|---|
| Q1 | Single versioned constitution file? | No. `docs/principles.md` (or `docs/principles/<topic>.md` if the directory accumulates ≥3-5 sibling principles); versioned by git. |
| Q2 | Hidden config dir for doc-state? | Deferred. Defaults are the contract; revisit if a use-case for machine-readable doc-state appears. |
| Q3 | Frontmatter shape? | `name` + `description` only. Mandatory on spec docs; encouraged on central. |
| Q4 | Bead-IDs in frontmatter or body? | Neither. Bead-ID is in the *path* for spec docs; central docs don't carry bead-IDs at all. |
| Q5 | Date prefixes on filenames? | Default no. Allowed when content is genuinely temporal. Not required, not promoted. |
| Q6 | `removals.txt` deprecation registry? | Deferred. Beads already carry rename/remove load. |
| Q7 | Top-level `CHANGELOG.md` / `AGENTS.md`? | CHANGELOG deferred until release cadence. AGENTS.md *for this repo* is the mechanik agent's prompt, not a doc. Top-level `CLAUDE.md` for users vendoring gc-toolkit remains genuinely open (see below). |
| Q8 | `docs/escalation/` doc-type? | Dissolved into the per-bead-dir model. The "feature work bundle" concept becomes `specs/<feature-bead-id>/` plus optional adoption to a central doc. |
| Q9 | Cross-source conflicts? | None remain after the directional calls captured in the [decisions document](../tk-yiwfz/decisions.md). |

## Genuinely open questions

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

## Provenance

- **Anchor**: [`specs/tk-yiwfz/decisions.md`](../tk-yiwfz/decisions.md)
  — directional calls from operator/mechanik conversation 2026-05-06.
- **Surveys** (cited inline above): six platform surveys at
  `docs/research/naming-conventions/{bmad-method, bmad-method-templates,
  superpowers, gastown, spec-kit, kiro}.md`. Each carries
  commit-SHA-and-path provenance to upstream.
- **v1 synthesis**: `docs/principles/document-spec.md`
  (polecat `gc-toolkit.furiosa`, bead `tk-yiwfz.4`). Reference for
  context; v2 is a clean rewrite, not a templated edit.
