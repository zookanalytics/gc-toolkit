# Proactive report: `mol-first-reaction` + budget + mr-invariant (`tk-3d0uh`)

**Bead:** `tk-3d0uh` — *Proactive-via-slung-mol: mol-first-reaction + budget + mr-invariant*
(child of `tk-n19tp` *Bead-Universe Operating Model v1*; sibling impl epic `tk-q4xaj`)
**Branch:** `polecat/tk-3d0uh` → `integration/bead-universe-v1`
**Phase:** 4 — Proactive-via-slung-mol (the final layer). Gated by Phase 3 attention `tk-qkags` (PR #100).
**Design refs:** design-doc.md Key Components 5-6, Phase 4.

---

## TL;DR — what shipped

1. **`formulas/mol-first-reaction.toml`** — the cheap first-reaction formula,
   modeled on `mol-review-leg` (load → react → persist). Three steps:
   `load-bead` (read the body + the Phase-2 universe slice), `first-reaction`
   (do the cheap reaction, write the fixed **card** — *Understanding · Found
   (freshness-stamped) · Proposal · Decision needed* — to the bead notes), and
   `advance-and-drain` (**flag** the bead onto the board, **release it OPEN**,
   drain). Where a review leg *closes* its bead, a first reaction **advances**
   a real work bead and hands it back to the human — **it never closes the
   target.**
2. **`agents/proactive/`** — the dedicated, small, mr-only pool that runs slung
   reactions: `max_active_sessions = 2` (never starves the impl pool's 5),
   `scope = "rig"`, a `work_query` that carries the city-cap shed clamp, and
   `GC_DEFAULT_MERGE_STRATEGY = "mr"`. Native agent (auto-discovered) +
   dedicated prompt + PROVENANCE.
3. **`tools/gc-proactive.sh`** — the budget-and-trigger engine: `sling` (mr-only
   sling at a bead; **refuses `--merge direct`**), `scan` (the process-scan over
   movable-forward / opt-in beads), `demand` (the pool work_query, mirrored and
   testable), `cap` (the city-cap state).
4. **Provenance tagging in `tools/gc-bd-universe.sh`** — every **fetched** tier
   (PR text, CI logs, comments, neighbor bodies) is now tagged as **untrusted
   DATA** (a visible fence on human output, a `_provenance` field on JSON). The
   **fed slice stays unfenced** — it is the trusted seed, not reached content.
5. **`tools/proactive-first-reaction-fixture.sh`** — the automatable Phase 4
   gate. **45/45 green**, hermetic (writes nothing to Dolt).

---

## The two triggers (operator refinement on `tk-3d0uh`)

The bead's note asked the trigger to accommodate **both** a per-bead opt-in
flag **and** a process-scan form. Both are served:

- **Per-bead / board-initiated** — `gc-proactive.sh sling <bead>` (or
  `gc sling <rig>/gc-toolkit.proactive <bead> --on mol-first-reaction
  --merge mr`). Covers the operator/board one-shot and `gc.proactive=1`.
- **Process-scan** — `gc-proactive.sh scan --sling`: the same "how do I move
  this forward?" loop the polecat demand-scan runs, but it **advances** rather
  than implements — open, ready, unassigned, non-epic beads not already reacted
  (`gc.proactive_reaction`) or hand-raised (`gc.attention`). NOT a resident
  loop: a process you run (operator / patrol / cron), bounded by the cap.

---

## The budget — two clamps, because proactive spends sessions

- **Pool cap** (`max_active_sessions = 2`). A *dedicated* small pool so
  proactive can never starve impl work (head-of-line blocking on the impl
  pool's 5 slots). The design's "max 2-3".
- **City-wide session cap** (the design's "reconciler clamp"). The pool's
  `work_query` **sheds** — emits `[]`, so the reconciler spawns nothing and an
  idle worker drains — when active city sessions are at/over
  `GC_PROACTIVE_CITY_CAP` (~8-16 band, default 12). Only this pool consults the
  clamp, so **proactive is the first thing to shed** under session pressure
  (design degraded mode "proactive sheds first").

### Why the clamp is INLINE in `work_query` (not a tool call)

`work_query` is expanded through `ExpandCommandTemplate`, whose surface is
`{Agent, AgentBase, Rig, RigRoot, CityRoot, CityName, WorktreesRoot}` —
**no `{{.ConfigDir}}`** (that is a `pre_start`-only var). For an *importing*
rig the pack's `tools/` live in the pack source, not under `{{.RigRoot}}`, so a
pack-relative tool path would not resolve. The clamp therefore lives inline in
`work_query` (it shells out only to `gc`/`bd`, both on PATH) with the pool
suffix `gc-toolkit.proactive` literal and only `{{.Rig}}` templated. The same
logic is mirrored, testably, in `gc-proactive.sh demand`, which the gate drives
hermetically — keep the two in sync.

`work_query` runs as `sh -c "<string>"` (cmd_hook.go), so it is a script body;
shed = `printf '[]'; exit 0`, which `workQueryHasReadyWork` reads as no demand.

---

## The security invariant — mr-only for code, never direct

A first reaction is **notes-only by default** (it writes a card; it does not
write code). IF a reaction produces code, that output takes the codex-gated
`mr` path, **never `direct`** — enforced **three ways**: the city default
(`default_merge_strategy = "mr"`), this pool's `GC_DEFAULT_MERGE_STRATEGY = "mr"`,
and `gc-proactive.sh sling`, which **hard-refuses** a `--merge direct` override
(GC_PROACTIVE_MERGE accepts `mr`|`local`; `direct` exits non-zero). The formula
spells out the code path: stamp `merge_strategy=mr`, hand to the refinery like
a polecat, never push to main.

---

## The provenance discipline — reached content is untrusted

The fed core is the bead's own body (the trusted seed); the fetchable tier is
content reached over gc/gh (PR text, CI logs, comments, neighbor bodies) —
potentially attacker-influenced, and **not an instruction channel**. Every
`fetch` is now tagged: human output wrapped in an `⟦ UNTRUSTED DATA … ⟧` fence,
JSON carrying a `_provenance` field. The fed slice is left unfenced. The
discipline is additive — the Phase 2 reachability fixture stays **20/20**
(it parses `.description`/`.number`/`.state` through the new `_provenance`
field, and substring-matches survive the fence).

---

## "Surfaces as advanced"

`advance-and-drain` flags the bead via `gc-attention.sh flag <bead> --reason
"advanced: first reaction ready — accept or redirect"` (sets `gc.attention=1`),
so it floats into the board's FLAGGED band carrying the **advanced** reason, and
stamps `gc.proactive_reaction=1` as the durable advanced marker. The operator
picks the row → lands on the first-reaction card → accepts (one move) or
redirects (one sentence). An explicit board *advanced* glyph (design Interface)
is a Phase-3-board refinement the `gc.proactive_reaction` marker enables; v1
surfaces via the flag + reason.

---

## The gate (`tools/proactive-first-reaction-fixture.sh`) — 45/45

Maps to the design's Phase 4 acceptance, hermetically:

- **the cap halts proactive at the limit** — `demand` flows routed work below
  the cap, sheds `[]` at/over it; the `cap` verb mirrors with an exit code.
- **mr-invariant** — `sling` refuses `--merge direct`, bakes in
  `--on mol-first-reaction --merge mr`, allows `local`, routes to the pool.
- **the formula contract** — the three steps, the four-part card, flags onto
  the board, forbids `gc bd close` on the target, releases it `--status=open`,
  pins code output to `merge_strategy=mr`, tags reached content.
- **the pool budget** — small dedicated pool (max 2), the shed clamp, mr
  default, rig scope.
- **the provenance discipline** — fetch fences as untrusted; the fed slice does
  not.

The human accept/redirect leg is the same operator-judged capstone Phase 3
already gates (board → pick → land → answer); this fixture locks the
deterministic Phase-4 machinery beneath it.

---

## Reused unchanged (per design)

`gc sling` (the `--on` / `--merge` path), `gc bd create/update`, the refinery,
`gc session list`, `gc-attention.sh flag` (Phase 3), `gc-bd-universe.sh slice`
(Phase 2). Phase 4 is assembly + one formula + one small pool + two clamps +
a provenance fence — no new lifecycle.
