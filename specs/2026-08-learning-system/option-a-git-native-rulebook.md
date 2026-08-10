---
name: Option A — Git-Native Rulebook (feedback-learning design sketch)
description: A design for folding operator feedback (PR comments, discussion turns) into the standing prompts as versioned repo content, riding the existing orders → audit-formula → change-unit-bead → polecat → refinery rails. Covers the learnings ledger, candidate/adopted/retired lifecycle, graduated-trust merge variants, anti-gospel machinery, hardening lessons into doctor/lint checks, and honest weaknesses.
---

# Option A: Git-Native Rulebook

Everything the system learns from operator feedback lives in the repo as
versioned files and moves through the same rails as every other change:
a cron-fired audit formula files change-unit beads, a pool polecat edits
files under `mol-polecat-work`, the refinery lands the result on `main`.
This is doc-keeper's loop (`specs/tk-yw3zb.1/doc-keeper-architecture.md` §1)
pointed at a new target surface: not the agent brief, but the **standing
prompts themselves**.

**Consistency-test trace** (docs/architecture.md): belief — *Agents improve*
plus *Decisions have a home*; primitives — molecule (the audits), bead (the
change unit), routing (pool dispatch); composition — identical to the
Doc & knowledge cohesion standing system. Nothing here is new machinery-kind;
it is doc-keeper with a second charter.

## 1. The artifact: `learnings/` ledger + `learned-rules-*` fragments

Two surfaces, deliberately separate, because the operator's top requirement
is that *recording* an observation must not *change* any prompt.

