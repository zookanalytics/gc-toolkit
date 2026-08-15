---
name: Learning-Mechanism Inventory — gc-toolkit
description: Complete survey of every existing or aspirational mechanism in gc-toolkit for capturing lessons from agent work and folding them back into prompts, formulas, docs, and checks. Structured as prompt-assembly surface, learning loops by maturity, raw-signal sources, gaps in the closed loop, and reusable rails. Filed as input for building a feedback-learning system.
---

# Learning-Mechanism Inventory — gc-toolkit

Survey date: 2026-08-10. Repo HEAD: `1c5a057`. Every claim below is grounded in a file path; where a doc *describes* something that does not exist as an artifact, that is stated explicitly.

## 0. The doctrinal frame (what the pack says about learning)

`docs/foundation.md` carries the belief:

> **Agents improve.** Lessons come from doing; the system carries them across restarts so the next conversation starts smarter.

and in its opening paragraph: *"every lesson compounds into the pack so attention is never spent twice."* Goal **G1** is "fewer escalations over time, each one higher-value." The Boundaries section contains the anti-pattern this whole area exists to defeat: *"gc-toolkit will not treat cheap restart as root cause… The right answer is to make the failure legible and improve the pack."*

`docs/architecture.md` is explicit that this belief gets **no primitive of its own**:

> Not every belief maps to one primitive. *Agents improve* is carried across the whole system — by reusable molecules and skills, and by the doc-and-knowledge layer that folds each lesson back into the pack — rather than by a primitive of its own.

Two of the five "standing compositions" carry it:

- **Engine health** — "composes molecules (resident patrol loops) and checks (an anti-regression suite that locks each hard-won fix into the pack). It serves *Agents improve* — a lesson learned once becomes a standing guard." That anti-regression suite is `doctor/`.
- **Doc & knowledge cohesion** — "a drift audit that catches a claim made false by movement, a memory audit that catches a learning missing from a brief — routed as ordinary work through Delivery. It serves *Decisions have a home*."

**Consequence for a new learning system:** `docs/architecture.md`'s closing **consistency test** requires a proposed capability to trace a straight line from a foundation belief, through one of the named primitives (bead / molecule / check / skill / role / routing), composed the way an existing standing system composes them. A learning system that invents its own primitive fails that test by construction. The two compliant shapes already demonstrated are (a) *molecule + routing* (the audits) and (b) *check* (doctor). Also relevant: *"The pack is self-hosting"* — pack changes are filed as beads and routed to the worker pool, so a learning system's output rides the same pipeline as everything else.

---

## 1. The prompt-assembly surface — what a learning would ultimately edit

This is the target surface. A learning that must change future agent behavior lands in exactly one of these places.

### 1.1 Fragment injection via `pack.toml` (the primary surface)

`pack.toml` patches the imported gastown roster with pure fragment-append overlays — **no whole-file prompt mirrors**:

| Agent | `pack.toml` block | Fragments appended |
|---|---|---|
| boot | `[[patches.agent]] name="boot"` | `layered-startup-discovery-boot` |
| deacon | ditto | `canonical-self-rename`, `heartbeat-no-consent-ui`, `layered-startup-discovery-deacon` + `overlay_dir="overlays/cycle-recycle"` |
| mayor | ditto | `canonical-self-rename`, `convoy-integration-branch-mayor`, `operator-next-step-trailing` |
| polecat | ditto | `polecat-convoys`, `polecat-non-impl-done`, `file-work-records` |
| refinery | ditto | `layered-startup-discovery-refinery` + `overlay_dir` |
| witness | ditto | `heartbeat-no-consent-ui`, `layered-startup-discovery-witness` + `overlay_dir` |

### 1.2 The fragment library

`template-fragments/*.template.md` — 12 files, 15 Go-template `{{ define "<name>" }}` blocks:

| File | Define(s) |
|---|---|
| `canonical-self-rename.template.md` | `canonical-self-rename` |
| `convoy-integration-branch.template.md` | `convoy-integration-branch-mayor` |
| `cycle-recycle.template.md` | `cycle-recycle` |
| `file-work-records.template.md` | `file-work-records` |
| `heartbeat-no-consent-ui.template.md` | `heartbeat-no-consent-ui` |
| `layered-startup-discovery.template.md` | `…-boot`, `…-deacon`, `…-refinery`, `…-witness` (4 in one file) |
| `operator-next-step-trailing.template.md` | `operator-next-step-trailing` |
| `polecat-convoys.template.md` | `polecat-convoys` |
| `polecat-non-impl-done.template.md` | `polecat-non-impl-done` |
| `thread-role.template.md` | `thread-role` (parameterized by `{{ .RoleName }}`) |
| `upstream-engagement.template.md` | `upstream-engagement` |
| `watch-dispatched-work.template.md` | `watch-dispatched-work` |

Sub-pack fragments in `packs/gascity-keeper/template-fragments/`: `polecat-patterns`, `rebase-conventions`, `refinery-rebase-handling`. These are **not** wired by any file in this repo — they are wired by `[[rigs.patches]]` blocks the importing city copies from `packs/gascity-keeper/pack.toml` into its own `city.toml` (see `docs/install.md` §3 and `agents/mechanik/prompt.template.md`, "Operational doctrine has two homes"). A learning system running inside this repo **cannot** reach that wiring; it can only edit the fragment bodies.

### 1.3 Native agent prompts and per-agent wiring

- `agents/mechanik/prompt.template.md` (~200 lines, composes `convoy-integration-branch-mayor`, `watch-dispatched-work`, `upstream-engagement`, `canonical-self-rename`, `operator-next-step-trailing`)
- `agents/converse/prompt.template.md` (80 lines — the visit loop)
- `agents/proactive/prompt.template.md` (134 lines)
- `agents/_polecat-gemini/prompt.template.md` (inert — `_` prefix skips agent discovery)
- `packs/gascity-keeper/agents/keeper/prompt.template.md`

