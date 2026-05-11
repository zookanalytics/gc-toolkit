---
name: doc-keeper Architecture Brief
description: How the gc-toolkit doc-keeper machinery routes drift signals and memory-promotion candidates into refinery-merged updates of central-tier docs, with the audit-feed → update-bead → worker-polecat → refinery loop described concretely against existing rig infrastructure.
---

# doc-keeper Architecture Brief

doc-keeper is a maintenance regime, not a new agent. It composes existing
gc-toolkit primitives — orders, formulas, polecats, refinery, convoys — into
a loop that keeps the central-tier docs enumerated in
`[doc-keeper].brief` (see `specs/tk-yw3zb.1/central-doc-inventory.md`)
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
                refinery rebases, runs gates, merges to main
                                      ▼
                          (optional) batched into a
                          rolling integration branch
                          via a doc-keeper convoy
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
5. Refinery executes `merge-push` per `metadata.merge_strategy`:
   - `direct` (default): fast-forward to `metadata.target` and push.
   - `mr` / `pr`: open a GitHub PR and treat PR creation as the
     terminal handoff.
6. Refinery closes the bead with merge metadata.

**Molecule shape** (the polecat-side contract, set by the worker formula
described in §4):

| Field | Value |
|---|---|
| Bead type | `task` (no new type required; `doc-update` is a label, not a type) |
| Title | `doc-update: <docs/path>: <one-line summary>` |
| Description | What needs to change, why, source signal (drift hash diff or memory file cite), proposed copy or diff |
| Branch | `polecat/<bead-id>` (formula default) |
| Commit prefix | `docs(<scope>): ...` to match existing rig commit style |
| `metadata.target` | `main` for direct flow, or `integration/doc-keeper-<period>` when batching (§3) |
| `metadata.merge_strategy` | `direct` for the steady state |

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

## 3. Batching: convoys + integration branches

The bead description asks "how does refinery batch overlapping branches
into one rolling PR?" — refinery itself does **not** batch. It processes
one bead per wisp iteration. Batching is achieved one layer up via
**owned convoys with integration-branch targets**:

```bash
gc convoy create doc-keeper-cycle-2026-W19 \
  --owned \
  --target integration/doc-keeper-2026-W19 \
  --merge mr
```

The convoy sets `metadata.target = integration/doc-keeper-2026-W19` on
itself; child work beads inherit the target via the existing convoy-
ancestor walk (`mol-polecat-work` step `workspace-setup` resolves
`{{base_branch}}` from the parent convoy). Each doc-update bead lands
into the integration branch as the worker polecat completes it.

When the cycle closes (the cron fires the next audit, or an operator
ends the cycle):

```bash
gc convoy land doc-keeper-cycle-2026-W19
```

`gc convoy land` (existing command) creates a graduation bead targeting
`main`; refinery handles the graduation as a normal merge or PR per
`--merge` setting. Setting `--merge mr` on the convoy means refinery's
graduation step opens one PR for the whole cycle's worth of doc edits —
the "rolling PR" pattern.

The cycle period is **doc-keeper config**, not refinery config. Default
proposal: weekly cycles named `doc-keeper-<ISO-week>`. Sub-bead
`tk-yw3zb.4` owns the rolling-cycle mechanism in detail; this brief
records that the mechanism is `gc convoy --owned --target integration/...`
and not new infrastructure.

If `[doc-keeper].batching = false`, child beads target `main` directly
and the rolling-PR pattern is skipped. Direct-merge mode is the simplest
path and is the recommended starting point for week one — switch on
batching only when individual doc edits start landing too noisily on
main.

## 4. Worker polecat formula (`mol-doc-update`)

A new variant of `mol-polecat-work`. **Formula identity, not a new agent
type** — same `gc-toolkit.polecat` template fills the role.

