# V7 Hidden Metrics — What the Pack Is Not Measuring

## Summary

The pack's current metric set is producer-side and rate-shaped: counts and ratios about what
the agent does (escalation rate, cull rate, override rate, eval pass rate, reversibility burn,
closure latency). Every one of these treats the human reviewer as a constant-quality oracle
who simply receives output. That assumption is the blind spot. Reviewers degrade, frames go
unchallenged, the pack's own self-knowledge stays implicit, and large categories of work — the
ones that resolve in deferral, in re-framing, in slow trust erosion — leave no trace in the
current numbers. The most generative reframing is to shift from *agent-side throughput
metrics* to *reviewer-state and frame-state metrics*: how clear is the human's mental model
right now, how stale are the artifacts the pack relies on, and how often does the agent get
the question itself wrong (versus its answer to a correct question). Three candidates below —
**Frame-redirect rate**, **Reviewer trust trajectory**, and **Half-life of skills/gates** —
expose entire design spaces (frame-first practices, reviewer-as-asset cultivation, decay
maintenance) that the current metric set cannot see.

## Hidden metric catalog

### H1. Frame-redirect rate

**The hidden metric.** Of all consults, how often does the human reject the *question the
agent asked* rather than choosing among the agent's options? "You're solving the wrong
problem" vs. "pick option B." Currently the pack tracks override rate (E6), which conflates
the two: a counter-pick within frame and a frame-rejection both count as "override."

**What measuring it would expose.** A frame-redirect is the most expensive failure mode in
the pack's economics — the agent's whole exploration was wasted, the contact sheet rendered
the wrong axis, the recommendation answered the wrong question. If frame-redirects are a
meaningful fraction of overrides, the pack's current investments (B3 contact sheet, P3
recognition, P5 density) are downstream of a problem they cannot fix. The design space
opened: *frame-first practices* — frame negotiation before generation, hypothesis docs (B4)
upgraded to "the question itself is the deliverable," candidate-of-frames before
candidate-of-solutions.

**What practices would emerge.** A frame-checkout step before generation. Two-tier consults:
"is this the right question?" precedes "which of these answers?" An A3 hypothesis doc whose
top section is *the question being decided* and which gets explicit sign-off before any
generation. A skill that, on a fresh task, generates 2–3 candidate framings and asks the
human to pick before the agent commits compute.

**Why we're ignoring it.** Conflated with override rate; politically uncomfortable because a
high frame-redirect rate indicts upstream spec quality (which the pack often blames on the
human); and hard to detect automatically — it requires a structured tag on the override
event, not just a counter-pick.

### H2. Reviewer trust trajectory

**The hidden metric.** Per-reviewer, per-skill: how is the reviewer's confidence in this
agent moving over time? Not just the override rate, but the *direction and velocity*. A
reviewer who has stopped reading the agent's reasoning carefully is a different state from
one who is still close-reading every diff — and the pack treats them identically.

**What measuring it would expose.** Trust is a depleting resource on the human side, not
just attention (T1). One bad consult costs more than ten good ones earn back; trust has
hysteresis. The current pack doesn't model this at all. Once surfaced, the design space
includes: *trust-budgeted operation* (low-trust skills run with extra confirmation surfaces;
high-trust skills get sampled review per I14), explicit *trust-rebuild rituals* after a
miss, and *reviewer-as-asset* framing where the reviewer's calibrated state is something the
pack cultivates and protects, not just consumes.

**What practices would emerge.** A per-skill trust ledger (overlaps I14 but extends it to
the reviewer-state side). A "trust event" tag on every consult outcome — caught defect,
missed defect, false escalation, wasted review — fed back into the ledger. A formal "trust
quarantine" for skills that have just had a miss (forced trajectory review for N runs). A
practice that *retires* a skill from a reviewer when trust falls below threshold rather than
asking the reviewer to keep grinding through low-quality output.

**Why we're ignoring it.** Trust feels squishy and subjective; quantifying it makes the
reviewer a measured object (H14 dignity concern in the ideation log). Also, the simpler
metric (override rate) is already there and looks adjacent enough that the pack assumes it's
covered. It isn't — override rate is a behavior, trust is a state, and behavior lags state.

