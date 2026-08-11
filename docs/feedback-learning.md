---
name: Feedback-Learning Loop
description: The conventions of the feedback-learning loop — how corrective feedback is recorded as observation beads, how observations become operator-reviewed rule changes, and where adopted rules live in agent prompts.
---

# Feedback-Learning Loop

The city learns from corrective feedback through one path: feedback is
recorded as observation beads, a distiller judges what the observations
add up to, and every resulting behavior change lands as an
operator-reviewed PR against this pack. Nothing changes agent behavior
until that PR merges.

## Scope

**Mandate.** The conventions of the feedback-learning loop — the
observation contract, the capture channels, the promotion and retirement
path, and the rule surface adopted rules render into.

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
| `obs.category` | free slug; the distiller owns the vocabulary and merges near-duplicates |
| `obs.scope` | `repo:<rig>` \| `agent:<role>` \| `global` — guess narrow |
| `obs.source` | `self` \| `miner` \| `operator` |
| `obs.directive` | `standing` \| `diff` — capture-time guess; the distiller re-judges |
| `obs.endorsed` | `operator` when filed via "learn this" |
| `obs.provenance` | the dedup key: `pr:<owner/repo>#<n>:comment:<id>`, `pr:<owner/repo>#<n>:veto`, or `bead:<id>:turn:<date>` — `<owner/repo>` is the full slug (`gh repo view --json nameWithOwner -q .nameWithOwner`, or parse the origin URL) |
| `gc.outcome` | `recorded`; `--status=closed` in the same update |

**Dedup is on `obs.provenance`, always.** The same event captured by
self-report and by the miner merges to one occurrence: the miner checks
before filing, and the distiller checks again before counting.

## Capture channels

Four producers file the same bead contract:

1. **Self-report.** Working agents (polecat, mayor, mechanik, converse,
   and their thread variants) carry the `file-feedback-observations`
   fragment: when a turn brings corrective feedback about standing
   behavior, the agent fixes the instance first, then files one
   observation bead with `obs.source=self`.
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

## The rule surface

Adopted rules render into agent prompts via
`template-fragments/learned-conventions-<role>` fragments — one per
role, seeded by the role's first promotion (`learned-conventions-polecat`
ships seeded empty). Every bullet is immediately preceded by its anchor
comment:

```
<!-- rule:<pattern-bead> src:<refs> adopted:<date> -->
```

Each fragment holds at most **15 bullets**. A promotion that would
exceed the cap must name the bullet it displaces — the weakest incumbent
goes in the same PR, or the promotion does not file. The polecat
fragment is wired in both `pack.toml` (polecat patch) and
`agents/polecat-codex/agent.toml` `inject_fragments`; the two lists are
hand-synced.

## Retirement and hardening

Every distiller run asks the retirement questions of each adopted rule:
still binding, subsumed, over cap, or mechanically detectable?
Retirements ride the same prompt-update → PR → operator-review path as
promotions. The best outcome a rule can have is hardening: when its
violation lints cleanly, the lint or doctor check lands in the same PR
that deletes the prose bullet AND its anchor — provenance thereafter
lives on the pattern bead and the harden PR. Evidence against an
adopted rule never
silently retires it — contradiction files a visit for the operator, who
picks scope-narrowing, retirement, or dismissal.
