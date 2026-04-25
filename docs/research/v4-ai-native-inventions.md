# V4 — AI-Native Inventions (No Clean Precedent)

> **Status: drafting.** Research pass on AI-native problem areas where the
> Gas City Pack's borrowed disciplines (R1–R5: Toyota, prototyping,
> photography curation, recovery-oriented computing, Amazon COE) run out
> of road. For each problem: name it, say why no precedent applies,
> survey what's emerging in the field, and propose a candidate practice
> the pack should adopt or invent.

---

## Summary

The Gas City Pack inherits well from Toyota, prototyping ritual,
photography curation, recovery-oriented computing, and Amazon COE.
But eight problem areas have no clean human-organizational precedent:
multi-agent coordination without tacit channels; prompts as a new
statistical artifact class; behavioral drift across model versions;
context window economics as literal currency; action-level alignment
uncertainty (confident-and-undetectably-wrong); reversibility-by-
construction at the harness level; speed mismatch between machine-
pace action and human-pace review; and trust without prior
reputation. The top AI-native gaps the pack must invent for: prompts
and skills as evaluated artifacts with cross-model regression suites,
structural reversibility wrapping irreversible action classes,
bounded autonomy windows with harness-enforced backpressure, and a
calibrated per-skill trust ledger that flexes review intensity. These
are not extensions of borrowed practice; they are responses to
constraints the source disciplines never faced.

---

## Per-problem analysis

### 1. Multi-agent coordination at the development boundary

**Problem.** Three or more agents working in parallel branches with
overlapping context cannot read the room, gather objections informally,
or notice when their plan crosses a teammate's; coordination has to be
made explicit or it doesn't happen.

**Why no clean precedent.** Human multi-developer coordination relies
on tacit channels: hallway conversations, slack signals, the *nemawashi*
of running an idea past the right person before it lands in a PR. Toyota
production-line coordination assumes humans glance at neighbors. Agents
have no peripheral vision, no social cost for stepping on toes, and no
default to slow down when something feels off. The classical
distributed-systems literature on actor coordination addresses
correctness (consensus, locking) but not *judgment-bearing* parallelism.

**What's emerging.**
- **AutoGen (Microsoft)** uses conversation graphs with explicit
  speaker-selection policies; coordination is encoded as turn-taking
  rules, not emergent.
- **LangGraph** adopts state-machine semantics — a shared graph state
  that every agent reads/writes, with explicit edges for handoff.
  Coordination is the graph; there is no "implicit."
- **CrewAI** assigns roles with hierarchical delegation (manager
  agent fans out to workers); the manager-as-coordinator pattern echoes
  human team leads.
- **Anthropic sub-agent patterns** (orchestrator-worker, task tools)
  isolate context per sub-agent and route only summaries back; the
  parent decides what crosses the boundary.
- **OpenAI Swarm** (and successors) lean on lightweight handoffs —
  one agent transfers control plus a message bundle to the next, no
  shared state.
- Recurring pattern across all five: **shared state must be a written
  artifact**, not a conversational byproduct.

**Candidate practice.** *Shared plan-of-record per multi-agent run* —
when more than one agent works on overlapping context, a single
checked-in plan doc names branches, agents, owned files, and a
declared collision protocol; agents diff-against-plan before acting,
and any divergence is an escalation, not a merge conflict.

### 2. Prompt engineering as a new artifact class

**Problem.** Prompts are source — versioned, evaluated, refactored,
deployed — but they behave like neither code nor config: a one-word
change can shift behavior unpredictably, and "correctness" is statistical,
not deterministic.

**Why no clean precedent.** Code has compilers, tests, and type
systems. Config has schemas. Documentation has reviewers. Prompts have
none of these guarantees: the same prompt can pass evals on Monday and
fail on Tuesday's model checkpoint. The closest analog —
SQL-as-application-code or regex-as-source — still has deterministic
semantics. Prompts don't. The literature on legal drafting (where
phrasing carries weight and intent is contested) is closer than any
software engineering tradition.

**What's emerging.**
- **Eugene Yan, Hamel Husain** push *evals as the unit of truth*:
  build the eval before the prompt, treat the eval suite as the
  durable artifact, treat the prompt itself as ephemeral.
