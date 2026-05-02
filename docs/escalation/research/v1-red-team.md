# V1 Red-Team — Section A & B

## Summary

The candidate set is heavy on rituals that all draw against the same finite reviewer attention budget — B1, B2, B4, B6, B8, B13, B14, B17, B20, B21, B22 each demand human authorship or judgment per task or per cycle. T1+A2 say attention is non-restartable; the practice list spends it like it's free. The biggest structural problems: (1) selection-criteria practices (B1, B26) silently assume the human can articulate weights *before* seeing candidates, which contradicts P3's recognition-over-reading premise; (2) several "metric" practices (B10 kill rate, B16 innovation accounting, B23 calibration) lack the corrective action that closes the loop, which is the exact failure mode X2 names; (3) the Toyota-Kata coach-apprentice frame (A4, B21) is a load-bearing borrowed metaphor that the source disanalogy breaks — a Toyota apprentice retains learning across cycles; an LLM agent does not, which makes the "curriculum" a category error unless paired with B5 externalize-state and B15 closure-as-merged-artifact. Many candidates are redundant overlays on existing tenets/practices (B3 is P5 + P3 with a name; A8 is the same; B5 is G3 restated). My strongest recommendation is to cut roughly a third — collapse the SBCE/contact-sheet/spread cluster, drop the metrics that have no corrective, and explicitly name attention budget as a constraint that practices must price.

## A. Refinements — red-team

**A1 — "zero escalations as failure mode."** Andon pull-rate is a *count of stops on a line of known cycle time*. Software work isn't cycle-paced, and tasks vary by orders of magnitude. Counting escalations across a heterogeneous task stream is a denominator problem dressed as a signal. The Toyota disanalogy (X2): a stopped Toyota line is unambiguously a defect-in-progress; a not-escalating agent could mean (a) trivial work, (b) hidden defects, *or* (c) the gates in P1 working as designed — which is the goal of G1. A1 risks creating a perverse incentive to escalate for hygiene, defeating P1.

**A2 — "non-restartable" attention.** Strong, but the phrasing creates a subtle error: human attention is partly restartable (sleep, weekend, context-switch) — the real claim is that *within a session* a depleted reviewer can't be reset by retry, and *historical* attention can't be re-spent. Tighten to "not restartable on demand" or the practice will be argued away by anyone who points out humans rest.

**A4 — coach-apprentice frame.** The disanalogy is severe and unflagged. Rother's apprentice has continuous memory; an LLM session does not. The "curriculum" that B21 implies is not retained by the agent across cycles unless externalized (B5, B15). Without that pairing, A4 becomes a metaphor that flatters humans and does not change behavior. Also overlaps with G2 ("equip the human") and T3 ("the pack learns") — the question is whether *the agent* learns or *the pack* (skills, gates, fewshots) learns. A4 conflates them.

**A5 — shape vs meaning defects.** The cleanest refinement in the set, but the binary is too clean. Real cases sit on a spectrum: a type-correct function that silently swallows an exception is a shape-pass / meaning-fail that current gates won't catch and humans will skim past. A5 needs a third category or an explicit "ambiguous — escalate" default, otherwise it inherits jidoka's blind spot it claims to solve.

**A6 — bidirectional contract.** Subsumes P2 rather than refining it. If the stronger phrasing wins, P2 should be rewritten not annotated. Also, "override cost is bounded" is aspirational unless paired with B3 (rendered alternatives) — without rendered candidates, counter-pick is *not* cheap.

**A8 — render-first.** Redundant with B3 (contact-sheet rendering). Pick one. A8 as a sub-rule on P5 is lighter weight and more durable; B3 as a standalone practice is more visible. Don't keep both.

**A9 — lineage labels.** Redundant with B12 (same idea, same source). Merge.

**A10 — "restartable" in premise.** Good, but it commits the foundation to R4's framing before R4 is shown to be the dominant lens. R1 and R3's framing ("attention is finite *and* job-shaped") might be sharper. Don't lock the premise to one source's vocabulary this early.

## B. New practices — red-team

