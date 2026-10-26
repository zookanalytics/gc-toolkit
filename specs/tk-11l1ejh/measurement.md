---
name: Built-once target — the measurements behind it
description: The derivations behind docs/built-once-target.md at main b09345315 — the baseline table, how each subsystem's target was derived from what survives, the whole files each scheduled removal names, the counts behind what has no place in the target, the pack's growth and the ledger of changes since the migration map, and the net of the branches in flight. Read it to check or re-derive a number the doc states.
---

# The measurements behind the built-once target

Every number here was taken at main b09345315 (2026-10-25) unless its row
names another commit. `measure.sh` in this directory produced the tables, and
each other count comes from the command shown with it, run from the
repository root.

## 1. The baseline table

```
$ specs/tk-11l1ejh/measure.sh b09345315
lines at b09345315

kind          lines
code          87911
flow          14168
text           6886
test         141625
docs          15007
tooling       13049
record        60959
generated      7994

subsystem      code     flow     text     test    total
merge         14986     1442      124    25194    41746
visit         12719      618     1648    24015    39000
board         15584       55        0    18448    34087
shared        10922       18        0    19708    30648
patrol         7271     2119      411    15550    25351
review         6946     1997     1633     9977    20553
work           4160     2571       17    12555    19303
doctor         7535       27        0     8913    16475
gctk           5776        0        0     4330    10106
keeper          784     1995     1012     1084     4875
feedback       1133      954      383     1851     4321
config           95     2372        0        0     2467
doctrine          0        0     1658        0     1658
```

The doc's "human engagement" is the `visit` row. Runtime is code, flow and
text: 108,965 lines. Pack weight adds tests: 250,590.

Generated counts the board's typed supervisor client,
`services/helm/web/src/drill/gen/supervisor.d.ts` (3,157 lines), which
openapi-typescript writes from Gas City's API and `npm run gen:supervisor-types`
regenerates. Its generator, `gen-supervisor-types.mjs`, is board code.

Component-model §4 has a row for 104 of the 145 runtime scripts under
`assets/scripts/`. The other 41, 9,131 lines, are placed by the `post` rules in
`measure.sh`. The largest are `bd-lib.sh` (816), `bead-context.sh` (665),
`orphan-dispose.sh` (639), `converse-signoff.sh` (489) and `self-review-check.sh`
(479).

## 2. How each target was derived

Each subsystem's target is the baseline size of what survives it, cut by the
doc's rules: a primitive Gas City ships weighs nothing, a fact is said
once with comments kept to reasons, and tests weigh no more than code and flow.
What survives comes from the migration members' contracts (their Keeps and
Retires) and the native-gates design. The cuts are estimates, rounded to 0.5k
for each subsystem's total.

**Work**, 6,748 to 2,500:

| What survives | Baseline | Target |
|---|---|---|
| `mol-polecat-work.toml`, extending core's `mol-polecat-base` | 1,980 | 500 |
| `mol-design-convoy.toml`, its recipes on `tracks` | 493 | 300 |
| `self-review-check.sh` | 479 | 350 |
| `queue-priority.sh` and `priority-lib.sh`, under their warrant | 1,094 | 800 |
| `deferred-dispatch.sh`'s two residuals, as an event order | 1,811 | 400 |
| the polecat's prompt, agent and order config | 115 | 100 |

Retiring: `work-tree-holder.sh` (317), `await-ruling.sh` (301, into the one
decline call) and `convoy-seed.sh` (158).

**Review**, 10,576 to 4,000:

| What survives | Baseline | Target |
|---|---|---|
| the five check skills, the specialist stance, the rubric ledger | 913 | 900 |
| the demo-capture and gc-demo-script skills | 670 | 650 |
| the demo modalities: `demo-screenshot.sh` and `.mjs`, `demo-repo-artifact.sh`, `demo-deliver.sh`, `rig-demo-capture.sh`, `demo-engine-lib.sh` | 1,660 | 1,250 |
| `mol-rig-demo.toml` | 337 | 200 |
| `review-checks.sh`, the check index reader | 415 | 300 |
| the check loop: `mol-review.toml`, `mol-review-quorum-signoff.toml`, `signoff.sh`'s verdict | 2,079 | 500 |
| the reviewers' prompts and config | 153 | 150 |

