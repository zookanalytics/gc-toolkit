---
name: Document Spec — v2 Synthesis (Draft A)
description: gc-toolkit's filing rules for central reference docs and bead-tied work artifacts; two-root layout, AI-centric framing, with cross-source provenance from six platform surveys.
---

# gc-toolkit document spec — v2 synthesis (draft A)

A clean rewrite of the v1 synthesis at `docs/principles/document-spec.md`,
re-derived from the directional decisions in
[`specs/tk-yiwfz/decisions.md`](../tk-yiwfz/decisions.md) and the six
platform surveys under `docs/research/naming-conventions/`. This draft
sits in `specs/tk-yiwfz.8/` for operator review; if adopted, the compact
binding form lands at `docs/document-spec.md` via a separate bead.

## Why this spec exists

Two reasons, both load-bearing.

**One: tools drop output everywhere.** Generators write to `.prd-reviews/`,
`.specs/`, `.bmad-output/`, sometimes `docs/`, sometimes the repo root —
whatever the tool's defaults happened to be. Files end up everywhere. A
human looking for the architecture decision, an AI loading context for a
task, a tooling pass scanning for specs — all three have to learn each
generator's idiosyncrasies. This spec exists to commit gc-toolkit to a
single canonical layout so any producer (human or AI) files predictably,
and any consumer always knows where to look.

**Two: gc-toolkit has to model its own rule.** To ask other tools and
agents to file consistently, gc-toolkit has to follow the rule it asks
others to follow. Without that self-discipline, there is no standing to
ask anyone else. The spec is therefore a stance gc-toolkit takes and
holds itself to — not just an external request to other tools.

Neither reason alone is enough. The first reason without the second is
"please do as I say, not as I do." The second reason without the first
is internal hygiene with no external pull. Together they make the spec
worth writing and worth keeping.

## AI-centric framing, stated explicitly