Per-agent knobs in `agents/<name>/agent.toml`:
- `prompt_template` — including the cross-pack `<pack>//<subpath>` form: `agents/polecat-codex/agent.toml` renders `gastown//agents/polecat/prompt.template.md`; `agents/mayor-thread/agent.toml` the same for mayor; `agents/mechanik-thread/agent.toml` points at `agents/mechanik/prompt.template.md`.
- `inject_fragments` (polecat-codex) and `append_fragments` (mayor-thread, mechanik-thread).
- `[env] RoleName` — drives `{{ .RoleName }}` in `thread-role`.

**Known hand-sync hazard, recorded in the file itself** (`agents/polecat-codex/agent.toml`): *"inject_fragments must be kept in sync by hand with the polecat patch's inject_fragments_append in pack.toml — there is no automatic propagation."* Any learning system editing polecat doctrine must touch both places.

### 1.4 Non-prompt behavioral surfaces

- **Overlays** — `overlays/cycle-recycle/.claude/settings.json` (a Claude `Stop` hook) + `.claude/hooks/cycle-recycle.sh`, staged into the agent's work dir via `overlay_dir`. This is behavior the harness enforces *regardless of LLM state*, and it exists precisely because prose doctrine degraded (see §2.3).
- **Formulas** — `formulas/*.toml` step `description` fields are prompt text poured into a session. Editing a formula step *is* editing a prompt.
- **Skills** — `skills/<name>/SKILL.md` (6: `demo-capture`, `filing-documentation`, `gc-demo-script`, `handoff`, `session-title`, `signoff-review`), invoked on demand.
- **Dispatch-carried method** — `assets/scripts/review-dispatch-body.sh` inlines `skills/signoff-review/SKILL.md` verbatim into the review bead's description, so the method is a property of the *bead* not the agent's skill catalog.

### 1.5 What guards this surface today

- `doctor/check-agent-prompt-integrity/` — every agent whose `prompt_template` is set must name a *readable* file in the **resolved** config, because `gc prime` silently renders a 16-line generic stub (exit 0, empty stderr) when a template can't be read. Has `run.test.sh`.
- `doctor/check-base-artifact-collision/` — gc-toolkit artifacts must not silently shadow gastown base. **A `{{ define "name" }}` whose name also exists in base is a hard ERROR** (the template engine resolves by name, not by file). Allowlisted mirrors WARN when base advances, compared against frozen snapshots under `doctor/check-base-artifact-collision/base-snapshots/`. **[RETIRED 2026-08-15, after this survey — tk-3w7p7.** It could not locate the base pack under the import-cache model and had been reporting `skipped` on every run since ~2026-06. Both arms above are gone with it and nothing replaced them; the mirror inventory it documented now lives in `docs/gascity-packs.md` §7a.**]**
- `doctor/check-startup-discovery/` — asserts specific *content* inside the `layered-startup-discovery-*` fragments (ephemeral-aware, title-scoped wisp queries; boot carries the read at both sites). Has `run.test.sh`.
- `doctor/check-cycle-recycle-hook/` — the overlay is shipped *and* wired onto witness/deacon/refinery.

---

## 2. Existing learning loops, by maturity

### BUILT

#### 2.1 Lesson → doctor check (the anti-regression suite)

**This is the pack's most mature learning mechanism.** 12 checks under `doctor/check-*/`. Structure per check:

```
doctor/<check-name>/
├── doctor.toml     # exactly one key: description (verified across all 12)
├── run.sh          # exit 0=OK, 1=Warning, 2=Error; stdout line 1 = message, rest = details
└── run.test.sh     # optional; present on 3 of 12
```

`run.sh` reads the pack root from `${GC_PACK_DIR:-.}`, greps/parses pack artifacts, and accumulates an `errors=()` array.

The pattern by which a lesson becomes a check is visible in the artifacts themselves:

1. An incident happens and is fixed under a bead. Git log shows the fix-commit convention: `fix(quiesce): is_terminal_anchor misses a refinery-HELD anchor … (tk-rlm94) (#272)`.
2. The `doctor.toml` `description` is written as a **one-sentence statement of the invariant plus the bead id that paid for it**. Examples:
   - `check-cycle-recycle-hook`: "…so the 200K context recycle can't be silently un-shipped (**tk-g8pfg**; supersedes the pour-before-handoff check)"
   - `check-merge-gate-drop`: "A declared merge gate is never silently dropped… (**tk-4na1b**)"
   - `check-keeper-resume-handoff-token`: "…resume-vs-duplicate guard, **gc-lwc5p**"
   - `check-rig-scoped-orders-bound`: "…(**tk-gi2pc**). Backstop for the discovery-path guard; permanently green once that lands"
   - `check-pr-prep-single-commit-unchanged`: "…keeps the single-commit (N=1) path after batch support… (**tk-ur4o2**)"
3. `run.sh`'s header comment carries the **narrative**: what actually produced the bug, and — in the best examples — what the check *used to* wrongly encode. `doctor/check-agent-prompt-integrity/run.sh` has a whole section titled "WHAT DOES NOT PRODUCE IT — the premise this check used to encode (tk-5wdy8)", documenting that the check was rewritten after research (`specs/tk-5wdy8/findings.md`) proved the original theory wrong. `doctor/check-base-artifact-collision/run.sh` names the audit (`tk-kdu2v5`, 2026-05-27) that found three classes of silent mirror, and includes a "Reconciliation workflow when this check WARNs" (that check was retired 2026-08-15, tk-3w7p7; its narrative and reconciliation workflow moved to `docs/gascity-packs.md` §7a).
4. The check lands in the same PR as the fix. `git log --diff-filter=A` per check dir confirms: `check-agent-prompt-integrity` ← `b44af79` (tk-5wdy8), `check-startup-discovery` ← `d4d3828` (tk-jd4b8), `check-rig-scoped-orders-bound` ← `87af788` (tk-gi2pc), `check-liveness-sweep-wired` ← `ce471c1`. The remaining 8 arrived in a bulk import commit.

