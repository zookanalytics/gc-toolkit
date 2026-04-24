# Consult-Bead Surfacing Channel — Design

**Status:** design, not approved. Do not implement from this doc alone.
**Bead:** [tk-uac](#references) — picks up from tk-a4t (architect) and tk-6s5
(strategic direction).
**Audience:** overseer, mechanik, architect; future consult-producing
specialists.

## 1. Problem

Consult beads are how a specialist agent and the human overseer hold a
conversation. The architect defined the bead shape — `architect-consult`
label, `gc.consult_type` metadata, `[type] …` title prefix, replies as bead
notes (`agents/architect/prompt.template.md` on
`origin/polecat/tk-a4t-architect-skeleton`). That protocol answers *what a
consult looks like*.

It does not answer *how the overseer finds out one exists*. Without a
surfacing channel, a consult filed at 09:05 sits unread; the architect's
Partner hat fails silently; the roadmap's "branded context channels"
primitive is violated by a general-text fallback; and the "consult" brand
decays into another bead-queue the overseer has to remember to scan.

This doc picks the **channel**. It does not redefine the bead shape. It is
rig-agnostic, merge-strategy-agnostic, and public-pack-safe.

## 2. Constraints (given, not re-litigated here)

- **Distinct from mayor.** Overseer has explicitly rejected overloading
  mayor. Mayor is mid-conversation when the consult arrives; cramming a
  second register onto the same surface makes both worse. (Input from
  tk-uac description; echoed in `docs/roadmap.md` §Decisions §Open.)
- **Honors the architect protocol.** Channel is a reader of
  `architect-consult` / `gc.consult_type` / `[type] …`, not a redefiner.
- **Rig-agnostic.** City-level machinery. The architect runs per-rig; the
  consult channel runs across rigs.
- **Public-pack.** No private rig names. No shared webhooks in the first
  cut.
- **Design-only.** Implementation is out of scope for this bead; a
  follow-up bead will carry the build.

## 3. Design axes

Options differ along four axes. Naming them upfront lets the comparison
stay honest.

| Axis | Values |
| --- | --- |
| **Aggregation site** | rig-local queue / city-level index / external |
| **Delivery shape** | push-on-event / cadenced digest / on-demand pull / hybrid |
| **Reply path** | overseer writes `bd update --notes` directly / typed reply through an agent / mail thread / external app |
| **Persistence** | stateless (queries on demand) / stateful (an agent holds the index) |

Option A is stateful + city-index + cadenced-plus-on-demand + agent-mediated
reply. Option B is stateless + city-index + cadenced-digest + direct-notes.
Option C is stateful but shares state with mayor. Option D is external
delivery on top of A or B.

## 4. Options

### Option A — Dedicated city agent ("concierge")

A new city-scoped agent, `agents/concierge/`, whose only job is to present
and route consults.

**Mechanism.** On wake, concierge runs the consult query
(`bd list --label architect-consult --status open,in_progress
--metadata-field gc.awaiting=human`), ranks entries by age and
`gc.consult_type`, and produces a digest mail to the overseer with bead
links and one-line summaries. Runs on `idle_timeout = "2h"`, wakes on
`fresh` mode; can be nudged on demand (`gc nudge concierge
"what's open?"`). When the overseer replies (by mail or by talking to
concierge directly), concierge writes the reply back as `bd update <id>
--notes "…"` on the originating bead and flips `gc.awaiting=specialist`.
The specialist's own Active hat pulls from there.

The `gc.awaiting` metadata is the state machine: `human` → concierge
surfaces; `specialist` → concierge hides; `resolved` → bead closes, consult
is archived.

**What the overseer's day looks like.** One branded sender ("concierge")
delivers one mail in the morning containing *all* open consults, ranked.
Overseer opens the mail, scans titles, replies to concierge in plain
prose — "on the auth ADR, go with option 2; drift on rate-limits, file
the correction." Concierge threads each answer to its bead. Overseer
never uses `bd` directly for a consult.

**Failure modes.**

- Concierge becomes a second mayor (scope creep). Mitigation: hard scope
  in the prompt — *only* consults, no coordination. Reject dispatch
  requests with a redirect to mayor.
- Concierge itself becomes silent (no consults → no mail → overseer
  forgets it exists). Mitigation: even an empty-digest morning mail
  ("no open consults — X closed in last 24h") is a brand reinforcement;
  the cost is low.
- Reply misrouting: overseer replies conversationally referencing one
  consult by number, concierge attaches to the wrong bead. Mitigation:
  each digest line carries the explicit bead ID; concierge refuses to
  attach a reply if the target is ambiguous and asks one clarifying
  question.
- Agent overhead: another persistent context, another wake script,
  another surface to prompt-engineer.

**What else this forces into the design.**

- New `agents/concierge/` directory in the pack (agent.toml + prompt
  template). City-scoped, `fresh` wake mode, long idle timeout.
- A small formula, `mol-consult-sweep` (or an inlined query in the
  prompt), that runs the consult query and writes the digest.
- Metadata convention: `gc.awaiting = human | specialist | resolved` on
  every consult bead. The architect prompt needs one paragraph added to
  set `gc.awaiting=human` on consult creation and flip to
  `gc.awaiting=specialist` after a reply.
- Mail-reply routing: concierge reads its own inbox, parses per-line
  answers, writes bead notes. This is the non-trivial ergonomic bet.
- A `gc nudge concierge` ritual — already supported by the `nudge`
  command.

### Option B — Mail-channel convention + consult digest formula

No new agent. A periodic formula, `mol-consult-digest`, runs on the same
machinery as `mol-digest-generate` (periodic, dog-pool dispatched) and
mails the overseer a ranked list of open consults at a configured
interval.

**Mechanism.** Same query as Option A, same metadata, same digest
structure. The dog polecat runs the formula, composes the mail with a
`[consults]` subject prefix, and sends to the overseer alias. Overseer
replies by mail; there is a helper script (`gc consult reply <bead-id>
"<note>"`) that the overseer invokes directly, or the overseer opens the
bead and runs `bd update --notes`.

Alternatively (looser variant): no formula — just a subject-prefix
convention (`[consult] …`) on mail sent by specialists when they file a
consult, and a `gc mail inbox --label consult` convenience filter.

**What the overseer's day looks like.** Mail arrives from the dog pool
("sender: dog-1234 on behalf of mayor" or a dedicated alias). Overseer
scans. To reply, they either run a helper script or edit the bead's
notes directly. No agent persona to talk to — just a bundled mail.

**Failure modes.**

- No brand. The overseer gets another digest from another dog polecat;
  nothing about this surface says "this is the consult surface." Brand
  failure is exactly the thing the roadmap primitive warns against.
- Reply ergonomics. Writing a bead note is not a natural reply action
  for the overseer; the friction compounds per consult. The helper
  script fixes some of this but still requires overseer habit change.
- Silent failure when empty. Unlike a persistent agent, a digest formula
  that has nothing to report either (a) sends a no-op mail daily (noise)
  or (b) sends nothing (brand invisibility). Neither is great.
- Stale consults have no patrol. Option A's Active hat watches for
  consults that have sat in `gc.awaiting=human` too long. Option B has no
  one doing that.

**What else this forces into the design.**

- Formula: `mol-consult-digest.toml`, patterned on `mol-digest-generate`.
- Configuration in `city.toml` under `[[formulas.periodic]]`.
- Optional helper command: `gc consult reply` (gastown CLI change, not
  pack-only — a bigger ask). Or: documented convention that overseer
  types `bd update <id> --notes "..."` themselves.
- Same `gc.awaiting` metadata on consults.

### Option C — Mayor overlay

Mayor's prompt grows a "consult inbox" first-class section: on wake,
mayor runs the consult query before the dispatch query and surfaces any
`gc.awaiting=human` consults at the top of its response. Same reply
mechanism as Option B (bead notes), but threaded through mayor as the
surface.

**What the overseer's day looks like.** One surface (mayor), two
registers: "here's your dispatch state, and here are three open
consults." Mayor gains context to know when to batch vs. interrupt.

**Failure modes.**

- This is the option the overseer already rejected. The failure mode was
  felt in practice: mid-conversation context collision. "Feels like I'm
  mid-conversation when I want to send it something else."
- Mayor's dispatch cadence is not consult cadence. A consult may wait
  two hours until the next dispatch turn; a dispatch decision may wait
  because mayor is presenting consults.
- Brand overload: mayor's brand is coordination. Tacking consults on
  erodes both brands instead of strengthening either.

**What else this forces into the design.** Mayor prompt rewrite;
additional fragment in `template-fragments/`; still needs the
`gc.awaiting` metadata convention.

### Option D — Remote surface (Slack / email / webhook)

An aggregator (Option A's concierge or Option B's formula) pushes a
digest to an external channel.

**What the overseer's day looks like.** Slack notification → click →
reply in Slack → webhook turns it into a bead note.

**Failure modes.**

- Credential management lives outside the public pack; putting it in the
  pack by default leaks private configuration.
- Hard to test without a real webhook endpoint.
- Reply routing across systems (Slack → bead notes) is the hard part of
  Option A multiplied by a network boundary.

**Verdict.** Not a first-cut candidate. The design should remain
*compatible* — meaning the aggregation step produces a structured
payload (subject + body + bead links) that a future webhook can forward
verbatim — but no external delivery target ships in the first version.

## 5. Recommendation

**Adopt Option A: a dedicated city agent, `concierge`.** Keep Option B's
digest formula alive as the *engine* the agent runs, but the agent is
the surface.

### Why

1. **Branded surface.** A named agent is the cheapest way to earn the
   "branded context channel" primitive. The overseer knows who they are
   talking to and what the register is. A dog polecat running a digest
   cannot do that — it is, by construction, anonymous infrastructure.
2. **Three-hat fit.** The channel role is genuinely three-hatted:
   *Partner* (answers "what's open?" on demand), *Active* (notices
   stale `awaiting=human` consults and nudges), *Library* (knows the
   consult index across rigs). A formula cannot hold hats two or three
   between invocations. The same argument gc-toolkit already made for
   the architect applies here, at smaller scale.
3. **Reply ergonomics.** Overseer replying to concierge in prose and
   having it threaded to the right bead is materially better than
   `bd update --notes`. This is the single biggest overseer-day
   improvement.
4. **Mayor stays pure.** The explicit constraint — distinct from
   mayor — is honored by construction. Mayor and concierge do not share
   context or conversation state.
5. **Idle-cheap.** City-scoped, `idle_timeout = "2h"`, `wake_mode =
   "fresh"` — if there are no consults, there is no running concierge.
   The overhead worry from "another persistent agent" is smaller than it
   looks.

### Why not Option B first, with A as upgrade path

Defensible, and the second-best plan. Rejected because the brand is the
load-bearing piece, not the mechanism. Shipping B first trains the
overseer to a nameless digest; switching to A later then requires
*retraining* the overseer onto a new surface. A dedicated agent from day
one sets the right expectations cheaply.

That said — **if concierge implementation stalls** (mail-reply routing
turns out to be ugly, for example), ship Option B as a stopgap. It is
not a dead-end; it is a strictly simpler version of the same aggregation
query.

### Why not C or D

C was already rejected by the overseer and the design analysis confirms
why. D is a later layer on top of whichever aggregator ships; do not
build it first.

## 6. Scope of the first implementation

If Option A is approved, the follow-up build is bounded:

- `agents/concierge/agent.toml` and `agents/concierge/prompt.template.md`
  — city-scoped, fresh-wake, 2h idle.
- Prompt defines: consult query, digest format, on-demand nudge
  response, mail-reply → bead-note routing, `gc.awaiting` state machine.
- Small `mol-consult-sweep.toml` formula if the prompt's inline logic
  is not enough; otherwise, no new formula in round one.
- One-line addition to the architect prompt: set
  `gc.awaiting=human` on consult create, `gc.awaiting=specialist`
  after a reply.
- `city.toml` example wiring (copy-pasteable into a consuming city).
- Documentation in `docs/` — a short README at `agents/concierge/` and
  a note in `docs/roadmap.md`.

Explicit non-goals for the first implementation:

- No remote delivery (Slack/webhook) — the digest payload stays mail.
- No multi-human addressing — one overseer alias in the first version.
- No cross-rig patrol beyond the consult query — concierge does not
  know anything about mayor's dispatch state.

## 7. Open questions for the overseer

These need an explicit call; the design doc should not guess.

1. **Agent name.** `concierge` is the working name. Alternatives
   considered: `herald` (announces but does not route), `steward` (too
   generic), `aide` (too subordinate). Landing on a name before the
   build matters because the brand is the product.
2. **Cadence default.** Morning-only (one mail/day), twice (morning +
   afternoon), or on-event (push each new consult immediately, with a
   daily recap)? Cadence drives perceived noise. Default proposal:
   one morning digest + on-demand nudges, no per-event push.
3. **Empty digest behavior.** Should concierge send a "nothing open"
   mail on cadence (brand reinforcement) or stay silent (less noise)?
   Default proposal: empty digest on cadence, at least weekly.
4. **Reply routing ambiguity policy.** When the overseer's reply could
   apply to more than one open consult, does concierge (a) pick the
   newest, (b) apply to all of them, or (c) refuse and ask? Default
   proposal: (c) refuse and ask, once; if still ambiguous, fall back
   to filing a meta-consult.
5. **`gc.awaiting` initial value.** The proposal assumes the specialist
   (architect) sets it on consult creation. Alternative: concierge
   infers it from the absence of a specialist reply. The former is
   cleaner but requires updating every specialist prompt. The latter
   is more decoupled but less precise. Default proposal: specialist
   sets it; architect is the only consult-producer today, so the cost
   is one prompt edit.
6. **Should mayor know about concierge?** Mayor's role is coordination;
   concierge's is consult surfacing. A question filed to mayor that
   should have been a consult needs a redirect path. Default proposal:
   mayor's prompt gets a one-paragraph "when to redirect to concierge"
   section, but concierge does not appear in mayor's work queue.
7. **Is this a city-level agent or a gc-toolkit-pack agent?** Strictly,
   mechanik is already in the pack; concierge logically belongs there
   too. But city agents are declared in `city.toml`, not in pack files.
   The pack ships the prompt template and agent.toml; the consuming
   city wires it in. Confirming that path is correct before build.

## 8. Follow-up bead

Filed as **tk-uac.1** — "Implement consult surfacing channel (concierge
agent)." Contains scope (agent skeleton + architect prompt edit + example
`city.toml` entry), a pre-build decision checklist pulled from §7, and
mechanik-review-before-dispatch. The architect should author an ADR
recording the decision once the concierge is operational.

tk-uac.1 is scoped to Option A. If a different option is approved,
close tk-uac.1 and file a fresh implementation bead for the chosen
option — the scope differs enough that editing is the wrong move.

## References

- `tk-uac` — this design bead.
- `tk-uac.1` — implementation follow-up (Option A: concierge agent).
- `tk-a4t` — architect agent skeleton (merged). Source of consult
  protocol.
- `tk-6s5` — strategic direction; the primitives this design obeys.
- `agents/architect/prompt.template.md` on
  `origin/polecat/tk-a4t-architect-skeleton` — authoritative definition
  of the consult bead shape.
- `agents/mechanik/prompt.template.md` on main — peer agent; precedent
  for city-scoped specialist pattern.
- `docs/roadmap.md` — "Consult bead surfacing channel" open question
  and "branded context channels" primitive.
- `formulas/mol-digest-generate.toml` in gastown — prior art for
  periodic mail-digest mechanics referenced in Option B.
