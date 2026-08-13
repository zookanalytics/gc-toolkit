---
name: Promotion-gate dry-run — tk-48ru7 and the queued feedback patterns
description: Re-screens the nine open feedback-pattern beads (including tk-48ru7 / PR #330) against the two new always-injected-promotion gates, showing which would now be blocked and why none auto-promotes into always-injected content this cycle.
---

# Promotion-gate dry-run (tk-lv6q5)

Operator ruling 2026-08-12 (visit tk-yohhf, subject tk-d9g0x / PR #330,
closed unmerged) found the feedback-learning rubric promoted a self-sourced,
structural-remedy pattern (tk-48ru7) into always-injected polecat prompt
content that should never have qualified. tk-lv6q5 adds two gates on
promotion into always-injected content, defined in
`skills/learning-distill/SKILL.md` and recorded as decisions D8/D9 in
`specs/2026-08-learning-system/decisions.md`.

- **Gate 1 — source diversity.** A cluster that is entirely
  `obs.source=self`, or whose `distinct_sources=1`, cannot auto-promote into
  a `learned-conventions-<role>` fragment without an `obs.endorsed=operator`
  observation. Blocked → *surfaced*, not adopted.
- **Gate 2 — remedy class.** A remedy that is an exhortation, or that fixes a
  structural failure (verification gap / race / missing mechanical check),
  routes to an **engineering work bead**, not a prompt bullet. Only a
  concrete behavior keyed to a concrete trigger promotes as prose.

`distinct_sources` counts distinct `obs.source` values ∈ {`self`, `miner`,
`operator`} — not sessions. Four self-reports from four sessions are
`distinct_sources=1`: one voice repeating.

## Re-screen of the nine open feedback-pattern beads

Snapshot 2026-08-12. Gate 1 exception = an `obs.endorsed=operator` observation
in the cluster.

| Pattern | scope | sources | Gate 1 | Gate 2 | Net disposition under the new gates |
|---|---|---|---|---|---|
| **tk-48ru7** completeness-enumerate-full-set | agent:polecat | 1 (4× self) | **BLOCK** | **engineering** (exhortation + verification gap) | Blocked by **both**. The PR #330 case. No bullet; a mechanical done-gate is the real fix. In-window guard added (below). |
| tk-6u3v6 graphv2-step-close-contract | agent:polecat | 1 (2× self) | **BLOCK** | **engineering** (enforcement lives in `retry.go`/`values.go`) | Blocked by both. Route to a clearer `bd` rejection / non-retryable classification, not prose. |
| tk-6lgxp finding-disposition | repo:gc-toolkit | 1 (1× miner) | **BLOCK** | concrete behavior (promotable as prose in principle) | Blocked by Gate 1 (single source). Surface; promotes on a 2nd source or endorsement. |
| tk-v8sk4 test-gate-tier-selection | repo:gascity | 1 (1× self) | **BLOCK** | **engineering** (lean — "two gates one blind spot"; fix is tier-by-diff-reach) | Blocked by Gate 1; structural → engineering candidate. |
| tk-b7q0n transient-tooling-retry | agent:polecat | 1 (1× operator, `dir=diff`) | **BLOCK** | concrete-ish (judgment-flavored) | Blocked by Gate 1: operator-**sourced** but not **endorsed**, single source. See "edge case" below. |
| tk-ogsok converse-triage-bucket-contract | agent:converse | 1 (1× self) | **BLOCK** | **engineering** (bead says "converse-contract code/prompt fix, not a bullet") | Blocked by both. |
| tk-xgaeo prompt-content-economy | repo:gc-toolkit | 2 (miner+operator) | **PASS** | mixed (authoring guideline + a "do broadly" codebase sweep) | Clears Gate 1. Still HELD for its own reason (no content-authoring home surface exists; putting it in the always-injected polecat fragment would itself violate the economy principle). Strongest candidate once a home is chosen. |
| tk-nr2ii converse-operator-framing-rigor | agent:converse | 2 (self+operator) | **PASS** | **borderline** — "ground framings in verified reality" reads as instruction-dependent | Clears Gate 1. Would need a concrete-behavior rewrite to promote as prose, else engineering. Already HELD (no converse fragment; accumulate). |
| tk-vglpm operator-facing-trailing-content | global | 1 (2× operator, one **endorsed**) | **PASS** (exception) | concrete behavior | Clears both — the `obs.endorsed=operator` observation (tk-rlhkd) is the exception. Already HELD anyway: the endorsed ask shipped in PR #316; residuals lack a home fragment. |

### Result

**Zero of the nine would auto-promote into always-injected content under the
new gates this cycle.** Six are blocked by Gate 1 (self-only or
single-source, unendorsed). The three that clear Gate 1 are each already HELD
for an independent reason — no home fragment yet (tk-xgaeo, tk-nr2ii), or the
concrete ask already shipped (tk-vglpm) — and none is a clean
concrete-behavior promotion into an existing wired fragment. Four of the
blocked patterns (tk-48ru7, tk-6u3v6, tk-v8sk4, tk-ogsok) are structural and
would instead route to an engineering bead under Gate 2.

The gates therefore reproduce the operator's PR #330 verdict mechanically:
tk-48ru7 fails both, and nothing currently queued slips past them.

### Edge case worth naming — tk-b7q0n (operator-sourced, not endorsed)

tk-b7q0n is `obs.source=operator` but `dir=diff` and not `obs.endorsed`. The
gate's exception key is deliberately `obs.endorsed=operator` (the explicit
"learn this" / PR endorsement), **not** `obs.source=operator`: an operator
*writing a diff-scoped review comment* is not the same act as the operator
*endorsing a standing rule*. A single operator comment therefore surfaces and
promotes on corroboration or an explicit endorsement — consistent with D3
(operator review is the gate) and with judgment 1's treatment of unendorsed
universal wording. This keeps the exception from becoming a loophole where any
mined operator comment auto-adopts.

