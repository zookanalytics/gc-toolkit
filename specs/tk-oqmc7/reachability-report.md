# Reachability report: `gc bd universe --slice` + CI wiring (`tk-oqmc7`)

**Bead:** `tk-oqmc7` — *Reachability: gc bd universe --slice (fed/fetchable tiers) + CI wiring*
(child of `tk-q4xaj` *Bead-Universe Operating Model v1 — implementation*; convoy `tk-n19tp`)
**Branch:** `polecat/tk-oqmc7` → `integration/bead-universe-v1`
**Phase:** 2 — Reachability (the prompt/context). Gated by Phase 1 binding `tk-husu6` (PR #98).
**Design refs:** design-doc.md Key Component 3, Data Model, Phase 2.

---

## TL;DR — what shipped

1. **`tools/gc-bd-universe.sh`** — the design's `gc bd universe <id> --slice`
   projection: the **one shared contract** for a bead's universe that the
   launcher, the attention board, and slung mols all consume. Three verbs:
   `slice` (the fed core, human or `--json`), `fetch <tier>` (fetchable tiers
   on demand), `footprint` (token-cost gate). Read-only; writes nothing.
2. **The fed / fetchable / out tiers** (design Key Component 3) — the fed core
   trims `gc bd show --json`'s heavy default (it inlines every dependency's
   **full** description) down to a **title-only manifest** + 1-hop **counts** +
   the **notes tail**; full bodies, notes/comments, PR text, and CI live one
   `fetch` away; >1 hop / other rigs are **out** (hop into that neighbor).
3. **CI wiring** (`gh pr checks`) — a tri-state `fetch ci` with the **pre-work
   null-vs-error** distinction baked in (design Data Model).
4. **`tools/bead-universe-reachability-fixture.sh`** — the automatable Phase 2
   gate: a seeded subtree + answer-keyed questions, exact-match scored,
   asserting **100% recall AND fed-slice ≤ the token ceiling**. 19/19 green,
   hermetic (writes nothing to Dolt).

---

## Why a path-invoked tool, not a `gc bd` subcommand

`gc bd` is a pass-through to upstream **`bd`** (Go); it has no `universe`
subcommand and no plugin dispatch, and that source is not in this pack. So —
exactly as Phase 1's `gc bead-host` ships as `tools/gc-bead-host.sh` invoked by
path (`gc bead-host --help` resolves to gc's root help, not the script) — this
projection ships as a **path-invoked shell tool**. The bead's own wording
("**ideally** behind a `gc bd universe <id> --slice` projection") anticipates
this: what matters is the **shared contract**, not the literal command spelling.
If `gc bd` later grows native extension dispatch, the tool is the drop-in body.

---

## The three tiers (the contract)

| Tier | What | Source |
|---|---|---|
| **fed** (always in context) | `id/title/body/status/type/priority/assignee`, curated metadata (`branch`/`target`/`pr_url`), 1-hop **counts**, a title-only **manifest** of direct parent/children/deps, the **notes tail** | `gc bd show` (trimmed) + `gc bd children` |
| **fetchable** (named in fed, on demand) | full neighbor body, full notes, full comments, PR text+diff, **CI status**, parent's fields | `gc bd show <neighbor>` / `gc bd comments` / `gh pr view`/`diff`/`checks` |
| **out** (not reachable here) | anything >1 hop; other rigs (`bd` is rig-scoped) | — (hop into the neighbor's own universe) |

**The "one concrete build":** `gc bd show --json` inlines every dependency's
**full description** (the heavy default). The fed core projects each neighbor to
`id · title · status` only. Children come from `gc bd children` (already
title-only). The fixture proves a dep's full body is **trimmed out** of the fed
slice while its title remains (assertion Q12).

### Fed-core data sources (resolved)

- **bead itself + deps/parent**: `gc bd show <id> --json` → `.[0]`; `.dependencies[]`
  carries parent (matched against `.parent`), the convoy parent-child edge, and
  blocks/discovered-from edges — **all with heavy inline bodies → trimmed**.
- **children**: `gc bd children <id> --json` (lightweight `id/title/status/type`).
- **notes**: `.notes` (an append-only string) → tail of last
  `GC_BD_UNIVERSE_NOTES_TAIL_LINES` (default 12) lines; count = non-empty lines.
- **comments**: `.comment_count` for the fed count; full history via `fetch comments`.
- **PR/CI**: `metadata.pr_number`, else the trailing number of `metadata.pr_url`.

### The machine contract (`slice --json`)

`{ schema:"gc-bd-universe/slice@1", id, title, status, type, priority, assignee,
metadata:{branch,target,pr_url}, body, counts:{parent,children,deps,notes,comments},
manifest:{parent,children[],deps[{id,title,status,rel}]}, notes_tail, pr:{state,number,url,note}, fetchable[] }`

`fetchable[]` lists exactly what `fetch` accepts (`neighbor:<id>` for each 1-hop
neighbor, plus `notes`/`comments`/`pr`/`ci`/`parent`), so a consumer never has
to guess what is reachable — and `fetch neighbor` **refuses** an id not in that
list (the out-of-reach boundary; assertion Q15).

---

## CI wiring (`fetch ci`) — the tri-state, and null-vs-error

The design's "wire CI status (`gh pr checks` — the one missing fetch)" plus its
Data-Model requirement that the universe "distinguish *not yet* (null PR/CI,
expected) from *unreachable/error*, so a host doesn't chase an unborn PR":

| State | Meaning | When | Exit |
|---|---|---|---|
| `prework` | no PR referenced yet | no `pr_number`/`pr_url` on the bead | 0 |
| `no_checks` | PR exists, no checks reported | reachable PR, empty `statusCheckRollup` | 0 |
| `pass` / `fail` / `pending` | rolled up from check states | reachable PR with checks | 0 |
| `error` | PR referenced but unreachable | `gh` fails on a referenced PR | 3 |

`fetch ci` (human) prints `gh pr checks` text (the named tool); `fetch ci --json`
emits `{state}`, derived from `gh pr view --json statusCheckRollup` — chosen for
the state enum because `gh pr checks` conflates "failing" and "general error" in
its exit code, so reachability is **never** gated on it. `fetch pr` mirrors the
`prework`/`error` split. Verified live against PR #98 (`no_checks`) and against
the pre-work bead `tk-oqmc7` (`prework`).

---

## On-resume recompute (design Key Component 3, "On resume")

A bead-host suspends while the world moves. The design requires resume to
re-inject a **freshly recomputed** fed slice. This tool is **stateless** — every
`slice` call recomputes from live `bd`/`gh` — so "recompute on resume" is simply
"call `slice` again on wake." No cache to invalidate; the launcher (Phase 3)
calls `slice` at resume time.

---

## The token ceiling — proposed, and operator-tunable

`footprint <id>` estimates the fed slice's cost at **~4 bytes/token** (a
documented approximation; no tokenizer dependency) and gates it against
`GC_BD_UNIVERSE_TOKEN_CEILING`.

