# Escalation — Marching Orders for Downstream Agent Work

> **For the next agent:** this doc gives you the strategic context to do
> operational work on the escalation pack — write skills, draft templates,
> design surfaces, propose new practices. Read the foundation
> (`docs/escalation-foundation.md`) first; this doc fills in the strategic
> ground that the foundation's terseness leaves implicit.

**Status:** active iteration. Decisions captured below were made through
extended conversation; some are firm, some are directional, all are
revisable as use generates evidence.

---

## What this work is for

The pack designs the *consult / escalation moment* — the place where an
AI agent surfaces work to a human for judgment, and the human and agent
together arrive at a decision. The current focus is consult / concierge
work; the broader pack scope (brief → design → spec → implement) is in
scope but later.

The strategic stance, in three lines:

- **Cost of work flipped.** Execution is cheap; reviewer attention is
  scarce and not restartable on demand. Most design choices flow from
  this asymmetry.
- **Borrow as default; falsify as discipline.** Decades of organizational
  wisdom (Toyota, COE, photo editing, ROC) solve human problems that
  don't go away when execution gets cheap. We borrow heavily but every
  borrowing carries a falsification test — the AI failure mode that
  would invalidate it.
- **Make the AI's edges visible.** Legibility and fallibility-honesty
  matter more than apparent intelligence. The agent's job is to be
  readable to the human at every step, not to do more on its own.

These are not in the foundation explicitly; the foundation's principles
(T1–T4, P1–P6, premise) embody them. Trust the principles to do their
own work; don't try to make any one of them carry more than it should.

---

## What we operationally agreed (consult shape)

The consult format the pack standardizes on:

- **Frame layer comes first.** The agent articulates *what it thinks is
  being solved*, in 1–3 sentences, with a one-sentence summary that's
  scannable as the lede. Underneath: criteria considered (split between
  measurable and ambiguous), the slice of design space explored, an
  honest narrowness flag if the exploration was narrow. The frame may
  include a fidelity signal in native vocabulary ("at sketch stage" /
  "candidate ready" / "production-intent") and a reversibility note
  when applicable. No rigid scheme; no enforcement gates.
- **Bottom-anchored consumption (P4).** The recommendation is the *last
  line* of the message. Just above: alternatives with one-line whys.
  Just above: the frame summary. Above (on scroll): full details.
- **Information-dense, not narrative.** Bullet form for options;
  prose for the frame summary and any AAR/COE narrative — bullets let
  you bullet-point your way out of confusion when the discipline is to
  actually think.
- **Visual recommendation mark.** Single character (e.g., "→") on the
  rec line. Not "I recommend C because…" — that demotes the line from
  lede to narrative.
- **One-line whys are required, not optional.** Without them
  alternatives are decorative.
- **Push-back paths are equally cheap as accept.** Pick / pick-with-note
  / counter-pick to a sibling / redirect at the frame layer should all
  be one move away on the surface.
- **Self-contained artifact.** Readable cold without scrolling back into
  the chat that produced it. Eats G3 (decisions live in artifacts).

---

## Operational principles captured

- **Set-based / spread.** The frame block names the slice of design
  space the agent considered; flags when exploration was narrow.
  Spread is a quality the agent self-reports; not a metric the pack
  enforces.
- **Two-pass cull/pick.** The agent owns Pass 1 (technical reject —
  tests, lint, types, budget). The human owns Pass 2 (judgment).
  Separating decision types is the discipline; the consult only
  surfaces Pass-2-ready candidates.
- **Verification co-located with recognition.** Don't put tests,
  type-checks, behavior traces behind a click — they live in the
  contact-sheet view itself. P3 (recognition over reading) alone is
  dangerous; verification must be on the same surface where
  recognition fires.
- **Pre-mortem when stakes warrant.** A single line in the frame
  ("most likely failure mode if this lands: X") on consults touching
  irreversible action classes or production-intent fidelity. Not a
  mandatory ritual on every consult.
- **Reflect-class escalation is real.** The agent challenges the
  human's framing when high-confidence structural conflict warrants —
  bounded, batched as a single question. Dialogue is critically
  important; "here are options, decide" is over-simplification.
- **Goal-fit framing for AAR/COE.** First sentence names who was
  affected and how, in their terms. Not Amazon's brand language;
  generalize to "what failed regarding our goals."
