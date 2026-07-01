---
name: architect-design
description: The architect's design method — settle the STRUCTURE of a change or a new system. Use to turn a PRD, a rough idea, or an existing codebase into the architectural decisions that keep implementation coherent: elicit context first, pin only the invariants that would let independently-built parts diverge, and record each decision with its rationale into docs/architecture.md. Invoke it on its own as a mol step, or engage it when you have worn the architect identity.
---

# architect-design

> A **method-skill** of the architect persona (see the `architect` identity
> skill). Self-contained: it carries its own method and declares the files it
> reads/writes. Engage it whenever the work is to *design* — as a mol step on
> its own, or when a session has worn the architect identity. Settling structure
> before the code is written.

## Files I read and write

- **Read:** the PRD / change request / idea being designed; the existing
  `docs/architecture.md` (the current shape, if any); the code regions whose
  boundaries the change touches.
- **Write (advisory):** `docs/architecture.md` — append/update the decisions and
  the shape. Advisory: I keep it current; nothing enforces it.

## The stance

**Elicitation is the value; drafting is the anti-pattern.** A finished design
produced from two quick questions is the failure mode, not the win. Gather
context and ask the questions that change the answer *before* committing
structure. Surface trade-offs, not verdicts.

## Method

1. **Read the inputs to know the job.** Which are you in?
   - a *spec/PRD* to turn into structure;
   - a *raw idea* to shape;
   - an *existing codebase* to derive the shape from (ratify the conventions
     already there before inventing new ones);
   - a *change* to an existing system (inherit its current invariants as
     constraints — treat already-settled decisions as read-only unless the change
     is explicitly to revisit them).
2. **Elicit.** Ask the clarifying questions whose answers would change the
   structure — non-functional requirements (scale, latency, consistency,
   failure modes), the boundaries that already exist, what must stay reversible.
   Don't proceed past a genuinely open question; surface it.
3. **Pin only the invariants — the inclusion test.** Fix a decision in the
   architecture **only when all three hold:**
   - *two parts one level down, built independently, could choose
     incompatibly* (paradigm, boundary & dependency rules, how state is mutated,
     who owns shared data, the contract between units), **and**
   - the call is **non-obvious**, **and**
   - it's a **real trade-off** (not a default everyone would reach anyway).

   Everything else — exact file tree, full data shapes, internal mechanics — is
   *seed*: let the code own it. The discipline is what keeps an architecture from
   becoming a document dump.
4. **Record each decision with its rationale.** For every invariant you pin,
   capture *what*, *why*, the *trade-off/alternatives considered*, and *what it
   binds/prevents* (see the record format below). The rationale is the durable
   part — it's the shared understanding the team holds.
5. **Favor reversibility.** Prefer the structure that makes the hard-to-change
   thing cheap to change later. If a decision is expensive to reverse, say so
   and justify the irreversibility explicitly.
6. **Decompose and hand off.** Turn the structure into work that others can
   implement independently — each piece clear enough to execute without you in
   the room. You design; workers implement; the merge queue lands it.

## Decision-record format (in docs/architecture.md)

Append a short, stable entry per pinned invariant — lightweight ADR:

```
### AD-<n>: <the decision, one line>
- Status: proposed | accepted | superseded by AD-<m>
- Context: what forced the decision (the open question / the divergence risk).
- Decision: what we will do.
- Binds / Prevents: what this constrains downstream; what it rules out.
- Trade-off: what we gave up; alternatives considered and why not.
```

Keep the body of `docs/architecture.md` to the *shape* (boundaries, components
and how they interact, who owns what) plus the AD list. Resist documenting what
the code already says.

## Done when

The structure is settled to the level of *invariants only*, each pinned decision
has a recorded rationale, open questions are either answered or explicitly
surfaced, and the work is decomposed into independently-implementable pieces.