## tk-48ru7 re-adjudication and in-window guard

Under the new gates tk-48ru7 is blocked twice over: entirely `obs.source=self`
with `distinct_sources=1` (Gate 1), and its remedy — "enumerate the full set
before declaring done" — is an exhortation addressing a verification gap
(Gate 2). Once this change lands, the rubric blocks it by rule permanently and
names it as the worked example for both gates.

For the window before landing (the distiller runs on a 24h heartbeat), the
pattern bead already carried an operator note ("DO NOT re-promote until
tk-lv6q5 lands"). That note lives in the bead's `notes` field, which the
distiller's mechanical pattern listing does **not** project (it selects
`{id, title, metadata}`). So a machine-readable hold was added to the
metadata, where the listing does see it:

- `promotion_hold=gate1-and-gate2-pending-tk-lv6q5`
- `remedy_class=structural`

Both are non-rollup keys, so the distiller's single-writer rollup recompute
(`evidence_count` / `distinct_sources` / `first_seen` / `last_seen`) does not
touch them. tk-48ru7's four observations are already stamped consumed, so it
can only re-enter judging if a fresh observation clusters onto it; the note +
flag guard exactly that path until the rule supersedes them.

## Note on scope — "the template-fragment backing it"

The bead asked to edit "the promotion-judgment rubric (skill
`gc-toolkit.learning-distill` and the template-fragment backing it)". There is
no separate template-fragment carrying the rubric's judgment method — the only
parallel copy is the **degraded-core fallback** embedded in
`formulas/mol-feedback-distiller.toml` (`judge-and-cluster` §1), which the
distiller judges on when `origin/main:SKILL.md` is unreadable. Both copies now
encode the gates, so the fail-soft path cannot reintroduce the bug. Files
changed:

- `skills/learning-distill/SKILL.md` — the two gates, discriminator, worked examples (source of truth).
- `docs/feedback-learning.md` — the gates in the promotion-path + rule-surface conventions.
- `formulas/mol-feedback-distiller.toml` — degraded core (fallback), the two new judge outcomes (**surface** / **route-to-engineering**), and the engineering-bead filing route (`file-and-dispatch` §1b).
- `specs/2026-08-learning-system/decisions.md` — decisions D8/D9.
- `specs/tk-lv6q5/dry-run.md` — this record.
