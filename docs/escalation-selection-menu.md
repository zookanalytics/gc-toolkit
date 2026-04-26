# Escalation Selection Menu — Contact Sheet for Curation

> **You are the editor. The candidates are laid out for sweep. Each cluster
> below is a decision; each decision shows options, my opinion, and the
> downstream effects of picking each. Pick what to discuss; defer the rest.**

This doc is the contact sheet over the work in
`docs/escalation-ideation.md` and the five research reports
(`docs/research/r1-r5-*.md`) plus four validation reports
(`docs/research/v1-v4-*.md`). The ideation doc is the full inventory
(~150 candidates); this menu surfaces the load-bearing decisions and
my lean on each, so your job is selection, not generation.

## Reading order

The menu is ordered by *blast radius*: foundation-level decisions first
(they change what the pack stands for), then practice-level clusters
(they change what the pack does), then skills (what ships first), then
quick-ratifies (V1 cuts/merges), then deferrals.

You don't have to read top-to-bottom. Each cluster is self-contained.
Skip any cluster whose lean you trust me on; deepen any whose lean you
want to push back on.

## Status

- **Ideation:** complete. Six sections (A-H), three meta sections (M,
  I, J). All four validation agents returned.
- **Cuts/merges proposed by V1:** listed below for ratification.
- **Strongest gaps:** H1 (M4 grounding), H4 (spread index), H5 (eval
  overfitting), H7 (multi-agent coordination), H12 (T4 candidate).
- **Parked:** posture metaphor (D), pack ↔ agent roster integration
  (H15).

---

## Clusters

### Cluster 1 — Foundation decisions

These change what's in v0. Highest blast radius.

**1.1. Add `M1` (every practice prices its attention claim) to the
foundation.** *(V1 C1)*

- A. Add as a foundation-level rule above tenets (a "discipline" block
  between Premise and Goals).
- B. Add as a 7th practice in v0.
- C. Defer; surface only when a practice violates it.
- *Lean: A.* M1 governs how the pack itself is built — it's structural,
  not operational. Foundation placement makes it visible whenever a
  practice is added. V1 caught the pack already overdrafting attention
  in Section B; without M1, that pattern repeats.
- *Effects:* every existing practice gets a one-line "attention claim"
  field. Some Section-B candidates may not survive that field.

**1.2. Sharpen T1 with "non-restartable on demand."** *(A2 + V1 caveat)*

- A. Sharpen as A2 proposed: "Agent tokens, compute, retries, and
  self-critique are free and restartable. Human attention is finite
  and not restartable on demand."
- B. Keep T1 as-is.
- C. Reframe T1 entirely around the cost flip (V3 J4 — the cost flip
  may be the single biggest economic shift, deserving foundation
  status of its own).
- *Lean: A.* "On demand" addresses V1's correction (humans rest, can
  recover over weekends). The restart-asymmetry phrasing connects T1
  cleanly to T2 (the human owns the clock) and to the Premise's
  "agent labor near-free."
- *Effects:* small wording change; downstream M1 makes more sense.

**1.3. Adopt "borrow-as-hypothesis" in Premise.** *(V3 J6 + M3)*

- A. Strengthen M3: every borrowed pattern carries a *falsification
  test* (a specific AI failure mode that would invalidate the borrow),
  not just a disanalogy note.
- B. Bake into Premise text directly.
- C. Keep M3 as named in ideation; defer falsification-test layer.
- *Lean: A.* M3 is the right home; sharpening it to "disanalogy +
  falsification test" makes it operational. V3's whole point is that
  the pack risks treating borrowed disciplines as priors-to-relax
  instead of hypotheses-to-falsify.
- *Effects:* every borrow-site (kata, andon, A3, COE, contact sheet,
  nemawashi) needs two annotations: where the source breaks + how
  we'd know we got it wrong.

**1.4. Treat "agent context is also scarce" (I4) as T4, T1-companion,
or practice?**

- A. Promote to T4. Tenets stay small but this is genuinely sibling-
  shaped to T1.
