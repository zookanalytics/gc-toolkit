---
name: Design — Conversation-as-Continuation-Group (Bead-Universe v2)
description: The v2 reframe of the bead-universe conversation layer — a conversation is a continuation group with a role attached, assembled from Gas City core primitives (gc.continuation_group + a gc-role) instead of the bespoke per-bead session + hosts_bead binding of v1. Design-only; resolves the five questions posed on tk-h9pq5.
---

# Design: Conversation-as-Continuation-Group (Bead-Universe v2)

*Design-only spec for tk-h9pq5. It reframes the conversation-continuity layer of the Bead-Universe
Operating Model. v1 (`specs/bead-universe/design-doc.md`; implementation epic tk-q4xaj, CLOSED
2026-06-13) bound a conversation to a bead with a **bespoke per-bead session** plus a durable
`hosts_bead` link and "warm-while-live" grounding. This v2 reframe — settled in operator discussion
2026-07-29 — rebuilds the same capability from **primitives that already ship**, so "the conversation
that comes and goes over the life of the work" needs no new binding machinery. No implementation in
this bead.*

---

## Executive Summary

**The reframe, and everything follows from it:** *A conversation is not a session. It is a
**continuation group with a role attached.*** v1 asked "how do we keep one session alive and bound to
a bead across suspends?" and answered with a per-bead host, a reverse `hosts_bead` link, and grounding
that fights drains to stay warm. v2 asks a different question — "how does a bead get a conversation
that can come and go?" — and finds the answer is **already in core**:

1. **The subject bead's id *is* the continuation group.** No reverse link, no `hosts_bead`, no bespoke
   spawn tool, no durable-binding contract to get right. `gc.continuation_group = <subject-bead-id>`
   *is* the binding — the group name is the link.
2. **Turns are beads.** Each time the work needs the operator, a small child bead is filed carrying
   `gc.run_target = <conversation-role>` and `gc.continuation_group = <subject-bead-id>`. It is
   ordinary routed work; pool demand spawns the session with no operator keystroke.
3. **The role is a conversationalist, not an executor.** Same implementation surface as the shipped
   `run-operator` role — a ~5-line `agent.toml` plus a prompt. It differs from run-operator in exactly
   **one clause**: where run-operator *executes and closes*, the conversation role *rebuilds the
   subject's slice, does the reachable prep, **holds** for the operator, writes the outcome back to the
   subject bead, and closes only the **turn***. Then it re-claims within the group and drains when the
   group is dry.