- **Proposed default: 2000 tokens** for the fed core (design's "≤ ~2k", derived
  from the measured ~190-token slice for a 6-child epic + headroom).
- **Measured here:** live `tk-oqmc7` fed slice = **486 tokens**; the seeded
  fixture epic = **217 tokens** — both far under 2k.
- **OPERATOR ACTION:** the design says the ceiling is operator-tunable and the
  **operator/scale owner sets the final number before the Phase 2 gate is treated
  as binding**. Set it by exporting `GC_BD_UNIVERSE_TOKEN_CEILING=<N>` before
  running the fixture. The default (2000) is a proposal, not the operator's word.

---

## The gate fixture (automatable, hermetic)

`tools/bead-universe-reachability-fixture.sh` realizes the Phase 2 gate:

- **Seeded subtree** — an epic with 3 children, a discovered-from dep, and notes,
  staged as **canned data sources** under a temp dir and fed through the tool's
  `GC_BD_UNIVERSE_FIXTURE` hook. Deterministic, fast, and **writes nothing to
  Dolt** (no seeded beads to leak; the only cleanup is a temp dir, via an EXIT
  trap). This keeps the gate safe to run anywhere and re-runnable.
- **Answer-keyed questions** — each answered **only** from `slice`/`fetch` output
  (never the raw JSON), **exact-match** scored (not an LLM judge):
  7 fed-tier · 4 fetchable-tier · 2 trimming · 2 null-vs-error · 1 boundary
  · 1 footprint · 2 live-smoke = **19 assertions**.
- **Result:** `19/19 — RECALL 100%, footprint within ceiling. GATE PASS.`
- **Live smoke** — best-effort `slice` against a real bead (`tk-oqmc7`) proves
  the real `gc`/`gh` path; it **SKIPs** (does not fail) if that bead is absent,
  so the binding pass/fail rests on the hermetic gate.

Run it: `tools/bead-universe-reachability-fixture.sh`
(override `GC_BD_UNIVERSE_TOKEN_CEILING=<N>` for the operator's ceiling.)

---

## What this unblocks / hands off

- **Phase 3 (attention surface, `tk-qkags`)** consumes `slice` on pick-a-row /
  resume (the launcher calls `slice`; the board can render `slice --json`).
- **Phase 4 (proactive mol, `tk-3d0uh`)** uses the same contract to prime a
  slung first-reaction, and the fetchable tiers to reach what it needs.
- **Operator** sets the final token ceiling (above) before treating the gate as
  binding; the proposed 2000 holds with large headroom on every measured slice.

## Scope notes / honest limits

- Token cost is a **byte/4 estimate**, not a real tokenizer count — intentionally
  dependency-free; the operator-tunable ceiling absorbs the slop.
- Under the `GC_BD_UNIVERSE_FIXTURE` test hook, `fetch comments` reports the
  count only (full history is a live `gc bd comments` call) — the hook stages
  data sources, and full comment history is exercised on the live path.
- Intra-rig only (design Data Model): cross-rig neighbors are out of reach by
  construction; `bd` is rig-scoped.
