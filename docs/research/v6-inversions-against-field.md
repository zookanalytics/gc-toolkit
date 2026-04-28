# V6 — Inversions Against Field Consensus

> **Status: drafting.** Recovery-Oriented Computing flipped a dominant
> reliability frame (maximize MTBF → minimize MTTR) and got a richer design
> from the inversion. This document applies the same move to the
> AI-assisted-development field's 2026 consensus framings, asks which
> inversions are generative, and tests where they cut against or for the
> pack's current shape.

---

## Summary

[pending]

---

## Field framings and inversions

### 1. "Better models = better outcomes" → "the model is interchangeable; the harness is the product"

**Field frame.** Most 2026 product roadmaps and benchmark threads move
on capability — GPQA, SWE-bench Verified, Terminal-Bench, ARC-AGI-2 —
treating the model as the load-bearing input. OpenAI's model cards,
Anthropic's release posts, and the Cursor/Cognition leaderboards all
imply that *next model* is the unlock. Cognition's Devin marketing,
specifically, leans on raw capability claims; the user-facing
narrative is "trust because the model is better."

**Inversion.** The model is a swappable component; the harness — the
sandbox, transcript, hooks, eval set, escalation taxonomy, role-
specific rules — is what determines outcomes. Capability ceiling is
real but distant; the constraint binding *today's* output quality is
the harness around the model.

**What it generates.** A pack designed around this inversion treats
model selection as a tuning knob, not a strategic decision. It
invests in: lifecycle hooks (Anthropic's `PreToolUse`, `Stop`),
tool-approval signatures (OpenAI Agents SDK), Skills as the unit of
tacit-knowledge transfer, and held-out evals as the regression
spine. Model swaps are a Tuesday operation; harness changes are
versioned and reviewed.

**Generative or empty.** *Generative.* Willison's "harness
engineering" (2025) and Anthropic's skills/sub-agents/hooks stack
are already moving here, and the pack's B7 (poka-yoke first, prompt
last) plus the v2 candidates (B30 context hygiene, B33 typed
approval) sit on this side. The inversion sharpens what to invest in
and what to ignore.


### 2. "Maximize agent autonomy" → "maximize agent legibility"

**Field frame.** The dominant arrow in agent product design points
right on Karpathy's autonomy slider: longer-horizon runs, deeper tool
chains, less interruption. Cognition's Devin pitches days-long
unattended sessions; Cursor's Composer agent mode and Replit's Agent
V2 advertise "go do it" workflows; OpenAI Operator and Anthropic's
Computer Use both market hands-off operation as the headline. The
implicit success metric is *minutes of unsupervised agent time*.

**Inversion.** The agent's primary job is to be *readable* to the
human, not to do more on its own. Every additional minute of
autonomy without legibility is a future review-debt instalment; the
real product surface is the trace, not the result.

**What it generates.** A pack designed around legibility-maximization
treats the transcript, the diff, and the live environment (Replit's
contribution) as first-class artifacts that must be *navigable* — not
exhaustive. Sub-agents (Anthropic) exist not to do more work but to
keep the main thread's transcript readable. P3 (recognition over
reading) and P4 (last line is the lede) become harder constraints:
*if the human cannot recognize correctness in N seconds, the agent
ran too long.*

**Generative or empty.** *Strongly generative*, and it directly
challenges the field's implicit autonomy-as-progress frame. METR's
24/20/-19 result (developers thought they were faster, were actually
slower) is the empirical edge: more autonomy made performance
*worse* and self-report *less reliable*. Legibility-first inverts the
diagnosis.


### 3. "Reduce friction in human-AI interaction" → "introduce strategic friction at decision points"

**Field frame.** The UX consensus is to remove keystrokes, auto-
accept, auto-apply, auto-commit. Cursor's tab-to-accept, GitHub
Copilot's ghost text, Codeium's autocomplete UX, and most agent IDE
chat panels optimize for *flow* — minimum interruption from prompt
to merge. The implicit assumption: friction is waste.

**Inversion.** Friction *at decision points* is the load-bearing
mechanism that protects human judgment. The places where the
practitioner pauses, reads, and disagrees are the places where the
pack earns its keep. Removing friction there imports the costs to
the rollback queue and the postmortem.

**What it generates.** A pack designed around strategic friction
puts a typed-approval gate (OpenAI Agents SDK B33) on every
irreversible action, declares lethal-trifecta-bearing operations
(Willison's B31) as Review-class escalations (LangChain B27), and
*makes the diff harder to merge than to draft*. P5 (highest-density
form) becomes "make the decision visible at the friction point, not
at the tab-completion." Confirmation-bias evidence (arXiv 2603.18740,
88 percent attack success on framing) supports placing friction *on
the framing itself*: every change carries a structural-skeptic check
the framing cannot suppress.

