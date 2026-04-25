# Escalation Ideation — Broad Candidate Set

> **Status: drafting.** Wide net first; the user's job on return is selection,
> not generation. Every candidate carries a one-line description, a source
> tag, and a current lean. Tradeoffs and risks are surfaced explicitly so
> the menu reads more like a contact sheet than a recommendation.

Source tags: **R1** Toyota · **R2** Cheap Prototyping · **R3** Photography
Curation · **R4** Recovery-Oriented Computing · **R5** Amazon COE · **X**
Cross-cutting · **AI** AI-native (no clean human precedent).

Lean values: **strong** ready to land · **lean+** probably yes ·
**lean−** probably no · **explore** worth a deeper agent run · **park**
not now.

---

## Cross-cutting threads from R1–R5 (the spine)

These three patterns surfaced from every report and form the backbone for
everything below.

**X1. Selection beats execution.** When execution gets cheap, the work
moves to *framing* (what's worth iterating on) and *selection* (which of N
survives). R2's set-based engineering, R2's Pugh matrices, R3's editor's
workflow all converge: weights chosen *before* generation, candidates
rendered for sweep, kill rate as a health metric.

**X2. Automated catch has semantic blind spots, and AI widens them.** R1's
jidoka can't catch hallucination because the producer can't distinguish
defect from correct output. R5's Five-Whys is dangerously linear (Cook).
R4's "just restart" laundering. Same shape: shape-defects automatable;
meaning-defects need humans.

**X3. Human attention is the new constraint nobody had.** R4 names it
explicitly: cheap-restart without root-cause discipline burns reviewer
attention. R2 names decision fatigue. R3 names mid-curation drift. The
source disciplines didn't face this — Toyota line workers weren't the
bottleneck, photo editors had a job-shaped attention budget. The pack
does. T1 is doing more work than v0 knew.

---

## V1 Red-Team verdicts (summary)

Full report: `docs/research/v1-red-team.md`. Three load-bearing structural
findings the pack hadn't named:

- **Attention-budget overdraft.** A2 sharpens T1 to "non-restartable,"
  then B authors a dozen human-written rituals without a ledger. The
  pack needs an explicit *attention-budget meta-practice* (M1 below).
- **Metric-without-corrective.** B10/B16/B23 (and partly A1/B6)
  propose numbers to track without naming the action they trigger. X2
  failure mode in disguise. Need *metric-with-corrective discipline*
  (M2).
- **Borrowing from systems with retention.** A Toyota apprentice
  retains learning; an LLM session does not. A4/B21/B14/B17 are
  pantomime unless they terminate in a B15-style artifact diff. Need
  *coaching-terminates-in-artifact rule* (M5).

