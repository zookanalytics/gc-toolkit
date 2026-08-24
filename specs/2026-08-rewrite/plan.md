---
name: Rewrite plan — gc-toolkit as a workflow-shaped pack
description: The binding design for the 2026-08 ground-up rewrite. Target tree, the declared state space, the writer for every transition, what is kept / absorbed / deleted and why. Supersedes specs/tk-z9nln/consolidation-plan.md (which proposed incremental consolidation and explicitly declined a rewrite; the operator has since ordered the rewrite).
---

# Rewrite plan

Operator decisions (2026-08-24): in-place replacement on the rewrite branch;
native agent roster (no gastown import); keep the feedback/learning loop,
the gascity-keeper sub-pack, and the seed-audit machinery; prune specs/ to
keepers. `docs/foundation.md` is unchanged and remains the pack's charter.
`docs/component-model.md` §1–§3 is the design authority this plan implements:
the primitive list, the single state machine, and invariant→check binding.

## Design rules

1. **The pack is its workflows.** Gas City is a workflow engine. Every
   component belongs to a named workflow (work, review, merge, visit,
   feedback, patrol) or is a declared shared primitive. Nothing exists
   "because an incident happened"; incidents are closed by fixing a writer.
2. **Declared state space, one writer per transition.** `lifecycle/` declares
   the anchor state machine and the metadata-key registry.
   `assets/scripts/lifecycle.sh` is the only thing that writes a lifecycle
   transition: validate → one atomic `bd update` carrying every field of the
   transition → read back. (A single `bd update` invocation is atomic —
   docs/gascity-routing-model.md row 46; the healers existed because today's
   writers split transitions across calls.)
3. **Writers complete their own transitions; no healer category.** The only
   reconcile passes that survive react to *external* facts the pack does not
   write (GitHub closing/retargeting a PR; a session dying). A dead session
   is handled by one recovery path — witness orphan recovery — which works
   because rule 2 makes every transition all-or-nothing.
4. **Gates are evidence-bound and single-writer.** `check.<g>=<verb>@<oid>`
   is written only by `signoff.sh` (verdicts) and cleared/re-armed only by
   the merge cadence. The merge condition is unchanged: every declared gate
   `green@<live head>`.
5. **Mechanical work runs without an LLM.** Formula steps cannot execute
   without an agent (docs/gascity-packs.md §3), so anything that is
   timer+query+write is an exec order or a script an agent invokes as one
   call. Formulas carry judgment only.
6. **Comments document usage, not incidents.** A file's header states its
   job, contract, and callers. Constraints the code cannot show get one
   line naming the constraint (not the incident). History lives in git and
   in pruned specs/.
7. **Every invariant names its check.** doctor/ contains only live,
   structural checks (component-model I2–I10 plus addressing/config
   integrity). Per-incident source greps are deleted; shell hygiene moves
   to `tools/lint-learned.d/`-style lint, out of `gc doctor`.

## Target tree

