# V3 Skeptic — The Strongest Case Against the Pack's Premise

> **Status: drafting.** Steelman of the case that organizational wisdom does
> NOT transfer cleanly to AI-assisted development, and that AI-native work
> needs genuinely new patterns rather than borrowed ones. Sources are real
> practitioners and writers; critiques are theirs, not manufactured.

---

## Summary

The strongest case against the pack's premise is not that organizational
wisdom is irrelevant, but that the borrowed disciplines all share a hidden
assumption — *the producer is a deterministic, reproducible, finite-output
system whose defects have causal closure* — and AI agents violate every
clause of that assumption simultaneously. Toyota's andon, Amazon's COE,
photography's editor model, and cheap-prototyping's fidelity ladder were
all designed in worlds where the same input produced the same output, the
defect set was bounded, the artifact's appearance corresponded to its
fidelity, and the producer was the bottleneck. Under LLM-driven
development, none of these hold: outputs are stochastic and often
non-reproducible (Thinking Machines Lab, Chroma's "context rot"), failures
terminate at "the model predicted that token" with no further root cause
(TianPan, Arize), the candidate space is open and infinite (Karpathy,
Litt), polished prose hides shallow understanding (METR, Willison), and
the human reviewer — not the producer — is now the constraint. The
sharpest practitioner critiques (Karpathy's "Iron Man suit not robot,"
Litt's "code like a surgeon," Willison's "vibe engineering") all converge
on a claim the pack's premise underweights: AI changed the *kind* of work,
not just its cost, because the locus of judgment, the topology of
failure, and the economics of attention all flipped at once. The pack's
"borrow as default" stance is defensible *only* if it treats every
borrowing as a hypothesis to falsify, not a prior to relax from.

---

## The strongest arguments AI-dev is structurally different

### 1. Non-determinism is the floor, not a defect to engineer out

He et al. (Thinking Machines Lab, "Defeating Nondeterminism in LLM
Inference," September 2025) showed that even at temperature 0, LLM APIs
produce different outputs on identical inputs because *batch size* —
which depends on concurrent traffic the requester does not control —
breaks the numerical invariance of attention, RMSNorm, and matmul. They
ship a fix, but the fix costs 10–40 percent throughput and is not what
hyperscalers run in production. The pack's borrowing of COE / Five-Whys
assumes you can re-run the failure. AI failures regularly cannot be
re-run. TianPan ("AI Incident Retrospectives: When 'The Model Did It' Is
the Root Cause," April 2026) is explicit: classical 5-why analysis
*stalls* when the causal chain terminates at "the model predicted this
token." The whole genre of "ask why five times" presumes a producer
whose internal states a human can inspect. Transformer activations are
not that.

### 2. Context economics break the steady-state assumption

Chroma's "Context Rot" study (2025) tested 18 frontier models and
found *every one* degrades non-uniformly as input length grows —
attention weight thins out, middle-context recall collapses, and
the degradation begins well before the advertised window limit.
Lilian Weng's earlier "LLM Powered Autonomous Agents" (Lil'Log,
2023) called this out as the architectural bottleneck: planning over
long histories is fundamentally limited by finite, non-uniform context.
Toyota's andon assumes a worker whose performance is roughly constant
across the shift; Amazon's COE assumes a system whose state can be
captured in a snapshot. Agent context is neither — it *rots* during
the very session whose retrospective you are about to write, which
means the producer-at-failure-time and the producer-at-review-time are
not the same agent.

### 3. The candidate space is open, not closed

Karpathy's "Software 3.0" framing (AI Startup School talk, June 2025)
makes the structural point: in Software 1.0 you wrote one program; in
Software 2.0 you trained one model; in Software 3.0 the *prompt is the
program* and the program space is open-ended natural language. Geoffrey
Litt ("Malleable software in the age of LLMs," 2023, and "Code like a
surgeon," October 2025) extends this: when the artifact is generated
on demand, the "candidate set" is not a finite contact sheet of 36
exposures — it is an unbounded distribution. R3's photo-editor
borrowing rests on Edward Weston's premise that the camera produced N
exposures and the editor picked the best of N. AI does not produce N;
it produces a sample from a posterior that could have produced any N.
The kill-rate metric (B10) silently re-imports the closed-set
assumption.

### 4. The peer / collaborator framing changes the supervisory contract

Karpathy's "Iron Man suit, not Iron Man robot" formulation, paired with
his autonomy slider, frames the agent as a *partial-autonomy
collaborator* whose oversight level should slide with task criticality.
Litt's "Code like a surgeon" deepens this: tight feedback for core
work, long unsupervised runs for ancillary work, with the surgeon
choosing the dial. Shop-floor metaphors (line worker pulling andon)
silently assume the producer has *no opinion about its own oversight*
— it is supervised, full stop. A peer is not. If the agent is closer
to a junior collaborator than a CNC machine, then the discipline that
fits is closer to clinical supervision (Litt) than to TPS jidoka (R1).
The pack's bias toward manufacturing borrowings is therefore a category
error if the peer framing is even partially right.

### 5. The speed mismatch makes the human, not the producer, the bottleneck

The pack already named this (T1, X3) but the underweight is that
*every* borrowed discipline assumed the *producer* was the constraint.
Toyota optimized takt-time around the line; the worker was the slow
step. Photo editors had a fixed shoot to cull from. Amazon COEs
covered systems whose throughput was the budget. Under agent-driven
development the producer is functionally unconstrained — Willison
("Vibe engineering," October 2025) and the Security Boulevard 2026
survey (61 percent of developers say AI produces "looks-correct-but-
unreliable" code; 38 percent say reviewing it requires more effort
than reviewing colleagues' code) document that the new constraint is
*reviewer cognition*. This is not a parameter swap. It is a
constraint-flip, and disciplines designed around the old constraint
optimize the wrong variable when ported.

---

## The strongest arguments specific borrowings fail

### Toyota's andon / jidoka

The fundamental jidoka claim (Lean Enterprise Institute lexicon; Ohno
1988) is that machines should detect *abnormality* and stop themselves
— but this rests on the abnormality being detectable from a *fixed
spec* (this bolt is too long; this weld is cold; this seal leaked).
The detection rule is deterministic and the producer cannot
self-deceive about its output state.

LLMs violate both clauses. There is no fixed spec the producer can
check itself against — Farquhar et al. ("Detecting hallucinations
in large language models using semantic entropy," *Nature*, 2024)
demonstrate that the most reliable hallucination detection requires
*sampling the same model many times and measuring entropy across
meanings*, because the producer cannot directly tell whether its own
generation is grounded. This is the opposite of Toyota's torque sensor.
Worse, the producer's failure modes are *adversarial to itself*: an
LLM confidently outputting a fabricated API call is not in an
abnormal internal state — that *is* its normal generation behavior
under the right context. The pack's B6 ("andon for agents") quietly
re-imports the assumption that triggers can be *defined in advance*.
For shape defects (budget exceeded, type error, test fail) this is
fine. For the meaning defects that matter — and which the pack's own
A5/X2 already flag — there is no andon cord because there is no
sensor. Jidoka without a defect spec is just a pause button.

### Amazon's COE

Amazon's COE process (AWS Cloud Operations Blog, "Why you should
develop a correction of error") and its "five-whys to infrastructure"
discipline assume incidents are *re-runnable in principle*: you can
inspect the trace, identify the missing test, and write a regression
that prevents recurrence. TianPan's "AI Incident Retrospectives"
(April 2026) is the cleanest skeptical read on what happens when this
breaks. The core problem he identifies: the same inputs may not
reproduce the same outputs (Thinking Machines Lab batch-invariance
result), the model version may have silently rolled, the retrieval
corpus may have shifted, and the temperature seed may have drifted
across framework versions. He concludes that the *defensible
architecture* is to wrap the agent in a deterministic workflow and
treat agent calls as governed components — which is a much weaker
design than COE assumes.

The deeper objection: COE's value is in producing a *regression test*
that prevents recurrence. AI failures often cannot be regression-tested
in the COE sense — you can write an eval, but the eval is a
distribution-level claim ("the model passes this 95 percent of the
time"), not a binary guarantee. Drew Breunig and others have argued
informally on social media that LLM evals are closer to *clinical
trial design* than to unit testing, which is a different epistemic
discipline from the one Amazon developed for distributed systems.
Importing COE wholesale risks the ritual of postmortem without the
guarantee of correction.

### Photography's editor model

The R3 borrowing rests on the photo editor's job: 36 exposures arrive,
the editor selects N for the spread, the rejected frames are in
principle examinable. Edward Weston's contact-sheet practice produces
a *closed set with finite cardinality*. The editor's skill is
*recognition under finitude*.

The skeptical case (Karpathy's Software 3.0 framing, Litt's malleable
software work, and the more recent vibe-coding literature) is that
generative AI does not produce a contact sheet — it samples from a
distribution. If the human asks for "three more options" they get
three more samples, not three more frames from the same shoot. There
is no fixed N. This breaks the editor's discipline in two ways. First,
the *spread* metric (B26) cannot be enforced by the producer because
the producer doesn't know what axes vary across its own samples
without further reasoning. Second, the *kill rate* metric (B10)
silently re-imports a closed-set frame: the picture editor's 1-in-30
ratio comes from a fixed denominator. Under generative sampling, the
denominator is whatever the human chose to ask for, which makes the
ratio noisy at best and gameable at worst (ask for fewer candidates
to "improve" kill rate). The pack's photography borrowing is the
strongest of the five, but it imports a closed-set assumption that
modern image-generation tooling already broke (Adobe Generative Fill,
Pixlr, Canva all produce on-demand candidates without contact-sheet
finitude).

### Cheap-prototyping discipline

R2's borrowing assumes prototypes look *like prototypes* — Ulrich and
Eppinger's looks-like / works-like / production-intent ladder works
because fidelity is *visually legible*. A foamcore mockup announces
its own incompleteness; you cannot mistake it for a shipping product.

LLM-generated code and UI deny this affordance. Nielsen Norman Group
("Good from Afar, But Far from Good: AI Prototyping in Real Design
Contexts," 2025) documents that AI-generated prototypes appear
production-ready while concealing structural defects in hierarchy,
spacing, and information architecture. The Security Boulevard 2026
survey adds the developer-side mirror: 61 percent of developers say
AI code "looks correct but isn't reliable." Willison's "vibe
engineering" essay (October 2025) makes the methodological point: the
golden rule has to be "won't commit code I cannot explain," because
the surface signals that previously distinguished a prototype from
production code (rough edges, TODOs, unhandled cases) have been
erased. The pack's B12 (lineage labels) is the right shape of fix,
but it is fighting the medium rather than relying on it; the previous
discipline relied on the artifact's appearance to do half the work.
That signal is gone, and the pack should not pretend otherwise.

### Amazon's COE

[pending]

### Photography's editor model

[pending]

### Cheap-prototyping discipline

[pending]

---

## Empirical evidence

The empirical record on AI workflows treated like other-domain workflows
is, charitably, mixed; uncharitably, it suggests that ported disciplines
fail in characteristic and predictable ways.

**METR's 2025 RCT (Becker et al., "Measuring the Impact of Early-2025
AI on Experienced Open-Source Developer Productivity," July 2025).** The
single most-cited result: 16 experienced open-source developers,
randomized issue-by-issue between AI-allowed and AI-disallowed,
self-predicted a 24 percent speedup, *self-reported* a 20 percent
speedup after the fact, and *actually* slowed down by 19 percent. The
delta is what matters: the developers' own retrospective sense of
productivity was off by roughly 40 percentage points. This is direct
evidence against borrowing self-report-driven retrospective practices
(R5's COE, R1's coaching kata) without external measurement —
practitioners cannot accurately retrospect on AI-assisted work even
immediately after.

**GitClear's 2024 and 2025 code-quality studies.** Across roughly 211
million changed lines (Jan 2020–Dec 2024), the percentage of lines
reverted within two weeks rose from 3.1 percent (2020) to 5.7 percent
(2024); refactoring lines fell from 25 percent to under 10 percent;
copy-paste-cloned lines rose from 8.3 percent to 12.3 percent. This is
the *cheap-prototyping* discipline failing under AI: when generation is
free, churn rises, reuse falls, and the artifact's surface polish hides
the regression in structural quality. The pack's B12 lineage labels are
a reaction to exactly this, but the empirical baseline says the
discipline is not transferring on its own.

**Stanford's 100k-developer field study.** The headline of a 20 percent
average productivity gain conceals a non-uniform distribution:
productivity gains drop sharply as codebase size grows from 10k to 10M
LOC, and self-assessed productivity correlated weakly with measured
output (people misjudged by an average 30 percentile points). The
"workslop" finding — Stanford's name for AI-generated output that looks
like work but produces no downstream value — is the cleanest empirical
counterpoint to the cheap-prototyping borrowing: the prototype is no
longer cheap if the *next* worker has to reverse-engineer its intent.

**Confirmation bias in LLM-assisted review (arXiv 2603.18740, 2026).**
Framing a change as "bug-free" reduces vulnerability detection by
16–93 percent in LLM reviewers, with adversarial framing succeeding in
88 percent of attacks against autonomous Claude Code in real
project configurations. This is a direct hit on the andon / jidoka
borrowing: if the *reviewing* agent inherits the framing of the
*producing* agent, the safety mechanism fails silently. Toyota's andon
worked because the line worker had no incentive to suppress the cord
and could not be linguistically coerced.

**Security Boulevard 2026 developer survey.** 61 percent of developers
say AI produces code that "looks correct but isn't reliable"; 38
percent say AI code review takes more cognitive effort than colleague
review; reviewers default to checking that tests pass and moving on.
This is the constraint flip — reviewer attention is now the bottleneck
— showing up in field data, exactly as T1's sharpened "non-restartable"
formulation predicts.

---

## Implications for the pack

If the skeptical case holds even partially, the pack should make four
specific changes — none of which require abandoning the borrow-as-default
stance, but all of which raise the bar for what a borrowing must
demonstrate before earning its place.

**1. Treat every borrowing as a falsifiable hypothesis, not a prior.**
The premise's "departures should earn their place" bakes in a default
toward the borrowed discipline. Under non-determinism, open candidate
spaces, and the constraint flip, the safer default is the inverse:
*every borrowing is a hypothesis to test against AI-specific
pathologies*, and the burden of evidence sits with the borrowing, not
the departure. Practical: every R1–R5-derived practice gets a "failure
mode under non-determinism / open-set / hidden-fidelity" annotation
before it lands.

**2. Promote the constraint flip from a tenet sharpening to a structural
claim.** A2 already proposes "non-restartable" as the sharpening of T1.
The skeptical case suggests the flip is bigger: it changes what counts
as waste, what counts as a defect, and what counts as a retrospective.
A standalone tenet (or an explicit sub-tenet under T1) naming
"reviewer cognition is the budget" — and committing the pack to
optimize for it even when that conflicts with borrowed discipline —
would be load-bearing.

**3. Replace deterministic-defect andon with distributional-defect
gates.** B6 as currently drafted assumes definable triggers. Under
hallucination and confirmation-bias evidence, the operative discipline
is closer to *semantic-entropy sampling* (Farquhar et al., *Nature*
2024) and held-out adversarial evals (already in B18) than to
trigger-based andon. The pack should name this distinction explicitly:
shape andon (deterministic, bounded, automatable) vs. distributional
andon (sampling, eval-based, statistical). Treating the first as the
template for the second imports the wrong epistemics.

**4. Rebuild COE around non-reproducibility as the default.** B14's
two-layer cadence is the right shape, but the COE template itself
needs to drop the assumption that the failure can be re-run. TianPan's
"governed deterministic workflow around stochastic agent" model is one
candidate; capturing the full prompt + model version + retrieval
snapshot + temperature seed at failure time is the minimum bar. A COE
whose action item is "we wrote a regression eval at the 95th
percentile" is a different kind of artifact than one whose action item
is "we fixed the bug" — and the pack should not pretend they are the
same.

**5. Acknowledge the peer framing or reject it on the record.** The
pack's posture (T2's "the human owns the clock," P2's "opinion
alongside options") leans peer-adjacent without naming it. Karpathy
and Litt argue the framing is consequential — peers earn graduated
trust, peers have opinions about their own oversight, peers are
supervised differently from machines. If the pack endorses peer
framing, several borrowings (jidoka in particular) need re-derivation
from a clinical-supervision base rather than a manufacturing base. If
it rejects peer framing, that should be explicit in the foundation,
because much of the AI-native literature it competes with assumes peer
framing as default.

---

## References

**Practitioners on AI as kind-different, not cost-different**

- Karpathy, A. "Software Is Changing (Again)" / "Software 3.0." AI
  Startup School talk, June 2025. Latent Space writeup:
  https://www.latent.space/p/s3 . Key claims: prompt is the program;
  LLMs are operating systems; Iron Man suit not Iron Man robot;
  autonomy slider as the design primitive.
- Litt, G. "Malleable software in the age of LLMs." 25 March 2023.
  https://www.geoffreylitt.com/2023/03/25/llm-end-user-programming.html
- Litt, G. "Code like a surgeon." October 2025. Surgical-team analogy
  and the autonomy slider for delegation. (Also: Dive Club interview,
  November 2025.)
- Willison, S. "Vibe engineering." 7 October 2025.
  https://simonwillison.net/2025/Oct/7/vibe-engineering/ . The "won't
  commit code I can't explain" rule; the distinction between vibe
  coding and seasoned-professional acceleration.

**Theoretical / structural arguments**

- He, H. et al. (Thinking Machines Lab). "Defeating Nondeterminism in
  LLM Inference." September 2025.
  https://thinkingmachines.ai/blog/defeating-nondeterminism-in-llm-inference/
  . Batch invariance as the hidden source of non-determinism; the cost
  of fixing it.
- Hong, K. et al. (Chroma). "Context Rot: How Increasing Input Tokens
  Impacts LLM Performance." 2025.
  https://www.trychroma.com/research/context-rot . 18-model evaluation
  of non-uniform context degradation.
- Weng, L. "LLM Powered Autonomous Agents." Lil'Log, 23 June 2023.
  https://lilianweng.github.io/posts/2023-06-23-agent/ . Finite
  context, planning fragility, and self-reflection limits.
- Farquhar, S. et al. "Detecting hallucinations in large language
  models using semantic entropy." *Nature*, 2024.
  https://www.nature.com/articles/s41586-024-07421-0 . Sampling-based
  hallucination detection as the operative epistemics.

**Specific-borrowing critiques**

- TianPan. "AI Incident Retrospectives: When 'The Model Did It' Is the
  Root Cause." April 2026.
  https://tianpan.co/blog/2026-04-20-ai-incident-retrospectives-model-failures
  . Five-Whys stalls under stochastic failure; the governed-workflow
  alternative.
- Nielsen Norman Group. "Good from Afar, But Far from Good: AI
  Prototyping in Real Design Contexts." 2025.
  https://www.nngroup.com/articles/ai-prototyping/ . Prototype polish
  conceals structural defects.

**Empirical evidence**

- Becker, J. et al. (METR). "Measuring the Impact of Early-2025 AI on
  Experienced Open-Source Developer Productivity." 10 July 2025.
  https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/
  . The 24/20/-19 perception-vs-reality result.
- GitClear. "AI Copilot Code Quality: 2025 Data Suggests 4x Growth in
  Code Clones." February 2025.
  https://www.gitclear.com/ai_assistant_code_quality_2025_research .
  Churn, clones, and reuse decline.
- Stanford Software Engineering Productivity Research. AI Impact
  field study of 100k+ engineers, 600+ companies.
  https://softwareengineeringproductivity.stanford.edu/ai-impact .
  Codebase-size sensitivity and self-report unreliability.
- "Measuring and Exploiting Confirmation Bias in LLM-Assisted Security
  Code Review." arXiv:2603.18740, 2026.
  https://arxiv.org/html/2603.18740 . Adversarial framing succeeds in
  88 percent of attacks on autonomous review.
- "How to scale code review when AI writes code faster than you can
  understand it." Security Boulevard, March 2026. 61 percent
  "looks-correct-not-reliable" survey result.