Specific verdicts (V1's strongest lean, not the final word):
- **Cut:** A1, B8, B10, B11, B16, B17, B23, B25
- **Merge:** A8↔B3, A9↔B12, A4↔B21↔B15, B2↔A5, B4↔B13, B5↔G3, B24↔B1
- **Keepers no change:** A2 (with "on demand" tightening), A5, A6, B15,
  B19, B22

Items in A and B below are not edited inline; the user picks. The cuts
and merges go on the selection menu later as proposals to ratify.

---

## M. Meta-practices — discipline that polices the rest

V1 surfaced gaps in the *shape* of the pack itself, not just in
individual candidates. These meta-practices govern how the rest hold
together.

**M1. Every practice prices its attention claim.** *(V1 C1)* No
practice is admitted without a stated bound on human cost per task
class. The default is "unbounded → rejected." This is the ledger T1+A2
demand. **strong, candidate for foundation-level addition.**

**M2. Every metric practice names threshold + corrective + actor.**
*(V1 C2)* A number without an action is observation theater.
Threshold says when to act, corrective says what to do, actor says who
does it. **strong.**

**M3. Every borrowed pattern flags its disanalogy inline.** *(V1 C5)*
Patterns from Toyota / photography / SRE / Amazon carry a one-line
"where the source breaks" note at the borrow site, not buried in a
research log. Prevents cargo-culting. **strong.**

**M4. Pre-commit vs. discovery: distinguished by task class.** *(V1
C3)* Pre-commit weights (B1, Pugh) work for measurable axes — perf,
cost, dependency footprint, diff size. They actively suppress
recognition (P3) for ambiguous axes — UX, code-shape, intent
clarity. Apply pre-commit selectively; require an "amend criteria"
ritual when the candidates surface a dimension nobody named. **strong.**

**M5. Coaching terminates in a merged artifact.** *(V1 C4)* Any
coaching/review/retrospective practice (A4, B14, B17, B21, AAR/COE)
counts only when it produces a skill/gate/fewshot/eval diff. The
agent doesn't retain across sessions; the *pack* retains. B15 is the
spine. **strong, makes B15 load-bearing.**

**M6. Default-conservative reversibility classification.** *(V1
B19 co-practice)* When in doubt about whether an action is
reversible, classify as irreversible. The reverse default fails
silently and catastrophically. **lean+.**

---

## A. Refinements to v0

Targeted edits to existing items. Most are tightenings; a few are
sharper restatements.

**A1. G1 — name "zero escalations" as a failure mode.** *(R1)* Toyota
tracks andon pull-rate as a health metric: a falling rate is a warning.
G1's "fewer escalations over time" reads naturally as "monotonically
lower," which is the wrong reading. Add a sentence: *"Zero escalations
is a failure mode — either the system is solving only trivial work, or
defects are hiding."* **lean: strong.**

**A2. T1 — sharpen with "non-restartable."** *(R4, X3)* R4's hardest
caveat: human attention is finite and non-restartable. ROC didn't have
this constraint; we do. The phrase "non-restartable" is sharper than
v0's "scarce." Candidate body: *"Agent tokens, compute, retries, and
self-critique are free and restartable. Human attention is finite and
non-restartable. Every action prices its claim against it."* **lean:
strong.**

**A3. T2 — add: license to parallelize during wait.** *(R2 set-based)*
Currently T2 says wait time deepens single work. SBCE (Ward/Liker/Sobek
1995) says the right thing to do during wait is *carry multiple
candidates longer than feels comfortable*. Candidate body extension:
*"Wait is also when the option set widens; the human's clock is what
collapses it."* **lean: lean+.**

**A4. T3 — add coach-apprentice frame.** *(R1)* The most important
thing that didn't transfer when software borrowed TPS, per Rother's
*Toyota Kata*. The pack's learning is human-coached, not auto-
learning. Candidate body sentence: *"The human is the coach; the
agent is the learner; the pack is the curriculum."* **lean: lean+,
but watch for "we already said this in T2/G2" overlap.**

**A5. P1 — split shape-defects from meaning-defects.** *(R1, X2)*
P1's "only what only the human can answer" is the right shape but
hides the most important AI-specific distinction: jidoka catches
*shape* defects (type errors, exceeded budget, test failures); it
cannot catch *meaning* defects (hallucination, wrong intent,
ambiguous spec). The pack should pre-filter the first and reliably
escalate the second. Candidate elaboration: *"Shape defects belong to
the agent's gates (poka-yoke, type checks, budget caps); meaning
defects always escalate. The agent does not adjudicate its own
semantics."* **lean: strong.**

**A6. P2 — bidirectional contract phrasing.** *(R3)* R3's editor
contract is sharper than v0's "opinion alongside options": the agent
is opinionated, the human is sovereign, override cost is bounded by
what's already laid out. Candidate body: *"The agent ships its
recommendation, the dismissed alternatives, and a one-line why for
each. The human can stay on the rec (cheap), counter-pick (cheap),
or escalate (rare). Single-rec systems concentrate authority; pure
buffets offload all judgment."* **lean: strong.**

**A7. P3 — add the three preconditions.** *(R3)* Recognition only
fires when (a) the artifact is rendered, not described; (b) the
presentation supports sweep, not drill (grid not list); (c) the
vocabulary is the reviewer's. v0's P3 is one sentence — these
preconditions are load-bearing and worth surfacing. **lean: strong.**

**A8. P5 — render-first requirement.** *(R2, R3)* P5 says "highest-
density form." R2/R3 sharpen: when the agent produces N candidates,
it must render N visible artifacts laid out for sweep, not N
descriptions. The principle is *information density*, but the
sub-rule is *rendered, not narrated*. **lean: strong.**

**A9. P6 — add lineage labels.** *(R2)* Ulrich & Eppinger's looks-
like / works-like / production-intent labels prevent prototype-as-
spec confusion. P6 is about context triggers; fidelity is one of the
most useful triggers. Candidate addition: *"Lineage labels —
'spike,' 'works-like,' 'production-intent' — are context triggers
that prevent confusing a learning artifact with a candidate for
merge."* **lean: lean+.**

**A10. Premise — sharpen the asymmetry line.** *(X3)* The current
last line "agent labor is near-free; attention isn't" is good. R4
adds the sharper version: *"agent labor is restartable; attention
isn't."* This connects directly to T1's proposed sharpening (A2).
**lean: lean+.**

## B. New practice candidates

Operational hows that emerged from R1–R5 and don't yet exist in v0. The
list is deliberately wide. Many overlap; merging is part of selection.

**B1. Pre-commit selection criteria.** *(R2 Pugh)* Before the agent
generates N candidates, the human (or the agent under human approval)
writes the weighted criteria. Without this, reviewers default to surface
heuristics — clever-looking diff over boring-correct one. **strong.**

**B2. Two-pass review: cull, then pick.** *(R3)* Pass 1 (cull, default-
keep, technical reject only — tests/lint/types/budget) is automatable;
the agent does it. Pass 2 (pick, default-drop, judgment) is the human's
single keystroke + optional note. Separating decision types is the
discipline. **strong.**

**B3. Contact-sheet rendering.** *(R3)* When the agent emits N
candidates, render N visible artifacts laid out for sweep — diff
carousel, UI variant grid, behavior screenshots, test-result strips.
Not a list of descriptions. The pack should refuse to present
candidates as prose. **strong.**

**B4. Hypothesis-first prompting (intent layer).** *(R2 Ries/Cagan)*
Before generation: what we believe, what would change our mind,
success criteria, guardrails. A `hypothesis.md` per task. The agent
restates it before generating. The AI-A3. **strong.**

**B5. Externalize state (artifact-as-recovery).** *(R4 crash-only)*
The agent's plan, decisions, and progress live in repo files (branch,
plan doc, scratchpad), not in chat context. A fresh agent can pick up
where the previous one stopped. The artifact *is* the recovery state.
**strong.**

**B6. Andon for agents — defined stop-and-escalate triggers.** *(R1)*
A bounded class of abnormalities triggers escalation: ambiguous spec,
conflicting evidence, irreversible action, low-confidence tool result,
exceeded budget, semantic ambiguity. The escalation is cheap (one tool
call), visible (logged), rewarded (not penalized). Pull rate is a
health metric. **strong.**

**B7. Poka-yoke first, prompt last.** *(R1)* Every "the agent did X by
mistake" postmortem yields a *structural control* (typed schema, dry-
run mode, sandbox, branch protection, idempotency key) — not a line in
the system prompt. Prompts are the worst place to enforce safety;
they fail silently. **strong.**

**B8. Pre-PR consensus (nemawashi for agents).** *(R1)* Before opening
a 2,000-line PR, the agent circulates a one-page intent doc to humans
and to agents that own affected code, gathers objections, revises. The
PR ratifies a decision; it doesn't start one. Inverts the current
"agent ships, humans review at the end" default. **strong.**

**B9. Set-based candidate carrying.** *(R2 SBCE)* Carry 3+ live
candidates explicitly until a forcing function collapses the set, not
the first-plausible. Default is pluralism. The pack ritual makes
"keep the runner-up" a required field, not a courtesy. **lean+.**

**B10. Kill rate as a health metric.** *(R3)* Track human acceptance
rate per task class. Too low (≈100% accept = rubber-stamping or
trivial work); too high (<5% accept = bad framing). Picture editors
expect 1-in-30; AI-dev should sit somewhere comparable. The number is
the number; the trend is the signal. **strong.**

**B11. Diff-of-diffs.** *(R3)* When N candidates exist, surface what
varies vs. what's invariant across them. The reviewer's eye lands on
the decision-relevant axis instead of re-reading the same lines five
times. Tooling gap. **explore.**

