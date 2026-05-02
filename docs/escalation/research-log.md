# Escalation Research Log

Companion to `docs/escalation-foundation.md`. Captures the cross-industry
research that informs the pack's borrowing strategy (see Premise: "AI
changed the cost of work, not [necessarily] the principles of organizing
it").

Working thesis being investigated: **when execution gets cheap, oversight
migrates to the ends — intent (front) and integration (back) — and proven
organizational patterns are the right default to borrow from.**

For each area: standard practices that emerged, AI-development analogs,
known counter-arguments / failure modes, primary references.

Status legend: `[QUEUED]` agent dispatched · `[IN PROGRESS]` agent running · `[RETURNED]` findings landed below · `[DEEPENED]` user has flagged for further iteration

---

## Queue

### R1. Toyota Production System `[RETURNED]`
Nemawashi, A3, hansei, kaizen, jidoka, andon cord, kanban, JIT,
genchi genbutsu, poka-yoke, gemba walk. The canonical front+back+mid
template for cheap-execution oversight. User notes: "very solid
practices, absolutely worth deep understanding and references."

Report: `docs/escalation/research/r1-toyota-production-system.md`. All 13
practices covered with mechanics and failure modes. Most important
thing that *didn't* transfer to software: the coach-apprentice dyad.
AI-dev mappings: andon-as-escalation with pull-rate as a health
metric, A3 as the canonical agent→human handoff artifact, nemawashi
as pre-PR consensus, hansei after each task, poka-yoke via typed
schemas and sandboxes. Critical limit (sharp): jidoka can't catch
*semantic* defects like hallucination because the producer can't
distinguish them from correct output. Steel-mans: DeMarco/Lister/
Holub on manufacturing-vs-knowledge mismatch, Emiliani on Lean
theater, Toyota's 2009-10 and 2022-24 scandals as evidence that
scaling execution past the judgment layer fails silently.

### R2. Cheap prototyping (CAD, 3D print, rapid prototyping, on-demand fab) `[RETURNED]`
Design thinking, MVP, lean startup, design sprints, dual-track agile.
The counterintuitive finding that cheap iteration *raises* the bar for
upstream rigor. User notes: "worth a deeper dive."

Report: `docs/escalation/research/r2-cheap-prototyping.md`. Load-bearing finding:
when iteration cost collapses, the bottleneck migrates to *framing*
(what's worth iterating on) and *selection* (which of N survives), not
execution. Empirical support: Thomke & Fujimoto front-loading research,
Ward/Sobek set-based concurrent engineering, Kohavi A/B testing
literature on hypothesis pre-registration. Portable patterns:
hypothesis-first prompting (Ries), Pugh-matrix weighted selection with
weights set *before* generation, three-tier design critique with named
Decider (Knapp), prototype-lineage labels (looks-like → works-like →
production-intent) to prevent prototype-as-spec confusion. Failure
modes: sunk-cost fixation survives cheap prototyping (Viswanathan &
Linsey), low-code's ~60% partial-rewrite rate (McKinsey), demo-driven
development.

### R3. Cheap photography → curation `[RETURNED]`
Photo editor workflows, picture desks, contact sheet rituals, cull-then-
edit, smartphone era, AI image gen curation. User notes: "curious what
processes have emerged from cheap photography." Especially relevant to
P3 (recognition over reading) and P2 (opinion alongside options).

Report: `docs/escalation/research/r3-cheap-photography-curation.md`. P3 grounded
in cognitive science: Klein's Recognition-Primed Decision (RPD),
Kahneman/Klein on intuitive expertise, gestalt perception. Three
conditions for recognition to work: rendered (not described) artifacts,
sweep-friendly layout, reviewer-matched vocabulary. P2 grounded in the
picture editor's flagged-pick-on-contact-sheet protocol: the social
contract works because alternatives stay visible — agent opinionated,
human sovereign, override cheap. Direct dev mappings: rendered UI
variant grids (closest analog), test-output thumbnail grids, two-pass
cull-then-pick (agent Pass 1 = objective failures, human Pass 2 =
judgment). Steel-mans: decision fatigue, mid-curation drift, brand-fit
homogenization, software lacks photography's "publication slot"
scarcity (response: production config is the slot).

### R4. Recovery-Oriented Computing & cheap-restart patterns `[RETURNED]`
Patterson/Fox ROC, crash-only software (Candea/Fox), microreboots, undo
systems, immutable infrastructure, cattle-not-pets, chaos engineering,
SRE error budgets. User notes: "if the restart is cheap, step one is
to just restart a broken machine. Well researched principles worth
pulling in."

Report: `docs/escalation/research/r4-recovery-oriented-computing.md`. Key finding:
the Gas City thesis maps cleanly — agent session is the pod, the
artifact (PR/branch/plan doc) is the externalized recovery state,
multi-sample is FIT for prompts, feature-flag-plus-revert is the
deployed-change undo button. Critical caveat: human reviewer attention
is finite and non-restartable, so cheap-restart without root-cause
discipline becomes an anti-pattern — a constraint ROC didn't face.

### R5. Amazon COE (Correction of Error) `[RETURNED]`
COE document structure, weekly ops review, Bar Raiser, ties to
Customer Obsession / Ownership / Dive Deep. Comparison with Google SRE
postmortem, AAR, M&M conferences. User notes: "I worked at Amazon so
the COE practice is highly regarded by me."

Report: `docs/escalation/research/r5-amazon-coe.md`. Key findings: what COE
uniquely insists on is written-first + customer-framed + action-tracked
+ widely-distributed. Concrete agent-COE template proposed with two-
layer cadence (per-event AAR + periodic full COE sweep) feeding skill/
gate/example updates. AI-specific risk flagged: COE corpus becomes
training data and overfits to past surface forms — the Five-Whys
linearity trap (Cook) compounds when treated as ground truth by future
agents.

---

## Returned findings

*(agents will append structured reports here as they complete)*
