# Cross-agent review-chain pilot learnings (signal-loom Epic 6)

**Bead:** tk-0tdy7 (research/survey for tk-ztapg)
**Surveyed at:** 2026-05-07
**Surveyed by:** gc-toolkit.nux

This doc consolidates pilot data from the cross-agent review-chain bootstrap on
signal-loom Epic 6 (`sl-yqslv`). It is **research input** for tk-ztapg (formal
review-chain formula design, mayor-owned). It does not design the formula.

Pilot learning #1 (push timing) is already captured in tk-ztapg's notes as the
baseline; this doc confirms that learning, reports new friction surfaced by the
three pilots that followed, and flags review-driven work that landed OUTSIDE
the chain (the operator-stated gap).

## Provenance table

| Doc-type / artifact | Producer (chain phase / agent / git artifact) | Source location | Surveyed at |
|---|---|---|---|
| Push-timing baseline | tk-ztapg notes (mayor / human) | `gc bd show tk-ztapg` notes section ("Pilot learning #1") | 2026-05-07 |
| Epic 6 root | mayor-filed epic | `sl-yqslv` (signal-loom) | 2026-05-07 |
| Pilot 1 impl bead | impl polecat (Claude) | `sl-v0nb0`, branch `gc-gc-toolkit.furiosa-1c1a7af7e181`, impl SHAs `3213561f` + `8a0eaead` | 2026-05-07 |
| Pilot 1 codex review | polecat-codex | `sl-5j7i2` | 2026-05-07 |
| Pilot 1 claude triage | impl polecat (Claude) | `sl-rt1rw`, triage SHAs `5803439d` + `998aa4be` | 2026-05-07 |
| Pilot 1 claude review | impl polecat (Claude) | `sl-ysoae` | 2026-05-07 |
| Pilot 1 PR | refinery merge | github.com/zookanalytics/signal-loom PR #459 (merged 2026-05-06T18:45:51Z) | 2026-05-07 |
| Pilot 2 impl bead | impl polecat (Claude) | `sl-a6hjw`, branch `refactor/epic-6.2-orphan-conversation-deletions`, single impl SHA `6fff2941` | 2026-05-07 |
| Pilot 2 codex review | polecat-codex | `sl-qbfbi` (0 findings → no triage commits) | 2026-05-07 |
| Pilot 2 claude triage | impl polecat (Claude) | `sl-6f0za` (n/a — 0 commits applied) | 2026-05-07 |
| Pilot 2 claude review | impl polecat (Claude) | `sl-5kti3` | 2026-05-07 |
| Pilot 2 PR | refinery merge | PR #460 (merged 2026-05-06T19:10:04Z) | 2026-05-07 |
| Pilot 3 impl bead | impl polecat (Claude) | `sl-kze1c`, branch `audit/epic-6-a11y-2026-05`, impl SHA `0d39ed5d` | 2026-05-07 |
| Pilot 3 codex review | polecat-codex | `sl-yv1mq` | 2026-05-07 |
| Pilot 3 claude triage | impl polecat (Claude) | `sl-fmdth`, triage SHAs `de07aa3a` + `5ce8049d` + `93fdcd8c` | 2026-05-07 |
| Pilot 3 claude review | impl polecat (Claude) | `sl-8dvca` | 2026-05-07 |
| Pilot 3 PR | refinery merge | PR #461 (merged 2026-05-07T18:11:08Z); + 2 downstream operator SHAs `96da8ef0` + `47b76bef` (cspell) | 2026-05-07 |
| Pilot 4 impl bead | impl polecat (Claude) | `sl-zn84a`, branch `audit/epic-6.5-theme-consistency-sl-zn84a`, impl SHA `20304719` | 2026-05-07 |
| Pilot 4 codex review | polecat-codex | `sl-r1hvi` | 2026-05-07 |
| Pilot 4 claude triage | impl polecat (Claude) | `sl-wxlo9`, triage SHAs `fa7a3b79` + `cd64a1a8` + `fd4de194` | 2026-05-07 |
| Pilot 4 claude review | impl polecat (Claude) | `sl-bcumr` | 2026-05-07 |
| Pilot 4 PR | claude-review opened (still open at survey time) | PR #462 (open); + 1 downstream operator SHA `01df971d` (cspell) | 2026-05-07 |