Diátaxis (tutorials / how-to / reference / explanation) is the
canonical doc taxonomy for human-only docs and the obvious starting
point. BMAD adopts it verbatim
([Source: docs/research/naming-conventions/bmad-method.md#Doc-type-taxonomy]),
and it works well when the only consumer is a human reading sequentially.

It is, however, **human-centric**. It classifies docs by *learning mode*
— is the reader trying to learn, do, look up, or understand? That axis
is irrelevant to an AI consumer. For an AI, the relevant question is
*when does this doc enter the context window*: every conversation, when
a particular task is loaded, when the agent matches a specific request,
or never automatically (cited only when linked).

gc-toolkit's docs serve human and AI consumers together, and the
AI-friendlier axis is **scope and temporal binding** — does this doc
describe the project as it is right now (refreshed in place) or capture
a moment of work (tied to a bead)? That axis is also legible to humans:
"current truth about the project" vs "what we were thinking when we did
that work." It happens to be the same axis Spec Kit and Kiro adopt
([Source: docs/research/naming-conventions/spec-kit.md#Central-vs-local-documents],
[Source: docs/research/naming-conventions/kiro.md#Doc-type-taxonomy]),
and the one that emerges from BMAD's three-tier output split
([Source: docs/research/naming-conventions/bmad-method-templates.md#Planning-vs-implementation-split]).

This spec adopts central-vs-local-by-temporal-binding as the primary
axis. Diátaxis-style classification (if useful) lives inside an
individual central doc — section structure within `docs/architecture.md`,
not the layout above it.

## The queries readers need to make

Filing rules are derived from the queries, not the other way around. The
table below enumerates the queries gc-toolkit's readers (human + AI)
need to make and the filing rule each one implies.

| Query | Reader | Filing rule it implies |
|---|---|---|
| "What's the architecture decision for X?" | human + AI | Central tier; predictable path (`docs/<topic>.md`) |
| "What are gc-toolkit's principles?" | human + AI | Central tier; one well-known location (`docs/principles.md`) |
| "What's the spec for feature F?" | human + AI | Local tier; bead-keyed (`specs/<bead-id>/`) |
| "What research has been done on topic T?" | human + AI | Flat per-type at central tier with `description` frontmatter; grep is the index |
| "What docs are in epic E / bead B's tree?" | AI + tooling | Bead-graph via tooling; bead-id is in the path so the tree is reachable from the bead |
| "Why was decision D made?" | human | Central doc says what; git blame → commit → bead reference says why |
| "I need to file a new <type>" | human + AI author | Predictable type/bead path; soft conventions for filename within bead dir |
| "Loading context for task X" | AI | Description frontmatter is crisp enough that a grep returns the right doc set |
| "Is this doc still authoritative?" | human + AI | Path tier answers it: central is authoritative by default; local requires bead-context to interpret |

Two filing rules fall out of this table immediately:

1. **Central docs are reached by predictable name** (one-per-concern,
   `docs/<topic>.md`); local docs are reached **through their bead**
   (path encodes bead identity). Different access patterns, different
   tiers.
2. **`description` frontmatter is the discoverability hook** that
   compensates for flexible filenames inside bead dirs and for the
   limitation that a topic title can lie about what a central doc
   actually covers.

The remaining sections turn these into concrete rules.

## Two-root layout

```
<repo-root>/
├── docs/                  central — authoritative, refreshed in place
│   ├── principles.md
│   ├── architecture.md
│   ├── document-spec.md
│   └── ...
└── specs/                 local — bead-tied historical record
    ├── tk-yiwfz/
    │   ├── decisions.md
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

Both roots sit at the **repo root**, not nested. This is the most
load-bearing structural decision in the spec; the rest follows from it.

**Why `specs/` is at the repo root, not under `docs/`:**

- **Spec Kit and Kiro converge on it.** Spec Kit puts every per-feature
  doc set under `specs/<feature>/`
  ([Source: docs/research/naming-conventions/spec-kit.md#Output-document-types-—-inventory]);
  Kiro under `.kiro/specs/<feature>/`
  ([Source: docs/research/naming-conventions/kiro.md#Directory-structure]).
  Of the surveyed sources, the two with the most-developed AI-driven
  workflows agree on this shape. Spec Kit-aware tooling files into
  `specs/` without reconfiguration — exactly the friction this spec
  exists to eliminate.
- **The two tiers follow distinct rule sets.** Central docs are
  refreshed-in-place, one-per-concern, no bead-id. Local docs are
  write-once-then-evolved, bead-keyed, free-form. Same parent (`docs/`)
  would suggest same rules; different parents make the rule-shift
  explicit at the path.
- **The two-bucket model is legible to humans and AI.** Humans go to
  `docs/` for current truth and to `specs/` to read the rationale of a
  past piece of work. AI loading context for a task can scope by tier:
  central docs always, local docs only when the bead is in scope.

The reading-mode mnemonic: **central is what's true; local is what was
thought.**

## Central is authoritative; local is historical record

The deeper distinction between `docs/` and `specs/` is **epistemic
status**, not just rule-set:

**Central docs are authoritative.** They speak what is true. They
describe how things actually work *today*. If a central doc is wrong,
the doc is the bug, and the fix is to update the doc. A reader (human
or AI) can cite a central doc as ground truth without further
qualification.

**Local docs are historical record.** They capture what was thought,
proposed, decided, or considered at a moment of work. They may be
wrong, outdated, never-pursued, abandoned, or half-formed. A reader
cannot cite a local doc as ground truth without first knowing the
bead's context — is it current, superseded, abandoned? The bead's
status is the gating signal.

**Local docs are relevant when linked-to.** "This change was made due
to bead `tk-yiwfz`" is the typical access pattern: read the bead's
context, understand why the change was made, *don't* generalise from
it. A decision recorded inside a bead applies to that bead's scope and
only while known to be current.

This grounds the no-archiving rule below: a closed bead's docs don't
move because they were always historical record, never authoritative.
A closed bead's docs may still be linked-to from a current
authoritative central doc as the "why this is the way it is" context.

## Central tier — `docs/`

Rules:

- **One file per concern.** `docs/principles.md`, `docs/architecture.md`,
  `docs/document-spec.md`. Refreshed in place; not duplicated, not
  versioned in the filename.
- **Flat by default.** `docs/<topic>.md`, no sub-directories. Promote
  `docs/<topic>.md` to `docs/<topic>/<sub-topic>.md` only when 3–5
  siblings warrant a directory. The single `docs/principles.md`
  becomes `docs/principles/` only if multiple sibling principle docs
  emerge, and the move happens then, not pre-emptively.
- **No `docs/design/` as a standing directory.** A "design doc" is
  either a durable topic (lives in central tier — "this is what a
  consult looks like") or a per-bead work iteration (lives in
  `specs/<bead-id>/proposal.md`). The doc-type splits in two; it
  doesn't need its own central directory.
- **No `docs/notes/` doc-type.** Notes that live outside a bead don't
  exist as a category — if a working note needs filing, file it under
  the bead it belongs to. (This drops the v1 `docs/notes/` candidate.)
- **No bead-IDs in central docs.** Not in frontmatter, not in body.
  Central docs are about the project as it is, not about the bead that
  produced any given revision. Provenance lives in git history (commit
  → PR → bead).

## Local tier — `specs/`

Rules:

- **Per-bead directory; the bead-id is the directory name.**
  `specs/tk-yiwfz/`, `specs/tk-design-iter/`. The directory IS the
  bead.
- **No descriptive suffix on the bead-dir name.**
  `specs/tk-yiwfz/`, **not** `specs/tk-yiwfz-document-spec/`. Meaningful
  names drift as scope evolves; bead-ids don't. A descriptive suffix
  forces a rename when the bead's subject shifts (which it often does)
  and breaks every external reference to the path. Revisit only if a
  concrete use-case demands name-based navigation; for now, bead-id
  alone.
- **Files inside a bead dir are flat by default.** Multiple proposal
  files, alternative mockups, ad-hoc review docs all sit at one level.
  Don't force sub-directories for grouping. If a workflow eventually
  needs them, the workflow can introduce them.
- **Bead hierarchy is flat too.** Bead dirs sit as siblings under
  `specs/`. The bead-id (`tk-yiwfz.4`) already encodes the parent
  reference; the filesystem doesn't need to repeat it. Optional
  nesting (`specs/tk-parent/{tk-parent.1/, tk-parent.2/}`) is allowed
  when the parent–child relationship is durable and physical
  co-location aids the reader (e.g., four design alternatives reviewed
  together under one parent design bead).
- **Fixed filenames are workflow-specific, not universal.** Specific
  workflows may converge on `spec.md` + `plan.md` + `tasks.md`
  (Spec Kit-shaped feature work
  [Source: docs/research/naming-conventions/spec-kit.md#Per-template-detail]),
  or `requirements.md` + `design.md` + `tasks.md` (Kiro-shaped
  [Source: docs/research/naming-conventions/kiro.md#Filename-patterns]),
  or `synthesis.md` (a synthesis bead), or `proposal.md` (a design
  bead). These conventions emerge for the workflows that need them.
  This spec does **not** prescribe a master list of canonical
  filenames; we avoid defining things before they need to be defined.

The Spec Kit and Kiro convergence on fixed-filename-per-workflow
([Source: docs/research/naming-conventions/spec-kit.md#Output-document-types-—-inventory],
[Source: docs/research/naming-conventions/kiro.md#Doc-type-taxonomy])
is informative: it works *because* each project picks one workflow.
gc-toolkit hosts multiple workflows simultaneously (Spec-Kit-shaped
feature work, design iterations, synthesis beads, research surveys),
so filename rigidity at the spec level would force every workflow into
one shape. Instead, the spec promises bead-id-keyed paths and
description-frontmatter discoverability; filenames inside the bead
dir are the workflow's call.

## Frontmatter

Universal fields — **`name` + `description` only**. That's it.

```yaml
---
name: <descriptive name>
description: <one-line, used for cross-bead discovery and AI loading>
---
```

- **Mandatory on spec files.** Filenames inside `specs/<bead>/` are
  flexible; `description` is the discoverability hook. Without it, a
  cross-bead grep for "the doc about the OAuth refresh flow" returns
  nothing useful.
- **Strongly encouraged on central docs.** A topic title can lie about
  what a doc actually covers (or about which corner of the topic it
  goes deep on). `description` keeps the title honest and gives
  context-loaders a one-line summary.
- **No bead-id field.** For spec docs the bead-id is in the path; for
  central docs there is no bead-id at all. A frontmatter field would
  duplicate the path for one and lie about the other.

**Not adopted:**

- `inclusion` / `fileMatchPattern` (Kiro
  [Source: docs/research/naming-conventions/kiro.md#Notable-shape-template]).
  Too prescriptive, harder to manage, ties context-loading rules to
  individual files. Better solutions to the AI-loading-axis problem
  will emerge from the Skills standard or convergent patterns; we
  defer.
- `handoffs` (Spec Kit
  [Source: docs/research/naming-conventions/spec-kit.md#Per-template-detail]).
  In Spec Kit the next-command suggestion lives in the command file;
  in gc-toolkit, beads carry handoffs (assignee, dependency edges,
  status). Frontmatter handoffs would be a parallel system.
- `status` enums. Lifecycle status lives at the bead, not the doc.
  Spec Kit's `**Status**: Draft` field has no documented vocabulary
  and isn't read by any consumer
  ([Source: docs/research/naming-conventions/spec-kit.md#Awkward-patterns]);
  Kiro ships no status field at all on first-party docs
  ([Source: docs/research/naming-conventions/kiro.md#Lifecycle-markers]).
  The bead's status is the lifecycle.
- `version` on principles or other central docs. Git is the version.

## Cross-doc references

Three mechanisms cover the cases that arise:

**1. Markdown relative-path links** for forward references between
docs. `[anchor text](relative/path.md)` or `(...md#section)`. The
prevailing pattern across all six surveys; nothing more is needed for
"this doc points at that doc."

**2. Path-as-bead-anchor** for spec docs. A doc at
`specs/tk-foo/spec.md` is reached by its path, and the bead identity
is in the path. There is no separate inline-citation convention for
"this doc descends from bead X" — the path says it. This avoids
inventing a `bead-id:` field that would duplicate the path
information; it also matches BMAD's "directory placement is the
type signal" pattern
([Source: docs/research/naming-conventions/bmad-method.md#Doc-type-taxonomy])
applied to bead identity.

**3. `[Source: <path>#<section>]` citations** when one doc draws facts
from another and inline provenance is useful. Borrowed from BMAD's
story-template convention
([Source: docs/research/naming-conventions/bmad-method-templates.md#Per-template-detail]).
Used in this synthesis throughout — every cross-source claim cites the
survey it draws from. Useful for synthesis docs, design rationale
docs, and any reference that aggregates facts from multiple sources.

**Rejected:**

- **Numbered IDs within a doc** (`FR-001`, `T###`,
  `[Spec §FR-001]`-style anchors). Spec Kit and Kiro both use these
  ([Source: docs/research/naming-conventions/spec-kit.md#Cross-doc-reference-scheme],
  [Source: docs/research/naming-conventions/kiro.md#Cross-doc-reference-scheme])
  and both surveys flag the same trap: reorder the source list and
  every reference silently shifts. gc-toolkit's beads provide stable
  IDs that play this role for cross-doc anchors; numbered IDs inside
  a doc duplicate that work less stably.
- **Filename-pairing-by-shared-slug+date** (Superpowers' paired
  plan/spec docs sit in sibling directories with identical date+slug
  segments and a `-design` suffix on the spec
  [Source: docs/research/naming-conventions/superpowers.md#Filename-patterns]).
  The bead is the durable join key; date+slug pairing is a workaround
  for not having one.
- **Glob discovery** for finding peer docs (BMAD's
  `{planning_artifacts}/*prd*.md`
  [Source: docs/research/naming-conventions/bmad-method-templates.md#Cross-doc-reference-scheme]).
  Tolerates renames but is ambiguous when multiple matches exist and
  has no machine-checkable "this PRD belongs to that brief" link.
  Path-as-bead-anchor solves the same problem with a stable identity.
- **Live-file-embed** (Kiro's `#[[file:<path>]]`
  [Source: docs/research/naming-conventions/kiro.md#Where-they-live]).
  Breaks silently on file rename/move; couples the embedding doc to
  the embedded file's exact path forever. Markdown link to the file
  is sufficient.

## What's deliberately **not** here

To make rejection visible (so it doesn't get re-litigated):

**No archive directory, no archive sweep.** Location is set at
file-time and never changes based on bead state. A closed bead's docs
stay where they were filed. Bead status (open / closed / abandoned) is
the lifecycle marker, and it lives at the bead, not on disk. A "stale"
doc — bead closed, no longer current — is just a doc whose bead status
the reader can check via tooling.

**No filename version suffix.** No version-numbered filenames, no
semver. Versioning is git. If a release-frozen snapshot is genuinely
needed, it's a git tag plus a pointer line in the live doc, not a
duplicated file. The versioned-reference doc-type that v1 considered
(Gas Town has one in-tree central doc that pairs an evergreen
reference with a release-frozen sibling carrying a version segment in
the filename
[Source: docs/research/naming-conventions/gastown.md#Filename-patterns])
collapses into "central docs roll forward; tags are how you address a
release."

**No date prefix on filenames** — by default. Beads timestamp the work
and git timestamps the commit; that's enough for the standard case.
**Allowed when the content is genuinely temporal** — a bead doing
research on the state of something at a specific point in time
("state of upstream BMAD as of 2026-05-01") may use a timestamp in
its output filename to pin the snapshot. Valid when the timestamp is
part of the doc's *meaning*, not a generic disambiguator. Not
required, not promoted; reach for it only when the doc is genuinely
about a moment.

**No constitution-versioning footer.** Spec Kit's
`**Version**: X.Y.Z | **Ratified**: ... | **Last Amended**: ...`
trailing line on `constitution.md`
([Source: docs/research/naming-conventions/spec-kit.md#Constitution-—-constitution-md])
is rejected. Useful for a doc with a formal ratification process; not
useful for a project where principles evolve through PRs and git
history is the audit trail.

**No sync-impact-report HTML comments** prepended to amended principle
docs. Spec Kit prepends one after each constitution amendment
([Source: docs/research/naming-conventions/spec-kit.md#Constitution-—-constitution-md]);
gc-toolkit lets the PR description carry that load.

**No top-level meta-doc index for `docs/`.** The directory listing is
the index. If `docs/` ever grows past the point where listing is
enough, that's the time to consider an index — not pre-emptively.

## Resolved open questions

Carried over from v1 (`tk-yiwfz.4`), now closed by the directional
decisions in `specs/tk-yiwfz/decisions.md`:

| # | Question | Resolution |
|---|---|---|
| Q1 | Single versioned constitution file? | No. Single `docs/principles.md`; versioned by git history. No semver footer. |
| Q2 | Hidden config dir for doc-state? | Deferred. Defaults are the contract; revisit if a mapping use-case appears. |
| Q3 | Frontmatter shape? | `name` + `description` only. Mandatory on spec files; encouraged on central. |
| Q4 | Bead-IDs in frontmatter or body of a central doc? | Neither. Bead-id is in the path for spec docs; central docs don't carry it. |
| Q5 | Date prefixes on filenames? | Default no. Allowed when content is genuinely temporal. Not required, not promoted. |
| Q6 | `removals.txt`-style deprecation registry? | Deferred. Beads can carry rename/remove load when needed. |
| Q7 | Top-level `CHANGELOG.md` / `AGENTS.md`? | CHANGELOG deferred until a release cadence motivates it. AGENTS.md for *this* repo would describe mechanik (the agent), and that's a separate concern. Top-level `CLAUDE.md` for users vendoring gc-toolkit is genuinely open — see below. |
| Q8 | `docs/escalation/` doc-type? | Dissolved. Per-bead-directory model under `specs/<bead-id>/` covers it. |
| Q9 | Cross-source conflicts requiring decision? | None remain after the directional calls in `decisions.md`. |

## Genuinely remaining open questions

Two are open, neither blocks adoption:

**Top-level `CLAUDE.md` for vendoring users.** A repo that vendors
gc-toolkit (or any user of the Gas Town SDK) may want a top-level
`CLAUDE.md` that orients an AI agent to gc-toolkit's conventions —
analogous to Superpowers' `CLAUDE.md`
([Source: docs/research/naming-conventions/superpowers.md#Filename-patterns])
or Spec Kit's per-integration agent context files
([Source: docs/research/naming-conventions/spec-kit.md#Agent-context-files]).
Whether gc-toolkit ships one and what it contains is a separate
decision; the doc-spec can accommodate either choice (a top-level
`CLAUDE.md` is a central doc by these rules).

**Cross-bead query tooling.** With local docs scattered across
`specs/<bead-id>/` directories and discoverability resting on
frontmatter `description`, a gc-toolkit-specific helper for "find all
spec docs whose description matches X" would be useful. Today the
answer is `grep -r 'description:' specs/`; a wrapper that returns
`bead-id + path + description` rows is future work. Non-blocking;
the manual query works.

## Drafting and adoption flow

**1. Drafts in `specs/`** are loose. The whole point of having a
local tier is that we can freely write just about anything inside a
`specs/<bead-id>/` folder without committing to a binding form. This
synthesis at `specs/tk-yiwfz.8/synthesis.md` is exactly such a draft;
so is its sibling at `specs/tk-yiwfz.9/`. Drafts get reviewed,
revised, abandoned, or promoted.

**2. Operator review.** Drafts are cheap; revision until the operator
is happy on substance is the gating step.

**3. Adoption PR.** When a draft is ready to bind, a PR commits the
**compact central version** at `docs/document-spec.md` and updates
agent discoverability touchpoints (mechanik prompt, README pointers,
any `CLAUDE.md` orientation). Items in `docs/` are deliberate, like
code: review focuses on whether the binding form correctly captures
what was decided, not on iteration cycles.

**4. Migration is a separate bead.** Re-shaping the existing tree
(`docs/principles/document-spec.md` → `docs/document-spec.md`,
`docs/research/naming-conventions/<survey>.md` →
`specs/<survey-bead>/<survey>.md`, `docs/design/<topic>.md` split
into central or per-bead) is its own work. The migration bead carries
the file-list and the rename plan; this spec just defines the target
layout. (Migration impact is a fact, not a selling point — the
question for adoption is whether the new layout is right, not whether
the move cost is small.)

## Provenance

**Decisions anchor.** [`specs/tk-yiwfz/decisions.md`](../tk-yiwfz/decisions.md)
captures the operator/mechanik conversation of 2026-05-06 that set the
directional calls this synthesis rests on. Every default in this draft
traces to a decision there.

**Source surveys** under `docs/research/naming-conventions/`:

| Survey | File | Upstream |
|---|---|---|
| BMAD (naming) | [`bmad-method.md`](../../docs/research/naming-conventions/bmad-method.md) | `github.com/bmad-code-org/BMAD-METHOD` ~v6.6.0 era |
| BMAD (templates) | [`bmad-method-templates.md`](../../docs/research/naming-conventions/bmad-method-templates.md) | `github.com/bmad-code-org/BMAD-METHOD` @ `e36f219` (2026-05-01) |
| Superpowers | [`superpowers.md`](../../docs/research/naming-conventions/superpowers.md) | `github.com/obra/superpowers` v5.0.7 (2026-03-31) |
| Gas Town | [`gastown.md`](../../docs/research/naming-conventions/gastown.md) | `rigs/gascity/examples/gastown/` + in-tree `rigs/gc-toolkit/docs/` |
| Spec Kit | [`spec-kit.md`](../../docs/research/naming-conventions/spec-kit.md) | `github.com/github/spec-kit` @ `0f26551` (2026-05-05) |
| Kiro | [`kiro.md`](../../docs/research/naming-conventions/kiro.md) | `kiro.dev/docs/` + community templates (2026-05-05) |

Each survey carries upstream commit-SHA provenance to the source
material it summarises; this synthesis cites the surveys, not the
upstream, per the contract in `decisions.md`.

**v1 reference.** [`docs/principles/document-spec.md`](../../docs/principles/document-spec.md)
(polecat `gc-toolkit.furiosa`, bead `tk-yiwfz.4`, surveyed 2026-05-06).
Read for context; v2 rebuilds rather than edits. Stays at v1 location
until the migration bead.
