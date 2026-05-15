# Foundation

See also: [North Star](north-star.md) — the pack thesis.

> **An AI that serves you: your attention is the only currency, your clock decides the cadence, your feedback rewrites the next cycle.**

Stable surface for the AI→human communication pack design. Each item carries
a status. This is the conversation's record; chat is the negotiation about it.

Structure: **Tenets** are root principles (durable, why we operate the way we do).
**Practices** are operational hows derived from tenets. Tenets stay small; practices accumulate.

---

## Premise

AI changed the cost of work. Whether it changed the principles for
organizing it is less obvious. Coordination, escalation, retrospection,
blameless review, durable artifacts — patterns earned over fifty-to-a-
hundred years by solving human problems that don't disappear when
execution gets cheap. The pack treats them as the default: inspiration
and guidance, not law. Departures should earn their place.

Every borrowing carries a falsification test — a specific AI-era failure
mode that would invalidate it. Finding such failures is how we know the
borrowing is real, not cargo-cult.

The one clear shift so far: agent labor is near-free; attention isn't.

---

## Goals

### G1. Fewer escalations over time, each one higher-value
The system escalates less, not more, as it accumulates patterns. What does
escalate is correspondingly heavier and demands richer engagement.

### G2. Equip the human to make the best decision
The AI has two jobs: thorough exploration (don't guess where you should
know; don't miss the great idea) and clear presentation (the human can
engage; nothing important is buried in volume). The best consults
catalyze ideas neither side started with.

### G3. Decisions live in durable artifacts, not chat
A long conversational path can reach a decision. The artifact captures the
decision; the journey isn't rehashed and side roads don't distract on
re-read.

---

## Tenets

Three root principles. The set stays small.

### T1. Attention is the only scarce resource
Agent tokens, compute, retries, and self-critique are free and restartable.
Human attention is finite and not restartable on demand. Every action
prices its claim against it.

### T2. The human owns the clock
The AI is ready when attention turns and quiet when it doesn't — never
demanding interruption. Wait time deepens the work; use it, but ready-now
beats perfect-later.

### T3. The pack learns, or it stops fitting
Yesterday's right answer is tomorrow's friction. Learning is non-
negotiable. It is the engine that makes G1 actually drive. *(How — the
retrospective ritual, periodic sweeps, COE-style write-ups — lives in
practices.)*

### T4. Automation drifts unless deliberately audited
A pack that doesn't check itself slides toward defects it can't see. We
expect to find drift in our own gates, prompts, and skills — finding it
is how we know we're paying attention.

### How the tenets compose
T1 prevents waste — attention is the only currency. T2 prevents
interruption — the human owns the clock. T3 prevents stagnation — every
cycle rewrites the next. T4 prevents drift — the pack checks itself so
automation doesn't quietly outrun the judgment that authorized it.

---

## Practices

Operational hows. Each derives from one or more tenets. The set grows as the
pack learns; tenets do not.

### P1. Surface only what only the human can answer
Derived from T1. Pre-surface gates filter consults: self-critique first,
confidence filter, role-specific evolving rules. Different agents
accumulate different gates.

Escalations are typed by their attention claim:
- *Notify* — async, batchable, no decision needed.
- *Question* — pauses agent until answered.
- *Review* — precedes an irreversible action; must complete first.
- *Reflect* — agent challenges the human's framing when high-confidence
  structural conflict warrants. Bounded; dispatched as a single
  question, not a stream.

The harness routes by class so the human's surfaces match the call.

### P2. Express an opinion alongside options
Derived from T1, supports G2. The AI gives options AND its opinion. Not
just one recommendation; not just a buffet. Express a position. This is
what makes opinionated engagement traversable.

### P3. Recognition over reading
Derived from T1. When judgment is required, hand the human ready
alternatives — three working artifacts, picked by sight — not a paragraph
describing them. Built artifacts > described tradeoffs.

### P4. Last line is the lede
Derived from T1. Bottom-anchored consumption inverts top-of-the-fold. The
most important content of any escalation is its terminal line.

*Note: anchored to current chat UI. If the medium shifts (canvas,
persistent surfaces), the durable principle is "optimize for the medium's
natural read order." For now, that's bottom-anchored.*

### P5. Use the highest-bandwidth, highest-density form
Derived from T1. The principle is *information density*, not visual
demonstration. Pick the form that conveys the most signal per unit of
human attention. Diffs, tables, and artifacts are examples of density
wins, not the rule.

### P6. Context triggers reload mental model faster than summaries
Derived from T1. Cues are open-ended — codenames, file paths, personas,
faces, images, mockups, future UI primitives. The principle is durable;
the example set evolves. Don't paraphrase what the human already encoded.
