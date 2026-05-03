# Gas Town — document naming conventions

## Source surveyed

- Pack source tree: `rigs/gascity/examples/gastown/` (project memory:
  "gastown ships from gascity")
  - `gastown/` — example city root with two packs: `packs/gastown/`
    (domain-specific coding workflow) and `packs/maintenance/`
    (generic infrastructure)
  - Top-level docs: `FUTURE.md`, `SDK-ROADMAP.md`, `city.toml`
  - Pack manifests: `packs/gastown/pack.toml`, `packs/maintenance/pack.toml`
- Reference doc shipped in gc-toolkit:
  `rigs/gc-toolkit/docs/gas-city-reference.md` (the formal user-facing
  reference to Gas City packs and conventions)
- gc-toolkit's own pack root for comparison/transition signal:
  `rigs/gc-toolkit/{pack.toml,agents/,prompts/,formulas/,docs/}`
- The escalation branch shape referenced by parent bead `tk-yiwfz`
  (`docs/escalation/research/r<n>-…`, `v<n>-…`) was inspected via
  `git ls-tree origin/claude/research-ai-communication-mGN27`

Gas Town has very few standalone narrative docs — most "documents" are
prompts, formulas, template fragments, and pack-manifest comments. The
strongest naming signal in Gas Town is therefore in **configuration
artifacts that are docs in spirit**: `*.template.md` fragments,
`mol-*.toml` formulas, `agent.toml` + `prompt.template.md` pairs, and
`pack.toml` header comments.

## Directory structure

### Top of an example city

```
examples/gastown/
├── FUTURE.md                  # Gap analysis: missing gc commands
├── SDK-ROADMAP.md             # Roadmap: what needs to be built in gc binary
├── city.toml                  # City-specific runtime config
├── packs/                     # Pack content (the actual reusable pieces)
│   ├── gastown/
│   └── maintenance/
└── *_test.go                  # Go tests over the example
```

Two top-level docs (`FUTURE.md`, `SDK-ROADMAP.md`) sit alongside
`city.toml`. There is **no `docs/` directory at the gastown example
root** and **no `README.md` at the example root or inside any of the
two packs.** The opening comments in `city.toml` and each `pack.toml`
serve the role a README would.

### Inside a pack

`packs/gastown/` is the canonical shape for a v2 pack:

```
packs/gastown/
├── pack.toml                  # Pack manifest (with explanatory header comment)
├── agents/<name>/             # Convention directory per agent
│   ├── agent.toml             #   Agent config (no `name` field — derived from dir)
│   ├── prompt.template.md     #   Agent prompt template
│   └── namepool.txt           #   Optional: per-agent themed name pool
├── assets/                    # Files referenced from configs
│   ├── scripts/<name>.sh
│   ├── prompts/<name>.template.md
│   └── namepools/<theme>.txt
├── commands/<name>/           # Convention directory per gc subcommand
│   ├── run.sh
│   └── help.md
├── doctor/<check-name>/       # Convention directory per doctor check
│   ├── doctor.toml            #   (optional metadata — observed in maintenance only)
│   └── run.sh                 #   (the check itself)
├── formulas/mol-<name>.toml   # Formula files
├── orders/<name>.toml         # Order files (cooldown / event / cron)
├── overlay/                   # Files merged into the runtime tree
│   └── .claude/settings.json
├── template-fragments/<name>.template.md   # Reusable {{ define "x" }} blocks
└── embed.go                   # Go //go:embed of the whole pack tree
```

`packs/maintenance/` is structurally identical, minus `commands/` and
`overlay/`. The convention is recursive: every "kind of thing" gets its
own subdirectory whose **directory name doubles as the entity name**.

### Documents in the consuming rig

`gc-toolkit/docs/` is the closest example of a "real" doc tree:

```
gc-toolkit/docs/
├── design/                    # Design docs
│   ├── consult-surfacing.md
│   └── consult-session-feasibility.md
├── gas-city-pack-v2.md        # Reference: what shipped in v2
├── gas-city-reference.md      # Canonical reference manual
├── gascity-local-patching.md  # Process doc
└── roadmap.md                 # Living planning doc
```

The in-flight escalation branch `claude/research-ai-communication-mGN27`
adds a richer shape that the parent bead `tk-yiwfz` cites as reference:

```
docs/escalation/
├── ideation.md
├── marching-orders.md
├── research-log.md
├── research/
│   ├── r1-toyota-production-system.md
│   ├── r2-cheap-prototyping.md
│   ├── ...
│   ├── v1-red-team.md
│   ├── v2-ai-native-prior-art.md
│   └── ...
├── roadmap.md
└── selection-menu.md
```

Note the **mixed root**: process artifacts (`ideation.md`,
`marching-orders.md`, `selection-menu.md`, `research-log.md`,
`roadmap.md`) sit at `docs/escalation/`, while research and validation
docs live one level deeper at `docs/escalation/research/`. There is no
`docs/escalation/principles/` or `docs/escalation/adopted/` — adopted
content has not yet been promoted out of the working area on that
branch.

## Filename patterns

| Domain | Pattern | Examples |
|---|---|---|
| Top-level project notes | `SCREAMING-KEBAB.md` | `FUTURE.md`, `SDK-ROADMAP.md`, `LICENSE`, `README.md` |
| Pack manifests | singular `lowercase.toml` | `pack.toml`, `city.toml`, `agent.toml`, `doctor.toml` |
| Formula files | `mol-<kebab>.toml` | `mol-polecat-work.toml`, `mol-digest-generate.toml`, `mol-witness-patrol.toml` |
| Order files | `<kebab>.toml` (no prefix) | `wisp-compact.toml`, `gate-sweep.toml`, `digest-generate.toml` |
| Template fragments | `<kebab>.template.md` | `propulsion.template.md`, `architecture.template.md`, `approval-fallacy.template.md` |
| Agent prompts | fixed name `prompt.template.md` | `agents/polecat/prompt.template.md` |
| Shared prompts | `<role>.template.md` | `assets/prompts/crew.template.md` |
| Scripts | `<kebab>.sh` | `worktree-setup.sh`, `tmux-theme.sh`, `bind-key.sh` |
| Namepools | `<theme>.txt` | `minerals.txt`, `agents/polecat/namepool.txt` |
| Reference docs (in gc-toolkit) | `<kebab>.md` | `gas-city-reference.md`, `gascity-local-patching.md`, `roadmap.md` |
| Versioned reference docs | `<topic>-<vN>.md` | `gas-city-pack-v2.md` |
| Design docs (in gc-toolkit) | `<kebab>.md` under `design/` | `design/consult-surfacing.md` |
| Research docs (in-flight) | `r<n>-<topic>.md` / `v<n>-<topic>.md` | `r1-toyota-production-system.md`, `v3-skeptic.md` |
| Go test files | `<feature>_test.go` | `gastown_test.go`, `precompact_hook_test.go` |

The dominant convention is **kebab-case for content names** with the
type carried by the **path or extension**, not by a filename prefix.
The two visible exceptions are formulas (`mol-` prefix) and research
docs on the in-flight branch (`r<n>-` / `v<n>-` prefixes).

### Two extension dialects for "Go-template markdown"

- v2 (current, dominant): `*.template.md` — used for prompts and
  fragments inside `packs/`, and inside gc-toolkit's `agents/<name>/`
  convention dirs.
- v1 (legacy, transitional): `*.md.tmpl` — visible only in
  `gc-toolkit/prompts/mechanik.md.tmpl`, kept alongside the v2
  `agents/mechanik/prompt.template.md` during transition.

`gas-city-reference.md` (lines 1416, 1440) explicitly documents the
move: `prompts/<name>.md.tmpl` → `agents/<name>/prompt.template.md` is
part of the v1→v2 migration checklist.

### Two formula-file dialects

- v2 (current): `formulas/<name>.toml` — flat, no infix.
- v1 (legacy): `formulas/<name>.formula.toml`.

`gas-city-reference.md` line 841: *"TOML workflow templates defining
multi-step work. **File naming in v2 is flat `<name>.toml` under
`formulas/` (the `.formula.` infix was removed).**"* The v1→v2 table
at line 1417 records the rename explicitly.

### Two order-file dialects

- v2 (current): `orders/<name>.toml` — flat single file per order.
- v1 (legacy): `orders/<name>/order.toml` — one directory per order.

Documented in `gas-city-reference.md` line 1418.

## Doc-type taxonomy