**B12. Lineage labels (looks-like / works-like / production-intent).**
*(R2 Ulrich & Eppinger)* Every agent artifact carries a fidelity
label. The pack refuses to merge a "spike" without an explicit
upgrade. Prevents prototype-as-spec drift. **lean+.**

**B13. Pre-mortem before generation.** *(R2 Klein)* "Imagine this
landed and caused an outage in 30 days. What was it?" Cheap insurance
against the agent's plausible-looking output. Pair with a per-event
AAR (B14). **lean+.**

**B14. Per-event AAR plus periodic COE sweep.** *(R5)* Two-layer
cadence: lightweight write-up (within a day) after every surprising
escalation outcome — wrong reject, missed context, hidden defect —
and a weekly/biweekly batch read of the AARs that produces 1–2 full
COEs on the patterns that recur. Avoids 1000-COEs-nobody-reads.
**strong.**

**B15. Closure-as-merged-artifact.** *(R5)* Every action item closes
with a commit hash, not "we discussed it." The artifact updates
(skill diff, gate config, new few-shot example, regression eval)
are the unit of closure. **strong.**

**B16. Innovation accounting for agent runs.** *(R2 Ries)* The metric
isn't tokens spent or PRs opened; it's *hypotheses resolved*. Most
agent invocations don't move the team's belief about the system; the
ones that do are the signal. Weekly review compares predicted-to-
actual impact and feeds back into prompt and spec quality. **explore.**

**B17. Quarterly meta-review for repeats.** *(R5)* A scheduled read of
the past quarter's AARs/COEs looking for *repeats*. Repeats are the
signal that a one-off fix didn't reach the underlying pattern. **lean+.**

**B18. Held-out adversarial eval.** *(R5)* Past failures are training
data, but if the agent only sees them, it learns the surface forms,
not the underlying pattern. Reserve a held-out set for periodic
adversarial evaluation. **lean+.**

**B19. Reversibility budget / quarantine zones.** *(R4)* Irreversible
actions (email send, card charge, production schema, public posts)
get explicit budgets and quarantine boundaries — not optimistic
restart. Brown's IMAP needed a proxy delay layer; agent harnesses
need analogous staging. **strong.**

**B20. Senior-reader one-hard-question discipline.** *(R5)* Every COE
gets one hard written question from a senior reader. Anti-ritual-
completion. The question is on the COE doc, public, answered before
closure. **lean+.**

**B21. Coach-apprentice cadence.** *(R1 Toyota Kata)* Daily-ish 1-on-1
between human-as-coach and agent-as-learner against an explicit
target condition (e.g., "reduce false-escalations from 12% to 5%").
Rother's coaching kata. The dyad — not the corpus — is the deep
learning mechanism. **lean+.**

**B22. Agent as witness, human as author.** *(R5)* The agent drafts
the timeline section of any postmortem (it has the trace); a human
authors the rest. Authorship discipline. The agent does not adjudicate
its own behavior. **strong.**

**B23. Confidence calibration tracking.** *(synthesis)* Confidence
tags are useful only if calibrated. Track stated-vs-actual outcome
rates per agent per task class. Miscalibrated confidence is worse
than no confidence. **explore.**

**B24. Pre-composition discipline (resist "fix it in the cull").**
*(R3 counter)* The best PR is the one that didn't need a cull
carousel. Cheap-iteration culture atrophies pre-prompt design. Spec
quality and intent clarity stay first-class even when generation is
free. **lean+.**

**B25. Don't A/B architecture.** *(R2 + R3)* Empirical decisions
(perf, UX, error rate) ship behind a flag and let the metric
decide. Architectural decisions get critique-style review. Don't
conflate. Knapp-style Decider for architecture; Kohavi-style
hypothesis testing for empirics. **lean+.**

**B26. Spread requirement on candidate sets.** *(R3 counter)* Five
similar candidates is decorative, not real. The pack requires
*spread* — meaningful axis variation — in any candidate set, not
just count. Otherwise the contact sheet is theater. **lean+.**

## C. Skill / artifact candidates

Concrete templates that would live in `skills/<name>/SKILL.md` per the
pack-v2 schema. Each has a clear artifact shape and a clear when-to-
invoke. Some entries may be tools or agents, not skills — flagged.

**C1. Hypothesis A3 (`skills/hypothesis/`).** One-page intent doc:
what we believe, what would change our mind, success criteria,
guardrails, options considered, recommendation, plan, rollback.
Used before generation; circulated for nemawashi. The canonical
agent→human handoff format. *Combines B4 + B8.* **strong.**

**C2. Selection matrix (`skills/selection/`).** A `selection.md`
table with weights set in advance, candidates as rows, the chosen
variant marked with a one-paragraph rationale, runner-up preserved
for later. Format also encodes P2 (opinion + alternatives). *B1.*
**strong.**

**C3. Andon escalation (`skills/escalate/`).** Bounded stop-and-
escalate triggers (ambiguous spec, conflicting evidence, irreversible
action, low-confidence tool result, exceeded budget, semantic
ambiguity) with a structured trace context. One-shot, cheap, logged,
rewarded. *B6.* **strong.**

**C4. AAR (per-event) (`skills/aar/`).** Lightweight within-a-day
write-up: what was supposed to happen, what happened, why the gap,
what we'll change. Standing structure, three to five lines per
section. Drafted by the human in the loop, with the agent producing
the timeline section from its trace. *B14.* **strong.**

**C5. COE (periodic deep) (`skills/coe/`).** Customer/intent impact
first; timeline; Five Whys (with Cook caveat — pair with contributing
factors); lessons; action items with commit hashes for closure.
Read in a recurring forum. *B14, B15.* **strong.**

**C6. Plan-doc (`skills/plan/`) — externalized state.** Standard
structure: goal, plan, decisions log, scratchpad, open questions.
Lives in the working branch. Lets a fresh agent pick up where the
previous one stopped. *B5.* **strong.**

**C7. Pre-mortem (`skills/premortem/`).** Klein's exercise applied
before a non-trivial agent task: "imagine this landed and caused an
outage in 30 days. What was it?" Pair with the hypothesis A3 (C1).
*B13.* **lean+.**

