---
name: Feedback-Learning Loop
description: The conventions of the feedback-learning loop — its ceiling-raising purpose, how feedback is recorded as observation beads, how observations become operator-reviewed rule changes, the four carriers adopted rules land in, and the recurrence metric that says whether the loop works.
---

# Feedback-Learning Loop

The learning system's purpose is **ceiling-raising**: capturing what the
operator cares about and responds to, so agents present better options
and escalations over time. It works through one path. Feedback is
recorded as observation beads; a distiller judges what the observations
add up to; every resulting behavior change lands as an operator-reviewed
PR against this pack. Nothing changes agent behavior until that PR
merges.

Hardened detectors (`tools/lint-learned.d/`) and doctor checks are **not
the learning system**. They are ordinary pack hygiene — a well-architected
pack fixing its own bugs — which is why they live outside the conventions
cap and outside `gc doctor`'s invariant set. A rule that hardens has
graduated out of the learning system into tooling.

## Scope

**Mandate.** The conventions of the feedback-learning loop — the
observation contract, the capture channels, the promotion and retirement
path, the carriers adopted rules land in, and how the loop's own success is
measured.

**Boundaries.** The design rationale and decision record live in
`specs/2026-08-learning-system/`. The judgment content of the promotion
rubric — what makes an observation promotable — lives in
`skills/learning-distill/SKILL.md`, not here. Doc-keeper's
brief-maintenance is an adjacent, separate loop: it keeps documentation
current; this loop changes standing agent behavior.

## The observation bead

An observation is a standard `task` bead, **closed at creation** — an
ephemeral record unit where "landed" means "recorded". It is never
routed, never assigned, and never blocks anything.

- **Title:** `obs: <one-line restatement of the feedback> (<source ref>)`
- **Type/labels:** `-t task -l learning -l observation`
- **Body sections:** `## Statement` (the generalizable point),
  `## Quote` (verbatim feedback + link), `## Proposed norm` (draft rule
  text, explicitly non-binding), optionally `## Context` (what the diff
  was doing).
- **Metadata:**

| key | values |
|---|---|
| `task_kind` | `observation` |
| `obs.category` | free slug; the distiller owns the vocabulary and merges near-duplicates. Also the finding half of the dedup key, so two observations from one event need different slugs |
| `obs.scope` | `repo:<rig>` \| `agent:<role>` \| `global` — guess narrow |
| `obs.source` | `self` \| `miner` \| `operator` |
| `obs.directive` | `standing` \| `diff` — capture-time guess; the distiller re-judges |
| `obs.endorsed` | `operator` when filed via "learn this" |
| `obs.provenance` | the event half of the dedup key: `pr:<owner/repo>#<n>:comment:<id>`, `pr:<owner/repo>#<n>:veto`, or `bead:<id>:turn:<date>` — `<owner/repo>` is the full slug (`gh repo view --json nameWithOwner -q .nameWithOwner`, or parse the origin URL) |
| `gc.outcome` | `recorded`; `--status=closed` in the same update |

**Dedup is on the pair (`obs.provenance`, `obs.category`), always.** The
same finding captured by self-report and by the miner merges to one
occurrence: the miner checks before filing, and the distiller checks again
before counting. The category half is what keeps two findings from one
sitting or one review comment from collapsing into one, because provenance
names the event and a single event can produce several findings. Recurrence
and source-diversity rollups still count distinct `obs.provenance`, so one
event stays one occurrence and one voice however many findings came out of
it.

## Capture channels

Four producers file the same bead contract:

1. **Self-report.** Working agents (polecat, mechanik, converse)
   carry the `file-feedback-observations` fragment: when a turn brings
   corrective feedback about standing behavior, the agent fixes the
   instance first, then files one observation bead with
   `obs.source=self`.
2. **PR miner.** The `mol-feedback-miner` order sweeps each importing
   rig's merged/closed PRs' review and conversation comments and files
   what self-report missed, with `obs.source=miner`. It files
   observations only — never patterns, never proposals.
