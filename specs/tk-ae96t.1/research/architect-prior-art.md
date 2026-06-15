---
name: Architect prior-art — index + distillation
description: Provenance-stamped index of the prior-art behind the gc-toolkit architect persona (BMAD-METHOD "Winston"; Roo Code Architect mode; wshobson/agents backend-architect + ship-mate/architect; Martin Fowler "Who Needs an Architect?") and the cross-cutting distillation of what makes a strong architect — identity stance, what it owns, core methods — that the authored persona is built from. Keeps the design auditable from the repo alone.
---

# Architect prior-art — index + distillation

This is the **provenance-stamped index** behind the first gc-toolkit persona, the
**architect** (epic `tk-ae96t`, operator decision Path A, 2026-06-14). The bead's
STEP 1 surveyed strong architect prior art from live sources; the full write-ups
live alongside this file and are linked below, so the patterns folded into the
authored persona stay auditable from the repo alone. The persona itself —
`skills/architect`, `skills/architect-design`, `skills/architect-review`, and the
`agents/architect` standing form — is **built from the distillation at the bottom
of this file.**

This survey is deliberately *architect-specific*, complementary to the
*persona-system* surveys under [`specs/tk-oe8o0/research/`](../../tk-oe8o0/research/prior-art.md)
(which surveyed how frameworks structure roles in general). Those answered "what
shape is a persona"; these answer "what makes a strong *architect*."

## Surveys

### 1. BMAD-METHOD Architect ("Winston") — the closest prior art
**Full survey:** [`survey-bmad-architect.md`](survey-bmad-architect.md)

The current skills-based Winston (`customize.toml` + `SKILL.md`) and the classic
V4 persona-block (`role`/`style`/`identity`/`focus`/`core_principles` + commands +
task/template dependencies); the "architecture spine" invariants-first method;
mandatory elicitation; auditable `AD-n` decisions.

- `github.com/bmad-code-org/BMAD-METHOD` (main, v6.8.0; and the `V4` branch)

### 2. Architect roles — Roo Code, wshobson/agents, Martin Fowler
**Full survey:** [`survey-architect-roles.md`](survey-architect-roles.md)

Roo Code's built-in Architect mode (plan-before-code, edit-restricted to
markdown); wshobson/agents' `backend-architect` (deep-domain, ADRs, defers to
peers) and `ship-mate/architect` (strict plan-only boundaries + escalation
triggers); Martin Fowler's canonical human stance.

- `github.com/RooCodeInc/Roo-Code` · `github.com/wshobson/agents` ·
  `martinfowler.com/ieeeSoftware/whoNeedsArchitect.pdf`

## Distillation — what makes a strong architect

Synthesized across all four sources; every claim is sourced in the linked
surveys. These are the points the authored persona is built from.

1. **Identity = "hold the shape of the system," as a collaborator, not an oracle.**
   The recurring stance is a technical leader who works *before/around* code, not
   above it — and the strongest framing is *collaborative* (Fowler's Oryzus, against
   the decide-everything Reloadus; BMAD's "trade-offs, not verdicts"). → drives
   `skills/architect`'s "Who I am."
2. **Owns the *important, hard-to-change, hard-to-reverse* stuff — boundaries and
   contracts.** Architecture is "things people perceive as hard to change" (Fowler);
   operationally, service boundaries, dependency rules, who owns shared data, the
   contracts between units (BMAD's "spine"; backend-architect's "clear service
   boundaries"). → drives the architect's advisory `owns docs/architecture.md` and
   the *invariants-first* core of `architect-design`.
3. **Owns the decision *rationale*, durably and auditably.** Record *why* and the
   trade-offs, not just *what*: ADRs (wshobson), `AD-n` with Binds/Prevents/Rule +
   memlog (BMAD), architecture as the team's shared understanding (Fowler). → drives
   the "decision record" output of `architect-design`.
4. **Method — gather context and elicit before deciding; drafting is the
   anti-pattern.** Information-gather + clarifying questions (Roo), start from
   non-functional requirements (backend-architect), and BMAD's blunt "a finished
   architecture from two quick questions is the failure mode." → drives the
   elicitation-first shape of `architect-design`.
5. **Method — pin only the invariants; let code own the rest.** BMAD's spine test:
   *fix it here only if two units built independently could choose incompatibly,
   AND the call is non-obvious, AND it's a real trade-off.* The discipline that
   keeps an architecture from becoming a document dump. → the inclusion test inside
   `architect-design`.
6. **Method — decompose into reviewable, independently-executable steps, then hand
   off.** Plan items "clear enough that another mode could execute independently"
   (Roo); pause for approval (ship-mate). The architect plans/reviews; polecats
   implement; the refinery merges. → drives the handoff shape and `architect-review`.
7. **Scope is bounded, deferential, and reduces irreversibility.** Enforced by
   capability (Roo markdown-only; ship-mate no code) and by lane (defer to peers,
   escalate, "do not guess"); the highest-leverage move is making hard-to-change
   things cheap to change (Fowler). → drives the "What I do NOT do" + escalation in
   the architect identity, and the *advisory* (non-enforcing) nature of its owns.

## How the distillation maps onto the build

| Distilled trait | Where it lands in the persona |
|---|---|
| 1 collaborative identity | `skills/architect` — "Who I am" / stance |
| 2 owns boundaries/contracts | `skills/architect` owns `docs/architecture.md`; invariants core of `architect-design` |
| 3 owns rationale (auditable) | `architect-design` decision-record output |
| 4 elicit before deciding | `architect-design` — elicitation-first |
| 5 invariants-only inclusion test | `architect-design` — the spine inclusion test |
| 6 decompose + hand off | `architect-review` + handoff shape (architect plans, polecat implements) |
| 7 bounded/deferential/advisory | `skills/architect` "What I do NOT do" + advisory owns |