**C8. Lineage label.** A required front-matter field on every plan
doc / PR description: `fidelity: spike | works-like | production-
intent`. Refuse merge of `spike` without explicit upgrade. Could be
a procedural skill, but more naturally a harness gate. *B12.*
**lean+ — light skill or harness rule.**

**C9. Reversibility ledger (`skills/reversibility/`).** Per-task
declaration of which actions in the plan are reversible and which
aren't. Irreversibles get budget-and-quarantine — flag-gated, dry-
run first, explicit human green-light. *B19.* **lean+.**

**C10. Decider designation.** A required field at the top of any
multi-candidate decision: `decider: <named human>`. Single owner
breaks ties; consensus is *not* the goal. Procedural. *B25 + R2
Knapp.* **lean+ — light.**

**C11. Coach session (`skills/coach/`).** Standing structure for
the human↔agent kaizen 1-on-1: target condition, last experiment,
what we learned, next experiment, obstacles. *B21 Toyota Kata.*
**lean+.**

**C12. Spread-checked candidate set.** A check (probably a small
tool wrapping a model call) that 3+ candidates show meaningful axis
variation, not surface paraphrase. Refuses contact-sheet rendering
on a homogeneous set. *B26.* **explore — tool/eval.**

**C13. Confidence calibration log.** Records agent-stated
confidence alongside actual outcome for trend tracking per task
class. Powers calibration analysis (B23). **explore — measurement
infra.**

**C14. Adversarial eval suite.** Held-out failure modes that don't
enter agent context, run periodically against the live pack. *B18.*
**explore — engineering, not a skill per se.**

**C15. Innovation-accounting ledger.** Tracks hypotheses-resolved
per period. Compares predicted-to-actual impact of merged agent
changes. *B16.* **explore — measurement infra.**

**C16. Diff-of-diffs viewer.** Surfaces what varies vs. invariant
across N candidate diffs. *B11.* **explore — tool, not a skill.**

**C17. Hansei reflection block.** A short self-critical paragraph
the agent appends to every task report: what assumption did I make
I shouldn't have, what tool call wasted budget, what I'd do
differently. Could fold into the AAR (C4) or stand as a per-task
microform. *R1 hansei.* **explore — possibly subsumed by C4.**

## D. Posture / metaphor candidates

The user parked the AI's posture metaphor (surgeon/scrub-nurse rejected).
A good metaphor must encode: human as decider (sovereign); agent as
opinionated and prepared, with options; asymmetric attention costs;
teaching/coaching loop; artifact-mediated work.

**D1. Chief of staff + executive.** *(synthesis)* The agent prepares
briefings, drafts memos, surfaces options with recommendations,
manages the calendar of decisions, runs background research. The
executive (human) makes the calls and owns the outcome. Modern,
captures attention-as-currency, opinion-alongside-options, durable-
artifacts naturally. **strong.**

**D2. Co-pilot + pilot in command.** *(synthesis, aviation CRM)* The
PIC has final authority; the co-pilot challenges, supports, takes
over when delegated. Crew Resource Management literature is rich
(callouts, "I have the controls," challenge-and-verify). Anthropic-
adjacent — fits the GitHub Copilot / "Claude as co-pilot" framing.
Weaker on the artifact-mediation side; CRM is mostly verbal.
**lean+.**

**D3. Principal investigator + research assistant.** *(synthesis)*
PI sets the questions and judges results; RA runs the experiments,
gathers data, drafts findings. Strong on hypothesis-first (B4),
front-end discipline, back-end review. Resonant for research-heavy
work; less natural for routine coding. **lean+, partial fit.**

**D4. Coach + apprentice.** *(R1 Toyota Kata)* The human is the
coach; the agent is the apprentice; the pack is the curriculum.
Captures the kaizen loop and the learning-by-coaching mechanism that
R1 named as the missing ingredient when software borrowed TPS.
Weakness: feels paternalistic for software audiences and doesn't
naturally capture the agent's volume capability. **lean+, captures
T3.**

**D5. Picture editor + photographer / writer.** *(R3)* The agent is
the producer (high-volume capture or first-draft); the human is the
editor (cull, sharpen, enforce voice). Strong on the
selection/recognition layer that R3 named. Weakness: the agent is
not really an artist with vision; the metaphor over-romanticizes the
generation step. **lean+, partial fit.**

**D6. Caddy + golfer.** *(synthesis)* Caddy reads the course,
suggests the shot with reasons, knows the bag — golfer takes the
shot and owns the outcome. Captures opinion-with-options and clean
authority. Light, sport-flavored. **explore — small but evocative.**

**D7. Reject the single metaphor; use a roster.** *(meta)* Different
work uses different relationships: ambient agents are chief-of-staff;
live coding is co-pilot; research is PI/RA; high-volume generation
is editor/photographer. The pack adopts a roster keyed to context
rather than a master metaphor. Lower elegance, higher accuracy.
**explore — has the virtue of being honest.**

**D8. Reject metaphor entirely.** *(meta)* The relationship is what
the practices encode; reaching for an analogy is a comfort move, not
a discipline move. The pack just says "agent and human" precisely
and lets the practices do the work. **explore — austere but
defensible.**

*Note: the existing pack already has a roster of agents
(concierge, architect, mechanik). Whatever metaphor lands here
should be compatible with that roster, not redundant with it.*

## E. Metric candidates

Each metric below names threshold, corrective, and actor per the M2
discipline. Metrics without those three should not appear.

**E1. Pull rate (escalations per task class).** *(R1, replaces A1)*
*Threshold:* stable per-class rate; significant deviation triggers
review. *Corrective:* rising → investigate spec ambiguity; falling →
investigate gate sufficiency or trivialization. *Actor:* pack
maintainer. **strong; this is what A1 was trying to be.**

**E2. Cull rate / acceptance rate (per task class).** *(R3, B10
fixed)* *Threshold:* per-class baseline established empirically over
N runs (no borrowed magic number). *Corrective:* low rate (≈100%
accept) → likely rubber-stamping or trivial work, escalate review
intensity; high rate (<5% accept) → upstream framing problem, spec
rewrite. *Actor:* human reviewer. **strong if anchored per-class.**