**Read-side:** `formulas/mol-deacon-patrol.toml` step 4 ("System diagnostics") runs `timeout 300 gc doctor --json`, filters `.results[] | select(.status != "ok")`, and mails findings to the mayor. Note the fragility: commit `0c52288` fixed *"doctor findings filter uses `.checks[]` but schema is `.results[]` — all doctor escalation silently empty"*. The formula now defends with a schema-drift guard that mails HIGH if `.results` is absent.

`specs/2026-08-fresh-start/gas-city-native.md:82` names this the pack's memory outright: *"**Banked lessons** — the doctor checks and trap docs. These survive any composition; they are the pack's memory."*

#### 2.2 Lesson → prompt fragment

`pack.toml`'s own comments are the audit trail. Two worked examples:

- boot's `layered-startup-discovery-boot`: *"Base boot reads the deacon's patrol wisp with `gc bd list … --json` and no `--include-infra`, at two sites… Wisps are ephemeral, so both return empty on every wake and the triage rows keyed on wisp staleness can never fire (**lx-ody8m**). This fragment supersedes both sites."*
- witness's `layered-startup-discovery-witness`: *"…every restart pours a fresh wisp while leaking the prior one (**tk-1waw2**)."*

`template-fragments/polecat-non-impl-done.template.md` is the same shape written as prompt prose: it opens by naming the failure it repairs ("refinery sees a branch with no commits ahead of the target, rejects the merge, and the bead loiters open until a human closes it") and includes a four-signal detector with a "durable structural fallback" — and notes *"one of the recurrences this override exists to fix was a review bead whose review never reached GitHub."*

#### 2.3 Lesson → deterministic hook (prose that failed, escalated to machinery)

`overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh` header states the lesson precisely:

> Because the harness runs the hook regardless of LLM state, the recycle is genuinely enforced — unlike the soft "Apply cycle-recycle" prose that used to live in the patrol formulas, which degraded exactly as context filled (the bug this fixes, **tk-g8pfg**: the fuller the context, the less reliably the model ran the end-of-wisp check, so context climbed and the check was skipped harder).

Guarded by `doctor/check-cycle-recycle-hook/`. This is the pack's canonical demonstration of *poka-yoke over prompt* — a principle `specs/tk-px5od/ideation.md` B7 names ("poka-yoke first, prompt last") but never landed as doctrine.

#### 2.4 Lesson → dispatch-carried method

`assets/scripts/review-dispatch-body.sh` is the most explicit incident-to-mechanism artifact in the repo. Its header:

> **THE BUG.** The review dispatch named no method… A polecat handed that bead looks for a method and finds one by description match, and the catalog entry that advertised "Use when reviewing code changes before creating a PR" won every time — a 6-persona fan-out that measured, over 2026-07-31..08-02, **518 codex sessions / 794M tokens, 4.9 subagents and ~4.7M tokens per review, for 12 merged PRs**. Rescoping that one skill (city commit `a68a29b0`) stopped THAT skill being selected; it did not give reviews a method, so the next review-shaped entry in a polecat's catalog reintroduces the drift.
>
> **THE FIX.** Carry the method IN THE DISPATCH… gc has no per-agent skill allowlist to fall back on (`skills = [...]` is a tombstone, a parse error in v0.16), so the dispatch naming the method IS the control surface.

Beads: `tk-jufvl` (emitter), `tk-wghh1` (the `signoff-review` skill it inlines). The skill itself contains a hard-won rule stated as *"This prohibition is the point of the skill, not a performance note."* There is also a **fail-soft** contract: if the skill file can't be read, a degraded inline method plus a stderr WARN — never a bare title.

#### 2.5 doc-keeper drift audit (docs kept *true*)

- `formulas/mol-doc-keeper-drift-audit.toml` — globs `docs/gascity-*.md`, reads each `## Scope`, judges claims against current upstream, files change-unit `doc-update` beads citing triggering commits. Stateless (no SHA baseline), read-only, capped by `audit_max_beads_per_run` (default **5**).
- `orders/doc-keeper-drift-audit.toml` — `trigger="cooldown"`, `interval="24h"`, `pool="gc-toolkit.polecat"` (bare), `scope="rig"`.
- Design: `specs/tk-yw3zb.1/doc-keeper-architecture.md` §5a.
- **This loop demonstrably runs.** Git log contains its output: `ea95101 doc-update: gascity-agents.md — Variant A lifecycle omits… (tk-m2v7d) (#268)`, `25d5ca5 doc-update: gascity-agents.md — the 4-tier startup-discovery "reference implementation" pointer names… (tk-p4j5t) (#267)`, `3e54700 doc-update: gascity-reference.md — drop the false "(incl. repository map)" annotation (tk-agn6v) (#258)`, plus `5ad18d2`, `8bbc818`. That is a functioning closed loop from "the world moved" to "a merged PR."

#### 2.6 Record discipline (decisions get a home)