Gas Town distinguishes doc types primarily by **path**, secondarily by
**filename pattern** for in-flight research, and only rarely by
frontmatter.

| Type | Where | Naming signal |
|---|---|---|
| Pack/city manifest | pack root | `pack.toml`, `city.toml` |
| Reference manual (canonical, user-facing) | `<rig>/docs/` | descriptive kebab name (`gas-city-reference.md`) |
| Versioned reference (frozen for a release) | `<rig>/docs/` | version suffix in name (`gas-city-pack-v2.md`) |
| Living planning / roadmap | `<rig>/docs/roadmap.md` or top-level `SDK-ROADMAP.md` | `roadmap.md` |
| Gap-analysis / "what's missing" | top-level | `FUTURE.md` (SCREAMING) |
| Process docs ("how we do X") | `<rig>/docs/<topic>.md` | descriptive kebab (`gascity-local-patching.md`) |
| Design docs (approved or proposed) | `<rig>/docs/design/<topic>.md` | path; status declared in body frontmatter |
| Research surveys (in-flight) | `<rig>/docs/escalation/research/r<n>-<topic>.md` | `r<n>-` prefix; numbered |
| Validation rounds (in-flight) | `<rig>/docs/escalation/research/v<n>-<topic>.md` | `v<n>-` prefix; numbered |
| Selection / curation | `<rig>/docs/escalation/selection-menu.md` | descriptive name |
| Agent prompts (docs in spirit) | `<pack>/agents/<name>/prompt.template.md` | fixed filename, agent dir = name |
| Reusable prompt fragments | `<pack>/template-fragments/<topic>.template.md` | filename = define-block name |

What's notable: Gas Town does **not** use a `principles/`, `adr/`,
or `case-studies/` directory anywhere on `main`. The escalation
branch experiments with that shape, but everything currently merged
to main fits in: `docs/`, `docs/design/`, plus narrowly-named
project memos at the rig root (e.g. `learning_mockup_review-20260430.md`
sits at the gc-toolkit rig root rather than under `docs/`).

The "research vs adopted" distinction on the in-flight branch is
**path-based**: research lives under `docs/escalation/research/`,
"adopted" content (if it ever existed there) would graduate out to a
sibling like `docs/escalation/<topic>.md`, then likely migrate up to
`docs/<topic>.md` once general. The branch hasn't yet exercised the
"graduation" path — only filing.

## Lifecycle markers

Gas Town signals lifecycle through several mechanisms, in roughly
descending order of prevalence:

### 1. Path moves

The dominant mechanism. v1→v2 migration table in
`gas-city-reference.md` (line 1413+) is **expressed entirely as path
renames**:

> | Agent prompts | `prompts/<name>.md.tmpl` (flat) | `agents/<name>/prompt.template.md` |
> | Formula files | `formulas/<name>.formula.toml` | `formulas/<name>.toml` |
> | Order files | `orders/<name>/order.toml` | `orders/<name>.toml` (flat) |

Adopted content in `<rig>/docs/`, in-flight content in
`<rig>/docs/escalation/`, design content in `<rig>/docs/design/`.
Lifecycle = which directory you're in.

### 2. Strikethrough in markdown tables

`FUTURE.md` uses `~~text~~` inside table rows to mark resolved items
**without removing them**, preserving the audit trail of what
*was* missing. Resolved rows expand on the row to record what
replaced the missing command:

> | ~~`gc done`~~ | **RESOLVED:** Push branch + `bd create --type=merge-request --assignee=refinery` + `bd close <work-bead>` + exit | polecat, dog |

Visible in `FUTURE.md` line 20–24 and throughout subsequent tiers.

### 3. Filename version suffixes

`gas-city-pack-v2.md` carries the version in the filename when the
content is **specifically about that version**. The opening line
explicitly frames it: *"Structural reference for Pack/City v2, the
shape that landed with the 1.0 release."*

Singular reference docs (`gas-city-reference.md`) are *not*
versioned; they're rolled forward and date-stamped at the top:
*"Current as of v1.0.1 (2026-04-22)."*

### 4. Numeric prefixes for ordered series (in-flight only)

On the escalation branch, `r1-…`, `r2-…`, `v1-…`, `v2-…` give a
monotonic order to research surveys. The two letter prefixes
distinguish two parallel series (`r` = round-1 industry research,
`v` = validation/criticism rounds), so the same number across series
is intentional and not a collision.

