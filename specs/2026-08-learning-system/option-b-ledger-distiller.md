---
name: Feedback Learning — two-tier ledger + distiller
description: How corrective feedback on PRs and in conversations becomes durable prompt improvements — a cheap, review-free observation ledger in beads, a periodic distiller formula that promotes only proven patterns into the git-versioned, PR-reviewed prompt surface, and a demotion path so learned rules that stop earning their tokens get retired.
---

# Feedback Learning: two-tier ledger + distiller

The operator's problem: reviewers keep giving the same corrective feedback —
stale "historical artifact" references left in code, comments that restate the
code or duplicate a constant's value, boilerplate pasted into files it doesn't
apply to — and nothing folds it back into the standing agent prompts. The two
failure modes to avoid are symmetric: prompts locked behind git+PR review make
every lesson cost an approval cycle (so nobody files them), while prompts
editable on a whim turn one strong reaction into gospel and accrete bloat
(which is itself harmful — every rule spends prompt tokens forever).

The design splits the write path in two, on the doc-keeper precedent
(`specs/tk-yw3zb.1/doc-keeper-architecture.md`):

- **Tier 1 — the observation ledger.** Raw feedback events are cheap,
  high-volume, subjective, and touch no prompt. Filing one is a single
  `gc bd create`, no review, no git.
- **Tier 2 — the prompt surface.** `agents/*/prompt.template.md` and
  `template-fragments/*.template.md`, wired through `pack.toml`
  `[[patches.agent]] inject_fragments_append`. Git-versioned, edited only by a
  polecat under `mol-polecat-work`, landed only through the refinery as a
  reviewed PR to `main`. Low-frequency by construction.

A periodic **distiller** formula is the only bridge between the tiers. This is
*Agents improve* made structural: high-frequency writes need no review;
low-frequency promotions get real review — exactly where human attention pays.

## 1. The observation ledger: beads

Three substrates were evaluated:

| Substrate | Verdict | Why |
|---|---|---|
| **Beads** (`task_kind=observation`) | **Recommended** | Queryable (`gc bd list -l learning --json` + jq — the exact pattern `mol-triage-recurrence` already runs); native provenance (description body, `tracks` dep to the work bead, metadata fields); writable in one command from any agent mid-turn; the `task_kind` discriminator is the established idiom (`doc-update`, `review`, `visit`, `triage-subject`); and *Decisions have a home* says the bead store IS the pack's record primitive. Dolt backend makes metadata cheap and transactional. |
| **Append-only JSONL/markdown in-repo** | Rejected | "Auto-committable without review" contradicts the pack's own law: gc-toolkit is self-hosting — versioned content lands through beads → polecat → refinery → PR (`docs/architecture.md`, mechanik Principle 6). An auto-commit side channel to `main` either bypasses the check-set (the exact hole `doctor/check-merge-gate-drop/` exists to catch) or inherits the full PR cycle, defeating cheapness. Concurrent appends from parallel polecats also race on push. |
| **Agent auto-memory** | Rejected | Memory is per-agent and off-repo — a polecat's correction and the miner's finding would have no shared home. Worse, `mol-doc-keeper-memory-audit`'s nature gate *deliberately drops* agent-conduct corrections as operational lore — the very signal this system feeds on. Wrong filter, wrong scope. |

**The observation bead** is an *ephemeral unit* in work-bead-state-machine
terms: its landing target is its own notes, so it is **closed at creation** —
"landed" means "recorded." It never appears in open-work queues, is never
routed, and never blocks anything.

```bash
OBS=$(gc bd create "obs: comments restating the adjacent code (PR #241)" \
  -t task -l learning -l observation \
  -d "## Statement
Reviewer feedback: the added comments restate what the code already says.
## Quote
> 'this comment just repeats the line below it' — https://github.com/zookanalytics/gc-toolkit/pull/241#discussion_r99123
## Proposed norm (draft, non-binding)
Comments explain why, never what; never duplicate a constant's value." --json | jq -r '.id')
gc bd update "$OBS" \
  --set-metadata task_kind=observation \
  --set-metadata obs.category=comment-verbosity \
  --set-metadata obs.scope=agent:polecat \
  --set-metadata obs.severity=minor \
  --set-metadata obs.source=self \
  --set-metadata obs.recurring=suspected \
  --set-metadata obs.provenance="pr:241 comment:...#discussion_r99123 bead:tk-x4k2p" \
  --set-metadata gc.outcome=recorded --status=closed
gc bd dep add "$OBS" tk-x4k2p --type=tracks   # tracks, not parent-child: no state transmission
```

Schema fields: **statement** (title + body), **category** (slug: the distiller
curates the vocabulary), **scope** (`repo:<rig>` / `agent:<role>` / `global`),
**provenance** (PR + comment URL, originating bead id), **severity**
(`minor|substantive|blocking`), **source** (`self|miner|operator`),
**recurring** (`one-off|suspected`), plus `obs.endorsed=operator` when set by
channel (iii). Dedup key is the provenance comment URL.

## 2. Capture: three channels, all writing the same bead shape