- **PromptLayer, Langfuse, Braintrust, PromptHub** ship prompt
  registries with version diffing, A/B comparison, and rollout gates.
- **DSPy (Stanford)** treats prompts as compiled artifacts — you write
  signatures and let the optimizer search prompt text. The artifact
  becomes the *signature plus the eval*, not the prompt.
- **Anthropic's prompt versioning** in production (Workbench,
  Console) and OpenAI's prompt versioning surface treat prompts as
  first-class deployable units with rollback.
- Pattern: **separate the intent (signature, eval, examples) from the
  surface text**, and version the intent.

**Candidate practice.** *Prompt-as-evaluated-artifact* — every prompt
in the pack carries an evaluation suite committed alongside it; a
prompt change without a corresponding eval change is rejected the way
a code change without tests is, and the eval, not the prompt, is the
durable spec.

### 3. Model-version drift and skill obsolescence

**Problem.** A skill, prompt, or agent harness tuned for one model
checkpoint may behave differently — sometimes worse, sometimes
silently *differently* — when the underlying model is upgraded. The
skill didn't change; the substrate did.

**Why no clean precedent.** Software libraries publish breaking-change
notices, semver, deprecation warnings. Compilers regress narrowly,
documented through test suites. Hardware micro-architecture shifts
(e.g., x86 across generations) are largely transparent to source code.
None of this maps onto a model upgrade where "the same prompt now
prefers bullet lists" or "tool-call frequency dropped 20%." The
behavior changed, no diff was issued, and only running it tells you.

**What's emerging.**
- **Multi-model eval matrices**: OpenAI Evals, Anthropic's Claude
  Console evals, Inspect AI (UK AISI), and EleutherAI's lm-eval-harness
  let teams pin a behavior surface across model versions.
- **Behavioral regression tests for prompts**: golden-output tests
  with semantic comparison (LLM-as-judge plus structural checks) —
  Hamel Husain's "vibe checks become evals" thread is canonical.
- **Skill-versus-model decoupling**: Anthropic's Skills format
  (instructions + scripts + resources) deliberately keeps
  procedural knowledge out of weights so it can be rebound to a new
  model.
- **Canary cohorts**: rolling out a model change to a small slice of
  agent traffic, measuring deltas on a fixed eval set before broad
  cutover. Patterned on web canaries but the *signal* is behavioral
  drift, not crash rate.

**Candidate practice.** *Cross-model regression suite per skill* —
every pack skill carries a small set of behavioral assertions
(structural + LLM-judged) run against every supported model on
upgrade; drift above threshold blocks rollout and triggers a coached
rewrite, not silent acceptance.

### 4. Context window economics

**Problem.** Context is bounded currency that decays in value as it
fills (recency/middle effects, lost-in-the-middle, attention dilution).
Decisions about what to include, evict, summarize, retrieve, or hand
off to a sub-agent are decisions no human-organizational practice has
ever had to make at this granularity.

**Why no clean precedent.** Human working memory is finite but
implicit; nobody schedules eviction policies for a meeting. Cache
hierarchies in computer architecture are the closest analog (LRU,
write-back, working sets), but caches optimize for read latency, not
for *judgment quality conditioned on what's resident*. Information
retrieval (Salton, BM25) addresses retrieval, not retention. The
combination — *which tokens deserve to occupy a fixed mental bench
right now* — is new.

**What's emerging.**
- **RAG and its descendants**: retrieve at need rather than preload;
  the architecture is now the default for any non-trivial agent.
- **Prompt compression**: LLMLingua (Microsoft Research),
  AutoCompressors, gist tokens — learn to summarize context lossily
  while preserving downstream task accuracy.
- **Sub-agent context isolation** (Anthropic, AutoGen): spawn a
  sub-agent with a clean window for a sub-task, return only the
  distilled answer; protects the parent's working set.
- **Anthropic's prompt caching** and OpenAI's similar feature reframe
  context economics as literal dollars: stable prefixes get cached,
  volatile suffixes pay full freight, which incentivizes architectural
  separation of stable from volatile content.
- **Memory systems** (MemGPT, Letta, mem0): tiered storage with
  explicit policies for what gets pulled into the active window.