### 5. Status frontmatter (in body, not YAML)

Design docs use prose status lines near the top:

> **Status:** approved design. Implementation bead to be filed by
> mechanik against this revision.

Visible in `docs/design/consult-surfacing.md`. There is no YAML
frontmatter — the status is one of the first lines in the document
body.

### 6. Header date stamps and "Current as of …" lines

`gas-city-reference.md` opens with a blockquote stating the
authoritative version it's documenting; `gas-city-pack-v2.md` opens
similarly with a release date. These are not in a structured field —
they're prose intended to be re-edited when the doc is rolled
forward.

### 7. "Out of scope" sections

Filing beads (e.g. `tk-yiwfz`) and approved design docs both use an
explicit `## Out of scope` section to fence what is *deliberately
excluded*, keeping intent legible to whoever picks the work up later.

## Well-named patterns (with reasoning)

### `mol-` prefix on formula files

`formulas/mol-polecat-work.toml`, `formulas/mol-witness-patrol.toml`,
etc. The `mol-` prefix maps directly to the in-system concept of a
**molecule** (the runtime instantiation of a formula). When an agent
sees `formula = "mol-polecat-work"` in a bead, the formula directory
filename is identical and immediately resolvable.

This also disambiguates from order files which sit alongside in
`orders/` and use no prefix. A reader scanning a tree sees
`mol-polecat-work.toml` vs `wisp-compact.toml` and knows the first is
a formula and the second is an order without opening either file.

### Convention directories with the directory name as canonical name

`agents/<name>/agent.toml` (no `name = "..."` field — directory **is**
the name); `commands/<name>/run.sh`; `doctor/<check-name>/doctor.toml`.

Why it works: the path becomes the namespace, files inside have fixed
generic names (`agent.toml`, `run.sh`, `prompt.template.md`,
`doctor.toml`), and grep/glob patterns are uniform across packs.
`gas-city-reference.md` line 223 documents the rationale: *"No `name`
field — the directory is the name."*

### `template-fragments/<topic>.template.md` with `{{ define "<topic>" }}`

`template-fragments/architecture.template.md` defines
`{{ define "architecture" }}`. The filename matches the define-block
name without the `.template.md` extension. A reader inspecting
`{{ template "architecture" . }}` in a prompt template can find the
definition by grepping the filename without parsing the file.

The convention extends to **specialized variants** with a kebab suffix:
`approval-fallacy.template.md` defines both
`{{ define "approval-fallacy-crew" }}` and
`{{ define "approval-fallacy-polecat" }}`. The file groups
related variants; the suffix on the define-block name distinguishes
audience.

### Themed namepools as flat `.txt` files

`assets/namepools/minerals.txt`, `agents/polecat/namepool.txt` (Mad
Max characters). Each file is one name per line, prefixed by a
`# Theme — themed pool names` header. Namepools are content, not
config; treating them as flat text keeps them legible and editable
by hand. The theme name in the filename (`minerals`, vs the
implicit theme-by-content for `polecat/namepool.txt`) tells a reader
the pool's flavor before opening it.

### Header comment block in every `pack.toml` and `city.toml`

Every manifest file opens with a multi-line `#` comment block that
states what the pack is for, what scope its agents have, and how it
composes with sibling packs. Example from
`packs/gastown/pack.toml`:

> ```
> # Gas Town — domain-specific coding workflow pack.
> #
> # Gastown roles: mayor (coordinator), deacon (patrol), boot (watchdog),
> # plus rig-scoped agents (witness, refinery, polecat).
> # Dog (utility pool) is defined here with tmux theming; maintenance provides
> # the fallback (unthemed) dog. Mechanical housekeeping lives in maintenance.
> #
> # Referenced by both workspace.pack and rigs[].pack:
> #   workspace.pack → expands city-scoped agents only (mayor, deacon, boot)
> #   rigs[].pack    → expands rig agents only (witness, refinery, polecat)
> ```

Why it works: this is the README of the pack, kept inside the file
that has to load anyway. There's nothing to keep in sync; the comment
sits next to the configuration it explains.

## Awkward patterns (with reasoning)

### Top-level vs `docs/`-nested overlap