| Step (inherited from base) | Override note |
|---|---|
| `load-context` | Read `metadata.source_signal` (drift hash + path, or memory file path); load the cited central doc; load the source signal contents. |
| `workspace-setup` | Standard polecat-work workspace-setup. Honors `{{base_branch}}` from convoy chain (§3). |
| `preflight-tests` | Inherited; skips silently when commands empty. |
| `implement` | Edit the single central doc named in the bead. Make a single focused commit `docs(<scope>): ...`. Forbidden: editing files outside the central-tier set in `[doc-keeper].brief`. |
| `self-review` | Inherited. |
| `submit-and-exit` | Inherited. |

Sub-bead `tk-yw3zb.5` owns the formula authoring; this brief records
the *shape*. Single-doc scope per bead is the keystone — keeps the
worker polecat short, the diff small, and the rejection-resume path
clean.

## 5. Audit-feed formulas

Two cron-fired formulas produce update beads. Both are stateless modulo
git+memory and both are bounded — they file a configurable max number of
update beads per run to avoid swamping the pool.

### 5a. drift-audit (`mol-doc-keeper-drift-audit`)

Fires on cron (§7). Walks the diff between **last-audit hashes** (stored
in a per-doc audit-state bead per central doc) and current HEAD across
two repositories: gascity at `$GASCITY_REMOTE/main` and gc-toolkit at
`origin/main`. For each tracked doc in `[doc-keeper].brief`, asks: does
any commit in the diff window touch a section the doc claims authority
over? Section ownership is encoded by a `<!-- doc-keeper:owns
<glob-pattern> -->` annotation block in each tracked doc, OR a
`source_paths = [...]` field per doc in `[doc-keeper].brief`. Anything
hitting an owned glob produces one `doc-update` bead.

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
   target doc (best fit from `[doc-keeper].brief`), proposed paragraph
   draft, and the source memory file cited. The proposed target is the
   audit's recommendation; the worker polecat may pick a different
   target doc if the recommendation is wrong.

The memory remains mechanik's. The audit only surfaces.

Sub-bead `tk-yw3zb.7`.

## 6. Configuration: `[doc-keeper]` block

Lives in `pack.toml` (per-rig) or city.toml (cross-rig override). Per
sub-bead `tk-yw3zb.3`, the schema lock proposal:

```toml
[doc-keeper]
enabled = true
batching = false                            # default off; switch on later
cycle_period = "weekly"                     # weekly | manual
audit_max_beads_per_run = 5                 # safety cap
brief_label = "agent brief"                 # display name for the canonical-three (§1a row 3-5)

[[doc-keeper.brief]]
path = "docs/file-structure.md"
source_paths = ["docs/file-structure.md"]   # self-referential; only PRs that touch this file
brief = false

[[doc-keeper.brief]]
path = "docs/roadmap.md"
source_paths = []                           # purely organic; drift-audit yields nothing for this
brief = false

[[doc-keeper.brief]]
path = "docs/gas-city-reference.md"
source_paths = [
    "rigs/gascity/cmd/**",
    "rigs/gascity/internal/**",
    "rigs/gascity/docs/**",
]
brief = true                                # part of the canonical-three

[[doc-keeper.brief]]
path = "docs/gas-city-pack-v2.md"
source_paths = [
    "rigs/gascity/internal/pack/**",
    "rigs/gascity/internal/city/**",
]
brief = true

[[doc-keeper.brief]]
path = "docs/gascity-local-patching.md"
source_paths = []                           # organic-only
brief = true

[[doc-keeper.brief]]
path = "docs/principles/document-spec.md"
source_paths = ["docs/principles/document-spec.md"]
brief = false
```

`source_paths` is the explicit input the drift-audit walks. Empty
`source_paths` means "no drift-audit findings for this doc; updates
happen organically or via memory-audit." Authoritative spec lives with
sub-bead `tk-yw3zb.3`.

## 7. Cron registration