**B1 — pre-commit selection criteria.** The deepest design tension in the set. P3 says recognition beats reading because humans don't know what they want until they see it; B1 says weight your criteria before you see anything. Pugh matrices worked in physical product design where the criteria (weight, cost, manufacturability) are stable and externally given. Software UX criteria are often discovered *during* candidate review. B1 will either degrade to ritual ("usability: 5, performance: 3") or actively suppress the discovery P3 is built for. Edge case: a reviewer who pre-commits to "performance > readability" and then sees a 10x readability win for 5% performance loss has to choose between contract violation and lost insight. Co-practice missing: a "criteria amend" ritual that's cheap and visible.

**B2 — two-pass review.** Subsumes P1 + adds a procedural shape. The split (technical reject vs judgment) is just A5 (shape vs meaning) with different vocabulary. Keeping both makes the pack repeat itself. Also: "single keystroke + optional note" assumes a UI surface that doesn't exist yet — the practice is committing to tooling that's parked.

**B3 — contact-sheet rendering.** Redundant with A8 and P5. Pick one home. Also: the photography disanalogy is strong — a photo contact sheet shows N variants of *the same scene at the same moment*; AI candidates often differ in what they're solving, not just how. Rendering N solutions to subtly different problems on a grid invites apples-to-oranges selection. B26 (spread requirement) tries to fix this but doesn't address the cross-axis problem.

**B4 — hypothesis-first prompting.** Strong in principle, but the artifact (`hypothesis.md` per task) is exactly the bureaucracy that burns reviewer attention upfront. For a 30-minute task, a hypothesis doc is overhead; for a 3-day task, it's essential. B4 needs a size threshold or it becomes ritual. Also overlaps with B8 (pre-PR consensus) — both are "write the intent before the work."

**B5 — externalize state.** Redundant with G3 (decisions live in artifacts). The novelty is "the artifact *is* the recovery state," but G3 already implies durability. Keep B5 only if it commits to a specific artifact contract (branch + plan doc + scratchpad), otherwise it's restating the goal.

**B6 — andon for agents.** The trigger list ("ambiguous spec, conflicting evidence, irreversible action…") is the right shape but inherits A1's problem: pull-rate as a health metric assumes a denominator. Also: "rewarded, not penalized" is a culture claim with no mechanism. Without a concrete reward signal (gate update? skill credit? leaderboard?), this fails like every "blameless" exhortation does in practice.

**B7 — poka-yoke first, prompt last.** Strong and underspecified. Missing co-practice: who decides a postmortem yields a structural control vs a prompt fix? Without a forcing function, the cheap path (edit the prompt) wins. Pair with B15 (closure-as-merged-artifact) and require the artifact be a config/code change, not a prompt diff.

**B8 — pre-PR consensus.** Inverts the cheap-iteration premise. A 2,000-line PR with circulated intent doc is cheaper to *generate* than to *review* — B8 trades agent cost (free) for human cost (scarce) at exactly the wrong end. Nemawashi worked at Toyota because consensus *prevented* expensive rework; in AI-dev, rework is cheap. The practice is solving a problem the cost structure already solved. Likely a candidate to cut or scope to irreversible/cross-team work only.

**B9 — set-based candidate carrying.** Conflicts with B1: if criteria are pre-committed, the set should collapse fast, not be carried. SBCE worked at Toyota because physical prototypes had long lead times and parallel exploration *saved* calendar; in AI-dev, generation is instant, so "carry 3+ candidates" mostly means "make the reviewer compare 3+ things." Burns attention (T1/X3) for diminishing returns.

**B10 — kill rate as health metric.** Classic metric-without-corrective. What does "too low" trigger? A skill update? A spec rewrite? A reviewer rotation? The number is observation theater unless it's wired to an action. Also, picture editors had a *known* base rate from decades of practice; AI-dev doesn't — anchoring on "1-in-30" is borrowing a number whose generative process doesn't transfer.

**B11 — diff-of-diffs.** Tooling, not practice. Park until the rendering surface exists, otherwise it's a wish.

