# Escalation Research Log

Companion to `escalation-foundation.md`. Captures the cross-industry
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

### R1. Toyota Production System `[QUEUED]`
Nemawashi, A3, hansei, kaizen, jidoka, andon cord, kanban, JIT,
genchi genbutsu, poka-yoke, gemba walk. The canonical front+back+mid
template for cheap-execution oversight. User notes: "very solid
practices, absolutely worth deep understanding and references."

### R2. Cheap prototyping (CAD, 3D print, rapid prototyping, on-demand fab) `[QUEUED]`
Design thinking, MVP, lean startup, design sprints, dual-track agile.
The counterintuitive finding that cheap iteration *raises* the bar for
upstream rigor. User notes: "worth a deeper dive."

### R3. Cheap photography → curation `[QUEUED]`
Photo editor workflows, picture desks, contact sheet rituals, cull-then-
edit, smartphone era, AI image gen curation. User notes: "curious what
processes have emerged from cheap photography." Especially relevant to
P3 (recognition over reading) and P2 (opinion alongside options).

### R4. Recovery-Oriented Computing & cheap-restart patterns `[RETURNED]`
Patterson/Fox ROC, crash-only software (Candea/Fox), microreboots, undo
systems, immutable infrastructure, cattle-not-pets, chaos engineering,
SRE error budgets. User notes: "if the restart is cheap, step one is
to just restart a broken machine. Well researched principles worth
pulling in."

Report: `docs/research/r4-recovery-oriented-computing.md`. Key finding:
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

Report: `docs/research/r5-amazon-coe.md`. Key findings: what COE
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
