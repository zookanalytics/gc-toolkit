# V2 — AI-Native Prior Art Survey

> **Status: drafting.** Survey of what serious AI-native practitioners are
> actually proposing or running today. Goal: identify patterns that should
> be on the gas city pack's candidate list but aren't yet. Companion to
> R1–R5 (cross-industry priors) and the v1 red team.

---

## Summary

Across serious AI-native practice (Karpathy, Litt, Willison, Anthropic
engineering, OpenAI, LangChain, Cursor/Aider, Replit, Lütke, Hamel/
Eugene Yan, plus pre-2025 priors from Vaccaro and Russell), five
patterns recur that the pack does not yet name. (1) **Escalation
typology** — Notify / Question / Review carry different attention
prices and routing rules; the pack uses one undifferentiated verb.
(2) **Autonomy as a slider, not a binary** — Karpathy's per-task
autonomy dial replaces the implicit "agent acts or escalates"
posture. (3) **Eval-diff as the closure unit** — Hamel/Yan/Anthropic
converge that every fixed escalation should add a held-out eval
case; the eval set is the durable memory. (4) **Context-window
hygiene as a first-class concern** — Anthropic's sub-agents/skills/
hooks treat the main thread's context as scarce and rivalrous, a
sibling to T1. (5) **Lethal trifecta as a named structural hazard**
— Willison's compositional check (private data + untrusted content +
external communication) is sharper than the pack's reversibility
budget framing. Two further strong candidates: snapshot-as-undo for
live-environment agents (Replit) and per-tool approval class as a
typed signature (OpenAI Agents SDK).

---

## Pattern catalog

### 1. Andrej Karpathy — Software 3.0

**What he proposes.** Karpathy frames coding with LLMs as a generation/
verification loop where the human's job is rapid audit. Two load-bearing
ideas: (a) the **autonomy slider** — products should expose a control that
slides from suggest → complete → agent, and the slider is a first-class
design surface, not a hidden mode; (b) **keep verification fast** — the
human stays in the loop only if checking is cheaper than generating. He
argues against "flashy autonomous demos" in favor of partial autonomy
products that incrementally hand off as trust accrues.

**Pack overlap.** The slider concept matches T2 (the human owns the clock)
and the v0 spirit of opinionated engagement. "Verification fast" is a
restatement of P3 (recognition over reading) and P5 (density). The pack
already encodes the asymmetry — generation cheap, verification scarce —
in T1.

**Genuinely new.** The pack does **not** name the slider as an explicit
artifact. Karpathy treats per-action autonomy level as a *configurable
parameter the human dials*, not a fixed posture. This is finer-grained
than the pack's current "escalate or don't" binary.

### 2. Geoffrey Litt — ambient agents, malleable software