Inside `examples/gastown/` the two narrative docs (`FUTURE.md`,
`SDK-ROADMAP.md`) are at the **example root**. Inside `gc-toolkit/`
the analogue (`roadmap.md`) is in **`docs/`** — but a roadmap-shaped
file (`learning_mockup_review-20260430.md`) lives at the **rig
root** while another roadmap-shaped file
(`docs/escalation/roadmap.md`) lives **two levels deep** on the
in-flight branch. There is no consistent rule for "where does a
roadmap-shaped doc go."

Compounding this: top-level files use `SCREAMING-KEBAB.md` while
`docs/`-nested files use `lowercase-kebab.md`, so a doc moving down a
level also has to be renamed.

### `*.md.tmpl` vs `*.template.md` extension drift

`gc-toolkit/prompts/mechanik.md.tmpl` (v1 shape) and
`gc-toolkit/agents/mechanik/prompt.template.md` (v2 shape) coexist
**with diverged content**: 135 lines vs 116 lines, with a different
section about reference docs in the v2 copy. The two-extension drift
makes it ambiguous which is canonical for a reader who doesn't know
the migration is in progress, and the duplication invites bit-rot.

`gas-city-reference.md` line 1450 calls this out as expected:
*"Legacy file naming for formulas/orders/prompts (still recognized,
but migrations go one-way)."*

### `learning_mockup_review-20260430.md` filename conflates date and topic

The single `_` in `learning_mockup_review-20260430.md` mixes
underscore-separated and dash-separated tokens, and the date is a
contiguous YYYYMMDD with no separator from the topic. None of:
- topic-yyyy-mm-dd.md
- yyyy-mm-dd-topic.md
- topic.yyyymmdd.md

is followed elsewhere; this single file invents its own scheme and
sits at the rig root rather than under `docs/`. It hints at a missing
convention for "dated working notes" — the kind of doc that ages out
quickly.

### `mol-` prefix only for formulas, but molecule-IDs everywhere else

The `mol-` prefix lives on formula filenames (`mol-polecat-work.toml`)
and on the formula's `formula = "mol-polecat-work"` line, but **bead
IDs** for poured molecules use neither (`tk-yiwfz.3`, `wt-…`). A
reader skimming bead lists won't see the `mol-` connection unless they
already know the formula is named that way. The prefix carries weight
in the file system and `gc formula list` output, but does not
propagate into the bead namespace.

### Pack subdirectories are documented only by `pack.toml` headers

There are **no `README.md` files inside `packs/gastown/` or any of its
subdirectories**. The agent in `agents/refinery/` cannot be
distinguished from `agents/witness/` without opening either
`agent.toml` or the prompt template. For a contributor reading the
tree from `find` output, the only document explaining a pack
subdirectory is the comment block in the parent `pack.toml`. This is
fine for a small pack and starts to bend at gc-toolkit scale where the
agent count grows.

### `docs/escalation/research/` mixes two prefix series at one level

Both `r1-…` (industry research) and `v1-…` (validation rounds) are
flat siblings in the same directory. A reader has to know that `r`
and `v` are *parallel* series with related-but-distinct intent. A
sub-directory split (`research/round-1/`, `research/validation/`) or
a longer prefix (`r-…`, `v-…` already work but a single letter is
load-bearing) would carry the distinction more legibly. The current
shape relies on the reader knowing the convention.

### `agents/concierge/example-city.toml` is a doc-shaped artifact in a config slot

`gc-toolkit/agents/concierge/example-city.toml` is a configuration
*example* — read by humans, not by `gc`. It demonstrates how to wire
the concierge into a consuming city. By convention the file would
live under `docs/examples/` or be a code-fenced block inside
`prompt.template.md`. Sitting in the agent dir alongside `agent.toml`
risks a future loader treating it as live config.

## Stated rationale

Where Gas Town documents *why* a naming choice was made:

### v1 → v2 migration justification

`gas-city-reference.md` line 161+ (V2 City & Pack Layout) frames the
v2 conventions as a deliberate flattening:

> A city root IS a pack. Its `pack.toml` declares `schema = 2` and can
> import other packs. `city.toml` carries only city-specific concerns
> (rigs, providers, daemon, beads, mail, dolt, etc.). Most
> agent/prompt/formula/order content lives in pack directories
> discovered by convention.