### H3. Half-life of skills and gates

**The hidden metric.** When was each skill, gate, fewshot, or eval last touched, validated,
or fired? What fraction of the pack's surface area is older than the model currently
running? Stale assets fire silently and either no-op or, worse, mis-fire on input shapes
they were never tuned for.

**What measuring it would expose.** The pack assumes its accumulated assets are an asset.
Past some age, they are a liability — borrowed wisdom from a model that no longer exists,
gating decisions that don't apply, examples that anchor the agent on dated patterns. The
design space opened: *decay maintenance* as a first-class practice, parallel to the Toyota
hansei but for the pack itself. Every skill carries a freshness signal; the pack does
periodic sweeps (the missing M-practice the Section M list almost has but stops short of).

**What practices would emerge.** A "last fired / last validated / last edited" timestamp on
every skill and gate. A staleness dashboard that surfaces which assets haven't been
exercised in N model versions or M weeks. An automatic re-validation run on model upgrade
(I11 covers part of this but only for the supported model set; the half-life metric would
also surface skills that *have no* declared model set). A retirement ritual — skills that
fail freshness checks get archived rather than left to mis-fire.

**Why we're ignoring it.** It feels like maintenance, not innovation; nobody gets credit
for retiring a stale skill. Also disguised — the existence of a skill in the directory is
treated as evidence it's working, even when nothing has fired against it for months. The
pack's "the pack learns" tenet (T3) is asymmetric: it only models accretion, not decay.

### H4. Time-to-first-judgment

**The hidden metric.** Wall-clock time between the agent producing reviewable output and
the human meaningfully engaging with it. Not the closure latency (E3, which measures
action-item lifecycle), but the *attention-arrival latency*: how long does work sit in the
queue before a human looks?

**What measuring it would expose.** The pack optimizes for the cost of each consult once a
human is reading, but doesn't measure the *queue depth* in front of the human. A reviewer
who finally engages 18 hours after the agent produced output is engaging with stale
context — the agent's reasoning is no longer fresh, the project state may have moved.
Surfaces a design space the current pack has not entered: *queue-aware generation*. If the
queue is deep, the agent should produce more self-contained, context-resilient artifacts;
if the queue is shallow, denser, faster handoffs win.

**What practices would emerge.** Queue-depth-aware autonomy slider (I2/I13) — the agent
operates more conservatively as queue depth grows. Backpressure on the agent: refuse to
generate new work until the queue drains. "Aging" tags on consults so the human can see
what's stalest, not just what's newest. Possibly a re-context step where the agent
refreshes its own framing before the human engages with old output.

**Why we're ignoring it.** Hard to measure without instrumentation on both sides (when did
the human actually look?). Also disguised as closure latency, which it isn't — closure
latency starts when judgment happens.

### H5. Information-density-per-consult

**The hidden metric.** Bits of decision-relevant signal per token (or per second of human
attention) in each consult. P5 names "information density" as a principle; the pack does
not measure whether actual consults achieve it.

**What measuring it would expose.** The principle without the metric is exhortation. A
consult that takes 800 words to convey one bit ("approve / reject") is an attention burn;
the pack has no signal for catching this. Surfaces design space around *consult
compression*: structural templates that bound length per decision-bit, automated checks
that the lede is in the terminal line (P4), and rejection of consults that fail a density
threshold.

**What practices would emerge.** A consult linter that scores draft escalations on a rough
density proxy (decision tokens / total tokens). A "lede check" before a consult is
delivered: can the human give a thumbs-up/down based on the last paragraph alone? Rewrite
loops that target density, run by the agent against itself before the consult lands.

**Why we're ignoring it.** Density is hard to measure mechanically — bits-of-signal is
fuzzy and varies by reviewer. Also: the pack's culture rewards thorough exploration (G2),
which can quietly subsidize verbose output as evidence of effort.

### H6. _(placeholder)_

### H7. _(placeholder)_

### H8. _(placeholder)_

### H9. _(placeholder)_

## Recommendations

_(to be filled)_