- `agents/converse/prompt.template.md` step 5: `gc bd update $SUBJECT --append-notes "<decision, rationale, what changed>"`, and refresh a `## Current state` block ("current position, decisions in force, open questions") when notes grow. Step 6: stamp `gc.outcome=<one-word>`, **verify the stamp reads back**, then close — *"an unstamped closed visit is invisible to everything that reads outcomes."*
- `template-fragments/file-work-records.template.md` (injected into polecat): durable documents are committed repo artifacts, never bead comments.
- `skills/filing-documentation/SKILL.md` + `docs/file-structure.md`: the two-tier rule — `docs/<topic>.md` is *what's true now*; `specs/<bead-id>/` is *what was thought*. Plus the `## Scope` standard (mandate + boundaries, category-not-members), which is what makes gap-vs-drift distinguishable at all.

#### 2.7 Within-PR review → rework loop

`formulas/mol-refinery-patrol.toml` + `skills/signoff-review/SKILL.md`. Findings are graded P0/P1/P2 with `file:line`; verdict is `COMMENT` (pass) or `REQUEST_CHANGES`; a rework child is filed and re-gated; the round cap escalates rather than spinning (`99d79ba fix(signoff): cap rework rounds — escalate instead of spawning round N+1 (tk-uqfk1)`; `GC_MAX_REVIEW_ROUNDS` default 3, then `blocked_reason="signoff did not converge after $ROUNDS rework rounds… findings are in the review beads under this anchor"`). **This corrects one PR. Nothing reads across PRs.**

### PARTIAL

#### 2.8 doc-keeper memory audit (docs kept *complete*)

Artifacts exist and are wired: `formulas/mol-doc-keeper-memory-audit.toml` + `orders/doc-keeper-memory-audit.toml` (24h cooldown, bare pool, rig scope). Three steps: `load-context` → `scan-and-classify` → `file-and-dispatch`. Cap `max_beads_per_run` default **3**.

Why it is *partial* rather than built, on the formula's own terms:

1. **The source is an absolute path on one machine.** `[vars.memory_dir]` defaults to an absolute path under the operator's home directory. A missing dir is a deliberate clean no-op (`echo "memory dir $MEM not present — nothing to audit this run."` → close step → drain).
2. **Two gates, and the base rate is designed to be zero.** Gate 1 (nature) admits only *structural* truths — durable contracts, by-design sharp edges — and rejects all *operational* state: live defects, workarounds, calibrations, incident lore. Gate 2 (scope) requires a brief's mandate to *cleanly own* it ("topical adjacency is not mandate ownership"). The formula says so directly: *"because mechanik auto-memory is overwhelmingly operational, the expected outcome of a run is that nothing promotes… A run filing several beads is a smell that the nature gate is being skipped."*
3. **The escape hatch is a log line, not a bead.** A structural learning with no clean owner is surfaced as a "one-line **missing-brief observation**" in run output — *"a surfaced signal only, never a new bead and never brief-creation work."*
4. Unlike the drift audit, **no memory-audit output appears in git history.**

The formula also carries two well-written negative examples that are worth reading before designing anything adjacent: the promoting case ("Gas City discriminates beads with `task_kind`, not custom per-kind schemas") and the *contra* case (the mirror-vs-overlay basename-collision learning — structural, but no brief cleanly owns it, so it stays local).

#### 2.9 `mol-first-reaction` (cheap prep, not learning)

`formulas/mol-first-reaction.toml` + `agents/proactive/`. Reads the bead's universe slice, writes a fixed-shape CARD to notes (`Understanding · Found (freshness-stamped) · Proposal · Decision needed`), files a visit, stamps a `takeaway`, releases the bead, drains. Never closes the work bead; mr-only if it produces code. **This is a reaction loop, not a feedback loop** — nothing reads the cards back. The pool ships **default-disabled** (`GC_PROACTIVE_ENABLED` gate in both `work_query` and `scale_check`).

#### 2.10 `mol-triage-recurrence` (recurrence of *conversations*, not defects)

`formulas/mol-triage-recurrence.toml` + `orders/triage-recurrence.toml` (24h). For each `task_kind=triage-subject` bead it evaluates a machine-readable `triage.scope` (tokens `p<=N`, `label:X`, `kind:X`, `unrouted`) against open beads and files at most one live visit. Guarded by `doctor/check-liveness-sweep-wired`. Spec: `specs/2026-08-fresh-start/liveness-and-triage-spec.md` §3; principle P3 in `operating-principles.md`.

Despite the name, **this has nothing to do with recurring defects.** It is a scheduled prioritization sitting. It is however the closest existing template for "a cron formula that decides whether a human conversation is warranted, and never stacks two."

### ASPIRATIONAL

#### 2.11 The `specs/tk-px5od/` ideation epic

An "escalation pack" ideation with ~150 candidates, 5 domain research reports (R1 Toyota Production System, R2 cheap prototyping, R3 cheap-photography curation, R4 recovery-oriented computing, R5 Amazon COE) and 7 validation reports (V1 red-team, V2 AI-native prior art, V3 skeptic, V4 AI-native inventions, V5/V6 inversions, V7 hidden metrics).

**What it decided about learning-from-failure** (`ideation.md`, `selection-menu.md` Cluster 3, `marching-orders.md`):