The migration table at line 1413 makes the rationale concrete: every
v1→v2 entry is a move toward **fewer infixes, fewer required
metadata fields, and the directory carrying the namespace**.

### Why worktrees are bead-scoped not agent-scoped

`mol-polecat-work.toml` lines 84–87 explains a naming-adjacent
ownership decision:

> Worktrees are scoped to the work bead (not the agent name) so that:
> - An agent can pick up new work even if an old worktree is being recovered
> - Multiple orphaned worktrees can coexist without collision
> - The witness cleans them independently per-bead

The path that records this is `metadata.work_dir` on the bead. Naming
choice = ownership choice.

### Why formula filenames moved off `.formula.` infix

`gas-city-reference.md` line 841: *"File naming in v2 is flat
`<name>.toml` under `formulas/` (the `.formula.` infix was removed)."*
No prose-level rationale is given, but the v2 design pattern is
consistent: convention dirs, no infix, single canonical filename per
artifact type.

### Why mechanik (gc-toolkit) duplicates the prompt during transition

`gas-city-reference.md` line 1450: *"Legacy file naming for
formulas/orders/prompts (still recognized, but migrations go
one-way)."* The duplication is intentional; the v1 shape stays loadable
for compatibility while the v2 shape becomes canonical.

### Why pack manifests carry a header comment

Implicit, not stated. The pattern is uniform across `pack.toml`,
`city.toml`, and several `*.toml` order files:
each file opens with a 3–8 line `#` comment describing purpose and
composition. Treating this as the README means the explanation can't
drift away from the configuration it explains.

## Notes for the synthesis bead

A few signals likely to matter when proposing a gc-toolkit
convention:

1. **Path is already the dominant signal in Gas Town.** The
   convention-directory pattern (`agents/<name>/`,
   `commands/<name>/`, `doctor/<check-name>/`) is well-established
   and works. Reaching for filename prefixes (`r1-`, `mol-`)
   should be reserved for cases where path-distinction is
   insufficient — ordered series, type-collisions in a flat dir.

2. **Gas Town has no precedent for `principles/`, `adr/`, or
   `case-studies/`.** These directories don't exist on `main`. If
   gc-toolkit adopts them, it's net-new territory; the convention
   chosen now becomes the example for future packs. Conversely, if
   gc-toolkit *doesn't* adopt them and instead uses
   `docs/<topic>.md`, that follows current Gas Town practice and
   keeps gc-toolkit close to the reference shape.

3. **Status-as-prose-blockquote** (`**Status:** approved design.`)
   is the only existing pattern for in-doc lifecycle marking. Gas
   Town has not adopted YAML frontmatter anywhere visible. If
   gc-toolkit wants frontmatter, it would be a deliberate divergence;
   the divergence should be documented.

4. **Numeric prefixes (`r1-`, `v1-`, …) only appear on the
   in-flight escalation branch.** They have not been ratified into
   the main shape. Treating them as "Gas Town convention" is
   premature; treating them as "experiment that earned its keep on
   one branch" is fairer.

5. **The `*.template.md` extension is load-bearing.** It marks
   "this file contains Go-template syntax and is composed at runtime."
   Any naming convention that touches prompt-shaped or
   fragment-shaped docs should respect it.

6. **Gas Town rolls reference docs forward in place,** dating them
   at the top (`Current as of v1.0.1 (2026-04-22)`), and reserves
   filename versioning (`gas-city-pack-v2.md`) for **frozen
   release-bound references**. The distinction is: living doc =
   stable name + dated body; frozen doc = versioned name. This
   distinction probably wants to carry into any gc-toolkit
   convention.

7. **The single `learning_mockup_review-20260430.md` file** at the
   gc-toolkit rig root is the only existing example of a "dated
   working note," and its naming is ad-hoc. Any synthesis should
   decide whether dated notes are a doc-type that deserves a
   convention (and where they go) or whether they should be filed
   as bead notes instead.

8. **Pack-internal docs are absent.** No `packs/<name>/README.md`,
   no `packs/<name>/CONVENTIONS.md`, no per-agent README. The
   pattern is "pack.toml header comment is the README." If
   gc-toolkit grows beyond the size where this scales, that
   becomes a decision worth marking explicitly.