**(i) In-conversation self-report.** A new fragment,
`template-fragments/file-feedback-observations.template.md`, appended via
`pack.toml` to the polecat, mechanik, and converse patches (the
`file-work-records` precedent). The instruction: *when a turn contains
corrective feedback — a review comment, an operator correction, a rework
child's cause — fix the instance now, and file one observation bead before the
turn ends. Filing is recording, not proposing: do not edit any prompt.* Cheap,
immediate, subjective — and capture is deliberately decoupled from learning:
**in-conversation, only the ledger is written; prompts change only at
distillation.**

**(ii) PR-review miner** (`formulas/mol-feedback-miner.toml`, order
`orders/feedback-miner.toml`, `trigger="cooldown"`, `interval="24h"`, bare pool
`gc-toolkit.polecat`, `scope="rig"`, `phase="vapor"` so the scale-from-zero
pool wakes). Steps mirror the memory audit: prime → `gh pr list --state merged
--search "updated:>=<window>"` → read review threads via `gh api` → extract
*corrective* comments (a human asking for a change of a generalizable kind, as
opposed to discussion) → dedup by comment URL against existing observation
beads → file, capped by `max_obs_per_run`. This channel is objective, catches
feedback given to *humans* too, and backstops an agent that failed to
self-report.

**(iii) Operator "learn this."** A one-liner (or thin `skills/learn-this`
wrapper) that files the same bead with `obs.endorsed=operator`. This is the
single-occurrence fast path through promotion — deliberate, and auditable.

## 3. The distiller: `mol-feedback-distiller`

`formulas/mol-feedback-distiller.toml`, fired by
`orders/feedback-distiller.toml` (`trigger="cooldown"`, `interval="168h"`,
same pool/scope/vapor shape). Mirroring `mol-doc-keeper-memory-audit` step for
step:

1. **load-context** — prime; list closed `task_kind=observation` beads in the
   evidence window (180 days); list open `task_kind=feedback-pattern` beads
   (below); missing/empty inputs are a clean no-op with the step bead closed
   `gc.outcome=pass` before `gc runtime drain-ack`.
