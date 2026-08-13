---
name: Learning-System — Narrowing Decisions
description: The operator rulings that narrow the 2026-08 learning-system exploration into a buildable shape — substrate, apply timing, promotion gate, rule reach, miner reach, the judgment-over-counters evidence model, bead-count-driven cadence, and the two always-injected-promotion gates. Supersedes the numeric-threshold proposal in capture-promotion-pruning.md §B and the fixed cadences in the option docs.
---

# Learning-System — Narrowing Decisions

Operator rulings, 2026-08-10, on the questions posed in
[synthesis.md](synthesis.md) §6. Where a ruling contradicts the research docs,
this doc wins; the research docs stay as the record of what was considered.

## D1. Observation ledger: beads

Raw feedback observations are standard `task` beads, closed at creation
(`task_kind=observation`), provenance-keyed (PR comment URL / bead id), per
[option-b-ledger-distiller.md](option-b-ledger-distiller.md) §1. Git carries
only promoted rules; each promotion PR carries the full evidence list in its
body. No merge-gate exceptions, no git counter-store.

## D2. Apply timing: PR-gated only

A lesson changes agent behavior only when its promotion PR merges. No live
hot tier for now — the operator fast path ("learn this" → promotion bead →
same-day PR approved while the operator is already engaged) covers urgent
cases. Option C's TTL'd hot tier remains a documented bolt-on if days-latency
ever demonstrably hurts.

## D3. Promotion gate: full review

Every promotion and retirement PR requires explicit operator merge. No
quarantine auto-approve. This gate is the primary anti-gospel backstop under
D6 — the review is where "should this bind every future agent?" gets a human
answer, so it must stay a real judgment, not a rubber stamp. Revisit only
after months of observed promotion quality.

## D4. Rule reach: pack-wide, scope recorded

Promoted rules land in shared `template-fragments/learned-conventions-<role>`
fragments and bind every rig importing gc-toolkit. No per-rig overlay plumbing
now. Every observation still records scope (`repo:<rig>` / `agent:<role>` /
`global`) so per-rig projection can be added later without re-mining evidence.

## D5. Miner reach: every importing rig

`mol-feedback-miner` ships as a rig-scoped pack order — each rig importing
gc-toolkit mines its own repo's merged-PR review threads into its own bead
store (enablement-is-import, like the doc-keeper orders). The distiller reads
observations cross-rig (`gc bd … --rig <name>`); validating that cross-rig
read is an explicit build-phase task before the miner multiplies volume.

## D6. Evidence model: judgment over counters — and the judgment itself learns

**Operator ruling (supersedes the numeric thresholds in
[capture-promotion-pruning.md](capture-promotion-pruning.md) §B and the N/M
arms in the option docs):** promotion is a *reasoned judgment*, not a counter
comparison — and one loud day absolutely can change rules. What must not
happen is over-indexing to feedback-is-gospel; the guard is the quality of
the reasoning plus the D3 review, not an occurrence floor.

The distiller judges each pending observation (or cluster) on what the
feedback actually *says*:

- **Explicit standing directives promote immediately at N=1.** Feedback that
  states universal intent — "never do this again", "change all occurrences",
  "stop doing X everywhere" — is a directive about standing behavior, not a
  reaction to one diff. It files a promotion bead in the next distiller run
  regardless of count. (The D3 review still applies; nothing lands unseen.)
- **Diff-scoped reactions wait for corroboration.** A nit phrased about this
  change ("this comment is redundant here") is evidence toward a pattern, not
  a rule by itself. Recurrence across PRs/beads, source diversity, and heat
  are all *inputs the reasoning weighs* — none is a gate, none is ignored.
- **Contradiction triggers re-review, never silent flip-flop** — unchanged
  from capture-promotion-pruning.md §B (contention → operator visit).
- **Scope inference still defaults narrow**; explicit operator scope wins.
- Counters (occurrences, distinct PRs, last-seen) are still derived and
  cached on pattern beads — as telemetry and as evidence *for* the judgment
  and for challenge audits, not as promotion arithmetic.

**The rubric is a learnable artifact.** The promotion-judgment rubric lives
as a versioned skill (working name `skills/learning-distill/SKILL.md`),
inlined into the distiller dispatch via the dispatch-carries-the-method rail
(`assets/scripts/review-dispatch-body.sh` precedent). Because it is versioned
pack content, it is inside the loop it powers:

- a promotion the operator vetoes at PR review → an observation with
  `obs.category=learning-rubric` (the rubric over-promoted);
- a missed promotion the operator later endorses by hand → same category
  (the rubric under-promoted);
