---
name: Learning-System Exploration — Synthesis
description: Entry point for the 2026-08 learning-system research bundle. Summarizes what the six research threads found, where they converge, where the real decisions are, maps each option against the operator's stated concerns, and proposes a composite direction plus the narrowing questions to settle next.
---

# Learning-System Exploration — Synthesis

**The ask** (operator, 2026-08-10): feedback given on PRs and in discussions —
stale "historical artifact" references, comments that restate the code or copy
constant values, boilerplate comments pasted into inapplicable files — should be
audited, learned from, and folded into the standing prompts future agents run
with, *including removing* guidance that stops earning its place. Stated
concerns: git-only prompts mean a heavy approval cycle; unversioned means no
evolution trail; one strong reaction must not become gospel while repeated
feedback is a strong signal; external tools vs simple-and-local; and when does
learning actually happen.

**The bundle** (all in this directory):

| Doc | Thread |
|---|---|
| [internal-inventory.md](internal-inventory.md) | What exists in the pack today — the prompt surface, the loops by maturity, the signal sources, the gaps, the reusable rails |
| [prior-art.md](prior-art.md) | The field as of 2026-08 — rule files, memory frameworks, self-improving-context research, PR-feedback products; 8 transferable patterns, 5 anti-patterns |
| [option-a-git-native-rulebook.md](option-a-git-native-rulebook.md) | Everything in-repo: `learnings/` ledger + fragment projection, split-trust merge policy |
| [option-b-ledger-distiller.md](option-b-ledger-distiller.md) | Observations as closed-at-creation beads; a weekly distiller promotes into the reviewed prompt surface |
| [option-c-live-memory-git-export.md](option-c-live-memory-git-export.md) | Live fleet-memory files agents read at prime time; git gets snapshots; ratify-or-expire |
| [capture-promotion-pruning.md](capture-promotion-pruning.md) | Storage-agnostic: capture taxonomy, evidence/promotion model, lifecycle state machine, pruning |

## 1. The two facts that anchor everything

**The delivery half of the loop already exists and demonstrably runs.** The
doc-keeper drift audit closes the loop from "the world moved" to "a merged PR"
today (inventory §2.5 cites five merged doc-update PRs in git history). The
change-unit bead → `mol-polecat-work` → refinery → small PR pipeline needs *no
modification* to carry prompt edits. What is missing is entirely on the intake
side: **no durable corpus of feedback, no recurrence detection across PRs, and
an explicit charter exclusion** — `specs/tk-yw3zb.1/central-doc-inventory.md`
§2a rules agent prompts out of doc-keeper's scope and defers to a "separate
maintenance regime" that was never defined. This learning system *is* that
regime.

**The pack already has a complete learning ladder — it's just hand-cranked.**
Lesson → prompt fragment (pack.toml comments citing beads), lesson → doctor
check (12 checks, each citing the bead that paid for it), lesson → deterministic
hook (cycle-recycle: prose that degraded, escalated to a harness hook). Every
rung exists; a human notices the recurrence and files the work. The system to
build is the noticing.

## 2. Where all six threads converged

These showed up independently in the internal inventory, the prior art, all
three option designs, and the cross-cutting model — treat them as settled
unless the operator objects:

1. **Two-tier split: capture is cheap and never touches prompts; promotion is
   rare and reviewed.** Every design lands here. It is also the direct answer
   to "when does learning happen": capture continuously in-flow, distill and
   promote periodically on audit, with an operator fast path for emergencies.
   The approval cycle stops being heavy because approvals only happen where
   judgment lives (~1 promotion/retirement PR a week), not on every
   observation.
2. **Recurrence thresholds, not reaction strength.** One comment = one
   occurrence, however loud. Promotion at ~2–4 independent occurrences
   (distinct PRs/beads, distinct days), scaled to blast radius. Heat buys
   *priority of investigation*, never state change. Operator endorsement
   bypasses thresholds but is permanently marked as a decree, so challenge
   audits re-examine it first. (Prior art: this is exactly the evidence-model
   gap in CodeRabbit/Cursor — the field-wide weakness gc-toolkit can beat.)
