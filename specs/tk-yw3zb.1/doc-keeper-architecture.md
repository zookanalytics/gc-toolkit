---
name: doc-keeper Architecture Brief
description: How the gc-toolkit doc-keeper machinery routes drift signals and memory-promotion candidates into refinery-merged updates of central-tier docs, with the audit-feed → update-bead → worker-polecat → refinery loop described concretely against existing rig infrastructure.
---

# doc-keeper Architecture Brief

doc-keeper is a maintenance regime, not a new agent. It composes existing
gc-toolkit primitives — orders, formulas, polecats, refinery — into a
loop that keeps gc-toolkit's **agent brief** current as the world and the
codebase evolve.

## The charter model

The brief is the set of authoritative briefs under `docs/gascity-*.md`,
discovered by **globbing that path** — never a hand-maintained list (a
list recorded twice is a list that drifts). Today the glob is four docs:
`gascity-agents.md`, `gascity-local-patching.md`, `gascity-reference.md`,
`gascity-routing-model.md`. A fifth dropped into `docs/gascity-*.md`
(e.g. a future `gascity-packs.md`) enrolls automatically.

Each brief declares a **`## Scope`** section — its charter: the mandate
it speaks on and the boundaries it deliberately leaves to adjacent docs
(the convention is defined in `docs/file-structure.md` → "The Scope
section"). The charter is what doc-keeper holds each doc accountable to,
and the two ways a doc can fall out of step with its charter are exactly
the two audits:

- **Drift** — a claim in the doc is no longer true *within its scope*
  because an upstream change invalidated it. The **drift audit** catches
  this (keep each brief *true*).
- **Gap** — something *inside the doc's scope* is missing: a durable
  learning that belongs in the charter but was never written down. The
  **memory audit** catches this (keep each brief *complete*).

doc-keeper judges each brief against what its `## Scope` says it intends
to represent — not against a diff of git history. The unit of work it
produces is one upstream **change or learning** (§4), which may touch
more than one brief.

## 1. The loop

```
                  drift-audit (cron)               memory-audit (cron)
                       │                                  │
                       ▼                                  ▼
            files doc-update beads             files doc-update beads
                       │                                  │
                       └──────────────┬───────────────────┘
                                      ▼
                       routed to gc-toolkit.polecat pool
                                      ▼
                          worker polecat claims one
                                      ▼
                        edits the impacted brief(s)
                                      ▼
                    pushes branch, reassigns to refinery
                                      ▼
                refinery rebases, runs gates, opens one PR to main
                                      ▼
                       operator reviews and merges the PR
```

Every arrow is an existing primitive: existing agent types, a standard
`task` bead, and the generic refinery on its existing PR merge path.

## 2. Refinery contract for doc-only beads

Refinery (`mol-refinery-patrol`, version 4 in this rig) is **generic** —
it does not branch on bead type, label, or path-touched. A doc-only bead
flows the same way as a code-touching bead:

1. Polecat sets `metadata.branch` and `metadata.target` on the bead and
   reassigns to `${GC_RIG}/${binding_prefix}refinery`.
2. Refinery (the `find-work` step in `mol-refinery-patrol`) picks the
   bead off its assignee queue.
3. Refinery rebases the branch onto `metadata.target` (default `main`).
4. Refinery runs `setup_command`, `typecheck_command`, `lint_command`,
   `build_command`, and (if `run_tests=true`) `test_command`. The
   gc-toolkit rig leaves these empty in `pack.toml`, so all of these
   skip silently for our doc-only beads — as they do today for any
   bead in this rig. **No special doc-only test bypass is required.**
5. Refinery executes `merge-push` per `metadata.merge_strategy`. Every
   doc-update bead sets `mr`, so refinery opens one GitHub PR to `main`
   and treats PR creation as the terminal handoff. (The generic refinery
   also supports a `direct` fast-forward; doc-keeper does not use it.)
6. Refinery closes the bead with merge metadata.

**Molecule shape** (the polecat-side contract — the change-unit bead of
§4):

| Field | Value |
|---|---|
| Bead type | a standard `task` bead; doc-keeper is carried by `task_kind=doc-update` plus the `doc-keeper` / `doc-update` labels |
| Title | `doc-update: <one-line summary of the change>` |
| Description | the change request and its provenance — the upstream commit or memory entry that prompted it, the brief(s) it impacts, and what should change |
| Branch | `polecat/<bead-id>` (formula default) |
| Commit prefix | `docs(<scope>): ...` to match existing rig commit style |
| `metadata.target` | `main` — every doc-update lands directly on `main` |
| `metadata.merge_strategy` | `mr` — one small PR to `main` per edit (§3) |

### Why no special doc-only handling

The bead description asks "does refinery route doc-only work cleanly,
or does it expect code-touching beads (lint/test/build gates)?" — empty
gate commands skip silently in `mol-refinery-patrol` step `run-tests`,
so the answer is "yes, cleanly, today, without changes". If the gc-toolkit
rig later configures gates that *would* trip on doc-only changes (e.g. a
broken-link checker that lives in `lint_command`), that becomes a
real-time signal that the gate fits a different policy than blind-on-all-
beads — at which point we revisit. We do not pre-build a bypass for a
gate that does not exist.

## 3. No batching: one small PR per edit

An earlier design batched overlapping doc edits into a rolling
integration branch via an owned convoy, graduating the cycle to `main`
as one "rolling PR." The **2026-06-12 epic rescope dropped that
apparatus** in favour of the simplest thing that works: each
`doc-update` bead lands on `main` as its own small pull request
(`metadata.target = main`, `metadata.merge_strategy = mr`). No rolling
branch, no convoy, no cycle period.

Refinery still processes one bead per wisp iteration; the difference is
that there is no batching layer above it. One edit, one PR — each
reviewed and merged independently. This keeps every diff small and the
rejection-resume path clean, at the cost of more (but smaller) PRs.

The retired mechanism lived in `specs/tk-yw3zb.4/rolling-cycle-mechanism.md`
and `assets/scripts/doc-keeper-rolling-cycle*.sh`; both were deleted in
the same simplification.

## 4. The doc-update unit of work

The unit of work is **one upstream change or learning**, not "one doc".
A single change can touch several briefs at once — a routing-model
change that affects both `gascity-routing-model.md` and the routing
notes in `gascity-agents.md`, say — and the worker addresses it as ONE
atomic commit/PR editing whatever brief(s) the change impacts, carrying
clear **provenance**: the upstream gascity / gc-toolkit commit, or the
memory entry, that prompted it. Dedup is on the **change** — never two
PRs for the same change, and never two open PRs racing the same target.

This is plain polecat work, expressed in plain Gas City primitives:

- A doc-update bead is a **standard `task` bead** with a metadata
  discriminator — `task_kind=doc-update` plus the `doc-keeper` /
  `doc-update` labels — exactly as `mol-refinery-patrol` discriminates
  its pre-publish review beads with `task_kind=review`. There is **no
  custom bead "schema"**: the change request — which brief(s), what
  change, what provenance — lives in the bead body.
- It runs through the **standard `mol-polecat-work` lifecycle** — claim
  → branch → implement → self-review → refinery handoff. There is **no
  bespoke formula "extension"**: editing a doc is ordinary polecat work,
  and the polecat template already carries the skills to do it. The
  refinery opens one PR to `main` (`merge_strategy=mr`) and closes the
  bead, with no knowledge that doc-keeper exists.

> **Build status.** The worker leg is being conformed to this model by
> the machinery split filed under `tk-yw3zb` (§8). The earlier
> `mol-doc-update` formula used `extends` + a custom bead schema + a
> one-doc scope guard; the change-unit model drops all three — a change
> that legitimately spans two briefs is one atomic PR, not two beads.

## 5. Audit-feed formulas

Two cron-fired formulas (§7) surface work against the charter model.
Both glob `docs/gascity-*.md` for the brief set — no enumerated list —
and read each brief's `## Scope` to decide what is in-bounds. Both are
read-only (they file beads, never edit docs), bounded by a per-run cap,
and emit the same change-unit bead shape (§4): a standard `task` bead
with `task_kind=doc-update`, the change request and provenance in the
body, deduped on the change.

### 5a. drift-audit (`mol-doc-keeper-drift-audit`) — keep each brief *true*

Fires on cron. For each brief, given the upstream movement in the repos
it tracks (gascity at its remote `main`, gc-toolkit at `origin/main`,
since the last audit baseline), it asks the charter question: **is the
doc still true within its `## Scope`?** A change that invalidates a
claim the doc makes *inside its mandate* is drift, and the audit files
one change-unit bead citing the triggering commits as provenance. The
audit does not write the edit — it cites the change and names the
affected brief(s); the worker reads the cited commits and writes the
fix. (How the audit derives "relevant to this scope" from a prose
`## Scope` — versus the retired hardcoded per-doc source-glob table — is
the open design question in §9, owned by the `.6` re-model.)

Sub-bead `tk-yw3zb.6` (re-model tracked by §8).

### 5b. memory-audit (`mol-doc-keeper-memory-audit`) — keep each brief *complete*

Fires on cron. This is the **gap** audit. It scans accumulated durable
learnings (mechanik's auto-memory, primarily) and, for each, asks the
charter question from the other side: **does this fall inside some
brief's `## Scope` but isn't captured there?** An in-scope-but-missing
learning is a gap, and the audit files one change-unit bead proposing
the addition, citing the memory entry as provenance. (Worked example
from the operator: convention learnings like "GC uses `task_kind`, not
custom bead schemas; mols don't use a bespoke extension" fall inside a
brief's scope and should be caught as missing.) Stay-local notes —
corrections about an agent's own conduct, or one-off resolved incidents
whose durable record is git + the bead trail — fall *outside* every
brief's scope and are no-ops. The memory stays mechanik's; the audit
only surfaces.

Sub-bead `tk-yw3zb.7` (re-model tracked by §8).

## 6. Configuration: none (the rescope dropped `[doc-keeper]`)

An earlier design proposed a `[doc-keeper]` block in `pack.toml` (an
`enabled` flag, a `batching` toggle, a `cycle_period`, a per-run bead
cap, and the tracked-doc `brief` list). The **2026-06-12 epic rescope
removed it**. doc-keeper now reads no config block:

- **Enablement is import.** The two audit orders ship in the gc-toolkit
  pack's `orders/` layer (§7). Importing the pack makes them live; a rig
  that does not import gc-toolkit never sees them. There is no `enabled`
  flag to read.
- **The brief set is the `docs/gascity-*.md` glob**, resolved at run
  time — not an enumerated list in config, in a formula, or in this
  brief. There is exactly one source of truth (the filesystem), so the
  set cannot drift from a stale second copy. A new `docs/gascity-*.md`
  enrolls on the next run; a removed one drops out.
- **The per-run bead cap is a formula var** (`audit_max_beads_per_run`,
  poured at dispatch — drift-audit default 5, memory-audit default 3),
  not a config field.
- **No batching toggle** — batching was dropped wholesale (§3).

The glob resolves today to the four briefs named in "The charter model"
above. The earlier idealized names (`gas-city-reference.md`,
`gas-city-pack-v2.md`) and the `docs/principles/document-spec.md`
central doc never existed in the repo and are not part of the set.

## 7. Cron registration

Cron in this city is the `gc order` system, not crond. Orders live in
`<rig>/orders/<name>.toml`; the order file IS the registration and is
re-scanned on every `gc` start, so the schedule is durable across
controller restarts (unlike the session-only town `CronCreate`).

Two orders ship in the gc-toolkit pack's `orders/` layer. There is no
`enabled` gate — enablement is the pack being imported (§6). Both are
**rig-scoped with a BARE pool** so the wisp lands in, and is claimed
from, each importing rig's own polecat store; a rig-qualified pool or a
city scope would strand it. Sub-bead `tk-yw3zb.8` owns wiring; the
shipped shape:

```toml
# orders/doc-keeper-drift-audit.toml
[order]
description = "doc-keeper: scan gascity + gc-toolkit HEAD for agent-brief drift; file doc-update beads"
formula = "mol-doc-keeper-drift-audit"
trigger = "cooldown"
interval = "24h"
pool = "gc-toolkit.polecat"
scope = "rig"
```

```toml
# orders/doc-keeper-memory-audit.toml
[order]
description = "doc-keeper: scan mechanik auto-memory for promote-to-brief candidates; file doc-update beads"
formula = "mol-doc-keeper-memory-audit"
trigger = "cooldown"
interval = "24h"
pool = "gc-toolkit.polecat"
scope = "rig"
```

**Pool-wake prerequisite:** a formula routed to a scale-from-zero pool
only wakes a worker when its compiled root is Ready-visible, which
requires the audit formulas to declare a top-level `phase = "vapor"`.
Without it the order fires on schedule but no polecat spawns. Land the
`.6`/`.7` formulas before/with these orders so a fire never fails
"formula not found."

## 8. Sub-bead mapping

How the seven existing build-phase sub-beads (`tk-yw3zb.2` through
`tk-yw3zb.8`, filed by the prior scout pass) map to the brief:

| Sub-bead | Section in this brief |
|---|---|
| `tk-yw3zb.2` doc-keeper: rename to 'agent brief' terminology | `central-doc-inventory.md` §1a; this brief §6 |
| `tk-yw3zb.3` doc-keeper: define `[doc-keeper]` config block | **superseded** — the `[doc-keeper]` config block was dropped by the 2026-06-12 rescope (§6) |
| `tk-yw3zb.4` doc-keeper: rolling-cycle mechanism | **superseded** — the rolling-cycle apparatus was dropped by the rescope; spec + scripts deleted (§3) |
| `tk-yw3zb.5` doc-keeper: doc-update worker polecat formula | this brief §4 |
| `tk-yw3zb.6` doc-keeper: drift-audit polecat formula | this brief §5a |
| `tk-yw3zb.7` doc-keeper: memory-audit polecat formula | this brief §5b |
| `tk-yw3zb.8` doc-keeper: cron registration | this brief §7 |

The build-phase dependency wiring predates the rescope: with `.3` (config
block) and `.4` (rolling-cycle) now superseded (§6, §3), those two drop off
the critical path. The terminology lock (`tk-yw3zb.2`) and the `.5`–`.8`
worker/audit/cron chain still stand — no rewires needed for the surviving
work.

### Charter-driven re-model (operator #122 review)

The 2026-06-13 operator review of #122 reworked doc-keeper to the charter
model above. It lands in stages:

| Bead | Carries |
|---|---|
| `tk-yw3zb.10` | **Foundation (landed):** the `## Scope` convention in `docs/file-structure.md`, a `## Scope` charter on each of the 4 briefs, and this brief's re-model to the charter-driven model. |
| `tk-o28ci` | doc-update bead-shape + worker conformance: a standard `task` bead + `task_kind=doc-update`, dropping the `extends` extension and the custom schema, with the unit of work = the change (§4). The keystone shape. |
| `tk-ej8s1` | charter-driven audit re-model (§5): both audits glob `docs/gascity-*.md`, read each `## Scope`, and emit change-unit beads; fixes the formula doc-set/reference errors and reconciles `central-doc-inventory.md`. Blocked by `tk-o28ci`. |

The `.5`/`.6`/`.7` formulas are re-modeled by `tk-o28ci` / `tk-ej8s1`;
until those land, the formulas on this branch still implement the
pre-charter (source-glob + custom-schema) shape, so this brief leads the
implementation by design.

## 9. Open questions for mechanik review

- **Deriving scope-relevance from a prose `## Scope`** (owned by
  `tk-ej8s1`, §5a). The retired model used a hardcoded per-doc
  source-glob table — the thing the operator rejected. The charter model
  needs a non-hardcoded way for an audit to decide "this upstream change
  / this learning is relevant to *this* brief's scope." Candidates:
  (a) grep upstream commit diffs / memory entries for salient terms
  drawn from the doc's `## Scope`; (b) a coarse audit (any upstream
  movement) that hands the true-within-scope / in-scope-but-missing
  judgment to the worker reading the `## Scope`; (c) a lightweight,
  scope-derived (not hand-maintained) relevance hint. This shapes both
  audits and the per-doc baseline/state mechanism.
- **A `gascity-packs.md` brief?** The operator flagged packs as a topic
  of particular interest worth its own brief. It is not yet written; if
  added under `docs/gascity-*.md` with a `## Scope`, it enrolls in both
  audits automatically (no list to update — that is the point of the
  glob). File it as its own doc bead when the content is ready.
- **Migration of `docs/design/` and `docs/research/`** to `specs/<bead>/`
  is recommended by the inventory but not filed as a sub-bead. File a
  one-shot cleanup bead under `tk-yw3zb`, or skip and leave the
  misplacement cosmetic? (No effect on doc-keeper functioning either way.)
- **First-run yield expectation** — §1d of the inventory predicts a
  high-yield first memory-audit pass against `docs/gascity-reference.md`.
  The `audit_max_beads_per_run` var (memory-audit default 3) throttles
  that first pass — pour a higher value (e.g. 20) for the initial
  backfill, then let it default back.
