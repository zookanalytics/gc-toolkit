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
  in `gc-next` — agents, formulas, fragments, scripts, doctor checks, orders,
  and skills — is distinct from every basename in the current pack, in the
  imported gastown layer, *and in the bundled builtin packs* (core/bd/dolt,
  loaded in every city — core ships `mol-do-work.toml` and
  `graph-worker.md`). The implementation ships a collision audit script and
  the review checks it. Formulas use a `mol-nx-*` prefix and doctor checks a
  `check-nx-*` prefix during staging for this reason (renamed at cutover when
  the old set retires). Two artifact classes are handled by ownership rather
  than rename: roster-agnostic **skills** and the two roster-agnostic
  **orders** (`quota-park-nudge`, `reconcile-rig-checkouts`) stay owned by
  the live pack through the overlap window and move to gc-next only at stage
  5 (§9) — shipping copies in both packs would silently shadow or
  double-fire. **`[global]` hooks are not basenames and no audit catches
  them**: gc-next's status-line global is gated behind an env var
  (`GC_NX_STATUS=1`) during staging so the overlap window never has two
  writers of the status bar; the gate is removed at stage 5.

Layout inside `packs/gc-next/` follows the pack spec's well-known directories:

```
packs/gc-next/
├── pack.toml              # schema=2; no [imports] of any example pack
├── agents/<name>/         # agent.toml + prompt.template.md, colocated
├── formulas/mol-nx-*.toml
├── template-fragments/
├── assets/scripts/        # private files, per pack-spec (no top-level scripts/)
├── doctor/check-nx-*/
├── orders/nx-*.toml
├── services/helm/         # the Go sidecar, carried (§7)
└── README.md              # brand, scope, install pointer
```

(No `skills/` during staging: roster-agnostic skills stay owned by the live
pack until stage 5 — the §1 ownership rule.)

## 2. What the gastown import supplies today, and where each piece goes

*(O1's enumeration. Sources: root `pack.toml`, `docs/install.md`, the agents
inventory.)* The wholesale import currently supplies the six patched roster
agents plus the non-roster capabilities below:

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
| **The imported work-formula family** — `mol-polecat-work` (the city-scope `default_sling_formula`; depended on by the witness patrol, first-reaction, and both doc audits), `mol-polecat-base` (the keeper's `mol-upstream-gc-sync` hard-depends on it via `extends`), `mol-review-leg`, and the dog formulas | **Succeeded natively.** `mol-nx-work` is the successor of `mol-polecat-work`, and repointing `default_sling_formula` at it is an explicit flip-stage step (§9 stage 4). `mol-review-leg`'s dispatch duty is subsumed by `mol-nx-work`'s review step. The keeper's sync formula is re-based off `mol-polecat-base` at the keeper-retarget step (§8). Dog formulas are subsumed by the dog-drop row above. |

The `gc.attention` / Helm surface is gc-toolkit's own (it does not cross the
import boundary) but is listed here for completeness because its wiring
assumes the gastown-shaped roster: it is carried and rewired per tk-h9pq5
(§6). Skills, orders, doctor checks, services, and tools are already native
(inventory, Phase 1).

**Native roster dispositions** (the current pack's own agents, for the same
completeness — each residency call is on the record per O7):

- **`mechanik`** (the pack's only current `[[named_session]]` resident;
  city-scoped, `mode="always"`) — **dropped as a resident, recomposed.**
  Its stewardship function — "its steward dispatches, it does not hand-edit"
  — distributes per tk-h9pq5 open question 2's direction: structural
  engineering work arrives as ordinary routed beads to `wright`; strategy
  conversation happens in a `thread-ops` session or as conversation turns on
  the subject bead. Its prompt doctrines land per the injection matrix (§7).
  This resolves the mechanik half of OQ2 on the record, not just the mayor
  half.
- **`bead-host`** — retired (census §7; tk-h9pq5 Q4).
- **`polecat-codex` / `_polecat-gemini`** — cutover-stage decision (§4).
- **`mayor-thread` / `mechanik-thread`** — succeeded by `thread-*` roles
  (§4).