**The ledger — `learnings/<slug>.md`, one file per lesson.** Slug-keyed
(`learnings/comment-restates-code.md`, `learnings/stale-historical-artifact-refs.md`),
not bead-keyed: evidence accrues across many beads, and the lesson outlives
any one of them. Per `docs/file-structure.md` ("Location is set at
file-time"), lifecycle state lives in frontmatter, never in the path — no
`candidates/` vs `adopted/` directories, no moves on promotion.

```yaml
---
name: Comments must not restate code
description: Operator repeatedly flags comments that paraphrase the adjacent
  line or copy a constant's value into prose.
status: candidate            # candidate | adopted | retired
scope: polecat               # which fragment surface an adoption edits
statement: >-                # the exact bullet a promotion will inject
  Never write a comment that restates the adjacent code or copies a
  constant's literal value; comments carry the why, the code carries the what.
evidence:
  - {date: 2026-08-02, source: "https://github.com/…/pull/241#discussion_r17…"}
  - {date: 2026-08-07, source: "tk-9fk2x (visit turn, operator note)"}
adopted:                     # date, set by the promotion PR
review_by:                   # adopted + 90d, set by the promotion PR
superseded_by:               # set when hardened into a check (§4)
---
## Notes
Free prose: the operator's exact words, edge cases, near-misses.
```

**The prompt surface — `template-fragments/learned-rules-<scope>.template.md`.**
One fragment per injection scope, each a `{{ define "learned-rules-polecat" }}`
block containing *only* the `statement:` lines of adopted lessons, one bullet
each, capped (default 15 bullets — the forced-ranking budget, §4). No
provenance, no dates, no prose in the prompt: tokens are the scarce thing the
rulebook must respect. Wiring is the existing mechanism, a one-time change:

- gastown-imported agents: add `"learned-rules-polecat"` to the polecat
  `inject_fragments_append` list in `pack.toml` (alongside `polecat-convoys`,
  `polecat-non-impl-done`, `file-work-records`);
- native agents: `{{ template "learned-rules-mechanik" . }}` in
  `agents/mechanik/prompt.template.md`;
- the review gate: `learned-rules-review` injected into the pre-publish
  signoff dispatch, so the codex reviewer *enforces* adopted rules on PRs
  before the operator ever sees them — the shortest path from "learned" to
  "operator stops seeing the mistake".

The ledger is the source of truth; the fragment is a projection. A doctor
check (§4) holds the two consistent, which is what lets them live in
separate files without drifting.

## 2. Lifecycle in git

- **candidate** — ledger file exists (or gained an evidence entry); no
  fragment references it; zero effect on any prompt. This is the "single
  observation recorded without becoming gospel" state.
- **adopted** — one promotion PR atomically: sets `status: adopted`,
  `adopted:`, `review_by:` in the ledger file AND inserts the `statement`
  bullet into the scope's fragment. The prompt surface changes only here.
- **retired** — one retirement PR: removes the bullet from the fragment,
  sets `status: retired` plus a retirement reason in Notes. The file stays
  (file-structure: no archiving) — it is the immune memory that stops the
  same lesson oscillating back in, and the challenge audit can cite it if
  fresh evidence argues for re-adoption.

Evidence on an already-retired or already-adopted lesson is still appended —
retired-with-fresh-evidence is exactly the re-adoption signal, and
adopted-with-fresh-evidence means the rule isn't working as prose and is a
priority candidate for hardening into a check (§4).

## 3. What rides the rails: two formulas, two orders

Mirroring `mol-doc-keeper-memory-audit` / `orders/doc-keeper-memory-audit.toml`
exactly — graph.v2 steps, read-only audits that file change-unit `task` beads
(`task_kind` discriminator + labels, `target=main`), pool-routed to
`${GC_RIG:+$GC_RIG/}gc-toolkit.polecat`, worker is plain `mol-polecat-work`
(no bespoke worker formula — the tk-o28ci lesson), refinery lands it.

**`formulas/mol-feedback-audit.toml` + `orders/feedback-audit.toml`** (24h
cooldown). Steps: (1) prime, resolve repo + ledger; (2) scan feedback
surfaces — `gh` review comments on recently closed/merged PRs, plus any
`task_kind=learning-signal` beads filed in-conversation (see below) —
classify each as *matches an existing ledger slug* → evidence-append, or
*new recurring-shaped complaint* → new candidate file; dedup on the exact
comment URL / bead id already cited in `evidence:` (the same
provenance-filename dedup the memory audit uses); (3) file ≤
`{{max_beads_per_run}}` beads, `task_kind=learning-update`, label
`learning`, and drain. Like the memory audit's nature gate, the classifier
has a base-rate stance: most PR comments are about *this diff*, not about
*standing behavior*; the expected yield of a run is one or two candidates,
and a chatty run is a smell.

**`formulas/mol-learning-curator.toml` + `orders/learning-curator.toml`**
(7d cooldown). The promotion *and* challenge audit in one formula, both
read-only-plus-bead-filing: (a) candidates clearing the threshold (§4) →
one `task_kind=learning-promotion` bead each, whose worker edits ledger +
fragment; (b) adopted lessons past `review_by` → a retirement-proposal bead
arguing keep / retire / harden; (c) integrity sweeps the doctor check also
guards (orphan bullets, over-budget fragments) → fix beads.

**When does learning happen?** On audit, not in-conversation — with one
cheap in-conversation on-ramp: a short `capture-learning-signals` fragment
injected into the converse/mechanik surfaces saying *when the operator gives
feedback about recurring agent behavior, file a `task_kind=learning-signal`
bead citing their words; never edit `learnings/` or any fragment yourself.*
Conversation capture is one `gc bd create`; all judgment (is it recurring?
where does it belong?) stays in the audited, rate-limited, deduplicated
cron path.

**Build size.** Two formulas in the house style (~250–350 lines TOML each),
two ~25-line orders, two fragments (~60 lines total), one pack.toml wiring
diff, one doctor check + hermetic test (~250 lines), `docs/learnings.md`
(the conventions above, ~80 lines). A doc-keeper-scale epic: 5–7 polecat
beads, no runtime changes, no new primitive.

## 4. Anti-gospel machinery

**One strong reaction ≠ gospel.** A first occurrence creates a candidate —
inert by construction. Promotion requires, as curator formula vars:
`promotion_min_evidence` (default 3) distinct evidence entries, from ≥ 2
distinct PRs/beads, spanning ≥ 7 days. Overrides exist but are human-shaped:
the operator can file a promotion bead directly ("adopt this now"), which is
just mode-3 operator-driven work on the same rails.

**Repeated feedback = strong signal**, structurally: every recurrence is an
evidence-append commit, so the count *is* the git history, and the curator
reads it off the frontmatter list rather than trusting memory.

**Expiry and challenge.** `review_by = adopted + 90d`. Silence after
adoption is *success*, so the challenge audit doesn't ask "any new
evidence?" — it asks: does the rule still bind (does the anti-pattern
appear in recent diffs at all)? is it subsumed by a newer rule or a check?
does it contradict another bullet? is the fragment over its bullet budget
(if so, force-rank: the weakest-evidenced bullet gets a retirement
proposal)? Removal is a first-class outcome; bloat is treated as drift.

**Hardening — the strongest form of learning.** A lesson whose violation is
mechanically detectable graduates from prose to executable check, and the
prose bullet retires (`superseded_by:` names the check). All three of the
operator's examples are lintable-ish:

- stale "historical artifact" references → grep for the phrase family in
  changed files;
- comment copies a constant's value → flag comments containing the literal
  defined on the adjacent line;
- boilerplate comment pasted where inapplicable → fingerprint comment
  blocks repeated verbatim across files.

