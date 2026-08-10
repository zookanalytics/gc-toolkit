---
name: Fleet Learning System — Capture, Promotion, and Pruning
description: Storage-agnostic design for the three cross-cutting subsystems of an agent-fleet learning loop — signal capture taxonomy, evidence-based promotion (anti-gospel), and budgeted pruning with hardening (anti-bloat) — grounded in gc-toolkit's bead/molecule/order/doctor idioms.
---

# Fleet Learning System: Capture, Promotion, Pruning

Two failure modes bracket this design. **GOSPEL**: one strongly-worded review comment
("NEVER leave historical-artifact references!") becomes a permanent fleet-wide rule on the
strength of a single reaction. **BLOAT**: rules accumulate monotonically until every prompt
is a scar-tissue museum and marginal rules degrade the whole surface. The system must add
*and* remove, and both must be evidence-driven, not vibe-driven.

Everything below is expressible on any of three storage substrates (bead metadata, a
lessons file/directory in-repo, or an external DB). Where a choice depends on storage it is
marked **[storage]**. The unit of record is a **lesson**: a candidate behavioral rule with
provenance, scope, evidence list, and lifecycle state — the analogue of doc-keeper's
change-unit bead, deduped on the lesson, never on the message that reported it.

## When learning happens (three timescales)

The operator's "when does learning happen?" dissolves once split into three clocks:

1. **Capture is continuous and in-flow.** Any moment feedback appears — a review comment, a
   conversation correction, an operator command — a raw *observation* is filed. Filing is
   cheap, append-only, and requires no judgment beyond "this looks like corrective feedback."
   Capture never edits a prompt. This is what makes capture safe to run everywhere: a bad
   observation costs one record, not a rule.
2. **Distillation + promotion is periodic, at audit time.** A cron-fired formula (the
   doc-keeper / mol-triage-recurrence pattern: an order fires daily, files work only when
   there are candidates) clusters observations into lessons, scores evidence, and files
   promotion/demotion proposals as ordinary reviewable work. Judgment runs cold, batched,
   with the full evidence list in view — the structural antidote to gospel, because no
   single hot moment ever writes a rule.
3. **Emergency adoption is operator-driven and marked.** `learn: ... --now` bypasses the
   thresholds by explicit human authority. The bypass is recorded *as* a bypass
   (`endorsed_by=operator`, evidence N may be 1), so a later challenge audit knows this rule
   was decreed, not corroborated, and re-examines it on the same footing as any other.

Splitting the clocks resolves the tension directly: capture must be immediate or fidelity is
lost; adoption must be slow or gospel wins; and the operator retains a fast path that is
visible rather than laundered through fake evidence.

## A. Signal capture taxonomy

Five capture points, characterized on latency / fidelity / coverage / cost / spoofability.
"Spoofability" = how easily a non-signal (sarcasm, misread, agent self-justification, or a
malicious/confused third party's comment) enters the record as if it were operator intent.

| # | Capture point | Latency | Fidelity | Coverage | Cost | Spoofability |
|---|---|---|---|---|---|---|
| 1 | In-conversation self-report (agent files an observation when corrected) | seconds | high — full conversational context available at capture | only conversations an agent is present in; agents under-report corrections that embarrass them | near-zero marginal (one record per event) | medium — the *agent* interprets the feedback; misreading and self-serving paraphrase are real |
| 2 | PR-review mining (periodic sweep of merged-PR review threads) | hours–days (cron) | medium — thread text without live context; tone/sarcasm harder to read cold | best of all: catches feedback the operator gave when **no agent was present**, and feedback agents failed to self-report | low, batched; grows with PR volume | low-medium — reviews are attributable and durable, but any reviewer's comment enters the pipe, so weight by author identity |
| 3 | Operator explicit command (`learn: ...`) | seconds | highest — operator states the lesson in their own words, often with intended scope | only what the operator remembers to file | zero | lowest — authenticated, intentional; *the* trusted channel |
| 4 | Automated detection (reviewer-agent flags the pattern itself, e.g. a verbose-comment detector) | minutes (per-PR) | high precision *for encoded patterns only*; blind to everything not yet encoded | full coverage of what it encodes | build cost per detector; cheap to run | very low — deterministic; but note it detects only *known* lessons, so it belongs to enforcement/measurement more than discovery |
| 5 | Post-hoc retro audits of incident/bead trails | days–weeks | low-medium — reconstructive, context decayed | catches systemic patterns invisible per-event (the same correction across 5 unrelated beads) | highest — an agent-run reading pass over trails | low — reads durable records |

**Build first: #3, #2, then #1.** #3 is trivial and gives the operator the escape valve day
one. #2 is the workhorse: highest coverage, catches operator feedback given in the agent's
absence, and runs as a cron order + formula exactly like the doc-keeper audits — no new
machinery. #1 is a prompt-level instruction ("when corrected, file an observation before
acting on the correction") — cheap, but arrives with #2 as its safety net since agents will
miss it. Defer #4 to the *hardened* lifecycle stage (it is the output of learning, not an
input) and #5 until trail volume justifies it.

