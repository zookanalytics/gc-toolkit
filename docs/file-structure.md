---
name: File-Structure Conventions
description: Where gc-toolkit writes documentation and specs, with rules for document types, naming, semantics, and frontmatter.
---

# File-Structure Conventions

This document describes how gc-toolkit writes documentation — the
conventions its agents, personas, and skills follow wherever they write
it, including documentation they write into other repositories. It does
not apply to customer-facing documentation. Two rules define
the approach:

- If the document says what's true now, file it in `docs/` and keep
  it true.
- If the document records work, file it in `specs/<bead-id>/` and
  preserve it as context.

## Scope

**Mandate.** The conventions that decide where the documentation and
specs gc-toolkit writes are filed, and how they are named, framed, and
cross-referenced — the central-versus-local tier split and the
discipline that keeps each tier's promise: central docs true, local docs
preserved as history.

**Boundaries.** This governs how gc-toolkit writes documentation — what
its agents, personas, and skills produce, wherever they write it,
including into other repositories — not customer-facing documentation. It
sets where a doc goes and how it is framed — never what any individual doc
must *say*; that is the doc's own content, governed by that doc's
[`## Scope`](#the-scope-section).

## Use Cases

| Query | Filing rule it implies |
|---|---|
| "What is the architecture / convention / principle for X?" | Central tier: predictable path under `docs/`, refreshed in place. |
| "What was decided in the work on bead Y?" | Local tier: per-bead directory keyed by bead-ID. |
| "What's been researched on topic T?" | Whichever tier the research lives in: cross-bead-query the local tier; cite where authoritative conclusions made it into central docs. |
| "What docs descend from epic E or bead B?" | Bead-graph (via `bd dep`/`bd show`) plus filesystem prefix: every doc in `specs/B/` is part of B's tree. |
| "Why was central decision D made?" | `git blame` → commit → bead reference → bead description. |
| "I need to file a new \<thing\>." | If it's durable and one-of-a-kind: central. If it's tied to a piece of work: local under that work's bead-ID. |
| "Loading context for task X." | Bead-graph from the task's bead (via `bd dep`/`bd show`) + central docs. |

## Two tiers: central authoritative, local historical

*Mnemonic: central is what's true; local is what was thought.*

This spec defines where docs *live* based on what they *claim*.

**Central docs (`docs/`) are authoritative.** They speak what is true
*now*. If a central doc is wrong, the doc is the bug, and the fix is
to update the doc. A reader can cite a central doc as ground truth
and act on it.

**Local docs (`specs/<bead-id>/`) are historical record.** They
capture what was thought, proposed, decided, or considered during a
bead's work — including dead ends, drafts, and ideas explored and
dropped.

Local docs are **read when linked-to**. A commit, a code comment,
another local doc, or a central doc points at bead Y → read bead Y's
local docs for the context that work descends from. The cited record
is ground truth for the work that cites it, not beyond.

This distinction grounds the [no-archiving rule](#location-is-set-at-file-time):
a closed bead doesn't change the truth-status of its docs, because
those docs were *always* historical record. There is nothing to
archive.

## Directory Structure

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

`specs/` matches the per-feature-directory convention used by
spec-driven-development tools — Spec Kit at `specs/<feature>/`,
Kiro at `.kiro/specs/<feature>/`. gc-toolkit follows the same shape
with bead-keyed names.

## Inside `docs/`

A doc belongs in `docs/` only if it is durable, authoritative, and
someone owns keeping it current as the world or the codebase
evolves. Otherwise it goes in `specs/<bead-id>/`.

The default layout is flat at `docs/<topic>.md` —
`docs/file-structure.md`, `docs/principles.md`, `docs/architecture.md`,
and so on. Promote to `docs/<topic>/<sub-topic>.md` only when 3–5
sibling sub-topics warrant the directory.

**Notes are bead-tied.** Working notes exist in service of a piece of
work; they go under that work's bead-ID at `specs/<bead-id>/`.

**Research is usually bead-tied.** A bead's surveys, investigations,
and comparisons go under `specs/<bead-id>/`. A central doc that
*consumes* research over time — `docs/competitive.md` kept current
across multiple research beads, for example — fits central tier
because the doc itself meets the durable + authoritative + maintained
bar. The raw research stays bead-tied; what graduates is the
synthesis someone owns keeping current.

**Lineage in central docs is via git history.** `git blame` → commit
→ bead reference is the primary path. Inline bead citation (footnote
or body) is allowed where it adds value to the reader, not as a
default.

## Inside `specs/`

### Default: bead-keyed directories

The canonical form is `specs/<bead-id>/`. Each bead that produces
filing creates its own directory; the bead IS the directory. This
is the gc-toolkit-native pattern, and the one that earns the
"path-as-bead-anchor" reference mechanism (see
[Cross-doc references](#cross-doc-references)).

### Accommodation: topic-or-feature directories

`specs/<topic-or-feature>/` is allowed for non-bead-tied local work:
contributors who haven't started a bead, vendoring users who don't
run the gc-toolkit bead workflow, pre-bead content waiting to be
adopted into a bead, and migration of historical content into the
new layout. Same flat-by-default rules apply inside.

A temporal reference in the directory name
(`specs/2026-05-design-pass/`) is encouraged but not required. A
bare topic slug reads as authoritative-on-the-topic; `specs/` is
historical record, and a date keeps that framing honest.

### Directory name = bead-ID alone

`specs/tk-yiwfz/`, **not** `specs/tk-yiwfz-document-spec/`.

The bead-ID is the stable anchor. Bead titles drift as scope
clarifies; descriptive folder suffixes encode an early-bead title
that may no longer fit by the time the bead closes. A descriptive
suffix would force a rename whenever the bead's framing shifts and
break every external reference to the path. The bead-ID is fixed at
creation; let it carry the identity.

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

This spec **does not prescribe a master list** of fixed filenames.
Naming a doc `spec.md` because "everyone names spec docs that"
beats inventing a slug; naming it `something-specific.md` because
the bead has many docs is also fine. We avoid defining things before
they need to be defined.

What is required: the doc's `description` frontmatter field has to
make the doc findable, since the filename is no longer a typing
convention. See [Frontmatter](#frontmatter).

## Filename and path discipline

### Location is set at file-time

A doc's path is fixed when the file is written and never changes
based on lifecycle state. A bead's state — open, in-progress,
closed, abandoned — is the lifecycle marker. The bead carries that
signal; the filesystem does not duplicate it. A closed bead's docs
stay exactly where they were filed.

### Versioning is git (central docs)

Central docs roll forward. The live doc is the version; git history
is the revision trail. Filenames carry no version segment, principle
docs carry no semver footer, and amended docs carry no
sync-impact-report comments.

If a release-frozen snapshot is genuinely needed, address it by git
tag plus a pointer line in the live doc, not a duplicated file.

### Timestamps: rare, only when content is genuinely temporal

Beads timestamp the work. Git timestamps the commits. Filesystem
timestamps duplicate that without adding sortability `ls` doesn't
already give.

**Default: no date in filenames.** The standard case has nothing to
gain.

**Allowed when the content is genuinely temporal.** A research bead
capturing a current-events snapshot — competitor positioning, the
state of an external dependency, regulatory landscape — as of
2026-05-01 may use a timestamp in its output to pin it. The
timestamp is part of the doc's *meaning*, not a generic
disambiguator.

**Not required, not promoted.** Don't reach for a date prefix as a
default; for almost every doc it is the wrong tool.

## Frontmatter

This spec takes a stance on two frontmatter fields, `name` and
`description`. Other fields are allowed if a workflow needs them.

```yaml
---
name: <descriptive name>
description: <1-2 sentence overview>
---
```

`name` is a contextual reminder of which doc this is — "Spec for
XYZ" triggers a memory in a way `spec.md` doesn't. `description` is
a 1-2 sentence overview of why the doc exists, or when to use it.

- **Mandatory on local spec docs.** Filenames inside `specs/<bead>/`
  are flexible, so frontmatter carries the reader's orientation.
- **Strongly encouraged on central docs.** A topic-shaped filename
  can lie about what the doc covers; the description keeps that
  honest.

A description helps a reader answer "is this the right document for
my question?" — not give the answer itself. It shouldn't restate the
doc's body, and shouldn't change often as the doc evolves.

## The Scope section

Every authoritative `docs/` doc carries a `## Scope` section in its
body — the doc's charter. What follows is the **scope standard**: what
a `## Scope` is, what makes one good, and how it is maintained.

This standard is **v1** — a deliberate first cut, expected to sharpen as
we accumulate calibration examples and as the doc-keeper audits expose
what it fails to pin down. It is the current best articulation, not a
finished spec.

### What a scope is

A scope states, at the right altitude, **what the doc is responsible
for representing**. It has two parts:

- **Mandate** — the subject the doc speaks on authoritatively: what it
  intends to represent, completely and truthfully.
- **Boundaries** — what the doc deliberately does *not* cover, and where
  the adjacent material lives instead.

Scope is the doc's own statement of what "true and complete" means for
it. A reader uses it to decide whether a fact belongs here; whatever
holds the doc to account — an agent, an audit, a human maintainer — uses
it as the thing the doc is judged against: is every claim still true
*within this mandate* (no drift), and is everything inside the mandate
actually captured (no gap)? The check is against the charter the doc
declares, not against a diff of git history.

### What makes a good scope

- **It states the mandate, not the implementation.** The mandate names
  the doc's *remit* — what it is responsible for. It does not enumerate
  the doc's contents: the sections, steps, commands, and mechanisms are
  what the scope *governs*, not what it lists. A remit is stable; an
  outline drifts with every edit. If the mandate reads like a table of
  contents, it is pitched too low.
- **It is distinct from the frontmatter [`description`](#frontmatter).**
  The two may share a subject, but they do different jobs at different
  altitudes. The `description` is a one-line discovery blurb in the
  index — "is this the doc I want?" The scope is the in-body charter —
  "what does this doc own, and where are its edges?" A scope that merely
  re-words the description in longer form has not earned its place; the
  mandate must add the precision — named subjects, the doc's distinctive
  angle — and the boundaries a one-line blurb cannot carry.
- **It names its boundaries.** A boundary states what is deliberately out
  and points at where it lives instead. Boundaries are what let an audit
  tell two failure modes apart: something *in-scope but missing* is a gap
  to close; something *out-of-scope* was correctly skipped. Without
  stated edges, every absence looks like a gap.

| | `description` (frontmatter) | `## Scope` (body) |
|---|---|---|
| Size | one line | a short section |
| Job | discovery / index summary | the doc's charter |
| Answers | "is this the doc I want?" | "what does this doc own, and where are its edges?" |
| Changes | rarely | only when the mandate or boundaries genuinely shift |

Keep it tight: a mandate sentence and a short boundary list, not a
table of contents.

### A calibration example

The point is the *shape*, so this example is deliberately contrived —
anchoring the standard to a real file would only make the standard drift
as that file is improved. Suppose a doc owns *how a project cuts
releases*. A good scope for it might read:

> **Mandate.** How a release is produced and published — the stages a
> change moves through from a green `main` to a tagged, announced
> artifact, and the rule that holds across all of them: nothing ships
> that `main` hasn't already proven. It is the authority on that
> *sequence* and its gates, not on any single tool that implements a
> stage.
>
> **Boundaries.** This covers *cutting* a release, not deciding what goes
> *into* one — feature selection and changelog content belong with the
> work that produces them. It does not document the CI system's own
> configuration, and it treats the artifact store as a downstream given:
> named, not specified.

Read it for the moves, not the subject. The mandate names concrete
subjects — the stages, the gates — and states a distinctive angle (the
invariant that ties them together) without reciting the doc's section
headings. The boundaries draw a crisp line — cutting a release versus
filling one — and disclaim the adjacent material, so an absence reads as
deliberate, not as a gap. A live doc's real scope is always the better
calibration; this one only shows the form.

### How a scope is maintained

A scope is **stable**, but not frozen. It evolves in two cases: when the
doc is *re-chartered* — its mandate or boundaries genuinely shift — and
when the scope itself has become *inaccurate*, no longer describing what
the doc is responsible for. What it does *not* track is ordinary content
churn: the content beneath the charter moves whenever the world does,
while the charter that governs it stays put.

**Agents read** the scope as the measuring stick — it is what a doc's
claims are held against to decide whether the doc is true and complete,
whatever process is doing the reading. They do not author or rewrite it.
Re-chartering is a deliberate human editorial act, the same kind of
decision as [adding a new central doc](#drafting-and-adoption).

## Cross-doc references

### 1. Markdown relative-path links

The default for cross-doc references. Use them freely — between
specs and central docs, to anchored sections within a doc, or to
external sources.

```markdown
See [decisions](../tk-yiwfz/decisions.md) for the directional calls
this synthesis anchors against.
```

### 2. Path is the identifier

A doc's path is how readers refer to it. For central docs, the
filename carries meaning (`docs/file-structure.md`). For local docs,
the directory carries it — `specs/tk-foo/` for bead-keyed work,
`specs/2026-05-design-pass/` for topic-or-feature accommodation. In
either case, no separate inline-citation convention is needed: the
path itself answers "which doc?" or "which bead?"

### 3. Citing sources

When a synthesis or principle doc draws on external research, cite
inline with a standard markdown link. Descriptive text in the link
carries the provenance; the URL is plumbing.

```markdown
This layout matches [Spec Kit's per-feature directories](../specs/tk-yiwfz.6/spec-kit.md).
```

## Drafting and adoption

The two tiers carry different evolution patterns, both grounded in
their epistemic role: `specs/` is history of work, `docs/` is what
is true now.

**`specs/<bead-id>/` is a workspace.** Anyone can freely write into
the directory of work they're doing — drafts, proposals, scratch
notes, dead ends, alternatives. The cost is intentionally low; that
is what makes it useful.

**Updating a central doc happens alongside the change that makes it
stale.** When a feature, refactor, or decision invalidates what a
`docs/` file says, the same PR updates the doc directly — no draft
in `specs/` required first. A spec might reference *that* a central
doc will change, but the actual change goes in with the work, the
same way code changes do. Stale central docs are worse than friction
in updating them; the path has to stay easy.

**Adding a new central doc is the deliberate case.** Claiming
authoritative status for a new topic is a commitment to keep that
claim true going forward. A doc is as authoritative as the branch
it sits on — drafts on a working branch are not yet adopted,
regardless of whether they sit in `specs/<bead-id>/` or directly in
`docs/<topic>.md`. What matters is that the merge to main puts the
doc in the right place with the right content, and that the
discoverability surface (READMEs, agent prompts, sibling docs)
updates in the same PR.