Two homes, matching the two things being checked. **Work-product lints**
live as `tools/lint-learned.d/<slug>.sh` behind a `tools/lint-learned.sh`
runner, wired per-rig into the refinery's `lint_command` (empty today in
this rig — turning it on is a deliberate rig decision, since refinery gates
run on every bead). **Pack-integrity** gets a doctor check in the existing
pattern (`doctor/check-learnings-ledger/{doctor.toml,run.sh,run.test.sh}`,
exit 0/1/2, hermetic test): every fragment bullet traces to exactly one
`status: adopted` ledger file whose `statement` matches; no fragment
references a candidate/retired lesson (the **inertness guarantee** variant
b leans on); every adopted file has `review_by`; bullet count ≤ budget.
This is the anti-regression move the doctor/ suite already embodies: a
hard-won invariant frozen into a check so it cannot silently unravel.

## 5. The approval-friction problem: three graduated-trust variants

- **(a) Everything is a normal PR** (`merge_strategy=mr` throughout, exactly
  like doc-update beads). Review load: at realistic feedback volume (~5–10
  qualifying comments/week early on) that is 5–10 near-trivial
  evidence-append PRs plus ~1 promotion PR per week. The trivial ones train
  the operator to rubber-stamp — which then bleeds into the promotion PRs,
  the only ones where review genuinely matters. Safest on paper, worst
  attention economics; contradicts *Human attention is the budget*.
- **(b) Split trust by surface (recommended).** Ledger-only beads
  (candidate creation, evidence appends) set `merge_strategy=direct` — the
  refinery fast-forwards them onto `main`, no PR, no approval. Promotion,
  retirement, and hardening beads — anything touching
  `template-fragments/`, `pack.toml`, `tools/`, `doctor/` — stay `mr` with
  human review. This is a deliberate exception to the pack's
  pin-agent-work-to-the-gated-path stance (docs/architecture.md, "How a
  bead finally lands"), and it is defensible on exactly one ground: ledger
  files are *provably inert* — injected into no prompt, referenced by no
  fragment — and `check-learnings-ledger` makes that inertness a standing
  machine-checked invariant rather than a promise. Review load: ~1
  promotion/retirement PR a week, each one a real decision ("should this
  bind every future agent?") arriving with its evidence list attached.
  Friction lands only where judgment lives.
- **(c) Weekly learning-digest PR.** The curator batches the week's ledger
  churn + promotions into one PR. One review event/week, but it mixes inert
  hunks with behavior-changing hunks, partial rejection means hand-editing
  the batch, and doc-keeper already tried and dropped batching for exactly
  this rejection-resume cost (brief §3, the retired rolling-cycle). Only
  worth revisiting if (b)'s promotion PRs somehow multiply.

Recommendation: **(b)**, degrading to (a) by flipping one metadata default
in the audit formula if the direct-path exception proves uncomfortable.

## 6. Honest weaknesses

- **Latency of learning.** Feedback → candidate (≤24h) → threshold
  (days–weeks by design) → promotion PR review (operator-paced) → and, in
  this dev-mode rig, prompts reach agents only after a pack rebuild
  (`make install`, mechanik "Pack Maintenance") and next spawn. The same
  mistake recurs for days while its lesson is in flight. The anti-gospel
  threshold and the learning latency are the *same dial*; you cannot turn
  one without the other.
- **Git is a poor counter-store.** Evidence counts are frontmatter-list
  appends: two concurrent appends to one lesson conflict at refinery
  rebase (serialized, but retries burn polecat cycles), and dedup is only
  as good as citing the exact comment URL. Fine at ~10 events/week; wrong
  substrate at 100.
- **PR fatigue is reduced, not solved.** Variant (b) still asks for a
  weekly judgment PR forever; a rushed approval there *is* the
  one-reaction-becomes-gospel failure, moved rather than removed.
- **The classifier is LLM judgment.** "Standing feedback vs. one-off
  nitpick" in `mol-feedback-audit` is the same soft gate as the memory
  audit's nature gate; false positives accrete ledger noise that the
  curator must then challenge — the system can generate its own busywork.
- **Token budget vs. signal strength.** The bullet cap keeps prompts lean
  but means a genuinely new strong lesson can be blocked behind
  force-ranking; hardening to lints is the pressure release, and not every
  lesson lints.
- **Pack-wide blast radius.** Fragments ship with the pack: one rig
  operator's taste becomes every importer's doctrine. Per-rig scoping
  would need overlay/patch plumbing this sketch deliberately avoids.
- **Negative evidence is invisible.** Git records occurrences, never the
  thousand PRs where the rule held or the comments that *didn't* happen;
  the challenge audit approximates decay with `review_by`, a blunt tool.
