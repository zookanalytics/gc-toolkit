---
name: File-Structure Conventions
description: Where gc-toolkit writes documentation and specs, with rules for document types, naming, semantics, and frontmatter.
---

# File-Structure Conventions

How gc-toolkit writes documentation — the conventions its agents and skills
follow wherever they write it, including into other repositories. Two rules
define the approach:

- If the document says what's true now, file it in `docs/` and keep it true.
- If the document records work, file it in `specs/<bead-id>/` and preserve it
  as context.

## Scope

**Mandate.** How gc-toolkit files the documentation it writes: where each
document belongs and what its location must keep true.

**Boundaries.** This covers documentation gc-toolkit writes, wherever it lands
— not customer-facing documentation. It governs where a document goes and how
it is framed, never what it must *say*; that is held by the document's own
[`## Scope`](#the-scope-section).

## Use Cases

| Query | Filing rule it implies |
|---|---|
| "What is the architecture / convention for X?" | Central tier: predictable path under `docs/`, refreshed in place. |
| "What was decided in the work on bead Y?" | Local tier: per-bead directory keyed by bead-ID. |
| "Why was central decision D made?" | `git blame` → commit → bead reference → bead description. |
| "I need to file a new \<thing\>." | Durable and one-of-a-kind: central. Tied to a piece of work: local under that work's bead-ID. |

## Two tiers: central authoritative, local historical

*Mnemonic: central is what's true; local is what was thought.*

**Central docs (`docs/`) are authoritative.** They speak what is true *now*.
If a central doc is wrong, the doc is the bug, and the fix is to update it. A
reader can cite a central doc as ground truth and act on it.

**Local docs (`specs/<bead-id>/`) are historical record.** They capture what
was thought, proposed, decided, or considered during a bead's work — dead ends
included. They are **read when linked-to**: a commit, a code comment, or a
central doc points at bead Y → read bead Y's local docs for the context that
work descends from. The cited record is ground truth for the work that cites
it, not beyond.

This grounds the [no-archiving rule](#location-is-set-at-file-time): a closed
bead doesn't change the truth-status of its docs, because those docs were
*always* historical record.

### Not a tier: `generated/`

`generated/` holds machine-written artifacts — trees a script emits from
sources tracked elsewhere in the repo, regenerated on commit and never
hand-edited. Neither filing rule reaches it: a generated file is neither kept
true nor preserved — it is re-emitted, and the way to change one is to change
its source. Filing a document there is always wrong.

## Directory Structure

Both tiers at the repo root. **Not** `docs/specs/`.

```
<repo-root>/
├── docs/                  central, refreshed-in-place, authoritative
├── specs/                 local, bead-keyed, historical
│   ├── tk-yiwfz/
│   └── 2026-08-rewrite/   (topic accommodation, dated)
└── generated/             machine-written, neither tier
```

## Inside `docs/`

A doc belongs in `docs/` only if it is durable, authoritative, and someone
owns keeping it current. Otherwise it goes in `specs/<bead-id>/`.

Default layout is flat at `docs/<topic>.md`. Promote to
`docs/<topic>/<sub-topic>.md` only when 3–5 sibling sub-topics warrant it.

- **Notes are bead-tied** — they go under the work's bead-ID.
- **Research is usually bead-tied.** What graduates to `docs/` is a synthesis
  someone owns keeping current; the raw research stays in `specs/`.
- **Lineage is via git history.** `git blame` → commit → bead reference is the
  primary path; inline bead citation only where it helps the reader.

## Inside `specs/`

### Default: bead-keyed directories

The canonical form is `specs/<bead-id>/` — the bead IS the directory.

### Accommodation: topic-or-feature directories

`specs/<topic-or-feature>/` is allowed for non-bead-tied local work. A
temporal prefix (`specs/2026-08-rewrite/`) is encouraged: `specs/` is
historical record, and a date keeps a topic slug from reading as
authoritative-on-the-topic.

### Directory name = bead-ID alone

`specs/tk-yiwfz/`, **not** `specs/tk-yiwfz-document-spec/`. Bead titles drift
as scope clarifies; a descriptive suffix would force renames and break
references. The bead-ID is fixed at creation; let it carry the identity.

### Bead hierarchy: default flat, optional nesting

Bead dirs sit flat as siblings; the bead-ID (`tk-yiwfz.4`) already encodes the
parent. Nest (`specs/tk-parent/tk-parent.1/`) only when the parent–child
relationship is durable and a reader landing on the parent should see the
children together.

### Files inside a bead dir are flat by default

Proposals, mockups, notes, reviews — one level. Introduce sub-directories only
when a workflow demonstrates they carry their weight.

### Filenames inside bead dirs are workflow-specific conventions

No master list of fixed filenames. `spec.md` because everyone names spec docs
that is fine; `something-specific.md` because the bead has many docs is also
fine. What is required: the doc's `description` frontmatter makes it findable.

## Filename and path discipline

### Location is set at file-time

A doc's path is fixed when written and never changes with lifecycle state.
The bead carries the open/closed signal; the filesystem does not duplicate
it. A closed bead's docs stay exactly where they were filed.

### Versioning is git (central docs)

Central docs roll forward; git history is the revision trail. No version
segments in filenames, no semver footers, no sync-impact comments. A genuinely
needed release-frozen snapshot is a git tag plus a pointer line, not a
duplicated file.

### Timestamps: rare, only when content is genuinely temporal

Default: no date in filenames — beads timestamp the work, git timestamps the
commits. Allowed when the timestamp is part of the doc's *meaning* (a
current-events snapshot pinned to a date), never as a generic disambiguator.

## Frontmatter

```yaml
---
name: <descriptive name>
description: <why the doc exists / when to use it>
---
```

- **Mandatory on local spec docs** — filenames there are flexible, so
  frontmatter carries the reader's orientation.
- **Strongly encouraged on central docs** — a topic-shaped filename can lie;
  the description keeps it honest.

A description helps a reader answer "is this the right document for my
question?" — it shouldn't restate the body, and shouldn't change often.

## The Scope section

Every authoritative `docs/` doc carries a `## Scope` section — the doc's
charter, in two parts:

- **Mandate** — the subject the doc speaks on authoritatively.
- **Boundaries** — what it deliberately does *not* cover, and where the
  adjacent material lives instead.

A reader uses it to decide whether a fact belongs here; an audit uses it as
the measure — every claim true within the mandate (no drift), everything
inside the mandate captured (no gap).

What makes a good scope:

- **It names the category, not the members.** "The sequence a release moves
  through and its gates," never the individual stages. Members drift; the
  category stays put. If a scope line goes stale when a member is renamed, it
  is pitched too low.
- **It is distinct from the frontmatter `description`.** The description is
  for discovery; the scope is the in-body charter. One that merely re-words
  the description has not earned its place.
- **It points at edges, it doesn't catalog references.** A boundary marks
  what is deliberately out and where it lives instead — which is what lets an
  audit tell *in-scope but missing* (a gap) from *out-of-scope* (correctly
  skipped).

| | `description` (frontmatter) | `## Scope` (body) |
|---|---|---|
| Job | discovery / index summary | the doc's charter |
| Answers | "is this the doc I want?" | "what does this doc own, and where are its edges?" |

A scope is **stable but not frozen**: it changes only when the doc is
re-chartered or the scope has become inaccurate — never with ordinary content
churn. Re-chartering is a deliberate human editorial act; agents read the
scope as the measuring stick but do not rewrite it.

## Cross-doc references

1. **Markdown relative-path links** are the default, used freely between
   specs, central docs, anchored sections, and external sources.
2. **Path is the identifier.** `docs/file-structure.md` or `specs/tk-foo/`
   answers "which doc?" — no separate citation convention.
3. **Cite sources inline** with descriptive link text carrying the
   provenance; the URL is plumbing.

## Drafting and adoption

**`specs/<bead-id>/` is a workspace.** Anyone can freely write into the
directory of work they're doing; the cost is intentionally low.

**Updating a central doc happens alongside the change that makes it stale** —
the same PR, no draft in `specs/` required first. Stale central docs are worse
than friction in updating them.

**Adding a new central doc is the deliberate case.** Claiming authoritative
status is a commitment to keep the claim true. A doc is as authoritative as
the branch it sits on; the merge to main puts it in the right place with the
right content, and the discoverability surface (READMEs, agent prompts,
sibling docs) updates in the same PR.
