---
name: Design note — the Gas City-native composition
description: What gc-toolkit looks like if we just use Gas City as it is designed today — a domain-by-domain mapping of the pack's standing systems onto upstream's current answers (verified 2026-08-08 from live docs and pack sources), the thin opinion layer that genuinely remains, the two foundation beliefs this pressures, and a try-it-first increment path. Position paper for operator reaction, not a ratified plan.
---

# Design note: the Gas City-native composition

> **Filing note.** Authored on the fresh-start contribution branch outside the
> city; files under the topic slug `2026-08-fresh-start` per
> [file-structure.md](../../docs/file-structure.md); re-key to the tracking
> bead at intake.

The operator's push, taken at full strength: *what if gc-toolkit just used
Gas City as it is being designed today — not as it was months ago?* This
note answers by mapping every standing gc-toolkit system onto upstream's
current answer, keeping only what upstream genuinely does not provide. All
upstream claims verified 2026-08-08 (live docs at docs.gascity.com; pack
sources at gastownhall/gascity-packs @ main; companion fact ledger:
[gascity-conversations.md](../../docs/gascity-conversations.md)).

The headline: the push is right. Upstream now covers most of what the pack
built or planned to build, including two things that were "missing
ecosystem-wide" as recently as the 2026-08-06 research. The pack that
remains is small, opinionated, and mostly *configuration plus doctrine* —
which is what a pack is supposed to be ("any orchestration pack is pure
config" — upstream's own words).

## The mapping

| Domain | gc-toolkit today (or planned) | Gas City today | Verdict |
|---|---|---|---|
| Conversation continuity | tk-h9pq5 design: continuation groups + a hold-not-close converse role + turns as beads (unbuilt) | `extmsg`: conversations bind to a **configured agent**, survive restarts by cold-wake, move between agents via `gc extmsg handoff`; Slack/Discord/LLM-client packs carry the channel | **Ride** the binding + channel; keep only the subject-bead discipline (below) |
| Brief → tree of work | `mol-nx-plan` spec (design-only): plan block, diff-against-live, ratification turn | The `gascity` pack build factory: `requirements-planner` → `design-author` → `review-synthesizer` (approval, incl. interactive mode) → `task-decomposer` → `create-beads` files convoys/beads with dep edges from schema-validated `tasks.md`; methodology packs (bmad, superpowers, …) override the decomposition step | **Adopt**; shelve mol-nx-plan. Re-open only the desired-state-reconcile delta if lived re-planning demands it |
| Worker/role contract | Hand-authored roles planned; gastown polecat imported+patched | `gc-role-worker` shared fragment, 12 roles, `gc gc claim` discovery, close+outcome discipline, empty-group session boundary | **Adopt** the gascity roles pack; express any variant as a delta on the fragment |
| Human approval / gating | Head-pinned check-set, merge-skill single writer, pre-open gate, signoff rounds (shipped, battle-tested) | v2 check loops re-run work until a script passes; **no native human-approval construct** ("embedded in agent prompts or external review roles"); `gc converge` gates are legacy | **Keep ours** — this is the pack's sharpest earned value; recompose it as gastown-refinery patches, unchanged in substance |
| Landing work | Refinery patched from gastown + bespoke close-on-land reconcile | Convoys grew landing machinery: merge strategies (`direct\|mr\|local`), `gc convoy land`, `gc convoy stranded`; merge-queue behavior still explicitly pack territory | **Ride** convoy landing; keep the check-set layer on top |
| Patrols / engine health | deacon/witness/refinery patrols imported+patched; quota nudges; cycle-recycle | Core absorbed housekeeping orders (`beads-health` etc.); gastown patrols remain the default coding-workflow answer, actively maintained upstream (orphan races, witness-death detection — all fixed upstream in the last 8 weeks) | **Ride** gastown's, drop local patches upstream has since fixed; keep only what upstream still lacks (quota-park nudge) |
| Attention: what needs me now | Helm board (5 anchor kinds, severity ranking, flag/pick), Go sidecar, Canvas plan | **Nothing.** Dashboard is state-only; "the documentation contains no mechanism for agents sending mail or notifications to human operators"; escalation explicitly punted to packs | **Ours.** The genuinely native ground |
| Decisions have a home | Bead as locus; turn outcomes written to subject; work-bead state machine | Beads are durable and survive sessions ("sessions are disposable — the work they did is not"), but nothing makes a *conversation* land its outcome anywhere | **Ours**, as doctrine (fragments), not machinery |
| Session search / memory | — | `cass` pack (coding-agent session search, skill overlay) | **Adopt**, free |

Verified upstream movement in just the last three weeks: build-factory
methodology packs published, a pr-review adoption pack, oversight-rig
executive-status skill, witness-death detection, worktree-safe direct
merge. The ecosystem is compounding; every month of bespoke machinery is a
month of divergence from that.

## The composition

A city stood up today, upstream-native:

- **Imports:** core+bd (default) · `gascity` (roles + build factory) ·
  `gastown` (coding roster: polecats, refinery, patrols, mayor) ·
  `slack-full` or `slack-mini` (the human channel over extmsg) · `cass`.
- **gc-toolkit, the pack, shrinks to a thin opinion layer:**
  1. **The attention surface** — the board's semantics (anchor kinds,
     severity ranking, a bead raising its own hand) and an *escalation
     policy*: rows that cross a threshold reach the operator through the
     extmsg channel everyone else already uses. Upstream has punted
     exactly this; it is the pack's clearest reason to exist.
  2. **The record discipline** — doctrine fragments: a conversation that
     reaches a decision writes it to the subject bead; turns are filed as
     beads so the spine is board-legible. Meeting extmsg *at the subject
     bead*, as already recorded in
     [gascity-conversations.md](../../docs/gascity-conversations.md).
  3. **The merge check-set** — the head-pinned gate machinery and its
     doctor checks, recomposed as refinery configuration. Upstream v2 has
     no human-approval construct; this layer is where "agent-initiated
     code is gated by default" lives, and its scripts encode incidents
     upstream has not had yet.
  4. **Banked lessons** — the doctor checks and trap docs. These survive
     any composition; they are the pack's memory.