All bead survey done via `gc bd show --rig signal-loom <id>`. PR commit data via
`gh api repos/zookanalytics/signal-loom/pulls/<n>/commits`.

## 1. Pilot inventory

Four pilot tasks, all Epic 6 BMAD follow-ups. All 16 chain beads (4 impl + 12
review) closed. Three PRs merged; one (PR #462) open with one downstream
operator commit awaiting CI / merge.

| # | Story | Impl bead | Branch | PR | State | Codex findings | Triage decisions | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | 6.1 doc trailer | sl-v0nb0 | `gc-gc-toolkit.furiosa-1c1a7af7e181` | #459 | merged 2026-05-06T18:45:51Z | 3 (1 nice, 2 should) | 3y/0n/0defer | approve |
| 2 | 6.2 orphan deletions | sl-a6hjw | `refactor/epic-6.2-orphan-conversation-deletions` | #460 | merged 2026-05-06T19:10:04Z | 0 | 0y/0n/0defer (n/a) | approve |
| 3 | 6.3 a11y audit | sl-kze1c | `audit/epic-6-a11y-2026-05` | #461 | merged 2026-05-07T18:11:08Z | 3 (2 medium, 1 low) | 3y/0n/0defer | approve* |
| 4 | 6.5 theme audit | sl-zn84a | `audit/epic-6.5-theme-consistency-sl-zn84a` | #462 | **open** at survey time | 3 (2 must-fix, 1 nice) | 3y/0n/0defer | approve |

`*` Pilot 3 hit a handoff bug between claude-review push and PR-open; recovered
by a later polecat session (see §5).

### Wall time per phase (impl-bead start to chain-bead close)

Times from bead `started_at` / `closed_at`. The impl phase clock starts at impl
bead `started_at` and ends at codex bead `started_at` (proxying impl-finish);
each subsequent phase is the chain bead's own start-to-close span. Chain total
is the sum of those phase spans.

| # | Impl | Codex | Triage | Claude review | Chain total | Refinery to merge |
|---|---|---|---|---|---|---|
| 1 (sl-v0nb0) | ~1h33m | ~22m | ~10m | ~6m | ~2h11m | ~15h39m (cross-day, refinery scheduled) |
| 2 (sl-a6hjw) | ~21m | ~10m | ~2m | ~6m | ~39m | ~40m |
| 3 (sl-kze1c) | ~20m | ~4m | ~7m | ~9m | ~40m | ~22h27m (recovery + manual cspell fixes — see §3 + §5) |
| 4 (sl-zn84a) | ~15m | ~28m | ~21m | ~4m (after 1h+ idle gap) | ~2h12m | not merged at survey time |

The chain itself runs fast (under an hour for trivial deltas, ~2h for non-trivial)
when nothing goes wrong. Refinery-to-merge wall time is unreliable because of
the downstream-commit gap (§3) and one handoff bug (§5).

## 2. Push-timing learning baseline (already captured in tk-ztapg)

tk-ztapg's notes already encode the push-timing constraint surfaced by Pilot 1:

> The impl polecat opened the PR at end-of-impl (per the bootstrap contract),
> so the PR was live on GitHub through the entire codex review + triage +
> claude review chain. Two triage commits got pushed to the open PR after
> codex's findings, which means GitHub Actions ran multiple times on
> review-driven rewrites — wasted CI minutes.
>
> Updated contract: do not push to origin until claude final review approves.
> All work happens locally on the branch in shared-`.git` worktrees. Origin
> push happens **once, at the end**.

**This survey confirms the baseline holds** for Pilots 2-4 (which all ran
under the corrected contract). Pilots 2-4 all show:

- Single chain push (claude-review is the first to push to origin)
- All chain commits land in one CI run on PR open
- Local-only triage commits are visible in PR commit history because the
  shared `.git` object store preserves them — the operator preference for
  per-commit history is satisfied without per-commit CI runs

**Confirming evidence** (PR commit author = `Zook Bot` for all chain commits;
`John Zook` for downstream operator commits — see §3):

| PR | Chain commits (Zook Bot) | Downstream commits (John Zook) | Total |
|---|---|---|---|
| #459 (Pilot 1, OLD contract) | 4 (2 impl + 2 triage) | 0 | 4 |
| #460 (Pilot 2) | 1 (impl only; 0 triage) | 0 | 1 |
| #461 (Pilot 3) | 4 (1 impl + 3 triage) | **2 (cspell allowlist)** | 6 |
| #462 (Pilot 4) | 4 (1 impl + 3 triage) | **1 (cspell allowlist)** | 5 |

Pilots 2-4 all push exactly once (corrected contract works as designed).

**One refinement for tk-ztapg's metadata gate proposal** (`metadata.push_blocked_until_review_approve = true`):
Pilots 2-4 set `metadata.branch` early but not the gate flag. The chain still
worked because no agent pushed prematurely. The gate flag is useful as a
*defensive* signal for refinery / witness, not a load-bearing primitive — the
chain currently relies on the prose contract telling the impl polecat not to
push, which held across all three subsequent pilots. The flag would matter if
an external agent (e.g., refinery) could otherwise pick up the bead too early;
in practice that did not happen because impl polecats reassigned to the
codex-review bead, not refinery.

## 3. Downstream review-commits gap (the operator-stated gap)

> Operator note 2026-05-07: "Several of the PRs landed already and will have
> had additional commits added based on downstream reviews. Ideally, we're
> getting those steps done within Gas City workflow."

**Confirmed.** Two PRs received human-operator commits after claude-review
approval and outside the chain:

### PR #461 (Pilot 3, sl-kze1c, a11y audit)

```
0d39ed5d 2026-05-06T19:09:20Z Zook Bot   docs: add Epic 6.3 WCAG 2.1 AA audit ...
de07aa3a 2026-05-06T19:28:28Z Zook Bot   docs: triage codex finding #1 ...
5ce8049d 2026-05-06T19:29:26Z Zook Bot   docs: triage codex finding #2 ...
93fdcd8c 2026-05-06T19:30:18Z Zook Bot   docs: triage codex finding #3 ...
96da8ef0 2026-05-06T21:16:33Z John Zook  docs: allow Beads epic id 'yqslv' in cspell for audit doc
47b76bef 2026-05-06T21:24:02Z John Zook  chore: ignore Beads work-item IDs (sl-XXXXX) in cspell
```

Last 2 commits (96da8ef0, 47b76bef): operator manually fixed cspell
allowlist after CI failed on the audit doc, which contained bead IDs
`sl-yqslv` and `sl-XXXXX` that cspell did not recognize.

### PR #462 (Pilot 4, sl-zn84a, theme audit)

```
20304719 2026-05-06T19:02:36Z Zook Bot   docs: add Epic 6.5 theme consistency audit
fa7a3b79 2026-05-06T19:53:52Z Zook Bot   docs: triage codex finding #1 ...
cd64a1a8 2026-05-06T19:55:05Z Zook Bot   docs: triage codex finding #2 ...
fd4de194 2026-05-06T19:56:38Z Zook Bot   docs: triage codex finding #3 ...
01df971d 2026-05-07T18:14:51Z John Zook  chore: allowlist 'hoverable' in cspell
```

Last commit (01df971d): operator manually fixed cspell on the word
`hoverable` (a term coined in the theme audit).

### Pattern

All three downstream commits are **cspell allowlist fixes** triggered by CI
running cspell on doc-only PRs. The chain's self-review gates (`pnpm
type-check`, `pnpm check:lint`, `pnpm test`, `pnpm test:storybook:check`) do
not include cspell. CI does. The audit doc deliverable, by its nature,
introduces new vocabulary (bead IDs, jargon like "hoverable") that triggers
cspell errors.

### What bringing this inside Gas City would require

1. **Gate parity**: claude-review's self-review must include cspell (or
   whatever CI gates the rig actually runs). Currently the chain runs a
   subset of CI checks — gate parity would catch cspell failures pre-push.

2. **Authority to modify config**: cspell allowlist updates are edits to
   `cspell.json` (or equivalent). The chain currently scopes triage commits
   to "accepted findings" — extending scope to "+ CI-config edits required
   to land the change" would let claude-review or triage handle these
   instead of bouncing to the operator.

3. **Refinery escalation path**: when the chain handed sl-kze1c / sl-zn84a
   to refinery, refinery should have detected CI failure and re-routed to a
   polecat (codex or claude) for a CI-fix commit, instead of leaving it for
   the operator. The current refinery flow assumes "claude-review approved
   ⇒ ready to merge"; CI is the gate it cannot bypass on its own.

   Per the rejection-aware pattern in `mol-polecat-work` (rejection_reason
   metadata + branch reuse), refinery already has the primitive — it just
   does not currently use it for CI failure on a PR that the chain
   approved. tk-ztapg's formula could either bake CI-fix into the chain's
   final step or expose a "kick back to claude-triage" rejection path.

4. **Lower-cost option**: project-level cspell config that auto-allowlists
   `sl-`/`tk-`/etc. bead-ID patterns globally. This is a one-time fix that
   would have prevented all three downstream commits in this pilot batch
   without changing the chain at all. (Out of this bead's scope but worth
   surfacing.) Operator's commit `47b76bef` ("chore: ignore Beads
   work-item IDs (sl-XXXXX) in cspell") may already cover this for
   signal-loom going forward.

## 4. Other friction observations

### 4.1 Handoff bug: claude-review push-without-PR (sl-kze1c)

`sl-kze1c` carries `metadata.recovered=true` and
`metadata.recovery_note="claude-review-polecat pushed branch but never opened PR; pr_url metadata stale"`.

The claude-review bead (`sl-8dvca`) closed at 2026-05-06T19:43:51Z with
`close_reason: "Approved. PR #461 opened. sl-kze1c routed to refinery."` —
but the PR was not actually opened. A subsequent polecat session (in
`gc-toolkit.nux` worktree, per `metadata.work_dir`) detected the gap and
recovered it. By the time refinery merged, the bead carried correct
`pr_number=461` and `pr_url`.

**Implication for the formula:** the claude-review step is a multi-action
phase: (a) verdict, (b) push, (c) open PR, (d) update metadata, (e)
reassign. A failure between (b) and (c) leaves the branch on origin with no
PR — invisible to refinery via the bead's `pr_url`, but visible if anyone
greps GitHub.

The current bootstrap relies on the polecat self-reporting "PR #N opened" in
the close reason. The recovery path was ad-hoc. The formula should encode:
- Atomic "push + open PR + record pr_url" or staged with a verifiable
  post-condition (e.g., re-read the bead's pr_url at end-of-step before
  closing).
- A predecessor / refinery-side check: if the impl bead reaches refinery
  without `pr_url` set, refinery should not merge — it should kick back or
  call a recovery agent.

This is the only handoff bug observed across 4 pilots (1 / 4).

### 4.2 Wall-time gaps suggest scheduling friction, not chain-design friction

Pilot 4 (sl-zn84a) shows a 1h+ gap between claude-triage close (19:59:13Z)
and claude-review start (21:01:00Z). Pilot 1 shows a 15h39m gap before
refinery-merge. These are dispatch / scheduling delays, not formula-design
issues — the chain itself is fast when an agent is available. tk-ztapg's
formula will inherit whatever queue/dispatch behavior the runtime offers;
no chain-internal change can compress these gaps.

### 4.3 "4 beads per task" feels right at this scale, but cost is non-trivial

Each pilot used 4 beads (impl + codex-review + claude-triage + claude-review).
For trivial deltas (sl-a6hjw, 0 codex findings, 0 triage commits), the
codex-review and claude-triage beads added overhead with no decision content
(0 findings table = 0 rows). Wall time was small (~12m combined) but bead
overhead is non-zero (Dolt commits per bead, mail / nudges, status updates).

**Two viable options for the formula** (operator's call, per tk-ztapg's
"single-bead UX" goal):
- **Collapse to 1 bead** with `metadata.phase` advanced through the chain.
  Loses some auditability (4 separate close_reasons collapse into a
  single bead's notes / phase log). Saves Dolt cost and bead-management
  overhead.
- **Keep 4 beads per task**. Easier auditing per phase. Higher Dolt cost.
  Possibly skip codex-triage when codex returns 0 findings (collapse just
  the trivial path).

This survey does not pick between them — both are visible from the data.
tk-ztapg's design call.

### 4.4 Codex polecat behavior on prose contracts

Codex review beads were filed with prose contracts in the bead description.
All four codex polecats (sl-5j7i2, sl-qbfbi, sl-yv1mq, sl-r1hvi) honored
the "no PR comments" and "no commits to branch" constraints. Findings landed
in bead notes only. No PR comments were observed across the four pilots.

**Codex prose-contract honor rate: 4 / 4.**

The prose contract format (numbered steps, "CRITICAL" header, explicit
"NO PR comments. NO commits to branch.") was sufficient. The formula can
encode the same constraints structurally (e.g., a polecat-codex agent
that has no `gh pr review` permission, no `git commit` in its allowed
toolkit when in `phase=codex-review`) — but the prose-only bootstrap held.

### 4.5 `bd dep list <this>` predecessor lookup pattern

The chain prose contracts referenced predecessor beads explicitly by ID
(e.g., sl-5kti3 walks the chain via `gc bd show <this-bead-id> --json | jq
-r '.[0].dependencies[] | select(.type=="blocks") | .depends_on_id'`).
This pattern worked across all four pilots — claude-review beads
successfully traced back to triage and codex notes for chain summaries.

**Implication:** the formula does not need a new "previous phase bead"
primitive; the existing `dependencies` graph plus `select(.type=="blocks")`
is sufficient. Encoding this lookup in the formula's claude-review-step
prompt template is straightforward.

### 4.6 PR commit-history fidelity

The corrected contract preserves per-commit history (one commit per chain
phase action). Operator preference is "preserve each individual commit, no
squash on open". PR commit lists confirm:

- PR #459: 4 commits = 2 impl + 2 triage (commits semantically labeled
  "satisfy markdownlint…" / "drop stale diff items" / "name
  computeCategorizedDiff()…")
- PR #461: 4 chain commits + 2 downstream cspell commits = 6 total
- PR #462: 4 chain commits + 1 downstream cspell commit = 5 total

Operator's preference is satisfied. (Not tested: whether refinery's merge
strategy is "merge commit", "rebase merge", or "squash merge"; PR data
shows the head-branch state, not the merge result. SHA differences
between local triage commits and PR commits suggest a rebase happened on
push for some pilots — worth confirming with refinery flow if commit
preservation is a hard requirement.)

## 5. Open questions for the formula design (input for tk-ztapg)

1. **Should claude-review's push + open-PR be atomic, or staged with a
   post-condition check?** Pilot 3's recovery suggests staged with a
   re-read of `metadata.pr_url` before closing; atomic would require a
   single command that does both with rollback on partial failure.

2. **Where does CI-fix authority live?** Either:
   - Add cspell (and full CI gate parity) to claude-review's self-review,
     so the chain catches it pre-push.
   - Add a "CI-fix" rejection path on refinery that bounces the bead back
     to claude-triage with `metadata.rework_reason="ci-failure: <kind>"`.
   - Project-level allowlist for bead-ID patterns (out of formula scope but
     captures the recurring case).

3. **Single-bead vs 4-bead tradeoff.** tk-ztapg's design pad already
   leans toward "collapse to 1 bead with `metadata.phase`". This survey
   confirms the 4-bead overhead is real but bounded; the data does not
   force the decision either way.

4. **`metadata.push_blocked_until_review_approve` gate flag.** Pilots 2-4
   worked without it. Defensive value only. Whether to include it depends
   on whether tk-ztapg's design assumes external agents (refinery,
   witness, deacon) need a discoverable signal vs. trusting the prose
   contract. Pilots 2-4 had no incidents from missing this flag.

5. **Codex review skip-on-no-findings.** When codex returns 0 findings
   (as in Pilot 2), the claude-triage step is essentially a no-op. The
   formula could either keep it for symmetry or short-circuit to
   claude-review on `codex_findings_count == 0`. This is a small
   optimization with a small downside (loss of audit symmetry).

6. **Refinery PR-presence pre-check.** Should refinery refuse to merge a
   bead lacking `metadata.pr_url`, or detect the missing PR and re-route?
   Pilot 3 recovered through ad-hoc means; the formula could codify this
   as either a hard refinery precondition or a re-route step.

7. **SHA preservation across push.** Some pilots (1, 3) show SHA
   mismatches between locally-recorded commit SHAs in chain notes and
   what appears in the GitHub PR; Pilot 2's single commit kept the same
   SHA. If "preserve commit history" is a hard requirement, the formula
   should specify a non-rebasing push and refinery merge strategy.
   Otherwise, the operator-visible commit messages are preserved (good
   enough for human review) but SHAs are not.

## Out of scope (per bead description)

This doc deliberately does not:
- Design the formula (that's tk-ztapg)
- Re-run the pilots
- Propose changes to the bootstrap pattern in flight
- Address heavy CI / infrastructure changes
- Discuss cross-rig CI parity beyond the cspell case in §3
