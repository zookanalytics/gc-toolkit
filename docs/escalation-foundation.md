# Escalation Foundation — Working Doc

Stable surface for the AI→human communication pack design. Each item carries
a status. This is the conversation's record; chat is the negotiation about it.

Status legend: `[LOCKED]` agreed · `[DIRECTIONAL]` concept locked, wording open · `[REFINED]` updated, awaiting confirm · `[OPEN]` under discussion · `[PARKED]` deferred · `[UNSEEN]` not yet discussed

Structure: **Tenets** are root principles (durable, why we operate the way we do).
**Practices** are operational hows derived from tenets. Tenets stay small; practices accumulate.

---

## Goals

### G1. Fewer escalations over time, each one higher-value `[LOCKED]`
The system escalates less, not more, as it accumulates patterns. What does
escalate is correspondingly heavier and demands richer engagement.

### G2. Approval is the goal; opinionated engagement is the path `[DIRECTIONAL]`
*Concept locked; wording open to sharpening.*

Approval / agreement is the terminal state of an interaction, not its
typical immediate reply. The journey there is opinionated engagement: the
human reacts to the AI's position, picks among options, refines, or pushes
back. That engagement is where judgment actually lives.

Two legitimate shapes:
- **Direct approval** — the human accepts without engagement. Signals the
  consult was notify- or inform-shaped. Still valuable.
- **Engage then approve** — the human engages substantively, converges to
  alignment. The heart of consults that need judgment. The engagement
  itself produces the decision.

### G3. Decisions live in durable artifacts, not chat `[LOCKED]`
A long conversational path can reach a decision. The artifact captures the
decision; the journey isn't rehashed and side roads don't distract on
re-read.

---

## Tenets

Three root principles. The set stays small.

### T1. Attention is the only scarce resource `[LOCKED]`
Agent tokens, compute, retries, and self-critique are free. Human attention
is the budget. Every action prices its claim against it.

### T2. The human owns the clock `[DIRECTIONAL]`
The AI is ready when attention turns and quiet when it doesn't — never
demanding interruption. Wait time deepens the work; use it, but ready-now
beats perfect-later.

### T3. The pack learns from observation `[LOCKED]`
Patterns from accepts, rejects, and engagements inform the next gates and
the next packaging. Observation precedes prescription. Continuous, not a
destination — which is why this is a tenet, not a goal. It is the engine
that makes G1 (fewer escalations over time) actually drive.

### How the tenets compose `[DIRECTIONAL]`
Each tenet takes a proactive stance that prevents one kind of failure.
T1 budgets attention — prevents waste. T2 waits on the human — prevents
interruption. T3 learns from each cycle — prevents stagnation.

---

## Practices

Operational hows. Each derives from one or more tenets. The set grows as the
pack learns; tenets do not.

### P1. Surface only what only the human can answer `[LOCKED]`
Derived from T1. Pre-surface gates filter consults: self-critique first,
confidence filter, role-specific evolving rules. Different agents
accumulate different gates.

### P2. Express an opinion alongside options `[REFINED]`
Derived from T1, supports G2. The AI gives options AND its opinion. Not
just one recommendation; not just a buffet. Express a position. This is
what makes opinionated engagement traversable.

### P3. Recognition over reading `[LOCKED]`
Derived from T1. When judgment is required, hand the human ready
alternatives — three working artifacts, picked by sight — not a paragraph
describing them. Built artifacts > described tradeoffs.

### P4. Last line is the lede `[LOCKED]`
Derived from T1. Bottom-anchored consumption inverts top-of-the-fold. The
most important content of any escalation is its terminal line.

*Note: anchored to current chat UI. If the medium shifts (canvas,
persistent surfaces), the durable principle is "optimize for the medium's
natural read order." For now, that's bottom-anchored.*

### P5. Use the highest-bandwidth, highest-density form `[REFINED]`
Derived from T1. The principle is *information density*, not visual
demonstration. Pick the form that conveys the most signal per unit of
human attention. Diffs, tables, and artifacts are examples of density
wins, not the rule.

### P6. Context triggers reload mental model faster than summaries `[REFINED]`
Derived from T1. Cues are open-ended — codenames, file paths, personas,
faces, images, mockups, future UI primitives. The principle is durable;
the example set evolves. Don't paraphrase what the human already encoded.

---

## Process notes

- Conversation moves item-by-item, smallest viable bite per turn.
- This doc is the source of truth between turns; chat is negotiation about
  it.
- Tenets must be medium-agnostic and durable. Examples may evolve; the
  principle should outlast them.

---

## Parked

- Specific skill list — derives from foundation, not before
- Callout vocabulary — emerges from observation
- Metaphor for AI's posture (surgeon/scrub-nurse rejected; underlying idea
  of "instrument-ready" still open)
- Mechanism for T3: how does the pack actually accumulate patterns?