- **M5 — "Coaching terminates in a merged artifact."** *"Any coaching/review/retrospective practice counts only when it produces a skill/gate/fewshot/eval diff. The agent doesn't retain across sessions; the **pack** retains."* This is the governing rule and matches this repo's actual practice.
- **B15 — Closure-as-merged-artifact.** Every action item closes with a commit hash, not "we discussed it."
- **Cluster 3.1 decision (lean C):** closure unit = **commit hash for shape-defects; commit hash + eval diff for semantic-defect closures.** Rationale: B15 alone is too lax ("we updated the prompt and ticked the box"); universal eval-diff is too heavy.
- **Cluster 3.2 decision (lean A):** cadence = **per-event AAR + weekly COE batch.** Daily Toyota-Kata coach sessions explicitly rejected as "theatre without retention"; kata becomes anomaly-triggered (F11), not scheduled.
- **Cluster 3.3 decision (lean C):** eval lifecycle layers **1 + 2** (closure-time eval add; per-skill cross-model regression), layer 3 (held-out adversarial sweep) marked a milestone.
- **Cluster 3.4 decision (lean B):** reviewer-accuracy tracking is **opt-in, self-visible only** — visible-to-others weaponizes it.
- **Cluster 7.1 (lean A):** first five skills = `hypothesis/`, `selection/`, `escalate/`, `aar/`, `coe/`.
- **X2** (a cross-cutting finding): *"Automated catch has semantic blind spots, and AI widens them… shape-defects automatable; meaning-defects need humans."*
- **Anti-patterns named** in `marching-orders.md` that a learning system must defend against: **Lean theater** (borrowing COE forms without the social system), **Coaching without retention closure**, **Metric without corrective**, **Spec-as-training-data** ("Including past COEs in agent context teaches surface forms, not patterns. Keep a held-out adversarial set"), **Five-Whys linearity**, **Blame leakage** ("the model hallucinated" is the AI version of "human error"), **Just-restart**.

**What actually landed:** nothing but `docs/foundation.md`. `git log -- specs/tk-px5od` returns a single bulk commit (`d37ec5e`); `docs/foundation.md` has two commits, the second being `2819f8c` (the architecture doc). There is **no `skills/aar/`, no `skills/coe/`, no `skills/escalate/`, no `skills/selection/`, no `skills/hypothesis/`**. `find . -iname '*eval*'` returns exactly one hit: `specs/tk-3s5uo/oversight-rig-eval.md` (an unrelated rig evaluation). **No evals directory exists anywhere in the pack.** `selection-menu.md` is itself marked superseded by `marching-orders.md`.

`roadmap.md` is the explicit parking lot ("this doc is the parking lot, not the graveyard"). Its highest-leverage un-built items, each with an "unblocks when":

- **Silent-decision audit** — Form 1 "growing gates" (*"Gates accumulate from evidence, not from a priori design"* — which is a precise description of what `doctor/` already does informally) and Form 2 inter-agent peer audit.
- **Agent roster watching scope** — *"Mechanik watches for implementation drift (silent fixes that should have been documented or tested)."*
- **Hidden metrics** (from `research/v7-hidden-metrics.md`): frame-redirect rate, reviewer trust trajectory, **half-life of skills and gates** (*"When was each last touched? T3 says the pack learns; H3 says the pack also decays. Audit by age, not just by event."*), and **pack self-knowledge depth** as the gating precondition.
- **Prompt-as-evaluated-artifact** / **cross-model regression suite per skill** / **calibrated trust ledger per skill** — all "unblocks when skills exist and have usage history."

#### 2.12 The molecule-check interlock

`docs/architecture.md` names the target — "a molecule step signs off a check, and a check that has not run runs itself" — and then flatly states: **"It is mostly unrealized."** This matters because the natural home for an auto-generated learning check is a molecule step that discharges it.

---

## 3. Raw-signal sources that exist today

| Signal | Where it lives | Machine-readable? | Read by anything? |
|---|---|---|---|
| **mechanik auto-memory** | Provider memory path on the operator's machine — **outside this repo**. ~100 entries indexed in `MEMORY.md`. Two filename families: `feedback_*.md` (rules mechanik has been corrected on) and `project_*.md` (incident records + current-state operational facts). Inventoried in `specs/tk-yw3zb.1/central-doc-inventory.md` §2b, which buckets entries three ways (promote-candidate / stay-local rule+reason / stay-local incident) with named examples. | Loosely — filename prefix + `MEMORY.md` index | Only `mol-doc-keeper-memory-audit`, whose gates reject nearly all of it. Shared read/write between mechanik and mechanik-thread — `template-fragments/thread-role.template.md` warns: *"Be careful about writing memory mid-thread; the canonical may be operating on the same file."* |
| **Decision beads** | `bd create "..." -t decision` (`agents/mechanik/prompt.template.md`; listed as a mechanik input). `services/helm/internal/source/supervisor.go:321` fetches `/beads?type=decision` for the board. | Yes (bead type) | The helm board surfaces them. No audit reads them. |
| **Desire-path beads** | Named twice: `agents/mechanik/prompt.template.md` ("Desire-path beads filed by other agents") and `agents/mechanik/PROVENANCE.md`. | — | **Vocabulary only.** No formula, script, skill, or template instructs any agent to file one, and no consumer exists. Purely aspirational. |
| **PR review verdicts** | Bead notes (the fixed `VERDICT:` block in `skills/signoff-review/SKILL.md` §6) + a `gh pr review --comment` on GitHub. Refinery stamps `check.<name>=green@<sha>` markers on the anchor. | Semi — the verdict block is fixed-shape but free-text | Consumed *within* the PR (gate + rework). Nothing aggregates across PRs. Findings die when the anchor closes. |
| **Pilot-learnings / findings docs** | `specs/tk-0tdy7/pilot-learnings.md` is the exemplar: a provenance table, per-pilot wall-time tables, a "push-timing learning baseline" confirmation, a named operator-stated gap (§3 downstream cspell commits) with four remediation options, §4 friction observations, and §5 "Open questions for the formula design" as explicit input to another bead (`tk-ztapg`). Siblings: `specs/2026-08-fresh-start/{live-adoption-findings,-round2,-round3}.md`, `build-factory-trial-{findings,reactions}.md`, `follow-ups.md`, `specs/tk-5wdy8/findings.md`, `specs/tk-gi2pc/rig-scoped-order-unbound-firing.md`. | No — prose | Read when linked-to (`docs/file-structure.md`: local docs are "read when linked-to"). Not scanned. |
| **`specs/2026-08-fresh-start/follow-ups.md`** | Ten items captured from the PR #259 review, each with "the operator's raise, plus the initial read banked so the future conversation starts warm." Explicitly *"Candidates for beads at intake."* Item 5 even proposes a doctor check ("asserting every formula description opens with a when-to-use sentence"). | No | Manual. |
| **Commit messages** | The de-facto lesson corpus. Convention: `fix(<area>): <symptom in one line> (<bead-id>) (#<PR>)`. Read `git log --oneline` and you get 25 legible failure modes. | Semi — bead id + PR number are extractable | Nothing reads them. |
| **`doctor.toml` descriptions** | 12 one-sentence invariant statements, most citing the bead that paid for them. | Yes (TOML, one key) | `gc doctor` (as display text) and `mol-deacon-patrol` (as mail body). |
| **`gc doctor --json` results** | Runtime. | Yes (`.results[]` with `.name`, `.status`) | `mol-deacon-patrol` step 4 → **mail to mayor**, not a bead. |
| **Bead outcome stamps** | `gc.outcome` (pass/fail/folded/cut-short) on step beads and visits; `rejection_reason`, `blocked_reason`, `recovery_note`, `recovered=true` metadata on work beads. | Yes | Consumed by the state machine. Never aggregated. |
| **Ad-hoc "second time" notes** | `assets/scripts/quota-park-nudge.sh:75`: *"…and it is the second time that lesson has been paid for."* | No | Human noticed it manually. This is exactly the recurrence signal a system should detect. |