**What he proposes.** Litt's recent work centers on two ideas: (a)
**ambient agents** — agents that run continuously in the background on
the user's behalf (watching email, drafts, repos) and surface only on
demand or trigger, replacing the chat-prompt-reply cadence; (b)
**end-user-malleable software** where every UI surface is also a place
the user can edit behavior, with the agent helping. He has also written
about levels of trust ("operator → collaborator → consultant → approver
→ observer" framings appear in adjacent academic work).

**Pack overlap.** Ambient agents fit T2 directly: the agent is *quiet by
default, ready when the human turns*. P6's "context triggers" line up
with malleable surfaces — the user's own artifacts become the prompt
substrate.

**Genuinely new.** The pack assumes a session-bounded agent (one task,
one consult, one decision). Litt's ambient frame implies *long-lived
agents that accumulate context across days/weeks* and surface only when
their watch hits a threshold. This is a different cadence than v0
imagines, and it implies a new practice: **a notification budget**
(how many ambient surfaces is the human willing to receive per day).

### 3. Simon Willison — harnesses, agentic patterns, lethal trifecta

**What he proposes.** Three durable contributions in 2025–2026: (a) the
working **definition of agent** = LLM running tools in a loop toward a
goal; (b) the staged taxonomy *prompt engineering → context engineering
→ harness engineering*, where the harness (sandbox, tools, transcript,
gates) is the unit of design now, not the prompt; (c) the **lethal
trifecta** safety pattern — any agent combining private data + untrusted
content + external communication is exfiltration-vulnerable by
construction, regardless of prompt hygiene.

**Pack overlap.** Harness engineering aligns with B7 (poka-yoke first,
prompt last) — Willison and the pack converge that *structural*
controls dominate prompt-level controls. The lethal trifecta is a
specific instance of B19 (reversibility budgets / quarantine zones).

**Genuinely new.** The trifecta is sharper than B19: it names a
*compositional* hazard rather than a per-action one. The pack should
adopt the trifecta as a named anti-pattern and require any agent design
to declare which leg it severs. Also genuinely new: Willison's
**transcript-as-artifact** habit (he publishes raw agent transcripts);
this is a B5 cousin but applied to *learning corpus*, not recovery.

### 4. Anthropic engineering — skills, sub-agents, hooks, plugins

**What they propose.** The Claude Code stack now ships four composable
primitives with public docs: (a) **Skills** — directories with a
`SKILL.md` discoverable on demand, dynamically loaded into context only
when relevant; (b) **Sub-agents** — specialized agents with isolated
context windows whose verbose work stays out of the main thread, only
summaries return; (c) **Hooks** — deterministic shell-side handlers
firing on lifecycle events (Stop, UserPromptSubmit, PreToolUse) that
the harness executes, not the model; (d) **Plugins** — bundles of the
above. The Anthropic engineering post "Equipping agents for the real
world with Agent Skills" frames skills as how an org's tacit
knowledge becomes agent-loadable.

**Pack overlap.** Skills map to B5 (externalized state) and to T3
(learning lives in artifacts). Sub-agents instantiate B22 (agent as
witness, human as author) — the verbose worker keeps the reviewer's
context clean. Hooks are direct instances of B7 (poka-yoke first):
they are *structural* gates the model cannot bypass.

**Genuinely new.** Two patterns the pack does not yet name:
(i) **context-window hygiene as a first-class concern** — sub-agents
exist *because* main-thread context is sacred; the pack treats human
attention as scarce but not the agent's working context.
(ii) **lifecycle hooks as the home of policy** — UserPromptSubmit /
PreToolUse / Stop are the semantic anchors where pack invariants
should live, not in system-prompt prose.

### 5. OpenAI engineering — Operator, Agents SDK, watch mode

**What they propose.** Operator (the Computer-Using Agent) and the
Agents SDK both make human approval a first-class control flow:
(a) **declared-approval tools** — tools register a flag that says "this
call needs human approval"; the SDK pauses, surfaces the call, and
resumes only on accept; (b) **watch mode** — for sensitive surfaces
(email, banking) the agent runs but the user is asked to actively
supervise; (c) **categorical refusal** — Operator declines whole task
classes (banking, hiring decisions) regardless of prompt.

**Pack overlap.** Watch mode is a reversibility-budget instance (B19).
Categorical refusal is a strong B7 (poka-yoke first) example —
structural, not promptable.

**Genuinely new.** The pack does not yet name **per-tool approval as a
declarative property**. A tool's signature should carry its escalation
class; approval is a typed gate, not a runtime decision. This is
sharper than B6 (andon for agents) which describes the trigger but not
the implementation surface.

### 6. Cursor / Continue.dev / Aider — rules systems, conventions files

**What they propose.** All three converge on **per-repo rules**:
Cursor's `.cursor/rules/*.mdc` (modern), Continue's `.continuerules`,
Aider's `CONVENTIONS.md`. Rules carry frontmatter (when this rule
fires: globs, file types, agent mode), enabling **scoped, conditional**
context injection. Modern Cursor allows multiple `.mdc` files; rules
attach to file globs, so the agent loads the right rules for the
right file. Community pattern collections (e.g. `awesome-cursorrules`)
treat rules as a shareable artifact.