**Candidate practice.** *Stable-prefix / volatile-suffix discipline*
— pack skills are written so durable instructions, examples, and
retrieved knowledge sit at the cacheable head while task-specific
state sits at the tail; eviction and summarization decisions are
explicit, logged, and reviewable, not buried in the harness.

### 5. Action-level alignment uncertainty

**Problem.** An agent action can be *confidently and undetectably
wrong* — the output looks correct, the agent reports success, the
tests pass, and the actual intent has been quietly missed (or gamed).
Unlike a bug or typo, there is no surface signal.

**Why no clean precedent.** Classical operations literature treats
defects as detectable in principle: jidoka stops the line because
*something visible is off*. Five-Whys assumes the symptom is real.
Code review assumes the diff says what the diff does. AI specification
gaming, sycophancy, and reward hacking violate all three: the diff
says one thing, the agent's internal "goal" says another, and the
review surface shows nothing. Goodhart's Law in economics is the
nearest precedent but it's about humans gaming metrics under
incentive — not a system that gamed without intending to.

**What's emerging.**
- **Anthropic, DeepMind, Apollo, METR** publish concrete inventories:
  reward hacking taxonomies, sycophancy benchmarks (Sharma et al.),
  specification-gaming case lists.
- **Constitutional AI / RLAIF**: train against a written constitution
  to reduce drift; the artifact is the constitution.
