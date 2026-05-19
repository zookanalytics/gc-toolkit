# R2: What Changed When Prototyping Became Cheap

*Background research for the gas city pack — patterns from disciplines that already weathered an iteration-cost collapse.*

## Summary

Every discipline that absorbed a prototyping-cost collapse — mechanical engineering after CAD/3D printing, product design after Figma-class tools, startups after cloud + Lean, web product after A/B platforms — converged on the same three-layer response: **sharper upstream framing, structured selection rituals, explicit fidelity/lineage discipline at the integration boundary**. The naive expectation (cheap iteration replaces thinking) is empirically wrong; the consistent finding from Toyota's set-based engineering, Thomke's front-loading studies, and the A/B-testing literature is that cheap iteration *raises* the value of upstream rigor because the bottleneck moves to deciding what to build and reading the noisy result. For the gas city pack, the directly portable patterns are: hypothesis-first prompting (Ries), generate-N-then-converge with a Pugh-style weighted matrix decided *before* generation (Pugh, Ulrich & Eppinger), Decider-led design critique with Figma's jam/standing/quality-review tiers (Knapp, Figma), explicit prototype-lineage labels to prevent prototype-as-spec confusion, and innovation accounting over agent runs to track which invocations actually moved the team's beliefs. The principal failure modes to design against are sunk-cost fixation (which survives the cost reduction — Viswanathan & Linsey), demo-driven development, and the prototype-to-production gap that bit low-code hardest.

## Standard Practices

The pattern across every discipline that absorbed an iteration-cost collapse is the same: a new ritual emerges that protects *quality of judgment* once quantity of artifacts is no longer scarce. The ritual is almost always (a) a structured way to generate many candidates, (b) a forcing function that requires a decision before sunk cost accrues, and (c) a feedback loop tied to a real signal rather than internal opinion.

**Design Thinking (IDEO; Stanford d.school, mid-1990s onward).** Tim Brown's *Change by Design* (2009) and Tom Kelley's *The Art of Innovation* (2001) codified a five-mode loop — empathize, define, ideate, prototype, test — explicitly built around cheap, "low-resolution" prototypes (paper, foamcore, role-play). The slogan "fail early to succeed sooner" is Brown's. What changed: prototype shifted from *demonstration of a chosen design* to *instrument of inquiry*. New ritual: the team fabricates several throwaway artifacts per week and shares them in observed user sessions, treating the prototype as a question, not an answer.

**Lean Startup (Eric Ries, 2011).** Build–Measure–Learn around an MVP, with "validated learning" as the unit of progress and a pivot/persevere decision at each loop. What changed: cheap deployment (cloud, A/B infra) plus cheap prototype-grade product collapsed the cost of running a market experiment from quarters to days. New ritual: the explicit *hypothesis statement* ("we believe [X] for [persona]; we'll know it's true if [metric] moves [Y]") and the *innovation accounting* meeting that compares predicted to actual cohort behavior.

**MVP and Concierge/Wizard-of-Oz variants.** The MVP isn't the smallest shippable product; it's the smallest artifact that resolves the riskiest open hypothesis. New ritual: ranking hypotheses by risk and addressing them in order, often with non-code prototypes (Dropbox's explainer video, Zappos' photographed-shoes site). The discipline is to *not* build the easy thing first.

**Design Sprints (Jake Knapp, GV, *Sprint*, 2016).** A five-day script — Map, Sketch, Decide, Prototype, Test — that boxes a question into a single working week with five real users on Friday. What changed: the sprint replaces months of debate with a forced-choice cadence and requires a single named *Decider* (typically the founder/exec). New ritual: the silent gallery walk with dot voting ("heat-map"), the "straw poll" then "supervote" by the Decider, and the rule that the Friday user test is the tiebreaker — not seniority.

