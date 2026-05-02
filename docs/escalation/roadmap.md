# Escalation — Roadmap (Future / Phased Work)

> **What's not in v1 but should land in some phase.** Items here were
> captured during foundation work, recognized as load-bearing or
> directionally right, and explicitly deferred — either because they
> need infrastructure that doesn't exist yet, evidence from real use,
> or a strategic call about scope.

**Status:** active. Items can be promoted to operational work when the
gating evidence appears. This doc is the parking lot, not the
graveyard.

---

## Promoting items off this list

Each item names what would unblock it. When that condition appears,
the item moves out of this doc into the appropriate operational
artifact (foundation update, new practice, skill spec, etc.). When in
doubt, surface it as a Reflect-class consult to the human and ask.

---

## Highest-leverage items

### Silent-decision audit

The structural counter to T4 (automation drifts unless deliberately
audited). Has two operational forms:

- **Form 1: Growing gates.** Certain document classes (architecture
  docs, schema files, public APIs) accumulate "always-require-approval"
  status because the audit revealed silent changes there went wrong.
  Gates accumulate from evidence, not from a priori design.
- **Form 2: Inter-agent peer audit.** Specialized roles (architect,
  mechanik, concierge) audit each other's silent work. The audit runs
  on agent time (cheap), surfaces only when drift is found.

The two compose: Form 2's audits produce evidence that drives Form 1's
gate accumulation.

*Unblocks when:* the pack has enough operational history (and harness
support) to detect patterns. Probably needs basic ledger surface
first.

### Edges-visible-proportional-to-impact

Operational practice under T4. AI edges scale with impact —
architecture changes, new API surfaces, UI features are big edges and
must be visible in the corresponding canonical artifact; small impacts
don't need big visibility. The agent self-classifies edge size in its
frame; the audit catches misclassification.

*Unblocks when:* skills exist and the consult format is in real use —
need data on how agents actually classify their own work to design the
audit's catch mechanism.

### Agent roster watching scope

Each role in the existing concierge / architect / mechanik roster gets
a *watching responsibility* alongside its doing responsibility:

- Architect watches for architectural drift (silent changes that should
  have updated arch docs).
- Mechanik watches for implementation drift (silent fixes that should
  have been documented or tested).
- Concierge watches for conversation/consult drift (consults that
  didn't follow up; decisions that didn't propagate to artifacts).

*Unblocks when:* the silent-decision audit (above) is operational.
This is the human side of how the audit's findings get acted on.

---

## Hidden metrics worth measuring

From V7 (`docs/escalation/research/v7-hidden-metrics.md`). The pack's
current metric thinking is producer-side and rate-shaped, and silently
assumes the human reviewer is a constant-quality oracle. These metrics
relax that assumption.

- **Frame-redirect rate.** Distinguishes "human pushed back at the
  framing" from "human picked from offered options." Different defects
  with different fixes; currently conflated.
- **Reviewer trust trajectory.** Per-skill direction and velocity of
  reviewer confidence. Eroding trust on a skill is pre-erosion
  intervention signal.
- **Half-life of skills and gates.** When was each last touched? T3
  says the pack learns; H3 says the pack also decays. Audit by age,
  not just by event.
- **Pack self-knowledge depth (precondition).** Can the pack answer
  questions about itself — which skills, which gates, calibration
  trends, silent-decision counts? Without this, the others stay
  aspirational.

*Unblocks when:* the harness has telemetry / introspection surfaces.
H8 (self-knowledge) is the gating engineering item.

---

## Broader-pack scope (beyond consult / concierge)

These are right for the wider gc-toolkit but not for the current
consult focus.

### Hypothesis-first prompting

Before the agent generates anything substantial: write the hypothesis
(what we believe, what would change our mind, success criteria,
guardrails). Lives more in brief → design → spec → implement workflow
than in consults specifically. The frame block of a consult is a
compact sibling of this.

*Unblocks when:* broader-pack scope work begins.

### Develop before asking

When the agent can develop multiple avenues to evaluable depth without
asking the human, it should. Distinguishes *gating* questions (the
agent literally cannot proceed) from *preference / development*
questions (the answer surfaces naturally when avenues are
visualized). Gating questions get asked early; preference questions
get answered by what the agent develops.

This is the cost-flip in action: parallel deep exploration is cheap;
human attention isn't. Prefer parallel depth over sequential
interrogation.

*Unblocks when:* broader-pack scope work begins, and when the harness
supports parallel sub-agent development with clean reconvene.

---

## Tooling / infrastructure preconditions

Several of the above items depend on infrastructure that doesn't
exist yet:

- **Spread-index check.** Validating that candidate sets show
  meaningful axis variation (semantic similarity, LLM judge,
  categorical taxonomy per task class). B26 in ideation.
- **Diff-of-diffs viewer.** Surfacing what varies vs. invariant across
  N candidate diffs.
- **Confidence calibration log / trust ledger.** Per-skill, per-class
  records of stated-vs-actual outcomes.
- **Cross-model regression suite per skill.** Behavioral assertions
  that run on every model upgrade.
- **Held-out adversarial eval.** Failure modes that don't enter agent
  context, run periodically against the live pack.

*Unblocks when:* harness work prioritizes them. Several may be
independently valuable; not all need to land at once.

---

## First skills

The pack-v2 schema lives at `skills/<name>/SKILL.md`. The first set of
skills to write is left to downstream agent work — the marching orders
in `marching-orders.md` give the strategic context, and the agent
selects based on what the foundation calls for.

*Unblocks when:* downstream agent picks the set. Likely candidates
include skills for the consult format, AAR, COE, and the escalation
typology, but the agent should justify its picks against the
foundation rather than inheriting a list from here.

### Canonical SKILL.md template

A worked example that other skills can follow. Should pick one
canonical structure (front-matter + sections + hooks integration
points) and instantiate it well, rather than letting per-skill drift
emerge. Naming conventions are themselves a separate conversation.

*Unblocks when:* the first skill is written, and a template gets
extracted from it.

---

## Posture / metaphor

User explicitly parked twice. Default for now is no metaphor — the
practices encode the relationship. Will revisit when first use
generates a need for one (and when the need is for *what*, not just
*whether*).

Candidates considered: chief-of-staff, co-pilot, principal-investigator
/ research-assistant, coach / apprentice, picture-editor / writer,
caddy / golfer. Surgeon / scrub-nurse explicitly rejected. Roster of
metaphors keyed to context (different work, different relationship)
also considered.

---

## Cross-model regression and prompt-as-evaluated-artifact

From V4 (`docs/escalation/research/v4-ai-native-inventions.md`):
genuinely AI-native problems with no clean human precedent. Worth
tracking but not for v1:

- **Prompt-as-evaluated-artifact.** Every prompt and skill ships with
  an eval suite committed alongside it. The eval, not the prompt
  text, is the durable spec. AI-native because no other artifact
  class needs statistical correctness gates by construction.
- **Cross-model regression suite per skill.** Skills declare their
  supported model set and carry a small behavioral-assertion battery
  run on every model upgrade. Drift above threshold blocks rollout.
- **Calibrated trust ledger per skill.** Acceptance rate, calibration
  of stated confidence, alignment-sensitive escalation precision.
  Review intensity flexes against the ledger.

*Unblocks when:* skills exist and have enough usage history to make
the evals meaningful.

---

## Inversions reviewed but parked

From V5 (`docs/escalation/research/v5-inversions-within.md`) and V6
(`docs/escalation/research/v6-inversions-against-field.md`). The
inversions reviewed but not absorbed:

- **Pack deliberately forgets** (V5 I4). Skills that retire when no
  longer earning their attention claim. Worth revisiting once trust-
  ledger data exists.
- **Peer-flat vocabulary** (V5 I7). Reframe "escalation" as "request
  between equals." Worth revisiting after first use shapes how the
  Reflect class actually behaves.
- **Pack built to be replaced** (V5 I8). The pack designed for short
  half-life and quick replacement, rather than slow refinement. The
  current bias is toward refinement; revisit only if evidence shows
  the slow-refinement default is failing.
- **Inversion 5 work-selection question** (V6). AI changes what's
  worth doing, not just makes existing work cheaper. The pack assumes
  the same problem shape applies; Drucker's-knowledge-work analogy
  says fundamentals are perennial. Don't override that without
  evidence.

---

## Outstanding "things to consider when amending" list

Six considerations worth checking when amending the foundation,
captured during the M-meta discussion. Not enforced as a template
field; just a list to walk:

1. **Attention claim** — does the change respect T1?
2. **Metric corrective** — if it's a metric, does it name threshold +
   corrective + actor?
3. **Disanalogy + falsification test** — if it borrows, where does the
   source break and what AI failure mode would invalidate it?
4. **Pre-commit vs. discovery** — if it's a selection rule, does it
   work only on measurable axes?
5. **Coaching terminates in artifact** — if it's a learning practice,
   does it end in a merged diff?
6. **Default-conservative reversibility** — if it touches irreversible
   actions, does it classify-on-doubt as irreversible?

This list lives here rather than in the foundation because the
foundation rarely changes; the considerations apply when it does.