---

## 4. Gaps — from "review comment on a PR" to "future agents behave differently"

Tracing the desired path step by step against what exists:

**Step 1 — a reviewer (human or codex) leaves a finding.** ✅ Exists, well-structured: `skills/signoff-review/SKILL.md` mandates P0/P1/P2 + `file:line` + impact + fix, plus an honest coverage line.

**Step 2 — the finding is captured somewhere durable and scannable.** ❌ **Gap.** It lands in bead notes and on GitHub. Bead notes are explicitly *"operational state, not the record"* (`template-fragments/file-work-records.template.md`). No index, no corpus, no schema. The one durable-corpus mechanism the pack has — mechanik auto-memory — is written only by mechanik, only from mechanik's own sessions, and lives outside the repo at a hardcoded absolute path.

**Step 3 — recurrence is detected across findings.** ❌ **Gap, and it is the biggest one.** Nothing counts how often a defect class recurs. `mol-triage-recurrence` despite its name is a conversation scheduler. The px5od epic named this precisely — **B17 "Quarterly meta-review for repeats"** (*"Repeats are the signal that a one-off fix didn't reach the underlying pattern"*) and **B14** (per-event AAR + periodic batch that "produces 1–2 full COEs on the patterns that recur") — and neither exists. Note the signoff skill already names a recurring defect class in prose: *"The recurring defect class here is a predicate fixed in one copy and left stale in two."* That observation is not counted anywhere.

**Step 4 — the recurrence is routed to the right target surface.** ❌ **Gap, and it is structural, not just missing plumbing.** The only audit→edit pipeline that exists (`doc-keeper`) can target **only `docs/gascity-*.md`**. `specs/tk-yw3zb.1/central-doc-inventory.md` §2a explicitly rules prompts out:

> `agents/{…}/prompt.template.md` — These are agent behavior specs, not "what is true now" docs… **out of scope for doc-keeper** — separate maintenance regime (prompt-engineering reviews, vendor-pack updates)

That "separate maintenance regime" does not exist. **There is no mechanism today that can route a learning into `template-fragments/`, `pack.toml`, a formula step, a skill, or a doctor check.**

**Step 5 — the gates would let it through anyway.** ❌ **Gap.** Even if a PR finding reached the memory audit, gate 1 (nature) rejects it: agent-conduct corrections and one-off incidents are named as never-promoting. Gate 2 (scope) requires a brief that *cleanly owns* it. A review finding is operational by construction. The audit's designed yield for exactly this class is zero.

**Step 6 — the edit gets tested.** ❌ **Gap.** No evals exist. A fragment edit's only verification is (a) whatever doctor check happens to grep for a string in it, and (b) a human reading the PR. px5od's I10 ("a prompt change without an eval change is rejected the way a code change without tests is") and I11 (cross-model regression) are both un-built and both listed in `roadmap.md` as "unblocks when skills exist and have enough usage history."

**Step 7 — the edit ships and future agents behave differently.** ✅ Exists, and this half is strong: the `doc-update` change-unit bead → `mol-polecat-work` → refinery → one small PR → merge → agents render the new prompt on next `gc prime`. The drift audit proves this half runs end to end.

### Additional structural gaps