**Pack overlap.** Rules systems instantiate P1's "role-specific
evolving rules." They are also B5 cousins (externalized state) and
B15 (closure-as-merged-artifact — a rule diff is the unit of closure
when a postmortem identifies a recurring miss).

**Genuinely new.** Two patterns:
(i) **scoped rule activation by glob/context** — pack rules are
implicitly global today; the prior art says rules should fire
*conditionally* on what's loaded, with frontmatter declaring the
trigger.
(ii) **rules-as-PR-artifact** — when an escalation closes with "next
time, do X," that next-time should be a *committed rule diff*,
reviewable like code. The pack already implies this in B15 but does
not name the rule file as the canonical home.

### 7. Replit / Amjad Masad — Agent V2, env-as-product

**What he proposes.** Replit Agent V2 treats the **dev environment
itself** as the agent's primary surface: the agent provisions, runs,
and recovers a sandboxed VM, with the user watching live as it
edits, runs, fails, and retries. Masad has argued publicly that the
right unit of agentic work is "the live environment, not the diff."
Failures roll back via environment snapshots, not git reverts. The
agent's "what I did" is shown as a running app, not a description.

**Pack overlap.** Live-running output as the surface is a strong P3
(recognition over reading) and P5 (density) instance. Environment
snapshots are a B19 (reversibility) instance.

**Genuinely new.** **Snapshot-as-undo for agent runs** is a structural
control the pack should add: an agent operating on real state must be
able to roll the *world*, not just the *commit*, back to a known
point. The pack's B5 externalizes plan and decisions; Replit
externalizes the *runtime*.

### 8. Shopify / Tobi Lütke — AI use as baseline, "no AI no hire"

**What he proposes.** Lütke's internal memo (April 2025) made AI
fluency a baseline expectation across Shopify engineering: (a)
**reflexive AI use** as the default starting point for any task;
(b) **AI use as a hiring filter** — managers must justify a non-AI-
augmented hire; (c) **public learnings shared** across the org so AI
use compounds. He reports that the team's *bar* for what counts as
"productive" has reset because the floor moved.

**Pack overlap.** The "compounding learnings" frame matches T3 and
B14 (per-event AAR). The "bar moved" observation is the v1 red team's
"escalation rate isn't the metric, escalation *quality* is."

**Genuinely new.** Lütke's memo names an org-level pattern: **AI
fluency as a competency line, not a tool**. The pack is silent on
*who* the human is and what skills they need. A candidate practice:
the pack assumes a *practiced* reviewer, and reviewer skill should be
explicitly cultivated, not assumed.

### 9. LangGraph / LangChain — interrupt(), Notify/Question/Review

**What they propose.** LangGraph's `interrupt()` primitive pauses a
graph execution, persists state, and resumes on a `Command`. Built
atop this, LangChain's "ambient agents" post defines three escalation
types — **Notify** (FYI, no action), **Question** (agent stuck,
needs input), **Review** (agent has a draft action, needs approval).
Each has different latency and attention costs.

**Pack overlap.** Direct parallel to P1 and B6. The three classes are
the cleanest existing taxonomy of escalation type.

**Genuinely new.** The pack uses one verb ("escalate") but the prior
art uses three with different attention prices. Notify is cheap and
batchable; Question is mid (synchronous-ish); Review is expensive
(must precede an irreversible action). The pack should adopt the
**three-type taxonomy** explicitly: each escalation declares its
class, and the harness can batch/route by class.

### 10. Practitioner posts — Hamel Husain, Eugene Yan, swyx, Goodside

**What they propose.**
- **Hamel Husain** — *evals are the moat*. "Manually look at 20–50
  outputs after every significant change." A single domain expert as
  the quality decider. Without evals, every other practice is theater.
