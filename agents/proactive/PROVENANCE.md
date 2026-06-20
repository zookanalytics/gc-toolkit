# Agent: proactive

**Status:** native
**Source:** N/A (gc-toolkit-original)
**Drift:** N/A

## Goals

The dedicated, small, mr-only pool that runs slung first reactions — Phase 4
of the Bead-Universe Operating Model (epic tk-q4xaj; bead tk-3d0uh; design Key
Components 5-6). A proactive worker takes one bead, gives it a cheap first
reaction (read the body, write a first-reaction card to the notes, flag it
onto the attention board), and drains. It makes the human arrive at *advanced*
work — a bead that already moved one step.

## Why we built this

"Proactive" in v1 is deliberately NOT a resident loop (the operator deferred
that). It is a `mol-first-reaction` (formulas/mol-first-reaction.toml) slung at
a bead — operator/board one-shot, or the `tools/gc-proactive.sh scan --sling`
process form over movable-forward beads. This pool is where those reactions
execute. It is a sibling of the impl polecat pool (same worktree/refinery
machinery) with three deliberate differences, all from the design's budget +
security commitments:

1. **Dedicated + small** (`max_active_sessions = 2`). Routing proactive work
   into the impl pool would starve real implementation (head-of-line blocking
   on the impl pool's 5 slots). The design's "max 2-3"; start at 2.

2. **City-wide shed clamp.** `work_query` emits `[]` — no demand, so the
   reconciler spawns nothing and an idle worker drains — when active city
   sessions are at/over `GC_PROACTIVE_CITY_CAP` (~8-16 band, default 12). This
   is the design's "reconciler clamp": the reconciler runs `work_query` to
   decide whether to spawn. Only THIS pool consults the clamp, so proactive is
   the first thing to shed under session pressure (design degraded mode
   "proactive sheds first under Dolt pressure"). The clamp is inline in
   `work_query` because that template surface has no `{{.ConfigDir}}` (only
   `{{.Rig}}`/`{{.RigRoot}}`/…), so a pack-relative tool path would not resolve
   in importing rigs; the same logic is mirrored, testably, in
   `tools/gc-proactive.sh demand`.

3. **mr-only for code.** A first reaction is notes-only by default. The
   security invariant — any code-producing proactive output takes the
   codex-gated `mr` path, never `direct` — is enforced three ways: the city
   default (`default_merge_strategy = "mr"`), this agent's `GC_DEFAULT_MERGE_
   STRATEGY = "mr"`, and `tools/gc-proactive.sh sling`, which hard-refuses a
   `--merge direct` override.

## Notes

Rig-scoped (each rig gets its own small proactive pool, like polecat-codex).
Triggered by `gc sling <rig>/gc-toolkit.proactive <bead> --on mol-first-reaction
--merge mr` (operator/board one-shot) or `tools/gc-proactive.sh scan --sling`
(process-scan). NOT a resident loop either way.

The first reaction NEVER closes the target work bead — it advances it (card +
`gc.attention` flag) and releases it open for the human to accept/redirect.
The `gc.proactive_reaction` marker stops the scan from re-reacting. The card
shape (Understanding · Found · Proposal · Decision needed) is the same one the
wellhead opens with and the board picker lands the human on.

Gate: `tools/proactive-first-reaction-fixture.sh` (hermetic) — the shed clamp
halts proactive at the cap; the mr-invariant refuses `direct`; the formula
writes the card and flags without closing; the slice tool fences reached
content. Design refs: design-doc.md Key Components 5-6, Phase 4.
