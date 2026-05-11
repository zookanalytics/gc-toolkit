---
name: Central-Doc Inventory for doc-keeper
description: Inventory of gc-toolkit central-tier documentation candidates plus operational-knowledge surfaces, evaluated against docs/file-structure.md tier criteria, with per-item maintenance-mechanism recommendations.
---

# Central-Doc Inventory for doc-keeper

This inventory is the input to the `[doc-keeper]` config block (sub-bead
`tk-yw3zb.3`). Each row classifies an existing artifact against
`docs/file-structure.md`'s two-tier criteria (durable + authoritative + owned)
and proposes a keep-current mechanism. Decisions noted as *recommend* are
the scout's call; mechanik signs off before any of them lands as config.

## Method

Walked three surfaces:

1. `docs/` — current central-tier filings (17 files in 4 groups).
2. `agents/<name>/` — agent prompt templates and provenance files.
3. Mechanik auto-memory at
   `/home/zook/.claude/projects/-home-zook-loomington/memory/`
   (100 entries indexed in `MEMORY.md`).

For each item, asked the four file-structure.md questions:

- *Durable* — does the artifact's truth-life outlast a single piece of work?
- *Authoritative* — does someone consult this as ground truth?
- *Owned* — is there a named owner who'll keep it current?
- *If yes to all three* — central. Otherwise local-tier or out-of-scope.

## 1. `docs/` inventory

### 1a. Top-level files

| Path | Tier | Owner | Keep-current mechanism | Decision |
|---|---|---|---|---|
| `docs/file-structure.md` | central | gc-toolkit | organic (touched in same PR as the convention change) | **keep central; doc-keeper-tracked** |
| `docs/roadmap.md` | central | mechanik | organic (touched as roadmap state moves) + periodic drift-audit on referenced features/beads | **keep central; doc-keeper-tracked** |
| `docs/gas-city-reference.md` (1600 lines) | central | gc-toolkit ⨯ gascity | drift-audit (gascity HEAD changes invalidate sections) | **keep central; doc-keeper-tracked; "agent brief"** |
| `docs/gas-city-pack-v2.md` (291 lines) | central | gc-toolkit ⨯ gascity | drift-audit | **keep central; doc-keeper-tracked; "agent brief"** |
| `docs/gascity-local-patching.md` (218 lines) | central | gc-toolkit | organic (touched as local-patching strategy evolves) | **keep central; doc-keeper-tracked; "agent brief"** |

### 1b. `docs/principles/`

| Path | Tier | Owner | Keep-current mechanism | Decision |
|---|---|---|---|---|
| `docs/principles/document-spec.md` (710 lines) | central | gc-toolkit | organic + memory-audit (mechanik observations may surface principle drift) | **keep central; doc-keeper-tracked** |

### 1c. `docs/design/`

These are sketches, feasibility studies, and proposals. Per
`docs/file-structure.md` §"Inside `docs/`", *research is usually bead-tied*
and *notes are bead-tied*. Each carries explicit "sketch" / "feasibility /
not approved" status markers and a bead reference.

| Path | Current bead anchor | Tier per spec | Recommendation |
|---|---|---|---|
| `docs/design/cockpit-sketch.md` | (no bead linked) | local | **migrate to `specs/<bead>/`** — file a bead if none exists |
| `docs/design/consult-session-feasibility.md` | tk-bek | local | **migrate to `specs/tk-bek/`** |
| `docs/design/consult-session-v2-impl.md` | (consult v2 lineage) | local | **migrate to appropriate `specs/<bead>/`** |
| `docs/design/consult-surfacing.md` | (consult lineage) | local | **migrate to appropriate `specs/<bead>/`** |

Migration is **out of scope for the doc-keeper machinery itself** and is not
a doc-keeper-tracked surface. Worth a separate one-shot cleanup bead under
`tk-yw3zb` only if mechanik wants the layout aligned before doc-keeper
turns on. A live doc-keeper has nothing to do here either way.

### 1d. `docs/research/`

Both subdirectories carry the "Bead:" / "Surveyed:" markers that
`docs/file-structure.md` reserves for bead-tied research:

| Path | Bead | Recommendation |
|---|---|---|
| `docs/research/naming-conventions/spec-kit.md` | (tk-yiwfz lineage) | **migrate to `specs/tk-yiwfz/`** |
| `docs/research/naming-conventions/bmad-method.md` + `bmad-method-templates.md` | (tk-yiwfz lineage) | **migrate to `specs/tk-yiwfz/`** |
| `docs/research/naming-conventions/gastown.md` | (tk-yiwfz lineage) | **migrate to `specs/tk-yiwfz/`** |
| `docs/research/naming-conventions/kiro.md` | (tk-yiwfz lineage) | **migrate to `specs/tk-yiwfz/`** |
| `docs/research/naming-conventions/superpowers.md` | (tk-yiwfz lineage) | **migrate to `specs/tk-yiwfz/`** |
| `docs/research/pack-architecture/spike-gc-toolkit-as-primary-pack.md` | tk-rw0cb | **migrate to `specs/tk-rw0cb/`** |

Same scoping note as design/: out of scope for the live doc-keeper, possibly
worth a one-shot cleanup bead.

## 2. Operational knowledge surfaces

### 2a. Agent prompt templates (`agents/<name>/prompt.template.md`)

