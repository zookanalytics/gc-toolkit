---
name: doc-keeper Architecture Brief
description: How the gc-toolkit doc-keeper machinery routes drift signals and memory-promotion candidates into refinery-merged updates of central-tier docs, with the audit-feed → update-bead → worker-polecat → refinery loop described concretely against existing rig infrastructure.
---

# doc-keeper Architecture Brief

doc-keeper is a maintenance regime, not a new agent. It composes existing
gc-toolkit primitives — orders, formulas, polecats, refinery — into
a loop that keeps the central-tier docs enumerated as a constant in each
audit formula (see `specs/tk-yw3zb.1/central-doc-inventory.md`)
current as the world or the codebase evolves.

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
                            edits one central doc
                                      ▼
                    pushes branch, reassigns to refinery
                                      ▼
                refinery rebases, runs gates, opens one PR to main
                                      ▼
                       operator reviews and merges the PR
```

Every arrow is an existing primitive. Nothing in this design adds a new
agent type, new bead type, or new merge mechanism.

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

**Molecule shape** (the polecat-side contract consumed by the worker
polecat, §4):

| Field | Value |
|---|---|
| Bead type | `task` (no new type required; `doc-update` is a label, not a type) |
| Title | `doc-update: <docs/path>: <one-line summary>` |
| Description | What needs to change, why, source signal (drift hash diff or memory file cite), proposed copy or diff |
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

## 4. Worker polecat (standard `mol-polecat-work`)

No bespoke worker formula. A `doc-update` bead is ordinary polecat
work: the audit (or organic filer) routes it to the `gc-toolkit.polecat`
pool (`metadata.gc.routed_to`) and the **standard `mol-polecat-work`
lifecycle** claims and runs it. The bead's body and metadata — not a
custom formula — steer the edit:

| Standard step | What a `doc-update` bead drives |
|---|---|
| `load-context` | Bead body cites the source signal (drift hash + path, or memory file path) and names the target doc; the polecat loads the cited central doc and the signal contents. |
| `workspace-setup` | Branches `polecat/<bead>` from `origin/main` (`metadata.target` defaults to `main`). |
| `preflight-tests` | Inherited; skips silently when the rig leaves the commands empty. |
| `implement` | Edit the single central doc named in `## Target` / `metadata.doc_keeper.target_doc`. One focused `docs(<scope>): ...` commit; touch no file outside the tracked central-tier doc set. |
| `self-review` | Inherited. |
| `submit-and-exit` | Inherited — reassigns to the refinery, which opens one PR to `main` (`merge_strategy=mr`). |

An earlier design (sub-bead `tk-yw3zb.5`) gave this leg its own thin
`extends = ["mol-polecat-work"]` formula (`mol-doc-update`); the
change-unit rescope dropped it in favour of plain `mol-polecat-work`
driven by the bead shape. Single-doc scope per bead remains the
keystone — it keeps the worker polecat short, the diff small, and the
rejection-resume path clean.

## 5. Audit-feed formulas

Two cron-fired formulas produce update beads. Both are stateless modulo
git+memory and both are bounded — they file a configurable max number of
update beads per run to avoid swamping the pool.

### 5a. drift-audit (`mol-doc-keeper-drift-audit`)

Fires on cron (§7). Walks the diff between **last-audit hashes** (stored
in a per-doc audit-state bead per central doc) and current HEAD across
two repositories: gascity at `$GASCITY_REMOTE/main` and gc-toolkit at
`origin/main`. For each tracked doc in the formula's constant tracked-doc
table, asks: does any commit in the diff window touch a path the doc
claims authority over? Each table entry maps a doc to the source-path
globs it tracks (the rescope folded the old per-doc `source_paths` config
into this in-formula table). Anything hitting an owned glob produces one
`doc-update` bead.

The audit does **not** propose edits. It cites the commits that triggered
the signal and the section that needs review. The worker polecat reads
the cited commits and writes the actual edit.

Sub-bead `tk-yw3zb.6`.

### 5b. memory-audit (`mol-doc-keeper-memory-audit`)

Fires on cron (§7). Walks `/home/zook/.claude/projects/-home-zook-
loomington/memory/` looking for entries that match the **promote
candidate** pattern from `central-doc-inventory.md` §2b. Implementation:

1. List all memory `.md` files modified since `last-audit-tick` (stored
   in an audit-state bead).
2. For each, classify into bucket A (promote candidate) / B (rule + reason
   stay-local) / C (incident stay-local). Classification is a deterministic
   filename-+-frontmatter check, not LLM judgment, to keep the audit cheap
   and idempotent. Filename heuristics: `project_gascity_*`,
   `project_gastown_*`, `project_gc_toolkit_*` skew bucket A; `feedback_*`
   that name mechanik behaviors (e.g. `feedback_dont_*`,
   `feedback_execute_*`) skew bucket B; `project_*` that name an incident
   verb (panic, crash, race, leak) skew bucket C.
3. For each bucket-A entry, file ONE `doc-update` bead with proposed
   target doc (best fit from the tracked central-tier doc set), proposed
   paragraph draft, and the source memory file cited. The proposed target is the
   audit's recommendation; the worker polecat may pick a different
   target doc if the recommendation is wrong.

The memory remains mechanik's. The audit only surfaces.

Sub-bead `tk-yw3zb.7`.

## 6. Configuration: none (the rescope dropped `[doc-keeper]`)

An earlier design proposed a `[doc-keeper]` block in `pack.toml` (an
`enabled` flag, a `batching` toggle, a `cycle_period`, a per-run bead
cap, and the tracked-doc `brief` list). The **2026-06-12 epic rescope
removed it**. doc-keeper now reads no config block:

- **Enablement is import.** The two audit orders ship in the gc-toolkit
  pack's `orders/` layer (§7). Importing the pack makes them live; a rig
  that does not import gc-toolkit never sees them. There is no `enabled`
  flag to read.
- **The tracked-doc set is a constant** inside each audit formula,
  existence-checked against the live `docs/*.md` set at run time — a
  formula whose own doc list drifts is the one thing the audit cannot
  afford. See `central-doc-inventory.md` for the canonical list.
- **The per-run bead cap is a formula var** (`audit_max_beads_per_run`,
  poured at dispatch — drift-audit default 5, memory-audit default 3),
  not a config field.
- **No batching toggle** — batching was dropped wholesale (§3).

Current brief landing docs (verify at file time; names drift):
`docs/gascity-reference.md` (the always-present anchor),
`docs/gascity-local-patching.md`, `docs/gascity-agents.md`,
`docs/gascity-routing-model.md`. The earlier hyphenated names
(`gas-city-reference.md`, `gas-city-pack-v2.md`) do not exist in the repo.

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

## 9. Open questions for mechanik review

- **Migration of `docs/design/` and `docs/research/`** to `specs/<bead>/`
  is recommended by the inventory but not filed as a sub-bead. File a
  one-shot cleanup bead under `tk-yw3zb`, or skip and leave the
  misplacement cosmetic? (No effect on doc-keeper functioning either way.)
- **First-run yield expectation** — §1d of the inventory predicts a
  high-yield first memory-audit pass against `docs/gascity-reference.md`.
  The `audit_max_beads_per_run` var (memory-audit default 3) throttles
  that first pass — pour a higher value (e.g. 20) for the initial
  backfill, then let it default back.