```
pack.toml                      # native roster; no imports
lifecycle/
  lifecycle.toml               # states, transitions, metadata registry, gate vocabulary
docs/                          # foundation (verbatim), rewritten architecture/state docs,
                               # gascity-*.md runtime briefs kept
agents/
  polecat/     refinery/   witness/   deacon/
  converse/    mechanik/   polecat-codex/   proactive/
formulas/
  mol-polecat-work.toml        # extends core mol-polecat-base; lean
  mol-refinery-patrol.toml     # judgment only; cadence lives in the order
  mol-witness-patrol.toml      # orphan/liveness recovery only
  mol-deacon-patrol.toml       # infra health only
  mol-visit.toml               # unchanged in substance
  mol-first-reaction.toml
  mol-feedback-miner.toml  mol-feedback-distiller.toml
orders/
  refinery-reconcile.toml  deferred-dispatch.toml  reconcile-rig-checkouts.toml
  liveness-sweep.toml (condition; now fully exec)   quota-park-nudge.toml
  boot-health.toml  helm-build.toml  feedback-miner.toml  feedback-distiller.toml
assets/scripts/
  lifecycle.sh                 # the transition writer
  refinery-reconcile.sh        # cadence driver (~100 lines)
  gate-ensure.sh               # gate satisfiability (successor to check-set-heal phase 1)
  pr-open.sh                   # pre_open_gate → pull_request
  merge.sh                     # validate → merge → record (successor to merge-skill)
  pr-facts.sh                  # external PR events: abandoned / retargeted / conflict / stale gate
  convoy-graduate.sh
  signoff.sh                   # the review verdict writer (successor to polecat-non-impl-done)
  step-close.sh  deferred-dispatch.sh  worktree-setup.sh          # kept, trimmed
  escalate.sh                  # one open visit per situation (successor to escalation-gate + mails)
  liveness-sweep.sh  liveness-sweep-precheck.sh  liveness-recheck.sh
  gc-helm.sh                   # takeaway/open/react only; board = helm-svc
  gc-visit-open.sh  converse-claim.sh  bead-rehome.sh  gc-bd-watch.sh
  quota-park-nudge.sh (reduced)  boot-health.sh (reduced)
  gc-helm-build.sh  gc-helm-svc.sh  gc-terminal-attach.sh
  tmux-*.sh  gc-toolkit-status-line.sh  render-seed-audit.sh
doctor/                        # 9 structural checks (see below)
template-fragments/            # shared doctrine only (see below)
overlays/ (cycle-recycle, work-context)   skills/ (5)   services/helm/
packs/gascity-keeper/          # kept; prompt + formulas trimmed
tools/                         # gc-bd-universe.sh, gc-proactive.sh, lint-learned*, upstream-gc-sync.sh
```

## The state machine (lifecycle/lifecycle.toml)

Anchor state = runtime `status` × pack `merge_result` (key name kept for
ledger continuity; the enum is now closed and every writer is named).

| merge_result | status | meaning | written by |
|---|---|---|---|
| (absent) | open | not yet a merge anchor | — |
| pre_open_gate | open | branch pushed, gates armed, no PR | mol-refinery-patrol merge-push (via lifecycle.sh) |
| pull_request | open | PR open, awaiting gates+merge | pr-open.sh; merge-push (post-open path) |
| merged | closed | landed, `merged_sha` recorded | merge.sh |
| abandoned | open→human | PR closed unmerged externally | pr-facts.sh |
| retargeted | open→human | PR base moved externally | pr-facts.sh |
| blocked | open→human | recorded `existing_pr` unusable | mol-refinery-patrol |
| refused_false_completion | open→human | no commits on branch | mol-refinery-patrol |

Rejection (`rejection_reason` + re-route to pool) is a transition back to
unanchored, written by mol-refinery-patrol or signoff.sh (rework child path).
Unknown `merge_result` values are illegal: every reader treats them as an
error surfaced via escalate.sh, and doctor `check-state-space` catches them
(closes component-model I2).

Gate vocabulary (unchanged semantics, single writer):
`check_set` = comma list, default `codex`; sentinel `none` = explicit opt-out;
`check.<g>` = `green|fixable|exception@<oid>`; `approval` satisfied only by an
external APPROVED review. Merge requires every gate `green@<live head>`,
no unclosed rework/review child, base == `merged_target`, CLEAN, no holds
(`merge_hold`, `rebase_hold`, `tracking_only`).

Metadata registry: lifecycle.toml enumerates every pack-written key. The
healer-bookkeeping keys (`*_healed`, `*_heal_flagged`, `reopened_not_landed`,
`stranded_branch_*`, `stale_gate_*`, `anchorless_flagged`, `close_failures`,
`close_escalated`, `gate_verdict_condemned`, …) are deleted with their
writers.

## The merge cadence (orders/refinery-reconcile.toml, 60s, rig-scoped)

Driver + 5 arms, same load-bearing order, single-flight from the runtime:

