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

**The hidden metric.** How often the human rejects the *question* the agent asked rather
than choosing among its options. "Wrong problem" vs. "pick option B." E6 override rate
conflates the two.

**What it would expose.** A frame-redirect is the most expensive failure mode the pack
has — the whole exploration was wasted, the contact sheet rendered the wrong axis. If
frame errors are common, every practice that operates after generation (P3, B3, P5) is
patching the wrong layer. Opens *frame-first practices*: frame negotiation before
generation, candidate-of-frames before candidate-of-solutions.

**Practices that emerge.** A frame-checkout step before generation. Two-tier consults:
"is this the right question?" precedes "which answer?" The A3 hypothesis doc upgraded so
the top section is *the question being decided*, with explicit sign-off before compute is
spent. A skill that proposes 2–3 candidate framings on fresh tasks.

**Why ignored.** Conflated with override rate; politically uncomfortable (high
frame-redirect indicts upstream spec quality the pack tends to blame on the human); hard
to auto-detect — needs a structured tag, not just a counter-pick.

### H2. Reviewer trust trajectory

**The hidden metric.** Per-reviewer, per-skill: the *direction and velocity* of reviewer
confidence over time. A reviewer who has stopped reading the agent's reasoning carefully
is a different state from one still close-reading; the pack treats them identically.

**What it would expose.** Trust is a depleting human-side resource alongside attention
(T1), with hysteresis — one bad consult costs more than ten good ones earn back. Opens
*trust-budgeted operation* (low-trust skills get extra confirmation; high-trust skills get
sampled review per I14), *trust-rebuild rituals* after a miss, and *reviewer-as-asset*
framing.

**Practices that emerge.** A per-skill trust ledger extending I14 to the reviewer-state
side. A "trust event" tag on every consult outcome — caught defect, missed defect, false
escalation, wasted review — fed into the ledger. Trust quarantine after a miss (forced
trajectory review for N runs). Skill *retirement* from a reviewer when trust drops, rather
than grinding through low-quality output.

**Why ignored.** Trust feels squishy; quantifying it makes the reviewer a measured object
(H14 dignity concern). Override rate looks adjacent and is assumed to cover it — but
override rate is a behavior; trust is a state, and behavior lags state.

### H3. Half-life of skills and gates

**The hidden metric.** When was each skill / gate / fewshot / eval last touched,
validated, or fired? What fraction of the pack's surface area predates the current model?
Stale assets fire silently — either no-op or mis-fire on input shapes they were never
tuned for.

**What it would expose.** The pack treats accumulated assets as assets; past some age,
they are liabilities — wisdom from a model that no longer exists, examples anchoring the
agent on dated patterns. Opens *decay maintenance* as a first-class practice. T3 ("the
pack learns") is currently asymmetric: it models accretion, not decay.

**Practices that emerge.** "Last fired / last validated / last edited" on every skill. A
staleness dashboard. Auto re-validation on model upgrade (I11 covers the declared model
set; half-life also surfaces skills with *no* declared set). A retirement ritual — failed
freshness checks archive the skill rather than letting it mis-fire.

**Why ignored.** Maintenance, not innovation; no credit for retiring stale skills.
Disguised — the existence of a skill in the directory is treated as evidence it works,
even when nothing has fired against it for months.

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

### H6. Decisions-deferred rate

**The hidden metric.** Of consults that close, what fraction close in "let's wait and see /
revisit later / park" rather than a forward decision? The pack treats deferrals as benign
("the artifact captures it"), but a high deferral rate is evidence the consult shape isn't
forcing decisions.

**What measuring it would expose.** Deferral is hidden cost — the question will return,
the context will be colder, the prior agent state may be gone. The design space opened:
*forcing-function design*. Some deferrals are wise (waiting for real information); many
are the consult failing to package the decision in a way that lets the human commit.

**What practices would emerge.** Per-consult tag: forward-decision / structured-deferral /
unforced-deferral. A "what would close this?" required field on every parked decision —
naming the observation or input that would force resolution. A deferral budget per task
class: above threshold, spec quality is the issue, not patience.

**Why we're ignoring it.** Deferrals feel virtuous (humility, T2's "wait deepens the
work"); the cost is invisible because it lands on a future cycle. Also: closure metrics
(E3) treat any close as a close, not distinguishing committed from deferred.

### H7. Surface area of irreversible actions

**The hidden metric.** Total *count* of irreversible-action paths reachable in the pack —
not the per-period burn rate (E4), but the static surface: how many tools, in how many
skills, can fire send/charge/deploy/publish/drop without a staged surface? Surface area
grows monotonically in a pack that only tracks rate.

**What measuring it would expose.** E4 measures usage; H7 measures *exposure*. A pack
whose surface area is growing is accumulating risk even when current burn is low. Design
space opened: *irreversible-surface budget* (cap the number of naked irreversible
bindings, force consolidation through staged surfaces / I12), and audit rituals that
periodically count and prune.

**What practices would emerge.** A per-tool registry with reversibility class (auto/notify/
approve/refuse, per I7). A surface-area count surfaced in the F8 monthly review. A
no-net-new rule: any new irreversible path requires retiring an existing one or routing
through an existing staged surface.

**Why we're ignoring it.** Easy to count but nobody is counting; the pack's discipline is
on usage events, not the static graph. Also: removing irreversible paths is dull
maintenance work that competes with feature work for attention.

### H8. Pack self-knowledge depth

**The hidden metric.** What can the pack answer about itself, on demand, without a human
constructing the answer from scratch? "What skills exist?" "Which fired this week?" "Which
have never been validated against the current model?" "What's the override rate on
skill X?" If a question requires hand-rolled investigation, the pack doesn't know that
thing about itself.

**What measuring it would expose.** A pack with shallow self-knowledge cannot run any of
the meta-practices (M1–M5) reliably; every retrospective is a from-scratch investigation.
The design space opened: *introspectable pack* — assets discoverable by query, metrics
queryable by skill/task-class/reviewer, audit trails that aren't pulled from chat scrollback.

**What practices would emerge.** A `pack status` command that answers a fixed catalog of
questions about the pack's current state. Mandatory metadata on every skill (last-fired,
owner, model set, reversibility class). A self-audit skill that runs the catalog and
flags gaps. Concretely: most of the metrics in this very document presuppose this
infrastructure — without H8 the others are aspirational.