**B13 — pre-mortem.** Redundant with B4 (hypothesis includes "what would change our mind") and partly with B6 (escalate on ambiguity). Keep one of {B4, B13}.

**B14 — per-event AAR + COE sweep.** Strong shape but the cadence is unguarded. "After every surprising escalation outcome" is a reviewer-attention sink. Surprising-to-whom? A single false-negative will trigger an AAR by some definition every day. Needs a budget (e.g., "≤1 AAR/week or escalate the cadence itself").

**B15 — closure-as-merged-artifact.** Strong and load-bearing. Probably the single most important practice in the set because it's what makes T3 actually drive learning. Don't cut.

**B16 — innovation accounting.** Metric without corrective (same as B10). Also: "hypotheses resolved" is hard to count without B4-style hypothesis docs everywhere — circular dependency.

**B17 — quarterly meta-review.** Cadence without a forcing function. Quarterly reviews die in every org that doesn't tie them to budget/headcount. In a personal/small-team pack, they will silently lapse. Either make it lighter (monthly skim) or attach to an existing rhythm.

**B18 — held-out adversarial eval.** Implementation-heavy. Requires labeled past failures, eval harness, scoring criteria. Probably right but is a project, not a practice. Park as a skill/artifact (Section C).

**B19 — reversibility budget / quarantine zones.** Strong. Cleanest direct port from R4. Co-practice missing: who classifies an action as irreversible? Default-conservative classification is the only safe default and should be named.

**B20 — senior-reader one-hard-question.** Assumes a senior reader exists and has spare attention. In the personal/small-team setting, this is the same person being protected by T1. The practice eats the resource it claims to optimize. Useful in larger orgs; misfit here without scoping.

**B21 — coach-apprentice cadence.** See A4. The disanalogy is severe — daily coaching of an entity that doesn't retain anything between sessions is theater unless the coaching output is encoded in skills/gates/fewshots (B15). Should be merged into B15's loop, not stand alone.

**B22 — agent as witness, human as author.** Strong and underrated. No critique; this is exactly what X2 implies.

**B23 — confidence calibration tracking.** Metric without corrective. Also assumes confidence tags are stable across model versions, which they aren't — recalibration on every model swap is a hidden cost not surfaced.

**B24 — pre-composition discipline.** Restates premise of B1/B4 from the opposite direction ("don't iterate, think first"). The pack risks saying both "iterate cheaply" (B3, B9) and "don't iterate, design first" (B24) without naming the boundary. Needs a decision rule, not just opposite exhortations.

**B25 — don't A/B architecture.** Probably correct but too narrow to be a top-level practice. Better as guidance under P2 or B1.

**B26 — spread requirement.** Tries to fix B3's apples-to-oranges problem but creates a new one: who validates that 3 candidates are meaningfully spread? If the agent self-certifies, it's the same blind spot X2 names. Co-practice missing.

## Cross-cutting concerns

**C1. Attention-budget overdraft.** A2 sharpens T1 to "non-restartable," then Section B spends that budget without a ledger. B1 (write criteria), B4 (write hypothesis), B6 (handle escalations), B8 (review intent doc), B13 (pre-mortem), B14 (AAR per event), B17 (quarterly review), B20 (one hard question), B21 (daily coaching), B22 (author postmortem), B24 (pre-composition design) — every one is a human-authored artifact. The pack needs an explicit "attention budget per task class" or it will silently regress to "agent does it all and human rubber-stamps," which is the failure mode B10 names. *Recommendation: add a meta-practice — every new practice must price its attention claim.*

**C2. Metric-without-corrective cluster.** B10, B16, B23, partly B6 and A1. Each proposes a number to track without naming the action the number triggers. X2 warns that semantic blind spots aren't caught by metrics; these practices add metrics without closing the loop. *Recommendation: every metric practice must name (a) the threshold, (b) the corrective, (c) who acts on it.*