- **Reproducibility data in AAR/COE.** Was this consistent across
  runs? Don't assume reproducibility — AI failures may not reproduce.

---

## Anti-patterns to defend against

Named explicitly so they don't drift in:

- **Lean theater.** Borrowing artifacts (kanban boards, A3 templates,
  COE forms) without the social system that gives them meaning.
- **Just-restart.** Re-rolling the dice on a flaky agent until a
  plausible diff appears. Cheap restart without root-cause is
  technical debt with a friendly UX.
- **Vanity demos.** Polished UI, brittle code. Optimizing for the next
  stakeholder screenshot.
- **Prototype-as-spec.** Treating a sketch as a finished requirement
  because it looks done.
- **Recognition without verification.** "Good from afar." 61% of devs
  report AI code looks correct but isn't reliable.
- **Decision fatigue.** Late picks in a session are worse picks; bound
  consult-review density.
- **Five-Whys linearity.** Single causal chains obscure multi-factor
  texture. Pair with contributing factors.
- **Blame leakage.** "The model hallucinated" is the AI version of
  "human error" — a stop-thinking phrase.
- **Spec-as-training-data.** Including past COEs in agent context
  teaches surface forms, not patterns. Keep a held-out adversarial
  set.
- **Metric without corrective.** A number without an action it triggers
  is observation theater.
- **Pre-commit paralyzes discovery.** Pugh-style weights on ambiguous
  axes (UX, code shape) suppress the recognition the consult is built
  for. Pre-commit only on measurable axes; allow amend-on-discovery.
- **Coaching without retention closure.** Daily kata is theatre unless
  it terminates in a merged skill / gate / fewshot / eval diff. The
  pack — not the agent — is what learns.
- **Cargo-culted vocabulary.** Borrowing "kata," "andon,"
  "nemawashi," "COE" without flagging the disanalogy.

---

## What we chose *not* to do

Active rejections — these came up and were considered and dropped:

- **No harness-vs-model framing.** Models WILL get better and that
  matters. The pack doesn't position against model improvement; it
  focuses on the harness around the model's limits.
- **No metaphor commitment.** Surgeon/scrub-nurse rejected; chief-of-
  staff / co-pilot / PI-RA / coach-apprentice all considered and
  parked. Default is no metaphor; the practices encode the
  relationship.
- **No rigid fidelity scheme.** Looks-like / works-like / production-
  intent considered and rejected as too rigid. Fidelity is a
  contextual signal in the frame, native vocabulary, no gates.
- **No process gates that block work.** Process should empower good
  progress, not add artificial barriers. The pack guides; it doesn't
  gate.
- **No structural enforcement of every consideration.** Things to
  consider when amending the foundation are a list to check, not a
  template-enforced field. Foundation rarely changes; structural
  enforcement is overkill.
- **No conflation across principles.** Each tenet does its own work.
  Don't stretch T1 to cover legibility, don't stretch T2 to cover
  what P3 already says.

---

## What's next

Future / phased work — items captured but not in v1 — lives in
`docs/escalation/roadmap.md`. The most consequential items there:

- Silent-decision audit (the structural counter to T4).
- Edges-visible-proportional-to-impact (operational practice under T4).
- Agent roster watching scope (architect / mechanik / concierge each
  watching their domain).
- Hidden metrics (frame-redirect rate, reviewer trust trajectory,
  half-life of skills, pack self-knowledge).
- Hypothesis-first / develop-before-asking for the broader brief →
  design → spec → implement workflow.
- First skills to write — agent decides based on these marching
  orders and the foundation.
- Skill schema / canonical SKILL.md template.

---

## Pointers

- **Foundation:** `docs/escalation-foundation.md` — the canonical doc;
  start there.
- **Ideation breadth:** `docs/escalation/ideation.md` — full inventory
  of candidates considered (~150).
- **Selection menu:** `docs/escalation/selection-menu.md` — earlier
  attempt at organizing the ideation for curation; superseded by this
  marching-orders doc and the foundation updates.
- **Research:** `docs/escalation/research/` — five domain reports
  (R1–R5) plus seven validation reports (V1–V7). Read for depth on a
  specific borrowing or critique; not required for everyday work.
- **Research log:** `docs/escalation/research-log.md` — index of which
  reports cover what.
- **Roadmap:** `docs/escalation/roadmap.md` — phased / future items.
