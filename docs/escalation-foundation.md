# Escalation Foundation — Working Doc

Stable surface for the AI→human communication pack design. Each item carries
a status. This is the conversation's record; chat is the negotiation about it.

Status legend: `[LOCKED]` agreed · `[REFINED]` updated, awaiting confirm · `[OPEN]` under discussion · `[PARKED]` deferred · `[UNSEEN]` not yet discussed

---

## Goals

### G1. Fewer escalations over time, each one higher-value `[LOCKED]`
The system escalates less, not more, as it accumulates patterns. What does
escalate is correspondingly heavier and demands richer engagement.

### G2. Approval is the goal; opinionated engagement is the path `[LOCKED]`
Original draft: "default reply is accept (one signal)." Wrong-shaped — a
one-tap accept default contradicts G1.

Refined: approval / agreement is the terminal state of an interaction, not
its typical immediate reply. The journey there is opinionated engagement:
the human reacts to the AI's position, picks among options, refines, or
pushes back. That engagement is where judgment actually lives.

Two legitimate shapes follow:
- **Direct approval** — the human accepts without engagement. Signals the
  consult was notify- or inform-shaped. Still valuable; not the failure
  mode it appeared to be in the original draft.
- **Engage then approve** — the human engages substantively, converges to
  alignment. This is the heart of consults that need judgment. The
  engagement itself produces the decision.

T2 (opinion alongside options) is what makes the path traversable.

### G3. Decisions live in durable artifacts, not chat `[LOCKED]`
A long conversational path can reach a decision. The artifact captures the
decision; the journey isn't rehashed and side roads don't distract on
re-read.

---

## Tenets

### T1. Attention is the only scarce resource `[LOCKED]`
Agent tokens, compute, retries, and self-critique are free. Human attention
is the budget. Every action prices its claim against it.

### T2. The AI expresses an opinion alongside options `[REFINED]`
Original: "Recommend, don't enumerate."

Refined: the AI gives options AND its opinion. Not just one recommendation;
not just a buffet. Express a position.

[Open: reconciles with G2's reformulation. Refine together.]

### T3. Surface only what only the human can answer `[DERIVED]`
Agreed in spirit, but follows from T1. Weaker as a standalone tenet.
Candidate: collapse into T1 or drop.

### T4. Recognition over reading `[LOCKED]`
When judgment is required, hand the human ready alternatives — three
working artifacts, picked by sight — not a paragraph describing them.
Built artifacts > described tradeoffs. A more concrete how than T3, both
deriving from T1.

### T5. Last line is the lede `[LOCKED]`
Bottom-anchored consumption inverts top-of-the-fold. The most important
content of any escalation is its terminal line.

[Note: anchored to current chat UI. If the medium shifts (canvas,
persistent surfaces), the durable principle is "optimize for the medium's
natural read order." For now, that's bottom-anchored.]

### T6. Use the highest-bandwidth, highest-density form `[REFINED]`
Original: "Show, don't tell."

Refined: the principle is *information density*, not visual demonstration.
Pick the form that conveys the most signal per unit of human attention.
Diffs, tables, and artifacts are examples of density wins, not the rule.

### T7. Context triggers reload mental model faster than summaries `[REFINED]`
Original list of cues (codename, branch, commit-pinned line) was too
narrow.

Refined: cues are open-ended — codenames, file paths, personas, faces,
images, mockups, future UI primitives. The tenet is durable; the example
set evolves. Don't paraphrase what the human already encoded.

### T8. Engagement is human-paced `[UNSEEN]`
Consults wait until the human is ready. Urgency belongs to the human's
readiness, not the AI's queue.

### T9. The pack learns from observation `[LOCKED]`
Patterns from accepts, rejects, and engagements inform the next gates and
the next packaging. Observation precedes prescription. Continuous, not a
destination — which is why this is a tenet, not a goal. It is the engine
that makes G1 (fewer escalations over time) actually drive.

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
- Mechanism for G4 / T9: how does the pack actually accumulate patterns?