1. **gate-ensure.sh** — every gating anchor declares a non-empty check_set
   (stamp the default when absent; `none` respected) and every declared gate
   is *raisable*: marker green at live head, or a live routed review bead
   in flight, else dispatch one (stamp first, then dispatch; read back the
   route). rc=3 holds merge.sh for the pass. Successor to check-set-heal
   phase 1; phases 0/0a die with rule 2.
2. **pr-open.sh** — for each `pre_open_gate` anchor with `check.codex ==
   green@<live head>`: adopt an existing PR for the branch or `gh pr create`
   non-draft, re-read the created PR by number, refuse a moved head, replay
   the verdict as a comment (never an approval), then one lifecycle.sh
   transition to `pull_request` carrying pr_url/pr_number/merged_target.
3. **merge.sh** — for each `pull_request` anchor: pinned `gh pr view`,
   identity gates (same repo, not fork, head branch matches), re-read the
   anchor, validate holds/gates/children/approval/base/CLEAN, re-read the
   full authorization set immediately before merging, `gh pr merge --squash
   --match-head-commit <validated oid>`, then close + record via one
   lifecycle.sh call. One-anchor-per-PR is checked structurally by doctor
   (I4); merge.sh still refuses on sight as fail-closed defense.
4. **pr-facts.sh** — external facts only: PR merged out-of-band (record),
   closed-unmerged (→ abandoned + visit), base changed (→ retargeted +
   visit), CONFLICTING (file one rework child per head), gate green at a
   stale head (file one re-review child per head), hold-resolved retraction.
   No merge authority.
5. **convoy-graduate.sh** — unchanged contract: all members closed AND ≥1
   recorded merge onto the integration branch AND no hold/branch veto →
   assignee=refinery, branch=integration/<id>, merge_strategy=mr.

## The review/signoff workflow

Review beads (`task_kind=review`, `check_name`, `anchor_bead`, review_
branch/base or pr_number) are routed to the polecat-codex pool. Its prompt
(~80 lines) is purpose-written for reviews: read the dispatch, review per
skills/signoff-review, then run
`signoff.sh --review-bead <id> --verdict approve|request-changes` once.
signoff.sh owns all mechanics: post the artifact (`gh pr review --comment`
post-open; notes with `reviewed_oid` pre-open), stamp `check.<g>=green@<oid>`
with read-back, or file+sling one rework child and clear the marker; enforce
the round cap (default 3) by writing `exception@<head>` and routing the
anchor to human; dismiss the city's own superseded blocking review
(`signoff_dismissed`). This replaces template-fragments/polecat-non-impl-done
(1,209 lines) and reconcile-gate-verdicts.sh (1,010), and closes I7's surface
to one audited writer.

## The human surface

Unchanged model: subject/visit/takeaway on native primitives
(docs/gascity-human-engagement.md). mol-visit and the gate-visit block are
kept as the canonical entry point. converse keeps its claim/hold/record
loop. Escalation is unified: **escalate.sh files or refreshes exactly one
open visit per situation key** — replacing escalation-gate.sh (1,222 lines)
and patrol mails to a mayor that no longer exists. The board is
services/helm (kept as-is); `gc-helm.sh` keeps only the write verbs
(takeaway/open/react) and `tmux-pick-helm.sh` renders via
`helm-svc board --json`. The board remains render-only: everything works
without it.

## Roster

Native agents: **polecat** (worker pool), **refinery** (merge judgment
patrol), **witness** (rig recovery patrol: orphaned beads, stalled
workflows), **deacon** (city infra patrol: dolt health, doctor sweep),
**converse**, **mechanik**, **polecat-codex** (review pool), **proactive**
(default-disabled). Dropped: boot (boot-health order already owns
detection), mayor (escalations are visits; dispatch doctrine lives in
mechanik's prompt and docs), dog (was gastown's), _polecat-gemini (dead).
Prompts are purpose-written and lean; the layered-startup-discovery
fragment set dissolves into each patrol prompt's own startup-adopt section
(wisp queries with `--include-infra`, title-keyed adopt-before-pour).