- **Retired or shelved:** bead-host residue (already superseded),
  mol-nx-plan (superseded by the build factory until lived experience
  says otherwise), the bespoke conversation-role machinery (superseded by
  extmsg agent bindings), converge-style gating (upstream calls it legacy),
  most local patrol patches (upstream fixed the underlying bugs).

## What this pressures, honestly

Two foundation-level positions do not survive this composition unchanged;
both are operator decisions, flagged per the consistency test's own rule
that sometimes the belief upstream of the architecture is what moves.

1. **The gastown boundary.** Foundation says gastown "is an example pack,
   not an upstream" and the pack "does not augment" it; the architecture
   marks de-gastowning as the direction. But today's gastown is
   upstream's *first-party default coding workflow pack* — pure config,
   actively maintained, with the last two months of hard bug-fixes
   (orphan races, witness death, worktree-safe merges) landing there for
   free. Maximal-upstream means embracing it as exactly what it now is:
   the default roster we configure. The de-gastowning direction was
   fighting the ecosystem this pack claims to ride. **Recommendation:
   reverse it; edit foundation's boundary to name Gas City *and its
   first-party packs* as the substrate.**
2. **Pull, never interrupt.** The foundation-derived stance has been that
   the surface never pushes. But the operator's own stated need is
   triggers that bring a juggled item back — and upstream's channel plane
   (extmsg → Slack) is push-shaped. The reconciliation is curation, not
   silence: *the board's ranking decides what earns a push*, so
   interruptions stay scarce and high-value (foundation's actual point),
   but they exist. **Recommendation: restate the belief as "attention is
   spent by the board's ranking, never by an agent directly."**

What does *not* move: the merge gate stays gated-by-default (upstream
offers no opinion here, and ours is earned); decisions still land on
beads; the refinery remains the single writer of merged truth.

## Where the 90% lands, by focus area

- **Conversation lifecycle: ~70% upstream.** Binding, continuity,
  cold-wake, handoff, channels — all upstream. Ours: the subject-bead
  identity of a conversation and the record discipline. Open frontier:
  thread-per-bead (extmsg `--kind thread` + `--parent-conversation-id`)
  as the literal realization of "engage at the level of a bead" — a
  spike, not machinery.
- **Chaining / mol: ~80% upstream.** Build factory, 35 formulas, v2 check
  loops, convoy landing. Ours: the check-set gate layer; possibly a
  desired-state reconcile later.
- **Attention / context-shifting: ~20% upstream.** The channel exists;
  the judgment of what needs the operator now — ranking, anchors,
  branded surfaces, escalation thresholds — is entirely ours. This is
  where the pack's identity concentrates.

## Increment path (try before deciding)

Each step is one lived experiment, cheap to reverse, ordered by
information-per-cost; nothing later is committed until the operator has
reacted to what the step showed.

1. **Run one real brief through the upstream build factory** (import the
   `gascity` pack on one rig; no native code). Judge the tree it files
   against what mol-nx-plan would have produced. Focus 2, tested in an
   afternoon.
2. **Bind one real conversation via extmsg** (slack-mini is the smallest
   viable channel): agent binding, cold-wake after a session death,
   one handoff. Judge whether the subject-bead discipline can live as
   doctrine on top. Focus 1.
3. **Give the board one push path**: a row crossing its threshold
   publishes to the same channel. Smallest native increment; focus 3.
4. **Only then** revisit the roster question (how much of the patched
   gastown import simply un-patches) and the foundation edits above,
   with three lived data points in hand.

## Sources

- Live docs sweep 2026-08-08 (docs.gascity.com via llms.txt; quotes in
  [gascity-conversations.md](../../docs/gascity-conversations.md)).
- Pack-source survey 2026-08-08: gastownhall/gascity-packs @ main —
  `gascity/` (roles, formulas, schemas, README), `gastown/` (agents,
  formulas, refinery prompt, commit log), `cass/`, `slack-full/`,
  `registry.toml`; gastownhall/gascity commit log (partial render,
  infrastructure-only in the visible slice).
- Prior source-verification 2026-08-06 (quarry branch, clone `3e629ad`)
  where the live docs do not cover a claim.
