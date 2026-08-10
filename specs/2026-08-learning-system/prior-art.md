---
name: prior-art-agent-learning-systems
description: >
  Survey (as of 2026-08) of prior art for a fleet-level "learning system" that
  captures PR/conversation feedback on AI coding agents, audits it, and evolves
  the standing prompts/rules those agents run with — including removing
  guidance that no longer earns its place. Covers rule/memory files in coding
  agents, agentic memory frameworks, self-improving-context research,
  team-process analogues, and products doing PR-feedback-to-instruction loops.
  Ends with transferable design patterns and observed anti-patterns.
---

# Prior Art: Learning Systems for AI Coding-Agent Fleets

**Scope.** What exists, as of mid-2026, for the loop: *feedback on agent output →
audited lesson → updated standing instructions → retired instructions*. For each
item: mechanism (capture / store / apply / retire), evidence model (what stops one
loud comment from becoming gospel), versioning & auditability, and what gc-toolkit
could steal. Prompt bloat is treated as a first-class failure mode throughout;
Chroma's "Context Rot" report gives the empirical backing — across 18 frontier
models, accuracy on retrieval and instruction-following degrades non-uniformly as
input grows, often 30–50% below documented limits — so every rule kept in context
has a measurable cost, not just an aesthetic one.

---

## 1. Rule/memory files in coding agents

### 1.1 Claude Code — CLAUDE.md, auto memory, `.claude/rules/`, Skills

**Mechanism.** Four layers, all plain markdown:

- **CLAUDE.md hierarchy**: managed policy (`/etc/claude-code/CLAUDE.md` etc., cannot
  be excluded) → user (`~/.claude/CLAUDE.md`) → project (`./CLAUDE.md`) →
  `CLAUDE.local.md` (gitignored, personal). Files are *concatenated*, not
  overridden; ancestor files load in full at launch, subdirectory files load lazily
  when Claude reads files there. `@path` imports (max depth 4) expand at launch;
  external imports (paths outside the working dir) require a one-time approval
  dialog — a small but real provenance/consent gate.
- **`.claude/rules/`**: one topic per file; optional `paths:` YAML frontmatter
  glob-scopes a rule so it loads only when Claude touches matching files.
- **Auto memory** (on by default since v2.1.59, Feb 2026): Claude writes its own
  notes to `~/.claude/projects/<project>/memory/`. `MEMORY.md` is an index loaded
  every session but *hard-capped at 200 lines / 25KB* — writes past the limit
  succeed but trigger an error telling Claude to rewrite the index, and overflow
  is silently dropped on next load. Detail is pushed to topic files
  (`debugging.md`, …) read on demand. Docs explicitly instruct: "merge or drop
  stale entries." Files carry a `modified` ISO-8601 frontmatter timestamp stamped
  at write time (v2.1.214+) — machine-readable staleness signal.
- **Skills**: task-scoped procedures loaded only on invocation/relevance — the
  official pressure-release valve for CLAUDE.md bloat.

