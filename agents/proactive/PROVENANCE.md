# Agent: proactive

**Status:** native
**Source:** N/A (gc-toolkit-original)
**Drift:** N/A

## Goals

The dedicated, small, mr-only pool that runs first reactions — Phase 4 of the
Bead-Universe Operating Model (specs/bead-universe/design-doc.md — Key
Components 5-6). A first reaction is a run of `formulas/mol-first-reaction.toml`
slung on its subject (specs/tk-1tfzr71.105/design.md). A proactive worker claims
the run's one step, `react`, reads the subject as the run's input convoy's one
member, and runs the refusals check as its first act
(`tools/gc-proactive.sh sling <subject> --check --run <root>`). It then gives the
subject a cheap first reaction: it writes a first-reaction card to the notes,
headed with its run, and disposes the subject. It routes the subject to the pool
that does that work or holds it with Gas City's `hold:mayor` label for the
operator's placement sitting, recommends an action for the operator to trigger,
holds it on the bead it waits for, routes a confident no-op to a validating
closer, or puts it to the operator as a human gate. It closes its step and
drains. It is the city's first-level triage: it makes the human arrive at
*advanced* work — a bead that already moved one step — and it keeps the beads it
can schedule out of the human's queue entirely.

That design is **v1**, superseded in part by specs/tk-h9pq5/design-doc.md
(v2, 2026-07-29): v2 replaced the binding and lifecycle and left Phase 4
standing, so v1 is still this pool's authority for the reaction itself. Read its
supersession banner before citing the rest of it.

## Why we built this

"Proactive" is deliberately NOT a resident loop (the operator deferred that). A
reaction is a run slung per subject — by `tools/gc-proactive.sh sling`
(operator/board one-shot, via `gc-helm react`, and a patrol finding at filing)
or the scan order's `scan --sling` sweep over movable-forward beads — and the
pour routes its step here. This pool is where those reactions execute. It is a
sibling of the impl polecat pool (same worktree/refinery machinery) with three
deliberate differences, all from the design's budget + security commitments:

**Update (2026-08-25):** the enable gate (`GC_PROACTIVE_ENABLED`) and the
city-wide shed clamp (item 2 below) were removed at operator direction in
the rewrite review — the pool is always-on and `max_active_sessions` is its
only throttle. A slung run waits for a slot at no cost. Item 2 stands as the v1
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
   "proactive sheds first under Dolt pressure").

3. **mr-only for code.** A first reaction is notes-only by default. The
   security invariant is that code a reaction produces reaches main only
   through a PR. Code a reaction writes carries `merge_strategy=mr` itself, as
   this agent's prompt tells it to, so it opens a PR wherever it lands. A
   reaction's run carries no merge path of its own. Work a reaction routes is
   its subject's own, and it lands by the subject's target like any bead's.
   Aimed at main, it goes through a PR, because the refinery resolves a bead
   that would land `direct` on the default branch to `mr`. Aimed at an
   integration branch, it reaches main in that branch's PR.

## Notes

Rig-scoped (each rig gets its own small proactive pool, like polecat-codex).
Gas City's default work query offers the pool a routed, ready react step, and the
agent's `default_sling_formula` makes a bare sling or arm aimed at the pool pour
a first reaction. NOT a resident loop either way.

The first reaction NEVER closes its subject — every disposition advances it
and leaves it open, the `close` disposition included: it routes the subject to a
validating closer (mol-validate-close), which re-checks the no-work call and
closes the subject on its own confident check or escalates.
`gctk reaction dispose` performs each of them through native writes. No key on the subject records that a reaction landed: the run is the
record while it runs, `gc sling` refuses a second, and the state the exit wrote
and its headline keep the subject out of the scan afterwards. A worker that dies
before it closes its step leaves the step to the next, whose check passes only
while the exit has not dispatched the subject; that worker finds the card its run
wrote and re-runs the same exit. The card in the subject's notes records which
disposition was chosen and why, so a wrong call is visible rather than silent.
The card shape (Understanding · Found · Proposal · Decision needed · Disposition)
is the same one a converse session opens with when the operator picks the row
on the board.

Every bead is triaged on its merits, whatever its origin. A subject carrying
`gc.origin=operator` is weighed like any other: a clear, reversible action
routes or holds, a determinable action that warrants the operator's trigger is a
recommend, and only a genuine fork, an irreversible or destructive action, or a
policy call with no action to offer is a ruling. The guardrail lives in the
reacting agent's rubric (`agents/proactive/prompt.template.md`), not in an
origin gate on the script.

Gate: `tools/gc-proactive.test.sh` covers the sling, its refusals, the check and
the scan; the Go tests of `services/gctk/reaction` cover the exits themselves. Design refs: specs/tk-1tfzr71.105/design.md; design-doc.md Key
Components 5-6, Phase 4.
