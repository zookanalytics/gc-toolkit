# V5 — Inversions Within: ROC's Framing Move Applied to the Pack

> **Status: drafting.** Recovery-Oriented Computing did not just propose
> patterns; it inverted the dominant frame (MTBF → MTTR) and let the
> downstream patterns fall out. This doc applies that move to the pack
> itself: it names the framings the pack takes for granted, inverts each,
> and asks which inversions generate genuine insight rather than mere
> provocation.

---

## Summary

ROC's move was not a pattern; it was a *burden-of-proof flip*. Applied
to the pack, the most generative inversions are the ones that flip a
similar burden. **I1 (borrow-as-suspect, not borrow-as-default)** flips
the evidentiary burden from departures to borrowings and gives V3's
skeptical case a procedural shape. **I6 (optimize the no-consult
path)** flips the measurement target from the visible 5% (consults) to
the silent 95% (autonomous decisions), giving G1 a real metric beyond
"escalations down." **I3 (agent escalates back into the human's
framing)** flips the directionality of the consult itself — the agent
challenges the question, not just answers it. These three are the
strongest because each generates concrete practice changes that the
pack does not currently have, each addresses a real failure mode V1 or
V3 surfaced, and each is bounded enough to pilot without ripping out
v0. The remaining inversions (I2 attention/judgment, I4 deliberate
forgetting, I5 cheap judgment, I7 peer-flat, I8 rewrite cycle) range
from partially generative to provocative-but-deferrable.

---

## Inversion catalog

### I1. Borrow-as-default → Borrow-as-suspect

**Dominant frame.** The Premise treats fifty-to-a-hundred-year-old
organizational patterns (Toyota, COE, photography, ROC, cheap prototyping)
as the *default*: inspiration and guidance, not law, but departures must
earn their place. The burden of proof sits with the departure.

**Inverted frame.** Every borrowing is a hypothesis to *falsify* against
AI-specific pathologies. The burden of proof sits with the borrowing. A
practice is admitted only after it survives a documented falsification
test against non-determinism, open-set sampling, hidden-fidelity output,
or the constraint flip.