3. **Every lesson carries provenance** (PR comment URL, bead id) — the dedup
   key against double-counting, the audit trail, and what makes retirement
   safe ("we know what this was load-bearing for").
4. **Subtraction is structural, not aspirational**: hard caps on the prompt
   surface (adding past the cap must displace something), review-by dates,
   challenge audits that propose retirements, and **hardening as the best
   pruning** — a lesson converted to a doctor check or lint leaves the prompt
   entirely. All three of the motivating feedback examples are substantially
   lintable. (Prior art: Claude Code's 200-line memory cap and "write it as a
   hook instead"; the lint-promotion ladder; ACE's counter-driven pruning.)
5. **Retire ≠ delete.** Retired lessons keep their record (Zep's
   invalidate-with-timestamp; Option A's immune-memory files; the lifecycle's
   `deprecated → retired` with resurrection on recurrence). Cheap reversibility
   is what makes aggressive pruning safe — and it substitutes for building an
   eval harness early (a wrongly retired rule announces itself by recurring).
6. **Ride the existing rails**: order (cron) → audit formula → change-unit
   beads → polecat → refinery PR, mirroring `mol-doc-keeper-memory-audit`.
   Build size in every option is doc-keeper-scale (5–7 beads), no new
   primitives, which is what the architecture consistency test demands.
7. **Deltas, never rewrites.** The curator proposes itemized changes merged
   mechanically; nothing ever re-summarizes the whole rule set (ACE's "context
   collapse"/"brevity bias" — the failure mode where the learning system
   itself develops the verbose-then-lossy pathology it exists to fix).

## 3. Where the options genuinely differ

Only two decisions actually separate A, B, and C; everything else is shared.

**Decision 1 — where raw observations live** (they're high-volume and must be
review-free everywhere):

| | A: `learnings/*.md` files in repo | B: closed-at-creation beads | C: files on the city host |
|---|---|---|---|
| Evolution trail | native (git) | bead store history; git only sees promotions | events.jsonl + weekly git snapshot |
| Counters/queries | weak (frontmatter appends; rebase races) | strong (queryable, transactional) | fine (jsonl, single host) |
| Review friction | needs a `direct`-merge exception to the gated path for inert files | none — beads aren't versioned content, no exception needed | none, but also no pre-application review at all |
| Doctrinal fit | tension: an auto-merge lane through the delivery pipeline | clean: *Decisions have a home* — beads ARE the record primitive; `task_kind` is the established idiom | tension: state outside both repo and bead store; single-host |

B is the cleanest on this decision: it gets review-free capture *without*
carving an exception into the merge gates (A's split-trust `direct` lane is
defensible but is still a new exception to "pin agent work to the gated
path"), and beads give the recurrence detector real queries instead of
frontmatter archaeology. A's real weakness is using git as a counter-store;
C's is two sources of truth and single-host locality.

**Decision 2 — does a lesson apply before or only after human review?**
A and B: only after (days-to-weeks latency; the threshold and the latency are
the same dial). C: immediately (hot tier, TTL'd, ratify-or-expire within 45
days; the operator reviews *after* application via digest and can veto). This
is a genuine values choice about pre- vs post-application review — C's design
is honest that its weekly snapshot PR is bookkeeping, not a gate. Note C's
hot tier is *separable*: it can be added later as a bounded fast lane on top
of A/B without changing their architecture, seeded by the operator-endorsement
path that already exists in both.

## 4. Scorecard against the operator's concerns

| Concern | A: git rulebook | B: ledger + distiller | C: live memory |
|---|---|---|---|
| Heavy GitHub approval cycle | mitigated (split trust; ~1 real PR/wk) | mitigated (capture is beads; ~1 real PR/wk) | eliminated for application; review moves post-hoc |
| Versioned evolution trail | best — everything is git | promotions in git; raw trail in bead store | snapshot trail (weaker: after-the-fact) |
| Lower bar for some git changes | yes — the `direct` lane for inert ledger files | n/a (nothing inert lives in git) | n/a |
| One strong reaction ≠ gospel | thresholds + candidate inertness | thresholds + pattern beads + marked endorsements | TTL + ratify-or-expire (strongest anti-entrenchment) |
| Repeated feedback = strong signal | evidence appends in git history | best — queryable counts, derived not accumulated | counters in store |
| Other tools vs simple/local | fully local | fully local (beads already exist) | local files now; external memory service explicitly rejected at this scale |
| When does learning happen | on audit (24h capture / 7d promote) | on audit (24h capture / 7d promote) | same-day hot tier + audit ratification |

## 5. Proposed composite (for discussion, not decided)

**Spine: Option B.** Observation beads (`task_kind=observation`,
closed-at-creation, provenance-keyed) + a weekly distiller mirroring
`mol-doc-keeper-memory-audit` that clusters, scores against the
capture-promotion-pruning model, and files `prompt-update` change-unit beads
into the existing delivery pipeline. Promoted rules live in per-role
`learned-conventions-*` template-fragments (A's projection surface), capped,
with rule-anchor markers tying each bullet to its pattern bead.

**Adopt from A:** the fragment budget + `doctor/check-learned-rule-anchors`
integrity check; the hardening path (`tools/lint-learned.d/` + doctor checks)
as the preferred terminal state for mechanizable lessons — which all three
motivating examples are.

**Defer from C:** the hot tier. Start with the operator-endorsement fast path
(one `learn this` → promotion bead → same-day PR the operator approves —
fast because the human is already engaged, not because review is skipped). If
days-latency proves painful in practice, add C's TTL'd hot tier as a bounded
fast lane later; its ratify-or-expire mechanic is the right shape if and when
needed.

**Phasing** (each phase useful on its own):

1. **Capture + operator fast path** — the `file-feedback-observations`
   fragment (agents file observation beads when corrected) + the `learn this`
   endorsement path + the first `learned-conventions-polecat` fragment wired
   into pack.toml. No new formulas yet; mechanik can play distiller by hand at
   first (Principle 6 already gives it the dispatch rail).
2. **The distiller** — `mol-feedback-distiller` + order (7d): clustering,
   thresholds, promotion beads, demotion/challenge beads, budget enforcement.
3. **The miner** — `mol-feedback-miner` + order (24h): sweep merged-PR review
   threads so feedback given to humans (or missed by self-report) is captured;
   provenance-key dedup against channel-1 observations.
4. **Hardening** — first two lints (stale-reference phrases;
   constant-value-in-comment) as the proof that lessons can *leave* the
   prompt; retirement of their prose rules.

## 6. Open questions for the operator (the narrowing)

1. **Substrate ruling** — beads as the observation ledger (B), with git
   carrying only promoted rules? Or is a fully-git trail (A) worth the
   `direct`-merge exception and weaker counters?
2. **Latency tolerance** — is days-to-adopt acceptable when the operator
   endorsement path covers "now" cases, or is C's same-day hot tier wanted
   from the start (accepting post-hoc review)?
3. **Promotion review posture** — every promotion a real PR review (all
   designs' default), or a CodeRabbit-style quarantine (auto-approve after N
   days unless vetoed) once trust is established?
4. **Scope of rules** — fragments ship with the pack, so a promoted rule binds
   every importing rig. Acceptable for now (single-operator fleet), or do
   rules need per-rig scoping from day one?
5. **Where does the miner run** — the gc-toolkit rig only, or against every
   rig's repos (signal-loom etc.)? Cross-rig capture multiplies signal but
   needs the orders/pool story checked per rig.
6. **Thresholds** — the proposed defaults (promote at 3 occurrences across ≥2
   PRs/beads spanning ≥7 days; review-by 90d; fragment cap ~15 bullets) are
   starting values; any the operator wants moved before build?
