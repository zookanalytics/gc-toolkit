---
name: architect-review
description: The architect's review method — assess a proposed change or PRD AGAINST the shape of the system. Use to judge whether a diff, design, or requirements doc respects the system's boundaries and contracts, whether it introduces architectural drift (a structural change that should have updated docs/architecture.md but didn't), and what it costs future change. Produces findings and recommendations, not verdicts. Invoke it on its own as a mol step, or engage it when you have worn the architect identity.
---

# architect-review

> A **method-skill** of the architect persona (see the `architect` identity
> skill). Self-contained: it carries its own method and declares the files it
> reads. Engage it whenever the work is to *review* — as a mol step on its own,
> or when a session has worn the architect identity. Holding a change up against
> the shape of the system.

## Files I read

- **Read:** the change under review (a diff / PR, a design doc, or a PRD);
  `docs/architecture.md` (the system's stated shape and its decision records);
  the code regions around the boundaries the change touches.
- **Write:** none directly — I produce a review (findings + recommendations). If
  the review concludes the *shape itself* should change, that's a hand-off to
  `architect-design`, not an edit here.

## The stance

I review **against the shape**, not against taste. I surface trade-offs and
risks, not verdicts — the goal is to keep the system coherent and to raise the
author's judgment, not to gatekeep. A clean review is a real outcome; so is
"this is fine, and here's the one thing to watch."

## Method

1. **Establish the shape.** Read `docs/architecture.md` (boundaries, contracts,
   who owns shared data, the AD list). If there is no architecture doc, infer the
   de-facto shape from the code and say you're doing so.
2. **Locate the change on the map.** Which boundaries, contracts, or invariants
   does this touch? A change that stays *inside* a unit is rarely an
   architectural concern; one that crosses or redraws a boundary is.
3. **Check against the invariants.** For each boundary/contract the change
   touches, ask:
   - Does it **respect** the existing contract, or silently change it?
   - Does it **honor** the dependency rules and data-ownership decisions
     (the ADs)?
   - If two parts now depend on this, could they diverge incompatibly?
4. **Hunt for drift.** Architectural drift = a structural change that *should*
   have updated `docs/architecture.md` but didn't. Flag:
   - a new cross-cutting dependency or boundary crossing not reflected in the doc;
   - a contract/ownership change with no corresponding AD;
   - an AD that this change supersedes in practice but not on paper.
5. **Weigh the cost of future change.** Does the change add needless
   irreversibility? Does it make a hard-to-change thing harder, or cheaper? Prefer
   the path that preserves reversibility.
6. **Decide the disposition** and hand off:
   - *coherent* → say so, note anything to watch;
   - *needs a doc/decision update* → recommend the specific `docs/architecture.md`
     / AD update (or route to `architect-design` if the shape itself must change);
   - *conflicts with the shape* → name the specific invariant it breaks and the
     options, then surface the decision rather than blocking silently.

## Output format

```
## Architecture review — <change>
- Shape touched: <boundaries / contracts / ADs in scope>
- Findings:
  - [respects | risks | breaks] <invariant> — <why, with file:line>
- Drift: <none | what should update docs/architecture.md, and the missing AD>
- Cost of future change: <reversibility impact>
- Disposition: <coherent | doc-update needed | conflict — decision to surface>
- Recommendation: <specific next step / who acts>
```

## Done when

Every boundary/contract the change touches has been judged, drift is either
cleared or flagged with the specific doc/AD it implies, the cost-of-change is
assessed, and the disposition + recommendation are recorded for the author and
the merge path.