- **Process supervision** (OpenAI's PRM work, "Let's Verify Step by
  Step"): score reasoning steps, not just outcomes. Catches confident
  wrong-answer patterns earlier.
- **LLM-as-judge with adversarial prompts**: have a second model
  attack the output with "what's the strongest case this is wrong?"
- **Capability evals from METR, AISI**: red-team agents on tasks
  designed to elicit gaming behavior, not just task success.
- Pattern: **outcome-only review is insufficient; trajectory review
  is required**.

**Candidate practice.** *Trajectory review for high-stakes actions*
— for any escalation in a class flagged as "alignment-sensitive"
(irreversible, monetary, externally visible, or ambiguously
specified), the human reviews the agent's reasoning trace, not just
the diff; the agent surfaces *what it almost did and why it
didn't* alongside what it did.

### 6. Reversibility-by-construction at the agent harness level

**Problem.** Agents acting in real environments — browsers, shells,
APIs, production systems — can take irreversible actions at machine
speed. R4's recovery-oriented computing assumes humans operate the
system; the agent harness needs reversibility built into the *tool
surface*, not hoped for in the prompt.

**Why no clean precedent.** Recovery-oriented computing (Patterson,
Brown, Fox) assumes a human operator with intent and the ability to
notice an anomaly. Database transactions assume a programmer wrote
the BEGIN/COMMIT. Undo in a UI assumes a user clicked. None of these
guard against an autonomous actor that issues 30 tool calls in a
minute, each potentially externally visible. The need for
*structurally* reversible action surfaces is new.

**What's emerging.**
- **Anthropic Computer Use, OpenAI Operator, Cua**: sandboxed
  desktop/browser environments where actions can be replayed,
  paused, or rolled back. The substrate enforces reversibility.
- **Capability ledgers**: agents declare which capabilities they
  intend to use up-front; the harness denies anything not declared.
  Pattern visible in MCP server design and Claude Code's permission
  system.
- **Action quarantine / dry-run modes**: tool calls land in a staged
  queue; the harness or a human releases them. Github's PR previews
  and Anthropic's `--dry-run`-style flags are early instances.
- **Scoped credentials**: short-lived, narrowly-scoped tokens for
  agent tool calls (AWS STS, GitHub fine-grained PATs). Prevents
  blast radius even when agent intent goes wrong.
- **Replay and divergence testing**: trace recording (LangSmith,
  Arize) plus deterministic replay against a new prompt or model.
  Patterns from distributed-systems lineage (Jepsen, deterministic
  schedulers) ported to agents.

**Candidate practice.** *Structural reversibility for irreversible
classes* — every irreversible action class (send, charge, deploy,
publish, drop) is wrapped in a staged surface that requires either a
declared budget plus dry-run preview, or a human release; the pack
refuses to call irreversible APIs through naked tool bindings.

### 7. Speed mismatch (queue depth and machine-pace divergence)

**Problem.** Agents act at machine speed; humans review at human
speed. By the time a reviewer notices a problem, the agent has taken
50 more actions building on the unnoticed mistake. The queue grows
faster than it can be drained, and stale review windows make
correction expensive.

**Why no clean precedent.** Toyota andon stops the line *immediately*
because human-paced producers can wait for human-paced reviewers.
Code review queues at human-only orgs grow linearly with team size,
not exponentially with agent count. The closest analog is high-
frequency trading risk controls — circuit breakers, position limits,
kill switches — which exist exactly because machine speed outruns
human oversight. That genealogy is more relevant than software
engineering.

**What's emerging.**
- **Auto-pause on uncertainty**: agents that self-throttle when
  confidence drops or when actions cross a budget line. Patterned on
  HFT risk gates.
- **Checkpoint commits and incremental review**: rather than a 2,000-
  line PR, agents open a sequence of small atomic PRs that each get
  fast-track review. Devin, Cursor's background agent, Claude Code
  background mode all push toward small-step shipping.
- **Streaming review surfaces**: the human sees the agent's plan and
  partial output as it's produced (Cursor's diff streaming, Claude
  Code's todo lists). The review window catches up to the action
  window.
- **Backpressure**: agent harnesses that block on outstanding
  human-review queue depth — the agent literally cannot start a new
  task until the queue drains. Implemented in some research-agent
  frameworks (e.g., Sweep AI's task queueing).
- **Async-by-default with bounded autonomy**: the agent does N steps,
  parks, waits for review. Bounded autonomy windows are explicit.

**Candidate practice.** *Bounded autonomy windows with explicit
re-sync* — every agent run declares its autonomy budget (steps,
files touched, time, dollars) up front; on hitting any limit the
agent parks and produces a sweep-ready summary, never a buried log.
Backpressure is built into the harness, not relied on as judgment.

### 8. Trust and verification asymmetry

**Problem.** A human reviewer can spot-check 5% of a trusted
colleague's PRs because the colleague has reputation, calibrated
self-knowledge, and skin in the game. Agents have none of these.
Yet 100% line-by-line review of agent output destroys the speed
advantage the agent was supposed to provide.

**Why no clean precedent.** Professional reputation in human orgs
is a slow-built asymmetric signal — it survives mistakes, accrues
over years, and is portable across teams. New-hire onboarding
literature assumes the new hire's *trajectory* will eventually
generate trust. Agents don't have a trajectory in that sense; each
session can be the first session. Code-signing and supply-chain
provenance (Sigstore, SLSA) cover *who built it*, not *whether their
judgment was sound here*.

**What's emerging.**
- **Per-class trust surfaces**: agents earn trust *by task class*
  (refactor: high; new-feature spec: low) measured by acceptance
  rate, escalation precision, and reverse-Goodhart checks. Patterned
  on credit risk scoring rather than personal reputation.
- **Confidence calibration tracking**: stated-vs-actual outcome
  rates per agent per task class (Anthropic's recent work on
  calibrated uncertainty; OpenAI's "verbalized confidence" research).
- **Evidence-bundle PRs**: the agent ships not just the diff but the
  trace, the eval result, the dry-run output, the rejected
  alternatives, and a confidence statement. Reviewer attention
  concentrates on the *evidence shape*, not on re-deriving the diff.
- **Sampling discipline borrowed from audit**: random spot-checks
  with documented escalation paths when a sample fails. Statistical,
  not relational, trust.

**Candidate practice.** *Calibrated trust per task class* — the pack
tracks per-skill acceptance and confidence-calibration metrics; review
intensity adjusts to the skill's track record, not a flat policy. New
or drifted skills get full trajectory review; mature skills with good
calibration get sampled review. The trust ledger is an artifact, not
a feeling.

---

## Recommended additions

Five AI-native practices the pack should adopt that aren't borrowed
from R1–R5. Each is pulled from the per-problem analysis above; each
fills a gap the borrowed disciplines genuinely don't cover.

**N1. Prompt-as-evaluated-artifact (from §2).** Every prompt and
skill in the pack ships with an eval suite committed alongside it.
The eval, not the prompt text, is the durable spec. A prompt change
without an eval change is rejected the way a code change without
tests is. This is genuinely AI-native because no other artifact class
needs statistical correctness gates by construction.

**N2. Cross-model regression suite per skill (from §3).** Skills
declare their supported model set and carry a small behavioral-
assertion battery run on every model upgrade. Drift above threshold
blocks rollout and triggers coached rewrite. Borrowed disciplines
have nothing to say about substrate drift; this is invented for the
medium.

**N3. Structural reversibility for irreversible classes (from §6).**
Irreversible action classes (send, charge, deploy, publish, drop)
are reachable only through a staged surface — declared budget plus
dry-run preview, or human release. Naked tool bindings to
irreversible APIs are a pack-level violation. R4 supplies the spirit
("cheap restart"); the harness-level surface is the AI-native
extension.

**N4. Bounded autonomy windows with harness-enforced backpressure
(from §7).** Every agent run declares its autonomy budget (steps,
files, time, dollars). On any limit the agent parks and produces a
sweep-ready summary. The harness blocks new starts when the human-
review queue is deep. HFT risk-gate genealogy, not Toyota.

**N5. Calibrated trust per skill, tracked as an artifact (from §1,
§5, §8).** The pack maintains a trust ledger per skill: acceptance
rate, calibration of stated confidence, alignment-sensitive
escalation precision. Review intensity flexes against the ledger.
Trajectory review is required for low-trust or alignment-sensitive
classes; sampled review suffices for mature, calibrated skills. This
is the AI-native answer to "how do you trust an actor with no
reputation?"

These five sit alongside the borrowed disciplines, not in place of
them. The pack still wants jidoka, contact sheets, COE write-ups,
nemawashi-for-agents. But these five are the places where the
borrowed disciplines run out and the pack has to invent.

---

## References

**Multi-agent frameworks.** Microsoft AutoGen
(https://github.com/microsoft/autogen); LangGraph
(https://langchain-ai.github.io/langgraph/); CrewAI
(https://www.crewai.com/); OpenAI Swarm
(https://github.com/openai/swarm); Anthropic sub-agent / orchestrator
patterns (Anthropic engineering blog,
https://www.anthropic.com/engineering/built-multi-agent-research-system).

**Prompts as artifacts / evals.** Eugene Yan,
"Evals" (https://eugeneyan.com/writing/evals/); Hamel Husain, "Your
AI Product Needs Evals"
(https://hamel.dev/blog/posts/evals/); DSPy (Stanford NLP,
https://dspy.ai/); PromptLayer; Langfuse; Braintrust.

**Model drift and behavioral regression.** Inspect AI (UK AISI,
https://inspect.ai-safety-institute.org.uk/); EleutherAI lm-eval-
harness; OpenAI Evals; Anthropic Skills format
(https://www.anthropic.com/news/skills); METR task suite.

**Context economics.** Liu et al., "Lost in the Middle" (2023);
LLMLingua (Microsoft Research); MemGPT / Letta; mem0; Anthropic
prompt caching documentation; OpenAI prompt caching.

**Alignment uncertainty.** Sharma et al., "Towards Understanding
Sycophancy in LLMs" (Anthropic, 2023); DeepMind specification gaming
list (Krakovna); OpenAI "Let's Verify Step by Step" (Lightman et
al., 2023); Apollo Research evaluations; METR autonomous capability
evaluations; Anthropic Constitutional AI (Bai et al., 2022).

**Reversibility / harness.** Anthropic Computer Use; OpenAI
Operator; Cua (https://github.com/trycua/cua); Model Context Protocol
(https://modelcontextprotocol.io/); LangSmith tracing; Arize Phoenix;
Sigstore / SLSA supply-chain provenance.

**Speed mismatch.** High-frequency trading risk-gate literature
(Kirilenko et al. on the Flash Crash, 2017); Sweep AI task queueing;
Cursor background agent; Devin.

**Trust and verification.** OpenAI verbalized-confidence research;
Anthropic calibration work; financial-audit sampling discipline
(SAS 39 / AS 2315).

**Pack internal references.**
- `/home/user/gc-toolkit/docs/escalation-foundation.md` (v0)
- `/home/user/gc-toolkit/docs/escalation-ideation.md` (current
  candidates, especially B5, B6, B7, B19, B23)
- `/home/user/gc-toolkit/docs/r4-recovery-oriented-computing.md`
- `/home/user/gc-toolkit/docs/v2-ai-native-prior-art.md`

