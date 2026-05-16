# Foundation

gc-toolkit is a pack for Gas City, the multi-agent runtime, that gets work done by relentlessly focusing on high-bandwidth human interaction.

AI changed the cost of work. Agent iteration, parallel exploration, and self-critique are cheap. Human attention is scarce, context-bound, and not restartable on demand. gc-toolkit turns that asymmetry into operating discipline: agents do the cheap work before they interrupt, the surface makes judgment easier rather than transferring work back to the operator, and every lesson compounds into the pack so attention is never spent twice.

## Core Beliefs

**Human attention is the budget.** Attention is genuinely scarce and not restartable on demand.

**Agents earn every interaction.** Make it count: do the cheap work, plan ahead, and frame the choice. Every interruption justifies the attention it claims.

**Agents improve.** Lessons come from doing; the system carries them across restarts so the next conversation starts smarter.

**Agents make their edges visible.** Looking smart and being smart are different. Legible agents show which.

**Decisions have a home.** Documentation is the system's memory. What's written survives; what isn't, doesn't.

## Boundaries

gc-toolkit will not fork or replace Gas City or Gastown. It augments them with pack-local opinions, patches, agents, skills, and conventions.

gc-toolkit will not add process for its own sake. Review legs are partners, not walls; consults are for judgment, not ritual; metrics must trigger corrective action or they are noise.

gc-toolkit will not treat cheap restart as root cause. Re-rolling an agent until a plausible diff appears launders defects into reviewer fatigue. The right answer is to make the failure legible and improve the pack.

## Who It Is For

gc-toolkit codifies a set of principles for working with AI-era agents, currently realized on Gas City but applicable to any multi-agent engine. It's for operators who want agent labor to feel abundant without making human judgment feel cheap. It fits teams and solo operators who value durable records, explicit handoffs, and agents that can act autonomously while making their edges visible. Good gc-toolkit work leaves the next contributor with fewer questions, better artifacts, and a clearer sense of what the system believes.

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