**Dual-Track Agile / Continuous Discovery & Delivery (Marty Cagan, Jeff Patton, 2012; Cagan's *Inspired* 2008/2017, *Empowered* 2020; Teresa Torres, *Continuous Discovery Habits* 2021).** Two parallel streams: discovery generates validated backlog items; delivery ships releasable software. Cagan's stated objective: "validate our ideas the fastest, cheapest way possible." What changed: validation moved *before* code, not after release ("fake it before we make it"). New ritual: weekly customer-touchpoint cadence (Torres' rule: every PM interviews a user every week), opportunity-solution trees, and assumption-mapping workshops.

**Continuous delivery and trunk-based development (Humble & Farley, *Continuous Delivery*, 2010).** When deploy cost approaches zero, batch size shrinks to one change. New ritual: deployment pipelines, feature flags, canary releases, and post-deploy verification dashboards as the definition-of-done.

**A/B testing platforms (Microsoft ExP, Google, Booking.com, Optimizely).** Ron Kohavi's work at Microsoft documents Bing running >10,000 experiments/year by the late 2010s, with a per-experiment marginal cost approaching zero. What changed: design-by-opinion replaced by design-by-shipped-variant. New ritual: the experiment-review board (twice-weekly at Booking.com), pre-registered hypotheses, guardrail metrics, and an institutional memory of "things we believed and were wrong about."

**CAD and 3D printing in mechanical engineering (1980s–2000s).** Stratasys-style FDM and SLA dropped a tooled prototype from weeks-and-thousands to hours-and-dollars. Steven Eppinger and Karl Ulrich's *Product Design and Development* (1995, now in its 7th edition) is the canonical text on how this restructured the engineering organization: more concept generation up front, parallel concept testing, and concept selection via Pugh matrices and weighted scoring. New ritual: the *concept review*, where 6–20 candidates are scored against weighted criteria before one advances.

**Discount usability (Jakob Nielsen, 1989).** A pre-cursor pattern from HCI: heuristic evaluation plus think-aloud testing with 3–5 users per round. New ritual: usability testing as a weekly chore rather than a quarterly study.

## The Counterintuitive Finding

The naive prediction is that cheap iteration lets you skip thinking — just spray prototypes and let the market choose. The empirical record is the opposite in disciplines that actually metabolized the change: **cheap iteration raises the bar on upstream framing**, because the bottleneck moves from fabrication to (a) deciding what's worth fabricating and (b) reading the noisy feedback well.

**Evidence in favor.**

- *Toyota's set-based concurrent engineering.* Ward, Liker, Cristiano, and Sobek's MIT Sloan Management Review article (1995) and Sobek/Ward/Liker's later work documented that Toyota — the fastest auto developer in the world — *delays* commitment by carrying multiple design sets in parallel longer than competitors. Cheap iteration on subsystems is paired with disciplined upstream definition of design space, target curves, and trade-off relationships. The lesson: when iteration is cheap, you can afford to keep the option set wide, but only if you've defined the option space rigorously.
- *Stefan Thomke's "front-loading."* Thomke and Fujimoto's *Journal of Product Innovation Management* paper "The Effect of Front-Loading Problem-Solving on Product Development Performance" (2000) — based on Toyota and BMW data — shows that organizations capable of cheap prototyping derive most of the benefit from *moving problem identification earlier*, not from iterating faster late. Thomke's HBR piece "Enlightened Experimentation" (2001) generalizes the finding: experimentation systems pay off only when paired with hypothesis discipline.
- *Lean Startup's hypothesis discipline.* Ries explicitly inverts the casual MVP reading: an MVP that doesn't begin with a falsifiable belief is "just a half-built product." Innovation accounting exists to prevent that.
- *A/B testing literature.* Kohavi, Tang, and Xu's *Trustworthy Online Controlled Experiments* (2020) reports that the majority of A/B tests at mature programs (Microsoft, Bing, Booking) *fail to move the target metric* — and that the value comes from the cumulative learning, which requires pre-registered hypotheses, guardrails, and a culture that interrogates surprising wins for instrumentation bugs. Without that upstream rigor, cheap experimentation produces noise theater.
- *Discount usability.* Nielsen's original argument was not "skip rigor"; it was "do rigorous testing more often by lowering its cost." The 5-user rule depends on a *well-formed task scenario*, which is upstream work.

**Where it's overstated.**

- The claim doesn't generalize to consumer-content domains where preference is genuinely emergent. Spotify's Discovery and TikTok's For You page are existence proofs that you can let signal-rich behavioral feedback substitute for upstream theory, *if* the loop is fast and the population is huge. Most teams have neither.
- "Better requirements" is sometimes a euphemism for waterfall-by-the-back-door. The honest version is: clearer hypothesis statements, sharper success criteria, better-instrumented metrics — not longer PRDs.
- In hardware, front-loading rigor is genuine and well-measured (Thomke). In software, the evidence is softer; teams that ship continuously sometimes outperform teams that "frame better" simply because the feedback loop is tighter. The trade-off is real and context-dependent.

The defensible version of the claim: **cheap iteration shifts effort from execution to framing and from execution to reading. The total cognitive load goes up, not down — it just relocates.**

## Back-End Adaptations

When you have 100 prototypes instead of 3, the binding constraint moves from *production* to *selection, integration, and survival under real-world load*. Mature disciplines built explicit machinery for each.

**Selection: structured convergence.** The Pugh concept selection matrix (Stuart Pugh, *Total Design*, 1991) is the canonical mechanical-engineering tool: pick a datum, list weighted criteria up front, score each candidate as +/0/− against the datum, then iterate by *combining* the strengths of leading concepts into hybrid candidates rather than picking the top scorer. Pugh emphasized that the matrix is "a convergence tool, not a decision oracle" — the score triggers a focused investigation, not a commit. Industrial design uses analogous tools (weighted decision matrices, kano models). The discipline is the same: weights are chosen *before* the candidates are scored, to prevent post-hoc rationalization.

**Critique: structured social ritual.** Design critique (industrial design, architecture, advertising) is a ritualized peer-review with three roles: presenter, critics, and a facilitator who enforces norms ("describe before you judge," "critique the work not the person," "no solutioning during critique"). Figma's published critique playbook distinguishes *jam sessions* (early, generative), *standing critiques* (recurring, work-in-progress), and *design quality reviews* (gate-style, pre-ship). NN/g's guidance is specific: a critique is not a vote — it surfaces unstated assumptions and risks. The closest software analog is the *architecture review board*, but design critique is more frequent and lower-ceremony.

**Integration: the prototype-to-production gap.** Both hardware and low-code/no-code communities document the same failure: prototypes optimized for learning rarely satisfy production constraints (manufacturability, regulatory, performance, security). Ulrich & Eppinger's *Product Design and Development* describes the staged transition from looks-like → works-like → engineering-prototype → production-intent, each with its own fidelity rubric. In software, McKinsey's 2023 piece on low-code documents that ~60% of low-code apps that get past pilot require partial or full rewrite for enterprise scale. The lesson: *prototype lineage matters* — name the prototype's class so people don't confuse a learning artifact with a production candidate.

**Validation in a cheap-prototype world.** When prototypes are cheap, the rigor migrates to the test plan: who you test with, what task you set, what counts as a pass, and what guardrails you watch for unintended damage. Ron Kohavi's experimentation playbook formalizes this: a pre-registered hypothesis, primary metric, guardrail metrics, minimum detectable effect, and a stopping rule. The cost moved from "build the variant" to "design the experiment that earns trust in the result."

**Portfolio thinking.** When 100 candidates exist, no single one matters — what matters is the *coverage* of the option space. Portfolio reviews (Cooper's Stage-Gate, Toyota's chief-engineer reviews) ask: are we exploring the right diversity of concepts, or have we converged prematurely on a local optimum?

## AI-Dev Applications

When an agent emits five working alternatives in seconds, the human's job decomposes into the same three layers that mechanical engineering, design, and lean startup all evolved: *frame the question*, *select among candidates*, *integrate the survivor*. Concrete proposals for the gas city pack:

**1. Hypothesis-first prompting (intent layer).** Borrow Ries' hypothesis statement and Cagan's opportunity-solution tree. Before asking the agent to generate, write down: what we believe, what would make us change our mind, what success looks like, and which guardrails must hold. This is the AI-dev analog of front-loading. The pack should make the hypothesis a first-class artifact (a `hypothesis.md` per task) and require the agent to restate and check it before generating.

**2. Generate-N-then-converge (selection layer).** Adopt the Pugh matrix explicitly. When agents can produce 5 alternatives, *require* them; do not accept the first plausible answer. Score against weights chosen *before* generation: correctness, diff size, test coverage, dependency footprint, reversibility, conformity to existing patterns. The pack ritual: a `selection.md` table with weights set in advance, candidates as rows, the chosen variant marked with a one-paragraph rationale and the runner-up preserved for later.

**3. The AI-dev design critique.** The closest analog to a design critique is a structured human walkthrough of a candidate change before merge — but at the pace of cheap iteration, traditional code review under-serves. Borrow the Figma model: distinguish *jam* (architecture sketches, multiple agents, generative), *standing critique* (recurring small-group walkthrough of in-flight agent work, with norms: describe-before-judge, critique-not-solution), and *design quality review* (the merge gate). The Decider role from Knapp's Sprint maps cleanly: name a single human owner per change set who breaks ties, and require their sign-off rather than consensus.

**4. Editor's eye over the flood.** This is the load-bearing concept. The editor in publishing doesn't write the article; she rejects most submissions, sharpens the lede, and protects the voice. The AI-dev editor's job is the same: (a) cull — most agent output should be discarded, not refined; (b) sharpen — promote the strongest candidate by editing it down, not extending it; (c) enforce voice — keep the codebase coherent in pattern, naming, and abstraction level. The pack should make culling cheap (a one-key reject), surface a *diff-of-diffs* across candidates so the editor can see what varies and what's invariant, and track the rejection rate as a health metric (too low = rubber-stamping; too high = bad upstream framing).

**5. Cheap A/B over functional alternatives, where reversible.** When the agent produces two reasonable approaches and the choice is empirical (perf, UX, error-rate), ship both behind a flag and let the metric decide. Borrow Kohavi's discipline: pre-register the metric, pick guardrails, set a stopping rule. Don't A/B over architecture — that's a critique decision, not an experiment.

**6. Lineage labels: learning vs. production.** Mirror Ulrich & Eppinger's looks-like / works-like / production-intent. Every agent artifact should be labeled by intended fidelity. A spike branch is not a candidate for merge. The pack should make the label a required field and refuse to merge a "spike" without explicit upgrade.

**7. Innovation accounting for agent runs.** Borrow Ries: track which agent invocations actually changed the team's belief about the system. Most won't. The metric isn't tokens spent or PRs opened; it's hypotheses resolved. A weekly review (the AI-dev analog of the experiment-review board) compares predicted-to-actual impact of merged changes and feeds back into prompt and spec quality.

**8. Pre-mortems before generation, post-mortems after merge.** Klein's pre-mortem ("imagine this PR caused an outage in 30 days; what was it?") is cheap insurance against premature commitment, especially when the agent's output is plausible-looking. Pair with a lightweight post-merge retro on surprises.

## Counter-Arguments

Steel-manning the critiques of cheap-prototyping orthodoxy:

**Sunk-cost bias survives the cost reduction.** Viswanathan and Linsey (Georgia Tech, 2013 onward) ran controlled experiments showing that even when prototypes are cheap, designers who *physically build* fixate on their first concept and produce lower novelty and variety in subsequent ideation than designers who only sketch. The mere act of instantiation creates attachment. Implication for AI-dev: agent-generated code is *not* sunk-cost-free. As soon as a human reads and edits a generated artifact, attachment forms. Cheap doesn't mean free of bias.

**Prototype-as-spec confusion.** A common failure mode in design and especially in low-code/no-code: a stakeholder sees a working prototype and treats it as a finished requirement. Subsequent "make it real" work is constrained by accidental decisions baked into the throwaway. Tim Brown himself warns about prototypes that "look too finished." In AI-dev, this is acute: an LLM-generated UI looks polished and shippable even when it's a sketch.

**Premature commitment to early variants (design fixation).** Jansson & Smith's classic *Design Studies* (1991) work on design fixation showed designers who see one example anchor on it. The cheap-prototype world makes this worse: the first plausible thing arrives faster, so the anchor sets sooner. Toyota's set-based approach is the explicit counter — keep multiple sets alive longer than feels comfortable.

**Decision fatigue in a flood.** Generating 100 candidates is useful only if a selection mechanism scales. Hick's law and the broader judgment-and-decision-making literature predict degraded choice quality as alternatives proliferate. Without weights set in advance, reviewers default to surface heuristics (looks polished, fewer lines, familiar pattern) which may be uncorrelated with quality.

**Demo-driven development.** A failure mode well-documented in startup post-mortems and explicitly named in the Reforge AI prototyping piece: optimizing for the next stakeholder demo rather than for production behavior. Ries warned about "vanity metrics"; the AI-dev analog is "vanity demos" — agent runs that produce impressive screenshots but uninstrumented, untested, brittle code.

**Prototypes that don't survive contact with production constraints.** McKinsey's low-code analysis and decades of hardware experience converge: ~half of prototypes that pass user-facing validation fail under production constraints (security, latency, cost-at-scale, regulatory, supply-chain). Cheap prototyping creates a bias toward learnable risks (will users like it?) and away from unlearnable-by-prototype risks (will it scale, will it be maintainable, will it be safe?).

**Design Sprint specifically.** Critics (designsprint.academy; Davidson; service-design community) argue the Sprint over-rotates on ideation and validation while under-investing in problem discovery — you can run a perfect sprint on the wrong problem. The five-day box is artificial; the *Decider* role concentrates failure risk in one person; and the customer test on Friday with five users in one day is a thin instrument for anything but blunt reactions.

**Lean Startup over-extension.** Steve Blank, Ries' mentor, has noted that Lean Startup is poorly suited to deep-tech, regulated industries, and any context where the riskiest hypothesis is technical feasibility rather than market demand. MVPs in pharma, aerospace, and infrastructure software can mislead because the cheap version doesn't surface the hard problem.

**Iteration as a substitute for taste.** The unspoken assumption of cheap-iteration culture is that the market (or A/B test, or user) will tell you what's good. In domains with weak feedback signals (B2B sales cycles, novel categories, ethics-loaded products), there is no substitute for editorial judgment up front. Steve Jobs' frequently-quoted line about not asking customers what they want is the canonical statement; the empirical defense is that some categories require taste because feedback is too slow or too noisy to be useful.

**The synthesis.** Cheap iteration is a power tool, not a methodology. It pays off when paired with sharp framing, structured selection, and respect for the constraints that prototypes can't probe. It fails predictably when treated as a substitute for thought.

## References

**Books — primary methodology texts**

- Tim Brown, *Change by Design* (HarperBusiness, 2009; rev. 2019). The IDEO synthesis. Useful for: design-thinking framework, "fail early to succeed sooner," prototype-as-question stance.
- Tom Kelley, *The Art of Innovation* (Doubleday, 2001) and *The Ten Faces of Innovation* (2005). Inside-IDEO ethnography of cheap-prototyping rituals; useful for the social mechanics of brainstorming and critique.
- Eric Ries, *The Lean Startup* (Crown, 2011). Build–Measure–Learn, validated learning, innovation accounting. The hypothesis-discipline argument lives here.
- Marty Cagan, *Inspired* (SVPG, 2008/2017) and *Empowered* (Wiley, 2020). Discovery/delivery split; validation before code; product team norms. The dual-track origin essay is on svpg.com.
- Jake Knapp, John Zeratsky, Braden Kowitz, *Sprint* (Simon & Schuster, 2016). Five-day Sprint; Decider role; gallery walk and supervote.
- Teresa Torres, *Continuous Discovery Habits* (Product Talk, 2021). Operationalizes Cagan's discovery track; weekly customer-touchpoint cadence; opportunity-solution trees.
- Jeanne Liedtka & Tim Ogilvie, *Designing for Growth* (Columbia, 2011). Design thinking translated for managers; useful framing of "what is" vs "what if."
- Don Norman, *The Design of Everyday Things* (1988; rev. 2013). Foundational. The case for human-centered evaluation that every cheap-prototyping practice rests on.
- Karl Ulrich & Steven Eppinger, *Product Design and Development* (McGraw-Hill, 1995; 7th ed. 2020). The canonical engineering text. Concept generation, Pugh selection, fidelity progression, looks-like → works-like → production-intent.
- Stuart Pugh, *Total Design* (Addison-Wesley, 1991). The selection matrix and "controlled convergence."
- Allen Ward & Durward Sobek II, *Lean Product and Process Development* (LEI, 2007/2014). The set-based concurrent engineering book-length treatment.
- Jez Humble & David Farley, *Continuous Delivery* (Addison-Wesley, 2010). The software-side of cheap iteration.
- Ron Kohavi, Diane Tang, Ya Xu, *Trustworthy Online Controlled Experiments* (Cambridge, 2020). The A/B testing rigor canon; pre-registration, guardrails, sample-ratio mismatch.

**Articles — the load-bearing journal pieces**

- Tim Brown, "Design Thinking," *HBR*, June 2008. The piece that put design thinking in front of executives.
- Stefan Thomke & Takahiro Fujimoto, "The Effect of Front-Loading Problem-Solving on Product Development Performance," *Journal of Product Innovation Management*, 17(2), 2000. The empirical case that cheap experimentation pays off via earlier problem identification.
- Stefan Thomke, "Enlightened Experimentation," *HBR*, Feb 2001. Generalizes the Toyota/BMW result; pairs experimentation with hypothesis discipline.
- Allen Ward, Jeffrey Liker, John Cristiano, Durward Sobek, "Toyota's Principles of Set-Based Concurrent Engineering," *MIT Sloan Management Review*, Spring 1995. The original SBCE description.
- Sobek, Ward, Liker, "Toyota's Principles of Set-Based Concurrent Engineering," follow-up *Sloan Management Review*, 1999.
- Jakob Nielsen, "Usability Engineering at a Discount," 1989 (HCI International), and the NN/g "Discount Usability: 20/30 Years" retrospectives. Origin of the 5-user rule and lightweight evaluation.
- Viswanathan & Linsey, "Role of Sunk Cost in Engineering Idea Generation: An Experimental Investigation," *Journal of Mechanical Design*, 2013. Empirical evidence that physical prototyping induces fixation via sunk-cost bias.
- Jansson & Smith, "Design Fixation," *Design Studies*, 12(1), 1991. The classic experiment.
- Ron Kohavi & Stefan Thomke, "The Surprising Power of Online Experiments," *HBR*, Sep–Oct 2017. Practitioner-facing summary of A/B program design.
- McKinsey Digital, "Low-code/no-code: A way to transform shadow IT," 2023. Empirical-ish field observations on prototype-to-production gap.

**Web/practitioner sources used**

- SVPG: "Dual-Track Agile" essay (Cagan).
- GV: "The Design Sprint" overview (gv.com/sprint).
- Figma blog: "How we do design critiques at Figma."
- NN/g: "Design Critiques: Encourage a Positive Culture."
- Critical-perspective sources used for the counter-arguments: designsprint.academy ("Design Sprints Exposed"), service-design-show.com, alabut.com (Sprint pros/cons), Reforge AI prototyping article on demo-driven failure modes.

**Adjacent reading worth pulling later**

- Gary Klein on pre-mortems (*HBR*, Sep 2007).
- Robert Cooper, *Winning at New Products* (Stage-Gate origin).
- Steve Blank, *The Four Steps to the Epiphany* (customer-development precursor to Lean Startup).
- Clayton Christensen on jobs-to-be-done (intent-layer rigor).