**E3. Action-item closure latency (AAR/COE actions).** *(R5)*
*Threshold:* item open >N weeks triggers escalation; >2N weeks
auto-promotes priority. *Corrective:* re-prioritize, reassign, or
explicitly close with rationale. Aging dashboard visible to room.
*Actor:* COE author + pack maintainer. **strong.**

**E4. Reversibility-budget burn rate.** *(R4, B19)* *Threshold:*
fraction of agent runs touching irreversible actions, vs. allocated
budget per period. *Corrective:* approaching limit → tighten
quarantine, open a poka-yoke project. *Actor:* harness maintainer.
**strong.**

**E5. Time-to-restart (artifact-pickup latency).** *(R4)*
*Threshold:* a fresh agent should be able to resume from the plan-doc
within X minutes of a session loss. *Corrective:* exceeded → invest
in B5/C6 externalized-state quality. *Actor:* harness maintainer.
**lean+.**

**E6. Override rate (P2 contract health).** *(synthesis)*
*Threshold:* baseline how often the human counter-picks vs. accepts
the agent's recommendation. *Corrective:* very low → agent's
recommendations miscalibrated *or* human is rubber-stamping; very
high → spec ambiguity. *Actor:* pack maintainer. **explore — this
directly measures whether P2 is working.**

**E7. Skill-update yield per COE.** *(R5 + B15)* *Threshold:* every
closed COE should produce ≥1 merged skill/gate/fewshot/eval diff.
*Corrective:* zero → reopen the COE, the loop didn't close.
*Actor:* COE author + senior reader. **strong.**

**E8. AAR latency.** *(B14)* *Threshold:* AAR within 1 working day
of surprise. *Corrective:* missed → review cadence with M1
attention budget; relax if budget exceeded. *Actor:* human in
loop. **lean+.**

**E9. Repeat rate in COE corpus.** *(R5)* *Threshold:* fraction of
new COEs whose Five-Whys tree intersects a prior COE's. *Corrective:*
high → the previous fix didn't reach the underlying pattern;
escalate to a structural change (skill rewrite, gate redesign).
*Actor:* meta-reviewer (B17 if kept). **lean+.**

**E10. Confidence calibration delta (per task class).** *(B23 with
V1 caveat)* *Threshold:* Brier-score (or similar) deviation between
agent-stated confidence and observed outcome. *Corrective:*
recalibrate; suppress confidence display if uncalibrated. *Actor:*
pack maintainer. *Caveat:* recalibration is a real cost on every
model swap; this metric is for shipped agents, not new ones.
**explore.**

**E11. Spread index in candidate sets.** *(B26)* *Threshold:*
candidate set shows meaningful axis variation (semantic-similarity
or tool-based). *Corrective:* low → agent prompt widens or a
different generator is used. *Actor:* the rendering pipeline
itself, before reaching human. **explore — needs tooling (V1).**

**E12. Hypothesis-resolution rate.** *(B16, V1 caveat)* *Threshold:*
ratio of agent-merged changes that resolve a stated hypothesis.
*Corrective:* low → spec quality investigation. *Actor:* pack
maintainer. *Caveat:* circular dependency on B4 — only works if
hypothesis docs exist. Land with B4 or not at all. **explore.**

## I. AI-native additions (V2 prior art + V4 invention)

V2 surveyed Karpathy, Willison, Anthropic engineering, OpenAI Agents
SDK, LangChain ambient agents, Cursor, Replit, Hamel Husain, Eugene Yan,
Geoffrey Litt, Tobi Lütke, the Vaccaro meta-analysis. V4 mapped the
genuinely AI-native problems with no clean human precedent. The
combined set is below.

Full reports: `docs/research/v2-ai-native-prior-art.md`,
`docs/research/v4-ai-native-inventions.md`.

### From V2 (prior art)

**I1. Escalation class taxonomy: Notify / Question / Review.** *(V2 B27,
LangChain ambient agents)* Every escalation declares its class. Notify
is batchable and async; Question pauses agent until answered; Review
precedes an irreversible action and must complete before the action.
Harness routes by class — Notify lands in a daily digest, Question in
an inbox, Review on a synchronous attention surface. Replaces the
pack's single "escalate" verb. **strong.**

**I2. Autonomy slider as a per-task setting.** *(V2 B28, Karpathy +
Levels-of-Autonomy 2025)* Per-task choice: *suggest → propose → act-
with-approval → act-then-report → ambient*. Agent behavior — when to
surface, what to render — is a function of the slider, not hard-coded.
The pack's posture becomes parametric, not monolithic. **strong.**

**I3. Eval-diff as the closure unit.** *(V2 B29, Hamel/Yan/Anthropic)*
Sharpens B15. Every closed escalation must add (or modify) a held-out
eval case that would have caught the original miss. The eval set is
the durable memory. Without this, B18/V4-N2 has no source of training
pressure. **strong.**

**I4. Context-window hygiene via sub-agents and lazy-loaded skills.**
*(V2 B30, Anthropic)* Treat the main agent's context as a scarce
shared resource. Verbose work happens in sub-agents; specialized
knowledge loads on demand from skills; hooks enforce gates without
occupying tokens. The pack's T1 (human attention scarce) gets a
sibling: **agent context is also scarce and rivalrous.** **strong —
candidate for foundation-level addition (T4 territory).**

**I5. Lethal trifecta gate.** *(V2 B31, Willison)* Any agent design
combining (private data) + (untrusted content) + (external
communication) must declare which leg it severs. No exceptions.
Structural/poka-yoke gate at design time, not a prompt-level check.
Sharpens B19. **strong.**

**I6. Snapshot-as-undo for live-environment agents.** *(V2 B32, Replit)*
Agents that mutate real state operate inside a snapshotted environment
with explicit roll-back, not just git revert. The recovery unit is the
*world state*, not the *commit*. Extends B5 from plan-state to
runtime-state. **lean+.**

**I7. Per-tool approval class as a typed signature.** *(V2 B33, OpenAI
Agents SDK)* Every tool declares its approval class in its signature:
*auto / notify / approve / refuse*. The harness enforces; the model
cannot escape via re-prompting. Sharpens B6 — the trigger is a type,
not a runtime decision. **strong.**