- **`## Scope` charters exist only for `docs/gascity-*.md`.** The whole gap-vs-drift distinction in `docs/file-structure.md` ("something *in-scope but missing* is a gap to close; something *out-of-scope* was correctly skipped. Without stated edges, every absence looks like a gap") depends on the charter. **Fragments, formulas, and skills carry no charter**, so a gap audit cannot be run against them without inventing one.
- **Doctor findings terminate in mail, not a bead.** `mol-deacon-patrol` mails the mayor. A doctor RED does not become routed work, so it cannot ride the delivery pipeline. And that path has already failed silently once (`0c52288`).
- **No half-life / decay audit.** `roadmap.md` names it ("half-life of skills and gates… Audit by age, not just by event"). `doctor/check-rig-scoped-orders-bound`'s own description says it will be *"permanently green once that lands"* — a check that has outlived its purpose, with no mechanism to notice.
- **No lesson→check generator.** All 12 checks are hand-authored bash. No done-sequence step, formula, or skill says "file a doctor-check bead for this."
- **mechanik's Principle 6 is the right rail with no ramp.** `agents/mechanik/prompt.template.md` Principle 6: *"Dispatch gc-toolkit edits, don't make them… Even small typo-class fixes go through the polecat path: it's fast enough, and the audit trail matters more than the saved minute."* But no formula files a prompt-change bead. Mechanik does it by hand, from a session, from its own recall.
- **The hand-sync hazard** between `pack.toml`'s polecat `inject_fragments_append` and `agents/polecat-codex/agent.toml`'s `inject_fragments` is unguarded by any doctor check. A learning system editing polecat doctrine can silently half-apply.
- **Mechanik has no explicit "watch" mandate.** `roadmap.md` proposes it ("Mechanik watches for implementation drift"); `docs/architecture.md`'s three-hats test says a domain earns a standing agent only when it needs *partner + active watch + library*, and *"Only the first survives as a molecule — patrolling and indexing are continuous."* Mechanik today is the partner hat only; the watch hat is exactly what a learning system would supply as a molecule.

---

## 5. Rails a new learning system can ride

### 5.1 The `gc order` cron rail

`orders/*.toml` is the whole registration — *"the order file IS the registration and is re-scanned on every `gc` start,"* durable across controller restarts unlike the town's session-only `CronCreate` (`orders/doc-keeper-drift-audit.toml` header). Canonical shape:

```toml
[order]
description = "..."
formula = "mol-<name>"
trigger  = "cooldown"
interval = "24h"
pool     = "gc-toolkit.polecat"   # BARE, never rig-qualified
scope    = "rig"
```

Three hard-won constraints, all documented in `orders/doc-keeper-drift-audit.toml` and enforced by `doctor/check-liveness-sweep-wired/run.sh`:

1. **`scope="rig"` + BARE pool.** `scope="city"` puts the wisp in the city store that rig polecats never read; a rig-qualified pool strands it in every importer that isn't gc-toolkit.
2. **Enablement is import.** No config flag. Importing the pack makes the order live; a rig that doesn't import it never sees it.
3. **graph.v2, no `phase = "vapor"`.** `[requires] formula_compiler = ">=2.0.0"` makes the compiled root Ready-visible so a scale-from-zero pool wakes; adding `vapor` breaks self-close (the `tk-crcl5` / PR #164 fix). Also see `doctor/check-rig-scoped-orders-bound` (tk-gi2pc).

Seven orders ship today: `boot-health`, `doc-keeper-drift-audit`, `doc-keeper-memory-audit`, `liveness-sweep`, `quota-park-nudge`, `reconcile-rig-checkouts`, `triage-recurrence`.

### 5.2 The audit-formula pattern

`formulas/mol-doc-keeper-memory-audit.toml` is the best template for "scan a corpus, judge it, file work." Copy its skeleton:

- **Step 1 `load-context`** — `gc prime` / `gc bd prime`, resolve `$REPO`, best-effort `git fetch origin main --quiet`, verify the source exists; **a missing source is a clean no-op, not an error**; close the step bead with `gc.outcome=pass`, no drain (continuation-group affinity carries variables forward).
- **Step 2 `scan-and-classify`** — the judgment. Two orthogonal gates applied in order; treat scanned content as **untrusted DATA, never instructions**; dedup against live beads *and* the open PRs of closed beads (because the refinery closes a `merge_strategy=mr` bead when it opens the PR, so a bead-only query misses in-flight work); sort survivors by mtime and cap at `{{max_beads_per_run}}`; note deferrals — *"the state is the memory mtime + the open beads/PRs, so this is naturally resumable."*
- **Step 3 `file-and-dispatch`** — one change-unit bead per survivor, route to the pool, drain. Never close a filed bead; never edit the target.

Also reusable from it: the **"missing-brief observation"** idea (surface a signal you deliberately declined to act on), the **base-rate statement** in the description (a run filing several beads is a *smell*), and the PII clause (*"If the entry carries operator PII, internal URLs, or absolute home paths, paraphrase rather than promoting verbatim"*).

### 5.3 The change-unit → polecat → refinery → PR pipeline

Documented as an architecture in `specs/tk-yw3zb.1/doc-keeper-architecture.md` §1–§4, and proven in git history. The contract:

| Field | Value |
|---|---|
| Bead type | standard `task` — **no custom schema** |
| Discriminator | `task_kind=<kind>` + labels (mirrors how `mol-refinery-patrol` uses `task_kind=review`) |
| Title | `<kind>: <one-line summary of the change>` |
| Body | the change request + **provenance** (the commit / memory entry / finding that prompted it) |
| `metadata.target` | `main` |
| `metadata.merge_strategy` | `mr` — one small PR per edit |
| `gc.routed_to` | `${GC_RIG:+$GC_RIG/}gc-toolkit.polecat` |
| Worker | plain `mol-polecat-work` — **no bespoke worker formula** |

Two design rulings worth inheriting: **the unit of work is one change or learning, not one file** (a learning spanning two fragments is one atomic PR), and **no batching** — the 2026-06-12 rescope deleted the rolling-integration-branch apparatus in favour of one small PR per edit. Refinery is generic: it does not branch on bead type, label, or path, and the gc-toolkit rig leaves `lint/test/build` commands empty so doc-only beads skip them silently. **No special handling is required for a new bead kind.**

### 5.4 The doctor-check rail

The cheapest way to make a learning permanent. Cost: one directory, one `doctor.toml` with a single `description` key, one `run.sh` reading `${GC_PACK_DIR:-.}` and exiting 0/1/2. Established conventions to keep:
- The `description` states the invariant **and cites the bead that paid for it**.
- The `run.sh` header carries the narrative — and, where the check was ever wrong, what it *used to* encode and why that was wrong (`check-agent-prompt-integrity`).
- WARN (exit 1) for "deliberate but rotting" (the base-snapshot mechanism in `check-base-artifact-collision`, retired 2026-08-15 — tk-3w7p7 — but the pattern stands); ERROR (exit 2) for "cannot be right."
- Add a `run.test.sh` when the logic is non-trivial (3 of 12 have one).
- Remember the read-side is `mol-deacon-patrol`'s `.results[]` filter — a new check is automatically escalated to the mayor by mail once it exists.

### 5.5 The visit / converse spine (for the human-judgment step)

Any learning that needs a human decision should file a **visit**, not a ping. Use the marked block verbatim — `# >>> gate-visit … # <<< gate-visit` — which appears in `formulas/mol-visit.toml`, `mol-first-reaction.toml`, and `mol-triage-recurrence.toml`, and whose presence is asserted by `doctor/check-liveness-sweep-wired`. Key invariants baked into that block: route to `${GC_RIG:+$GC_RIG/}gc-toolkit.converse`, stamp `gc.continuation_group=<subject>` and `task_kind=visit`, and use `gc bd dep add … --type=tracks` — **never parent-child**, which would transmit the subject's blocked state and make the visit unclaimable. Also: never stack a second visit on a subject that already has one live (open *or* `in_progress`).

The "one triage subject curating a scoped pool" pattern from `mol-triage-recurrence` maps directly onto "one standing subject curating the learning backlog": scope tokens in `triage.scope` metadata, one visit only when the scope has candidates, batched review rather than N board rows. The operator's ruling in `specs/2026-08-fresh-start/operating-principles.md` P3 — batched, scoped, plural triage subjects, **never a single resident agent** — applies verbatim.

### 5.6 The card / takeaway surface

`mol-first-reaction`'s fixed card shape (`Understanding · Found (freshness-stamped) · Proposal · Decision needed`) plus `gc-helm.sh takeaway <bead> "<≤140 chars>" --by <who> --release` gives you a board-visible one-line headline in the same Dolt write that releases the bead. That is the ready-made framing artifact for "here is the recurring pattern; accept or redirect."

### 5.7 The dispatch-carries-the-method rail

`assets/scripts/review-dispatch-body.sh` + `skills/signoff-review/SKILL.md` is the pattern for making a method reliable without a per-agent skill allowlist (which gc does not have): **one authored copy** in the skill file, **inlined verbatim** into the bead body by an emitter, with a **fail-soft** degraded path plus a stderr WARN. If a learning system needs a new procedure followed by arbitrary polecats, this is the shape.

### 5.8 The filing rail

`skills/filing-documentation/SKILL.md` + `template-fragments/file-work-records.template.md` + `docs/file-structure.md` already answer "where does a learning document go": a synthesis someone owns keeping current → `docs/<topic>.md` (needs a `## Scope` charter); a record of what was found on one bead → `specs/<bead-id>/`. Note the four-condition bar for a new `docs/gascity-*.md` in `docs/gascity-reference.md` — condition 2 is *"The learning is durable, not bead-tied. One-incident gotchas live in `specs/<bead-id>/` or working memory"*, which is exactly the boundary a feedback-learning system must argue against or work around.

---

## 6. The shortest credible path (synthesis, not a recommendation)

Every piece needed for a closed loop exists **except the corpus and the recurrence detector**, and the target surface is blocked by an explicit scope exclusion. Concretely, the missing pieces are:

1. **A corpus inside the repo.** Something a formula can glob, versioned with the pack, not a hardcoded absolute path on one machine. The pack has no home for this today; `specs/<bead-id>/` is the closest fit under existing conventions, and `docs/file-structure.md`'s tier rules would have to be consulted (or extended) for a cross-bead corpus.
2. **A capture step** at the two points where findings already exist in structured form: the signoff verdict block (`skills/signoff-review/SKILL.md` §6) and the refinery's round-cap escalation (`mol-refinery-patrol.toml`, `blocked_reason="signoff did not converge…"`).
3. **A recurrence audit** on the `orders/` + audit-formula rail (§5.1, §5.2) — same skeleton as the memory audit, different corpus, different gates. The gates are where the real design work is; the memory audit's two-gate structure and its explicit base-rate statement are the model to argue with.
4. **A `prompt-update` change-unit kind** parallel to `doc-update`, reusing §5.3 unchanged, whose target set is `template-fragments/`, `pack.toml`, `formulas/`, `skills/`, and `doctor/`. This requires either extending doc-keeper's charter past the `docs/gascity-*.md` glob or standing up the "separate maintenance regime" that `specs/tk-yw3zb.1/central-doc-inventory.md` §2a names and never defines — and it needs a charter convention for fragments, since `## Scope` is what makes gap-detection possible at all.
5. **A verification story for prompt edits.** Today the only one is a doctor check that greps for a string. `roadmap.md` and `ideation.md` I10/I11 describe the eval-suite answer; nothing has been built toward it.

And two doctrinal constraints that will shape whatever gets built:

- **`docs/architecture.md`'s consistency test.** The capability must compose existing primitives the way an existing standing system does — most naturally *Engine health* (molecule + check) or *Doc & knowledge cohesion* (molecule + routing through Delivery). "Agents improve has no primitive of its own" is a deliberate constraint, not an oversight.
- **`docs/foundation.md`'s "no process for its own sake"** and `marching-orders.md`'s **"metric without corrective"** / **"lean theater"** anti-patterns. A recurrence count that triggers no corrective, and an AAR template with no merged-artifact closure, are both already named in this repo as failure modes.