**Generative or empty.** *Generative.* Confirmation-bias evidence and
the Security Boulevard 2026 reviewer-effort survey both indicate
flow-optimized UX silently transfers cost to a place practitioners
cannot see. The pack's existing P1 / P2 / B6 already trend here; the
inversion supplies the explicit theory.


### 4. "Reduce hallucination" → "make hallucinations cheap to detect and correct"

**Field frame.** Most safety and reliability work is framed as
hallucination *reduction* — better RAG, grounding, fact-checking
chains, fine-tunes that "lie less." Anthropic, OpenAI, and the
academic safety stack all measure hallucination *rate* as the
metric to push down.

**Inversion (already in the prompt).** Treat hallucination as a
permanent floor; invest in detection cost and correction cost
instead. Make every hallucination cheap to surface and cheap to
fix.

**What it generates.** A pack on this footing is built around
Farquhar et al.'s semantic-entropy sampling (multi-sample the same
question, measure meaning-level disagreement), Hamel's "look at 20–
50 outputs" discipline, and Willison's transcript-as-published
artifact. Eval-diff as the closure unit (B29) becomes the central
ritual: every detected hallucination lands as a regression eval, so
the *correction cost* falls each cycle even if the *rate* does not.
B14's per-event AAR shifts from "why did the model lie" (Five-Whys
stalls per TianPan) to "why didn't our gates catch it." This mirrors
ROC's MTBF→MTTR move almost exactly: stop optimizing the asymptote,
optimize the *time and cost of recovery*.

**Generative or empty.** *Strongly generative* and the most direct
ROC-shaped inversion in the set. The pack's T3 (learning compounds)
already implies this; the inversion makes it the spine.


### 5. "AI augments existing developer workflows" → "AI changes what's worth doing in the first place"

**Field frame.** Most enterprise AI-coding rollouts (Shopify,
Microsoft internal, Atlassian, the GitHub Copilot for Business
playbook) frame AI as *speeding up the existing SDLC*: same
backlog, same tickets, same review process, just faster. Lütke's
"reflexive AI use" memo, even at its strongest, asks the *same
work* to be done *with* AI; it does not redraw what work to do.

**Inversion.** AI changes which problems are worth solving at all.
Cheap generation makes prototyping-as-investigation viable for
questions previously too expensive to explore; entire categories of
work (writing throwaway adapters, scaffolding speculative branches,
generating three independent implementations to compare) become
default rather than exotic.

**What it generates.** A pack designed around this inversion treats
the *backlog itself* as a candidate set to prune, not a queue to
work through. P3 (recognition over reading) extends from artifacts
to *problem statements*: surface three framings of the work, pick
by sight. R2's prototyping discipline becomes a *search* discipline;
B10 kill-rate metrics extend to scrapped *ideas*, not just scrapped
candidates. The retrospective ritual asks "what did we learn we
shouldn't have built" alongside "what should we have built better."

**Generative or empty.** *Generative but partial.* The strongest
form of this inversion is closer to product-strategy reframing than
to pack-level practice; the pack can adopt the prune-the-backlog
posture without committing to the strong claim that all existing
workflows are obsolete. The weak form (cheap generation changes the
search/build ratio) is already implicit in P3 and R2.


### 6. "Make the AI seem smart" → "make the AI's limits legible at every step"

**Field frame.** Consumer-facing assistant UX (ChatGPT, Claude.ai,
Gemini, most agent products) hides uncertainty: confident prose,
streaming tokens, no surfacing of "I am not sure." Even in
developer tools, Cursor, Copilot, and Cognition Devin generally
present output as a finished artifact. The product instinct is to
*reduce the appearance of fallibility* because users prefer
confidence.

**Inversion.** Every output renders its own limits: confidence
intervals, retrieval provenance, tool-call uncertainty, the
adjacent paths considered and discarded. "I'm guessing here"
appears in the artifact, not just the chat.

**What it generates.** A pack that adopts this writes calibration
into output format: every claim carries a provenance pill (was
this read, retrieved, generated), every recommendation carries an
explicit "I would re-check this if X" caveat, and the consult
format requires the AI to surface the *closest alternative it
rejected*. P2 (opinion + options) extends to "opinion + options +
my own confidence in the opinion." Russell's CIRL ("agents should
be uncertain about objectives") becomes a UI principle, not just a
training-time concept. Confirmation-bias evidence (arXiv 2603.18740)
makes this load-bearing — the framing the model carries forward
into review is exactly what currently fools reviewers.

**Generative or empty.** *Strongly generative.* Directly cuts
against most polished agent-product UX. The pack's P2 and P6 already
lean here; this inversion would harden the lean into a tenet.


### 7. "Standardize on a single model / vendor" → "use model diversity as mutual check"

[pending]

### 8. "Document the decision" → "document why we almost did the other thing"

[pending]

---

## Where inversions challenge the pack

[pending]

---

## Where inversions reinforce the pack

[pending]

---

## References

[pending]