**I8. Reviewer-skill cultivation as an explicit pack concern.** *(V2
B34, Lütke + Vaccaro 2024)* Empirically, human-AI teams underperform
without practiced humans. A practice: track reviewer accuracy (caught
vs. missed defects, overrides that turned out wrong) and use it as
input to coaching. Reviewer skill is a learned craft, the pack
should cultivate it. **lean+.**

**I9. Notification budget for ambient agents.** *(V2 B35, Litt +
LangChain)* Long-running proactive agents accumulate the right to
interrupt. Cap that right: a daily/weekly notify budget, with
overflow batched into digests. Pairs with I1. **lean+.**

### From V4 (AI-native invention — no human precedent)

**I10. Prompt-as-evaluated-artifact.** *(V4 N1)* Every prompt and
skill ships with an eval suite committed alongside it. The eval, not
the prompt text, is the durable spec. A prompt change without an
eval change is rejected the way a code change without tests is.
Genuinely AI-native — no other artifact class needs statistical
correctness gates by construction. **strong.**

**I11. Cross-model regression suite per skill.** *(V4 N2)* Skills
declare their supported model set and carry a small behavioral-
assertion battery run on every model upgrade. Drift above threshold
blocks rollout and triggers coached rewrite. Borrowed disciplines
have nothing to say about substrate drift. **strong.**

**I12. Structural reversibility surface for irreversible classes.**
*(V4 N3)* Irreversible action classes (send, charge, deploy, publish,
drop) reachable only through a staged surface — declared budget plus
dry-run preview, or human release. Naked tool bindings to
irreversible APIs are a pack-level violation. R4's spirit ("cheap
restart"); the harness-level surface is the AI-native extension.
**strong, overlaps with I7.**

**I13. Bounded autonomy windows with harness-enforced backpressure.**
*(V4 N4)* Every agent run declares its autonomy budget (steps, files,
time, dollars). On any limit the agent parks and produces a sweep-
ready summary. The harness blocks new starts when the human-review
queue is deep. HFT risk-gate genealogy, not Toyota. **strong,
overlaps with I2.**

**I14. Calibrated trust ledger per skill.** *(V4 N5)* Per-skill
ledger: acceptance rate, calibration of stated confidence, alignment-
sensitive escalation precision. Review intensity flexes against the
ledger — trajectory review for low-trust or alignment-sensitive
classes; sampled review for mature, calibrated skills. The AI-native
answer to "trust an actor with no reputation." **strong, sharpens
B23 / E10.**

### Overlaps to resolve in selection

- **I2 + I13** → autonomy framing. I2 is the user-facing dial; I13
  is the harness-enforced budget. Likely both, paired.
- **I7 + I12** → typed approval surface. I7 is the per-tool
  signature; I12 is the staged surface for irreversible classes.
  I7 + I12 + I5 (lethal trifecta) form the safety surface.
- **I3 + N2 + B18** → eval-as-memory. I3 is closure-time eval add,
  I11 is per-model regression, B18 is held-out adversarial. They
  compose into a single "eval lifecycle" practice.
- **B23 + I14** → trust calibration. I14 is the more concrete
  framing; B23 alone is metric-without-corrective per V1.

## J. V3 Skeptic — hidden producer-side assumptions

V3 (full report: `docs/research/v3-skeptic.md`) names the structural
assumption shared by *all* the borrowed disciplines in R1–R5: that
the producer is **deterministic, reproducible, finitely-set, legibly-
fidelitous, and the bottleneck**. AI agents violate all five
simultaneously.

**J1. Non-determinism breaks reproducibility-based postmortems.**
*(R5 COE, R4 ROC)* COE assumes you can re-run the failure; the
agent's failure may not be reproducible (Thinking Machines batch-
invariance result, context rot). The Five Whys terminates at "the
model predicted that token." *Implication:* COE for agents must
include distribution-of-outcomes data, not single-trace, and treat
non-reproducibility as the default.

**J2. Posterior sampling breaks contact-sheet finiteness.** *(R3)* A
photo contact sheet has 36 frames; an LLM has an infinite posterior.
"Generate-N-and-pick" samples a slice, not exhausts a set. *Implication:*
the spread requirement (B26 / E11) is load-bearing; without it the
contact sheet is decorative. Also: rerun-with-different-seed is a
sibling of "more candidates."

