# Consult-Bead Surfacing Channel — Design

**Status:** approved design. Implementation bead to be filed by mechanik
against this revision.
**Beads:** [tk-uac](#references) (first-pass design, closed),
[tk-89y](#references) (this revision, conversational-concierge model).
**Audience:** overseer, mechanik, architect; future consult-producing
specialists.

## 1. Problem

Consult beads are how a specialist agent and the human overseer hold a
conversation. The architect first defined the bead shape; this design
generalizes it so any specialist can file. The shape is: `consult`
label, `gc.consult_type` metadata, `[type] …` title prefix, back-and-forth
captured as bead notes, filed as a dependency of the bead whose work
the consult is blocking.

That protocol answers *what a consult looks like*. It does not answer
*how the overseer finds out one exists* or *how the conversation
actually happens*. Without a surfacing channel, a consult filed at 09:05
sits unread; the specialist's Partner hat fails silently; the roadmap's
"branded context channels" primitive is violated by a general-text
fallback; and the "consult" brand decays into another bead-queue the
overseer has to remember to scan.

This doc picks the **channel** and the **conversation model**. It does
not redefine the bead shape (beyond generalizing the label). It is
rig-agnostic, merge-strategy-agnostic, and public-pack-safe.

## 2. Constraints (given, not re-litigated here)

- **Distinct from mayor.** Overseer has explicitly rejected overloading
  mayor. Mayor is mid-conversation when the consult arrives; cramming a
  second register onto the same surface makes both worse.
- **Consults are parent-bead dependencies, not standalone.** A consult
  is always filed as a dependency of the bead whose work it is
  blocking. Resolution (closing the consult) unblocks the parent via
  the bead dependency graph. No separate "awaiting" state is needed or
  wanted.
- **Any specialist can file.** Not architect-only. The label is
  `consult`; the specialist's identity travels in the owner/author
  fields and is used for context loading.
- **Rig-agnostic.** City-level machinery. Specialists can run per-rig;
  the consult channel runs across rigs (with an allowed per-rig variant
  where it earns its keep).
- **Public-pack.** No private rig names. No shared webhooks in the
  first cut.
- **Design-only.** Implementation is out of scope for this bead; a
  follow-up bead filed by mechanik will carry the build.

## 3. Design axes

Options differ along four axes. Naming them upfront lets the comparison
stay honest.

| Axis | Values |
| --- | --- |
| **Aggregation site** | rig-local queue / city-level index / external |
| **Delivery shape** | push-on-event / cadenced digest / on-demand pull / real-time conversation / hybrid |
| **Reply path** | overseer writes `bd update --notes` directly / typed reply through an agent / mail thread / conversational turn with an agent / external app |
| **Persistence** | stateless (queries on demand) / stateful (an agent holds the index) |

The approved design lands at: *city-level index · push-on-create +
on-demand conversational pull · conversational turn with concierge ·
stateful*. Options A–D below explore the space; §5 describes the
approved design in detail.

## 4. Options considered

### Option A — Dedicated city agent ("concierge")

A new city-scoped agent, `agents/concierge/`, whose only job is to
surface consults and host the conversation with the overseer that
resolves them.

**Mechanism (as explored).** Originally proposed as a morning-digest
sender that mails the overseer a ranked list of open consults and
threads prose replies back to the right beads. During review the
mechanism was reshaped into a conversational model: push a short
notification on consult creation, then hold a real-time conversation
with the overseer on engagement — loading full bead context, ranking
what's open by type and age, and writing decisions back as bead notes.
§5 carries the full mechanism.

**What the overseer's day looks like (conversational model).** A
notification arrives when a new consult is filed — the overseer is
never waiting on cadence. When the overseer engages ("what's open?",
"let's do UX reviews", or names a bead ID), concierge pulls up the
relevant consults, reads their full context, and has a real conversation
— prose in, prose back — in the same way they'd talk to any specialist.
Concierge threads the decision to the bead and closes it, which
automatically unblocks the parent work.

**Failure modes.**

- Concierge becomes a second mayor (scope creep). Mitigation: hard
  scope in the prompt — *only* consults, no coordination. Reject
  dispatch requests with a redirect to mayor.
- Concierge itself becomes silent (no consults → no conversation →
  overseer forgets it exists). Mitigation: push-on-create keeps the
  brand alive; optional weekly resurface for still-open consults keeps
  stale ones from going invisible.
- Reply misrouting: overseer's answer could apply to more than one open
  consult. Mitigation: every digest line and every conversation turn
  names the target consult; concierge refuses and asks once when
  ambiguous.
- Agent overhead: another persistent context, another wake script,
  another surface to prompt-engineer. Partly offset by city-scoping
  and long idle timeout — if there are no consults, concierge is not
  running.

**What else this forces into the design.**

- New `agents/concierge/` directory in the pack (agent.toml + prompt
  template). City-scoped, `fresh` wake mode, long idle timeout.
- A small formula or inlined query that runs the consult query and
  produces the digest / conversation context.
- Each specialist prompt gains the "push to concierge on consult
  creation" instruction (for architect today; others as they land).
- `gc nudge concierge` ritual — already supported by the `nudge`
  command.

### Option B — Mail-channel convention + consult digest formula

No new agent. A periodic formula, `mol-consult-digest`, runs on the
same machinery as `mol-digest-generate` (periodic, dog-pool dispatched)
and mails the overseer a ranked list of open consults at a configured
interval.

**Mechanism.** Same query as Option A, same digest structure. The dog
polecat runs the formula, composes the mail with a `[consults]` subject
prefix, and sends to the overseer alias. Overseer replies by mail; a
helper script (`gc consult reply <bead-id> "<note>"`) threads the reply,
or the overseer opens the bead and runs `bd update --notes` directly.

**What the overseer's day looks like.** Mail arrives from the dog pool.
Overseer scans. To reply, they run a helper script or edit the bead's
notes. No agent persona to talk to — just a bundled mail.

**Failure modes.**

- No brand. Another digest from another dog polecat; nothing about
  this surface says "this is the consult surface." Brand failure is
  exactly the thing the roadmap primitive warns against.
- Reply ergonomics. Writing a bead note is not a natural reply action;
  the friction compounds per consult.
- Silent failure when empty. A digest formula that has nothing to
  report either sends no-op mail daily (noise) or sends nothing (brand
  invisibility).
- No conversational surface. A digest is monologue; a real consult
  frequently needs a back-and-forth.
- Stale consults have no patrol. A persistent agent (Option A) can
  notice consults that have sat too long; a digest formula cannot.

### Option C — Mayor overlay

Mayor's prompt grows a "consult inbox" first-class section: on wake,
mayor runs the consult query before the dispatch query and surfaces
open consults at the top of its response.

**What the overseer's day looks like.** One surface (mayor), two
registers: "here's your dispatch state, and here are three open
consults." Mayor gains context to know when to batch vs. interrupt.

**Failure modes.**

- This is the option the overseer already rejected. The failure mode
  was felt in practice: mid-conversation context collision. "Feels
  like I'm mid-conversation when I want to send it something else."
- Mayor's dispatch cadence is not consult cadence.
- Brand overload: mayor's brand is coordination. Tacking consults on
  erodes both brands instead of strengthening either.

### Option D — Remote surface (Slack / email / webhook)

An aggregator (Option A's concierge or Option B's formula) pushes a
digest or notification to an external channel.

**Failure modes.**

- Credential management lives outside the public pack.
- Hard to test without a real webhook endpoint.
- Reply routing across systems (Slack → bead notes) is the hard part
  of Option A multiplied by a network boundary.

**Verdict.** Not a first-cut candidate. The approved design stays
compatible — concierge's notification payload is structured enough
that a future webhook forwarder is a downstream layer — but no
external delivery target ships in the first version.

## 5. Approved design

**Option A, with the mechanism reshaped into a conversational model.**
Concierge is a dedicated city agent whose job is to notify on consult
creation and hold a real-time conversation with the overseer that
resolves consults and writes decisions back to the bead.

### 5.1 Concierge as conversational partner

Concierge is not a digest sender. It is a conversational partner.

- **Push on create.** When a new consult is filed, concierge pushes a
  short notification (mail or nudge) to the overseer. The overseer is
  never waiting on cadence to discover a consult exists.
- **Pull on engagement.** When the overseer engages — "what's open?",
  "let's do UX reviews", a specific bead ID — concierge pulls up the
  relevant consults, ranks them by type and age, reads each bead's
  full context (description, notes, linked artifacts, parent-bead
  context), and begins a conversation.
- **Converse in prose.** The conversation is the interface. Overseer
  speaks in prose; concierge responds in prose, grounded in the loaded
  bead context. Back-and-forth until a decision lands.
- **Write back and close.** When the overseer's decision is clear,
  concierge writes it to the bead as a note and closes the consult.
  Because the consult is a dependency of the parent bead, closing
  unblocks the parent automatically.

The overseer's experience is: "a new consult just landed. I can see
what it is when I want to. When I'm ready, I tell concierge; we talk it
through; it records the outcome." No bead CLI required for the common
path.

### 5.2 Consults as parent-bead dependencies

A consult is never a floating bead. It is always filed as a dependency
(directly or transitively) of the bead whose work it blocks.

- **Resolution unblocks.** Closing the consult propagates through the
  bead dependency graph. The parent bead's assigned work resumes.
- **No `gc.awaiting` state machine.** A consult is "open for the human"
  when it is open and "resolved" when it is closed. The specialist's
  filing, the concierge's conversation, and the final decision all
  operate on bead state — no parallel metadata flags.
- **Parent context travels.** Concierge can walk the dependency edge
  upward to understand *why* the consult matters, and carry that
  context into the conversation.

### 5.3 Bead as conversation record

Back-and-forth on the bead is allowed and expected — the same way a
polecat bead captures its own progress as it works. The bead holds the
conversation record plus the final decision.

- **Live state lives in the session.** The concierge session (loaded
  context, current conversation turn, pending questions) is ephemeral.
  When the session ends, the bead is the durable artifact.
- **Notes are the transcript.** Each meaningful turn — a posed option,
  a clarification, a decision — lands as a bead note. A future
  concierge (or any reader) can reconstruct the conversation from the
  bead alone.
- **Closing note carries the decision.** The final note on a consult
  states the resolution explicitly so downstream readers do not have
  to infer it from the transcript.

The v1 design carries conversations through bead notes + concierge's
in-context recall. The session-per-consult direction (see §5.11) will
make live conversation even more natural in a future revision; the v1
does not depend on it.

### 5.4 Sub-bead nesting for mid-conversation side-quests

When a consult cannot resolve without deeper investigation — reading
existing code shape, reviewing a historical decision, running a quick
prototype — a **sub-bead** is filed. This is the *standard* shape for
mid-conversation side-quests, not an exception.

Two modes:

- **Blocking sub-bead.** The conversation pauses until the sub-bead
  returns an answer. Example: "I can't pick between options A and B
  until the architect reviews the existing ADR on retry behavior."
  The consult depends on the sub-bead; the conversation resumes once
  the sub-bead closes with its answer.
- **Parallel sub-bead.** The conversation continues while the sub-bead
  runs in the background. Example: "Kick off a benchmark on these two
  approaches; keep discussing the design while we wait for numbers."
  The sub-bead is an independent unit of work whose result feeds back
  into the open conversation when ready.

Concierge presents this choice explicitly when a side-quest comes up:
"I can either file this as blocking (we pause here until it comes back)
or parallel (I'll keep talking while it runs) — which do you want?"
The overseer picks; concierge files appropriately.

The architect's "sub-beads for side-quests" convention is the prior
art; this design formalizes it as the standard mid-conversation shape.

### 5.5 Context bar at filing

Specialists file consults with enough context that the overseer (and
concierge) can seek any remaining context from the bead alone. A
consult bead is not a one-liner. The filing bar is part of the
protocol.

At minimum, a filed consult carries:

- **Why this needs a decision.** The blocker or crossroads the
  specialist has hit. What work stalls without an answer.
- **Options on the table.** What the specialist has considered, with
  the trade-offs for each. At least two options when a binary choice
  is being posed.
- **Links to artifacts.** Branches, diffs, prior beads, roadmap
  entries, ADRs, docs, anything the overseer might want to open.
- **Prior analysis.** Any research the specialist has already run —
  so the overseer doesn't duplicate it in the conversation.

A consult that does not carry this context should be rejected or
augmented before it reaches concierge's notification path. The
specialist is responsible for the bar; concierge does not rewrite
filings but can kick them back.

### 5.6 Label and metadata

- **Label:** `consult`. Not `architect-consult`. Any specialist can
  file.
- **Consult type:** `gc.consult_type` metadata carries the type. The
  current candidate taxonomy is {review, decision, drift, promotion,
  ingest, research}; see §7 — worth a short pass to confirm (or
  revise) before build.
- **Title prefix:** `[type] …`, consistent with the original architect
  convention.
- **Dependency:** always filed as a dependency of the blocking parent
  bead. No standalone consults.
- **Routing:** concierge's query watches for open beads with label
  `consult`, regardless of owner.

### 5.7 Mayor ↔ concierge bidirectional awareness

Mayor and concierge do not share work queues — their registers are
distinct (coordination vs. consult surfacing). But each knows the other
exists and redirects when mis-addressed.

- **Mayor's prompt gains one paragraph.** If asked "what's pending my
  feedback?" or "what consults are open?", ping or engage concierge.
  Do not answer from mayor's own queue.
- **Concierge's prompt gains the symmetric paragraph.** If asked about
  dispatch state, worker counts, or coordination, redirect to mayor.

This keeps each agent's brand clean without isolating them — the
overseer gets redirected gracefully rather than bouncing off a silent
agent.

### 5.8 Cadence

- **Push on create.** New consult → immediate notification. This is
  the primary signal.
- **No daily empty digest.** If nothing is open, concierge is silent.
  "Nothing to report" mails train the overseer to ignore the sender.
- **Optional periodic resurface.** Weekly-ish reminder of stale open
  consults is acceptable to keep them visible. This is an option, not
  a default — cities can enable it where the human's engagement
  cadence makes it useful.
- **On-demand pull.** "What's open?" and specific bead IDs are always
  answerable — concierge responds to nudges regardless of push state.

### 5.9 Deployment

City-level agent is primary. Every city that adopts gc-toolkit's
specialist stack runs one concierge across the rigs in that city.

A **per-rig concierge variant** is allowed where a rig's consult
volume or sensitivity justifies it — follows the mayor precedent. Some
cities/rigs will want it; others won't. The prompt template is written
to support both deployments with minimal divergence.

Whether a per-rig concierge shares state with the city concierge or
operates independently is open (see §7). The first implementation
ships city-only.

### 5.10 Reply ambiguity

When the overseer's reply could apply to more than one open consult,
concierge refuses and asks once.

- Every conversation turn and every digest line names the target
  consult by ID. This makes ambiguity rare in practice.
- If the overseer's reply is still ambiguous, concierge asks one
  clarifying question ("which one — tk-abc or tk-def?") rather than
  guessing. No second clarification — if the second round is still
  ambiguous, concierge files a meta-consult and backs off.

Design goal: make ambiguity so rare by careful presentation that the
refusal path is almost never exercised.

### 5.11 Future primitive: session-per-consult

A feasibility study (see tk-bek in [References](#references)) is
running in parallel with this revision. It explores whether a future
iteration should spawn a dedicated session per conversation —
effectively making each consult a short-lived polecat with the filing
specialist's context loaded — so the overseer is talking to "the
specialist who filed this" rather than to concierge carrying a summary.

This v1 design **does not depend on that primitive.** The v1 concierge
holds conversations in its own persistent context. If the feasibility
study recommends building session-per-consult, it becomes a later
upgrade layer on top of the v1 machinery.

## 6. Scope of the first implementation

mechanik will file the implementation bead against this design. The
build is bounded:

- **`agents/concierge/agent.toml` and `agents/concierge/prompt.template.md`**
  — city-scoped, fresh-wake, long idle timeout.
- **Prompt defines**: the consult query (label-based, not
  metadata-state-based), push-on-create notification, engagement-driven
  context loading, conversation guidelines, bead-note writing, sub-bead
  nesting (blocking vs. parallel), filing-bar rejection,
  ambiguity-refusal protocol, mayor-redirection paragraph.
- **Architect prompt edit**: replace any `gc.awaiting`-era instructions
  with the "consult = parent-bead dependency" convention and the "push
  notification to concierge on create" action.
- **`city.toml` example wiring** — copy-pasteable into a consuming
  city.
- **Documentation** — short README at `agents/concierge/`, plus the
  already-applied entry in `docs/roadmap.md`.

Explicit non-goals for the first implementation:

- **No remote delivery** (Slack, webhook). Notification payloads stay
  on the pack's existing mail/nudge channels. A future webhook
  forwarder is a layer on top.
- **No multi-human addressing.** One overseer alias in the first
  version.
- **No session-per-consult spawning.** Tracked by tk-bek as a future
  primitive; v1 concierge holds conversations in its own context.
- **No cross-rig patrol beyond the consult query.** Concierge knows
  nothing about mayor's dispatch state.

## 7. Residual open questions

These need an explicit call during (or before) implementation.

1. **Consult-type taxonomy.** Current candidates: {review, decision,
   drift, promotion, ingest, research}. Worth a short pass before
   build to confirm the list or revise it — the set should cover the
   common shapes without so many types that specialists guess wrong.
2. **Per-rig vs. city-level state sharing.** When a rig adopts a
   per-rig concierge, does it share the consult index with the city
   concierge or operate independently? Decide when per-rig adoption
   is first proposed; first implementation is city-only.
3. **Agent name.** `concierge` is the working name and the name used
   throughout this doc. Confirm (or replace) before build — the brand
   is the product.

Questions from the first-pass design that the approved model has
settled (and so no longer appear here): the `gc.awaiting` state-machine
initial value, cadence defaults, empty-digest behavior, reply-routing
ambiguity policy, and whether mayor knows about concierge. Each is
answered explicitly in §5.

## 8. Follow-up bead

The original tk-uac.1 placeholder assumed the digest-model scope.
Since the approved design reshapes the mechanism, **mechanik will file
a fresh implementation bead** against this revision rather than editing
tk-uac.1 in place. Nudging mechanik on the close of tk-89y is part of
the handoff.

The fresh implementation bead carries:

- Scope from §6.
- Pre-build decision checklist from §7.
- Architect prompt edit as a companion change.
- Any ADR the architect wants to record once concierge is operational.

## References

- `tk-uac` — first-pass design bead (closed).
- `tk-89y` — this revision, conversational-concierge model.
- `tk-bek` — feasibility study: session-per-consult conversation
  spawning (running in parallel; informs future upgrade path).
- `tk-a4t` — architect agent skeleton (merged). Source of the original
  consult protocol.
- `tk-6s5` — strategic direction; the primitives this design obeys.
- `agents/architect/prompt.template.md` on
  `origin/polecat/tk-a4t-architect-skeleton` — authoritative definition
  of the consult bead shape (pre-generalization).
- `agents/mechanik/prompt.template.md` on main — peer agent; precedent
  for city-scoped specialist pattern.
- `docs/roadmap.md` — "Consult bead surfacing channel" entry and
  "branded context channels" primitive.
- `formulas/mol-digest-generate.toml` in gastown — prior art for
  periodic mail-digest mechanics referenced in Option B.