**Add vs remove.** Docs give explicit *add* triggers ("Claude makes the same
mistake a second time", "a code review catches something Claude should have
known") and *remove* tooling: `/doctor` proposes trims of a checked-in CLAUDE.md,
cutting content Claude can derive from the codebase (directory layouts,
dependency lists) and keeping "pitfalls, rationale, and conventions that differ
from tool defaults." Target under 200 lines; "longer files … reduce adherence."
Also a promotion-out path: "if the instruction must run at a specific point …
write it as a hook instead" — i.e., graduate deterministic rules out of prose
entirely.

**Evidence model.** None built in. No counters, no usage tracking; the human (or
`/doctor`) is the audit. Auto memory's evidence model is just "Claude decides
what's worth remembering."

**Versioning/audit.** Project files via git; auto memory is plain markdown,
browsable via `/memory`, but machine-local with no history beyond the `modified`
timestamp. `InstructionsLoaded` hook can log exactly which instruction files
loaded and why — useful audit primitive.

**Steal:** the hard index-size budget with forced rewrite-on-overflow; the
`modified` timestamp convention; `/doctor`-style trim audits that distinguish
derivable content from genuine pitfalls; the explicit "second occurrence"
threshold for adding a rule; hooks as the graduation target for rules that should
be enforced, not suggested.

### 1.2 Cursor — `.cursor/rules/*.mdc`, generated rules, Memories

**Mechanism.** `.mdc` files with frontmatter (`description`, `globs`,
`alwaysApply`) giving four application modes: Always / Auto-attached (glob match
in context) / Agent-requested (agent decides from `description`) / Manual
(`@`-mention). Nested rules in subdirectories; AGENTS.md also supported with
nearest-file-wins. Team rules (dashboard-enforced, Team/Enterprise) take
precedence over project over user. `/Generate Cursor Rules` (v0.49+) captures
decisions from a chat back-and-forth into a rule file — the closest mainstream
analogue to "conversation feedback → standing rule," but write-only: nothing
audits the generated rule later. Guidance: keep rules under 500 lines, split
into composable files. Legacy `.cursorrules` is deprecated and not loaded in
Agent mode.

**Evidence/retire.** Nothing. Rules are git files; removal is manual. Community
guidance widely notes that ≥10 `alwaysApply` rules eat significant context before
the conversation begins — bloat is recognized but only socially policed.

**Steal:** the four-mode application taxonomy (especially "agent-requested via
description" — rules as retrievable, not resident) and one-command rule capture
from a correction conversation.

### 1.3 Devin — Knowledge

**Mechanism.** Knowledge items = **content + required trigger description**
(semantic cue for recall, not keyword match), optionally pinned to no repo / one
repo / all repos; pinned-to-repo items always load in that repo. Created manually
or **suggested by Devin from chat feedback** — the suggestion is editable and
dismissible before saving, i.e., human approval is in the loop by construction.
Items can be individually enabled/disabled per user *without deletion*, organized
in folders, bulk-toggled; enterprise scope promotes org knowledge upward. Best
practices: one item = one topic, keep items short, make triggers highly relevant.

**Evidence model.** The approval gate at creation, plus disable-without-delete
(reversible retirement). No usage counters documented.

**Steal:** trigger descriptions (recall condition stored *with* the lesson —
scoping by situation, not just by path); suggest-then-approve capture; soft
disable as a retirement stage before deletion.

### 1.4 OpenAI Codex — AGENTS.md

**Mechanism.** Cross-tool standard. Codex walks from repo root to cwd combining
every AGENTS.md; nearest file wins on conflict ("more deeply nested files take
precedence"). Global `~/.codex/AGENTS.md`; `AGENTS.override.md` at each level
takes precedence over the plain file — an explicit local-override channel that
keeps the shared file clean. No capture loop, no evidence model; pure git-file
governance. Claude Code interops via `@AGENTS.md` import or symlink.

**Steal:** the override-file convention — personal/experimental deltas live in a
separate file instead of muddying the audited shared rules.

### 1.5 Aider — CONVENTIONS.md

**Mechanism.** Free-form markdown loaded read-only (`--read CONVENTIONS.md` or
`.aider.conf.yml`), read-only so it's prompt-cache-friendly. A community repo
(Aider-AI/conventions) shares starter files. No scoping, no capture, no
retirement — the minimal baseline all other systems improve on.

### 1.6 GitHub Copilot — instructions files

**Mechanism.** `.github/copilot-instructions.md` repo-wide;
`.github/instructions/*.instructions.md` with `applyTo` frontmatter for
path-specific scope. Both are honored by Copilot code review as well as
completion/chat — one instruction corpus feeding both generation and review.
Org-level instructions exist on Enterprise. Git provides provenance/versioning;
there is no capture loop from review feedback into the files and no
usage-tracking. Add and remove are both fully manual PRs — which at least means
rule changes get human review by default.

**Category-1 summary.** Everyone has *scoping* (path globs, repo pinning,
directory nesting) and *git-grade versioning*. Almost no one has *evidence*
(counters, provenance links to the originating feedback) or *systematic removal*
(Claude Code's `/doctor` and size caps are the only native pruning pressure).
Capture-from-feedback exists (Cursor generate-rules, Devin suggestions) but is
fire-and-forget: nothing later asks whether the captured rule earned its keep.

---

## 2. Agentic memory frameworks

### 2.1 mem0

**Mechanism.** Two-phase pipeline (Chhikara et al., arXiv:2504.19413). *Extract*:
LLM distills candidate facts from new messages plus a running summary. *Update*:
for each candidate, retrieve top-k semantically similar existing memories, then
an LLM tool-call chooses one of four ops — **ADD** (no equivalent exists),
**UPDATE** (augment existing), **DELETE** (contradicted by new info), **NOOP**.
Graph variant adds entity/relation structure.

**Evidence/retire.** The conflict-resolution step *is* the model: every write is
adjudicated against what's already believed, so contradictions trigger DELETE
rather than accumulate. But there's no frequency threshold — a single confident
statement can ADD or DELETE. Designed for user-facts/preferences in
conversational products, not lessons-from-feedback; no per-memory outcome
tracking.

**Steal:** the four-op adjudicated write. Every proposed lesson in gc-toolkit
should be resolved against existing rules as add/merge/supersede/noop rather than
appended.

### 2.2 Letta (MemGPT)

**Mechanism.** Memory blocks = labeled, size-limited persistent strings in
context, edited by the agent via tools (`core_memory_append/replace`); archival
memory is out-of-context cold storage queried by tool call. **Sleep-time
compute** (Letta blog): a *separate* sleep-time agent — not the primary — holds
the memory-editing tools and asynchronously rewrites/consolidates the primary
agent's blocks between interactions.

**Evidence/retire.** Consolidation is delegated to the offline agent's judgment;
size-limited blocks force triage (you cannot bloat a capped block — you must
choose what stays). No counters.

**Steal:** the role split — the agent doing the work never edits the standing
rules directly; a dedicated offline curator does, on its own schedule, against
hard size budgets.

### 2.3 LangMem / LangGraph memory

**Mechanism.** The closest framework to "lessons-from-feedback": explicit
**procedural memory** (behavior rules) alongside semantic/episodic, plus
**prompt optimizers** that turn conversations+feedback into system-prompt
updates via three algorithms — `metaprompt` (reflection proposes updates),
`gradient` (separate critique step, then proposal step), `prompt_memory`
(simple). Background consolidation runs an LLM Memory Manager over batches:
merge similar memories, summarize old ones, delete flagged entries, write back.

**Evidence/retire.** The gradient optimizer's critique/propose split is a
structural hedge against sloppy edits; batch consolidation is the pruning pass.
Still LLM-judgment-based — no quantitative promotion threshold.

**Steal:** treating the standing prompt itself as the memory object with a
proposal pipeline (critique → proposed diff), not just a memory store queried at
runtime.

### 2.4 Zep / Graphiti

**Mechanism.** Temporal knowledge graph; every edge (fact) carries
`valid_at`/`invalid_at` plus bi-temporal event-time vs ingestion-time. When new
information contradicts a fact, the old edge is **invalidated by timestamp, not
deleted** — the graph can answer "what did we believe, and when," and never
serves a stale fact as current.

**Steal:** the retirement semantics. Retired rules in gc-toolkit should get an
`invalidated_at` + reason and drop out of assembly, while remaining queryable —
that's the audit trail that makes aggressive pruning safe, because any removal is
reversible and explainable.

---

## 3. Research on self-improving prompts/contexts

### 3.1 Reflexion (Shinn et al. 2023, arXiv:2303.11366)

Verbal self-reflection after failure (signaled by unit tests / environment
reward — a *concrete* failure signal, not vibes), stored in an episodic buffer
prepended to the next attempt. **Evidence model:** reflections are grounded in
an observed failed trajectory. **Pruning:** the buffer is capped (typically 1–3
reflections) and sliding — lessons decay by default and never outlive the task.
**Lesson for gc-toolkit:** short-horizon, auto-expiring memory is the right tier
for weak/unconfirmed feedback; only what recurs should escape the buffer into
standing rules.

### 3.2 Voyager (Wang et al. 2023, arXiv:2305.16291)

Skill library of *executable code*: a skill is added only after self-verification
confirms the task succeeded; skills are indexed by embedding of their description
and retrieved by similarity to the current situation. **Evidence:** verification
gate at entry — only demonstrated-working artifacts get stored. **Pruning:**
none; the library grows monotonically (tolerable only because retrieval, not
context residence, is the delivery mechanism). **Steal:** verify-before-store,
and retrieval-by-situation so library size doesn't tax every prompt.

### 3.3 DSPy / GEPA (Agrawal et al., arXiv:2507.19457, ICLR 2026 oral)

Genetic-Pareto reflective prompt evolution: sample execution trajectories,
reflect on them in natural language (metrics can return **textual feedback**, not
just scalars — reviewer-comment-shaped signal is a first-class input), mutate
prompts, and select candidates from the **per-instance Pareto frontier** — any
candidate that is best on at least one training instance survives — rather than
keeping a single global best. Every mutation is validated on a minibatch before
acceptance. **Evidence/overfitting:** the Pareto frontier is explicitly the
anti-overfitting device: it prevents collapse onto one lucky prompt and preserves
complementary lessons, which later merge. **Steal:** (a) evaluate any proposed
rule change against a *battery* of past cases, not the single triggering case;
(b) keep candidate rule-sets that win on different slices instead of crowning one
winner per edit.

### 3.4 ACE — Agentic Context Engineering (Stanford/SambaNova 2025, arXiv:2510.04618)

The most direct blueprint. Context = playbook of **itemized bullets**, each with
"(1) metadata, including a unique identifier and counters tracking how often it
was marked helpful or harmful; and (2) content, capturing a small unit such as a
reusable strategy." Three roles: **Generator** (produces trajectories),
**Reflector** ("distills concrete insights from successes and errors"),
**Curator** (emits compact **delta** bullet-sets "merged via non-LLM logic" —
deterministic merge, so the curator LLM can't silently rewrite everything).
Grow-and-refine: new-ID bullets append, existing bullets update in place
(counters increment); a dedup pass compares bullets via semantic embeddings;
refinement runs proactively (each delta) or lazily (when the context window
overflows). Named failure modes it exists to prevent: **brevity bias**
(optimizers compressing prompts into short generic advice, losing domain
specifics) and **context collapse** (iterative monolithic rewrites eroding
knowledge). Works from natural execution feedback without labeled supervision
(+10.6% agents, +8.6% finance).

**Steal:** basically the whole write path — itemized rules with IDs and
helpful/harmful counters incremented from PR outcomes, LLM-proposed deltas,
deterministic merge, embedding dedup, counter-driven pruning.

### 3.5 Dynamic Cheatsheet (Suzgun et al., arXiv:2504.07952, EACL 2026)

Test-time learning: a persistent memory the model itself curates between queries,
storing "concise, transferable snippets rather than entire transcripts" —
explicitly "avoiding context ballooning." Two modes (cumulative vs
retrieval-and-synthesis). No ground-truth labels needed; dramatic gains
(GPT-4o Game-of-24 10%→99% after discovering and reusing one Python strategy).
**Evidence:** what gets retained is what worked when reused — but curation is
self-judged. **Steal:** the insistence that memory entries be *transferable
distillations*, never transcript quotes; a stored lesson should read like a rule,
not like the argument that produced it.

### 3.6 AWM — Agent Workflow Memory (Wang et al., arXiv:2409.07429, ICML 2025)

Induces reusable **workflows** (common sub-routines) from *successful* past
trajectories, offline or online, and selectively injects them into future tasks.
+24.6%/+51.1% relative on Mind2Web/WebArena, fewer steps per task.
**Evidence:** induction only from successes; recurrence across trajectories is
the promotion signal. **Steal:** mine *recurrence across many PRs/sessions* as
the promotion criterion — one success (or one complaint) induces nothing.

---

## 4. Team-process analogues

### 4.1 Mining recurring PR review feedback / lint-rule promotion

Industry practice (Graphite, Propel, codetinkerer): when the same nit recurs,
**stop writing the comment and automate it** — formatter, lint rule, template, or
checklist; "if a rule can be expressed programmatically, let a tool enforce it."
The implicit promotion ladder: ad-hoc comment → team checklist/docs → lint rule →
CI gate. Each promotion step *removes* the need for prose guidance — the
guidance graduates out of the prompt/review entirely. Google's "Resolving Code
Review Comments with ML" (ICSE 2024) established the raw material exists at
scale: millions of reviewer comments/year, ~60 min author shepherding per change,
and comments are predictable enough that an ML model can propose the resolving
edit. Meta's **Getafix** (arXiv:1902.06111) closed a version of the loop
pre-LLM: hierarchical clustering over past human fixes (including fixes made in
response to code review) mines fix patterns ranked by context — recurring human
corrections literally become automated fixers.

**Steal:** the ladder itself, with "expressible as a lint/hook?" as a standing
audit question — the best outcome for a captured lesson is often to *leave* the
prompt and become deterministic tooling; and clustering (Getafix-style) as the
recurrence detector over captured feedback.

### 4.2 Amazon COE / "mechanisms, not good intentions"

COE: a significant error triggers a written document; Five-Whys drills to root
cause; output is **tracked corrective action items** that change the underlying
condition, "because people already had good intentions when the problems cropped
up." The Bezos framing: a mechanism is a *complete loop* — tool + adoption +
inspection + iteration. Applied to agent fleets: "we told the agent to stop
doing X" is a good intention; a mechanism is a rule with an owner, a metric
(does X recur?), an inspection cadence, and a sunset condition. AWS explicitly
distinguishes COE from postmortems: "the focus is on corrective actions, not just
documenting failures."

---

## 5. Products doing PR-feedback → updated agent instructions

### 5.1 CodeRabbit Learnings (deepest implementation found)

- **Capture trigger:** reply to a CodeRabbit review comment (agree/disagree/
  explain); CodeRabbit itself judges whether the feedback is a systemic
  preference worth storing, and acknowledges with a collapsible "Learnings Added"
  section on the PR — capture is *visible at the point of feedback*. Bulk import:
  `@coderabbitai add a learning using docs/coding-standards.md`.
- **Storage:** internal DB keyed to the Git org; natural-language statements.
  Credential redaction at write time only (no backfill of old learnings).
- **Scoping:** `auto` (public repo → repo-only learnings; private repo → all org
  learnings), `global`, `local`. Path instructions (config) take precedence over
  learnings.
- **Application:** every time it prepares a comment, it loads in-scope learnings
  as additional context.
- **Editing/expiry:** dashboard (`app.coderabbit.ai/learnings`) tables each
  learning with **usage count, last-used, created, updated**; admins edit/delete;
  anyone can request changes via `@coderabbitai` comments. **No automatic expiry
  or decay** — docs recommend manual quarterly review, flagging "Never Used"
  (zero-usage) learnings and deleting contradictory entries.
- **Approval workflow:** `knowledge_base.learnings.approval_delay` (0–30 days)
  turns new chat-sourced learnings into pending requests, auto-approved after the
  delay unless an admin disapproves — a *default-allow quarantine window*.
- **Evidence model:** thin. One reviewer reply can mint an org-wide learning
  (mitigated only by scoping config and the approval delay). Their own docs warn:
  don't store one-time exceptions; explain the why.

**Steal:** usage-count + last-used telemetry per rule; approval-delay quarantine;
in-PR visible acknowledgment of capture; the documented failure mode (no decay →
mandatory manual quarterly gardening) as a cautionary spec.

### 5.2 Ellipsis

Learns which comment types a team values from **thumbs up/down reactions**, applied
at review time via **embedding search over similar past comments** (k-NN over
reaction history rather than distilled rules) — an *implicit*, per-instance
evidence model: one downvote only suppresses near-identical future comments, and
more votes = stronger signal, which elegantly sidesteps the one-loud-comment
problem but produces nothing auditable or editable as a rule. Replies with
explanations feed the LLM context; uploaded style-guide docs act as explicit
rules; review agents themselves are **YAML config files in the repo** (trigger +
model + prompt) where the default-branch version is the live agent — instruction
changes ride the normal PR review/merge pipeline with zero extra machinery.

**Steal:** agents-as-config-in-repo (rule changes get code review for free), and
k-NN-over-feedback as the *pre-promotion* tier: raw feedback influences behavior
immediately and locally, and only clusters of similar feedback get distilled into
explicit standing rules.

### 5.3 Sweep

`sweep.yaml` holds a rules list checked against new commits; violations trigger
auto-fix PRs. PR-comment feedback only iterates the current PR — no persistence
into rules. Notable mainly as "rules in repo + rules actively enforced by the
agent" rather than a learning loop.

---

## 6. Synthesis

### Transferable design patterns

1. **Evidence ledger per rule (helpful/harmful counters + usage telemetry).**
   Every standing rule carries an ID, counters incremented from real outcomes
   (rule cited in an accepted comment → helpful; rule implicated in reverted/
   rejected guidance → harmful), plus usage-count/last-used à la CodeRabbit's
   dashboard. Zero-use and net-harmful rules are pruning candidates by query, not
   by archaeology. (ACE arXiv:2510.04618; CodeRabbit learnings docs.)
2. **Adjudicated writes, never appends.** Each candidate lesson is resolved
   against semantically similar existing rules as ADD / UPDATE / SUPERSEDE / NOOP
   (mem0's four-op update), and applied as an itemized **delta** merged
   deterministically (ACE's non-LLM Curator merge + embedding dedup). This is the
   structural defense against both duplication ("you copy-pasted an inapplicable
   comment") and contradiction accumulation. (mem0 arXiv:2504.19413; ACE.)
3. **Recurrence threshold + quarantine before promotion.** One comment never
   becomes gospel: raw feedback lands in a short-lived, task-scoped tier
   (Reflexion's capped buffer; Ellipsis's k-NN over reactions) and is promoted to
   a standing rule only on recurrence across independent PRs/authors (AWM induces
   only from repeated successful trajectories; Claude Code docs' "makes the same
   mistake a *second* time"), then sits in a CodeRabbit-style approval-delay
   window where a human can veto. (arXiv:2303.11366; arXiv:2409.07429; CodeRabbit
   `approval_delay`.)
4. **Scope every rule to the narrowest context that reproduces the feedback.**
   Path globs (Cursor `globs`, Copilot `applyTo`, Claude `.claude/rules` `paths:`),
   repo pinning + semantic trigger descriptions (Devin), nearest-wins nesting
   (AGENTS.md). Narrow scope shrinks both the context tax and the blast radius of
   a wrong rule — and retrieval-by-situation (Devin triggers, Voyager embeddings,
   Skills) keeps the library's size from taxing every prompt.
5. **Invalidate, don't delete.** Retirement writes `invalidated_at` + reason +
   superseded-by (Zep/Graphiti bi-temporal edges); retired rules leave assembly
   but stay queryable. Combined with rules-as-files-in-git (Ellipsis agents,
   Copilot instructions), every add/change/removal has diff, author, review, and
   rollback. Cheap reversibility is what makes aggressive pruning politically
   possible. (Zep arXiv:2501.13956/getzep.com; Ellipsis docs.)
6. **Promotion ladder with an exit from prose.** comment → ephemeral lesson →
   scoped rule → **lint rule / hook / CI gate**, with a standing audit question
   "is this expressible deterministically?" The best rules eventually *leave the
   prompt* (Claude Code: "write it as a hook instead"; industry lint-promotion
   practice; Getafix mining fixers from recurring human fixes). Prompt space is
   for judgment calls only.
7. **Separate the worker from the curator, and budget the context hard.** Rule
   editing is an offline role (Letta sleep-time agent; ACE Reflector/Curator)
   validated against a battery of past cases on a Pareto basis rather than the
   single triggering case (GEPA arXiv:2507.19457), writing into hard size budgets
   with forced rewrite-on-overflow (Claude Code's 200-line/25KB MEMORY.md cap).
   A budget converts "should we prune?" into "what must go?"
8. **Make capture and audit visible.** Acknowledge capture at the point of
   feedback (CodeRabbit's "Learnings Added" collapsible on the PR); log which
   rules loaded per session (Claude Code `InstructionsLoaded` hook); store
   provenance links (originating PR/comment URL) on every rule so audits can
   re-check the rule against its source incidents — the COE discipline of tracked
   corrective actions with owners and inspection, not good intentions.

### Anti-patterns observed

1. **Monolithic rewrite consolidation.** Letting an LLM re-summarize the whole
   rule file each cycle erodes detail ("context collapse") and drifts toward
   short generic advice ("brevity bias") — ACE named and measured both. Deltas
   with deterministic merge, never full regeneration.
2. **Append-only memory with no decay pressure.** Voyager's monotonic library,
   CodeRabbit's no-expiry learnings (manual quarterly cleanup as the documented
   fix), and typical CLAUDE.md/Cursor-rules sprawl. Given Context Rot, every
   stale rule actively degrades the agent even when individually harmless.
3. **One loud comment becomes org-wide gospel.** CodeRabbit can mint an
   org-scoped learning from a single reply; Cursor's generated rules are
   fire-and-forget. Any capture path lacking recurrence thresholds, scoping
   defaults, and a veto window institutionalizes individual reviewers' pet
   peeves — the agent-fleet version of the "infinite loop of PR nits."
4. **Capture without provenance or outcome tracking.** Nearly every rule-file
   ecosystem stores the rule but not *why* (originating incident) or *whether it
   works* (usage/outcome). Such rules can never be safely deleted — nobody knows
   what they're load-bearing for — so they never are.
5. **Storing transcripts instead of distillations.** Memory entries that quote
   the argument rather than state the transferable rule (the failure Dynamic
   Cheatsheet's "concise, transferable snippets" design explicitly avoids) bloat
   context and generalize poorly — the root of "comments too verbose / restate
   the code" reappearing inside the learning system itself.

---

## Provenance / citations

Accessed 2026-08-10 via web search and direct fetch.

**Coding-agent rule/memory systems**
- Claude Code memory docs (CLAUDE.md hierarchy, `.claude/rules/`, auto memory caps, `/doctor` trims, `modified` timestamps): https://code.claude.com/docs/en/memory
- Cursor rules docs (.mdc frontmatter, four modes, team rules, /create-rule): https://cursor.com/docs/rules
- Devin Knowledge docs (trigger descriptions, pinning, suggested knowledge, enable/disable): https://docs.devin.ai/product-guides/knowledge
- AGENTS.md spec/guide: https://www.morphllm.com/agents-md-guide ; Codex nesting/precedence and AGENTS.override.md: https://codex.danielvaughan.com/2026/03/26/agents-md-advanced-patterns/ , https://github.com/openai/codex/issues/12115
- Aider conventions: https://aider.chat/docs/usage/conventions.html ; community files: https://github.com/Aider-AI/conventions
- GitHub Copilot instructions (repo-wide, `applyTo` path-specific, code review support): https://docs.github.com/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot , https://docs.github.com/en/copilot/reference/custom-instructions-support

**Memory frameworks**
- mem0 paper (ADD/UPDATE/DELETE/NOOP): arXiv:2504.19413 — https://arxiv.org/abs/2504.19413
- Letta memory blocks: https://www.letta.com/blog/memory-blocks/ ; sleep-time compute: https://www.letta.com/blog/sleep-time-compute/
- LangMem SDK (procedural memory, prompt optimizers metaprompt/gradient/prompt_memory, background consolidation): https://www.langchain.com/blog/langmem-sdk-launch
- Zep temporal knowledge graph / Graphiti (bi-temporal valid_at/invalid_at): https://www.getzep.com/ai-agents/temporal-knowledge-graph/ ; paper: https://arxiv.org/abs/2501.13956

**Self-improving context research**
- Reflexion: arXiv:2303.11366 — https://arxiv.org/abs/2303.11366
- Voyager: arXiv:2305.16291 — https://arxiv.org/abs/2305.16291
- GEPA (ICLR 2026 oral): arXiv:2507.19457 — https://arxiv.org/abs/2507.19457 ; DSPy integration: https://dspy.ai/api/optimizers/GEPA/overview/ ; https://github.com/gepa-ai/gepa
- ACE (Agentic Context Engineering): arXiv:2510.04618 — https://arxiv.org/abs/2510.04618 (mechanism details from https://arxiv.org/html/2510.04618v1 ); press: https://venturebeat.com/ai/ace-prevents-context-collapse-with-evolving-playbooks-for-self-improving-ai
- Dynamic Cheatsheet (EACL 2026): arXiv:2504.07952 — https://arxiv.org/abs/2504.07952 ; https://github.com/suzgunmirac/dynamic-cheatsheet
- Agent Workflow Memory (ICML 2025): arXiv:2409.07429 — https://arxiv.org/abs/2409.07429
- Context Rot (Chroma, long-context degradation): https://research.trychroma.com/context-rot

**Team-process analogues**
- Graphite on nits: https://graphite.com/blog/what-are-nits ; Propel on promoting recurring nits to guardrails: https://www.propelcode.ai/blog/code-review-nitpicks-vs-must-fix-issues ; https://www.codetinkerer.com/2024/01/12/nitpick-code-reviews.html
- Google, "Resolving Code Review Comments with ML" (ICSE 2024): https://research.google/pubs/resolving-code-review-comments-with-machine-learning/ ; blog: https://ai.googleblog.com/2023/05/resolving-code-review-comments-with-ml.html
- Meta Getafix: https://engineering.fb.com/2018/11/06/developer-tools/getafix-how-facebook-tools-learn-to-fix-bugs-automatically/ ; arXiv:1902.06111
- AWS on Correction of Error: https://aws.amazon.com/blogs/mt/why-you-should-develop-a-correction-of-error-coe ; Bezos mechanisms framing: https://www.cnbc.com/2022/10/06/how-this-popular-jeff-bezos-quote-drives-amazons-climate-goals.html

**PR-feedback-loop products**
- CodeRabbit Learnings (capture, scoping auto/global/local, approval_delay, usage counts, redaction): https://docs.coderabbit.ai/knowledge-base/learnings
- Ellipsis (thumbs up/down + embedding search over past comments; agents as YAML in repo): https://www.nsbradford.com/blog/how-we-built-ellipsis ; https://docs.ellipsis.dev/features/code-review
- Sweep (sweep.yaml rules, auto-fix PRs on rule violations): https://docs.sweep.dev/custom-prompts ; https://github.com/sweepai/sweep/blob/main/sweep.yaml
