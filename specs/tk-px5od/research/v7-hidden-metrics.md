# V7 Hidden Metrics — What the Pack Is Not Measuring

## Summary

The pack's current metrics are producer-side and rate-shaped — counts and ratios about
what the agent does (escalation rate, cull rate, override rate, eval pass, reversibility
burn, closure latency). All of them implicitly treat the human reviewer as a
constant-quality oracle who receives output. That assumption is the blind spot. Reviewers
degrade, frames go unchallenged, the pack's own self-knowledge stays implicit, and whole
categories of work — those that resolve in deferral, re-framing, or slow trust erosion —
leave no trace in the current numbers. The generative reframe is to shift from
*agent-side throughput metrics* to *reviewer-state and frame-state metrics*: how clear is
the human's mental model right now, how stale are the artifacts the pack relies on, and
how often does the agent get the *question* wrong versus its *answer* to a correct
question. Three candidates below — **Frame-redirect rate**, **Reviewer trust
trajectory**, and **Half-life of skills/gates** — expose entire design spaces
(frame-first practices, reviewer-as-asset cultivation, decay maintenance) the current
metric set cannot see.

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

**The hidden metric.** Wall-clock between the agent producing reviewable output and a
human actually engaging. Not E3 (action-item lifecycle) — *attention-arrival latency*.

**What it would expose.** The pack optimizes the cost of each consult once a human reads,
but doesn't measure queue depth in front of the human. A reviewer engaging 18 hours later
engages with stale context. Opens *queue-aware generation*: deeper queue → more
self-contained, context-resilient artifacts; shallow queue → denser, faster handoffs.

**Practices that emerge.** Queue-depth-aware autonomy (I2/I13). Backpressure: refuse new
generation until queue drains. Aging tags on consults. A re-context step where the agent
refreshes its framing before the human engages with old output.

**Why ignored.** Needs instrumentation on both sides (when did the human *actually* look?).
Disguised as closure latency, which starts only after judgment.

### H5. Information-density-per-consult

**The hidden metric.** Bits of decision-relevant signal per token (or per second of
attention). P5 names density as a principle; the pack does not measure whether actual
consults achieve it.

**What it would expose.** Principle without metric is exhortation. An 800-word consult
delivering one bit ("approve / reject") is an attention burn the pack cannot detect.
Opens *consult compression*: templates that bound length per decision-bit, automated lede
checks (P4), rejection of consults below a density threshold.

**Practices that emerge.** A consult linter on draft escalations (decision tokens / total
tokens as a rough proxy). A lede check: can the human decide from the terminal line
alone? Self-rewrite loops the agent runs against itself before delivery.

**Why ignored.** Bits-of-signal is fuzzy and varies by reviewer. Also: G2 rewards
thorough exploration, which can quietly subsidize verbose output as evidence of effort.

### H6. Decisions-deferred rate

**The hidden metric.** Of consults that close, what fraction close in "wait and see /
revisit / park" rather than a forward decision? The pack treats deferrals as benign; a
high deferral rate suggests the consult isn't forcing decisions.

**What it would expose.** Deferral is hidden cost — the question returns colder, prior
agent state may be gone. Opens *forcing-function design*: distinguishing wise deferrals
(waiting for real information) from unforced ones (the consult failed to package the
decision).

**Practices that emerge.** Per-consult tag: forward / structured-deferral / unforced.
"What would close this?" as a required field on every parked decision. A per-task-class
deferral budget — above threshold, spec quality is the issue, not patience.