**What it generates.** M3 (disanalogy flagging) becomes a *falsification
test*, not a footnote. Every R1–R5 borrow ships with a named AI failure
mode that would invalidate it (e.g., "B6 andon assumes detectable
abnormality; falsified if hallucinations pass shape-defect gates >5% of
the time"). The research log gains a column: *what would have to be true
for this borrow to be wrong?* Practices that cannot articulate that test
are quarantined as "ritual under examination" rather than admitted to the
pack. V3 J6 already gestured at this; the inversion makes it the default
posture rather than a tightening of M3.

**Worth taking seriously?** Yes — high. This is the cleanest application
of ROC's move. ROC didn't ban MTBF work; it inverted who carried the
burden. The same shift here turns the pack from a curated borrow-set into
a discipline of *active skepticism toward its own ancestry*. V3 already
makes the case; the inversion gives the case a procedural shape.

### I2. Attention-scarce → Attention-abundant; judgment-scarce

**Dominant frame.** T1 declares attention the only scarce resource;
every practice prices its claim against it. The pack reads attention as
the bottleneck because agent labor went to zero, leaving the human as
the slow step.

**Inverted frame.** Suppose attention were *abundant* — a focused
operator with hours of unbroken time — but *judgment* (the right
question to ask, the right axis to optimize) were the scarce resource.
What would the pack price against?

**What it generates.** A different practice surface. P3 (recognition
over reading) is no longer about saving keystrokes; it is about *forcing
the operator to encounter axes they did not pre-name*. P2 (opinion +
options) becomes less about cheap traversal and more about ensuring the
agent's recommendation is *contestable* — that it provides the seam an
under-judging human can pry open. The cadence layer (F-series) shifts:
fewer attention-bounded rituals, more *discovery-bounded* rituals where
the corrective is "did this run produce a question the team did not have
yesterday?" V1 already flagged metric-without-corrective; under this
inversion, the missing corrective is usually a judgment-development
move, not an attention-recovery move.

**Worth taking seriously?** Partially. Attention is in fact scarce —
T1's empirical grounding is solid (METR, Security Boulevard). But the
inversion exposes a real blind spot: T1 prices everything against
attention *cost* and underweights *judgment formation*. G2 ("the best
consults catalyze ideas neither side started with") already gestures at
this; the inversion sharpens it. Worth surfacing as a sub-tenet or
co-goal: **the pack should produce judgment, not just preserve
attention.** Without this, T1 silently selects for the cheapest possible
consult, which is also the consult that develops the operator least.

### I3. Agent surfaces, human decides → Human surfaces, agent decides what to escalate

**Dominant frame.** The pack's directionality is fixed: agent generates,
filters, and surfaces; human adjudicates. P1 ("surface only what only
the human can answer") encodes this. Escalation flows from agent up to
human.

**Inverted frame.** The human surfaces (intent, ambiguity, half-formed
hunch); the agent decides what to escalate *back* — what part of the
human's stated intent is internally inconsistent, under-specified, or
contradicted by the codebase. Escalation flows from agent *toward* the
human's own thinking.

**What it generates.** A new escalation class beyond Notify/Question/
Review (I1): *Reflect.* The agent ships a one-line "your stated goal X
conflicts with constraint Y you mentioned three turns ago — which
governs?" before generation, not after. C1 (Hypothesis A3) becomes a
*two-way* artifact: the human drafts hypothesis; the agent annotates
with structural objections; the human revises. P2 inverts in spirit —
the agent expresses an opinion *about the human's framing*, not just
about candidate solutions. This naturally couples with V3 J5 (peer
framing): a peer challenges the question, not just the answer.

**Worth taking seriously?** Yes — high, but bounded. The pack already
has the seed (G2's "catalyze ideas neither side started with") but
behaviorally trends toward the asymmetric default. The risk is that
agents over-challenge framing for low-stakes work and burn the very
attention budget T1 protects. Bound it: *Reflect-class escalations are
permitted only when the agent's confidence in a structural conflict
exceeds a threshold*, and they are dispatched as a single batched
question, not a stream. With that bound, this is one of the strongest
inversions on the list — it changes what the agent is *for*.

### I4. Pack learns from observation → Pack deliberately forgets

**Dominant frame.** T3 says the pack learns or it stops fitting.
Yesterday's right answer is tomorrow's friction; the engine of G1 is
accumulation. M5 makes this concrete: every coaching session terminates
in a merged artifact diff. The implicit direction is monotonic — skills,
gates, fewshots, evals all grow.

**Inverted frame.** The pack *deliberately forgets.* Skills, gates, and
fewshot examples are admitted with *expiration tags* and pruned on a
fixed cadence. The default action on a stale artifact is delete, not
review. The pack defends its own simplicity against accumulation.

**What it generates.** A garbage-collection cadence (F-series addition):
quarterly skill-review where each skill must be re-justified against
last quarter's actual usage. Skills with zero invocations or with
calibration drift greater than a threshold (E10/I14) are removed, not
patched. Fewshot examples carry a "valid through model X.Y" tag; on
model upgrade (I11) they are *re-validated or dropped*, not migrated.
The COE corpus (B14/C5) gets a dedup pass — repeated patterns collapse
into a single canonical lesson and the duplicates are deleted. G9
(spec-as-training-data) gets a structural answer: forgetting is the
mechanism that prevents the agent from memorizing surface forms.

**Worth taking seriously?** Yes — surprisingly high. The borrowed
disciplines all assumed retention was the problem; under context rot
(V3 §2) and skill drift (G20), retention *is* the problem. A pack that
only accumulates becomes the cargo-cult corpus M3 was designed to
prevent. The pruning move is also load-bearing for I4 (context-window
hygiene) — agent context is rivalrous, so every skill the pack retains
costs the agent something at runtime. ROC's spirit applies: stop
optimizing MTBF (long skill life), start optimizing MTTR (rapid
turnover from observation to skill, and from stale skill to deletion).

### I5. Cheap execution / expensive judgment → Cheap judgment too

**Dominant frame.** The Premise's load-bearing asymmetry: agent labor
is near-free, attention isn't. The cost flip is real but *one-sided* —
execution went to zero, judgment stayed expensive. Practices fit that
asymmetry.

**Inverted frame.** Suppose judgment also got cheap — model-as-judge
(eval scoring), agent debate, large-N self-critique pipelines. What
would the pack stop doing? What would it start doing?

**What it generates.** A different practice surface for *what only the
human can answer* (P1). If model-judges can adjudicate UX consistency,
code-shape, intent clarity at acceptable accuracy, the meaning-defect
class (A5) shrinks. The human's role concentrates on *what no judge can
yet score*: irreversible commitments, value tradeoffs, taste at the
brand level, the question of whether the goal itself is right.
Practices like B22 (agent as witness, human as author) get sharper —
the human authors the things judgment cannot be cheapened on, full
stop. P3 (recognition over reading) stays load-bearing for those, and
shrinks for the rest. The pack also gains a *judge calibration
practice* parallel to I14 — judges drift just as agents do.

**Worth taking seriously?** Mixed. Judgment *partially* got cheap
already (LLM-as-judge in eval pipelines is mainstream); the inversion
is forecasting, not invention. The risk of taking it too seriously is
J1/G8 in disguise — "the judge said it was fine" laundering decisions
the same way "the model hallucinated" launders failures. The pack
should track judgment-cheapening as a *direction-of-travel* and
sharpen P1 to name what stays human even if every other axis becomes
score-able. Provocative, partially generative; the strongest yield is
forcing the pack to articulate the *un-cheapen-able* core.

### I6. Consult-centric → The negative space (work that does not consult)

**Dominant frame.** The pack is named "Escalation Foundation"; its
practices, metrics, and cadences orbit the consult — when to surface,
how to surface, how to close. G1 measures escalations; G2 equips the
human at the point of consult; P1–P6 shape what a consult looks like.

**Inverted frame.** Optimize for the work that *never enters the
consult queue*. The pack's quality is measured by what the agent
correctly handles silently — successful runs, unflashy completions, the
quiet 95% — not by the visible 5% that surfaces.

**What it generates.** A "silent ledger" practice: agents log
non-escalated decisions with rationale at sampling rate, not full rate;
a periodic audit (F8 monthly) reads a random sample. The corrective is
the inverse of E2 (cull rate): *too few silent decisions* means the
agent is over-escalating (T1 violation); *too many silent decisions
that turn out wrong on audit* means gates are too lax. Skills are
evaluated on *silent precision*, not just consult quality. M1
(attention-budget pricing) gets a sibling: M1' — every skill prices
its silent-error rate, and that rate must be lower than the
pre-skill baseline. Effectively this introduces an SLO for autonomous
operation, distinct from the SLO for consults.

**Worth taking seriously?** Yes — high. This is the closest analog to
ROC's exact move: ROC stopped optimizing the failure-free path (MTBF)
and started optimizing the recovery path (MTTR). The pack currently
optimizes the consult path; the inversion says optimize the *no-consult
path*. Without this measurement, G1's "fewer escalations" reads
ambiguously (A1 already named the failure mode: zero escalations could
mean perfect work or hidden defects). Silent-precision audits resolve
the ambiguity and put real evidence behind the trend. This pairs
naturally with I14 (calibrated trust ledger) and gives the trust ledger
its forcing function.

### I7. Escalation = lower → higher → Peer-flat: escalation is just request

**Dominant frame.** The vocabulary "escalation" implies a hierarchy:
agent at a lower level, human at a higher one. The agent submits;
the human adjudicates. P1's "only what only the human can answer" and
B22's "agent as witness, human as author" both encode this asymmetry.

**Inverted frame.** Drop the verticality. The agent and human are
peers with different competencies. What looks like "escalation" is just
a *request between equals* — the agent asks because the human is the
specialist on this axis, not because the human is above the agent.
Symmetrically, the human consults the agent because the agent is the
specialist on volume, recall, and code structure, not because the
agent is below.

**What it generates.** The vocabulary changes: "consult" replaces
"escalation" everywhere. The agent gets a parallel surface for
*requesting human input* on its own terms — "I need a decision on X
because it's a value tradeoff, not because I failed." More
substantively, the agent gains license to *decline* a human request
when the request would burn the agent's most scarce resource (context;
I4) without justification. P2's "opinion alongside options" extends:
the agent may withhold options if the question is malformed, and ask
for reframing instead — same way a peer would. V3 J5 (peer-not-tool)
is exactly this argument; the inversion makes it operational.

**Worth taking seriously?** Yes — moderate. The vocabulary fix is
cheap and clarifying; "consult" is more honest than "escalation" and
already partially in use. The deeper move (agent declines human
requests) is risky because authority asymmetries are not just framing —
the human owns outcomes the agent does not, and the legal/operational
buck stops there. Take the vocabulary; defer the authority shift until
trust ledgers (I14) and silent-precision data (I6 above) make the
peer claim defensible per skill. Adopt the renaming; treat the deeper
inversion as a direction-of-travel.

### I8. Pack as refined corpus → Pack built to be replaced

**Dominant frame.** The pack is a stable surface that *refines* over
time. v0 is locked; subsequent rounds tighten and extend. T3 (the pack
learns) implies incremental sharpening — yesterday's right answer
becomes tomorrow's friction, but the *form* of the pack persists.

**Inverted frame.** The pack is built to be *replaced wholesale* on a
short cycle. Every six months (or every model generation), the
foundation document is rewritten from scratch by an agent run against
the accumulated AAR/COE corpus, and the previous version is
*archived*, not iterated. The pack's value is in the *current
formulation*, not in its lineage.

**What it generates.** A "rewrite cadence" alongside the refine
cadence. The unit of versioning is not a tightening but a *fresh
synthesis*. The archive becomes a research input to the next pack, not
the spine of the current one. Practices like M3 (disanalogy flagging)
and M5 (coaching-terminates-in-artifact) stop being cumulative and
start being *re-derived* each cycle — if a borrow can no longer
justify itself in the current model regime, it doesn't migrate forward.
Skills, gates, and fewshots get a fresh-eye review at each rewrite,
which composes naturally with I4 (deliberate forgetting).

**Worth taking seriously?** Mixed. The full version is too costly —
foundation rewrites are expensive in the only currency T1 protects.
But a *bounded* version of this is generative: every twelve months,
hold a "pack rewrite" exercise where an agent drafts the next-version
foundation from the AAR corpus and the current foundation, and the
team chooses what to migrate forward *by exception*, not by default.
This inverts the migration burden the same way I1 inverts the
borrowing burden, and it operationalizes T3 in a way the current
"learning" framing leaves vague. Worth piloting, not adopting wholesale.

---

## Recommendations

The pack should consider adopting three of the eight inversions, each
in a bounded form. They compose: I1 raises the bar for what enters the
pack, I6 measures whether what's in the pack is actually working, I3
changes what the consult is *for*.

**Adopt I1 — burden of proof on the borrow.** Concretely: extend M3
from "flag the disanalogy" to "name a falsification test." Every
R1–R5-derived practice in `escalation-ideation.md` gets one inline
sentence of the form "*This borrow is wrong if [specific AI failure
mode] occurs at rate above [threshold].*" Practices that cannot
articulate that test are not cut, but they sit in a "ritual under
examination" status until they can. This is the cheapest inversion to
adopt — it is a documentation discipline — and it neutralizes the
single biggest risk V3 named (cargo-culted vocabulary, premise
overreach). Cost: a few hours per practice on first pass, near-zero
ongoing. Yield: V3's skeptical case becomes structural, not advisory.

**Adopt I6 — measure the no-consult path.** Concretely: add a
*silent-decision audit* practice to the F-cadence. A monthly sample of
non-escalated agent runs gets human review against three questions:
*Should this have escalated? Was the chosen path defensible? Would the
human have chosen differently?* The audit feeds the trust ledger
(I14/E10). This gives G1 ("fewer escalations, each higher-value") a
real measurement instead of a directional hope, and it resolves A1's
"zero escalations is a failure mode" concern with evidence rather
than aphorism. Cost: ~1 hour/month at sample rate of ~10 runs. Yield:
the pack stops flying blind on the 95% of agent work that never hits
the consult queue, which is where most of the actual quality lives.

**Adopt I3 (bounded) — license the Reflect-class consult.** Concretely:
add a fourth escalation class to I1's Notify/Question/Review:
*Reflect.* Used only when the agent identifies a structural conflict in
the human's stated intent (goal contradicts constraint, plan
contradicts spec, current request contradicts prior decision).
Bounded: at most one Reflect per task, dispatched as a single batched
question before generation begins, suppressed below a confidence
threshold. The Reflect class makes G2's "catalyze ideas neither side
started with" operational and gives the agent a structured way to
challenge framing without burning attention budget on every turn.
Cost: schema change to the escalation surface, prompt-side discipline
to suppress over-firing. Yield: the consult occasionally produces a
better *question*, not just a better answer, which is where the
highest-value escalations actually live.

The remaining inversions are not rejected — I4 (deliberate forgetting)
and I7 (peer vocabulary) are particularly worth revisiting once the
trust-ledger data exists to support them. But the three above are the
ones whose insight is concrete enough, bounded enough, and forcing
enough to land now without disrupting v0's foundation.