- **Eugene Yan** — *Patterns for Building LLM-based Systems & Products*
  (and the co-authored "What We Learned from a Year of Building with
  LLMs"): evals, retrieval, guardrails, defensive UX. Treats evals as
  the regression suite for non-deterministic systems.
- **swyx (Shawn Wang)** — *AI Engineer* taxonomy; "context engineering"
  vs. prompt engineering; agent-team-of-rivals patterns.
- **Riley Goodside** — adversarial prompting catalog; calibration
  failure modes; specific glitch tokens / jailbreak shapes.

**Pack overlap.** Evals overlap with B18 (held-out adversarial eval)
and B23 (confidence calibration). Defensive UX overlaps P2.

**Genuinely new.** **Evals as the spine, not a sidecar.** The pack
treats learning/closure as artifact-driven (B15), but the prior art is
unanimous: *the eval set is the durable artifact*. Every closed
escalation should add a regression eval. The pack should name **eval
diff as the closure unit** more strongly than it does in B15.

### 11. Pre-2025 academic priors — Vaccaro, Mitchell, Russell

**What they propose.**
- **Vaccaro et al. (2024) Nature Human Behaviour meta-analysis** —
  human-AI teams underperform the better of the two alone in many
  cases; collaboration overhead is real; design must be deliberate.
- **Tom Mitchell** — never-ending learning; agents that accumulate
  task-specific knowledge with human teaching loops.
- **Stuart Russell** — assistance games, value uncertainty: agents
  should be *uncertain about objectives* and seek human input
  precisely when uncertainty is high. The CIRL framework.

**Pack overlap.** Russell's "ask when uncertain" is exactly P1 and B6.
Mitchell's coach-apprentice is A4 and B21.

**Genuinely new.** The Vaccaro meta-analysis is a load-bearing prior
the pack should cite: **human-AI teaming is not free**. It can lose to
either side alone unless deliberately designed. This is empirical
support for X1 (selection beats execution) and a justification for the
pack's existence — the default of "just put a human in the loop"
*does not work* without the practices the pack codifies.

---

## Overlap and gap analysis

### What the pack already covers (with prior-art validation)

| Pack item | Validated by |
|-----------|--------------|
| T1 attention scarce | Karpathy (verification cost), Vaccaro (teaming overhead) |
| T2 human owns clock | Litt (ambient), LangGraph (interrupt) |
| T3 learning compounds | Lütke (compounding), Mitchell (never-ending learning) |
| P1 only-the-human surface | Russell (ask-when-uncertain), LangGraph (Question) |
| P2 opinion + options | OpenAI Operator (declared-approval pause-with-context) |
| P3 recognition over reading | Karpathy (verify fast), Replit (live env) |
| B5 externalize state | Anthropic Skills, Cursor rules, Aider conventions |
| B6 andon for agents | LangGraph Notify/Question/Review |
| B7 poka-yoke first | Anthropic hooks, OpenAI tool-approval flag, Willison harness |
| B14 per-event AAR | Hamel "look at 20-50 outputs" |
| B19 reversibility budgets | OpenAI watch mode, Replit snapshots, Willison trifecta |
| B22 agent-as-witness | Sub-agents (verbose work isolated) |
| B18 held-out evals | Hamel/Eugene Yan eval discipline |

### Where the prior art goes further than the pack

1. **Autonomy is a slider, not a binary.** Karpathy and the OpenAI/
   academic "levels of autonomy" frame treat autonomy as a continuous
   per-action dial. The pack's "escalate or don't" is too coarse.

2. **Escalations have type, not just yes/no.** LangChain's three
   classes (Notify / Question / Review) carry different attention
   prices and routing rules. The pack uses one undifferentiated verb.

3. **Ambient long-running agents.** The pack assumes session-bounded
   work. Litt and LangChain assume agents that watch indefinitely and
   speak rarely. A different attention shape.

4. **Context-window hygiene is its own discipline.** Sub-agents,
   skills (loaded on demand), and hooks (out-of-band gates) all exist
   to keep the main thread's context clean. The pack worries about
   *human* attention; agent context is also a finite, rivalrous
   resource that affects output quality.

5. **Evals are the regression suite.** Hamel/Eugene Yan/Anthropic
   converge: every fixed escalation should land as a held-out eval
   case. The pack hints at this in B18 but does not make eval-as-
   closure-artifact load-bearing.

6. **Lethal trifecta as a named hazard.** Willison's compositional
   safety check is a specific shape the pack does not yet name.

7. **The dev environment as the agent's surface, not the diff.**
   Replit's live-env model says the artifact-of-choice is sometimes
   the running thing, not the patch. P3/P5 hint at this; the pack
   should make snapshot/rollback explicit.

8. **Reviewer skill is cultivated, not assumed.** Lütke's memo and
   the Vaccaro meta-analysis converge: human-AI teaming requires
   *practiced* humans. The pack assumes a competent reviewer.



---

## Recommended additions

Specific candidates the pack should add to ideation. Numbered to slot
into existing sections.

**B27. Escalation class taxonomy: Notify / Question / Review.** *(AI:
LangChain ambient agents)* Every escalation declares its class. Notify
is batchable and async; Question pauses agent progress until answered;
Review precedes an irreversible action and must complete before the
action runs. The harness routes by class — Notify can land in a daily
digest, Question in an inbox, Review on a synchronous attention
surface. Replaces the pack's single "escalate" verb. **strong.**

**B28. Autonomy slider as a per-task setting.** *(AI: Karpathy +
Levels-of-Autonomy paper)* The human chooses the autonomy level for a
task: *suggest → propose → act-with-approval → act-then-report →
ambient*. The agent's behavior — when to surface, what to render —
is a function of the slider, not hard-coded. The pack's posture
becomes parametric, not monolithic. **strong.**

**B29. Eval-diff as the closure unit.** *(AI: Hamel/Eugene Yan/
Anthropic)* B15 says "closure is a commit hash." Sharpen: every
closed escalation must add (or modify) a held-out eval case that
would have caught the original miss. The eval set is the durable
memory. Without this, B18 (adversarial eval) has no source of
training pressure. **strong.**

**B30. Context-window hygiene via sub-agents and lazy-loaded
skills.** *(AI: Anthropic)* Treat the main agent's context as a
scarce shared resource. Verbose work happens in sub-agents;
specialized knowledge loads on demand from skills; hooks enforce
gates without occupying tokens. The pack's T1 (attention scarce)
gets a sibling: **agent context is also scarce and rivalrous**. New
practice: every long task is decomposed so the main thread sees
summaries, not transcripts. **strong.**

**B31. Lethal trifecta gate.** *(AI: Willison)* Any agent design
that combines (private data) + (untrusted content) + (external
communication) declares which leg it severs. No exceptions. This is
a structural/poka-yoke gate at design time, not a prompt-level
check. Sharpens B19. **strong.**

**B32. Snapshot-as-undo for live-environment agents.** *(AI: Replit)*
Agents that mutate real state (filesystem, databases, deployed
services) operate inside a snapshotted environment with explicit
roll-back, not just git revert. The recovery unit is the *world
state*, not the *commit*. Extends B5 from plan-state to runtime-
state. **lean+.**

**B33. Per-tool approval class as a typed signature.** *(AI: OpenAI
Agents SDK)* Every tool declares its approval class in its
signature: *auto / notify / approve / refuse*. The harness enforces;
the model cannot escape by re-prompting. Sharpens B6 — the trigger
is a type, not a runtime decision. **strong.**

**B34. Reviewer-skill cultivation as an explicit pack concern.**
*(AI: Lütke + Vaccaro)* The pack assumes a competent reviewer;
empirically, human-AI teams underperform without practiced humans.
A practice: track reviewer accuracy (caught vs. missed defects,
overrides that turned out wrong) and use it as input to coach-
apprentice cadence (B21). Reviewer skill is a learned craft.
**lean+.**

**B35. Notification budget for ambient agents.** *(AI: Litt +
LangChain)* If agents become long-running and proactive, they
accumulate the right to interrupt. Cap that right: a daily/weekly
notify budget, with overflow batched into digests. Pairs with B27.
**lean+.**



---

## References

### Practitioners and engineering blogs

- Karpathy, A. (2025). *Software Is Changing (Again)* / "Software 3.0"
  talk, YC AI Startup School. Coverage:
  https://www.latent.space/p/s3 ;
  https://singjupost.com/andrej-karpathy-software-is-changing-again/
- Willison, S. (2025–2026). *Agentic Engineering Patterns* and *How
  Coding Agents Work*. https://simonwillison.net/guides/agentic-
  engineering-patterns/how-coding-agents-work/
- Willison, S. (2025). *The Lethal Trifecta for AI Agents*.
  https://simonw.substack.com/p/the-lethal-trifecta-for-ai-agents
- Willison, S. (2025). *I think "agent" may finally have a widely
  enough agreed upon definition*. https://simonw.substack.com/p/
  i-think-agent-may-finally-have-a
- Anthropic Engineering. *Equipping Agents for the Real World with
  Agent Skills*. https://www.anthropic.com/engineering/equipping-
  agents-for-the-real-world-with-agent-skills
- Anthropic. *Claude Code Best Practices*.
  https://code.claude.com/docs/en/best-practices
- OpenAI. *Introducing Operator*. https://openai.com/index/
  introducing-operator/
- OpenAI. *Computer-Using Agent*. https://openai.com/index/
  computer-using-agent/
- OpenAI Agents SDK. *Human-in-the-loop*. https://openai.github.io/
  openai-agents-python/human_in_the_loop/
- LangChain. *Introducing Ambient Agents*. https://blog.langchain.com/
  introducing-ambient-agents/
- LangChain. *Making it Easier to Build Human-in-the-Loop Agents with
  Interrupt*. https://www.langchain.com/blog/making-it-easier-to-
  build-human-in-the-loop-agents-with-interrupt
- Cursor Docs. *Rules*. https://cursor.com/docs/context/rules
- `awesome-cursorrules`. https://github.com/PatrickJS/
  awesome-cursorrules
- Husain, H. *Your AI Product Needs Evals*. https://hamel.dev/blog/
  posts/evals/
- Husain, H. *LLM Evals: Everything You Need to Know*.
  https://hamel.dev/blog/posts/evals-faq/
- Yan, E. *Patterns for Building LLM-based Systems & Products*.
  https://eugeneyan.com/writing/llm-patterns/
- Yan, E. et al. *What We Learned from a Year of Building with LLMs*.
  https://applied-llms.org/
- Lütke, T. (April 2025). Internal Shopify memo on reflexive AI use,
  widely circulated. Coverage in industry press.
- Litt, G. *Malleable software in the age of LLMs* and ambient agent
  posts (geoffreylitt.com).

### Academic priors

- Vaccaro, M., Almaatouq, A., & Malone, T. (2024). *When Combinations
  of Humans and AI are Useful*. Nature Human Behaviour
  meta-analysis.
- Russell, S. (2019). *Human Compatible: Artificial Intelligence and
  the Problem of Control*. Assistance games / CIRL.
- Mitchell, T. et al. *Never-Ending Language Learning* (NELL) program;
  human-coached lifelong learning.
- *Levels of Autonomy for AI Agents* working paper (2025–2026).
  https://arxiv.org/html/2506.12469v1
- *Fully Autonomous AI Agents Should Not Be Developed* (2025).
  https://arxiv.org/html/2502.02649v3

### Pack source documents

- `/home/user/gc-toolkit/docs/escalation-foundation.md` — v0
- `/home/user/gc-toolkit/docs/escalation-ideation.md` — current
  candidates (sections A and B)
- `/home/user/gc-toolkit/docs/research/r1-toyota-production-system.md`
- `/home/user/gc-toolkit/docs/research/r2-cheap-prototyping.md`
- `/home/user/gc-toolkit/docs/research/r3-cheap-photography-curation.md`
- `/home/user/gc-toolkit/docs/research/r4-recovery-oriented-computing.md`
- `/home/user/gc-toolkit/docs/research/r5-amazon-coe.md`
- `/home/user/gc-toolkit/docs/research/v1-red-team.md`