**Why ignored.** Deferrals feel virtuous (humility, T2's "wait deepens the work"); the
cost lands on a future cycle, invisible now. E3 treats any close as a close.

### H7. Surface area of irreversible actions

**The hidden metric.** Static *count* of irreversible paths reachable in the pack — not
E4's per-period burn, but how many tools across how many skills can fire
send/charge/deploy/publish/drop without a staged surface. Surface grows monotonically in
a pack that tracks only rate.

**What it would expose.** E4 measures usage; H7 measures *exposure*. A pack with growing
surface accumulates risk even when current burn is low. Opens *irreversible-surface
budget*: cap naked bindings, force consolidation through staged surfaces (I12), audit
periodically.

**Practices that emerge.** A per-tool registry with reversibility class (per I7).
Surface-area count in the F8 monthly review. A no-net-new rule: any new irreversible path
requires retiring one or routing through an existing staged surface.

**Why ignored.** Easy to count, but nobody is. Discipline is on usage events, not the
static graph. Removing irreversible paths is dull maintenance competing with feature work.

### H8. Pack self-knowledge depth

**The hidden metric.** What the pack can answer about itself on demand without a human
hand-rolling the answer. "What skills exist?" "Which fired this week?" "Which haven't
been validated on the current model?" "Override rate on skill X?" If a question needs
investigation, the pack doesn't know.

**What it would expose.** Shallow self-knowledge means meta-practices (M1–M5) cannot run
reliably; every retrospective is from-scratch. Opens *introspectable pack*: assets
discoverable by query, metrics queryable by skill/task-class/reviewer, audit trails that
aren't pulled from chat scrollback.

**Practices that emerge.** A `pack status` command answering a fixed catalog. Mandatory
metadata on every skill (last-fired, owner, model set, reversibility class). A self-audit
skill that runs the catalog and flags gaps. Most metrics in this document presuppose this
infrastructure.

**Why ignored.** Infrastructure, not practice; no escalation when self-knowledge is
shallow, just extra audit hours later. Each metric looks measurable in isolation, so the
systemic gap stays invisible.

### H9. Distance from last known-good state

**The hidden metric.** For a long-running agent: how many steps / file edits / tool calls
since the last state a human explicitly affirmed? B5 and C6 provide the substrate;
nothing measures *drift*.

**What it would expose.** Drift is silent and compounding. An agent twenty steps past
its last green light is running on twenty layers of unverified inference; review at step
twenty is far more expensive than at step five. Opens *drift budgets* and *checkpoint
cadence*: forced re-affirmation past threshold, rollback to last-good rather than
forward-patching.

**Practices that emerge.** A drift counter per session. Auto-pause on threshold with
sweep-ready summary (session-internal sibling of I13's queue backpressure). "Snap back"
as a first-class verb — return to last-known-good and replay forward with new
information.

**Why ignored.** No instrumentation captures "last known-good"; the concept isn't named.
Disguised by reversibility framing — "we can always undo" hides that undoing twenty
steps is much more expensive than undoing two.

## Recommendations

Three of the nine open the largest design space — each generative because it exposes a
*category* of work the current metric set cannot see, not just a sharper version of an
existing number.

**1. Frame-redirect rate (H1) — most generative.** Distinguishing "wrong answer" from
"wrong question" lets the pack invest upstream of generation. Every current practice
(P1–P6, B1–B26) operates *after* the frame is set; if frame errors are common, the whole
practice stack is patching the wrong layer. Measuring this forces frame-checkout
rituals, candidate-of-frames before candidate-of-solutions, and B4 sharpened so the
question itself is the deliverable. The most ROC-shaped reframe in the catalog: as MTTR
exposed crash-only software and microreboots, frame-redirect exposes frame-first
generation, two-tier consults, and framing-as-artifact — design moves the pack currently
cannot name.

**2. Reviewer trust trajectory (H2).** T1 rests on attention-as-currency but silently
assumes constant-quality attention. Trust is the missing state variable. Measuring
trajectory — not just override rate — converts the reviewer from a consumed resource
into a cultivated asset, opening trust-rebuild rituals, trust-aware autonomy sliders,
and skill-level trust ledgers (sharpening I14). The metric most likely to reshape the
*human side* of the pack, where the current set is silent.

**3. Half-life of skills and gates (H3).** T3 says the pack learns; the pack's metrics
only model accretion. Half-life surfaces the symmetric truth — the pack also rots. This
exposes a maintenance discipline the pack lacks entirely: periodic re-validation, asset
retirement, model-upgrade re-tuning beyond what I11 covers. Cheapest to instrument (a
timestamp), most under-rewarded culturally — which is exactly why naming it forces work
the pack otherwise will not do.

Honest caveat: **H8 (pack self-knowledge depth) is a precondition for the other three.**
Measuring frame-redirects, trust trajectories, or skill half-life requires an
introspectable pack. H8 isn't the most generative metric on its own, but it gates the
infrastructure under which the top three become real rather than aspirational. If only
one investment lands, make it H8; the others follow.