- **`proactive`** — succeeded by `outrider` (§4).

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
gc-next lives in **self-continuing chains on routed, disposable pool
sessions** — a cycle claims its cycle bead, pours its patrol molecule
in-session, works it, files the next cycle routed back to the pool, and
drains. No resident patrol singletons. This revises the "resident patrol
loops" reading of architecture's Engine-health bullet, deliberately and on
the record: the three-hats clause ("nothing continuous can live in a role
that exists only between claim and drain") is satisfied because *the
continuity is not in the role* — it is in the chain of filed work, which
survives any individual session. What the resident model bought — a warm
context across cycles — is exactly what the cycle-recycle overlay exists to
throw away at 200K tokens anyway; gc-next sheds it every cycle by
construction. **The default roster is therefore zero `[[named_session]]`
entries in the core pack.** The keeper (in the carried `gascity-keeper`
sub-pack, §8) remains the one `on_demand` resident, argued there.

Three mechanics make the chain shape sound, and each is a specified
deliverable, not an aspiration:

- **The cycle bead is a plain routed bead, not a molecule root.** A v1
  molecule-container root is not Ready-visible to a scale-from-zero pool, and
  the `phase="vapor"` root-only workaround is the legacy mechanism new
  formulas must not use (packs.md §3). So cycle N ends by `bd create`-ing a
  plain next-cycle bead with `gc.routed_to=<pool>` stamped directly
  (stamp-don't-sling: in a city carrying a `default_sling_formula`, a bare
  sling is silently a Lane-4 attach that stamps no routing field —
  gascity-routing-model.md), unassigned, Ready-visible. The claimant's first
  act is to pour the patrol molecule into its own session and work it.
- **Chains are anchored, because every chain needs a first link and a repair
  path.** A fresh import has no cycle bead, and a failed file ends a chain
  silently — the current formulas' own guarded "could not pour; not burning"
  paths prove files fail. gc-next therefore ships a **chain-anchor order**
  (`orders/nx-patrol-anchor.toml`): on schedule, for each rig chain (land,
  health-rig), if no open cycle bead exists, file one — idempotent, so a
  live chain is untouched. Orders fire on schedule regardless of roster
  state, which is what makes the anchor the one piece of continuity that
  does not itself ride a chain. **Amended after phase-3 review (B4/D6):**
  the anchor fires a v2 formula (`mol-nx-patrol-anchor`) at the sentry pool
  — the proven order→pool wisp path — rather than an exec script, because
  order-exec env and store resolution for `gc bd` writes are undocumented;
  and the **health-city chain is a stage-4 activation**, not a staging
  deliverable: the both-contexts scope expansion this section previously
  assumed applies to city-level packs only, so the town half needs
  city-level import wiring that is a cutover decision, and the live pack's
  patrols keep owning town health through the overlap window.
- **Chain liveness is a doctor check** (`check-nx-patrol-chain-liveness`):
  errors when a rig chain has no open cycle bead and warns when the newest
  cycle bead is older than **twice** the anchor interval, doubled, or the
  ledger is unreadable. "Chain survives a killed file" is a stage-3 cutover
  gate (§9).

| Agent | Brand (one sentence, O8) | Variant & shape |
|---|---|---|
| **`wright`** | Builds one bead's output on its own branch and hands off to gating; it never lands, never closes a unit that merges. | Pool worker; explicit `scope="rig"`, `wake_mode=fresh`, `max_active_sessions=4`. Claim via standard hook tiers. Prompt authored fresh; fragments per the injection matrix (§7). |
| **`lander`** | The single writer of merged-truth: drives every gating anchor through its check-set and performs the merge, and is the only thing that targets the protected boundary. | **Demand-scaled, capped at one**: pool-shaped config, explicit `scope="rig"`, `max_active_sessions=1`, scale-from-zero on routed demand. The cap governs **controller-managed desired state only** — a manual `gc session new` can still mint a second instance, and the drain-ack-with-assigned-work repair can overlap teardown with a fresh claim — so the cap is an operational convenience, **not** the correctness boundary: the actual single-writer guarantee stays where the state machine puts it, in the merge skill's validate-merge-record sequence and close-on-land (§3 rule 5). A prompt clause and a doctor check ban manual spawns against lander. Runs `mol-nx-patrol-land` cycles (v1 self-pour, §5). |
| **`sentry`** | Runs one health-patrol cycle — orphans, queues, sessions, stores — files what it finds, executes bounded repairs, files the next cycle, and drains. | Pool worker; explicit `scope="rig"` (**amended after phase-3 review, B3**: the tri-state both-contexts expansion this row previously relied on applies to city-level packs only, so under this pack's rig-level import an unscoped sentry is rig-only regardless). Each rig expansion runs that rig's chain; the **town chain is a stage-4 activation** requiring city-level import wiring (D6), with the live pack's patrols owning town health until then. `max_active_sessions=2`, `wake_mode=fresh`. Runs `mol-nx-patrol-health` (v1, §5) with steps gated on a `chain_scope` var; executes bounded runtime-state repairs (§2 dog disposition). |
| **`converse`** | Holds a subject bead's conversation for the operator: rebuilds the slice, preps, holds, writes the outcome to the subject, closes only the turn. | Pool worker per tk-h9pq5 §Key-Components-3: `run-operator` shape with the hold-not-close clause; explicit `scope="rig"` (beads and continuation groups are rig-scoped); `max_active_sessions=2`; claims turns via `gc.routed_to`, continuity via `gc.continuation_group` vacuum. Carries the recycle guard: at the context threshold it writes the turn outcome to the subject and lets the session die (turn boundaries are the release valve). |
| **`outrider`** | Meets a newly filed bead before the operator does: reads its universe, writes the first-reaction card, flags it onto the board, and drains. | Small pool (explicit `scope="rig"`, `max_active_sessions=2`) executing `mol-nx-first-reaction`; carries the default-disabled gate + city-wide shed clamp doctrine in both `work_query` and `scale_check` (census §7). Kept separate from `converse` (tk-h9pq5 open question 4): an outrider run is autonomous and must never hold a slot waiting for an operator. |
| **`thread-ops`** | An operator-spawned parallel line of judgment — it acts and dispatches on the operator's behalf but owns no inbox, no patrol cadence, and no system-of-record identity. | Thread shape carried exactly from the existing thread agents (`work_query = "printf '[]'"`, failing `sling_query`, `wake_mode=resume`, `min_active_sessions=0`, explicit `scope="city"`). The thread *contract* is one shared fragment; each thread role is a thin `agent.toml` + role prompt, because `[env] RoleName` is static per agent.toml — there is no spawn-time parameterization (correcting an earlier draft's "one generic template"). gc-next ships exactly one thread role initially: `thread-ops`, whose role prompt is the fresh-authored operations/strategy line (the root/strategy conversation tk-h9pq5 OQ2 keeps); further thread roles are thin additions. |

**`wright-codex`** ships in staging (**amended per operator ruling,
decisions.md #4** — cross-provider validation is a strong requirement and
the direction is more of it, not less; the earlier draft deferred this to a
cutover-stage decision): a wright backed by the Codex provider, sharing the
wright prompt by reference, carrying `nx-signoff-gate`, capped at 2. Every
signoff-gate review the lander dispatches routes to it, preserving the
independence the live polecat-codex gives the pre-open gate today. The
operator's standing target — roughly a third of token spend validating work
through other agents — is recorded as the direction for future check-set
members. `_polecat-gemini` stays retired (disabled today); a Gemini wright
variant is a natural later leg under the same target.

## 5. The formulas

*(O3, O4. Documentary proxy for O4: the interlock line in each formula
header.)* Every formula ships with a header stating: contract (v1/v2) and why,
what it pours or routes, and — the O4 bar — either the step that signs off
each check it gates, or the recorded note naming which step will when the
interlock lands.

| Formula | Contract & why | Interlock position |
|---|---|---|
| **`mol-nx-work`** | **v2** — the implementation workflow: independently-routable step beads (build → hand-off), routed to `wright`; step bodies close `$GC_BEAD_ID` with `gc.outcome` per the graph-worker idiom. Its `workflow-finalize` bead is dispatcher-processed, so the formula header names the operational dependency: **a `gc convoy control --serve` loop must be running** (packs.md §4); observing it process finalize beads is a stage-3 gate (§9). | Build step ends by handing to gating with `check_set` declared; the signoff-gate stamp (`check.<name>=green@<sha>`) is written by the review step it dispatches — step-signs-off-check implemented. |
| **`mol-nx-patrol-land`** | **v1** — a self-continued patrol is data one agent works through in its own session; v2's engine buys it nothing (packs.md §1, and §3 rule 4 here). The current `mol-refinery-patrol` is *not* a precedent for "v2 self-pour": it declares the v2 compiler while pouring root-only — the exact self-contradictory shape packs.md §3 documents — and is harmless only because the declaration is inert. gc-next does not reproduce the mis-build. The cycle: reconcile gating anchors, dispatch pre-open reviews (a sling within a step, not an engine-routed step), run the merge skill, graduate convoys, file the next cycle bead (§4 chain shape). Carries the close-on-land, per-gate-marker, approval-member, and anchor-repair doctrines (census §7). | The merge step *is* a check-discharger by construction; unrun-check-runs-itself is partially realized by the stale-gate re-dispatch arm — noted in the header as the interlock's current realization, full self-running checks deferred. |
| **`mol-nx-patrol-health`** | **v1** — same rationale. File-next-before-work (the pour-before-burn descendant for the chain shape); never exits from an intermediate step (#1884). Merges the deacon-patrol and witness-patrol doctrines into one health cycle, with steps gated on the `chain_scope` var (city vs rig, §4) and per-step caps. | Recorded note: health checks it performs (orphan scan, queue starvation) become self-running checks when the interlock lands; today the cycle files what it finds. |
| **`mol-nx-first-reaction`** | **v1** — one-shot; advance-and-drain. Flag, don't close; mr-only for code; fenced-untrusted-data rule carried. | N/A (files no gated work itself); note recorded in header. |
| **`mol-nx-turn`** | **v1, one step** — the operator-driven trigger: create a turn bead in the subject's group routed to `converse`. The "I want to talk about this" one-step formula named by architecture. | N/A; note in header. |
| **`mol-nx-doc-drift`** / **`mol-nx-doc-memory`** | **v2** — carried from the doc-keeper pair nearly as-is (prime → audit → drain, routed to `wright`), renamed for the non-collision rule. | Recorded note (a new obligation — the current pair carries none). |

All v2 formulas declare `[requires] formula_compiler = ">=2.0.0"`; none uses
`phase = "vapor"`; check loops, where used, route iterations to pools and
carry that as an acceptance criterion in the formula header (packs.md §6) —
and no check loop may route iterations to `lander` without first verifying
that a `max_active_sessions=1` pool satisfies the multi-session
pool-route predicate, whose failure is silent (packs.md §6).

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
  and let demand spawn), and `takeaway --release` maps to
  stop-routing-and-drain. **Amended after phase-3 review (D2):** the rewire
  is **shipped as executable bash** in the staged tree: `nx-helm.sh` is a
  full copy of the live helm script with `cmd_open` rewired to
  file-or-attach a turn and `--release` re-meaning ending the conversation
  (**re-amended per operator ruling, decisions.md #7**: the live helm is
  frozen while this path is explored, so the divergence cost that
  motivated the earlier port-row compromise is gone). The Go sidecar
  remains a port row (roster-agnostic, unchanged).
- **Subjects never park `in_progress` under a hold.** The reaper-skip clause
  covers *turns* (`task_kind=conversation`); the subject bead needs no
  sibling shield because holding is the turn's job — the subject stays `open`
  (or whatever its own work lifecycle says) while a turn holds. The converse
  prompt states this invariant.
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

**The injection matrix** — the single authority on which fragment doctrine
reaches which role (§2 and §4 cite it; where they once disagreed, this table
wins):

| Fragment doctrine | → gc-next roles |
|---|---|
| `canonical-self-rename` | `converse` (self-title on claim, §6), `thread-ops` |
| `convoy-integration-branch` | `wright`, `lander`, `thread-ops` |
| `file-work-records` | `wright` |
| `operator-next-step-trailing` | `converse`, `thread-ops` |
| `polecat-convoys` | `wright` |
| `polecat-non-impl-done` — done-sequence half | `wright` |
| `polecat-non-impl-done` — signoff-gate half | `nx-signoff-gate`, appended to every `wright` (review beads run on that pool), and `lander`'s gating doctrine |
| `thread-role` (the thread contract) | every `thread-*` role |
| `upstream-engagement` | keeper (sub-pack) |
| `watch-dispatched-work` | `thread-ops`, keeper; referenced by dispatching formulas |

**Template fragments (12) — dispositions:**

| Doctrine | Disposition in gc-next |
|---|---|
| `canonical-self-rename` | Carried — per matrix. |
| `convoy-integration-branch` | Carried — per matrix; the owned-convoy/integration-branch model is load-bearing in the state machine. |
| `cycle-recycle` (policy stub) | Recomposed — see overlay row below. |
| `file-work-records` | Carried — per matrix; the docs-vs-specs filing rule is unchanged (file-structure.md owns it). |
| `heartbeat-no-consent-ui` | Recomposed — written for resident heartbeat agents; with zero residents its invariant ("never invoke consent UI; recycling is deterministic") becomes a clause in the patrol formulas' step doctrine instead of an injected fragment. |
| `layered-startup-discovery` (4 defines; lx-ody8m, tk-1waw2, upstream #1833, tk-fj56a) | Recomposed — the four-tier ephemeral-aware startup existed because resident patrols restart into ambiguous state. Disposable cycles don't restart — but the *reconcile* half (find in-progress work, adopt orphan work, `--include-infra`, `$GC_AGENT` not `$GC_ALIAS`, title-scoped reconcile) is exactly how a fresh `sentry`/`lander` cycle orients, so it is carried into the patrol formulas' first step. The lesson beads are cited there. |
| `operator-next-step-trailing` | Carried — per matrix. |
| `polecat-convoys` | Carried — per matrix (target resolution under an owned convoy). |
| `polecat-non-impl-done` (the 70K signoff-gate + non-impl done-sequence doctrine) | Carried — the largest single carry, split per matrix. |
| `thread-role` | Carried — is the thread contract (§4). |
| `upstream-engagement` | Carried — moves to the `gascity-keeper` sub-pack (fork-lifecycle doctrine; core gc-next has no upstream to engage). |
| `watch-dispatched-work` | Carried — per matrix. |
| **Keeper fragments (3):** `rebase-conventions`, `polecat-patterns`, `refinery-rebase-handling` | Carried in the keeper sub-pack, re-targeted at cutover: their injection targets become `wright` and `lander` (§8), and `refinery-rebase-handling`'s carve-out language is re-keyed to `lander`'s never-force-push rule. |
| **Overlay: `cycle-recycle` hook** (tk-g8pfg) | Recomposed — the deterministic 200K-token Stop-hook recycle existed for resident patrols. gc-next's patrol cycles die every cycle; the residual long-holding case is `converse` mid-hold, where the doctrine becomes: at threshold, write the outcome to the subject and let the session die (§4). The hook ships in gc-next staged onto `converse` only, with **two deliberate changes from the shipped overlay**: the role self-gate is re-keyed from `witness\|deacon\|refinery` to `converse` (carried "as today" it would be a permanent no-op), and the action changes from handoff-mail + `gc session reset` to **record-then-drain** — write the turn outcome to the subject, then drain-ack; a pool session has no singleton identity to reset into. Invariants (never prompt, exit 0, defer while operator attached) carried verbatim. |

**Doctor checks (9, by their exact names):** all carried, renamed under the
`check-nx-*` staging prefix (§1). `check-base-artifact-collision`'s snapshots
re-point at gc-next's own formulas (the check's job — detect silent shadowing
— becomes *more* important during staging); `check-merge-gate-drop`
(tk-4na1b) carried; `check-cycle-recycle-hook` re-scoped to `converse`;
`check-startup-discovery` re-scoped to the patrol formulas' orient step;
`check-pr-prep-single-commit-unchanged` (tk-ur4o2) and the four keeper checks
move with the keeper sub-pack. Two checks are **new** (§4): the lander
manual-spawn ban and `check-nx-patrol-chain-liveness`.

**Orders (4 existing + 1 new):** `doc-keeper-drift-audit` +
`doc-keeper-memory-audit` re-authored under `nx-` names (they fire the
renamed formulas); `quota-park-nudge` (tk-al95k) and
`reconcile-rig-checkouts` are roster-agnostic and **stay owned by the live
pack until stage 5** (§1 ownership rule — a copy in both packs would
double-fire). New: `nx-patrol-anchor` (§4 chain anchor).

**Formula-embedded doctrines:** close-on-land + GATING sub-states + check_set
machinery + approval member + anchor repair (`mol-nx-patrol-land`, from
refinery-patrol); Idle Town Principle + warrant caps (`mol-nx-patrol-health`,
from deacon-patrol); orphan re-offer lever table + never-exit-mid-step #1884
(`mol-nx-patrol-health`, from witness-patrol); flag-don't-close + universe
slice + card shape (`mol-nx-first-reaction`).

**Tools, skills, services:** `gc-bd-universe.sh`, `gc-helm.sh`/the helm
service (the Go sidecar ships under `services/helm/` in gc-next, same layout
as today), `gc-bd-watch.sh`, and the merge/check-set/pre-open script family —
carried under `assets/scripts/` (renamed where basenames clash; the overlay
tree ships under `assets/` per pack-spec). `gc-bead-host.sh`,
`agents/bead-host/`, and the two bead-host fixtures — **retired**: superseded
by tk-h9pq5 (its Q4 resolution; zero live instances, migration is deletion).
The remaining fixtures (helm-open, helm-surface, proactive-first-reaction,
bead-universe-reachability) are carried with the tools they pin.
`upstream-gc-sync.sh` moves to the keeper sub-pack with the rest of the fork
lifecycle. `gc-proactive.sh` carried for `outrider`. Skills
(`filing-documentation`, `handoff`, `session-title`, `demo-capture`,
`gc-demo-script`) are roster-agnostic and stay owned by the live pack until
stage 5 (§1 ownership rule). `_polecat-gemini` — retired (disabled today; its
provider-diversity intent is the cutover-stage `wright-codex` decision, §4).

## 8. Sub-pack boundaries

*(O1, O9.)* Two packs ship from this repo after cutover, as today:

- **`gc-next` (→ gc-toolkit)** — the core: roster, delivery, conversation,
  patrols, doc audits, skills, doctor checks, orders.
- **`gascity-keeper`** — carried, with the recompositions O1 forces (it is
  *not* untouched, correcting an earlier draft): its three fragments'
  injection targets re-point from refinery/polecat to `lander`/`wright` — a
  `[[rigs.patches]]` block whose target agent no longer exists **fails
  loading outright** (packs.md §8), so leaving the importing city's patches
  aimed at deleted agents would break the fork rig at stage 5, and the
  retarget is a named stage-4 step for that rig (§9); `mol-upstream-gc-sync`
  is re-based off the imported `mol-polecat-base` it currently `extends`
  (§2); `upstream-engagement` and `upstream-gc-sync.sh` move in (census §7).
  The keeper resident stays `on_demand` and is argued under O7 in its
  pack.toml header: the fork domain needs the partner hat conversationally,
  holds fork state worth a warm session, and is opt-in to exactly one rig —
  the exception is scoped, recorded, and cheap. **Operator lean on the
  record (decisions.md #9): keeping a resident here "seems weird with the
  rest of the approach"** — the keeper's residency is re-argued (or retired
  onto chains and conversation turns) as a cutover-era bead rather than
  silently perpetuated.

The boundary rule, restated once: **rig-specific capability never enters the
core pack.** Anything true only for a fork-bearing rig lives in the keeper;
anything true for every importer lives in core.

## 9. Cutover stages

**Strategy ruling (operator, decisions.md #8): the primary path is
all-or-nothing** — stand up a **fresh city** importing gc-next (city-level
where needed, which dissolves D6 at creation), copy the critical beads
over, run the same rigs, and shut the current city down once the new one
holds. Under that path, stages 1–3 below run unchanged as the *staging
city's* shakeout, and stages 4–5 collapse into one migration event: the
fresh city never runs the old composition, so the per-rig flip, the
overlap-window ownership rules, and the `nx-` renames become insurance
rather than choreography (the renames still happen at root takeover; they
are just uncontended). The staged per-rig flip below remains documented as
the conservative fallback if all-or-nothing is judged too sharp when the
moment comes. The operator reads the final PR before any trigger is
pulled.

*(Each stage is reversible; each is a future bead, not branch work.)*

0. **Intake** — re-key `specs/2026-08-rethink/` to the tracking bead; further
   changes ride Delivery (ends the bootstrap exception).
1. **First-run validation** — a staging rig imports `packs/gc-next`;
   `gc doctor` clean; the collision audit passes with both packs loaded in
   one city.
2. **Conversation gate** — tk-h9pq5 Phase 0–1 gates run against gc-next
   (including the pool-session self-rename check; pick a fallback if it
   fails), plus the Helm rewire exercised end-to-end (§6).
3. **Patrol shakeout** — `sentry` and `lander` chains run the staging rig
   unbabysat; the doctor suite green over a sustained window; the chain
   anchor observed re-seeding a deliberately killed chain (§4); the
   control-dispatcher serve loop observed processing a `mol-nx-work`
   finalize bead (§5); quota-park and checkout-reconciler orders observed
   firing.
4. **Rig flip** — importing rigs switch `[rigs.imports]` from gc-toolkit to
   gc-next one rig at a time; the city-scope `default_sling_formula` repoints
   from `mol-polecat-work` to `mol-nx-work` (§2); the fork rig's
   `[[rigs.patches]]` retarget from refinery/polecat to `lander`/`wright`
   (§8). The old composition remains importable throughout (rollback = revert
   the import line and the two repoints).
5. **Name and root takeover** — gc-next's contents move to the repo root,
   the pack takes the `gc-toolkit` name, `mol-nx-*`/`check-nx-*`/`nx-*`
   rename to their permanent names (re-running the collision audit against
   the builtin packs), roster-agnostic skills and orders transfer ownership,
   the `[global]` staging gate is removed, formula-body script paths are
   re-audited (the `$GC_CITY_PATH/rigs/<pack>/…` segment changes with the
   move — the silent-no-op class packs.md §9 documents), the old
   roster/patches/import are deleted, and **central docs are rewritten in
   place** to speak the new truth (the O6 cutover stage): architecture.md's
   transition section shrinks to what remains open (intake), install.md
   re-documents the import, pack.toml's gastown import is gone.
6. **Decommission** — retire `bead-host` config and any stragglers; file the
   provider-diversity (`wright-codex`) decision bead.

## 10. Documentary proxies, per outcome

| Outcome | Phase-3 review accepts |
|---|---|
| O1 | `packs/gc-next/pack.toml` with zero example-pack imports; §2's table realized; the collision audit script and its clean run. |
| O2 | The four §6 artifacts: `agents/converse/`, the turn-filing convention doc'd in its prompt + `mol-nx-turn`, the reaper-skip clause in `mol-nx-patrol-health`, and the Helm rewire **shipped in `nx-helm.sh`** (re-amended per decisions.md #7). |
| O3 | `mol-nx-work` + `mol-nx-patrol-land` conforming to the state machine doc; mr-mode + non-empty `check_set` defaults for agent-initiated work. |
| O4 | The interlock line present in every formula header (§5). |
| O5 | Every census row (§7) resolvable to a file/section in the staged tree, or its retirement rationale present in this spec. |
| O6 | No central doc rewritten on this branch beyond transition markers; this spec carries the cutover-stage rewrite list (§9 stage 5). |
| O7 | Zero `[[named_session]]` in `packs/gc-next/pack.toml`; the keeper argued in its own header; the §4 residency decision recorded. |
| O8 | A one-sentence brand at the top of every agent.toml, formula, and the pack README; new bead-type/metadata constants branded at their §3.6 definition sites; the turn-subject convention branded in the converse prompt and `mol-nx-turn`. |
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