**Why we're ignoring it.** It's infrastructure, not practice; nobody escalates because
self-knowledge is shallow, they just spend extra hours when an audit comes due. Also:
each individual metric looks measurable in isolation, so the systemic gap stays
invisible.

### H9. Distance from last known-good state

**The hidden metric.** For an agent in a long session: how many steps / file edits / tool
calls since the last state a human explicitly affirmed? B5 (externalize state) and C6
(plan-doc) provide the substrate; nothing measures *drift* from a checkpointed-good state.

**What measuring it would expose.** Drift is silent and compounding. An agent twenty
steps past its last green light is operating on twenty layers of unverified inference; a
review at step twenty is much more expensive than at step five. Surfaces design space
around *drift budgets* and *checkpoint cadence*: forced re-affirmation when distance
exceeds threshold, structural rollback to last-good rather than forward-patching when
something goes wrong.

**What practices would emerge.** A drift counter on every long-running session.
Auto-pause on threshold with a sweep-ready summary (overlaps I13 backpressure but on the
session-internal axis, not the queue axis). "Snap back" as a first-class verb — return to
last-known-good and replay forward with the new information.

**Why we're ignoring it.** No instrumentation captures "last known-good"; the concept
isn't even named in the pack. Disguised by reversibility framing — "we can always undo"
hides the fact that undoing twenty steps is much more expensive than undoing two.

## Recommendations

Of the nine candidates, three open the largest design space if the pack started measuring
them. Each is generative because it exposes a *category* of work the current metric set
cannot see, not just a sharper version of an existing number.

**1. Frame-redirect rate (H1) — most generative.** Distinguishing "wrong answer" from
"wrong question" is the move that lets the pack invest upstream of generation. Every
practice in the current set (P1–P6, B1–B26) operates *after* the frame is set; if frame
errors are common, the entire practice stack is patching the wrong layer. Measuring this
forces the pack to invent frame-checkout rituals, candidate-of-frames before
candidate-of-solutions, and a sharper hypothesis-doc shape (B4 with the question itself as
the deliverable). It is also the most ROC-shaped reframe in the catalog: just as MTTR
exposed crash-only software and microreboots, frame-redirect exposes a class of design
moves (frame-first generation, two-tier consults, framing-as-artifact) the pack currently
cannot name.

**2. Reviewer trust trajectory (H2).** The pack's economics rest on T1 (attention as
currency), but T1 silently assumes constant-quality attention. Trust is the missing state
variable. Measuring trajectory — not just override rate — converts the reviewer from a
consumed resource into a cultivated asset and opens the design space of trust-rebuild
rituals, trust-aware autonomy sliders, and skill-level trust ledgers (sharpening I14).
This is the metric most likely to reshape the *human side* of the pack, where the current
metric set is silent.

**3. Half-life of skills and gates (H3).** T3 says the pack learns; the pack's metrics
only model accretion. Half-life surfaces the symmetric truth: the pack also rots. This
exposes a maintenance discipline the pack is missing entirely — periodic re-validation,
asset retirement, model-upgrade re-tuning beyond what I11 covers. It is also the cheapest
to instrument (a timestamp on every asset) and the most under-rewarded culturally, which
is exactly why naming it as a metric is generative: it forces a kind of work the pack
otherwise will not do.

The honest synthesis: H8 (pack self-knowledge depth) is a precondition for the others.
Measuring frame-redirects, trust trajectories, or skill half-life requires an
introspectable pack. H8 isn't itself the most generative metric, but it gates the
infrastructure under which the top three become real rather than aspirational. If only one
investment is made, make it H8; the others follow.