**C3. Selection-criteria paradox.** B1 (pre-commit weights), B26 (spread), B9 (carry candidates), B24 (pre-compose) all assume the human can specify the decision frame *before* seeing candidates. P3 says recognition is the point because they often can't. The pack hasn't reconciled X1's "framing + selection" with P3's "judgment-on-sight." *Recommendation: distinguish task classes where pre-commit works (perf, cost, measurable axes) from where it doesn't (UX, code-shape, ambiguous intent) and apply B1 only to the former.*

**C4. Rituals borrowed from systems with retention.** A4, B14, B17, B21 all assume cumulative learning by a coachable entity. The agent doesn't retain across sessions; the *pack* (skills, gates, fewshots, evals) does. Every "coaching"/"review" practice must terminate in a B15-style artifact diff or it's pantomime. *Recommendation: collapse A4/B21 into B15 as a sub-rule: "coaching outputs are skill/gate diffs, or they didn't happen."*

**C5. Disanalogies stacked unflagged.** Toyota's apprentice retains; AI agent doesn't. Photo editors have a stable base rate; AI-dev doesn't. Toyota's andon assumes uniform cycle time; software doesn't. Several practices borrow vocabulary (kata, andon, contact sheet, kaizen) without flagging the structural break. The pack should either explicitly name the disanalogy at each borrow site or use AI-native naming.

**C6. Tooling-as-practice confusion.** B11 (diff-of-diffs), B18 (held-out eval), parts of B3 are tools/artifacts, not behaviors. Conflating practices with tooling delays both. Move to Section C/E.

## Recommendations for cuts/merges

**Cut outright:**
- **A1** (zero escalations as failure mode) — perverse incentive, denominator problem, fights G1.
- **B8** (pre-PR consensus) — solves a problem the cost structure already solved; trades cheap (agent rework) for scarce (reviewer attention).
- **B10** (kill rate) — borrowed base rate without generative process; metric without corrective.
- **B11** (diff-of-diffs) — tooling, not practice. Move to Section C/E.
- **B16** (innovation accounting) — circular dependency on B4, no corrective.
- **B17** (quarterly meta-review) — will lapse; absorb into B14 cadence.
- **B23** (confidence calibration) — metric without corrective; recalibration cost hidden.
- **B25** (don't A/B architecture) — too narrow; demote to a bullet under P2 or B1.

**Merge:**
- **A8 + B3** → keep one render-first home. Prefer A8 as a sub-rule on P5; drop B3 as standalone.
- **A9 + B12** → identical content; merge into B12 with A9 deleted.
- **A4 + B21 + B15** → coaching only counts when it terminates in a merged artifact. Collapse the coaching frame into B15's closure rule.
- **B2 + A5** → same shape/meaning split with different vocabulary. Keep A5's framing on P1; drop B2 or rewrite as A5's operational form.
- **B4 + B13** → hypothesis doc already implies pre-mortem. Keep B4, fold B13's "imagine the outage" prompt into B4's template.
- **B5 + G3** → B5 keeps only if it commits to a specific artifact contract; otherwise it restates G3.
- **B24 + B1** → both want pre-generation rigor. B24 is the philosophy, B1 is the mechanism. Combine.

**Keep, but add missing co-practice:**
- **B1**: amend-criteria ritual to handle P3's discovery case.
- **B6**: concrete reward signal (skill credit / gate update count); without it, "rewarded not penalized" is exhortation.
- **B7**: forcing function that prefers structural fixes over prompt edits at closure (tie to B15).
- **B19**: default-conservative classification rule for irreversibility.
- **B20**: scope to multi-person pack only; in solo/small settings, the senior reader *is* the protected resource.
- **B26**: who validates spread? Without a check, agent self-certifies and inherits X2's blind spot.

**Add (gap):**
- An explicit **attention-budget meta-practice**: every practice prices its claim against T1, and the pack rejects any practice whose human cost is unbounded per task. This is the missing co-practice for the entire B-cluster.
- A **disanalogy-flagging discipline**: every borrowed pattern (kata, andon, contact sheet, COE, nemawashi) carries a one-line "where the source breaks" note inline, not buried in research logs.

**Strongest keepers, no changes needed:** A2 (with the "on demand" tightening), A5, A6 (as a P2 rewrite), B15, B19 (with co-practice), B22.
