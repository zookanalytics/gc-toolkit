# V5 — Inversions Within: ROC's Framing Move Applied to the Pack

> **Status: drafting.** Recovery-Oriented Computing did not just propose
> patterns; it inverted the dominant frame (MTBF → MTTR) and let the
> downstream patterns fall out. This doc applies that move to the pack
> itself: it names the framings the pack takes for granted, inverts each,
> and asks which inversions generate genuine insight rather than mere
> provocation.

---

## Summary

[pending]

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

[pending]

### I8. Pack as refined corpus → Pack built to be replaced

[pending]

---

## Recommendations

[pending]
