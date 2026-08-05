# Spec — the ground-up recomposition of gc-toolkit

Phase 2 of the rethink ([outcome.md](outcome.md)). This document maps every
outcome (O1–O9) to concrete structure: the new pack's name and staging
location, its roster, formulas, conversation wiring, sub-pack boundaries, the
O5 doctrine census, each outcome's documentary proxy, and the cutover stages.
Phase 3 implements exactly what is specified here; deviations found necessary
during implementation are recorded back into this document.

Authorities this spec defers to rather than restates:
[work-bead-state-machine.md](../../docs/work-bead-state-machine.md) (the
lifecycle), [gascity-routing-model.md](../../docs/gascity-routing-model.md)
(the field contract), [gascity-agents.md](../../docs/gascity-agents.md) (agent
variants), [gascity-packs.md](../../docs/gascity-packs.md) (authoring traps),
and [`tk-h9pq5`](../tk-h9pq5/design-doc.md) (the conversation design, adopted
here in full).

## 1. The pack: name, location, relationship to the repo root

**The new pack is `gc-next`, staged at `packs/gc-next/`.** *(O1; non-goal:
no big-bang cutover.)*

- **Why there:** `packs/<name>/` is the repo's existing opt-in sub-pack
  convention (`packs/gascity-keeper/`), and nothing under `packs/` is loaded
  by the current pack's importers — the root `pack.toml` does not import
  sub-packs; rigs opt in explicitly. Merging this branch therefore changes
  nothing for any rig running the current composition.
- **Why a temporary name:** a pack's name qualifies its agents
  (`<binding>.<template>`), so `gc-next` keeps every staged identity disjoint
  from live ones even if a rig imports both during shakeout. Taking over the
  `gc-toolkit` name — and the repo root — is the final cutover stage (§9),
  not a property of the staged tree.
- **Non-collision (outcome non-goal, packs.md §7):** every artifact basename
  in `gc-next` — agents, formulas, fragments, scripts, doctor checks — is
  distinct from every basename in the current pack *and* in the imported
  gastown layer. The implementation ships a collision audit script and the
  review checks it. Formula names use a `mol-nx-*` prefix during staging for
  this reason (renamed at cutover when the old set retires).

Layout inside `packs/gc-next/` follows the pack spec's well-known directories:

```
packs/gc-next/
├── pack.toml              # schema=2; no [imports] of any example pack
├── agents/<name>/         # agent.toml + prompt.template.md, colocated
├── formulas/mol-nx-*.toml
├── template-fragments/
├── assets/scripts/        # private files, per pack-spec (no top-level scripts/)
├── doctor/
├── orders/
├── skills/
└── README.md              # brand, scope, install pointer
```

## 2. What the gastown import supplies today, and where each piece goes

*(O1's enumeration. Sources: root `pack.toml`, `docs/install.md`, the agents
inventory.)* The wholesale import currently supplies six patched roster agents
plus three non-roster capabilities:

| Supplied by gastown today | Disposition in gc-next |
|---|---|
| **boot** (city bootstrap triage) | **Native re-authorship, recomposed** — boot's startup-discovery duties fold into the patrol domain (§4, `sentry`); no dedicated boot agent. Rationale: boot's gc-toolkit-side value was the layered-startup-discovery doctrine, which is patrol doctrine, not a role of its own. |
| **deacon** (town health patrol) | **Native re-composition** — health patrol cycles run by `sentry` claimants of `mol-nx-patrol-health` (§4, §5). |
| **witness** (per-rig work-health patrol) | Same disposition as deacon; the orphan-recovery and re-offer doctrines move into `mol-nx-patrol-health` steps. |
| **refinery** (landing/merge) | **Native `lander`** (§4) running `mol-nx-patrol-land`; the close-on-land and check-set machinery is already gc-toolkit doctrine (the current 105K refinery patrol formula diverges heavily from stock), so this is the least-gastown-dependent role to re-author. |
| **mayor** (coordination/dispatch) | **Not carried as a resident.** Coordination in gc-next is formulas + conversation turns on subject beads (tk-h9pq5 open question 2 resolved in the distributed direction for the new pack); an operator who wants a standing strategy conversation spawns a `thread` (§4). The mayor-specific doctrines (convoy integration branch, operator-next-step) are carried in fragments injected into the roles that now hold those duties (`lander`, `thread`, conversation role). |
| **polecat** (impl pool worker) | **Native `wright`** pool (§4). |
| **dog pool** (warrant executor; gastown owns it explicitly — see `agents/DOG-NOTE.md`) | **Dropped as a role; the work re-routes.** A warrant that produces committed output is ordinary work routed to `wright` (it rides Delivery like everything else); a runtime-state-only repair (kill a stray process, requeue a bead) is executed by the `sentry` cycle that found it, bounded by a per-cycle cap, or filed routed to `sentry` for the next cycle. Rationale: with patrols on disposable pool sessions (§4), the patrol/executor split that motivated dog — keeping fix work out of resident patrol sessions — no longer buys isolation the pool boundary doesn't already provide. |
| **Base tmux theming** (`tmux-theme.sh` runs first; gc-toolkit overrides status-right) | **Native, single-layer.** gc-next ships one status-line script that owns the whole bar (theme + composable title/indicator slots). The current two-layer run-gastown-then-rewrite dance exists only because the base theme arrives via the import; with no import there is nothing to override. The gc-toolkit-side slots and bindings are carried (census §7). |
| **`gc.attention` / Helm surface** (gc-toolkit's own, but wired to gastown-shaped roster) | Carried and rewired per tk-h9pq5 (§6). |

Nothing else crosses the import boundary: skills, orders, doctor checks,
services, and tools are already native (inventory, Phase 1).

## 3. Primitive discipline: the rules every gc-next capability obeys

These are the consistency-test obligations (architecture.md) stated once, so
§4–§6 can cite them instead of repeating them:

1. **Routing is the only spawn.** Every gc-next session exists because routed
   work summoned it (`gc.routed_to` demand → reconciler spawn) or because an
   operator explicitly spawned a thread. No agent self-hosts work discovery
   beyond its claim contract.
2. **The record is durable; sessions are disposable.** Any turn/cycle boundary
   is a safe place for a session to die. Continuity lives in beads, molecules
   poured for the next cycle, and repo docs — never in a session staying warm.
3. **Field contract per the four lanes** (gascity-routing-model.md): pool
   dispatch stamps `gc.routed_to` only; named-session delivery stamps
   `assignee`; park-then-handoff uses `--reassign`; formula attach follows the
   Lane 4 contract.
4. **v1/v2 by shape, not fashion** (gascity-packs.md §1): self-poured patrol
   loops are v1; orchestrated graphs with independently-routable steps are v2;
   v2 step bodies close `$GC_BEAD_ID` before drain-ack; check loops route to
   pools; nothing pairs `phase = "vapor"` with the v2 compiler.
5. **Landing is gated.** Code an agent produces on its own initiative carries
   the mr-mode path and a non-empty declared `check_set`; the state machine
   doc owns the lifecycle; the merge skill stays the single writer of
   merged-truth.
6. **Brand at birth** (O8): each agent.toml, formula, and bead-type constant
   carries a one-sentence brand comment at its definition site.

## 4. The roster

*(O1, O7. Documentary proxy for O7: this table plus each agent.toml's header
argument.)*

**Residency decision (the O7 question, settled):** patrol continuity in
gc-next lives in **self-pouring molecule chains on routed, disposable pool
sessions** — a cycle claims its patrol bead, works the molecule, files/pours
the next cycle routed back to the pool, and drains. No resident patrol
singletons. This revises the "resident patrol loops" reading of architecture's
Engine-health bullet, deliberately and on the record: the three-hats clause
("nothing continuous can live in a role that exists only between claim and
drain") is satisfied because *the continuity is not in the role* — it is in
the chain of poured work, which survives any individual session. What the
resident model bought — a warm context across cycles — is exactly what the
cycle-recycle overlay exists to throw away at 200K tokens anyway; gc-next
sheds it every cycle by construction. Consequences: the cycle-recycle *hook*
is not needed for patrol roles in gc-next (each cycle starts fresh), and its
doctrine survives as the recycle guard on the one long-holding role
(conversation, below) plus the census entry (§7). **The default roster is
therefore zero `[[named_session]]` entries in the core pack.** The keeper (in
the carried `gascity-keeper` sub-pack, §8) remains the one `on_demand`
resident, argued there.

| Agent | Brand (one sentence, O8) | Variant & shape |
|---|---|---|
| **`wright`** | Builds one bead's output on its own branch and hands off to gating; it never lands, never closes a unit that merges. | Pool worker; `scope=rig`, `wake_mode=fresh`, `max_active_sessions=4`. Claim via standard hook tiers. Prompt authored fresh; injected fragments: work-records, convoy-target, non-impl-done, watch-dispatched (§7). |
| **`lander`** | The single writer of merged-truth: drives every gating anchor through its check-set and performs the merge, and is the only thing that targets the protected boundary. | **Demand-scaled singleton**: pool-shaped config capped `max_active_sessions=1`, scale-from-zero on routed demand — single-writer by cap, not by residency. Runs `mol-nx-patrol-land` cycles (v2, self-pour). |
| **`sentry`** | Runs one health-patrol cycle — orphans, queues, sessions, stores — files what it finds, pours the next cycle, and drains. | Pool worker; `scope=rig`, `max_active_sessions=2`, `wake_mode=fresh`. Runs `mol-nx-patrol-health` (v1, self-pour) and executes bounded runtime-state repairs (§2 dog disposition). |
| **`converse`** | Holds a subject bead's conversation for the operator: rebuilds the slice, preps, holds, writes the outcome to the subject, closes only the turn. | Pool worker per tk-h9pq5 §Key-Components-3: `run-operator` shape with the hold-not-close clause; `max_active_sessions=2`; claims turns via `gc.routed_to`, continuity via `gc.continuation_group` vacuum. Carries the recycle guard: at the context threshold it writes the turn outcome to the subject and lets the session die (turn boundaries are the release valve). |
| **`outrider`** | Meets a newly filed bead before the operator does: reads its universe, writes the first-reaction card, flags it onto the board, and drains. | Small pool (`max_active_sessions=2`) executing `mol-nx-first-reaction`; carries the default-disabled gate + city-wide shed clamp doctrine in both `work_query` and `scale_check` (census §7). Kept separate from `converse` (tk-h9pq5 open question 4): an outrider run is autonomous and must never hold a slot waiting for an operator. |
| **`thread`** | An operator-spawned parallel line of a named role that acts and dispatches but owns no inbox, no patrol cadence, and no system-of-record identity. | Generic thread template (`work_query` stub + failing `sling_query`, `wake_mode=resume`), parameterized by `[env] RoleName` — the existing thread-role fragment pattern, carried. Replaces mayor-thread/mechanik-thread with one template. |

Codex/Gemini provider-diversity pools (`polecat-codex`, `_polecat-gemini`) are
**not re-authored in staging** — they are wright-shaped variants whose value
is provider diversity in the *operational* city; a `wright-codex` variant is a
named cutover-stage addition once wright itself has shaken out. Recorded so
the capability is a decision, not a loss (census §7).

## 5. The formulas

*(O3, O4. Documentary proxy for O4: the interlock line in each formula
header.)* Every formula ships with a header stating: contract (v1/v2) and why,
what it pours or routes, and — the O4 bar — either the step that signs off
each check it gates, or the recorded note naming which step will when the
interlock lands.

| Formula | Contract & why | Interlock position |
|---|---|---|
| **`mol-nx-work`** | **v2** — the implementation workflow: independently-routable step beads (build → hand-off), routed to `wright`; step bodies close `$GC_BEAD_ID` with `gc.outcome` per the graph-worker idiom. | Build step ends by handing to gating with `check_set` declared; the signoff-gate stamp (`check.<name>=green@<sha>`) is written by the review step it dispatches — step-signs-off-check implemented. |
| **`mol-nx-patrol-land`** | **v2** — lander's cycle: reconcile gating anchors, dispatch pre-open reviews, run the merge skill, graduate convoys, pour next cycle. Carries the close-on-land, per-gate-marker, approval-member, and anchor-repair doctrines (census §7). | The merge step *is* a check-discharger by construction; unrun-check-runs-itself is the recorded-note case: the cycle re-dispatches a stale gate (the stale-gate arm) — noted as the interlock's current realization, full self-running checks deferred. |
| **`mol-nx-patrol-health`** | **v1** — a self-poured patrol is data one agent works through; v2's engine buys it nothing (packs.md §1). Pour-before-burn; never exits from an intermediate step. Merges the deacon-patrol and witness-patrol doctrines into one town+rig health cycle with per-step caps. | Recorded note: health checks it performs (orphan scan, queue starvation) become self-running checks when the interlock lands; today the cycle files what it finds. |
| **`mol-nx-first-reaction`** | **v1** — one-shot; advance-and-drain. Flag, don't close; mr-only for code; fenced-untrusted-data rule carried. | N/A (files no gated work itself); note recorded in header. |
| **`mol-nx-turn`** | **v1, one step** — the operator-driven trigger: create a turn bead in the subject's group routed to `converse`. The "I want to talk about this" one-step formula named by architecture. | N/A; note in header. |
| **`mol-nx-doc-drift`** / **`mol-nx-doc-memory`** | **v2** — carried from the doc-keeper pair nearly as-is (prime → audit → drain, routed to `wright`), renamed for the non-collision rule. | Recorded note (as today). |

All v2 formulas declare `[requires] formula_compiler = ">=2.0.0"`; none uses
`phase = "vapor"`; check loops, where used, route iterations to pools and
carry that as an acceptance criterion in the formula header (packs.md §6).

## 6. Conversation wiring

*(O2. Documentary proxy: the four artifacts below plus the reaper-skip
clause.)* Adopted from [`tk-h9pq5`](../tk-h9pq5/design-doc.md) without
re-litigation; this section only binds its design to gc-next names.

- **Role:** `agents/converse/` (§4) — the design's `agents/conversation/`,
  renamed for branding and non-collision.
- **Turns:** child beads of the subject carrying
  `gc.run_target=converse` (→ `gc.routed_to` at pour),
  `gc.continuation_group=<subject-bead-id>`, `task_kind=conversation`, filed
  by formulas (primary), by formulas that events drive, or by `mol-nx-turn`.
- **Reaper skip:** `mol-nx-patrol-health`'s orphan-recovery step skips beads
  where `task_kind == "conversation"` — the sibling clause tk-h9pq5 Q1
  specifies, carried into the new patrol with its fail-safe (decline-only)
  property and a regression fixture.
- **Attention surface:** the Helm board is carried; pick-a-row
  files-or-attaches a turn (warm attach if a group member is live, else file
  and let demand spawn). `takeaway --release` maps to stop-routing-and-drain.
- **Self-titling:** the role renames its session to the subject on claim
  (`gc session rename "$GC_SESSION_ID" …`, the canonical-self-rename shape).
  tk-h9pq5 flags the pool-spawned-session integration as unproven; that check
  is cutover stage 2 (§9), with the design's two fallbacks recorded.

## 7. The doctrine census

*(O5. Documentary proxy: this table; Phase-3 review checks implementation
against it.)* Every repo-recorded doctrine, mapped. "Carried" means the
doctrine text/logic ships in gc-next (fresh-authored where it was prompt
text, ported where it is script/config); "recomposed" means the need is met
by a structural change; "retired" carries its rationale inline.

**Template fragments (12):**

| Doctrine | Disposition in gc-next |
|---|---|
| `canonical-self-rename` | Carried — injected into `converse` (self-title on claim, §6) and `thread`. |
| `convoy-integration-branch` | Carried — injected into `wright` and `lander`; the owned-convoy/integration-branch model is load-bearing in the state machine. |
| `cycle-recycle` (policy stub) | Recomposed — see overlay row below. |
| `file-work-records` | Carried — injected into `wright`; the docs-vs-specs filing rule is unchanged (file-structure.md owns it). |
| `heartbeat-no-consent-ui` | Recomposed — written for resident heartbeat agents; with zero residents its invariant ("never invoke consent UI; recycling is deterministic") becomes a clause in the patrol formulas' step doctrine instead of an injected fragment. |
| `layered-startup-discovery` (4 defines; lx-ody8m, tk-1waw2, upstream #1833, tk-fj56a) | Recomposed — the four-tier ephemeral-aware startup existed because resident patrols restart into ambiguous state. Disposable cycles don't restart — but the *reconcile* half (find in-progress work, adopt orphan wisps, `--include-infra`, `$GC_AGENT` not `$GC_ALIAS`, title-scoped reconcile) is exactly how a fresh `sentry`/`lander` cycle orients, so it is carried into the patrol formulas' first step. The lesson beads are cited there. |
| `operator-next-step-trailing` | Carried — injected into `converse` and `thread` (the operator-facing roles). |
| `polecat-convoys` | Carried — into `wright` (target resolution under an owned convoy). |
| `polecat-non-impl-done` (the 70K signoff-gate + non-impl done-sequence doctrine) | Carried — the largest single carry. Split in two: the non-impl done-sequence into `wright`'s prompt; the signoff-gate machinery (COMMENT-never-APPROVE, `check.<gate>=green@<sha>`, pre-open branch review, host/repo pinning) into the review-step fragment `mol-nx-work` dispatches and `lander`'s gating doctrine. |
| `thread-role` | Carried — is the `thread` template's contract (§4). |
| `upstream-engagement` | Carried — moves to the `gascity-keeper` sub-pack (it is fork-lifecycle doctrine; core gc-next has no upstream to engage). |
| `watch-dispatched-work` | Carried — injected into `thread` and the keeper; referenced by dispatching formulas. |
| **Overlay: `cycle-recycle` hook** (tk-g8pfg) | Recomposed — the deterministic 200K-token Stop-hook recycle existed for resident patrols. gc-next's patrol cycles die every cycle; the residual long-holding case is `converse` mid-hold, where the doctrine becomes: at threshold, write the outcome to the subject and let the session die (§4). The hook itself ships in gc-next staged onto `converse` only, self-gated as today. Invariants (never prompt, exit 0, defer while operator attached) carried verbatim. |

**Doctor checks (9):** all carried. The three base-artifact-collision
snapshots re-point at gc-next's own formulas (the check's job — detect silent
shadowing — becomes *more* important during staging); merge-gate-drop
(tk-4na1b), cycle-recycle-wiring (re-scoped to `converse`),
startup-discovery-tiers (re-scoped to the patrol formulas' orient step),
PR-prep-N=1 (tk-ur4o2) and the four keeper checks move with the keeper
sub-pack.

**Orders (4):** `doc-keeper-drift-audit` + `doc-keeper-memory-audit` carried
(fire the renamed formulas); `quota-park-nudge` (tk-al95k) carried verbatim —
quota-parking afflicts any session, not just residents; `reconcile-rig-
checkouts` carried verbatim.

**Formula-embedded doctrines:** close-on-land + GATING sub-states + check_set
machinery + approval member + anchor repair (`mol-nx-patrol-land`, from
refinery-patrol); Idle Town Principle + warrant caps (`mol-nx-patrol-health`,
from deacon-patrol); orphan re-offer lever table + never-exit-mid-step #1884
(`mol-nx-patrol-health`, from witness-patrol); flag-don't-close + universe
slice + card shape (`mol-nx-first-reaction`).

**Tools, skills, services:** `gc-bd-universe.sh`, `gc-helm.sh`/helm service,
`gc-bd-watch.sh`, merge/check-set/pre-open script family — carried (renamed
under the collision rule where basenames clash). `gc-bead-host.sh` and
`agents/bead-host/` — **retired**: superseded by tk-h9pq5 (its Q4 resolution;
zero live instances, migration is deletion). `gc-proactive.sh` carried for
`outrider`. Skills (`filing-documentation`, `handoff`, `session-title`,
`demo-capture`, `gc-demo-script`) carried unchanged — they are already
pack-native and roster-agnostic. `_polecat-gemini` — retired (disabled today;
its provider-diversity intent is the cutover-stage `wright-codex` decision,
§4).

## 8. Sub-pack boundaries

*(O1, O9.)* Two packs ship from this repo after cutover, as today:

- **`gc-next` (→ gc-toolkit)** — the core: roster, delivery, conversation,
  patrols, doc audits, skills, doctor checks, orders.
- **`gascity-keeper`** — carried as-is with three additions from the census
  (`upstream-engagement` fragment; its doctor checks; its keeper resident,
  which stays `on_demand` and is argued under O7 in its pack.toml header: the
  fork domain needs the partner hat conversationally, holds fork state
  worth a warm session, and is opt-in to exactly one rig — the exception is
  scoped, recorded, and cheap). Its patches wire via the importing city's
  `[[rigs.patches]]`, unchanged.

The boundary rule, restated once: **rig-specific capability never enters the
core pack.** Anything true only for a fork-bearing rig lives in the keeper;
anything true for every importer lives in core.

## 9. Cutover stages

*(Non-goal: no big-bang. Each stage is reversible; each is a future bead, not
branch work.)*

0. **Intake** — re-key `specs/2026-08-rethink/` to the tracking bead; further
   changes ride Delivery (ends the bootstrap exception).
1. **First-run validation** — a staging rig imports `packs/gc-next`;
   `gc doctor` clean; the collision audit passes with both packs loaded in
   one city.
2. **Conversation gate** — tk-h9pq5 Phase 0–1 gates run against gc-next
   (including the pool-session self-rename check; pick a fallback if it
   fails).
3. **Patrol shakeout** — `sentry` and `lander` cycles run the staging rig
   unbabysat; the doctor suite green over a sustained window; quota-park and
   checkout-reconciler orders observed firing.
4. **Rig flip** — importing rigs switch `[rigs.imports]` from gc-toolkit to
   gc-next one rig at a time; the old composition remains importable
   throughout (rollback = revert the import line).
5. **Name and root takeover** — gc-next's contents move to the repo root,
   the pack takes the `gc-toolkit` name, `mol-nx-*` renames to `mol-*`, the
   old roster/patches/import are deleted, and **central docs are rewritten in
   place** to speak the new truth (the O6 cutover stage): architecture.md's
   transition section shrinks to what remains open (intake), install.md
   re-documents the import, pack.toml's gastown import is gone.
6. **Decommission** — retire `bead-host` config and any stragglers; file the
   provider-diversity (`wright-codex`) decision bead.

## 10. Documentary proxies, per outcome

| Outcome | Phase-3 review accepts |
|---|---|
| O1 | `packs/gc-next/pack.toml` with zero example-pack imports; §2's table realized; the collision audit script and its clean run. |
| O2 | The four §6 artifacts: `agents/converse/`, the turn-filing convention doc'd in its prompt + `mol-nx-turn`, the reaper-skip clause in `mol-nx-patrol-health`, the Helm rewire noted in the carried helm script header (implementation of the rewire itself is cutover-gated). |
| O3 | `mol-nx-work` + `mol-nx-patrol-land` conforming to the state machine doc; mr-mode + non-empty `check_set` defaults for agent-initiated work. |
| O4 | The interlock line present in every formula header (§5). |
| O5 | Every census row (§7) resolvable to a file/section in the staged tree, or its retirement rationale present in this spec. |
| O6 | No central doc rewritten on this branch beyond transition markers; this spec carries the cutover-stage rewrite list (§9 stage 5). |
| O7 | Zero `[[named_session]]` in `packs/gc-next/pack.toml`; the keeper argued in its own header; the §4 residency decision recorded. |
| O8 | A one-sentence brand at the top of every agent.toml, formula, and the pack README. |
| O9 | §7's doctor/orders/formula-doctrine rows implemented; keeper sub-pack intact. |

## 11. Consistency-test traces

Each shipped capability traces belief → primitive → standing composition
(architecture's test). The implementation repeats the trace in each artifact's
header; the spec-level table:

| Capability | Belief | Primitive(s) | Composes like |
|---|---|---|---|
| `wright` + `mol-nx-work` | Human attention is the budget | bead, molecule, routing | Delivery |
| `lander` + `mol-nx-patrol-land` | Edges visible (checks); attention budget | check, bead, routing | Delivery |
| `converse` + turns | Attention is the budget; earn every interaction | bead (continuation group), role, routing | Attention & conversation |
| `sentry` + `mol-nx-patrol-health` | Agents improve | molecule, routing | Engine health |
| `outrider` + `mol-nx-first-reaction` | Earn every interaction | molecule, routing | Attention & conversation |
| doc audits | Decisions have a home | molecule, routing | Doc & knowledge cohesion |
| keeper sub-pack | Borrow before invent | skill, role, molecule | Fork & upstream |
| doctor suite + orders | Agents improve | check (composed) | Engine health |