Retiring: `finding.sh` (1,428), `gate-ensure.sh` (1,243), `mol-validate.toml`
(599), `review-outcome.sh` (370), `review-workspace.sh` (296), `lane-state.sh`
(172), `migrate-approval-out-of-check-set.sh` (144) and
`validate-dispatch-body.sh` (97).

**Merge**, 16,552 to 2,000:

| What survives | Baseline | Target |
|---|---|---|
| the PR summary and title: `pr-summary-region.sh`, `pr-stack.sh`'s re-render | 750 | 350 |
| the step from a GitHub event to the bead that owns it | part of `pr-facts.sh` | 300 |
| `pr-status-label.sh` | 310 | 230 |
| the refinery's overrides of Gas Town's flow: `mol-refinery-patrol.toml`, `direct-merge-push.sh` | 1,633 | 500 |
| `detached-job.sh`, which runs a gate longer than one tool call | 440 | 330 |
| a reply step in the rework molecule, in place of `review-answer.sh` | 581 | 150 |
| the refinery's prompt and config | 138 | 140 |

Retiring: the rest of `pr-facts.sh` (5,448 in all), `bring-current-guard.sh`
(976), `reconcile-rig-checkouts.sh` (918), `pr-open.sh` (833),
`refinery-reconcile.sh` (498), `branch-supersession.sh` (492),
`pre-open-rebase.sh` (449), `bring-current-audit.sh` (419),
`duplicate-sweep.sh` (395), `scaffolding-sweep.sh` (354),
`convoy-graduate.sh` (321), `rejection-repool.sh` (311), `pace-lib.sh` (250),
`approval-withdraw.sh` (237), `refinery-workspace.sh` (188),
`merge-tail-report.sh` (119), `review-sweep.sh` (116), `review-dismissal.sh`
(99), `record-failure-cap.sh` (89), `review-verdict.sh` (83), `merge.sh` (66)
and two orders (39).

**Human engagement**, 14,985 to 5,500:

| What survives | Baseline | Target |
|---|---|---|
| the conversation doctrine: the converse prompt, its skills, agent config | 1,167 | 900 |
| the first-reaction and mechanik prompts and config | 671 | 650 |
| the terminal surfaces: pickers, bindings, status line, terminal attach | 1,971 | 1,450 |
| `gc-helm.sh`'s verbs that compose native calls | 4,529 | 900 |
| first-reaction exits as native writes (`first-reaction-dispose.sh`) | 1,169 | 300 |
| operator intake (`gc-visit-open.sh`) | 465 | 250 |
| sign-off, reap, rework, PR disposal, engage starters, subject context | 1,886 | 950 |
| the validating closer (`mol-validate-close.toml`) | 203 | 150 |

Retiring, with the native-gates convoy and tk-1tfzr71.13 and .17: the visit
plumbing (`converse-claim.sh`, `converse-hold.sh`, `converse-fold.sh`,
`converse-close-out.sh`, `converse-recheck-hook.sh`, `visit-close.sh`,
`visit-identity.sh`, `gate-visit-sweep.sh` with its order, `mol-visit.toml`,
`work-outcome.sh`), `bead-rehome.sh`, and the remaining small scripts, 2,924
lines in all.

**Board**, 15,639 to 5,000: Go 9,662 to 2,500 (derive and rank, the supervisor
client, the server), web 5,789 to 2,500 (the attention views), and `go.mod`.
The second data plane (`internal/source/beads.go`, 1,280), the visit package
(224) and the TypeScript mirror's parity test (886 lines of test) go. The rest
of the cut is the Helm UX epic's choice of views, so this row is the least
certain.

**Patrol**, 9,801 to 2,500:

| What survives | Baseline | Target |
|---|---|---|
| the witness: HELP-mail triage, salvage, the refinery-queue watch | 1,298 | 500 |
| the deacon: `gc doctor` from an order | 710 | 250 |
| `scratch-reap.sh`, `build-scratch-reap.sh` and their orders | 854 | 650 |
| `dolt-reclaim.sh` and its order, under their warrant | 283 | 230 |
| `quota-park-nudge.sh` and its order, if tk-1tfzr71.18's re-check keeps it | 914 | 600 |
| `order-cadence.sh` and the `ESCALATION:` mail pass | 362 | 200 |

Retiring: the liveness census (1,598 with its order), `doctor-sweep.sh` (643),
`orphan-dispose.sh`'s generic arms (639), `worktree-reap.sh` (617 with its
order), `gc-deacon-ledger.sh` (330), `pin-keepalive.sh` and `boot-health.sh`
with their orders (664), the dog's dance (`file-warrant.sh`, `dance-probe.sh`,
`mol-dog-shutdown-dance.toml` and the dog agent, 591), `branch-context.sh`
(187), and the convoy-check and review-workspace-reap orders.

**Doctor**, 7,562 to 3,000. The checks whose feature survives come to 2,941
lines: epic-closed-implies-ruled, seed-audit-current, config-bound,
cycle-recycle-hook, recycle-capable, demo-toolchain, cadence-live,
wisp-cascade-intact, session-store-scope, hq-marooned-work, state-space,
wait-is-an-edge, and pour-text-current reduced to 150. The three checks of
molecule execution (step-terminal, root-advancing, claim-advancing; 1,489)
become one of about 750, and the dispatch-arm checks one of about 300. The
comment rule takes 3,991 to about 3,200, rounded to 3,000.

**Shared glue**, 10,940 to 5,000:

| What survives | Baseline | Target |
|---|---|---|
| the gh write guard, `gh-origin-guard.sh` and its codex registrar, under their warrant | 1,274 | 950 |
| `render-seed-audit.sh` | 1,072 | 800 |
| the store helpers: `bd-lib.sh`, `bead-store.sh`, `pool-route.sh`, `resolve-route.sh`, `gc-bd-watch.sh` | 1,572 | 700 |
| the human-gate helper and findings: `human-gate.sh` (293 on the convoy's branch), `patrol-finding.sh` | 556 | 550 |
| run cancel, hand-back, one decline call, one read-back before an irreversible act | 564 | 550 |
| outbound sends and PR posts: `upstream-finding.sh`, `pr-post.sh` | 617 | 450 |
| the Go builds: `gc-build.sh`, `icu4c-cgo.sh` | 705 | 400 |
| work's hold and until readers: `hold-lib.sh`, `until-resolved.sh`, `live-work.sh`, `dispatch-path.sh` | 647 | 300 |
| `git-lib.sh`, `standing-kinds.sh`, `shellcheck-run.sh`, `lifecycle.sh`, `finalize-gate.sh`, `branch-end.sh`, `placement.sh` | 779 | 450 |

Retiring: `escalate.sh` (685, which the convoy replaces with `human-gate.sh`),
`step-close.sh` (606), `preexisting-failure.sh` (426), `worktree-setup.sh`
(369), `surface-census.sh` (323), `rework-child.sh` (246),
`rig-check-pre-existing.sh` (137), `gctk-resolve.sh` (117),
`lease-heartbeat.sh` (99), `escalation-rig.sh` (66), `molecule-hold.sh` (62)
and the `gctk-build` order (18).

**gctk**, 5,776 to 1,500: the rig check runner (`internal/cli/rig.go`,
`internal/rig/`, 1,084), `internal/git` (144), the store client cut to what the
records need (662 to about 300), the daemon (172) and `main` (113) come to
about 1,800, and the comment rule takes them to 1,500. `internal/cli/merge.go`
(1,892), `internal/cli/lifecycle.go` with `internal/lifecycle` (1,200),
`internal/cli/pace.go` (143) and pr-status (363) go.

**Feedback**, 2,470 to 2,000; **config**, 2,467 to 700, where the key
registry's 1,791 lines become about 300; **doctrine**, 1,658 to 1,300;
**keeper**, 3,791 to 0.

**Tests**: the target for each subsystem is its target code and flow, rounded:
work 2,500, review 2,000, merge 2,000, human engagement 4,000, board 5,000,
patrol 2,000, doctor 3,000, shared glue 5,000, gctk 1,500, feedback 1,500, in
all 28,500.

## 3. The scheduled removals, whole files

The files each bead's contract retires, with their tests (`X.test.sh` beside
`X.sh`, and a doctor check's `run.test.sh`), summed at the baseline. A bead
that rewrites part of a file retires more than this.

| Bead | Whole files | Lines (of which tests) |
|---|---|---|
| tk-1tfzr71.10 | `worktree-reap.sh`, `worktree-setup.sh`, the worktree-reap and convoy-check orders; 2,233 without the convoy-check order, which tk-tggczbp's branch deletes | 2,264 (1,228) |
| tk-1tfzr71.12 | `step-close.sh`, `work-tree-holder.sh`, `lease-heartbeat.sh`, `molecule-hold.sh` | 3,340 (2,256) |
| tk-1tfzr71.13 | `duplicate-sweep.sh` | 1,053 (658) |
| tk-1tfzr71.14 | `reconcile-rig-checkouts.sh` and its order | 2,716 (1,787) |
| tk-1tfzr71.15 | check-routed-work-claimable | 1,173 (602) |
| tk-1tfzr71.17 | `proactive-scan-sling.sh` and its order | 189 (126) |
| tk-1tfzr71.18 | `file-warrant.sh`, `dance-probe.sh`, the dance formula, the dog agent, `pin-keepalive.sh` with its precheck, `boot-health.sh`, `quota-park-nudge.sh`, their orders | 5,571 (3,402) |
| tk-1tfzr71.19 | `doctor-sweep.sh`, `gc-deacon-ledger.sh`, the four liveness scripts and their order, `orphan-dispose.sh` | 7,859 (4,628) |
| tk-1tfzr71.20 | `refinery-reconcile.sh` and its order, `pace-lib.sh`, `merge-tail-report.sh`, `record-failure-cap.sh`, `bring-current-guard.sh`, `bring-current-audit.sh`, `pre-open-rebase.sh`, `branch-supersession.sh`, `rejection-repool.sh`, `branch-context.sh`, `refinery-workspace.sh`, `preexisting-failure.sh`, `rig-check-pre-existing.sh`, check-refinery-patrol-live | 10,899 (6,106) |
| tk-1tfzr71.21 | `pr-facts.sh`, `review-answer.sh`, `review-dismissal.sh`, check-feedback-routing-owed | 14,850 (8,544) |
| tk-1tfzr71.22 | `gate-ensure.sh`, `lane-state.sh`, `review-outcome.sh`, `approval-withdraw.sh`, `finding.sh`, `mol-validate.toml`, `validate-dispatch-body.sh`, `review-sweep.sh`, `scaffolding-sweep.sh`, `rework-child.sh`, check-gate-marker-provenance, check-gate-integrity | 10,643 (5,459) |
| tk-1tfzr71.23 | `convoy-graduate.sh`, `convoy-seed.sh`, both also deleted by tk-tggczbp's branch | 964 (485) |
| tk-1tfzr71.25 | three wrapper lint rules, `surface-census.sh`, `tools/gc-polecat-metrics.sh`, `migrate-approval-out-of-check-set.sh`, the board's contract parity test | 2,688 (1,293) |
| tk-kvdomjb | the hand-offs `escalate.sh` and `escalation-rig.sh` with its test, at tk-iirrmiw.1's head | 241 (100) |
| tk-o6pd01i | `gate-visit-sweep.sh` with its order, `visit-identity.sh` | 597 (317) |

Counted once, with tk-tggczbp's deletions taken out of tk-1tfzr71.10 and .23,
these come to 64,052 lines.

## 4. The counts behind what has no place in the target

| Count | Result | Command |
|---|---|---|
| copies of the script-dir loop | 122 in 20 files, 30 in `mol-polecat-work.toml` | `git grep -c -E 'for c in "\$\{GC_(PACK_DIR\|RIG_ROOT):-\}"' -- . ':!specs' ':!generated'` |
| copies of the decline sequence | 20: 12 in `mol-polecat-work.toml`, 5 in `mol-rig-demo.toml`, 2 in `mol-validate.toml`, 1 in the polecat doctrine fragment | `git grep -c -F 'run-cancel.sh" --step' -- formulas agents template-fragments packs` |
| copies of its refusal sentence | 29 in 4 files | `git grep -c -F 'NOT cancelling or draining' -- . ':!specs' ':!generated'` |
| copies of the step-close loop | 10 in 5 formulas | `git grep -c -E 'for STEP in ' -- formulas packs` |
| comment share, runtime shell scripts under `assets/scripts/` | 20,834 of 57,691 lines (36%), shebangs excluded | lines matching `^[[:space:]]*#` |
| comment share, Go outside tests | 5,136 of 15,581 (32%) | lines matching `^[[:space:]]*//` |
| comment share, doctor checks | 2,363 of 7,535 (31%) | |
| comment share, the key registry | 1,428 of 1,791 (79%) | |
| comment share, orders | 331 of 496 (66%) | |
| shell inside formula code fences | 3,898 lines of 8,842 | lines between fence markers in `formulas/*.toml` |
| tests whose subject is a formula block | 48 files, 14,351 lines; 12 script tests also extract one | test files naming a formula and a `# >>>` marker, with no script of their own |
| "legacy" in runtime code | 30 mentions in 15 files | `git grep -c -i legacy` over runtime scripts, doctor checks, formulas and service source, keeping the paths `measure.sh` counts as runtime |
| compatibility pieces, with their tests | `molecule-hold.sh` 168; the hand-offs at tk-iirrmiw.1's head 241 (`escalate.sh` 127, `escalation-rig.sh` 14, its test 100) | `wc -l`, and `git show <ref>:<path>` on the branch |
| dead code | 1,675 lines with tests: `surface-census.sh` (431), `tools/gc-polecat-metrics.sh` (507), `migrate-approval-out-of-check-set.sh` (276), `tools/bead-universe-reachability-fixture.sh` (461) | `git grep -l -F <name> -- . ':!specs' ':!generated'` finds no caller |
| commits on the Gas City fork's main that upstream main lacks | 102, at upstream f78779e41 | `git -C rigs/gascity rev-list --count upstream/main..origin/main` |

The native primitives the doc names were verified present at Gas City upstream
main f78779e41 on 2026-10-26: `cmd/gc/cmd_worktree.go` (`gc worktree`),
`cmd/gc/cmd_hook_current.go` (`gc hook current`),
`auto_reap_closed_bead_worktrees` in `docs/reference/config.md`, the PR monitor
in `cmd/gc/cmd_github.go`, `[[webhook]]` in `docs/reference/config.md`,
`--no-formula` in `cmd/gc/cmd_sling.go`, and core's orders under
`internal/bootstrap/packs/core/orders/`: convoy-autoclose-backstop,
orphan-sweep, reaper, wisp-compact, spawn-storm-detect, prune-branches,
notify-on-human-gate-creation and renudge-stale-human-gates. `bd duplicate` and
`bd supersede` are in the installed bd 1.3.2. Store maintenance there still
runs observe-only (`engdocs/contributors/dolt-maintenance.md`), so the Dolt
reclaim warrant holds. Core's `mol-polecat-base` has a load-context step at
f78779e41 with no duplicate-dispatch gate in it. The gate is the fork's
(29f4f2137, revised at a319c2fd6), and upstream main has neither commit.

## 5. Growth

Pack weight on main, at the last first-parent commit before each date:

| Date | Commit | Code | Flow | Text | Test | Pack weight |
|---|---|---|---|---|---|---|
| 2026-08-01 | 763e2825f | 9,292 | 8,833 | 5,061 | 6,208 | 29,394 |
| 2026-09-01 | 2ff5ddd60 | 23,813 | 6,125 | 4,177 | 31,805 | 65,920 |
| 2026-09-15 | 98419730d | 42,877 | 8,862 | 4,695 | 59,502 | 115,936 |
| 2026-10-01 | c8062093a | 55,592 | 10,735 | 4,984 | 75,151 | 146,462 |
| 2026-10-15 | 132909cb5 | 79,519 | 13,242 | 5,966 | 120,281 | 219,008 |
| baseline | b09345315 | 87,911 | 14,168 | 6,886 | 141,625 | 250,590 |

The migration map was read at 35cf7c70f, the base of the native-gates
convoy's branch. These changes landed on main after it, net lines by
`measure.sh <commit>^ <commit>`:

| Commit | Change | Runtime | Tests | Pack |
|---|---|---|---|---|
| b399e485c | chore: Foundation states the use-upstream-as-is rule | +3 | +0 | +3 |
| e07af7197 | docs: Split the gascity-*.md pages | +3 | +3 | +6 |
| 262649845 | fix: A design-convoy subject closes when its owned convoy lands | +78 | +563 | +641 |
| cb33672a6 | fix: Answer each human review round in one living-answer comment | +198 | +398 | +596 |
| 7ed87f73f | chore: the arch check holds new operational surface to Gas City's docs | +0 | +26 | +26 |
| 9bb2be58d | chore: Correct the comments that say a workflow step has no assignee | −8 | −6 | −14 |
| 5efa7c218 | chore: Point the topology exclusion comments at Gas City's check | +5 | −2 | +3 |
| 7bf4411ae | chore: Correct the proactive pool's topology exclusion comments | +1 | +0 | +1 |
| be047f3d0 | chore: Steer by epic, unit 6: PR-finishing rank and its invariant | +492 | +1,091 | +1,583 |
| 0a91d69c5 | chore: The arch check sends back a commit with no docs/architecture.md | +17 | +6 | +23 |
| 974f87e03 | chore: Show a declined or deferred review point as needing the reviewer | +108 | +337 | +445 |
| a5e5c2cd2 | fix: The named-agent rule gives its real reason, and pool-slot-reap retires | −483 | −677 | −1,160 |
| 4118d877f | chore: Design: a PR is one reviewable unit | +0 | +0 | +0 |
| 7f885aac8 | fix: The witness gives back a visit whose sitting never started | +163 | +641 | +804 |
| 0af80d890 | fix: The refinery pushes a prepared head only for the bead its worktree holds | +143 | +422 | +565 |
| b232afa4b | fix: The polecat gives a bead back in one guarded write | +173 | +639 | +812 |
| 0dd5791f6 | chore: A review is one lifecycle formula plus one skill per check | +409 | +758 | +1,167 |
| b09345315 | fix: A rejected graduation is rebuilt on an ordinary child bead | +300 | +745 | +1,045 |

Of the 18, 15 grew the pack and 2 shrank it. Together they added 1,602 lines
of runtime and 4,944 of tests, 6,546 in all. The six fixes that grew it added
1,055 lines of runtime and 3,408 of tests.

## 6. The branches in flight

Net lines by `measure.sh <merge base> <branch head>`, on 2026-10-26:

| Branch | Head | Merge base | Runtime | Tests | Pack |
|---|---|---|---|---|---|
| `integration/tk-iirrmiw` (native-gates units A and B) | 8c895c258 | 35cf7c70f, on main | +247 | +2,064 | +2,311 |
| `polecat/tk-5u2xpan` (unit C) | c45343824 | 8c895c258, on `integration/tk-iirrmiw` | −1,006 | −4,731 | −5,737 |
| `polecat/tk-iirrmiw.1` (the integration fix) | a79c16f89 | b11e0b262, on `integration/tk-iirrmiw` | +226 | +429 | +655 |
| `integration/tk-tggczbp` (the one-bead PR model) | be958eeb8 | b09345315, on main | −204 | −64 | −268 |

The native-gates convoy nets −2,771 across its branches so far. The one-bead
PR model's branch changes 120 files, adding 4,761 lines and deleting 4,990.