## What is deleted, and what replaces it

| Deleted | Lines | Replaced by |
|---|---|---|
| check-set-heal.sh phases 0/0a + tests | ~2,200+ | atomic transitions (lifecycle.sh) |
| quiesce-completed-workflows.sh + test | 2,099 | step-close.sh wired into mol-polecat-work submit |
| recover-stranded-branches.sh + test | ~1,800 | single atomic handoff write + witness orphan recovery |
| reconcile-merged-prs.sh (backstop half) | ~1,500 | merge.sh records atomically; external half → pr-facts.sh |
| reconcile-gate-verdicts.sh + test | ~1,600 | signoff.sh (verdict writer) + gate-ensure re-arm |
| escalation-gate.sh + test | ~2,000 | escalate.sh (~150) |
| detect-stalled-workflows.sh, detect-parked-dispositions.sh + tests | ~2,600 | witness patrol step + liveness-sweep.sh (graph queries) |
| polecat-non-impl-done fragment | 1,209 | signoff.sh + polecat-codex prompt |
| layered-startup-discovery fragments | 550 | native prompt sections |
| mol-liveness-sweep formula | 1,313 | liveness-sweep.sh exec order (precheck kept) |
| mol-triage-recurrence + order | ~270 | folded into liveness-sweep.sh |
| mol-doc-keeper-* formulas + orders | ~700 | dropped (operator scope decision) |
| gc-helm.sh board half + contract_parity_test.go (cmd) + board tests | ~2,400 | helm-svc board |
| gastown import + 6 agent patches + shadow mirrors | — | native roster |
| 21 per-incident doctor checks | ~5,000 | 9 structural checks |
| skills/demo-capture + gc-demo-script | 777 | dropped |
| dead scripts (burn-watch, backfill-operator-origin, patrol-spend-split, tmux-switch-to-session, resolve-salvage-branch) | ~900 | — |

## doctor/ (the check set)

| Check | Invariant | Reads |
|---|---|---|
| check-state-space | I2 — every merge_result value and status combo is declared in lifecycle.toml | ledger |
| check-routed-work-claimable | I3 — every route AND assignee names a live target; rig-scoped orders bound | ledger + gc |
| check-one-anchor-per-pr | I4 | ledger |
| check-closed-implies-landed | I5 — closed anchor ⇒ merged+merged_sha or explicit terminal | ledger + gh |
| check-gate-integrity | I6+I7 — gating anchors declare check_set; markers well-formed `verb@oid` | ledger |
| check-step-terminal | I8 — no open step under a closed root; no frontier stalled > bound | ledger |
| check-cadence-live | I10 — every pack order fired within its interval | gc order history |
| check-config-bound | prompts/overlays/fragments resolve in resolved config | gc config |
| check-seed-audit-current | generated artifact freshness (warn-only if absent) | source |

Each: doctor.toml `description` (one sentence + invariant id), run.sh with
0/1/2 exits, first-line message, self-bounded probes, unreadable ≠ pass.

## Verification in this environment

No running city or `gc` binary is available. Verification is: `bash -n` on
every script; focused `.test.sh` suites with stubbed `gc`/`bd`/`gh` binaries
for lifecycle.sh, the five cadence arms, signoff.sh, escalate.sh,
liveness-sweep.sh (the stub-harness pattern already used by the repo's
tests); `go test ./...` under services/helm after the parity-test change;
TOML parse checks. generated/seed-audit is emptied with a README pointer —
it re-renders on first install (`render-seed-audit.sh --install-hook`), and
check-seed-audit-current warns rather than errors when absent.

## specs/ pruning rule

Keep: this plan, bead-universe/ (live authority for phases 2/4),
tk-h9pq5/ (converse design authority), 2026-08-fresh-start/,
2026-08-learning-system/, tk-z9nln/ (the audit this rewrite answers).
Delete: per-bead incident dirs not cited by any kept doc, formula, script,
or agent prompt (verified by grep before deletion). Git history keeps all.