Cron in this city is the `gc order` system, not crond. Orders live in
`<rig>/orders/<name>.toml`; the deacon's `periodic-formulas` step
dispatches them via cooldown/cron triggers (see
`rigs/gc-toolkit/orders/digest-generate.toml` for the existing pattern).

Two new orders, both gated by `[doc-keeper].enabled = true`. Sub-bead
`tk-yw3zb.8` owns wiring; the shape:

```toml
# rigs/gc-toolkit/orders/doc-keeper-drift-audit.toml
[order]
description = "Scan gascity + gc-toolkit HEAD for drift against tracked central docs"
formula = "mol-doc-keeper-drift-audit"
trigger = "cooldown"
interval = "168h"                           # weekly
pool = "gc-toolkit/gc-toolkit.polecat"
enabled_when = "config.doc_keeper.enabled"
```

```toml
# rigs/gc-toolkit/orders/doc-keeper-memory-audit.toml
[order]
description = "Scan mechanik auto-memory for promote-to-central-doc candidates"
formula = "mol-doc-keeper-memory-audit"
trigger = "cooldown"
interval = "168h"                           # weekly, lagged 24h behind drift-audit
pool = "gc-toolkit/gc-toolkit.polecat"
enabled_when = "config.doc_keeper.enabled"
```

`enabled_when` is conditional support that may need adding to the order
runner if it doesn't exist yet — `tk-yw3zb.8` confirms during wiring;
fallback is to leave the orders absent until enabled and add them at
flip-on time.

## 8. Sub-bead mapping

How the seven existing build-phase sub-beads (`tk-yw3zb.2` through
`tk-yw3zb.8`, filed by the prior scout pass) map to the brief:

| Sub-bead | Section in this brief |
|---|---|
| `tk-yw3zb.2` doc-keeper: rename to 'agent brief' terminology | `central-doc-inventory.md` §1a; this brief §6 (`brief_label`, `brief = true` rows) |
| `tk-yw3zb.3` doc-keeper: define `[doc-keeper]` config block | this brief §6 |
| `tk-yw3zb.4` doc-keeper: rolling-cycle mechanism | this brief §3 |
| `tk-yw3zb.5` doc-keeper: doc-update worker polecat formula | this brief §4 |
| `tk-yw3zb.6` doc-keeper: drift-audit polecat formula | this brief §5a |
| `tk-yw3zb.7` doc-keeper: memory-audit polecat formula | this brief §5b |
| `tk-yw3zb.8` doc-keeper: cron registration | this brief §7 |

The dependency wiring on those sub-beads (`tk-yw3zb.2` blocks the rest
because terminology must lock before `[doc-keeper]` config schema)
remains correct under this brief — no rewires needed.

## 9. Open questions for mechanik review

- **Migration of `docs/design/` and `docs/research/`** to `specs/<bead>/`
  is recommended by the inventory but not filed as a sub-bead. File a
  one-shot cleanup bead under `tk-yw3zb`, or skip and leave the
  misplacement cosmetic? (No effect on doc-keeper functioning either way.)
- **`source_paths` annotation form** — `[doc-keeper.brief].source_paths`
  in pack.toml (proposed in §6) vs. inline `<!-- doc-keeper:owns ... -->`
  HTML-comment annotation in each doc. Pack.toml keeps the manifest
  central and reviewable; inline annotation keeps the binding next to
  the prose. Recommendation: pack.toml — single-source of truth, easy
  to grep, cheap to refactor.
- **Cycle period** — weekly is a guess. If drift-audit yield is consistently
  zero for several cycles, lengthen to monthly. If memory-audit yield is
  routinely too high to triage in one cycle, shorten or split.
- **First-run yield expectation** — §1d of the inventory predicts a
  high-yield first memory-audit pass against `docs/gas-city-reference.md`.
  The `audit_max_beads_per_run = 5` cap will throttle that first pass —
  may need raising to e.g. 20 for the initial backfill, then ratcheted
  back to 5.
