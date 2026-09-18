# Agent: proactive

**Status:** native
**Source:** N/A (gc-toolkit-original)
**Drift:** N/A

## Goals

The dedicated, small, mr-only pool that runs first reactions — Phase 4 of the
Bead-Universe Operating Model (specs/bead-universe/design-doc.md — Key
Components 5-6), in the reaction-bead model
(specs/tk-5n01ns/reaction-bead-first-reaction.md). A proactive worker claims one
reaction bead R, gives its subject a cheap first reaction (read the body, write a
first-reaction card to the notes, then dispose the subject: route it to the pool
that does that work, hold it on the bead it waits for, file a visit, or supersede
it), closes R, and drains. It is the city's first-level triage:
it makes the human arrive at *advanced* work — a bead that already moved one
step — and it keeps the beads it can schedule out of the human's queue
entirely.

That design is **v1**, superseded in part by specs/tk-h9pq5/design-doc.md
(v2, 2026-07-29): v2 replaced the binding and lifecycle and left Phase 4
standing, so v1 is still this pool's authority. Read its supersession banner
before citing the rest of it.

## Why we built this

"Proactive" is deliberately NOT a resident loop (the operator deferred that). A
reaction is its own leased bead R, filed per subject — by `tools/gc-proactive.sh
sling` (operator/board one-shot, via `gc-helm react`) or the `scan --sling`
process form over movable-forward beads — and routed here. This pool is where
those reactions execute. It is a sibling of the impl polecat pool (same
worktree/refinery machinery) with three deliberate differences, all from the
design's budget + security commitments:

**Update (2026-08-25):** the enable gate (`GC_PROACTIVE_ENABLED`) and the
city-wide shed clamp (item 2 below) were removed at operator direction in
the rewrite review — the pool is always-on and `max_active_sessions` is its
only throttle. What one `tools/gc-proactive.sh scan --sling` sweep may hand it
is bounded separately, by `GC_PROACTIVE_SLING_CAP`. Item 2 stands as the v1
design record.

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
Triggered by `tools/gc-proactive.sh sling <bead>` (operator/board one-shot, via
`gc-helm react`) or `scan --sling` (process-scan), both of which file a reaction
bead routed here. NOT a resident loop either way.

The first reaction never closes its subject except through the evidence-gated
`bead-rehome.sh` (the `superseded` exit); the other three exits advance the
subject and leave it open. `assets/scripts/first-reaction-dispose.sh` performs
all four, stamps `gc.reacted_by=<R>` on the subject as the completion marker, and
closes the reaction bead R — exactly-once is the substrate's, keyed on R's
identity, not a done-marker on the subject. The card shape (Understanding · Found
· Proposal · Decision needed · Disposition) is the same one a converse session
opens with and the board's pick-a-row visit lands the human on.

One bead is never triaged on its merits: a subject carrying `gc.origin=operator`
came from `gc-visit-open`, where a human typed a topic and is waiting to talk
about it, so the visit is the only disposition the script will perform on it.

Gate: `tools/proactive-first-reaction-fixture.sh` (hermetic) — `sling` files a
reaction bead tracking the subject and routes it here; the create-R-once dedup
skips a subject that already has an open reaction; scan/demand drop graph-structural
beads; one `scan --sling` sweep is capped; the slice tool fences reached content.
`assets/scripts/first-reaction-dispose.test.sh` covers the four exits themselves,
and `assets/scripts/bead-rehome.test.sh` the evidence-gated close. Design refs:
specs/tk-5n01ns/reaction-bead-first-reaction.md; design-doc.md Key Components 5-6,
Phase 4.
