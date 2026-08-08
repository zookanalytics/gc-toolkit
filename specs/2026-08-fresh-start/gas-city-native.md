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
| Conversation lifecycle (identity, turns, record) | tk-h9pq5 design: subject bead id = continuation group, hold-not-close converse role, turns as beads (unbuilt) | Continuation groups ship in core and carry the continuity; **extmsg does not track in-city conversations** — it is last-mile transport for external channels (bindings + transcripts live channel-side, nothing touches beads) | **Build ours on continuation groups** (still pure core assembly); extmsg is reach-from-anywhere transport for the same conversations, later, plus the meet-at-the-subject-bead boundary for genuinely external messages |
| Brief → tree of work | `mol-nx-plan` spec (design-only): plan block, diff-against-live, ratification turn | The `gascity` pack build factory: requirements → plan → adversarial review → decompose → beads filed, autonomous per-stage pooled sessions. **Trialed 2026-08-08 (tk-c31ou): tree quality good, review stage caught a would-be destructive bead — but no approval mechanism exists at all** (no graph edge can wait on a human; the review's `changes_required` verdict is structurally advisory), and its plan lives in files, not the record | **ADAPT** ([trial reactions](build-factory-trial-reactions.md)): keep the stages, the pooled sessions, and the adversarial review; graft `mol-nx-plan`'s two core ideas onto the decompose boundary — the **ratification turn** (a real blocking edge) and the **rev-pinned plan in the brief bead's notes** (so re-planning diffs instead of re-files). mol-nx-plan is un-shelved to exactly that extent |
| Worker/role contract | Hand-authored roles planned; gastown polecat imported+patched | `gc-role-worker` shared fragment, 12 roles, `gc gc claim` discovery, close+outcome discipline, empty-group session boundary | **Adopt** the gascity roles pack; express any variant as a delta on the fragment |
| Human approval / gating | Head-pinned check-set, merge-skill single writer, pre-open gate, signoff rounds (shipped, battle-tested) | v2 check loops re-run work until a script passes; **no native human-approval construct** ("embedded in agent prompts or external review roles"); `gc converge` gates are legacy | **Keep ours** — this is the pack's sharpest earned value; recompose it as gastown-refinery patches, unchanged in substance |
| Landing work | Refinery patched from gastown + bespoke close-on-land reconcile | Convoys grew landing machinery: merge strategies (`direct\|mr\|local`), `gc convoy land`, `gc convoy stranded`; merge-queue behavior still explicitly pack territory | **Ride** convoy landing; keep the check-set layer on top |
| Patrols / engine health | deacon/witness/refinery patrols imported+patched; quota nudges; cycle-recycle | Core absorbed housekeeping orders (`beads-health` etc.); gastown patrols remain the default coding-workflow answer, actively maintained upstream (orphan races, witness-death detection — all fixed upstream in the last 8 weeks) | **Ride** gastown's, drop local patches upstream has since fixed; keep only what upstream still lacks (quota-park nudge) |
| Attention: what needs me now | Helm board (5 anchor kinds, severity ranking, flag/pick), Go sidecar, Canvas plan | **Nothing.** Dashboard is state-only; "the documentation contains no mechanism for agents sending mail or notifications to human operators"; escalation explicitly punted to packs | **Ours.** The genuinely native ground |
| Decisions have a home | Bead as locus; turn outcomes written to subject; work-bead state machine | Beads are durable and survive sessions ("sessions are disposable — the work they did is not"), but nothing makes a *conversation* land its outcome anywhere | **Ours**, as doctrine (fragments), not machinery |
| Session search / memory | — | `cass` pack (coding-agent session search, skill overlay) | **Adopt**, free |
| Event intake (GitHub) | Refinery patrol polls PR state; bespoke reconcile scripts | `github` pack: webhook `proxy_process` services (signature-checked, durably persisted), a rules file firing orders on events, addressed comments becoming **source beads** keyed by comment id, plus a 7-day `gh` reconciliation scan; `pr-review` pack: `mol-adopt-pr` (intake → rebase-check → multi-provider review → human gate → finalize) | **Ride** intake; the missing hop is ours — upstream keys *new* source beads by comment identity and has no wiring from an event to the **existing bead owning that PR**, which is exactly the accountability seam (feedback lands on the work's one owner) |

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
  1. **The attention surface** — the board's semantics: anchor kinds,
     severity ranking, a bead raising its own hand, and the visual
     consistency that makes a glance reinstate context (each anchor with
     a durable place, the Canvas direction). Strictly **pull**: the
     operator glances when they choose; nothing pings them. Ranking,
     curation, and visual consistency are the pack's identity — upstream
     has nothing here, and this is its clearest reason to exist.
  2. **The record discipline** — doctrine fragments: a conversation that
     reaches a decision writes it to the subject bead; turns are filed as
     beads so the spine is board-legible. Meeting extmsg *at the subject
     bead*, as already recorded in
     [gascity-conversations.md](../../docs/gascity-conversations.md).
  3. **The merge check-set** — the head-pinned gate machinery and its
     doctor checks, recomposed as refinery configuration. Kept as
     *mechanism*, with membership explicitly **shrinking by design**: a
     check is scaffolding that automation retires as it earns trust, and
     a human approval is only "a check nothing non-human can yet
     satisfy" — a temporary member, never the point. The codex signoff
     specifically is compensatory (born of under-using molecules to
     enforce steps, per the operator), so the direction of travel is
     upstream's own: verification as check loops *inside* the work's
     formula, with the gate set thinning toward mode-1
     automated-to-resolution.
  4. **Banked lessons** — the doctor checks and trap docs. These survive
     any composition; they are the pack's memory.
- **Retired or shelved:** bead-host residue (already superseded),
  converge-style gating (upstream calls it legacy), most local patrol
  patches (upstream fixed the underlying bugs). The converse role and
  turn machinery are **not** on this list: nothing upstream replaces
  them; they are the focus-1 build. And mol-nx-plan moved off this list
  after the trial: its ratification-turn + record-resident-plan core is
  precisely what the factory lacks ([trial verdict](build-factory-trial-reactions.md)).

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
2. **Pull, never interrupt — pressured, and the pressure was rejected.**
   Upstream's channel plane is push-shaped, and a draft of this note
   recommended letting the board's ranking push. **OPERATOR POSITION
   (2026-08-08, their words):** "I am still not a huge fan of the
   proactive notify operator, it's really against the let things
   surface of the foundation.md. Ranking, curated, and visual
   consistency, that's what I would say is more gc-toolkit than
   anything." This note follows that position: the trigger that brings
   a juggled item back is the glanceable, visually-stable board, not a
   ping. The extmsg plane stays valuable inverted, as a **pull
   surface** — a registered LLM-client the operator opens *toward* the
   city — never as a delivery mechanism aimed at them.

What does *not* move: decisions still land on beads; the refinery
remains the single writer of merged truth. And one stance softens per
an **OPERATOR PREFERENCE (2026-08-08):** "I'd like to get away from
human approval eventually … don't take checks too far as a hard
requirement" — checks are scaffolding on the way to automation, kept
composable so members retire as automation earns trust, not permanent
process.

## Where the 90% lands, by focus area

- **Conversation lifecycle: the primitive is upstream, the model is
  ours.** Continuation groups (core) carry continuity; everything that
  makes it a *conversation about work* — identity = subject bead, turns
  as beads, outcomes on the record, cold reconstitution — is the
  tk-h9pq5 build, unreplaced by anything upstream. extmsg contributes
  transport only: reach the same bead-anchored conversation from any
  registered client, and anchor genuinely external messages at the
  subject bead.
- **Chaining / mol: ~80% upstream.** Build factory, 35 formulas, v2 check
  loops, convoy landing. Ours: the check-set gate layer; possibly a
  desired-state reconcile later.
- **Attention / context-shifting: ~20% upstream.** The channel exists;
  the judgment of what deserves the operator's glance — ranking,
  anchors, branded surfaces, visual consistency — is entirely ours, and
  strictly pull. This is where the pack's identity concentrates.

## The gate pattern — a proposal (OPEN)

**Status: OPEN — nothing here is ratified.** The operator asked a
question (2026-08-08): *"Maybe what I'm looking for is as much
automation as possible with clear points where we use blocking gate
beads when I'm needed… do I make that happen by writing new mols, new
agents, or a completely new base pack?"* What follows is the
**assistant's recommendation** in answer, grounded in the three
interaction tiers the runtime actually has (blocking edges / pending
interactions / mail — blocking is the graph's job, asking is the
session's job, telling is mail's job). It awaits the operator's
reaction; a previous revision of this section mislabeled it "operator
direction" and "settled doctrine," which it never was.

- **Gates are authored in mols, because a gate is graph data.** A
  blocking gate = a bead + a `blocks` edge, both filed by a formula
  step. The authoring rule: *the step that needs the check files the
  check.* Work that needs no judgment files no gate; gate membership
  shrinks as automation earns trust (operator preference on checks,
  above).
- **One agent makes gates live: the converse role.** A bare
  human-routed bead is durably *stuck* (no claim contract drives it);
  a gate filed as a **turn** is durably *live* — demand spawns the
  role, it preps and holds with the choice framed, records the answer
  on the subject, closes the turn, and the cleared edge resumes the
  pipeline. Tier-2 pending interactions are the wrong tool for
  pipeline gates: they die with their session, and a multi-session
  pipeline (build-basic's shape) has no session alive long enough to
  hold the question.
- **No new base pack.** The pattern is additive — metadata, edges, one
  role, formula steps. It does not depend on what executes between
  gates, so the gastown-roster question stays a separate, gradual,
  argued-per-role track.
- **The merge boundary is the same pattern.** A PR held for human
  review is a gate bead blocking the land step — the check-set's human
  member expressed as a turn, one shape everywhere.

## Increment path (try before deciding)

Each step is one lived experiment, cheap to reverse, ordered by
information-per-cost; nothing later is committed until the operator has
reacted to what the step showed.

1. **Run one real brief through the upstream build factory** (import the
   `gascity` pack on one rig; no native code). Judge the tree it files
   against what mol-nx-plan would have produced. Focus 2, tested in an
   afternoon.
2. **Build the conversation spine** (tk-h9pq5 Phases 0–1): the converse
   role as a delta on `gc-role-worker`, the turn-filing convention,
   continuation-group continuity — lived on one real subject bead
   through a warm turn, a session death, and a cold reconstitution.
   Focus 1, the core build.
3. **(Optional, later) Spike extmsg as reach**: register a generic
   LLM-client and open the *same* bead-anchored conversation from off
   the machine — pure transport over the spine from step 2, no second
   conversation mechanism. Focus 3-adjacent, strictly pull.
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