- rubric edits ride the ordinary promotion pipeline (change-unit bead →
  polecat → refinery PR → D3 review).

This is the meta-loop: the system's own judgment quality is one of the
categories it learns about.

## D7. Cadence: bead-count-driven, timer as heartbeat

**Operator ruling:** distillation cadence should track the number of pending
learning beads, not the calendar.

The `gc order` rail only offers time-based cooldown triggers, so the
implementation is the `mol-triage-recurrence` restraint pattern: a **cheap
daily order** whose first step counts pending observations and cleanly no-ops
below the floor. The distiller *proceeds* when any of:

- pending observations ≥ `distill_min_pending` (formula var, starting value
  ~5);
- any pending observation is operator-endorsed or classified as an explicit
  standing directive (D6) — these never wait on volume;
- the oldest pending observation exceeds `distill_max_age` (~14d) — a trickle
  still gets processed eventually.

Effective cadence therefore scales with feedback volume: a heavy week
distills daily, a quiet month distills once. The miner keeps a plain 24h
cooldown (it sweeps external state; time-based is correct there).

## D8. Promotion gate — source diversity: no self-only auto-adoption

**Operator ruling, 2026-08-12** (visit tk-yohhf, subject tk-d9g0x / PR #330,
closed unmerged): a pattern that is entirely `obs.source=self`, or whose
`distinct_sources=1`, **cannot auto-promote into always-injected prompt
content** (a `learned-conventions-<role>` fragment bullet) without an explicit
`obs.endorsed=operator` observation. Self-report → self-promote → self-inject
is a loop with no external check — the design intent of a learning rule is to
encode a mistake an external voice (the operator, or an independent
reviewer/miner signal) called out, not one an agent asserted about itself. A
blocked pattern is *surfaced* to the operator, never auto-adopted; it promotes
on independent corroboration (a second distinct source) or an operator
`learn this`. The gate guards only the always-injected fragments —
`learning-rubric` proposals, retirements, and hardens are exempt. This narrows
D6: source diversity was a *weighed input*; for the always-injected surface it
is now a *hard floor*.

## D9. Promotion gate — remedy class: structural fixes are engineering, not prose

**Operator ruling, 2026-08-12** (same visit): an observation whose remedy is an
**exhortation** ("be thorough", "try harder", "don't declare done from a
partial view") or that addresses a **structural failure** (a verification gap,
a race, a missing mechanical check) does **not** promote into a prompt bullet —
it routes to an **engineering work bead**. A prose bullet an agent can forget
fails silently: the agent who would forget the behavior is the same one who
skips the bullet telling them to remember. Structural failures need a
mechanical fix (a lint, a doctor check, a gate, a code change); only a concrete
behavior keyed to a concrete trigger promotes as prose. This is the
promotion-time twin of the existing *hardenable?* retirement question (Option
A's hardening ladder, adopted into D6's composite): rather than promote prose
and retire it for a lint later, the distiller files the mechanism now. The
discriminator and the alternate filing route live in
`skills/learning-distill/SKILL.md` and `formulas/mol-feedback-distiller.toml`
(`file-and-dispatch` §1b).

## Superseded / adjusted in the research docs

- capture-promotion-pruning.md §B "Thresholds scale with blast radius" table
  → replaced by D6 (blast radius remains a *consideration the rubric weighs*,
  and wider-scope promotions deserve proportionally stronger reasoning in the
  promotion bead's body — but no numeric floor).
- option-b-ledger-distiller.md §3 promotion criteria (N=3 / M≥3) and 168h
  distiller interval → replaced by D6 / D7. Its demotion shape (challenge
  beads, retire-or-harden) stands, with the 90d window now a rubric input
  rather than a hard trigger.
- option-a-git-native-rulebook.md → not selected as substrate; its fragment
  projection, bullet budget, `check-learned-rule-anchors`-style doctor check,
  and hardening path (lints under `tools/`, doctor checks) are adopted into
  the composite.
- option-c-live-memory-git-export.md → hot tier deferred (D2); its
  ratify-or-expire mechanic is the reference design if a hot tier is ever
  added.

## What this settles, and what remains

Settled: substrate, apply timing, gate, reach, miner shape, evidence model,
cadence, and the two always-injected-promotion gates (D8 source diversity, D9
remedy class). The composite is Option B's spine + Option A's projection
surface and hardening ladder + D6's reasoned promotion with a learnable rubric.

Remaining before build: draft the implementation design (formula/step-level,
including the cross-rig distiller read and the rubric skill's first version)
and cut the phase beads — phasing per synthesis.md §5: capture + fast path →
distiller → miner → first hardened lints.