3. **Operator fast path.** "learn this: …" in any conversational session
   files the same bead with the operator's wording as `## Statement`,
   `obs.source=operator`, and `obs.endorsed=operator`. Endorsed
   observations never wait on volume: they trigger the distiller's next
   run and promote at any occurrence count.
4. **Distiller veto sweep.** The distiller records each promotion PR
   closed unmerged as one observation (`obs.category=learning-rubric`,
   provenance `pr:<owner/repo>#<n>:veto`) — the rubric's own misses feed
   the loop it powers.

## The promotion path

The distiller (`mol-feedback-distiller`, judging by the
`learning-distill` rubric skill) dedups pending observations, clusters
them onto pattern beads, and decides which clusters have earned a rule.
Each surviving proposal becomes one `prompt-update` bead carrying the
exact rule text, the evidence list, and the reasoning; a polecat builds
it; the refinery opens the PR; **operator review of that PR is the
gate**. The distiller records and proposes — it never edits a prompt,
fragment, or skill, and neither does any capturing agent.

### Two gates on promotion into a paid carrier

Not every earned pattern may be auto-adopted into content every future agent
pays for. Two gates — defined in full in the `learning-distill` rubric,
`skills/learning-distill/SKILL.md` — guard the `convention`, `profile`, and
`review-rubric` carriers:

- **External check (Gate 1).** A cluster that is entirely
  `obs.source=self` cannot auto-promote into a paid carrier without an
  `obs.endorsed=operator` observation: a self-report that promotes itself
  has no external check. An all-operator cluster spanning two or more
  distinct `obs.provenance` events is corroborated and promotes unendorsed,
  because the operator's correction is that check. A blocked pattern is
  *surfaced* to the operator (held with the block stated), never adopted;
  it promotes later on corroboration or an explicit `learn this`
  endorsement.
- **Remedy class (Gate 2).** A remedy that is an exhortation ("be
  thorough", "try harder") or that fixes a structural failure (a
  verification gap, a race, a missing mechanical check) does not become a
  prompt bullet — a bullet an agent can forget fails silently, since the
  agent who forgets the behavior is the one who skips the bullet. It routes
  instead to an **engineering work bead** (the promotion-time twin of the
  retirement pass's *hardenable?* question). Only a concrete behavior keyed
  to a concrete trigger promotes as prose.

Both gates guard the paid carriers only; they do not apply to
`learning-rubric` proposals against the skill, to retirements, or to
hardens (see decisions D8/D9 in
`specs/2026-08-learning-system/decisions.md`). Gate 2 has one redirect
beyond the engineering bead: a remedy that reads as an exhortation only
because the right behavior resists compression becomes an `exemplar`, if a
real before/after pair exists.

## The rule surface: four carriers

An adopted rule lands in one of four carriers. The carrier is chosen at
promotion, and it decides the target, the budget, and what the adoption
costs to keep. Different shapes of learning need different carriers; a prose
bullet is one of four, not the default. The selection rule lives in the
`learning-distill` rubric.

**`profile` — the operator profile.**
`template-fragments/operator-profile.template.md`
(`{{ define "operator-profile" }}`), a "What the operator cares about"
section. It is the most widely injected surface in the pack: every
coordinating agent renders it, and so does the polecat doctrine fragment.
This is the loop's ceiling-raising surface — entries state what the operator
values and responds to, the taste that makes agents present better options
and escalations, not just mistakes to avoid. Because it states operator
taste, a cluster with no `obs.source=operator` observation cannot claim it.
Hard cap **12 entries**. `specs/tk-awa7hv/operator-profile-audit.md` records
the audit that populated it.

**`convention` — learned conventions, per role.**
`template-fragments/learned-conventions-<role>` fragments — one per role,
seeded by the role's first promotion (`learned-conventions-polecat` ships
seeded empty). Each holds at most **15 bullets**. The polecat fragment is
injected by both polecat prompts (`agents/polecat` and `agents/polecat-codex`
both render `{{ template "learned-conventions-polecat" . }}`). Use this
carrier when the behavior must be carried into the turn by one role and no
reviewer sees the moment it goes wrong.