**The single most important consequence:** **turn boundaries are the release valve.** v1's binding
constraint was never session slots (those are not scarce) — it is that a provider conversation
eventually exhausts context. A resume-forever session spanning a months-long epic blows context with
no principled place to shed it. Because a v2 turn ends by writing its outcome to the subject bead,
**at any turn boundary the session can be allowed to die and nothing written down is lost.** "Let it
die" becomes a normal, safe operation instead of data loss — and the engineering burden flips from
*keeping a session alive* (v1's grounding, wake-reasons, config-drift-drain survival) to *making the
record good*, which we want anyway because the record is what makes the work legible to other agents
and to the operator weeks later.

**What v2 is:** a conversation layer that is pure assembly of shipping primitives — `run-operator`'s
claim contract, `gc.continuation_group`'s vacuum-onto-the-claiming-session behavior, and
`gc.run_target`→`gc.routed_to` pool routing. **What v2 supersedes:** the bead-host *binding and
lifecycle* (the per-bead session, `hosts_bead`, warm-while-live grounding). **What v2 keeps:** the
`gc.attention` board / Helm picker as the human-facing surface, rewired to route a turn instead of
resuming a host. Migration cost is near-zero: bead-host ships as *capability, not deployment* and has
no live instances to migrate.

**Sequence:** role + turn-mechanism → continuity (warm/cold) → reaper-skip for the hold → attention
rewire. Each ships and is gated independently, and none requires a schema migration — turns and the
group are metadata-only.

---

## Problem Statement

The bead-universe goal is unchanged from v1: bring the operator's serial, scoped attention to the
right branch of the work tree, and once there make everything already known or reachable — the unit
of engagement is **a bead with a resident LLM** (full framing: `specs/bead-universe/design-doc.md`,
tk-yrio). What is *new here* is a narrower, sharper problem the operator surfaced on 2026-07-29:

> A bead needs a **conversation that can come and go** over the life of the work — an epic lives for
> weeks; the operator drops in, ratifies or redirects, and leaves; the conversation must survive those
> gaps without either (a) an always-resident session that blows its context window, or (b) losing what
> was said when the session dies.

v1 solved "bound and resumable" but paid for "durable" by trying to keep the session *warm* — the
`agent.toml` header for bead-host documents the evolution from cold-by-default suspend/resume to
grounding that treats an involuntary drain as "a no-op-with-restart" so the reconciler revives the
host with its transcript intact. That works, but it makes durability a property of a **fragile live
session** and spends real engineering on surviving drains. The operator's instruction for v2 is to
**embrace core momentum**: if the same capability can be assembled from primitives that already ship,
build it that way, and let the *record* — not a kept-warm session — be what is durable.

---

## Primitives Verified

The bead asked that these be re-verified before writing. Each holds; evidence is cited so a reviewer
can re-check.

1. **A role is a prompt plus a claim contract, not a service.** `run-operator` (in the upstream
   `gc-roles` pack — `gascity/roles/agents/run-operator/`, which gc-toolkit imports nowhere today) is
   the reference implementation: its `agent.toml` is three lines (`description`, `scope`,
   `fallback=true`), and the whole contract lives in its `prompt.template.md`. That contract is
   *claim → execute → close(+stamp) → continue-or-drain*:
   - **Discovery is claim-only.** `gc hook --claim --json` is the *only* permitted discovery source;
     broad `bd ready`/`bd list`/root-bead/mail/session-log searches are explicitly forbidden, and it
     must never work a bead id that did not come from the immediately preceding claim
     (`run-operator/prompt.template.md` L15-19).
   - **Execute + close.** It executes exactly the claimed bead's description, stamps the requested
     `gc.outcome` (default `fail` + `gc.failure_class` on error), then `bd close`s **its own** claimed
     bead (L175, L180-188).
   - **Continue-or-drain, group-scoped.** After closing it re-runs the claim; it continues **only**
     for work in the *same* `gc.continuation_group` or `gc.root_bead_id`, and otherwise
     `gc runtime drain-ack`s (L215-229).
   This is the exact surface v2's conversation role is modeled on — see [Key Components §3](#key-components).

2. **A formula step declares who runs it, materialized as `gc.routed_to`.** A formula step author
   writes `metadata = { "gc.run_target" = "<role>" }` as a hint (e.g.
   `gascity/formulas/do-work.formula.toml:33`); the pour materializes the canonical wire key
   `gc.routed_to`, and the reconciler's spawn predicate keys on *that* — confirmed live at
   `agents/proactive/agent.toml:79`:
   `gc bd ready --metadata-field "gc.routed_to=$target" --unassigned --exclude-type=epic`. gc-toolkit
   itself uses `gc.run_target` in **zero** formulas today (grep count 0), so adopting the idiom is a
   deliberate first — see [Resolving the Mandated Questions §5](#resolving-the-mandated-questions).
   (My own claimed work bead carries `gc.routed_to: gc-toolkit/gc-toolkit.polecat`, first-hand proof
   the wire key is live.)

3. **`gc.continuation_group` is the continuity primitive, and it ships.** The hook-claim path reads
   `gc.continuation_group` to **vacuum open, unassigned sibling work onto the claiming session**
   (cited `gascity/internal/beadmeta/keys.go:458-460`). This is not theoretical: the very claim that
   dispatched *this* design bead used it — the `mol-polecat-work` pour set
   `gc.continuation_group = pool-workflow` on its step beads, and my `gc hook --claim` returned
   `continuation_group: pool-workflow` with five sibling steps vacuumed onto my session in one call.
   The same mechanism, keyed on the subject bead's id, is v2's *warm* continuity path.

   *Not built on:* `gc.session_affinity`. It is written but advisory only (no Go routing path reads
   it yet), so v2 relies on `gc.continuation_group` for continuity and does not depend on affinity.

---

## Proposed Design

The v2 loop, as one sentence:

> A **turn** is filed as a bead in the subject's continuation group and routed to the conversation
> role; **pool demand spawns the session** (or, if one is already live for the group, the claim
> **vacuums the turn onto it**); the role **rebuilds the subject's slice, does the reachable prep,
> holds for the operator**, records the outcome on the **subject** bead, closes the **turn**, then
> re-claims within the group and **drains when the group is dry** — the session free to die at that
> boundary because the record already holds everything.

Three commitments shape it:

- **Assembly over invention.** Every moving part already ships (`run-operator` contract,
  `continuation_group` vacuum, `run_target`→`routed_to` routing, the pool reconciler). v2 adds one new
  agent config, one turn-filing convention, and one reaper-skip clause — no new binding subsystem.
- **The record is the durable thing, not the session.** Continuity degrades gracefully (warm→cold)
  and the role never needs to know which case it is in; it re-reads the subject record every turn.
- **Additive rollout.** A conversation role is one more pool-agent config. Existing pools, the
  canonical mayor, mechanik, and the refinery keep running unchanged. Any bead *can* get a
  conversation; not every bead has one (capability, not deployment — inherited from bead-host).

---

## Key Components

**1. The subject bead as continuation group (the binding — and it's free).** The subject bead's id
*is* the group: turns carry `gc.continuation_group = <subject-bead-id>`. "Given a bead, find its
conversation" is "list open turns in group `<bead-id>`"; "is a session live for it" is "is any group
member `in_progress`." No `hosts_bead`, no forward cache, no lineage list, no atomic dual-write on
creation — all of which v1 needed. The group name carries the identity that v1's link had to store.

**2. Turns are beads.** A turn is a small child bead of the subject, filed when the work needs the
operator. It carries `gc.run_target = <conversation-role>` (→ `gc.routed_to` at pour) and
`gc.continuation_group = <subject-bead-id>`. It is ordinary routed pool work: the reconciler's
`gc bd ready --metadata-field gc.routed_to=<role> --unassigned` scan (`agents/proactive/agent.toml:79`
shape) spawns a session to satisfy the demand. A turn's *body* is the prompt for that visit ("PR review
posted — decision needed", "here is what changed while you were away", "ratify the spec"). Turns are
append-only history: the sequence of turn beads under a subject is the conversation's spine, legible on
a board and to any agent, independent of whether any provider transcript still exists.

**3. The conversation role (one clause different from run-operator).** A new agent —
`agents/conversation/` (or similar) — is `run-operator`'s shape with the execute/close clause replaced
by a *hold* clause. Its prompt, per turn:

| Step | run-operator | conversation role |
|---|---|---|
| Discover | `gc hook --claim --json` (only source) | **same** |
| Prime | execute the claimed bead's contract | **rebuild the *subject's* fed slice** (the turn names the subject via `gc.continuation_group`); do the reachable prep for the turn |
| Engage | — (autonomous) | **hold `in_progress` for the operator**; ratify/redirect in-band |
| Record | stamp `gc.outcome` on the claimed bead | **write the outcome to the *subject* bead** (a note / decision), stamp `gc.outcome` on the **turn** |
| Close | `bd close` its own claimed bead | **close only the turn bead** — never the subject (see below) |
| Continue | re-claim within `gc.continuation_group`/`gc.root_bead_id`, else drain | **same** — re-claim vacuums sibling turns of this subject; drain when the group is dry |

The subject bead is **never closed by the conversation role** — it closes through its own work
lifecycle (the refinery closes impl beads on land; a research/design bead closes by operator
disposition). The conversation role owns *turns*, not the subject's completion. This preserves the
polecat/refinery invariant carried from v1.

**4. Two-layered continuity, degrading gracefully.**
- **Warm** — a session is already live for the group (a prior turn still `in_progress`, or the same
  session between rapid turns): the next turn is **vacuumed onto it** by the `gc.continuation_group`
  claim path (primitive 3). The literal provider conversation continues — the session "remembers."
- **Cold** — the session is gone (drained at a turn boundary, reaped, or never existed): pool demand
  spawns a **fresh** role session, which claims the turn and **reconstitutes from the subject bead's
  accumulated record** (body + notes tail + the turn history + the reachable slice).

The role prompt does not branch on warm-vs-cold: it re-reads the subject record every turn, and warm
simply means it *also* remembers. This is the whole point of the reframe — **cold is a first-class,
lossless path**, not a degraded fallback the way v1's evicted-transcript case was.

**5. One entry point, three triggers.** All three collapse into the same mechanism — *file a turn
bead in the subject's group, routed to the role.* Do **not** build three mechanisms.
- **Formula-driven (primary).** A step in the work's own workflow files a turn when it needs
  ratification (e.g. a design workflow files "ratify the spec" before submit). Authored with
  `metadata = { "gc.run_target" = "<conversation-role>", "gc.continuation_group" = "<subject-id>" }`.
- **Event-driven.** An event drives a *formula*, which files a turn — never the event directly. The
  operator was explicit: a PR merely *opening* must not start a conversation; a PR *review posting*
  may trigger a formula that decides a discussion is needed. (The refinery's review loop already
  dispatches a formula on a review event — that formula is the natural hook point.)
- **Operator-driven.** "I want to talk about this" is a one-step formula: create the turn bead and
  route it. This is the [attention surface's](#key-components) pick-a-row action.

**6. The attention surface, rewired (not rebuilt).** The shipped board tooling is the Helm picker —
`prefix+b` / `assets/scripts/gc-helm.sh open` — over the `gc.attention` board metadata (there is no
`tools/gc-attention.sh`; the board lives in `gc-helm.sh`). v2 keeps the board and its ranking and
changes only what a pick *does*:
- **Pick-a-row** → *file-or-vacuum a turn*: if the group has a live member, the operator attaches to
  it (warm); else file a turn bead and let pool demand spawn it (cold). This replaces v1's
  "resume-or-create the bead-host" with "route-or-attach a turn" — same keystroke, core-primitive
  implementation.
- **`gc.attention` flag** (a bead's LLM raising its own hand) is unchanged — but now a flag *is* the
  natural precursor to a turn: flag sets the board metadata; pick-a-row files the turn.
- **`takeaway --release`** (Helm's teardown) maps to *ending the conversation*: it stops routing new
  turns and lets any warm session drain — no host to put down, because there is no host.

---

## Interface

| Surface | Change | Built from |
|---|---|---|
| `agents/conversation/agent.toml` + `prompt.template.md` | **New** — `run-operator` shape; hold-not-close clause | `run-operator` (3-line `agent.toml` + prompt) |
| Turn-filing convention | **New** — child bead with `gc.run_target=<role>` + `gc.continuation_group=<subject-id>` | `gc bd create`, `gc.run_target`→`gc.routed_to` pour |
| conversation pool (routed_to target) | **New** — a small dedicated pool, so turns never starve impl work | pool reconciler, `agents/proactive/agent.toml` shape |
| witness-patrol reaper skip | **Changed** — one clause so a parked turn/subject isn't orphan-recovered | `mol-witness-patrol.toml:147-171` host-bead-skip |
| Helm picker (`gc-helm.sh open` / `prefix+b`) | **Changed** — pick-a-row files-or-vacuums a turn (was: resume-or-create host) | existing `gc-helm.sh`, `gc.attention` board |
| `gc.continuation_group`, `gc hook --claim`, `gc bd ready`, pool reconciler, refinery, `gc bd create/update` | **Unchanged** — reused verbatim | themselves |
| `agents/bead-host/*`, `hosts_bead`/`host_session` links, warm-while-live grounding | **Retired** — superseded by the group + turns | — |

---

## Data Model

- **The binding is the group name, not a link.** `gc.continuation_group = <subject-bead-id>` on each
  turn is the entire binding. This is metadata-only, no schema change (beads store metadata as a
  free-form `map[string]string`). v1's `hosts_bead`/`host_session`/`session_lineage` triple is
  **removed** — the reverse-search it needed is subsumed by "list group members."
- **A turn bead** = a child of the subject (`gc bd dep add <turn> <subject> --type=parent-child`)
  carrying `gc.run_target`/`gc.routed_to` + `gc.continuation_group`, plus an optional
  `task_kind=conversation` marker (the structural tell the reaper keys on — see Q1). Its `description`
  is the visit prompt; its `gc.outcome` records ratify/redirect.
- **The subject bead** accumulates the durable record: `description` (the seed), `notes`
  (append-only; where each turn writes its outcome), and its own work metadata. The conversation lives
  in the *union of the subject's notes and its turns* — reconstructable cold, with no provider
  transcript required.
- **Intra-rig for v1.** `bd` and continuation groups are rig-scoped; cross-rig conversations are out
  of scope (unchanged from v1).

---

## Trade-offs and Decisions

- **Turns-are-beads over resume-forever (the core bet).** A per-turn session that dies at each
  boundary spends more spawns than one kept-warm session — but spawns are cheap and *context is the
  scarce thing*. Resume-forever has no principled place to shed context on a months-long epic;
  turns-are-beads sheds at every boundary for free, and makes cold reconstitution a lossless first-
  class path rather than v1's degraded-and-logged fallback. This directly supersedes v1's
  warm-while-live grounding, whose entire purpose was to *avoid* dying.
- **Native role over importing `gc-roles`.** (Resolves Q5.) gc-toolkit imports `gc-roles` nowhere and
  uses `gc.run_target` in zero formulas today; the conversation role is one ~5-line `agent.toml` + one
  prompt, cheaper to author natively (the pattern bead-host itself follows) than to import a whole
  pack and override it. Adopt the *idiom* (`run_target`→`routed_to`, which is core, not gc-roles-
  specific); do not adopt the *pack*. Revisit if a second and third role accumulate.
- **Supersede the binding, keep the board.** (Resolves Q4.) bead-host and v2 answer the same need
  with different continuity primitives; v2's is strictly core-built and sheds the stay-warm burden.
  Since bead-host is capability-not-deployment with no live instances, retiring the binding + grounding
  + `hosts_bead` is near-free. The `gc.attention`/Helm board is orthogonal to the binding — it is the
  *human surface* — so keep it and rewire pick-a-row. Net: **supersede lifecycle, keep+rewire the
  surface.**
- **Dedicated conversation pool over the impl pool.** Routing turns into the impl pool would let a
  waiting-for-operator hold occupy a slot real implementation needs (head-of-line blocking). A small
  dedicated pool (modeled on `agents/proactive`, `max_active_sessions=2`) + the city-wide session cap
  bounds concurrent provider memory — and *is* the natural home for the deferred queue (Q3).
- **Two v1 concerns stay dropped, and are safe to drop.** Single-writer-per-node is moot (each
  subject's group owns its own turns; `gc bd update --claim` is an atomic CAS). "Seat the payer" is
  N=1, one operator; cost shows up as the session cap, not a stakeholder model. (Carried from v1.)

---

## Resolving the Mandated Questions

The bead posed five questions "the spec must resolve." Each is resolved above; collected here for a
reviewer, with the one honest gap flagged.

1. **The hold — what keeps a parked turn from being reaped?** A conversation turn parks `in_progress`
   while it waits for the operator; the witness-patrol orphan-recovery must **skip it structurally**,
   exactly as it already skips grounded bead-hosts. The shipped skip
   (`formulas/mol-witness-patrol.toml:147-171`, regression `assets/scripts/host-bead-skip.test.sh`)
   drops from recovery any bead where `metadata.host_session_name == assignee`. v2 adds a **sibling
   clause** keyed on the conversation shape — `task_kind == "conversation"` (or `gc.run_target ==
   <conversation-role>`) — so a parked turn is recognized as *deliberately held*, not orphaned. The
   filter is fail-safe (it can only decline to orphan, never invent one), so the added clause is
   low-risk. **Resolution: extend the existing structural-skip filter; do not build a new reaper.**

2. **Session legibility — can the role title its session by subject?** ⚠ **Partial — the *command* is
   proven; the *integration* is not.** `gc session rename` **exists and is a shipped pattern**:
   `gc session rename <session> <title>` is a live subcommand, `tools/gc-bead-host.sh:564` calls it on
   the host-resume path, and `template-fragments/canonical-self-rename.template.md` already instructs a
   canonical session to self-title via `gc session rename "$GC_SESSION_ID" "<focus>"`. So the capability
   is not in doubt. What bead-host relied on for *initial* legibility is a different mechanism, though:
   **alias = bead-id** set at `gc session new` (`gc-bead-host.sh` L161) — an operator/tool choosing the
   name at creation. A **pool-spawned** role has no such chosen alias — the reconciler names it
   anonymously — so v2 needs the role to **self-title on claim**, which is genuinely new relative to
   bead-host. **The unproven dependency is therefore the integration, not the command:** that a
   *pool-spawned* session (anonymously named, able to choose its own alias only after it claims) can
   successfully rename itself to the subject on claim. **Resolution:** the role renames its own session
   to the subject bead's id/title on claim, reusing the established `$GC_SESSION_ID` self-rename shape;
   before Phase 1, confirm that shape works for a pool-spawned session specifically. **Fallbacks if it
   does not:** (a) have the reconciler set the spawned session's alias from the routed bead's
   `gc.continuation_group`, or (b) accept anonymous tmux names and rely on the board (which resolves
   subject→group) for legibility. This is the one v2 assumption whose *integration* is unproven; Phase
   1's gate must exercise it explicitly.

3. **Queue vs. live under memory pressure — deferred.** Whether pending turns queue rather than each
   going live is a LATER idea, per the operator; it is a **non-goal** here. Note only that
   turns-are-beads makes it trivial to add later: a queue is just *un-routed* turn beads plus the
   conversation pool's `max_active_sessions` cap — no redesign, no new state. Do not design it now.

4. **Relationship to the existing bead-host — supersede the binding, keep the board.** (Full
   reasoning in [Trade-offs](#trade-offs-and-decisions).) v2 **retires** `agents/bead-host/*`, the
   `hosts_bead`/`host_session` link, and warm-while-live grounding; it **keeps** the `gc.attention`
   Helm board and rewires pick-a-row. Zero live instances → migration is deletion of unused config.

5. **Where the role pack lives — native in gc-toolkit.** Author `agents/conversation/` natively,
   modeled on `run-operator`; adopt the core `run_target`→`routed_to` idiom; do **not** import the
   `gc-roles` pack (a new dependency with its own agents/scope/fallback blast radius for a one-file
   role). Recommend revisiting the import only if the role idiom spreads to several agents.

---

## Risks and Mitigations

- **[Flagged] Self-titling rests on the unproven *pool-session* self-rename integration.** (Q2.) The
  `gc session rename` command itself is proven (bead-host L564; the canonical-self-rename template);
  what is unproven is that a *pool-spawned* session can self-title on claim. *Mitigation:* confirm the
  integration in Phase 0/1; two concrete fallbacks (reconciler-set alias; board-only legibility) exist,
  so the design does not hard-depend on it.
- **Cold reconstitution quality depends on record discipline.** If turns don't write good outcomes to
  the subject, a cold resume reconstitutes from a thin record. *Mitigation:* the role's *Record* step
  is mandatory and gated (Phase 1 asserts a turn writes a subject-bead outcome before it closes); this
  is the same "make the record good" investment the reframe is built to reward.
- **Warm vacuum races.** Two turns filed near-simultaneously could both try to spawn. *Mitigation:*
  `gc.continuation_group` vacuum + `gc bd update --claim` atomic CAS already serialize this — the same
  mechanism that safely vacuumed five sibling steps onto this design session.
- **Reaper false-negative.** If the skip clause is too broad it could shield a genuinely-orphaned
  bead. *Mitigation:* key the clause on the *specific* conversation marker (`task_kind=conversation`),
  and rely on the filter's fail-safe (decline-only) property; the regression test
  `host-bead-skip.test.sh` gets a sibling case.
- **Dolt is a fragile shared SPOF the model leans on.** *Mitigation:* the conversation pool's
  `max_active_sessions` cap bounds concurrent sessions; turns degrade to queued (Q3's later work) if
  connection pressure rises. (Carried from v1.)

---

## Implementation Plan

Sequenced assembly-first; each phase independently shippable and gated. No phase requires a schema
migration.

**Phase 0 — Confirm the one unproven dependency (gates Q2).** The `gc session rename` command already
exists (bead-host L564; the canonical-self-rename template); verify the *integration* — that a
**pool-spawned** session can rename itself to the subject on claim; if it cannot, pick a fallback
(reconciler-set alias or board-only legibility). ~hours, zero new config. **Outcome:** the self-titling
mechanism is chosen before Phase 1 builds on it.

**Phase 1 — The role + the turn (the spine).** `agents/conversation/agent.toml` (`run-operator` shape,
hold-not-close) + `prompt.template.md`; the turn-filing convention; the dedicated conversation pool.
**Gate (on one real subject bead):** (1) file a turn → pool demand spawns a session with no operator
keystroke; (2) the role rebuilds the *subject's* slice (not the turn's) and holds `in_progress`;
(3) on operator input it writes the outcome to the **subject** bead and closes only the **turn**;
(4) a second turn filed while the first session is warm is **vacuumed onto it** (warm continuity);
(5) after the session drains, a third turn spawns a **fresh** session that reconstitutes from the
record (cold continuity) and can answer a pre-seeded question about the subject.

**Phase 2 — The hold survives the reaper (Q1).** Add the conversation-shape clause to
`mol-witness-patrol.toml`'s orphan-recovery skip + a sibling case in `host-bead-skip.test.sh`.
**Gate:** a turn parked `in_progress` past the orphan threshold is **not** recovered; a genuinely
orphaned bead still is.

**Phase 3 — Attention rewire (the surface).** Change Helm pick-a-row to file-or-vacuum a turn; wire
`gc.attention` flag → turn; map `takeaway --release` to stop-routing-and-drain. **Gate
(operator-judged capstone):** from the board, pick a flagged bead → land in its conversation (warm
attach or cold spawn) → it correctly answers a pre-seeded reach-requiring question → operator ratifies
in one move → the turn leaves the board.

**v1 Definition of Done (composite):** Phase 1 spine (automated, 5 assertions) **+** Phase 2 reaper-
skip (automated) **+** Phase 3 end-to-end demo (operator-judged). Done when these pass on one real
subject; no human-time number gates the ship (carried from v1).

**Cross-cutting:** intra-rig only; the record is the durable artifact; the refinery stays the sole
merge gate and impl-bead closer; measurement = intent only, no meter.

---

## Remaining Open Questions

Genuinely open after the resolutions above — best answered by the running system:

1. **Can a pool-spawned session self-title on claim?** `gc session rename` exists and is a shipped
   pattern; the one unproven dependency (Q2) is whether an anonymously-named pool session can rename
   itself to the subject on claim. Phase 0 settles it.
2. **How are the mayor and mechanik engaged once coordination distributes to node-conversations?**
   The operator's standing live question (carried from v1's Open Questions). v2's provisional bet:
   the canonical mayor and `mechanik-thread` stay as root/strategy conversations (both already ship as
   resume-mode threads — `agents/mayor-thread`, `agents/mechanik-thread` — which is *why* the machinery
   is the same); how far the mayor's dispatch role shrinks as subjects run their own turns is a v1.5
   question, not one to pre-specify.
3. **Suspend/queue policy at scale (Q3, deferred).** When many subjects want turns at once, does the
   pool cap simply queue them, and what ranks the queue? The turns-are-beads model supports it with no
   new state; the *policy* is later work.
4. **First-reaction proactivity as turns.** v1's `mol-first-reaction` (a slung mol that advances a
   bead before the operator arrives) maps naturally onto v2 — a "proactive turn" filed by a formula
   rather than by operator/board. Whether the first reaction runs *as* a conversation turn or as a
   separate polecat is the same open question v1 left (its Open Question 4).

---

## Non-goals

Per the bead, explicitly out of scope for this design:

- **No implementation.** Design doc only.
- **No queue mechanism.** (Q3 — captured as deferred, not designed.)
- **No resident proactive loop.** Proactivity, if any, is a *turn filed by a formula*, never an
  always-on loop.

---

## Future directions

*Recorded so they are not lost; explicitly beyond v1 scope.*

- **Contextual re-entry cue (the human's memory, not just the bead's).** Cold reconstitution restores
  the *subject's* record; triggering the *operator's* memory of the conversation is its own future
  design (titles are one cue that has worked). Carried from v1.
- **The turn history as a first-class transcript.** The sequence of turn beads under a subject is
  already a durable, legible conversation spine independent of any provider transcript; a future view
  could render it directly (a "conversation log" from beads), making warm-vs-cold invisible to the
  operator too, not just to the role.
- **Roles beyond the operator conversation.** If the `run_target` idiom proves out, other
  single-clause variants of `run-operator` (a reviewer conversation, a triage conversation) become
  cheap — at which point importing/extending `gc-roles` (Q5's deferred alternative) may earn its keep.
