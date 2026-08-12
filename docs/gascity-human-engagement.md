---
name: Gas City and human engagement
description: Local supplement tracking how Gas City is evolving to support human engagement — the shipping primitives, the live upstream investments, and the trajectory — with the seam gc-toolkit rides at each, and the pack's two-noun vocabulary (subject / visit). Companion to architecture.md's "How agents exist and converse"; every claim carries its verification date.
---

# Gas City and human engagement

**Vocabulary.** The pack's model has two
technical nouns. A **subject** is the durable thing a dialogue is about —
the bead; its id is the continuation-group identity; its notes and visit
history are the dialogue's record, spanning its whole life (an epic may
see hundreds of visits). A **visit** is one bounded sitting of that
dialogue: filed as a child bead, held live by the converse role, outcome recorded to the
subject, closed when the sitting ends; at most one sitting is live per
subject (the continuation-group vacuum serializes pending visits into
it). "Conversation" is deliberately **not** a technical term in this
pack — it reverts to plain speech, which also leaves upstream's extmsg
"conversation" (an external channel thread) unambiguous.

gc-toolkit's conversation model is a bet on Gas City's own momentum: the
runtime is steadily growing the primitives a human conversation needs, and
the pack composes those primitives rather than inventing beside them
([architecture.md](architecture.md), "How agents exist and converse"). That
bet only pays if the pack actually tracks where upstream is going — so this
document is the ledger of Gas City's conversation-relevant direction: what
ships today, what is moving, and the exact seam gc-toolkit rides at each.

## Scope

**Mandate.** The single place gc-toolkit records how Gas City supports —
and is evolving to support — human conversation: the primitives, their
verified status, upstream's own investments in the space, and the boundary
where gc-toolkit's model meets them. When upstream moves, this file is
where the movement lands first, and the pack's machinery re-derives from
it.

**Boundaries.** It records upstream facts and the seams we build on; it
does not design gc-toolkit's conversation system (that is
[architecture.md](architecture.md) and its design specs) and does not
duplicate upstream reference material
([gascity-reference.md](gascity-reference.md) indexes that). Facts here
are dated; an undated claim is a bug.

## The principle

When Gas City ships a primitive that covers something the pack built
bespoke, the pack re-derives its machinery on the primitive and retires
the bespoke part. The conversation model itself is the standing example:
`gc.continuation_group` is a live core primitive that carries the whole
subject-visit binding for free, so the visit/converse spine
(`specs/tk-h9pq5/`) rides it rather than a bespoke per-bead binding.
Expect the same trade wherever upstream covers bespoke ground; that is
what riding an ecosystem means.

## Shipping primitives the conversation model rides

Each entry: the upstream fact, its verification status, and the seam.