**`review-rubric` — what a reviewer checks.** `formulas/mol-review.toml`,
step `review`, the "What to check" dimensions. Preferred over `convention`
whenever the failure is visible in a diff: one dimension reaches every
agent's version of the mistake through the reviewer, where a bullet reaches
only the role whose fragment renders it. An amendment is one dimension
sharpened or added. The anchor goes in the TOML comment ledger above the
review step, not beside the dimension: the step description renders into a
step bead, where an HTML comment is noise in the text a reviewer reads.

**`exemplar` — the exemplar corpus.**
`template-fragments/learning-exemplars.template.md`, at most **8**
before/after pairs, resolved on demand during a review rather than injected
into any prompt. For lessons that are a shape rather than a statement.

Every adopted entry carries an anchor comment — immediately above it in the
three fragment carriers, in the ledger for `review-rubric`:

```
<!-- rule:<pattern-bead> src:<refs> adopted:<date> -->
```

The `rule:<pattern-bead>` field is what makes recurrence attributable; an
entry without one is adopted but unmeasured. A promotion that would exceed a
carrier's cap must name the entry it displaces — the weakest incumbent goes
in the same PR, or the promotion does not file.

## Measuring the loop

`assets/scripts/learning-recurrence.sh` is the loop's success metric.
Repeat feedback is the honest one: if the loop works, the same correction
stops coming back. The report reads observation beads across every store and
collapses duplicate captures — one correction read by both self-report and
the miner. Two observations are the same correction when they share a
provenance key AND an `obs.category`: a provenance key can name a whole
turn, and a turn carries several distinct corrections. It gives two numbers:

- **M1, repeat feedback by category.** The share of events in the window
  whose `obs.category` was already seen on an earlier event. `obs.category`
  is stamped at capture, so this half survives the distiller being disabled.
  The slug is free text minted per capture, so when nearly every event mints
  its own, the repeat count is pinned to (categorised minus distinct) and the
  share measures slug reuse rather than recurrence. The report withholds the
  rate when the key does not discriminate, and reports the spread instead.
- **M2, recurrence after adoption.** Per adopted entry, the observations
  attributed to its pattern bead since its adoption date. Attribution runs
  through `obs.distilled`, which only the distiller stamps. An anchor records
  a date, not a moment, and the distiller stamps consumed observations when
  it files the proposal — before merge. Counting therefore starts the day
  after the anchor date, so a rule cannot recur against its own evidence.

Both can floor out for reasons that are not improvement, so the report
states its own limits beside each number: near-unique category slugs stop
M1's key discriminating so its rate is withheld, an unattributed window
leaves M2 unmeasured, and an entry with no `rule:<pattern-bead>` anchor
cannot be scored at all. An unreadable store
exits non-zero rather than reporting a smaller city as a smaller problem.

The script runs standalone and needs no distiller run. The distiller echoes
it at the end of every run, and `--inventory` is the shared parser its
retirement pass reads instead of re-deriving the same anchor grep. Both the
distiller's calls pass `--ref origin/main`: read from a working tree, the
inventory counts a proposal branch's unmerged entries as adopted.

## Retirement and hardening

Every distiller run asks the retirement questions of each adopted entry, in
every carrier: still binding, still recurring, subsumed, over cap, or
mechanically detectable? Retirements ride the same prompt-update → PR →
operator-review path as promotions, and a retirement names the carrier it
removes from. The best outcome a rule can have is hardening: when its
violation lints cleanly, the lint or doctor check lands in the same PR
that deletes the prose bullet AND its anchor — provenance thereafter
lives on the pattern bead and the harden PR. A hardened rule has left
the learning system: the detector is ordinary pack hygiene, holding no
prompt weight and counting against no cap.

Recurrence after adoption is the pass's sharpest input: the rule was
adopted and the feedback came back anyway. That argues for a different
carrier or a mechanism, never for restating the same bullet more loudly.
Evidence against an adopted rule never silently retires it — contradiction
files a visit for the operator, who picks scope-narrowing, retirement, or
dismissal.