**J3. "Good from afar" breaks recognition-over-reading.** *(P3)*
Empirical evidence (NN/g; 61% of devs report AI code "looks correct
but isn't reliable") shows AI artifacts pass recognition's surface
filter but fail on closer read. *Implication:* P3 needs co-practices
that make the close-read cheap (rendered tests, behavior traces,
type-checks) — recognition without verification is more dangerous
than slow reading.

**J4. The cost flip may be over-claimed.** *(premise)* METR's RCT
showed experienced devs 19% slower with AI while *believing* they
were 20% faster. The pack's premise that "agent labor is near-free,
attention isn't" is empirically defensible but needs to flag that
the *measurement* of cost is itself unreliable. *Implication:* track
actual outcomes (B16 hypothesis-resolution, E6 override rate), not
self-report.

**J5. The peer-not-tool framing.** *(Karpathy, Litt)* Shop-floor
metaphors (andon, kanban) silently assume the producer has no
opinion about its own oversight. AI agents have opinions. *Implication:*
the agent posture (Section D) should accommodate the agent
challenging the gate, not just submitting to it. This argues against
D2/D4 (subordinate-flavored metaphors) and toward D1/D3 (peer-
flavored).

**J6. Borrow-as-hypothesis, not borrow-as-default.** The strongest
synthesis: every borrowing should be treated as a hypothesis to
*falsify* against AI-specific pathologies, not a prior to relax from.
This is a tightening of the Premise. *Implication:* candidate
addition to M3 — every borrowed pattern *also* declares a
falsification test (a specific AI failure mode that would invalidate
the borrow).

---

## F. Cadence candidates

Each cadence below names its M1 attention claim. Cadences without a
priced bound default to "rejected — won't survive contact with use."

**F1. Per-task: hypothesis + lineage label.** *(B4 + B12)* Before
generation. *Cost:* ~5 min on substantive tasks; skipped for trivial
ones (size threshold required, V1 caveat). **strong, scoped.**

**F2. Per-task: hansei reflection block.** *(R1)* Agent self-authors a
short post-task self-criticism. *Cost:* ~1 min agent, 0 human unless
flagged. **lean+ — agent-side, low human cost.**

**F3. Per-event AAR.** *(B14)* Within 1 working day of a surprise.
Triage gate prevents flood — limit one AAR per reviewer per
working day; overflow batches into F6. *Cost:* ~10–20 min human +
~5 min agent. **strong with triage.**

**F4. Per-prompt-change: eval run.** *(I10)* Automated gate; no merge
without eval pass. *Cost:* 0 human unless eval fails. **strong.**

**F5. Per-model-upgrade: cross-model regression.** *(I11)* Automated
behavioral-assertion battery. Drift blocks rollout. *Cost:* 0 human
unless drift detected; coached rewrite if so. **strong.**

**F6. Weekly batch: AAR → COE distillation.** *(B14)* Read the
accumulated AARs; produce 1–2 full COEs on recurring patterns. *Cost:*
~1 hour weekly. **strong; this is where T3 (the pack learns) actually
drives.**

**F7. Weekly: ambient-agent notify digest.** *(I9)* Batched
notifications from long-running agents delivered on a fixed cadence.
*Cost:* ~10–20 min weekly. **lean+ if ambient agents are in scope.**

**F8. Monthly: trust ledger + metrics review.** *(I14, E1–E12)* Read
per-skill calibration, override rate, kill rate, repeat rate, closure
latency. Adjust review intensity per skill. *Cost:* ~30–60 min
monthly. **lean+.**

**F9. Triggered-on-anomaly: skill audit.** *(synthesis)* When a metric
crosses threshold (kill rate too low, repeat rate too high, calibration
drift), audit the relevant skill. Triggered, not scheduled. *Cost:*
variable; bounded by triage. **lean+.**

**F10. Quarterly meta-review for repeats.** *(B17 with V1 caveat)*
V1: will lapse without forcing function. Either tie to existing
rhythm (release window, sprint review) or fold into F8 monthly.
**explore — fold into F8 unless tied to a forcing function.**

**F11. On-demand: coach session.** *(B21 + V1 M5)* Triggered by
F8/F9 anomalies; output is required to be a B15-style merged artifact
diff (skill, gate, fewshot, eval). Without that closure, the session
didn't happen. **lean+ — must terminate in artifact per M5.**

*Cadence summary by attention claim per week:*
- Per-task (F1, F2): scales linearly with task volume; F2 mostly
  agent-side. F1 is the human cost.
- Per-event (F3): bounded by triage to ~5/week max.
- Weekly (F6, F7): ~1.5 hr/week.
- Monthly (F8): ~1 hr/month → ~15 min/week amortized.
- Automated (F4, F5): 0 human cost on green path.

Total expected human cadence cost: ~2–3 hours/week steady-state plus
per-task hypothesis effort (highly variable by task profile).

---

## G. Anti-patterns to name

Failure modes the pack should explicitly name and surface. Each is a
trap the practices are designed to avoid; naming them helps users
catch the drift before it sets.

**G1. Lean theater.** *(R1, V1 C5)* Adopting visible artifacts (A3,
COE template, andon cord, kanban board) without the social
infrastructure that gives them meaning. Counter: every borrow flags
its disanalogy and names the social discipline it depends on (M3).

**G2. Just-restart.** *(R4 counter, V1)* Re-rolling the dice on a
flaky agent until a plausible diff appears, instead of fixing the
prompt, the tools, or the spec. Cheap restart without root-cause is
technical debt with a friendly UX.

**G3. Vanity demos.** *(R2 counter)* Optimizing for the next
stakeholder screenshot over production behavior. AI corollary:
impressive UI, brittle code. Counter: lineage labels (B12/C8); the
spike never auto-promotes.

**G4. Prototype-as-spec.** *(R2, R3 counter)* AI-generated artifact
looks polished and shippable; stakeholders treat it as a finished
requirement; subsequent work inherits its accidental decisions.
Counter: lineage labels and explicit upgrade ritual.

**G5. Editor sycophancy / homogenization.** *(R3 counter,
Filterworld)* Picking what last week picked. The contact sheet that
always returns similar candidates extinguishes outliers. Counter:
spread requirement (B26/E11) and brand-fit-trap awareness.

**G6. Decision fatigue / mid-curation drift.** *(R3)* Reviewer
reviews 30 candidates in a sitting → rubber-stamps the last ten.
Counter: triage gates on F3, attention-budget meta-rule (M1),
rotate reviewers when feasible.

**G7. Five-Whys linearity trap.** *(R5, Cook 2002)* A single causal
chain feels satisfying and obscures the actual multi-factor texture.
Counter: pair Five Whys with contributing factors enumeration; for
serious events, STAMP/CAST.

**G8. Blame leakage despite blameless framing.** *(R5, Dekker)*
"The model hallucinated" is the AI equivalent of "human error" —
a stop-thinking phrase. Counter: ask "what made this the rational
output given the prompt + context + tools the agent had?"

**G9. Spec-as-training-data.** *(R5 counter)* COE corpus included in
agent context → agent learns surface forms, not underlying pattern
(teaches to the test). Counter: held-out adversarial eval
(B18/I3).

**G10. Metric-without-corrective.** *(V1 C2)* Already named as M2.

**G11. Attention-budget overdraft.** *(V1 C1)* Already named as M1.

**G12. Coaching without retention closure.** *(V1 C4)* Already named
as M5.

**G13. Pre-commit-paralyzes-discovery.** *(V1 C3)* Pre-commit weights
work for measurable axes; they suppress recognition for ambiguous
ones. Already named as M4.

**G14. Lethal trifecta.** *(Willison, I5)* Private data + untrusted
content + external comms in the same agent design.

**G15. Vanity confidence.** *(B23 + V1)* Stated confidence without
calibration is worse than no confidence — it gives reviewers false
warrant. Counter: I14 trust ledger.

**G16. Treating the contact sheet as exhaustive.** *(V3 J2)* Five
candidates is a slice of a posterior, not a closed set. Counter:
spread (B26), rerun-with-different-seed as sibling of "more
candidates."

**G17. Recognition without verification.** *(V3 J3)* "Good from afar."
NN/g findings + 61% of devs report AI code looks correct but isn't
reliable. P3 alone is dangerous; pair with cheap close-read paths.

**G18. Self-report cost flip.** *(V3 J4, METR 2025)* Devs 19% slower
with AI while feeling 20% faster. Counter: track outcomes (E6, B16),
not satisfaction.

**G19. Notification creep.** *(V2 I9)* Long-running agents accumulate
the right to interrupt. Counter: notify budget (I9).

**G20. Skill drift across models.** *(V4 I11)* What worked on the
old model may not work on the new. Without regression suites, drift
compounds silently.

**G21. Naked binding to irreversible APIs.** *(V4 I12)* No staged
surface; tool can fire `send_email()` or `drop_table()` directly.
Counter: structural reversibility (I12) + per-tool approval class
(I7).

**G22. Agent self-adjudication.** *(R5, M5)* Agent authoring the COE
about itself. Counter: agent is witness, human is author (B22).

**G23. Senior-reader exhaustion paradox.** *(V1 B20)* The senior
reader doing one-hard-question discipline is the same human T1 is
trying to protect. Counter: scope to multi-person settings; solo/
small-team needs a different mechanism.

**G24. P3-violation-by-prose.** *(synthesis)* Agent presents
candidates as a paragraph instead of rendered artifacts. Counter:
P5 render-first sub-rule (A8/B3).

**G25. Cargo-culted vocabulary.** *(M3, V1 C5)* Borrowing "kata,"
"andon," "nemawashi," "COE" without flagging the disanalogy at the
borrow site. Counter: M3 disanalogy-flagging discipline.

---

## H. Open questions / candidates needing more research

These surfaced during ideation but don't yet have enough grounding to
land. Most are candidates for a second-round agent run or for picking
up after first use generates real patterns.

**H1. M4 decision rule grounding.** *(V1 C3)* The pre-commit-vs-
discovery split is named; the heuristic — "measurable axes pre-commit;
ambiguous axes discover" — needs concrete examples and a clear test.
Worth a short agent run on Pugh-matrix + design-critique boundary
conditions.

**H2. The senior-reader question for solo / small-team settings.**
*(V1 G23, B20)* B20's senior-reader hard-question discipline assumes
≥2 humans. What's the small-team / solo equivalent? Candidates: agent
as devil's-advocate reviewer (with disclosure); cross-pack peer
review; a skill that runs a structured critique against the COE
itself. Worth research.

**H3. I1 (Notify/Question/Review) in non-ambient settings.** The
typology came from ambient agents. Does it map cleanly to interactive
coding sessions where the user is actively engaged and "pause until
answered" has a different meaning? Agent-routing-by-class needs
worked-through examples.

**H4. Spread-index implementation.** *(B26/E11/G16)* Who/what
validates that candidates show meaningful axis variation? Embedding
similarity? LLM judge? Categorical taxonomy per task class? Tooling
gap.

**H5. Eval-diff overfitting.** *(I3/I10)* "An eval that would have
caught the original miss" risks teaching to the test (G9). How
generic should the eval be? Worth a research run on the eval-design
literature (Husain, Yan, OpenAI evals, Hugging Face evals).

**H6. The posture metaphor (parked).** *(D)* Section D has 8
candidates. User has previously parked this. Likely defer until first
use surfaces what the practices need a metaphor *for*.

**H7. Multi-agent coordination at the development boundary.** *(V4
§1)* The pack hasn't decided how to handle 3 concurrent agents on
overlapping branches. AutoGen / LangGraph multi-agent patterns vs.
single-agent-with-sub-agent decomposition. Probably blocked by first
use.

**H8. Skill schema mapping.** *(C1–C17 → pack-v2)* What does each
candidate skill look like in `skills/<name>/SKILL.md` format? Front-
matter? Section conventions? Hooks integration? Need a worked
example before scaling.

**H9. Plan-doc (B5/C6) vs. existing scratchpads.** Many harnesses
already have planning UIs (TodoWrite, ExitPlanMode, Cursor's TODO,
Aider's chat history). How does the pack's plan-doc integrate vs.
duplicate? Probably needs a per-harness adapter, not a single
universal format.

**H10. T2 grain.** "Human owns the clock" is true but flat. The
human's bandwidth varies by time-of-day, focus state, project
load. Does T2 need a grain — burst-capacity, deep-work-hours,
notification windows? Worth thinking through after first use.

**H11. Pack defaults vs. per-project configuration.** Which
practices are universal (e.g., M1 attention budget, I5 lethal
trifecta), which are per-project (e.g., F8 monthly cadence, I9
notify budget)? Needs a clear taxonomy in the eventual user-facing
doc.

**H12. T4 candidate: agent context is also scarce.** *(I4)* V2
explicitly proposed this as a sibling principle to T1. Tenets are
supposed to stay small (v0 said three). Does context-scarcity earn
a fourth? Or does it land as a practice rooted in T1? Strong
candidate for foundation-level, but the user has explicit constraints
on tenet count. Bring back when ready.

**H13. Metaphor / posture / role distinction.** Section D conflates
three different things. A *metaphor* (chief of staff) is a
communication tool; a *posture* (opinionated, deferential, peer) is
a behavior pattern; a *role* (concierge, architect, mechanik) is an
assignment in the agent roster. Each needs a separate treatment.

**H14. Reviewer-skill cultivation without dignity cost.** *(I8)*
Tracking reviewer accuracy as a metric makes the reviewer a measured
object. How do we cultivate reviewer skill without surveillance
overhead? Probably needs the reviewer to *opt in* and be the primary
audience for the data.

**H15. Pack ↔ existing agent roster (concierge / architect /
mechanik) integration.** Which practices live at the foundation
level, which at the agent-role level, which at the skill level?
Worked examples needed.

**H16. Falsification tests for borrowed patterns.** *(V3 J6)*
Strengthening of M3: every borrowed pattern declares not just its
disanalogy, but a specific AI failure mode that would invalidate the
borrow. Worth turning into a candidate practice.