**The double-count problem.** The same event — operator comments on PR #412, the agent
present self-reports it (#1), the nightly sweep finds it again (#2) — must count as ONE
occurrence or the system inflates its own evidence and self-gospels. Rule: every observation
carries a **provenance key** = `(source_kind, source_id, thread/comment id, author, date)`
— e.g. `pr:owner/repo#412:comment:98765`. Distillation dedupes on provenance key *before*
counting: two observations with the same key merge, keeping the higher-fidelity capture
(#1's context) and both capture-point tags. Same discipline as doc-keeper: "dedup is on the
change — never two PRs for the same change." **[storage]** the key is the same everywhere;
only the uniqueness enforcement differs (bead metadata query vs. file key vs. DB constraint).

## B. Evidence & promotion model (anti-gospel)

### What counts as one independent occurrence

One occurrence = one **(provenance-deduped event, distinct work unit, distinct day)**
triple. Concretely: distinct PR *or* distinct bead, and not the same calendar day as another
occurrence from the same work unit. Rationale: five comments on one PR thread are one
occurrence (one annoyed reviewer, one context); the same nit on three PRs across two weeks
is three (a pattern). Same-day/same-bead repeats collapse because a reviewer restating
themselves is emphasis, not independence. Distinct *author* is not required but is recorded
— two humans independently flagging the same thing is strong and can be weighted (counts as
+1 occurrence bonus), one human flagging it thrice is still a signal worth 3, but see
strength-of-reaction below.

### Thresholds scale with blast radius

The wider the scope a lesson would touch, the more independent occurrences it needs:

| Scope | Promotes to adopted at | Rationale |
|---|---|---|
| file/module-specific | 2 occurrences | cheap to adopt, cheap to retire, small blast radius |
| repo-specific | 2–3 | moderate radius; 2 if same author twice, 3 if mixed signals |
| role-specific (one agent prompt, fleet-wide) | 3 | changes every run of that role |
| fleet-wide (all agent prompts / shared brief) | 4 | maximum blast radius; also requires an explicit operator sign-off check before landing |

**Operator endorsement bypasses any threshold** — `learn: ... --now` or an approval on a
candidate — but the lesson is permanently marked `endorsed` with N at time of endorsement.
Endorsed rules are not second-class, but challenge audits (§C) treat `endorsed, N=1` as
first in line for re-confirmation, because a decree has never been corroborated by the world.

**Strength of reaction is NOT promotion evidence.** One furious ALL-CAPS comment is exactly
one occurrence. What strength *does* buy is **priority**: high-heat observations get
distilled in the next cycle rather than batched, and may trigger filing an investigation
visit for the operator ("this seemed to matter to you — confirm scope?"). Heat routes
attention; count moves state. This single sentence is the anti-gospel core.

**Negative evidence triggers re-review, never silent flip-flop.** An observation that
*contradicts* an adopted lesson (operator says "actually, a comment here is fine — this
constant is genuinely non-obvious") does not decrement-and-auto-retire. It files a
**contention** on the lesson: state moves `adopted → contested`, the rule stays in force,
and a review visit is routed to the operator with both evidence lists framed. Outcomes:
scope-narrow (most common — the rule was right but over-broad), retire, or dismiss the
contradiction. Silent flip-flop is gospel's mirror image: the last-loudest voice winning.

### Scope inference

At distillation, each lesson gets a scope guess from its evidence footprint: all occurrences
in one file → file-scoped; one repo → repo-scoped; multiple repos or the feedback text
generalizes ("stop doing X *everywhere*") → candidate fleet-wide, but **default one level
narrower than the evidence suggests** and let recurrence at the wider scope widen it later.
Widening is a normal promotion (new evidence at the wider scope, wider threshold applies);
narrowing is the standard resolution of a contention. Explicit operator scope in a `learn:`
command overrides inference.

### Lesson lifecycle state machine

```
observed → candidate → corroborated → adopted → hardened
                │            │           │  ↘ contested → (adopted | scope-narrowed | deprecated)
                └────────────┴───────────┴──→ deprecated → retired
```

| Transition | Driven by |
|---|---|
| raw event → **observed** | any capture point (continuous, mechanical) |
| observed → **candidate** (N=1) | distillation formula: clusters deduped observations into/onto a lesson |
| candidate → **corroborated** (N ≥ scope threshold) | distillation formula, automatic on count |
| corroborated → **adopted** | a promotion bead lands through the normal delivery pipeline — the prompt edit is a reviewable PR; fleet-wide scope adds an operator check. Adoption records `adopted_at`, `review_by`, and the prompt-surface token cost |
| any → **adopted** (bypass) | operator endorsement, marked `endorsed` |
| adopted → **hardened** | mechanization bead: the rule becomes a doctor check / linter / reviewer-agent detector; the prompt text is **removed** in the same change. All three motivating examples partially mechanize: stale "historical artifact" references → grep-class doctor check for banned phrases ("previously", "used to", "legacy note:"-style markers) with an allowlist; verbose comments → heuristic linter (comment token-overlap with adjacent code; literals in comments duplicating nearby constant values); boilerplate-in-wrong-file → fingerprint known boilerplate blocks, flag when file type/path doesn't match the template's applicability list. "Partially" is fine — the check catches the 80% mechanical core, and residual judgment cases re-enter as fresh observations |
| adopted → **contested** | negative-evidence observation; routes a review visit |
| adopted/hardened → **deprecated** | challenge audit finding, expired review-by date, or operator call; rule text removed from prompt (check disabled but kept) |
| deprecated → **retired** | one quiet review period (e.g. 60 days) with no recurrence of the tagged category; record archived, never deleted — provenance is the defense against re-learning a bad rule *and* against re-litigating a good retirement |
| deprecated → adopted | recurrence during the quiet period resurrects it — evidence that the rule was load-bearing |

## C. Pruning & evaluation (anti-bloat)

**Token budgets make cost visible.** Every prompt surface (per-role prompt, shared fleet
brief, per-repo addendum) declares a lesson-section budget — e.g. 600 tokens per role
prompt, 1000 for the fleet brief **[storage: where the budget number lives varies; the
invariant doesn't]**. A promotion that would exceed the budget cannot simply land: the
promotion bead must name what it displaces — deprecate the weakest incumbent (stale
review-by, zero recent confirmations), harden an incumbent out of the prompt, or compress.
A doctor check (`check-prompt-lesson-budget`) asserts every surface is under budget, so
budget violations block landing exactly like any other check. Zero-sum by construction:
adding is never free, and the marginal rule must beat the current worst rule to get in.

**Every adopted lesson carries freshness metadata**: `review_by` (default adoption + 90
days; endorsed-N=1 rules get 30) and `last_confirmed_useful` — updated when a hardened
check fires, a reviewer-agent detector catches an instance, or a new deduped occurrence of
the category appears (the rule is still guarding against a live pressure). A rule past
`review_by` with no confirmations is presumptively dead weight.

**Challenge audits** — a cron order + formula, mirroring the doc-keeper audits in shape and
mol-triage-recurrence in restraint (file work only when there are candidates, never stack).
Each run samples K adopted lessons, oldest-review-by first, and asks per lesson: (a) any
occurrences of the tagged category since adoption — if the behavior it forbids has never
been seen since, either the rule works or it was never needed; (b) can this be hardened —
if yes, file a mechanization bead (the *preferred* outcome); (c) does removing it plausibly
change behavior — is the model likely to do the right thing without being told (many 2024-era
lessons are 2026 base behavior)? Output: retirement-candidate / harden / reconfirm beads,
routed as ordinary reviewable work. Retirement is a PR the operator can see, not a silent GC.

**Hardening is the best pruning.** A lesson converted to a doctor check or linter leaves the
prompt entirely: zero recurring token cost, deterministic enforcement, and a built-in
usefulness meter (the check's fire rate *is* `last_confirmed_useful`). The prompt says
nothing; CI enforces it. The challenge audit's first question should always be "can this
leave the prompt?" — the steady state to aim for is a small prompt of genuinely
judgment-requiring lessons above a growing floor of mechanized ones. The doctor-check idiom
(self-contained `run.sh` + `doctor.toml`, each check born from one hard-won lesson) is
exactly this pattern already operating in the engine-health system.

**Measuring whether a rule ever worked: recurrence rate.** Every observation is tagged with
its lesson/category id at distillation, which makes the question computable: occurrences of
category X per unit of review activity (per 100 merged PRs — normalize, since raw counts
confound with fleet throughput) before vs. after adoption. A rule whose category recurs at
the pre-adoption rate is demonstrably not working — retire it or harden it, but stop paying
tokens for it. Implement as `mol-lesson-recurrence`, structurally mirroring
mol-triage-recurrence: a daily order; for each adopted lesson, count tagged occurrences in
the window; file a review visit only when the number says something (recurrence above
floor after adoption, or a clean N-week zero streak supporting retirement); never stack a
visit on a lesson that already has one live.

**Golden-set eval: honest assessment — don't build it early.** The idea: keep a small set
of real diffs/PRs that historically drew feedback, replay them against a prompt variant
(with vs. without a rule), and diff agent output. It is genuinely cheap to *run* but not to
*maintain*: the golden set goes stale as repos move, "did the output improve" needs an
LLM-judge whose noise can exceed the signal for single-rule deltas, and at fleet scale of
tens of rules the recurrence metric answers the same question from production data at zero
marginal cost. Verdict: over-engineering at this stage. Build it only when (a) a specific
high-stakes fleet-wide rule change needs pre-landing validation, or (b) recurrence data is
too sparse because fleet throughput is low. Until then, the eval *is* production +
recurrence measurement + cheap retirement (any wrongly retired rule announces itself by
recurring and resurrects via `deprecated → adopted`). The system's reversibility is what
makes the expensive eval unnecessary: mistakes in either direction are cheap to observe and
cheap to undo, which is the whole design in one sentence.