- **Continuation groups — live core, the identity of a conversation.**
  The hook-claim path reads `gc.continuation_group` and vacuums open,
  unassigned sibling work onto the claiming session
  (`internal/beadmeta/keys.go`; verified from source 2026-08-06, clone
  `3e629ad`, and exercised live by this pack's own pool claims; live docs
  2026-08-08 confirm — "the hook atomically claims one ready bead and
  preassigns continuation siblings", tutorials/06-beads). *Seam:*
  the subject bead's id **is** the group; visits filed into the group reach
  a warm session automatically, and a cold session reconstitutes from the
  record. No reverse links, no bespoke binding.

- **Routing — `gc.routed_to` is the sole persisted key.** `gc.run_target`
  is compile-time routing intent the router resolves into `gc.routed_to`
  at dispatch (upstream #2779; verified 2026-08-06; live docs 2026-08-08
  confirm both key roles verbatim, formula-spec-v2). The read side is **exact string match**, so
  direct stamps must be rig-qualified; and under a `default_sling_formula`
  a bare sling is a formula attach that stamps nothing — stamp-don't-sling
  or `--no-formula` ([gascity-routing-model.md](gascity-routing-model.md)).
  *Seam:* a visit is ordinary routed work; pool demand spawns the
  conversation session with no operator keystroke.

- **The worker-role contract — upstream now owns the idiom.** The
  `gc-roles` pack ships a shared `gc-role-worker` contract fragment used
  by all ~12 roles (source-verified 2026-08-06, gascity-packs `0b95742`;
  **source-only** — the roles pack is absent from the public docs and the
  registry showcase as of 2026-08-08, so re-verify against the
  gascity-packs source, not the docs site):
  discovery is claim-only via the `gc gc claim` wrapper; **an empty
  continuation group after close is a hard session boundary; a successful
  claim is authoritative even across groups**. Per-role prompt citations
  older than this are stale. The pack also now ships
  `requirements-planner` and `task-decomposer` — planning roles adjacent
  to decomposition work. *Seam:* a conversation role is `gc-role-worker`'s
  contract with the execute/close clause replaced by hold-for-operator;
  the delta is expressed against that fragment, not a bespoke prompt. The
  planner roles are a standing adoption question wherever the pack plans
  or decomposes (see the tripwire below).

- **Human waits — the `type=human` gate, with drivers.** Upstream's live
  human-wait primitive is the `type=human` **gate** (`gc bd gate create`):
  excluded from Ready, with core notify/renudge orders that mail the
  escalation recipient (source-verified 2026-08-06; **source-only** — the
  public docs do not cover the human-gate primitive, hold labels, or the
  renudge orders as of 2026-08-08). By contrast
  `gc.routed_to=human` **parks** — no core machinery claims it, the nudge
  order fails silently on it (same verification). The sanctioned hold
  taxonomy is `hold:mayor` / `hold:external` only; a bare `human` hold
  label has no sanctioned upstream meaning. *Seam:* a human question is a bead whose
  canonical form is a visit — the visit is the
  dialogue-carrying refinement of the human gate, never a competitor
  to it; an open human gate is a legitimate named wait. The raw
  `routed_to=human` lane is a trap, not a feature.

- **Questions gate work natively — blocking dependencies.**
  `bd dep <blocker> --blocks <blocked>` creates a blocking edge, and
  blocked work is invisible to work queries (verified 2026-08-06; live
  docs 2026-08-08 confirm both, tutorials/06-beads — "blocked work is
  invisible to work queries"). `bd dep remove` exists in source
  (golden-tested; not covered in the public docs). *Seam:* a
  decision-needed visit can block its dependents with core edges — "a
  human approval is just a check nothing non-human can yet satisfy"
  composes directly, no bespoke gate machinery.

## Upstream's own conversation investment: `extmsg`

Gas City's active investment in human conversation is **`extmsg`** — and
it is provider-generic, not a chat-platform integration: a conversation
is a `(provider, account_id, conversation_id)` tuple, any client
registers via `POST /v0/extmsg/clients` and speaks inbound-POST +
SSE-reply, and upstream ships a `provider: "llm-client"` for direct LLM
clients with no chat platform at all (verified 2026-08-08,
guides/connected-clients). Slack and Discord are adapter packs over that
same API. Bindings attach a conversation to a **session or a configured
agent** — agent bindings survive restarts by cold-waking a session — and
`gc extmsg handoff` rebinds a live conversation to another agent
("pure transport"; the routing judgment lives in the agent's prompt). It is further along than a casual read suggests (live docs
2026-08-08): CLI verbs `gc extmsg bind` / `handoff` / `unbind`; an API
plane with client registration, `POST /v0/extmsg/inbound`, and a
long-lived SSE reply stream per `(provider, account_id,
conversation_id)`; and — the telling detail — **the first inbound turn
implicitly creates the conversation binding**, durable and
reconnect-safe via sequence-number replay (guides/connected-clients).
Slack and Discord ship as first-party packs. The outbound path is
already exercised by the oversight-rig pack's rollup delivery
(`specs/tk-3s5uo/`).

This is a **different plane** from gc-toolkit's beads-as-turns — extmsg
is channel-shaped and session-bound; ours is operator-internal and
record-durable — and the two are complementary, not competing. The
boundary, on the record: **when an external channel arrives, the
subject bead is the natural binding anchor — the two models meet at the
subject bead.** A Slack thread about a piece of work should bind where
that work's conversation already lives, not beside it.

`gc.attention` has zero upstream meaning (verified 2026-08-06), and the
pack does not use it either — there is no flag-for-attention concept.
"An agent believes a human should look at this" has exactly one form —
file a visit on the subject — so the board derives what is
pressing from real state (open visits, human gates, stranded work) rather
than from self-assertions with no lifecycle.

## How questions reach a human today (source-verified 2026-08-08)

Upstream surfaces "a human is needed" at two tiers with sharply different
maturity — the split matters more than any single fact here:

- **Live-session questions (ephemeral) get first-class treatment.** A
  runtime-detected prompt becomes a **pending interaction**
  (`request_id`, `kind`, optional prompt/options), emitted on the
  per-session SSE stream, aggregated city-wide
  (`GET /v0/city/{city}/pending`, concurrent probe with partial-failure
  reporting), answerable via a respond endpoint — and the **dashboard
  ranks it**: a home-view attention queue with closed alert kinds
  (`pending-decision`, `run-needs-operator`, `run-thrashing`,
  `operator-mail`), a single top-ranked "One Mark," and an agents-nav
  "Needs you (N)" section with reasons (awaiting-input / errored /
  rate-limited / stalled) and mapped actions (respond / reset / nudge).
  Upstream is actively building a needs-me surface for *sessions*.
- **Durable human-gate beads (the graph tier) are reachable but have no
  surface identity.** Core's built-in gate watcher skips human gates,
  and `await_type` never crosses the supervisor API — no dashboard or
  API object represents a gate. What core's bundled bootstrap pack ships
  instead is **mail + renudge**: an order that mails on human-gate
  creation (addressee: assignee → `gc.deferred_assignee` →
  `$GC_ESCALATION_RECIPIENT`, default `"human"`) and a sweep that
  re-nudges stale open gates hourly. Plus `gc bd gate list` and an
  indirect projection: a run blocked on a gate shows as "Blocked,
  awaiting operator," and the gate's mail surfaces as an
  `operator-mail` alert. Upstream's own notes call gates "beads with
  metadata" — the primitive is theirs; the *presentation* is not built.
- **Formula-level questions are prose.** The build-factory schemas make
  artifact `status: questions|blocked` machine-readable and require an
  Open Questions section, but individual questions carry no needs-human
  flag; the worker contract forbids asking after a claim; and
  `interaction_mode=interactive` names no mechanism for the ask to
  travel. A question that must survive its session has exactly one
  sound home today: a gate bead in the graph.

*Seam:* gc-toolkit's conversation model is the missing top of this
stack, not a competitor to it — a gate filed as a **visit** gives the
durable tier what the session tier already has (framing, a
conversation, an owner), and the board gives gates the first-class
ranked identity `await_type` lacks. Ride the notify/renudge orders and
the alert model rather than duplicating them.

## How a held sitting ends (source-verified 2026-08-11; attachment rung reconciled 2026-08-12)

A hold has no timeout *in the pack's doctrine* — but the runtime under it
does end sittings, and every surface that said otherwise was wrong. The
mechanism, verified against the gascity source (rig checkout `7cff88fdc`,
2026-08-11) after an operator lost two threads mid-attention (`tk-bzm86`):

- **`wisp_ttl` is not this, and never was.** `[daemon] wisp_ttl` is how
  long a **closed** wisp — an ephemeral v1 formula-run bead — survives
  before the GC deletes it (`internal/config/config.go`, `WispTTL`;
  enabled only when `wisp_gc_interval` and `wisp_ttl` are both non-zero).
  It reaps *records*, not sessions, and never touches a live held visit.
  Reading the city's `wisp_ttl = "8h"` as the thing that collects
  conversations is a coincidence of two unrelated 8h values.
- **The clock that ends a sitting is the agent's own `idle_timeout`** —
  pack-owned config (`agents/converse/agent.toml`), not core policy.
- **"Idle" means the terminal produced no output.** The reconciler's
  `checkIdle` reads the provider's last activity, which for tmux is the
  most recent per-window `#{window_activity}` (`Tmux.rawSessionActivity`,
  `internal/runtime/tmux/tmux.go`) — pane output and `send-keys`. **An
  operator reading a held thread generates neither**, so activity alone
  cannot tell sustained attention from abandonment. For a **detached**
  reader — watching through the dashboard or scrollback, not connected to
  the pane — that is the whole story, and reading a thread for 8h is what
  gets it collected. (An *attached* terminal is now observed separately and
  defers the reap — see *The core seam, now closed*, below.)
- **Holding work defers the stop, but only briefly.**
  `DecideIdleTimeout` (`internal/session/lifecycle_timers.go`) walks
  blocker → pending interaction → attachment → assigned work → stop, and a
  held visit is assigned work, so the stop defers on the assigned-work rung
  (the attachment rung above it — landed since; see below — is a separate,
  uncapped defer). The reconciler caps the assigned-work streak:
  `assigned_work_defer_limit` (default 3 —
  `defaultAssignedWorkDeferLimit`, `cmd/gc/assigned_work_defer_tracker.go`)
  consecutive same-anchor defers, then `DecideAssignedWorkExhausted`
  forces the stop under its own `assigned_work_exhausted` reason. At
  `patrol_interval = "30s"` the defer buys ~90 seconds, not immortality.
- **The kill erases the evidence.** The stop path calls
  `ClearScrollback` (`cmd/gc/session_reconciler.go`), wiping the pane's
  history, and the converse template's `wake_mode = "fresh"` makes the
  respawn a clean provider session. Contrast `wake_mode = "resume"`,
  which replays the provider transcript across gaps far longer than the
  timeout (measured at ~15h, `specs/tk-oml75/spike-report.md` §1). So a
  reaped converse thread is **unrecoverable, not merely hidden**, and no
  remedy may assume the operator can reopen it.

*Seam:* **nothing pack-owned runs at kill time**, so a warn-before-reap
is not available to us; the pack's only lever is to have already written
the trace. Hence the converse contract stamps the subject's takeaway when
the hold *begins* (not only at close) — a reap then leaves a dated record
of what the sitting was waiting for — and every deliberate close ends
with a sign-off block naming the outcome and the subject to look at next.
Longevity is deliberately not the remedy: raising `idle_timeout` only
widens the window in which a dead thread looks alive.

*The core seam, now closed (landed 2026-08-12):* attachment is observable —
`runtime.Provider.IsAttached` — and the idle ladder now consults it.
gascity merged `gc-rjtk1` (PR #126, commit `c8bff331d`; confirmed in
gascity `origin/main` 809a97f47): the reconciler supplies
`TimerFacts.Attached` from `sp.IsAttached(name)`
(`cmd/gc/session_reconciler.go`), and `DecideIdleTimeout`
(`internal/session/lifecycle_timers.go`) gained an **attachment rung**
between pending interaction and assigned work —
`if f.Attached { return deferDecision("attached", "deferred_attached") }`.
So "an operator is attached to this pane" now defers the reap, and
read-attention on a connected pane finally counts. The rung is
deliberately narrow, so the mechanism above still holds:

- **A defer, not an exemption.** It is re-evaluated every tick and the stop
  resumes the moment the terminal detaches — a forgotten attached pane is
  *not* immortal. Unlike the pending arm it cancels no drain and skips no
  wake pass; it is a plain defer.
- **The *attached* case only.** Idle is still measured from output
  activity, so a **detached** reader (dashboard or scrollback) is still
  indistinguishable from abandonment and still gets collected — attachment
  is a separate signal, not a fix to activity measurement. The pack's
  trace-at-hold-begin lever above therefore still earns its keep.
- **Aligns two subsystems.** `ComputeAwakeSet` already re-wakes an attached
  session via its "attached" wake override, so the old behavior killed a
  watched pane only to bounce it straight back awake — the same
  idle-kill/wake treadmill the assigned-work rung fixed (`ga-3ox7rk`).
- **Idle-timeout only.** `DecideMaxSessionAge` (a health restart, e.g.
  credential expiry) still fires regardless of who is attached.

Design record: `specs/tk-bzm86/design-doc.md`; the cross-rig filing
`gc-rjtk1` is now resolved upstream.

## Watch items — moving now, re-verify before building on them

- **`gc.session_affinity`** — still advisory (no routing path reads it),
  but drain has begun *writing* it, and a `gc.drain_continuation_group`
  key exists (2026-08-06). If a read side lands, warm-continuity
  assumptions should be re-derived on it.
- **The roles pack's growth** — every new upstream role is a standing
  question against a hand-authored one here. Recorded tripwire: when
  upstream ships a role covering something the pack hand-authors,
  re-argue adoption for that role specifically (`tk-h9pq5` Q5).
- **Dashboard surface** — upstream ships `gc dashboard` (Vite SPA over
  the supervisor API); the pack's sanctioned augmentation seam is the
  `proxy_process` `/svc/` route (`services/helm/` already uses it). Any
  conversation surface work should land behind that seam, not in new
  bespoke plumbing.

## What upstream does not ship (the pack's actual seam)

Revised 2026-08-08 after the build-factory trial and operator probing —
this is the genuinely native ground, and it is deliberately small. A
definition first, because everything below uses it:

> **A visit** is one bounded sitting of a subject's dialogue, stored as
> a bead: a small child of the subject whose body is the sitting's
> prompt ("ratify this plan", "review posted — decision needed"), whose
> metadata routes it to the converse pool and names the subject's
> continuation group, whose `gc.outcome` records what the sitting
> decided, and which closes when the sitting ends (the subject never
> closes this way) — out loud, with a sign-off naming the outcome and
> the subject to look at next, because the ending is the one part of a
> sitting the operator cannot reconstruct from the record ("How a held
> sitting ends", above). The sequence of visits under a subject is the
> dialogue's durable spine — board-legible, cold-reconstructable, no
> provider transcript required.

- **The hold on the gate.** Upstream has the *wait* (human gates,
  `blocks` edges — work durably stops). It has no role that services
  the wait: every upstream role's contract is claim → execute → close;
  none claims a bead and deliberately sits `in_progress` for a human,
  having rebuilt the subject's context and framed the choice, then
  records the answer to the subject and closes only the visit. Gate and
  hold are two halves of one mechanism: the gate makes the work wait;
  the hold (the converse role, on a visit) makes the wait worth arriving
  at instead of a parked bead you cold-start yourself.
- **The board's judgment — as a lens, never a dependency.** Ranking
  what deserves the operator's glance, derived from real graph state
  (open visits, human gates, stranded work), with visual consistency.
  **Constraint (operator, 2026-08-08): everything works without the
  board** — work moves entirely on graph state; the board renders it
  and must never be a mechanism anything depends on.
- **Ratification and record-residency for filed trees.** Upstream's
  build factory *does* decompose brief → requirements → plan → tree of
  beads (corrected after the trial; an earlier revision claimed
  otherwise). What it lacks is the gate — no edge can wait on a human
  before the tree lands — and the record-resident plan (files in
  `plans/`, not rev-pinned on the brief bead, so re-planning re-files
  instead of diffing). The native ground is the gate on the tree, not
  the tree-making.

Everything else in the conversation model is assembly of the primitives
above — which is the point.

## Refresh procedure

Claims here date from a source-level verification of 2026-08-06 (gascity
clone `3e629ad`; gascity-packs `0b95742`), cross-checked against the live
public docs on 2026-08-08 (site index: https://docs.gascity.com/llms.txt;
the site publishes no changelog, so recency must be inferred or diffed
against a docs-source clone). Re-verify before building on any
load-bearing claim: upstream moves fast, and the public docs lag the
source — claims marked **source-only** above are real but invisible to a
docs-site check; "not in the docs" is not "false". Ownership follows
[gascity-reference.md](gascity-reference.md)'s refresh procedure and bar;
the doc-keeper drift audit covers this file like any other central doc.
When a watch item fires or a claim goes stale, update the fact *and* the
seam it carries, and date the change.
