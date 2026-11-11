---
name: Memory backlog triage by the operator's three questions (tk-zlot608.1)
description: Every note in the gc-toolkit rig's agent memory store, sorted by the operator's three questions. Read it to remove the point-in-time notes (tk-zlot608.3), to apply the wording fixes (tk-zlot608.4), or as the worked example for the standing triage (tk-zlot608.2).
---

# Memory backlog triage by the operator's three questions

This record sorts the gc-toolkit rig's agent memory store, note by note, by the
three questions the operator gave in conversation tk-1amy8sd on 2026-11-11:

1. "Which memories are effectively point in time knowledge that can go away"
2. "Which memories are clear examples of vague or misleading directions that
   can be fixed with effectively zero increase in instruction size. These can
   be fixed even if they were only recorded once."
3. "Which memories are indication of something structurally wrong that needs a
   larger fix. Agents regularly getting confused where a script or more robust
   instructions would have them do the right thing the first time. This is
   where we are balancing scope of fix against severity, since the claim here
   is something that is off."

It changes nothing in the store or the pack. Merging it releases two beads
that wait on it: tk-zlot608.3 removes the whole notes listed under
[Point-in-time notes](#point-in-time-notes), after it copies the store, and
tk-zlot608.4 applies the [wording fixes](#wording-fixes). The answer each
question needs follows the reading the filing sitting gave on the work bead,
which is open to the operator's review.

## Summary

The store was read from a copy taken at 2026-11-11T21:01:17Z, with main at 6337a480c.
It held 1,455 files: the index (`MEMORY.md`), 34 collection notes
(`hub-*.md`) and 1,420 whole notes. A collection note is sorted entry by
entry. Its lines that link a whole note stand for that note, which has its own
row, so the sorted units are the 1,420 whole notes and the
741 entries that carry text of their own. The index holds pointers
only and is not sorted.

| Answer | Whole notes | Entries of collection notes | All units |
|---|---:|---:|---:|
| Point-in-time (question 1) | 413 | 116 | 529 |
| Live work | 87 | 37 | 124 |
| Wording fix (question 2) | 7 | 0 | 7 |
| Structural (question 3) | 61 | 70 | 131 |
| Fits none | 852 | 518 | 1,370 |
| All | 1,420 | 741 | 2,161 |

- **Live work** is a note about work that is still open. It is not question 1
  yet, and each one is listed with its bead.
- **Fits none** is a note that answers none of the three questions, such as a
  durable fact about a tool or a recipe that still holds. [Notes that fit
  none](#notes-that-fit-none) says what they are.
- 257 units record a ruling they attribute to the operator. Their
  rows in [notes.tsv](notes.tsv) give the source each one claims. A mark is
  kept only where the unit's own text names the operator.
- 182 units are about code the deletion schedule retires (tools/deletion-plan.tsv). Their rows name the retiring bead.

How far to trust it:

- A blind check of 40 whole notes the first pass called point-in-time, drawn at
  random, kept 6 of them. Each still held a recipe, a rule or a ruling the pack
  lacks. A second check of every whole note sorted as point-in-time, 546 in
  all, then kept 133, including those 6, so the list below holds only the
  413 notes both checks call point-in-time.
- Each wording fix was read against main by hand, and its words were cut to
  about zero change in size.
- The structural findings were grouped in one pass that read the repository
  for what each fix would touch and whether the pack had fixed it already.

## Point-in-time notes

These 413 whole notes are point-in-time knowledge that can go away.
Each one is a record of finished work, says what no longer holds, repeats an
instruction the pack already carries, or records one moment's state. Their
rows in [notes.tsv](notes.tsv) say which, and why. tk-zlot608.3 removes them.
The `sha256` column holds the first 12 hex characters of each file's hash at
the copy, so a note whose hash differs now has changed since and is skipped.


```text
MEMORY-hooks-archive
anchor-to-molecule-steps-reverse-walk
approval-scope-recheck-convoy-held-superseded
approved-pr-needs-attention-label-often-pending-required-ci
armed-follow-up-absorbed-by-rework-disarm-and-duplicate-of
armed-held-subject-keeps-arm-signoff-releases-unrouted
bare-rework-bead-hold-mechanism
bare-work-bead-claim-with-shadow-molecule
bring-current-guard-approval-cost-and-stamp
built-once-schedule-row-removed-by-the-landing-pr
claim-release-rework-and-rebased-build-check-2026-11-05-state
claude-session-scratch-tree-ownership-signals
claude-temp-dir-edquot-dont-sweep-tasks-spool
close-the-claimed-bead-not-gc-trigger-bead-id
closed-rework-child-redispatched-is-a-husk
conversation-merge-hold-tk-icol3l8-state
converse-board-sentence-140-cap-holding-prefix
converse-framing-orient-first-what-the-subject-is
converse-hold-and-signoff-exceed-120s-run-in-background
converse-iterate-document-skill-tk-cj4ke94
converse-land-and-iterate-clears-both-escalation-arms
converse-native-gates-design-tk-0ur8r9p
converse-no-work-disposal-ordering-held-subject
converse-pane-bounce-is-the-sittings-own-drain-ack
converse-retire-dispose-anchor-before-closing-pr
converse-retire-redispatch-same-bead-execute-not-drain
converse-signoff-before-dispose-held-no-work-subject
converse-signoff-route-human-when-funding-sibling-work
converse-sitting-end-v2-stop-done-tab-tk-7w7qdls-state
converse-sitting-visit-holds-its-pr-merge
convoy-graduation-can-be-vacuously-complete
convoy-membership-parent-edge-readers-map
deacon-findings-key-duplicates-older-doctor-check-tracker
dead-molecule-husk-reaper-is-dead-molecule-sweep-order
decline-copies-one-call-tk-qitjxcm-state
deferred-dispatch-cap-is-usually-order-timeout
delivery-unit-2-filing-tk-wmwcdlc-3-2-state
delivery-unit-4-landed-delivery-row-tk-wmwcdlc-3-4-state
demo-capture-proof-attach-browser-only
demo-check-rig-standard-tk-6bbqxxw-state
design-convoy-936-held-universal-approval-ruling
design-summary-flags-our-definitions-as-feature-or-debt
diff-scoped-lint-control-needs-the-old-base
direct-routed-premise-falsified-park-to-human
dismiss-and-visit-close-never-discharge-a-hold-demand
dispatch-unit1-raw-routes-gc-sling-tk-1tfzr71-57-state
dispatch-unit3-gate-alone-parks-tk-1tfzr71-62-state
dispatch-unit5-human-route-clear-tk-1tfzr71-63-state
dispose-timeout-writes-already-landed
disposition-cutover-rerun-tk-1tfzr71-53-state
docs-gascity-directory-layout-and-old-name-map
doctor-cannot-determine-sibling-fixes-not-uniform
doctor-order-firing-current-often-transient
doctor-visit-outcome-recorded-witness-refinery-stuck-never-retracts
dolt-backup-torn-restore-and-producer-fix
dolt-tk-saturation-helm-lite-cut-and-attribution
double-dispatch-repool-preserve-predecessor-work
duplicate-dispatch-late-peer-branch-collision
duplicate-rework-twin-inert-orphan-proceed-and-notice
editing-prompt-fragment-formula-requires-seed-audit-regen
epic-create-hypothesis-tk-wmwcdlc-7-state
executor-identity-residue-producer-is-proactive-release-path
feedback-distiller-order-can-double-pour
feedback-miner-dedup-same-finding-different-slug
feedback-routing-owed-on-dirty-pr-is-missing-stamp
findings-files-out-of-agent-homes-tk-irp6lb4-state
first-reaction-blocked-exit-collides-with-an-until-edge-on-the-same-pair
first-reaction-dispose-reaps-molecule-skip-trailing-step-close
first-reaction-dispose-release-quiesces-husks-close-held-step
first-reaction-dispose-release-reaps-whole-molecule-on-exit0
first-reaction-dispose-resume-reuse-visit-verify-stamps
first-reaction-dispose-slow-never-rerun-double-files
first-reaction-husk-fix-lives-in-the-formula-guard
first-reaction-husk-restamp-does-not-finalize
first-reaction-integration-target-unwired-bead-is-mechanik-effort-wiring
first-reaction-moot-duplicate-dispatch-hold-actionable-store-only-repair
first-reaction-never-closes-invariant
first-reaction-operator-capture-duplicates-parked-epic-member-is-ruling
first-reaction-operator-topic-under-intake-hold-is-recommend
first-reaction-parked-upstream-send-ruling-on-existing-visit
first-reaction-problem-in-retired-code-until-edge-on-retiring-bead
first-reaction-recommend-keep-status-quo-via-mol-validate-close
first-reaction-reoffer-card-written-dispose-not-run
first-reaction-resolve-target-from-own-root-input-convoy
first-reaction-stranded-between-card-and-disposition
first-reaction-subject-closed-as-duplicate-mid-reaction
first-reaction-subject-deacon-dedup-closed-mid-reaction
first-reaction-subject-is-stranded-graphv2-step-of-finished-molecule
first-reaction-subject-superseded-closed-is-unguarded-husk
first-reaction-target-duplicates-dormant-backlog-bead
first-reaction-target-duplicates-in-flight-twin-block-plus-duplicate-of
first-reaction-target-subsumed-by-newer-broader-cause-bead
fix-target-bead-is-impl-not-review
fixed-must-fix-finding-open-is-pass-latency-not-wedge
formula-vars-with-load-bearing-empty
gascity-precommit-gate-cannot-pass-toolchain-split
gascity-routing-doc-line-anchors-drift-with-every-fork-move
gate-marker-fixable-does-not-mean-findings
gate-visit-drift-test-couples-copies-executes-only-canonical
gc-helm-and-gc-proactive-fail-lint-on-main-any-edit-fails-branch
gc-helm-engage-closed-conversation-tk-2w86gqo-state
gc-helm-release-quiesce-walks-all-open-roots-slow
gc-helm-takeaway-release-quiesce-slow-not-hung
gc-toolkit-465-rewrite-detection-is-doctor-checks
gc-toolkit-go-test-edquot-shm-workaround
gc-toolkit-lint-command-town-citytoml-shadows-formula-default
gc-toolkit-pack-ci-skips-go-test-and-web-tsc
gctk-fallback-drop-two-arm-suite-was-the-parity-pin
gctk-paced-arm-port-mirror-gh-argv-and-fixture-renumber
gctk-rig-gated-test-under-stripped-env-loses-publish-keep-gc-home
gh-origin-guard-reads-heredoc-bodies-as-commands
github-label-description-change-needs-gh-label-edit
goal-initiative-standing-coordination-sitting
graduation-convoy-resume-inline-on-convoy-bead
graphv2-polecat-chain-close-unassigned-steps
graphv2-terminal-chain-close-loses-next-step-to-live-pool-worker
held-state-removal-tk-1tfzr71-37-state
helm-board-bead-state-derivation-holds-and-twin-order
helm-board-design-pass-armed-behind-936
helm-board-render-path-unified
helm-go-tests-run-by-no-gate-and-parse-review-demo-doc
helm-pr-state-two-axes-machine-vs-label
helm-ux-epic-coordination-point
hold-markers-reach-anchors-only-refinery-handoff-needs-blocks-edge
host-takeaway-stamp-does-not-quiesce-molecule
husk-reaper-sweep-objection-declinable-on-merits
i5-hits-are-hand-closed-drops-suspended-skip-hides-them
interrupted-tool-call-may-have-run-read-store-before-rerun
kfte3b-dismiss-gate-bring-current-round-record
legacy-non-gate-demands-live-in-stores
lifecycle-fix-needs-both-shell-and-gctk-port
live-claude-sessions-from-proc-environ
liveness-census-visit-freezes-sweep-read-pass-log
load-context-duplicate-check-misses-submitted-first-dispatch
load-context-gate-snapshot-stales-during-long-investigation
main-red-pool-nudge-wiring-carried-on-pr1320
mechanik-prime-cap-tk-ufmime2-state
merge-arm-landing-rate-tally-from-pass-log
merge-does-not-reap-redundant-double-dispatch-molecule
merge-hold-on-cancelled-rework-husk-resling-it
merge-model-resume-loops-a-rebase-based-refinery-check
merge-ordering-fix-bead-not-commit-fixable
merge-skill-can-silently-skip-a-fully-green-anchor
merged-close-sheds-live-objections-lifecycle-transition
mol-dog-stale-db-close-loop-fixed-upstream-residual-is-scratchpad-cwd
mol-first-reaction-inline-execution-and-chain-close
mol-first-reaction-inline-step-rehomes-to-sibling-during-long-gap
mol-first-reaction-molecule-reaped-midflight-retirement
mol-first-reaction-reoffered-step-grabber-releases-claim
mol-polecat-work-graphv2-inline-execution
mol-validate-human-batch-rule-mustfix-when-visit-already-surfaced
molecule-hold-blocked-step-is-intentional-not-stranded
moot-visit-close-leaves-reacted-subject-a-permanent-strand
native-gates-cutover-follow-up-tk-1tfzr71-33-state
native-gates-landing-correctness-round-tk-7t031w0
native-gates-unit-d-cutover-build-tk-o6pd01i
native-hold-correctness-rework-tk-k91bsep-state
native-hold-effort-summary-tk-rl8gz4b-31-state
native-hold-landing-bring-current-tk-rl8gz4b-28-state
native-hold-landing-fourth-bring-current-tk-ubwxe4x-state
native-hold-landing-second-bring-current-tk-4mweu4g-state
native-hold-landing-third-bring-current-tk-io7nijk-state
native-hold-rework-tk-8c4i969-correctness-round-state
native-hold-rework-tk-sx898vs-po-opening-state
native-hold-unit-2-tk-rl8gz4b-33-state
native-hold-unit-3-tk-rl8gz4b-34-state
native-hold-unit-5-tk-rl8gz4b-36-state
native-hold-unit-6-tk-rl8gz4b-37-state
new-city-pr-comment-writer-trips-unengaged-threads-hold
no-code-first-reaction-bead-has-no-clean-termination
one-bead-pr-model-design-tk-0erzikn
one-definition-what-holds-a-pr-tk-1sks8ez-state
one-repeatable-epic-review-tk-wmwcdlc-9-state
operator-pack-review-skills-carry-no-gc-toolkit-rule
override-base-prompt-via-append-fragment
pack-tests-have-no-auto-discovery
per-bead-tree-removed-at-handoff-tk-1tfzr71-43-state
plan-first-ruling-schedule-members-p1-lane-a-armed
pm-trigger-and-foundation-summary-line-tk-ipalnq1-state
polecat-done-sequence-hardcodes-target-main
polecat-duplicate-of-in-flight-peer-hold-and-drain-molecule
polecat-filing-bead-ends-at-rehome-not-yours
polecat-fold-refinement-into-mr-pr
polecat-handoff-atomic-write-blocked-by-own-claim
polecat-wakes-into-already-quiesced-standdown-molecule
polecat-wakes-on-demand-gate-relocated-standdown-husk
polecat-wakes-on-preopen-husk-with-unclaimed-rework-child
polecat-wakes-on-signoff-cap-parked-preopen-bead
pr-body-placeholder-never-rerendered
pr-d3dxec-converse-fold-cross-store-bring-current-round-record
pr-facts-routes-no-feedback-batch-without-a-pr-head
pr-hl17x4i-refinery-detached-gate-bring-current-round-record
pr-loop-blind-spots-issue-comments-and-red-checks
pr-model-unit-b-landing-bead-hold-readers-tk-rf8xr8a
pr-model-unit-c-implementation-tk-ii7o77n
pr-model-unit-d-guard-deletion-tk-9vv7nkg
pr-model-unit-e-banner-label-deletion-tk-uazul3l
pr-stack-arm-rotation-rate-half-a-day
pr-status-held-behind-a-persons-move-tk-ikpyzn-14-state
pr-title-bug-prefix-double-typed-by-cc-title
pr-writeback-marks-tk-fspfp2-bring-current-round-record
pr1015-rig-demo-mol-bring-current-round-record
pr1019-gate-visit-reuse-bring-current-round-record
pr1027-visit-close-fragment-bring-current-round-record
pr1032-feedback-child-under-hold-bring-current-round-record
pr1047-lease-heartbeat-bring-current-round-record
pr1051-recorded-no-verdict-bring-current-round-record
pr1052-fold-merge-hold-bring-current-round-record
pr1054-bead-id-citation-cleanup-bring-current-round-record
pr1055-escalate-subject-class-bring-current-round-record
pr1067-dispatch-path-bring-current-round-record
pr1068-registry-keys-bring-current-round-record
pr1069-check-refinery-resolve-bring-current-round-record
pr1073-supersession-guard-bring-current-round-record
pr1075-work-outcome-stamp-bring-current-round-record
pr1085-witness-notice-finding-bring-current-round-record
pr1086-id-read-guard-bring-current-round-record
pr1087-twin-pass-review-round-record
pr1088-finding-comments-bring-current-round-record
pr1089-convoy-target-guard-bring-current-round-record
pr1102-doc-filing-bring-current-round-record
pr1103-back-lane-one-write-bring-current-round-record
pr1105-engage-alias-held-bring-current-round-record
pr1106-converse-rework-bring-current-round-record
pr1111-formula-unquoted-for-bring-current-round-record
pr1112-demo-visual-check-bring-current-round-record
pr1115-bead-context-frontier-bring-current-round-record
pr1116-converse-retire-bring-current-round-record
pr1123-finding-upsert-one-write-bring-current-round-record
pr1126-run-tests-tree-scope-bring-current-round-record
pr1128-docs-page-rubric-bring-current-round-record
pr1150-stale-gate-review-round-record
pr1158-work-quality-b80kkz-bring-current-round-record
pr1163-seed-audit-shared-names-bring-current-round-record
pr1166-patrol-finding-sibling-gate-bring-current-round-record
pr1168-gh-origin-guard-pick-bring-current-round-record
pr1172-work-tree-holder-bring-current-round-record
pr1174-molecule-hold-waiting-steps-bring-current-round-record
pr1175-converse-signoff-fail-closed-bring-current-round-record
pr1176-store-pinned-visits-bring-current-round-record
pr1183-witness-map-session-list-bring-current-round-record
pr1186-step-close-convoy-bring-current-round-record
pr1189-rig-check-commands-bring-current-round-record
pr1190-direct-run-parts-bring-current-round-record
pr1193-deferred-followup-reuse-bring-current-round-record
pr1207-dispatch-path-guard-rebuild-round-record
pr1209-repo-artifact-bring-current-round-record
pr1212-merged-work-record-bring-current-round-record
pr1213-gc-build-bring-current-round-record
pr1216-takeaway-headline-readback-bring-current-round-record
pr1223-pr-finishing-priority-bring-current-round-record
pr1229-video-modality-bring-current-round-record
pr1232-check-cadence-live-one-read-bring-current-round-record
pr1237-rejection-repool-bring-current-round-record
pr1238-park-move-bring-current-round-record
pr1249-run-cancel-bring-current-round-record
pr1250-fold-successor-lookup-bring-current-round-record
pr1251-review-comment-shape-bring-current-round-record
pr1319-rig-root-bring-current-round-record
pr1385-held-gates-walk-bring-current-round-record
pr1411-step-number-citation-rework-tk-aupk2t2-state
pr936-design-convoy-graduation-bring-current-round-record
pr977-epic-gate-bring-current-round-record
pr995-conversation-axis-rework-round-record
pre-open-rework-prepare-mode-on-anchor-not-child
pre-rewrite-bug-may-target-a-deleted-healer
preexisting-failure-dedup-matches-wrong-bead
preexisting-failure-tracker-verify-against-current-main
preopen-rework-fix-is-a-referenced-beads-content-store-only
preopen-rework-mainrun-benign-signals
prepare-mode-stamp-is-last-preparer-not-filer
proactive-advance-and-drain-side-effects-may-already-be-done
proactive-already-reacted-guard-number-vs-string-false-negative
proactive-empty-hook-may-be-resume-not-drain
proactive-first-reaction-lost-step-chain-still-dispose-work-bead
proactive-hook-may-surface-live-sibling-advance-and-drain-step
proactive-inline-step-close-needs-root-during-concurrent-molecule-storm
proactive-intake-scan-reoffer-convoy-churn-signature
proactive-resume-derive-convoy-from-step-bead-not-formula-show
proactive-resume-step-assignee-is-own-wisp-id
reaper-yield-from-deacon-ledger-before-retiring
rebase-bead-hides-a-live-operator-review
rebase-child-closes-while-original-anchor-stays-open
rebase-child-open-vetoes-the-next-rebase
rebase-child-worktree-head-is-stale-probe-ref
rebase-do-not-repoint-operator-exception-marker
rebase-generated-tree-re-render-not-merge
rebase-inherits-new-lint-detectors
reconcile-deadline-starves-pr-feedback-routing-hand-file-comment-rework
reconcile-heals-untracked-in-way-rework-round-record
reconcile-keep-in-place-round-record
refinery-batch-aging-finding-restamp-masks-stuck-bound
refinery-burst-drain-one-land-per-pass
refinery-close-on-land-model
refinery-close-on-merge-reconcile
refinery-codex-review-dispatch-procedure
refinery-codex-verdict-comment-disambiguation
refinery-convergence-cap-arm
refinery-convoy-child-merge-strategy
refinery-current-wisp-type-wisp-broken
refinery-direct-landing-stamp-exit4-and-guard-test-traps
refinery-direct-rejection-deletes-branch-rebuild-hits-missing-branch-visit
refinery-duplicate-fix-bead-codex-loop
refinery-escalation-state-fingerprint-mail-retired
refinery-find-work-ignores-blocks-edges-release-assignee-to-hold
refinery-fix-bead-on-operator-closed-pr
refinery-fold-review-feedback-direct
refinery-idle-driver-passes-vs-agent-escalation
refinery-orphan-scan-unrouted
refinery-parked-pr-bead-returns-as-supersede-regate
refinery-pr-review-loop
refinery-pre-open-regate-strand
refinery-preopen-twin-signoff-acting-blindspot
refinery-reopened-bead-stale-assignee-flash
refinery-request-restart-noop
refinery-rework-handback-one-anchor
refinery-rework-prepushed-predrafted
refinery-run-tests-noop-codex-gate
refinery-stacked-pr-no-rebase
refinery-tier2-shortcircuit-orphans-wisps
refinery-two-writers-from-a-rearmed-idle-driver
refinery-unset-merge-strategy-defaults-mr
refinery-witness-nudge-false-positive
regen-merge-refinery-assigned-merge-in-child
resumed-first-reaction-ruling-reuse-filed-visit
resumed-fr-dispose-landed-edge-missing-wire-by-hand
resumed-poured-rework-molecule-at-submit-step
resumed-rework-child-handoff-may-be-unrun
review-cycle-checklane-beads-superseded-by-derived-ruling
review-method-is-check-based-dispatch
review-path-redesign-design-tk-zif1d8u
review-round-cap-retired-validator-ruling-ends-a-lane
rework-anchor-prepare-mode-can-be-stale-rebase
rework-anchor-takeaway-resolved-by-converse-visit-outcome
rework-child-collides-with-live-rebase-child-on-branch
rework-child-subsumes-a-peer-rebase-child
rework-resume-branch-held-by-predecessor-worktree
rework-resume-stale-local-ref-reset-to-origin
rework-worktree-may-hold-predecessor-uncommitted-work
run-tests-empty-diff-runs-whole-suite
seed-audit-current-version-drift-dont-rerender
seed-audit-hook-stages-640kb-render
self-review-main-red-untracked-preflight-runs-no-tests
self-review-thin-checks-run-go-web-manually
shell-script-review-gate
sibling-lane-rework-cancelled-by-tree-holder-holder-edges-and-arms-it
signoff-closer-arm-tk-8iaccir-state
signoff-release-fires-on-closed-held-item
sitting-title-pr-number-rework-tk-hyeleuw-state
step-close-already-closed-line-names-a-sibling-molecule
step-close-bare-step-closed-wrong-live-molecule-strand-repair
step-close-matches-a-prior-workflow
step-close-matches-stale-steps-from-earlier-molecules
step-size-bound-tk-hku6zzl-state
submit-and-exit-resume-after-push-detached-head
submit-presentation-only-rework-branch-unchanged
submit-resume-cross-slot-push-by-refspec
superseded-rework-child-clear-own-route
terminal-conversation-form-tk-po06sre-state
terminal-helm-board-retirement-tk-1tfzr71-52-state
terminal-step-drain-ack-is-the-last-command-not-the-chain-listing
tk-0bvgf9s-reask-retract-bring-current-round-record
tk-3h9mzz-review-gates-rebuild-inflight
tk-3lr25yr-molecule-end-bring-current-round-record
tk-44srzem-bring-forward-audit-bring-current-round-record
tk-57wjk4l-removed-script-hold-bring-current-round-record
tk-5n01ns-reaction-bead-bring-current-round-record
tk-869in7j-open-visit-status-round-record
tk-8gradm4.2-one-write-create-bring-current-round-record
tk-8qu5od6-witness-dead-set-bring-current-round-record
tk-blloeo-correctness-round-blocker-holder-and-owed-label-clear
tk-cnq3sze-preexisting-failure-key-bring-current-round-record
tk-cooyf3c-merge-fallback-drop-bring-current-round-record
tk-crbo7xo-review-test-evidence-bring-current-round-record
tk-fpn7hcr-open-visit-deferral-bring-current-round-record
tk-gfb2hbq-formula-step-size-bring-current-round-record
tk-hkllw2-cap-park-retirement-bring-current-round-record
tk-nbhjz-dup-of-tk-e8doyk-workcontext-drain-injection-fixed
tk-ockwq2v-contract-rule-bring-current-round-record
tk-r0sj3wv-approval-gate-bring-current-round-record
tk-s4int0m-render-gate-round-record
tk-tgxoqi-writeback-owed-thread-bring-current-round-record
tk-vd66j1.7-screenshot-engine-lib-rework-round-record
tk-vd66j1.9-video-modality-bring-current-round-record
tk-w4p8c45-stand-down-bring-current-round-record
tmp-quota-exhausted-use-tmpdir-on-home-disk
tmux-popup-tests-false-fail-when-run-concurrently
town-city-toml-rejects-packv1-agent-tables
twin-feedback-batch-per-anchor-park-duplicate-of-peer
twin-validation-pass-on-duplicate-anchor-park-as-duplicate
two-arm-suite-part-split-merge-and-gate-ensure
two-rework-children-one-branch-concurrent-push-early-ff
two-signoff-reviews-spawn-concurrent-rework-children
unstamped-orphan-finding-has-same-title-stamped-twin
until-auto-close-retired-tk-u5edbg1-state
validate-close-churn-claim-measure-rework-titles-pre-vs-post-cutover
validate-close-recurrence-claim-scan-class-beads-for-hold-markers
validate-close-subject-with-open-visit-close-leave-visit
verification-backstop-bead-verify-wiring-then-hold
visit-gate-on-plan-retired-code-moot-until-disposition
visit-hold-counts-only-a-routed-visit
visit-orphan-census-recipe
visit-outcome-word-moot-benign-suppress-escalation
visit-pr-comment-topic-and-action-tk-29u73hw-state
visit-retirement-follow-up-tk-1tfzr71-46-state
whole-tree-lint-rework-clean-at-pushed-head
witness-backlog-finding-filed-late-check-witness-idle-gap
witness-crash-loop-finding-is-stuck-open-churn-not-deaths
witness-malformed-refinery-queue-visits-cause-is-escalate-subject-guard
witness-patrol-idles-restart-held-off-hook-fix-tk-r4c0g67
witness-salvage-refused-on-notesonly-workbead-benign
witness-stale-pool-slot-orphans-are-roots-orphan-dispose-skips
worktree-reap-retirement-tk-1tfzr71-42-state
```

### Entries of collection notes

116 entries inside collection notes are point-in-time too. They
are not removed with the whole notes, because tk-zlot608.3 leaves every
collection note as it is, and editing them belongs to the standing triage
(tk-zlot608.2). By collection note:

| Collection note | Point-in-time entries | Entries sorted |
|---|---:|---:|
| `hub-review-lanes-and-fix-units` | 47 | 69 |
| `hub-self-review-proofs` | 16 | 337 |
| `hub-testing-and-hermetic-suites` | 12 | 100 |
| `hub-helm-board-and-anchor-membership` | 11 | 18 |
| `hub-polecat-run-mechanics` | 7 | 64 |
| `hub-converse-sitting-dispositions` | 4 | 8 |
| `hub-native-hold-effort` | 4 | 4 |
| `hub-validate-close-and-visit-outcomes` | 3 | 14 |
| `hub-design-records-and-rulings` | 2 | 2 |
| `hub-rework-branch-and-bring-current` | 2 | 3 |
| `hub-bd-cli-and-store-semantics` | 1 | 37 |
| `hub-demo-capture` | 1 | 4 |
| `hub-duplicates-and-rework-holds` | 1 | 1 |
| `hub-first-reaction-and-proactive` | 1 | 8 |
| `hub-host-and-dolt-ops` | 1 | 1 |
| `hub-pack-authoring-surfaces` | 1 | 3 |
| `hub-refinery-merge-and-landing` | 1 | 1 |
| `hub-work-record-patrol-and-codex` | 1 | 1 |

### Live work

These 124 units are about work that is still open, so they are not
point-in-time yet. Each one waits on the bead given.

| Unit | Waits on |
|---|---|
| `ambient-gc-rig-phantom-test-failures` | tk-u16i7ww |
| `anchor-children-related-edge-graph` | tk-slnm11l |
| `anchor-inflight-membership-computations` | tk-j5wrs |
| `approval-comments-and-thread-resolution-rule-2026-11-05` | tk-o9i6kp0 |
| `architecture-document-standard-tk-jughjuk-1-state` | tk-jughjuk |
| `armed-bead-into-retiring-code-rule-1-at-load-context` | tk-ppqwgmo |
| `bmad-restructured-ticket-tree-epics-first-class` | tk-rctkrj |
| `boilerplate-collapse-tk-c8724xi-state` | tk-bh2qlt5 |
| `check-claim-advancing-i11-load-bead-pool-step-false-positive` | tk-g1u9js |
| `codex-bash-32-failures-come-from-nested-bash-lc` | tk-f8ndl4b |
| `converse-handback-header-keeps-one-subject-label` | tk-pxfpxt |
| `converse-live-edit-design-tk-rymdhac-state` | tk-rymdhac |
| `converse-may-edit-live-ruling-pr-checks-are-the-checks` | tk-bvw8j5t |
| `converse-provider-names-tk-ujfbwml-state` | tk-sakjkju |
| `converse-signoff-rework-files-fresh-child-not-adopt` | tk-5v47s5i |
| `convoy-cleanup-cutover-leftover-graduations-and-1320-removal` | tk-l2o36ir |
| `dead-branch-cleanup-tk-pelfjuc-ruling-and-sweep-recipe` | tk-d7sa474 |
| `deferred-arm-needs-open-status-keep-defer-until` | tk-jezlwfe |
| `deferred-dispatch-malformed-args-warn-is-gc-sling-rc3` | tk-cedhuvm |
| `deferred-dispatch-reconcile-slings-from-pass-start-ready-snapshot` | tk-dgb8fqb |
| `deferred-follow-up-on-integration-branch-anchor-gate-on-convoy` | tk-grjsnf6 |
| `deleting-a-script-poured-step-text-names-breaks-open-runs` | tk-1tfzr71.39 |
| `design-convoy-first-run-tk-ikpyzn-12-setup-state` | tk-ikpyzn.12 |
| `design-pr-states-target-in-architecture-md-same-pr` | tk-jughjuk.5 |
| `dispatch-design-tk-1tfzr71-54-state` | tk-1tfzr71.15 |
| `distiller-gascity-review-index-gap-flood` | tk-ymhd3o4 |
| `distiller-live-noop-routes-agent-guidance-pack-lookup-bd-stub` | tk-9t1wmrd |
| `distiller-prvea-contract-clause-missed-next-lever-author-side` | tk-tayv80f |
| `doctor-skill-dangling-sink-after-pack-skill-deletion` | tk-ujz8d10 |
| `doctor-sweep-killed-by-deacon-cycle-restart-in-handback-turn` | tk-1tfzr71.19 |
| `dolt-backup-stale-manifest-on-suspended-rig-is-the-suspended-skip` | tk-1tfzr71.19 |
| `dolt-noms-size-finding-actionable-not-benign` | tk-0k49i9 |
| `drain-blocked-work-armed-finding-arm-and-rest` | tk-2yyrn4 |
| `feature-layer-design-tk-wmwcdlc-1` | tk-wmwcdlc.3 |
| `feedback-distiller-load-and-gate-blind-spots-half-filed-obs-and-abandoned-vetoes` | tk-5j0aben |
| `filing-rule-dependency-sibling-epic-decomposition-member` | tk-9wojzh |
| `first-reaction-close-arm-hand-fire-when-reconcile-wedged` | tk-m36nqr |
| `first-reaction-closed-twin-duplicate-stamped-hold-for-sweep-not-close` | tk-6121i3p |
| `first-reaction-killed-dispose-check-hold-edge-and-dup-stamp` | tk-6121i3p |
| `first-reaction-landed-stamp-is-not-the-hold-verify-edge-and-arm` | tk-2uy2h8c |
| `first-reaction-subject-in-flight-under-live-polecat-workflow-stand-down` | tk-yqx8vzu |
| `first-reaction-then-route-proactive-pours-mol-polecat-work` | tk-q3rr8q1 |
| `form-attach-engage-unlisted-sitting-tk-6678pvo-state` | tk-c9dcsbn |
| `formula-step-gains-a-script-call-only-by-trading-weight` | tk-bh2qlt5 |
| `gc-helm-home-page-tk-c9dcsbn-state` | tk-c9dcsbn |
| `gc-helm-takeaway-release-unconditional-park-write-reopens-closes` | tk-77b54fz |
| `gctk-architecture-effort-tk-ssm8qns-state` | tk-ssm8qns |
| `goal-centric-track-adopted-model` | tk-nt5uda |
| `graduation-seed-summary-pm-finding-must-fix-back-lane` | tk-985yma8 |
| `handoff-session-name-restamped-by-reconcile-race` | tk-taj63n2 |
| `held-molecule-blocks-resling-delete-source-misses-convoy-roots` | tk-ob4zfb4 |
| `helm-board-epic-split-where-things-stand-what-needs-you` | tk-ikpyzn |
| `human-park-route-owes-takeaway-and-edge` | tk-t1xvt2 |
| `i8-husk-finding-settle-not-hand-close` | tk-t6023b |
| `input-convoy-dispatch-not-gated-on-bd-ready` | tk-ob4zfb4 |
| `integration-unit-waiting-on-a-main-pr-needs-a-bring-current-handoff` | tk-1tfzr71.60 |
| `leftover-molecule-park-conversion-recipe-and-cross-rig-pins` | tk-ncnvjnv |
| `merge-rewrite-design-convoy-tk-1tfzr71-20-state` | tk-1tfzr71.66 |
| `migration-map-tk-1tfzr71-members-warrants-lanes` | tk-1tfzr71 |
| `mol-validate-stale-page-finding-stamp-predates-review-decline` | tk-pdc0ovc |
| `new-work-pause-intake-scan-and-deferred-dispatch-disabled` | tk-rl8gz4b.17 |
| `operator-epic-park-is-a-blocks-edge-onto-a-park-gate` | tk-rl8gz4b |
| `operator-epic-without-hypothesis-is-incomplete-pr1392` | tk-wmwcdlc.5 |
| `patrol-chain-repour-freezes-formula-var-defaults` | tk-h9qdbqk |
| `patrol-wisp-reconcile-slash-less-assignee-orphans-gascity` | tk-pj1jsra |
| `pre-park-poured-workflow-reaches-load-context-hold-as-parked` | tk-rl8gz4b |
| `preexisting-failure-dedup-test-red-in-session-gc-rig-root-leak` | tk-u16i7ww |
| `proactive-close-exit-needs-claim-released-before-arm` | tk-kvcgj8 |
| `proactive-dispatched-to-mechanically-owned-standing-triage-subject` | tk-hok6w |
| `proactive-scan-tests-belong-in-gc-proactive-test-sh` | tk-1wqr0qk |
| `reacted-finding-reoffers-via-vestigial-route` | tk-ou35ed |
| `reaper-cutover-rollout-tk-1tfzr71-10-state` | tk-6lctp3w |
| `refinery-findwork-exact-assignee-newest-first-starvation` | tk-h9qdbqk |
| `refinery-in-polecat-worktree-is-gascity-drain-source-cwd-bug` | tk-fryy9y |
| `review-body-rework-twin-block-on-inline-rework` | tk-5nwi2pz |
| `review-coverage-epic-elaboration-tk-qjdt90g` | tk-qjdt90g |
| `review-evidence-worktree-tk-x2tytm6-state` | tk-zmk32nr |
| `rig-board-page-tk-yhquh93-9-unit2-state` | tk-ikpyzn.12 |
| `rig-board-read-tk-yhquh93-2-unit1-state` | tk-ikpyzn.12 |
| `rig-checkout-reconcile-and-untrack-or-newly-tracked-paths` | tk-9hs7mxv |
| `rig-checkout-sync-cut-open-untrack-landing-tk-9hs7mxv-state` | tk-9hs7mxv |
| `second-rework-behind-live-holder-bare-route-wait` | tk-5nwi2pz |
| `shellcheck-pre-gate-debt-routes-to-batch-and-whole-tree-gap` | tk-fu1ofy5 |
| `validate-close-note-block-printf-format-hazard` | tk-52oz0ts |
| `witness-refinery-queue-recurring-can-mask-pr-awaiting-operator-approval` | tk-q3rr8q1 |
| `work-formula-rewrite-tk-1tfzr71-12-state` | tk-1tfzr71.39 |
| `zsh-reads-home-zshenv-codex-home-red-pool-home-green` | tk-vzecgfx |
| `hub-feedback-learning-distiller-and-miner#1` | tk-b80kkz |
| `hub-feedback-learning-distiller-and-miner#2` | tk-karx6a2 |
| `hub-feedback-learning-distiller-and-miner#3` | tk-4uw3cg3 |
| `hub-first-reaction-and-proactive#4` | tk-t9fl9ss |
| `hub-helm-board-and-anchor-membership#17` | tk-yhquh93 |
| `hub-helm-board-and-anchor-membership#2` | tk-1tfzr71.24 |
| `hub-helm-board-and-anchor-membership#3` | tk-fgek12q |
| `hub-pack-authoring-surfaces#1` | tk-bh2qlt5 |
| `hub-pack-authoring-surfaces#2` | tk-2ckjoft |
| `hub-review-lanes-and-fix-units#36` | tk-vbn1adn |
| `hub-review-lanes-and-fix-units#52` | tk-1tfzr71.66 |
| `hub-review-lanes-and-fix-units#54` | tk-1tfzr71.66 |
| `hub-review-lanes-and-fix-units#55` | tk-1tfzr71.66 |
| `hub-review-lanes-and-fix-units#57` | tk-1tfzr71.66 |
| `hub-review-lanes-and-fix-units#59` | tk-1tfzr71.66 |
| `hub-review-lanes-and-fix-units#60` | tk-1tfzr71.66 |
| `hub-review-lanes-and-fix-units#63` | tk-sakjkju |
| `hub-review-lanes-and-fix-units#64` | tk-c9dcsbn |
| `hub-review-lanes-and-fix-units#65` | tk-c9dcsbn |
| `hub-review-lanes-and-fix-units#66` | tk-ikpyzn.12 |
| `hub-review-lanes-and-fix-units#67` | tk-ikpyzn.12 |
| `hub-review-lanes-and-fix-units#68` | tk-jughjuk.3 |
| `hub-review-lanes-and-fix-units#69` | tk-1tfzr71.66 |
| `hub-self-review-proofs#167` | tk-gk06jad |
| `hub-self-review-proofs#17` | tk-1tfzr71.66 |
| `hub-self-review-proofs#19` | tk-1tfzr71.66 |
| `hub-self-review-proofs#211` | tk-hs8dn2d |
| `hub-testing-and-hermetic-suites#12` | tk-bakv50k |
| `hub-testing-and-hermetic-suites#20` | tk-zctvc35 |
| `hub-testing-and-hermetic-suites#23` | tk-zhs2jyx |
| `hub-testing-and-hermetic-suites#25` | tk-hs8dn2d |
| `hub-testing-and-hermetic-suites#30` | tk-z1zmas1 |
| `hub-testing-and-hermetic-suites#50` | tk-d0wm9dd |
| `hub-testing-and-hermetic-suites#88` | tk-1m99y85 |
| `hub-testing-and-hermetic-suites#89` | tk-x7q04de |
| `hub-validate-close-and-visit-outcomes#11` | tk-georjc |
| `hub-validate-close-and-visit-outcomes#14` | tk-1tfzr71.61 |

### Notes the deletion schedule will make point-in-time

These units are about code the deletion schedule retires and are not question 1 yet, because the code is still on main. Each becomes point-in-time when its retiring bead lands.

| Retiring bead | Units |
|---|---:|
| tk-1tfzr71.22 | 35 |
| tk-1tfzr71.20 | 24 |
| tk-1tfzr71.21 | 18 |
| tk-1tfzr71.19 | 14 |
| tk-1tfzr71.39 | 14 |
| tk-kvdomjb | 7 |
| tk-1tfzr71.15 | 1 |
| tk-1tfzr71.17 | 1 |
| tk-1tfzr71.18 | 1 |
| tk-1tfzr71.25 | 1 |

## Wording fixes

Each fix replaces the words of one instruction at main (6337a480c), at about
zero change in size. tk-zlot608.4 applies them in one pull request, and skips
any whose words have changed since.

### W-01: `skills/converse-hold/SKILL.md`

- **Section:** the close-out line (line 149).
- **What is wrong:** The placeholder reads as text to copy, and a close-out reached the operator with the placeholder in place of a reason.
- **Current words:** `dismiss --reason "<why this is done>"`
- **Replace with:** `dismiss --reason "<this sitting's real reason>"`
- **Size change:** no words.
- **Shown by:** `converse-close-out-line-carries-a-real-reason`.

### W-02: `docs/file-structure.md`

- **Section:** the table that sets the description beside the Scope section (the Job row).
- **What is wrong:** The row calls a description an index summary, while the frontmatter rule in the same page says it states why the doc exists and when to use it.
- **Current words:** `| Job | discovery / index summary | the doc's charter |`
- **Replace with:** `| Job | discovery: when to use it | the doc's charter |`
- **Size change:** +1 word.
- **Shown by:** `doc-description-says-when-to-use-it-not-a-summary`.

### W-03: `assets/scripts/patrol-finding.sh`

- **Section:** the recurrence paragraph appended to a finding's body (the words wrap across two lines in the file).
- **What is wrong:** A finding's key names the check, not the fault, so the same key can return with a new cause, and the text tells the reader the old fix regressed.
- **Current words:** `This finding fired again after $PRIOR was closed, so the earlier fix did not hold.`
- **Replace with:** `This finding fired again after $PRIOR was closed, and its cause may differ.`
- **Size change:** -3 words.
- **Shown by:** `finding-key-recurrence-may-be-a-different-cause`.

### W-04: `docs/component-model.md`

- **Section:** the I13 row of the invariants table.
- **What is wrong:** A graph.v2 pour routes every executable step, so the row's claim that continuation steps carry no route is false; closed bead tk-mc7s1uo left this row as it was.
- **Current words:** `those steps carry no owner and no route by construction, so a drain landing mid-molecule strands them`
- **Replace with:** `those steps carry a route from the pour but no owner, so only a route stripped mid-molecule strands them`
- **Size change:** +2 words.
- **Shown by:** `graphv2-steps-routed-at-pour-i13-doc-stale`.

### W-05: `agents/proactive/prompt.template.md`

- **Section:** Startup Protocol, step 1.
- **What is wrong:** Nothing says the claim is made once, so a mid-reaction nudge to re-check the hook led a worker to claim a second reaction bead.
- **Current words:** `# 1. Claim the reaction bead R (assigned first, then routed proactive demand).`
- **Replace with:** `# 1. Claim the reaction bead R once (assigned first, then routed proactive demand).`
- **Size change:** +1 word.
- **Shown by:** `proactive-reclaim-mid-reaction-claims-a-second-reaction-bead`.

### W-06: `template-fragments/work-quality-polecats.template.md`

- **Section:** learned rule tk-qenzk6e (its last sentence) (the words wrap across two lines in the file).
- **What is wrong:** The rule says to arm the removal bead, while the work skill holds a bead filed outside an epic for placement and a doctor check reports a held bead that an arm sends.
- **Current words:** `blocked by what retires the case and armed to dispatch when it lands.`
- **Replace with:** `blocked by what retires the case and held for placement, which arms it.`
- **Size change:** no words.
- **Shown by:** `removal-bead-for-a-kept-path-is-pending-not-armed`.

### Retired in place of a fix

`mol-validate-read-review-bead-notes-for-reviewer-repro` shows a gap in `formulas/mol-validate.toml`, which tk-1tfzr71.22 retires, so it gets no fix (AGENTS.md).

Together the fixes change the instructions by +1 word.

## Structural findings

131 units show something structurally wrong. They group into 35 findings, ranked so the best ratio of severity to the scope of the fix comes first. A finding in code the deletion schedule retires names the retiring bead in place of a fix.

### S-01: Polecat steps carry no rule for waiting out a long job

- **What is off:** Self-review's gate and other long commands outlast one tool call, yet only the refinery's prompt and formula start them through detached-job.sh and wait in the foreground. Polecat sessions end their turn on a background poll or sleep and are drained or killed mid-run.
- **Notes that show it:** 2, of which 2 record a repeat.
- **Cost when it happens:** A killed session loses its run and the work starts over, which the notes record many times over several weeks. Severity: high.
- **Scope of the fix:** Add a short foreground-wait rule to the polecat doctrine and start self-review's gate through the existing detached-job.sh, a few lines of text and one call (small).
- **Units:** `background-sleep-poll-misreads-elapsed-time`, `execution-backstop-kills-idle-pool-session-wait-in-foreground`

### S-02: Test suites inherit the live city's environment

- **What is off:** tools/run-tests.sh hands every suite the agent's GC_* and BEADS_* variables, so code that resolves the city root reaches the live city instead of a fixture. The test floor refuses a stray real gc or bd call, but nothing stops a suite from reading or writing live state through those variables.
- **Notes that show it:** 2, of which 2 record a repeat.
- **Cost when it happens:** Suites have written lock files into the live city, replaced a live service binary with a stub, and gone red in ways that became bogus pre-existing-failure trackers. Severity: high.
- **Scope of the fix:** Have run-tests.sh, and harness_init for a suite run on its own, point each file at a fixture city and unset the city and store variables, failing closed if any remain; one runner change (small).
- **Already in the pack:** partly: tools/test-floor has refused a stray real gc or bd call since 2026-10-12, but the variables still reach city-root code
- **Units:** `test-fallback-path-inherits-ambient-city`, `hub-testing-and-hermetic-suites#93`

### S-04: Summaries misstate what merging sets in motion

- **What is off:** Nothing lists the beads armed behind an anchor or the PR's current approval, so kept summaries say merging starts nothing while armed beads have the anchor as their last open blocker, or misstate what the operator still owes. Only a hand re-derivation at submit catches it.
- **Notes that show it:** 5, of which 5 record a repeat.
- **Cost when it happens:** Each miss costs a restamp, and one that slips through tells the operator a merge is inert when it dispatches work. Severity: high.
- **Scope of the fix:** One small script, run at submit and cited in the brief, that lists the anchor's armed dependents with their other open blockers and reads the PR's review state (small).
- **Units:** `hub-polecat-run-mechanics#6`, `hub-polecat-run-mechanics#7`, `hub-polecat-run-mechanics#17`, `hub-polecat-run-mechanics#26`, `hub-polecat-run-mechanics#48`

### S-05: The scratch reaper deletes live temp directories

- **What is off:** build-scratch-reap.sh removes a temp entry when no process holds a file in it at that instant, so a running suite's directory or a step's summary file can vanish between commands. Agents dodge it with a hand-picked short TMPDIR, and a TMPDIR nested in a session scratchpad then fails scratch-reap's own suite.
- **Notes that show it:** 3, of which 3 record a repeat.
- **Cost when it happens:** Suites go red mid-run for no fault of the change, and a vanished summary file leaves the PR body on the dispatch text. Severity: high.
- **Scope of the fix:** Narrow the reaper's scope or holder rule (tk-0ajlj81) and fix the suite's length cap (tk-bakv50k), two small script changes (small).
- **Units:** `build-scratch-reap-deletes-live-test-tmp-dirs`, `hub-self-review-proofs#240`, `hub-testing-and-hermetic-suites#22`

### S-06: A claim answer can hide a step the session still holds

- **What is off:** gc hook --claim can answer drain or no work, or hand over a fresh chain, while the session holds a step in progress, and it answers a false drain while the store's breaker is open. The doctrine treats a drain as the end of the turn, so a session that obeys it strands its own step.
- **Notes that show it:** 2, of which 2 record a repeat.
- **Cost when it happens:** The held step sits in progress with no worker until recovery returns it, and the session's work on it is lost. Severity: high.
- **Scope of the fix:** Have the claim contract check for a step the session still holds, and retry once after a store error, before it drains, in a few lines of doctrine or a check in claim-context.sh, and report the hook's answer upstream (small).
- **Already in the pack:** partly: since tk-1tfzr71.12 the work scripts send a store outage back to the pool instead of reading it as a verdict
- **Units:** `hook-claim-no-work-while-holding-ralph-iteration`, `dolt-rig-store-io-timeout-circuit-breaker-retry`

### S-09: A rework's order does not travel with the rework

- **What is off:** converse-rework.sh carries a ruling as one line in rejection_reason while the sitting's full requirements stay on the ruled subject's notes, and work-setup.sh unsets that line once the resume merge lands. Later sessions see no order, and nothing shows which of its findings the branch head already answers.
- **Notes that show it:** 3, of which 2 record a repeat.
- **Cost when it happens:** Rework misses requirements the operator ruled, redoes fixes already on the branch, and summaries cite a bead that no longer says what was asked. Severity: medium.
- **Scope of the fix:** Have converse-rework.sh copy the ruling's requirements into the rework's notes, and work-setup.sh append rejection_reason to the notes before clearing it and print the commits since the reviewed head; two small script changes (small).
- **Already in the pack:** partly: claim-context.sh has printed the work bead's notes at claim since 2026-10-26
- **Units:** `load-context-read-bead-notes-not-just-hook-description`, `rework-bead-may-relist-folded-sibling-work`, `hub-self-review-proofs#42`

### S-10: Test and lint runners accept a file list that names nothing

- **What is off:** run-tests.sh, lint.sh and lint-learned.sh take files as bare arguments and quietly drop or reinterpret a name that is not a file, such as a newline-joined list or a shard line from --list, while an empty expansion turns lint-learned.sh into a whole-tree scan. Each reports success or scans the wrong set without saying so.
- **Notes that show it:** 6, of which 5 record a repeat.
- **Cost when it happens:** A gate reads green over files it never ran or linted, or base findings pass for the change's own, and the miss surfaces in CI or at merge. Severity: medium.
- **Scope of the fix:** Make the three entry points refuse a name that is not a file, print how many files they selected, and take an explicit list whose empty form means nothing to do; a few lines in each (small).
- **Already in the pack:** partly: run-tests.sh --affected reads the change from git and runs nothing for an empty change
- **Units:** `lint-learned-false-clean-zsh-no-wordsplit`, `lint-learned-no-args-scans-whole-tree`, `zsh-unquoted-list-is-one-arg-run-tests-false-green`, `zsh-unquoted-var-no-word-split-false-clean-lint`, `zsh-unquoted-var-not-word-split-lint-false-skip`, `hub-testing-and-hermetic-suites#83`

### S-11: The affected-test subset misses suites a change can break

- **What is off:** The subset picks suites by file name and sourcing, so a Go-only change skips the shell suites that build gctk, a gc-helm.sh edit skips the helm Go test that pins its output, and a tree-wide case inside an ordinary suite never runs. Each first fails in CI's full run.
- **Notes that show it:** 3, of which 0 record a repeat.
- **Cost when it happens:** A green self-review is followed by a CI failure and another round, or agents assemble the missing suites by hand. Severity: medium.
- **Scope of the fix:** Map services/gctk and services/helm changes to the suites and Go tests that exercise them in tools/run-tests.sh, and move dispatch-path.test.sh's tree-wide case under run-tests-scope: tree (small).
- **Already in the pack:** partly: suites declaring run-tests-scope: tree have joined every subset since 2026-10-08
- **Units:** `gc-helm-open-stdout-pinned-by-helm-go-parity-test`, `hub-self-review-proofs#15`, `hub-testing-and-hermetic-suites#51`

### S-14: A session that oriented on a bead is handed another run at implement

- **What is off:** Core's implement step declares no continuation group, so after preflight the next claim can give the session another run's step while its own implement goes to a fresh session. Nothing records the orientation it gathered, and once the session was handed the validation pass on its own rework.
- **Notes that show it:** 2, of which 2 record a repeat.
- **Cost when it happens:** The next holder re-derives the context, and a session can end up ruling on work it is building. Severity: medium.
- **Scope of the fix:** Have the polecat doctrine tell a session to write its orientation into the work bead's notes before it closes preflight, where the built-once target puts refinements of core's steps; a few lines (small).
- **Units:** `hub-polecat-run-mechanics#57`, `hub-review-lanes-and-fix-units#24`

### S-15: The shared test harness hides two staging gaps

- **What is off:** mk_sut_dir copies a hand-kept list of sourced libraries, so a script that gains a sibling library breaks every suite that stages it, and the harness's bd create stub drops -d, so a created description reads empty. Both sit in assets/scripts/test-harness.sh.
- **Notes that show it:** 2, of which 1 record a repeat.
- **Cost when it happens:** Dozens of suite cases fail first in CI after a library is added, and description assertions run against an empty value. Severity: medium.
- **Scope of the fix:** Have mk_sut_dir stage whatever the copied script sources and have the create stub keep -d, two small changes in test-harness.sh (small).
- **Units:** `hub-testing-and-hermetic-suites#9`, `hub-testing-and-hermetic-suites#74`

### S-18: A rework left with no run, route or arm is finalized by nothing

- **What is off:** A rework child whose holder stopped before pushing or handing off, whose re-dispatch was only promised in a takeaway, or whose PR merged mid-flight stays open with nothing that offers or closes it. Its blocks edge holds the anchor's merge, and no check reports it.
- **Notes that show it:** 4, of which 1 record a repeat.
- **Cost when it happens:** The PR stalls silently for days while the operator believes the work is moving, until someone lists the anchor's children and re-slings by hand. Severity: high.
- **Scope of the fix:** One doctor check for open PR-finishing beads with no route, arm, assignee or live run (tk-dntkwct), plus a merged-anchor exit in work-submit.sh (tk-o3t1eg6) (medium).
- **Already in the pack:** partly: since tk-1tfzr71.12 a run that meets a sibling's tree waits on an edge and an armed re-sling, and a refused hand-off ends on a gate
- **Units:** `pr-merged-mid-bring-current-no-push-no-refinery-handoff`, `rework-shared-branch-stranded-sibling-blocks-merge`, `rework-sibling-fix-committed-local-not-pushed-verify-origin`, `settled-release-redispatch-is-prose-rework-strands-ready-unrouted`

### S-19: The PR summary is written across sessions and checked by hand

- **What is off:** Implement holds the research but drains, and fresh later sessions keep or restamp a summary against a long list of brief rules that nothing checks mechanically. Submit sessions recorded about thirty summaries that fell short in under a week, with costs or options missing, calls hidden in the fold, and counts overstated or stale.
- **Notes that show it:** 31, of which 31 record a repeat.
- **Cost when it happens:** Each one costs a restamp at submit, and one that slips through hands the operator a brief that hides or misstates a call. Severity: medium.
- **Scope of the fix:** A summary-check script for the rules a script can test (open text within a screen, a cost line, every option, an on-merge line, a fold), run wherever a summary is kept, plus a doctrine line that implement writes its research into the notes (medium).
- **Units:** `pr-body-answers-stamp-pr-summary-before-implement-drains`, `hub-polecat-run-mechanics#4`, `hub-polecat-run-mechanics#8`, `hub-polecat-run-mechanics#9`, `hub-polecat-run-mechanics#11`, `hub-polecat-run-mechanics#12`, `hub-polecat-run-mechanics#13`, `hub-polecat-run-mechanics#14`, `hub-polecat-run-mechanics#15`, `hub-polecat-run-mechanics#18`, `hub-polecat-run-mechanics#19`, `hub-polecat-run-mechanics#22`, `hub-polecat-run-mechanics#23`, `hub-polecat-run-mechanics#27`, `hub-polecat-run-mechanics#28`, `hub-polecat-run-mechanics#29`, `hub-polecat-run-mechanics#30`, `hub-polecat-run-mechanics#33`, `hub-polecat-run-mechanics#34`, `hub-polecat-run-mechanics#35`, `hub-polecat-run-mechanics#36`, `hub-polecat-run-mechanics#37`, `hub-polecat-run-mechanics#38`, `hub-polecat-run-mechanics#42`, `hub-polecat-run-mechanics#45`, `hub-polecat-run-mechanics#47`, `hub-polecat-run-mechanics#49`, `hub-polecat-run-mechanics#58`, `hub-polecat-run-mechanics#60`, `hub-polecat-run-mechanics#61`, `hub-polecat-run-mechanics#62`

### S-20: Overlap with other open branches is surveyed by hand

- **What is off:** No pack script surveys open PRs, integration branches and unpushed heads for conflicts a change adds, so each session rebuilds a merge-tree probe and relearns its parsing traps. A survey taken at self-review goes stale before submit, and a textual check misses semantic collisions.
- **Notes that show it:** 10, of which 10 record a repeat.
- **Cost when it happens:** Briefs carry a wrong all-clear or a false overlap, and a conflict missed at submit bounces at the refinery. Severity: medium.
- **Scope of the fix:** One survey script run at submit and cited in the brief, with a pointer in the self-review and submit steps (medium).
- **Units:** `merge-tree-isolate-conflicts-your-change-adds-vs-open-prs`, `hub-polecat-run-mechanics#16`, `hub-polecat-run-mechanics#20`, `hub-polecat-run-mechanics#24`, `hub-polecat-run-mechanics#31`, `hub-polecat-run-mechanics#39`, `hub-polecat-run-mechanics#41`, `hub-polecat-run-mechanics#43`, `hub-polecat-run-mechanics#50`, `hub-polecat-run-mechanics#51`

### S-21: The self-review gate does not fit a loaded host

- **What is off:** The gate runs under fixed limits, 900 seconds a suite in run-tests.sh and two hours a run in gctk rig, and in the session's own environment, so on a loaded host suites time out and recover only serially and whole runs end with no record. Sessions hand-build pre-run kits with stripped variables, longer limits, a cache TMPDIR and a detached launch so the step's own call answers from a record.
- **Notes that show it:** 11, of which 11 record a repeat.
- **Cost when it happens:** A false red or a lost run costs tens of minutes to hours per self-review, and hand launches leave stray processes behind. Severity: medium.
- **Scope of the fix:** Scale run-tests.sh's per-suite timeout and gctk rig's limit to host load, end the runner with one verdict line that names recoveries, and have rig-checks.sh launch detached with a scrubbed environment; a few scripts (medium).
- **Units:** `hub-self-review-proofs#23`, `hub-self-review-proofs#24`, `hub-self-review-proofs#97`, `hub-self-review-proofs#101`, `hub-self-review-proofs#102`, `hub-self-review-proofs#228`, `hub-self-review-proofs#229`, `hub-self-review-proofs#237`, `hub-self-review-proofs#241`, `hub-self-review-proofs#244`, `hub-self-review-proofs#245`

### S-22: Index rows a new surface owes are checked only at review

- **What is off:** A new script, order, closing or killing actor, or formula metadata key owes an entry in docs/component-model.md section 4, docs/authority-map.md or lifecycle/lifecycle.toml, and no lint compares a change with those indexes. The arch check finds the gap and sends the change back.
- **Notes that show it:** 3, of which 2 record a repeat.
- **Cost when it happens:** Each miss costs a rework round after an arch finding. Severity: medium.
- **Scope of the fix:** One lint that lists a branch's new scripts, orders, actuators and formula metadata writes and fails when their index entries are missing; tk-ppthdnd.2 holds the registry part (medium).
- **Units:** `component-index-s4-row-placement-sourced-libs-and-doctor-callers`, `new-actuator-owes-authority-map-row-and-architecture-reactive-path`, `hub-self-review-proofs#231`

### S-23: Pack shell written for bash still runs under zsh

- **What is off:** Formula and prompt shell relies on bash word splitting and plain colons after variables, while Codex sessions and some hand runs use zsh, where an unquoted list stays one word and a colon can act as a modifier. The failures are silent and look like valid results.
- **Notes that show it:** 2, of which 2 record a repeat.
- **Cost when it happens:** Wrong answers, vacuous green runs and duplicate filings go unnoticed until someone cross-checks. Severity: medium.
- **Scope of the fix:** Run every agent's commands under bash (tk-8gradm4.10) and extend the existing zsh lint to formula and prompt shell; config plus a lint rule (medium).
- **Already in the pack:** partly: Claude Code sessions now run commands under bash; Codex sessions do not yet
- **Units:** `run-formula-shell-blocks-under-bash-not-zsh`, `zsh-colon-modifier-mangles-git-show-rev-path`

### S-24: Dispatch ignores branches already changing the same code

- **What is off:** A bead slung fresh, or two beads armed on one landing, start with no check of open branches that touch the same files or already carry the fix. The overlap surfaces only when an agent edges the beads by hand, or at merge.
- **Notes that show it:** 2, of which 1 record a repeat.
- **Cost when it happens:** Two polecats build changes that conflict, or one rebuilds a fix that already sits on a live anchor branch. Severity: medium.
- **Scope of the fix:** A check in work-gate.sh that lists open anchor branches touching the bead's files and holds the later bead behind the first (medium).
- **Units:** `finding-dispatched-fresh-may-be-fixed-on-live-anchor`, `siblings-armed-on-one-landing-same-readers-edge-at-load-context`

### S-26: A first reaction cannot hold a finding on the bead it tracks

- **What is off:** A patrol finding carries a tracks edge to its subject and bd keeps one edge type per pair, so the blocked or close exit's blocks edge onto that subject is refused. The exit now fails loudly, but converting the edge is still done by hand.
- **Notes that show it:** 2, of which 2 record a repeat.
- **Cost when it happens:** A reaction stops partway and an agent removes the tracks edge and runs it again, minutes each time. Severity: low.
- **Scope of the fix:** Have first-reaction-dispose.sh replace a tracks edge onto the same bead with the blocks edge, since finding.about keeps the link (small).
- **Already in the pack:** partly: since 2026-11-08 a refused edge fails the exit instead of leaving a hold in text only
- **Units:** `first-reaction-blocked-on-already-tracked-bug-settle`, `first-reaction-blocked-on-subject-waiting-on-fails-on-tracks-edge`

### S-32: Validation-pass and review-lane machinery

- **What is off:** mol-validate, finding.sh, lane-state.sh, gate-ensure.sh and rework-child.sh mishandle resumes, rulings, steering, lane attribution, standing approvals and twin reworks in twelve recorded ways. Each is worked around by hand.
- **Notes that show it:** 12, of which 10 record a repeat.
- **Cost when it happens:** False fixed-in answers and duplicate notes reach PRs, declined items get built anyway, reviews see a mid-change branch, and reworks land on an old approval. Severity: high.
- **Scope of the fix:** Retired by tk-1tfzr71.22: no fix.
- **Units:** `approval-fallback-makes-supersede-lane-a-noop-on-approved-prs`, `fix-unit-reread-finding-notes-validator-steering-lands-mid-implement`, `gate-close-fires-ruling-child-and-armed-waiter-cancel-twin-run-by-root`, `mol-validate-finalize-resume-verify-step1-done`, `mol-validate-human-batch-parallel-rework-note-rulings-measure-claims`, `mol-validate-machine-fix-unit-pick-is-not-lane-specific`, `mol-validate-no-batch-human-pass-hold-not-close`, `new-rework-origin-key-sweep-absence-keyed-readers`, `preopen-rework-backlane-convergence-finding-holds-lane`, `resumed-mol-validate-finalize-verify-before-reclose`, `resumed-mol-validate-finalize-verify-prior-closes`, `review-wedge-repairs-differ-by-approval-and-reopened-lane`

### S-33: Merge cadence, rework and branch-currency machinery

- **What is off:** The reconcile cadence, the repool on rejection, pre-open rebase, the bring-current audit and guard, and the pre-existing-failure marks pour reviews before publishing, mint duplicate bring-current work, rewrite a branch under a live rework, keep one audit entry per path and accept stale marks. Agents compensate by hand each time.
- **Notes that show it:** 8, of which 5 record a repeat.
- **Cost when it happens:** False P1 findings, duplicate sessions, a merge that re-applies a rebased feature, and a self-review that could certify a red main no longer has. Severity: high.
- **Scope of the fix:** Retired by tk-1tfzr71.20: no fix.
- **Units:** `bring-current-audit-one-entry-per-path-across-merges`, `child-handoff-waits-for-sibling-bring-current-on-shared-branch`, `false-p1-stale-published-summary-pour-before-refresh-race`, `preopen-merge-in-child-twins-stale-base-finding-fix-unit`, `rework-resume-refinery-rebased-shared-branch`, `rework-submit-push-diverges-force-with-lease`, `shared-branch-sync-merge-owes-guard-entry-on-both-siblings`, `hub-self-review-proofs#242`

### S-34: pr-facts and the living review answer

- **What is off:** review-answer.sh shows nothing for a finding with no review id, so a fix for a Conversation comment is answered by hand along with a second bring-current. pr-facts.test.sh also leaks fixtures between its sections.
- **Notes that show it:** 2, of which 0 record a repeat.
- **Cost when it happens:** A reply is lost unless posted by hand, and the suite passes or fails depending on what ran before. Severity: medium.
- **Scope of the fix:** Retired by tk-1tfzr71.21: no fix.
- **Units:** `conversation-comment-finding-answer-and-second-bring-current`, `hub-testing-and-hermetic-suites#4`

### Findings shown by one unit

| Finding | What is off | Severity | Scope of the fix | Unit |
|---|---|---|---|---|
| S-03 | assets/scripts/rig-mentions.sh catches whole rig names, bead ids of two or more characters and checkout paths, but not bare id prefixes, one-character ids, product names, or an exempted dependency name used as data. Self-review and submit sessions keep finding such names by hand after the script reads clean. | high | Extend rig-mentions.sh to bare prefixes and short ids from the rig list, a city-held list of product words, and dependency names in data position; one script and its test (small) | `gc-toolkit-content-names-no-other-rig` |
| S-07 | The controller types a pool's startup nudge while the prime is still running, so Claude Code queues it and plays it after drain-ack, or as a stray tail mid-turn. A drained session that obeys it claims work it cannot finish. | high | The lasting fix is upstream, where the controller would drop a queued nudge after drain-ack (tk-1ggf9cr), and one clause in the pool nudges telling a drained session to ignore them stops the harm now (small) | `pool-startup-nudge-fires-after-drain-ack-do-not-claim` |
| S-08 | work-setup.sh cuts a bead's worktree inside the home of the slot that set it up, and later steps reuse that recorded tree from whatever slot claims them. A prune of the first slot's home deletes the tree while another session still works in it. | high | In work-setup.sh, cut per-bead trees outside slot homes or move a recorded tree into the claiming slot before reuse (tk-mp82kwe) (small) | `per-bead-worktree-in-another-slot-home-is-pruned-with-it` |
| S-12 | The Write and Edit tools take absolute paths that ignore the shell's directory, so edits meant for the per-bead worktree land in the slot home or the shared checkout. Nothing at self-review or submit notices that the worktree's diff lacks them. | medium | A check in self-review-check.sh or work-submit.sh that fails when the shared checkout or the slot home has changes while the worktree has none, plus one doctrine line on rooting file paths at the tree work-enter.sh prints (small) | `write-tool-targets-per-bead-worktree-not-pool` |
| S-13 | gctk merge and the board credit a blocker with an actor only through its routing key, so a blocker poured onto a pool run reads as unrouted. The anchor shows as needing a person while a polecat works the blocker. | medium | Count a blocker with a live run or an assignee as having an actor in gctk merge's in-flight read and the board's row (tk-j8dzqmm) (small) | `blocks-edge-on-an-anchor-is-a-merge-hold` |
| S-16 | The pm method has a reviewer raise a presentation finding when the operator has nothing to look at, without saying that a declared demo check attaches its capture only once the draft PR opens. Pre-open pm passes keep filing a must-fix that the rework cannot meet. | medium | One clause in skills/review-pm/SKILL.md that skips the ask when the check set declares demo (small) | `hub-review-lanes-and-fix-units#39` |
| S-17 | A file left at an agent home's root fails the home check on every later start of that slot, and no instruction names where a file a restart needs belongs. | medium | Name the per-bead cache in the scratch fragment (about 12 words), or have the home check move a stray file aside (small) | `agent-home-root-leftover-fails-slot-start-home-sync` |
| S-25 | About twenty scripts copy the GC_CITY_PATH, GC_CITY and GC_CITY_ROOT fallback chain and treat a registered city name as a directory. A shell that carries only the name gets lock and state paths relative to its working directory. | medium | One shared resolver that accepts an absolute path and otherwise asks gc, adopted by the copies outside code the plan retires (medium) | `gc-city-env-can-be-a-city-name-pack-chain-reads-it-as-path` |
| S-27 | The file-design step needs a brief that each run assembles through scratch files and shell variables, with quoting hazards, and the dispatch skips the priority settle. Every run repeats the workaround. | low | Have the step pass the brief from a file through a script call and run the priority settle before dispatch (small) | `mol-design-convoy-polecat-run-fill-and-verify` |
| S-28 | The pre-commit hook that re-renders generated/seed-audit is wired through core.hooksPath in the rig's shared git config, which comes and goes. A commit made without it leaves its render stale, and one made with it can stage renders that drift with the gc binary. | low | Have work-setup.sh wire the hook for each worktree it creates, a few lines (small) | `precommit-hook-hookspath-renders-seed-audit` |
| S-29 | The check carries a hand copy of Gas City's machinery bead types, since no command prints them, so each new upstream type makes it report city machinery as marooned work. | low | Pin the copy with a test against the upstream source at a named commit, or ask upstream to expose the list (small) | `check-hq-marooned-work-false-flags-city-machinery` |
| S-30 | mol-feedback-miner skips a candidate already recorded on the same post, but a self-report filed during the work carries a bead-keyed provenance and never matches. Each run greps observation bodies for the comment by hand. | low | Have feedback-miner.sh's show step also list observations whose body cites the post's comment id or anchor (small) | `feedback-miner-dedup-read-existing-when-provenance-hits` |
| S-31 | gh-origin-guard.sh treats a here-document body that quotes a gh write, such as a bead description with an example command, as a real write to another repository. Its refusal names no way around it. | low | Name the write-a-file route in the deny message, or skip a here-document fed to a command that is not a shell (small) | `gh-origin-guard-reads-bash-command-text-write-scripts-with-write-tool` |
| S-35 | A warning-only Dolt compaction marker clears on the next compactor pass, but the deacon's sweep files it again after each close. It has been filed and closed by hand about twenty times. | medium | retired by tk-1tfzr71.19 | `dolt-compact-pending-gc-writer-race-finding-is-designed-retry` |

## Notes that fit none

1,370 units answer none of the three questions. They hold knowledge that is still true and that the pack does not carry, so none of them is point-in-time, and none points at a wording fault or a structural one. What happens to them is the standing triage's design (tk-zlot608.2).

| Kind | Units | What it is |
|---|---:|---|
| recipe | 627 | A durable how-to with no pack defect behind it. |
| tool-fact | 342 | Durable behaviour of a tool the pack does not own, such as bd, gh, git, jq, a shell, Claude Code or Codex. |
| platform-fact | 164 | Durable Gas City behaviour. |
| unwritten-rule | 159 | A standing rule for agents that no pack instruction carries, and that a rewording cannot add. |
| reference | 33 | A durable pointer or map. |
| design-record | 27 | The reasoning behind a design that still stands. |
| host-fact | 14 | A fact about this machine or its environment. |
| other | 4 | Anything else. |

## How the sort was made

1. A copy of the store was taken at 2026-11-11T21:01:17Z, and every unit was read from
   it. The `sha256` column identifies each file or entry at the copy.
2. The beads and pull requests the units name were read in bulk: 7,283 of the
   7,545 bead ids named resolve, and 1,468 gc-toolkit pull requests. Each unit
   carried the state of what it names, so the live-work test needed no lookup.
3. Read-only classifiers sorted the units in 71 batches. Each was given the
   three questions, the reading of them above, and the repository at main to
   check its answers against. Every batch returned one row per unit, checked
   for completeness and for text a public record must not carry.
4. A second check went over every whole note sorted as point-in-time, after a
   blind sample showed the first pass erred towards deletion (above).
5. The wording fixes were checked by hand at main. Four proposals added 10 to
   17 words. Three were cut to two words or fewer, and the fourth is a
   structural finding, because its instruction was silent rather than
   misleading.
6. One pass grouped the structural units into findings. It sent
   42 units back as not structural.
7. An operator mark is kept only where the unit's own text names the operator.
   9 marks were dropped by that rule.

Limits:

- The entries of collection notes sorted as point-in-time had no second check.
  Nothing removes them until the standing triage does.
- The largest note, at 190 KB, was read in part by its classifier.
- Notes written after the copy are not in this record.