2. **cluster-and-score** — a reading task, not a bucketing script (the
   memory-audit's "the `## Scope` is the classifier" stance). Group
   observations by category + scope + semantic similarity. Each cluster is
   owned by one standing **pattern bead** (`task_kind=feedback-pattern`, open,
   unrouted — the `triage-subject` idiom: a standing record, not claimable
   work). The distiller recomputes and caches evidence on it (§5).
3. **promote / demote / dedup** — apply the criteria below; dedup against
   in-flight `prompt-update` beads *and the open PRs of closed ones* (the
   refinery closes on PR-open under `merge_strategy=mr` — the exact dedup
   trap the memory audit already documents); file at most
   `max_beads_per_run`; close the step; drain.

**Promotion criteria** (either arm):
- **N=3** observations across **M≥3 distinct PRs/beads** within 45 days, with
  ≥2 distinct authors or channels — one loud reviewer on one bad day is one
  vote, not three; or
- **1** observation carrying `obs.endorsed=operator`.

A promotion files ONE change-unit bead — `task_kind=prompt-update`, labels
`learning`/`prompt-update`, `target=main`, `merge_strategy=mr`,
`gc.routed_to=${GC_RIG:+$GC_RIG/}gc-toolkit.polecat` — whose body names the
rule text (draft), the target fragment, and the full provenance list. The
distiller never edits a prompt, exactly as the audits never edit a doc.

**Demotion criteria:** a promoted rule with **zero** supporting observations
in **K=90 days** gets a *challenge* bead proposing one of: retire the prose
(reclaim the tokens — the behavior is internalized or the models improved);
convert to a `doctor/` check if mechanically checkable; or keep (operator
call, recorded on the pattern bead so the same challenge isn't refiled every
cycle — `challenge_head` marker, the `stale_gate_head` re-arm idiom). Bloat is
a first-class defect: the distiller also warns when a learned-rules fragment
exceeds a word budget.

## 4. The prompt surface, and the loop end to end

Promoted rules compile into per-role fragments —
`template-fragments/learned-conventions-polecat.template.md` (etc.) — injected
via `pack.toml` `inject_fragments_append` for imported gastown agents and
`{{ template "..." . }}` for native ones. Each rule carries a marker comment
binding it to its pattern bead: `<!-- rule:tk-p7q2n src:PR#241,#248,#252
promoted:2026-08-24 -->`. Git history is the rule's evolution trail; the
pattern bead is its evidence trail.

**Worked example — "comments too verbose", three PRs over two weeks:**

1. *Aug 3, PR #241*: reviewer comments that new comments restate the code. The
   polecat fixes the comments in its rework, and its
   `file-feedback-observations` fragment files observation `tk-ob101`
   (`category=comment-verbosity`, `source=self`, provenance = comment URL).
2. *Aug 8, PR #248*: same feedback — given to a *human* contributor. No agent
   was in that conversation; the nightly `mol-feedback-miner` extracts it as
   `tk-ob117` (`source=miner`).
3. *Aug 14, PR #252*: a converse session gets the correction from the
   operator mid-discussion; files `tk-ob129`.
4. *Aug 17*: `mol-feedback-distiller` fires. Clusters the three under pattern
   bead `tk-p7q2n`: 3 observations, 3 distinct PRs, 2 channels, 14-day span —
   clears the N/M arm. Files `prompt-update: add concise-comments rule to
   polecat learned conventions` with draft rule text and provenance, routed to
   the pool.
5. A pool polecat claims it under `mol-polecat-work`: edits
   `template-fragments/learned-conventions-polecat.template.md` (adding the
   rule + marker; adds the fragment name to the polecat patch's
   `inject_fragments_append` if this is the first rule), pushes
   `polecat/<bead-id>`, hands off to refinery.
6. `mol-refinery-patrol` rebases, runs the (empty, silently-skipping) gates,
   dispatches the codex pre-open signoff, opens one small PR to `main`. The
   **operator reviews the promotion itself** — is this rule true, general, and
   worth its tokens? — and merges. The distiller's next pass stamps
   `rule.path`/`promoted_at`/`promoted_pr` on `tk-p7q2n`.
7. *~Nov 20*: 90 days with zero new `comment-verbosity` observations. The
   distiller files a challenge bead: retire the prose, or convert to a doctor
   check (`doctor/check-comment-verbosity/` — e.g. flag comments duplicating a
   literal constant value; mechanical, zero prompt tokens). Operator picks;
   the change rides the same polecat → refinery → PR path; `tk-p7q2n` records
   `retired_at`. If the pattern recurs post-retirement, its full evidence
   history argues for re-promotion — probably as a check, not prose.

## 5. Counters and state

Git stores no counters — it stores only the compiled rules. The race-safety
answer is: **capture never mutates shared state, and all counts are derived,
not accumulated.**

- **Capture is append-only.** Every channel *creates* a closed observation
  bead; nothing increments anything, so concurrent capture cannot race.
  Double-filing is bounded by the provenance-URL dedup at mine/distill time.
- **Counts are recomputed, cached on the pattern bead.** The distiller derives
  `evidence_count`, `distinct_prs`, `last_seen`, `first_seen` by querying the
  observation set each run and writes them as metadata on the pattern bead —
  a cache of a query, so any lost or duplicated write self-heals next run.
- **Single writer.** Only the distiller writes pattern-bead rollups — the
  "single writer of merged-truth" discipline from
  `docs/work-bead-state-machine.md` applied to learned-truth. Cooldown-trigger
  orders don't stack runs within an interval, and idempotent recomputation
  covers the residual.

## 6. Honest weaknesses, and build size

- **Two systems to keep coherent.** Fragment rules vs. pattern beads can
  drift (a rule hand-deleted; a pattern bead closed with prose still live).
  Mitigation: a `doctor/check-learned-rule-anchors/` check asserting every
  `<!-- rule:tk-... -->` marker has a live pattern bead and vice versa.
- **The distiller is the crux.** Clustering and "is this the same feedback?"
  are LLM judgment, like the memory audit's gates. Failure is bounded on both
  sides: over-promotion hits `max_beads_per_run` and then a human PR review;
  under-promotion is self-healing because observations persist and are
  re-scored statelessly every run (the drift-audit stance: no baseline cursor
  to corrupt).
- **Miner precision is genuinely hard** — corrective vs. conversational
  comments. Ship channels (i) and (iii) first; add the miner once the ledger
  shape is proven. The system degrades gracefully without it.
- **Ledger rot.** Observations accumulate and category slugs proliferate. The
  180-day evidence window bounds what the distiller reads; the distiller owns
  the category vocabulary and merges near-duplicate slugs.
- **Latency is a feature with a cost.** Feedback → standing-prompt change is
  bounded below by distiller cadence + PR review (days). The turn-level fix
  still happens immediately; only *generalization* waits. The operator
  endorsement path exists for "this must stick now."
- **Rig scope.** Orders are rig-scoped with bare pools; a `scope=global` rule
  learned in one rig reaches others only through the shared pack fragment —
  fine for gc-toolkit today, a real question for a multi-rig fleet.

**Build estimate** — deliberately the same order of magnitude as doc-keeper:
three new formulas (`formulas/mol-feedback-miner.toml`,
`formulas/mol-feedback-distiller.toml`, and nothing else — capture is a
fragment, not a formula), two new orders (`orders/feedback-miner.toml`,
`orders/feedback-distiller.toml`), two new template fragments
(`template-fragments/file-feedback-observations.template.md`,
`template-fragments/learned-conventions-polecat.template.md` seeded at first
promotion), ~6 lines of `pack.toml` `inject_fragments_append` wiring, one
optional doctor check (`doctor/check-learned-rule-anchors/`), and one central
doc (`docs/feedback-learning.md`) with the working spec under
`specs/<bead-id>/`. Phase 1 (fragment + distiller + orders) is roughly the
`.5`–`.8` slice of the doc-keeper build; the miner is a comparable second
phase.