| Surface | Tier evaluation | Decision |
|---|---|---|
| `agents/{mayor,deacon,boot,witness,refinery,polecat}/prompt.template.md` | These are agent behavior specs, not "what is true now" docs. They are versioned in source and hot-reloaded into sessions on prime. | **out of scope for doc-keeper** — separate maintenance regime (prompt-engineering reviews, vendor-pack updates) |
| `agents/{architect,concierge,consult-host,gascity-keeper,mechanik,polecat-codex}/prompt.template.md` | Same as above; native gc-toolkit agents. | **out of scope** |
| `agents/<name>/PROVENANCE.md` | Records vendoring source/SHA for the prompt. Static per-agent reference. | **out of scope** — touched at vendor-import time, not by drift |
| `agents/_polecat-gemini/prompt.template.md` | Underscore-prefixed = staged, not active. | **out of scope** |
| `agents/architect/consult-layer.md` | Agent-specific reference loaded into the architect prompt; effectively part of the agent brief surface but agent-scoped. | **out of scope for doc-keeper v1** — revisit if we generalize beyond the canonical-three brief |
| `agents/DOG-NOTE.md` | Static note about why dog isn't vendored. | **out of scope** — touched only when the upstream gripe is resolved |

The "agent brief" recommendation in sub-bead `tk-yw3zb.2` is what lets
doc-keeper claim authority over the canonical-three brief docs *as docs*,
without needing to also own the prompt templates that *cite* them.

### 2b. Mechanik auto-memory

Surface: `/home/zook/.claude/projects/-home-zook-loomington/memory/`. 100
entries indexed in `MEMORY.md`. Two filename families: `feedback_*.md` (rules
mechanik has been corrected on) and `project_*.md` (incident records and
current-state operational facts).

Per the `docs/file-structure.md` rule that "research is usually bead-tied"
and the explicit allowance that "a central doc that *consumes* research over
time fits central tier because the doc itself meets the durable +
authoritative + maintained bar", memory entries split three ways:

| Pattern | Examples (from MEMORY.md head) | Tier evaluation | Decision |
|---|---|---|---|
| **Promote candidates** — durable operational truths that other agents/operators would benefit from as ground truth | `project_gastown_ships_from_gascity.md`, `project_gascity_upstream_fork.md`, `feedback_bead_store_matches_scope.md`, `feedback_dispatch_via_sling_not_mayor.md`, `project_gc_toolkit_pr_squash_workflow.md`, `project_setup_timeout_60s.md` | **central candidate** — would land as paragraphs in `docs/gas-city-reference.md`, `docs/gascity-local-patching.md`, or a new `docs/operations.md` | **memory-audit surfaces; mechanik+operator decide promotion case-by-case** |
| **Stay-local — rule + reason** — corrections specific to mechanik's behavior or workflow that other agents wouldn't act on | `feedback_dont_manufacture_tension.md`, `feedback_execute_directive_dont_present_options.md`, `feedback_root_cause_first.md`, `feedback_skip_stopgap_when_polecat_dispatched.md` | local — operator-mechanik communication, not ground truth | **stay in memory** |
| **Stay-local — incident** — historical incidents that informed a now-resolved fix | `project_compactor_zfc_mismatch.md`, `project_disk_full_dolt_panic.md`, `project_dolt_stale_lockfile.md`, `project_mayor_crash_loop_dead_pane.md` | local — git history and bead trail are the durable record; the memory entry is mechanik's working note | **stay in memory** |

The audit formula (`tk-yw3zb.7`) walks every entry, classifies into one of
the three buckets, and files a `doc-update` bead **only for the promote
candidates**. Stay-local entries are no-ops. The decision to actually
promote a candidate stays with mechanik+operator — the audit surfaces, it
does not commit.

A specific structural pattern from the head of `MEMORY.md` worth flagging:
many `project_gascity_*` and `project_gastown_*` entries already match
sections of `docs/gas-city-reference.md`. The first promotion pass will
likely be high-yield against that doc. After the first pass settles, drift
will dominate and yield will drop — that is the steady state we design for.

### 2c. CLAUDE.md / role primers

The polecat's role context is injected by `gc prime` from agent-prompt
templates, not from a `CLAUDE.md` in the rig root. There is no top-level
`CLAUDE.md` in `gc-toolkit/` to maintain. Out of scope.

## 3. Recommendations

### 3a. Doc-keeper-tracked set (the `[doc-keeper].brief` list)

The six docs in §1a + §1b. The `[doc-keeper]` config block enumerates
this list — no implicit globbing — so adding a new central doc is a
deliberate config edit, not a side-effect of dropping a markdown file
into `docs/`. The brief sub-flavor (the canonical-three) is a tag on
three of those six rows, not a separate file list.

### 3b. Migration parking lot (out of scope for doc-keeper)

`docs/design/*` and `docs/research/*` should migrate to `specs/<bead>/`.
Worth a separate one-shot cleanup bead **under epic `tk-yw3zb`** if
mechanik wants the layout aligned before doc-keeper goes live; otherwise
the live doc-keeper ignores them and the misplacement is cosmetic. Not
filed by this scout — mechanik calls it.

### 3c. Memory-promotion ground rules

The memory-audit polecat (`tk-yw3zb.7`) MUST NOT auto-write to central
docs. It files `doc-update` beads with the candidate paragraph drafted and
the source memory file cited. Mechanik (the memory's owner) is the only
agent that can approve a promotion. This preserves mechanik's ownership of
the memory while letting durable bits surface.

### 3d. Frontmatter audit (incidental)

`docs/file-structure.md` has the recommended `name`/`description`
frontmatter; `docs/gas-city-reference.md`, `docs/gas-city-pack-v2.md`,
`docs/gascity-local-patching.md`, `docs/roadmap.md`, and
`docs/principles/document-spec.md` do not. Per `docs/file-structure.md`
§"Frontmatter", central docs are *strongly encouraged* (not required) to
carry frontmatter. The drift-audit can include a "missing frontmatter"
finding for tracked docs — cheap, actionable, doesn't gate anything.