- B. Land as a practice rooted in T1.
- C. Defer until first use generates patterns.
- *Lean: B for now.* The user's prior constraint on tenet count is
  durable; context-scarcity can land cleanly as a practice ("the main
  thread sees summaries, not transcripts; verbose work happens in
  sub-agents"). If first use shows it's foundational, promote later.
- *Effects:* if B, write it as a practice (P7?) under T1; if A, the
  three-tenet symmetry breaks and the composition note changes.

**1.5. Reshape "escalation" from single verb to typed event.** *(I1
Notify/Question/Review)*

- A. Adopt as a P1 sub-rule: every escalation declares its class
  (Notify / Question / Review).
- B. Land as a standalone practice.
- C. Defer to skill-level (in `skills/escalate/`).
- *Lean: A.* The typology is foundational shape, not implementation.
  Each class has a different attention price (M1) and a different
  routing rule. Burying it in a skill means the pack's vocabulary
  for "escalate" remains undifferentiated, which V2 named as a real
  gap.
- *Effects:* P1 grows by one sentence; the eventual escalate skill
  (C3) inherits the typology.

---

### Cluster 2 — Safety surface

The pack's stance on irreversible actions and dangerous compositions.
V2 + V4 surfaced three patterns that compose into one safety surface;
the question is whether to adopt them as a unit or piecewise.

**2.1. Adopt the safety surface as a single composite practice.**
*(I5 lethal trifecta + I7 typed approval + I12 structural reversibility)*

- A. Single composite practice: "the pack's safety surface is the
  composition of (a) lethal-trifecta gate at design time, (b) typed
  per-tool approval class on every tool, (c) structural reversibility
  surface for irreversible action classes."
- B. Three separate practices, adopted independently.
- C. Adopt I5 only; I7 and I12 are tooling, not practice.
- D. Defer all three until a real incident motivates each.
- *Lean: A.* They compose: I12 (staged surface for irreversibles)
  needs I7 (typed approval class to know what's irreversible) needs
  I5 (lethal-trifecta gate to refuse the dangerous-by-composition
  cases). Adopting them piecewise lets one slip and silently breaks
  the others.
- *Effects:* the safety surface becomes a single named practice the
  harness either implements or doesn't. New tools must declare their
  approval class; new agent designs must declare which trifecta leg
  they sever; irreversible classes only reachable through staged
  surface.

**2.2. Reversibility classification default.** *(M6)*

- A. Default-conservative: when in doubt, classify as irreversible.
- B. Default-permissive: only what's documented as irreversible is
  treated as such.
- C. Per-domain default (e.g., file ops permissive, API ops
  conservative).
- *Lean: A.* The reverse default fails silently and catastrophically.
  V1 caught this as a missing co-practice for B19; M6 was added.
- *Effects:* harness gates default to "blocked until classified" for
  any new tool.

**2.3. Snapshot-as-undo (I6) for live-environment agents.**

- A. Adopt as part of the safety surface.
- B. Adopt only for agents that touch real-world state outside the
  repo (databases, deployed services, cloud resources).
- C. Defer until the pack has a live-environment agent to apply it
  to.
- *Lean: B.* Snapshot-based undo is heavyweight for repo-only agents
  (git already handles it). For agents that mutate world state, the
  recovery unit is genuinely the world, not the commit. Scope to
  where it's load-bearing.
- *Effects:* harness-side; doesn't affect the foundation but does
  affect skill design for any harness that exposes world-mutating
  tools.

---

### Cluster 3 — Learning loop

T3 says the pack learns; M5 says coaching only counts when it
terminates in a merged artifact; B15 names that artifact. The
question is what the artifact actually contains, what the cadence
looks like, and what makes the loop close.

**3.1. Closure unit: commit hash, eval diff, or both?** *(B15 vs I3)*

- A. Commit hash sufficient (B15 as-is).
- B. Eval diff required for *every* closed AAR/COE.
- C. Eval diff required for closures that fix *semantic* defects
  (A5 meaning-defects); commit hash sufficient for shape-defects.
- D. Eval diff required for closures that update a *skill or
  prompt*; commit hash sufficient for harness/config diffs.
- *Lean: C.* B15 alone is too lax (V1 would catch the same loophole
  again — "we updated the prompt and ticked the box"). Universal
  eval diff is too heavy for trivial closures (G7 anti-pattern in
  practice). The semantic/shape split (A5) is already in the pack;
  it's the natural axis. D is also defensible; pick if the pack
  scopes mostly to skill-level work.
- *Effects:* AAR/COE template carries a "closure type" field;
  semantic-defect closures must reference an eval-diff PR.

**3.2. Cadence shape: AAR + COE batch, daily kata, or both?** *(B14
+ B21 + V1 M5)*

- A. AAR + weekly COE batch only (F3 + F6).
- B. Daily Toyota-Kata-style coach session (F11) on top.
- C. Triggered only — anomaly-driven (F9), no scheduled cadence.
- *Lean: A.* Daily kata is theatre without retention (V1 C4); F11
  triggers from anomalies in F8/F9, doesn't run as a scheduled rhythm.
  AAR catches per-event signal; COE batch finds patterns across the
  AARs. Both have priced attention budgets in F.
- *Effects:* the pack ships with `skills/aar/` and `skills/coe/` (C4,
  C5); kata is a triggered protocol, not a calendar entry.

**3.3. Eval lifecycle.** *(I3 + I11 + B18)*

- A. Three-layer: (1) closure-time eval add (I3), (2) per-skill cross-
  model regression (I11), (3) periodic held-out adversarial sweep
  (B18).
- B. Layer 1 only; the other two are aspirational.
- C. Layer 1 + 2; defer 3.
- *Lean: C with 3 as a milestone.* Layer 1 is the immediate ask
  (closes the loop). Layer 2 is the model-drift safety (V4 N2 is
  load-bearing — without it, every model upgrade is a silent
  regression). Layer 3 is real but is engineering project work; mark
  as a target, not a v1 deliverable.
- *Effects:* every skill ships with `evals/` directory in its skill
  package. Cross-model run wires into a CI gate. B18 lands when
  enough closed AARs/COEs exist to populate the held-out set.

**3.4. Reviewer-skill cultivation.** *(I8 + H14)*

- A. Adopt — track per-reviewer accuracy as input to coach cadence.
- B. Adopt as opt-in — reviewers see their own data; nobody else.
- C. Defer — dignity / surveillance concerns dominate.
- *Lean: B.* I8 is correct (Vaccaro: human-AI teams underperform
  without practiced humans), but tracking accuracy as a metric
  visible to others weaponizes it. Self-visible only is the right
  default; can open up later if culture sustains it.
- *Effects:* the trust ledger (I14) is per-skill *and* per-reviewer;
  the per-reviewer view is private to that reviewer.

---

### Cluster 4 — Selection ritual

The selection layer is where most agent-output meets human judgment.
V1 caught a hard tension: B1 (pre-commit weights) silently contradicts
P3 (recognition over reading). M4 named the resolution. This cluster
makes M4 operational.

**4.1. Pre-commit-vs-discovery decision rule.** *(M4 / H1 grounding)*

- A. Apply pre-commit weights (B1) only to *measurable axes* — perf,
  cost, diff size, dependency footprint, test coverage. Recognition-
  on-sight (P3) for *ambiguous axes* — UX, code shape, intent
  clarity. Require an "amend criteria" ritual when candidates surface
  a dimension nobody named.
- B. Always pre-commit; document the contradiction with P3 explicitly
  and let the user override per task.
- C. Always discover; treat B1 as guidance, not requirement.
- *Lean: A.* This is the V1 resolution. The "amend criteria" ritual
  is the missing co-practice — without it, A degrades to B's
  contradiction.
- *Effects:* `skills/selection/` (C2) ships with a measurable-axes
  weights template *and* an amend-on-discovery sub-flow.

**4.2. Contact-sheet rendering: where does it live?** *(A8 / B3 / V1
merge proposal)*

- A. Render-first as a sub-rule under P5 (A8). B3 is folded in.
- B. Standalone practice (B3 as-is). A8 is folded in.
- C. Both — P5 sub-rule for the principle, standalone practice for
  the procedure.
- *Lean: A.* V1's recommendation. Lighter weight, more durable. The
  procedure (grid, sweep, diff carousel, behavior screenshots) is
  better described in `skills/selection/` than as a top-level
  practice.
- *Effects:* P5 grows by one sentence; B3 deletes; the contact-sheet
  procedure lives in C2's template.

**4.3. Spread requirement: how to validate?** *(B26 / E11 / H4)*

- A. Add a spread-check step (tool-based: embedding similarity, LLM
  judge) before the contact sheet renders. Refuse to render
  homogeneous sets.
- B. Procedural — agent self-certifies, with manual review.
- C. Defer until tooling exists.
- *Lean: A as target; B as v1 stopgap.* V1 caught that A delegates
  to a tool that doesn't exist; B inherits X2's blind spot (agent
  self-adjudicating). The honest play is "B for now, A as
  milestone, with the gap explicitly named."
- *Effects:* selection skill notes the gap. A second-round agent
  could research existing spread/diversity tooling.

---

### Cluster 5 — Autonomy model

The pack's stance on what the agent is allowed to do without a human
checkpoint. I2 (per-task slider) and I13 (harness-enforced
backpressure) are the two halves.

**5.1. Adopt the autonomy slider + backpressure as a unit.**

- A. Both: I2 (user-facing dial: suggest/propose/act-with-approval/
  act-then-report/ambient) + I13 (harness floor: budget for steps,
  files, time, dollars; backpressure on review queue depth).
- B. I2 only — let humans set autonomy without harness enforcement.
- C. I13 only — single global limit, no per-task setting.
- *Lean: A.* I2 without I13 is theatre (set "ambient," agent runs
  forever). I13 without I2 is monolithic and forces constant
  re-tuning.
- *Effects:* every agent invocation requires an autonomy declaration;
  the harness reads the declaration plus the budget; the human's
  experience changes with the slider position.

**5.2. Notify budget for ambient agents.** *(I9)*

- A. Adopt — daily/weekly budget per agent, overflow batched into
  digest.
- B. Defer until ambient agents are in scope.
- C. Skip — ambient is not the pack's primary mode.
- *Lean: B.* The pack's primary mode is interactive coding; ambient
  agents are a likely future mode. Land I9 when ambient lands;
  meanwhile, name the gap so it doesn't regress.
- *Effects:* I9 sits in the parked-but-named bucket.

---

### Cluster 6 — Posture / metaphor

The user previously parked this (surgeon/scrub-nurse rejected). V3's
peer-not-tool framing is new evidence that subordinate-flavored
metaphors (apprentice, scrub-nurse, RA) silently assume the producer
has no opinion about its own oversight, which is wrong for partial-
autonomy agents.

**6.1. Pick a posture stance.**

- A. **Single metaphor, peer-flavored.** D1 chief-of-staff or D2 co-
  pilot. Both peer-flavored, both capture opinion-with-options and
  artifact-mediated work. D1 is stronger on attention-as-currency
  and durable-artifacts; D2 is stronger on live-authority and
  challenge-and-verify.
- B. **Roster of metaphors keyed to context.** D7. Different work
  uses different relationships: ambient → chief of staff; live
  coding → co-pilot; high-volume generation → editor. Lower
  elegance, higher accuracy.
- C. **No metaphor.** D8. The relationship is what the practices
  encode; reaching for analogy is a comfort move.
- D. **Defer.** Park as the user did before; let first use surface
  what the metaphor needs to *do*.
- *Lean: D for now, with B as the likely-future answer.* The pack's
  practices already encode the relationship clearly — opinion +
  options + artifact + slider + audit. Naming a single metaphor too
  early risks overfitting to one mode of work; naming a roster too
  early ossifies categories. Defer; revisit after first real use
  generates the patterns the metaphor needs to capture.
- *Effects:* Section D stays parked; no posture statement in v1; come
  back when there's signal.

**6.2. The peer-vs-tool framing.** *(V3 J5)*

- A. Adopt explicitly — Premise gets a sentence: "the agent is a
  partial-autonomy peer, not a tool, and may have opinions about
  its own oversight."
- B. Don't adopt explicitly — the practices already imply peer-
  shaped behavior (P2 opinion alongside options, B22 agent as
  witness).
- C. Stay agnostic — different deployments will treat the agent
  differently.
- *Lean: B.* The peer framing is implicit in P2 and the safety
  surface. Stating it explicitly invites debate that doesn't change
  practice. Let the practices do the work; let users land their
  own posture.
- *Effects:* none structural; the discussion stays in research notes.

---

### Cluster 7 — First skills to write

The pack-v2 schema lives at `skills/<name>/SKILL.md`. Ideation
Section C surfaced 17 skill candidates. Question: which 3-5 ship
first?

**7.1. First-five skill set.**

- A. **Foundation set:** `hypothesis/` (C1), `selection/` (C2),
  `escalate/` (C3), `aar/` (C4), `coe/` (C5). Covers intent,
  selection, escalation, per-event learning, periodic learning. Each
  has a clear when-to-invoke and clear artifact shape.
- B. **Minimum viable:** `escalate/` + `aar/` only. The pack runs;
  everything else is opt-in.
- C. **Safety-first:** `escalate/`, `coe/`, plus a new
  `safety-surface/` skill that operationalizes Cluster 2.
- D. **Selection-first:** `selection/`, `hypothesis/`, plus the
  rendering primitives.
- *Lean: A.* Five is a coherent set covering the load-bearing axes
  (intent, choose, raise, learn-fast, learn-slow). C is also strong
  if safety is the immediate priority; D is strong if selection is
  the most-used flow.
- *Effects:* the next ideation→implementation step is writing five
  SKILL.md files with worked examples. H8 (skill schema mapping)
  becomes the immediate gating question.

**7.2. Skill template / schema.** *(H8)*

- A. Adopt one canonical structure (front-matter + sections + hooks)
  for all skills. Worked example first; rest follow the pattern.
- B. Per-skill structure — let each skill find its shape.
- C. Defer until the first three skills exist; refactor to common
  structure if patterns emerge.
- *Lean: A with a worked example.* V1's "lean theater" critique
  (G1) applies to skill formats too — without a discipline, every
  skill drifts to its author's idiosyncrasies. Pick one shape, write
  one excellent example, copy.
- *Effects:* a `skills/_template/` example becomes the next
  artifact. Per-skill drift gets caught at review.

**7.3. Skill ↔ existing agent roster (concierge / architect /
mechanik).** *(H15)*

- A. Skills are agent-agnostic; agents pull skills as needed.
- B. Skills are pinned to specific agent roles.
- C. Some of each — foundational skills (escalate, AAR) are
  agent-agnostic; specialized skills (e.g., `architect/`) are role-
  pinned.
- *Lean: C.* Foundational skills are about how the pack relates to
  the human; they're cross-cutting. Role-specific skills exist for
  domain reasons. Mark the distinction in front-matter.
- *Effects:* skill front-matter gets an `applies_to:` field; some
  values are `[*]`, others are `[architect]`.

## V1 cuts/merges to ratify

V1 proposed specific candidates to drop or fold together. These are
quick yes/no decisions; my lean follows V1 in most cases. Walk
through and override anywhere you disagree.

### Cuts (drop the candidate entirely)

| ID | Candidate | V1 reason | My lean |
|---|---|---|---|
| A1 | Zero-escalations-as-failure | Denominator problem; perverse incentive vs G1 | Cut, keep idea in E1 (pull rate metric) |
| B8 | Pre-PR consensus (nemawashi) | Trades cheap (agent rework) for scarce (reviewer attention) | Cut, scope might survive for irreversible/cross-team only |
| B10 | Kill rate as health metric | Borrowed base rate without generative process | Replaced by E2 (per-class baseline) |
| B11 | Diff-of-diffs | Tooling, not practice | Cut from B; live in C/E if/when tooling exists |
| B16 | Innovation accounting | Circular dependency on B4; metric without corrective | Cut for now; revisit if B4 lands broadly |
| B17 | Quarterly meta-review | Will lapse without forcing function | Fold into F8 monthly cadence |
| B23 | Confidence calibration | Metric without corrective | Replaced by I14 trust ledger |
| B25 | Don't A/B architecture | Too narrow for top-level practice | Demote to bullet under P2 / B1 |

### Merges (fold A into B)

| Source | Target | Rationale |
|---|---|---|
| A8 | P5 sub-rule + drop B3 | Render-first as one home, not two |
| A9 | B12 | Identical content |
| A4 + B21 | B15 (closure rule) | Coaching only counts if it produces an artifact diff |
| B2 | A5 | Same shape/meaning split, different vocabulary |
| B13 | B4 | Pre-mortem fits inside hypothesis doc template |
| B5 | G3 (with artifact contract) | B5 only survives as a specific contract |
| B24 | B1 | Pre-composition is the philosophy; B1 is the mechanism |

### Keepers no change

A2 (with "on demand" tightening), A5, A6, B15, B19 (with M6 default-
conservative), B22.

### Strengthens

| Item | Strengthening | Source |
|---|---|---|
| B7 (poka-yoke first) | Pair with B15: closure must be config/code change, not prompt edit | V1 |
| B19 (reversibility budget) | Add M6 default-conservative classification | V1 |
| B26 (spread requirement) | Pair with H4 spread-index tooling note | V1 |
| M3 (disanalogy flagging) | Strengthen to "disanalogy + falsification test" | V3 J6 |
| B15 (closure-as-merged-artifact) | Strengthen to "eval diff for semantic-defect closures" | I3, Cluster 3.1 |
| B23 → I14 | Replace metric with calibrated trust ledger | V4 N5 |
| C3 (escalate skill) | Inherits Notify/Question/Review typology from I1 | V2 |
| B6 (andon for agents) | Triggers are typed signatures (I7), not runtime decisions | V2 |


## Deferrals

Items the ideation surfaced but that don't have enough grounding to
land in v1. Each is named so it doesn't regress; first-use signal is
what re-opens them.

| H# | Item | Why deferred | What unblocks it |
|---|---|---|---|
| H1 | M4 decision rule grounding | Resolution named, examples thin | Worked examples from real selection sessions |
| H2 | Senior-reader for solo / small-team | B20 paradox in single-person settings | First few real COEs in the small-team context |
| H3 | Notify/Question/Review in non-ambient | Came from ambient agents; semantics unclear in interactive | Worked examples in interactive coding |
| H4 | Spread-index tooling | Tool doesn't exist | Could be a second-round agent run on diversity-tooling literature |
| H5 | Eval-diff overfitting countermeasures | Real risk per G9 | Second-round agent on eval design (Husain, Yan, OpenAI evals) |
| H6 | Posture metaphor | User has parked once already | First use surfaces what metaphor needs to do |
| H7 | Multi-agent coordination | V4 §1 surveyed but undecided | First multi-agent task |
| H8 | Skill schema mapping | Cluster 7.2 picks the shape; details follow | First skill written to canonical form |
| H9 | Plan-doc vs. existing scratchpads | Per-harness adapter likely | First harness integration |
| H10 | T2 grain (time-of-day, focus) | Speculative without data | First few weeks of actual use |
| H11 | Pack defaults vs. per-project | Premature taxonomy | First two adopting projects |
| H12 | T4 candidate (agent context scarce) | User's tenet-count constraint | Strong signal that the practice form is insufficient |
| H13 | Metaphor / posture / role distinction | Section D conflates them | Same trigger as H6 |
| H14 | Reviewer-skill cultivation without dignity cost | Cluster 3.4 adopts opt-in; details follow | First reviewer-tracking instance |
| H15 | Pack ↔ agent roster integration | Cluster 7.3 picks per-skill `applies_to` | Worked skill examples |
| H16 | Falsification tests for borrows | Cluster 1.3 absorbs | None — adopt with M3 strengthening |

### Likely first second-round agent runs

If you want to deepen a few before deciding: H4 (spread-index tooling
survey) and H5 (eval-diff design) are the two with the highest
leverage and lowest cost. Both can be one-shot research agents.

---

## What I'd do first

If you want a sequence rather than a survey, here's the order I'd
take it in. Each step is a single decision you could make in one
sitting; each unblocks the next.

1. **Cluster 1.1 + 1.2** — adopt M1 (attention-budget meta-rule) and
   the "non-restartable on demand" T1 sharpening. These two changes
   make every other decision honest about cost.
2. **Cluster 1.3** — adopt M3 strengthening to "disanalogy +
   falsification test." Forces every borrowing to declare its
   pathology check.
3. **Cluster 1.5** — add I1 (Notify/Question/Review) typology as P1
   sub-rule. The pack's escalation vocabulary becomes typed.
4. **Cluster 2.1** — adopt the safety surface as a single composite
   practice. Names the harness gates the pack expects.
5. **Cluster 3.1** — closure unit becomes "commit hash + eval diff
   for semantic-defect closures." Closes the learning loop honestly.
6. **Ratify V1 cuts/merges.** Quick walkthrough; everywhere you
   disagree we discuss.
7. **Cluster 7.1 + 7.2** — pick the first-five skill set and write
   the canonical SKILL.md template. This is the bridge from ideation
   to working artifacts.
8. **Defer 6.1 (posture)** unless first use surfaces a need.

Total: 7 decisions to land v1 of the foundation; one open question
(skills) gating real implementation. After that, the H deferrals
become the second-round backlog.
