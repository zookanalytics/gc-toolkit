---
name: Measurements behind the testing-strategy design
description: Use when you check a number in design.md beside it, re-measure the suite's cost against the five-minute budget, or repeat the host profile on a later commit. It holds the CI figures and the host profile taken for tk-a5mwcic.1, with the method and the limits of each.
---

# Measurements behind the testing-strategy design

Main stood at a4ee5ae43 when these were taken, on 2026-11-13 and 14 (MST).
"macOS" and "Linux" mean the `test-macos` and `test` checks of
`.github/workflows/tests.yml`. A test-second is one second of one run's wall
time, as `tools/run-tests.sh` reports it on its `PASS <file> (<n>s)` line, and
a suite's summed test-seconds is the sum of those lines over one job's log.

## CI

### The checks at a4ee5ae43

Run 43560099589, read with `gh run view 43560099589 --json jobs` and each job's
log from `gh api repos/zookanalytics/gc-toolkit/actions/jobs/<id>/logs`.

| Check | Job id | Job | Before the suite | Suite (run-tests) | Parallel | Runs | Summed |
|---|---|---|---|---|---|---|---|
| test-macos | 132341660079 | 05:10:34 to 05:39:25, 28m51s | 37 s (checkout 4, setup-go 16, brew 16) | 1,687 s | 3 | 284 runs of 263 files | 5,059 |
| test | 132341660206 | 05:09:03 to 05:29:17, 20m14s | 13 s | 1,199 s | 4 | 284 runs of 263 files | 4,115 |
| go | 132341659899 | 05:09:03 to 05:12:10, 3m07s | 25 s | gctk vet and test 21 s; helm vet and test 2m17s, its first test result 1m52s in | — | — | package times sum to about 25 s |

The job's wall less run-tests' own time was 44 s on macOS, which is the
overhead the budget uses.

### The suite over time

The last successful push run on main each day, from `gh run list --workflow
tests.yml --branch main --event push`. Summed test-seconds come from the job
logs.

| Day | Commit | Linux files and runs | Linux summed | Linux job | macOS summed | macOS job |
|---|---|---|---|---|---|---|
| 2026-09-06 | 2bfd075ea | 110 | 464 | 2.6 min | — | — |
| 2026-09-20 | 63395fc14 | 137 | 757 | 3.8 min | — | — |
| 2026-10-01 | 2c52bbbaa | 165 | 613 | 3.1 min | — | — |
| 2026-10-12 | cf1ba3fc7 | 222 files, 241 runs | 1,536 | 6.7 min | 2,636 | 15.4 min |
| 2026-10-20 | 5efa7c218 | 253 files, 273 runs | 2,460 | 10.7 min | 4,644 | 26.8 min |
| 2026-10-27 | 40a808d08 | 258 files, 279 runs | 2,692 | 11.5 min | 5,403 | 31.2 min |
| 2026-11-02 | 39c69e501 | 264 files, 293 runs | 4,884 | 20.6 min | 7,642 | 43.4 min |
| 2026-11-07 | a45da5bf9 | 265 files, 286 runs | 3,949 | 19.5 min | 4,959 | 28.4 min |
| 2026-11-14 | a4ee5ae43 | 263 files, 284 runs | 4,115 | 20.2 min | 5,059 | 28.9 min |

Per file, with a file's parts summed and a file matched by its path:

- **macOS, 2026-10-12 to 2026-11-14:** 95 files new by path brought 1,260
  test-seconds, 54 files gone by the end took 322 away, and the 168 files present
  at both ends went from 2,314 to 3,799.
- **Linux, 2026-09-06 to 2026-11-14:** the 83 files present at both ends went
  from 411 to 2,441.
- **The same 210 files, 2026-10-27 to 2026-11-14:** Linux 2,490 to 3,461, macOS
  4,982 to 4,373. Over the whole suite, Linux's summed test-seconds as a share of
  macOS's rose from 0.50 to 0.81 in those weeks. The Linux runner image moved
  from 20261021.618 to 20261103.629 in that time, and this design does not
  depend on the cause.

### The spread between runs

| Commit | Run | macOS job | macOS summed | Linux summed |
|---|---|---|---|---|
| c3d9f4e32 | 43517883519 | 28.7 min | 5,054 | 3,774 |
| 46e03c4ed | 43534972900 | 26.8 min | 4,712 | 3,704 |
| 1d744d59f | 43541854579 | 36.2 min | 6,341 | 3,735 |
| a4ee5ae43 | 43560099589 | 28.9 min | 5,059 | 4,115 |

46e03c4ed and 1d744d59f are consecutive runs whose suites cost Linux within 1%
of each other, and between them the macOS check's time moved by 1.35. One
change touching the merge path landed between them (d3d1571d8). Per run, a file
or one of its parts, over the runs of at least 10 s in the first:

| | Runs | Median ratio | 5th percentile | 95th percentile |
|---|---|---|---|---|
| macOS | 100 | 1.27 | 1.04 | 1.62 |
| Linux | 86 | 1.00 | 0.90 | 1.09 |

Every successful main run from 2026-11-12 to a4ee5ae43 ran the macOS suite 3
parallel and took the macOS check 26.8 to 44.0 minutes, and the Linux check 15.4
to 23.5. The next main run, 43568696149 at 45e9ddb41, got a macOS runner with
five cores on the same image (macos-26-arm64 20261102.0473.1): 5 parallel,
4,705 summed test-seconds in a 941 s suite, and a 16.4-minute job. The PR runs
that started at 06:44Z and 07:08Z, either side of it, ran 3 parallel. Each
job log's `run-tests: ... N parallel` line gives the count.

### Where the suite's time sits at a4ee5ae43

A file is retiring when `tools/deletion-plan.tsv` lists it. A file's subsystem
is the one `tools/measure.sh` gives its script: section 4 of
`docs/component-model.md`, else measure.sh's own rules.

| Part | Files | macOS | Linux |
|---|---|---|---|
| Whole files the deletion plan retires | 42 | 1,848 | 1,701 |
| of which tk-1tfzr71.21, `pr-facts.test.sh` among them | 4 | 1,098 | 1,117 |
| of which tk-1tfzr71.22 | 11 | 279 | 230 |
| of which tk-1tfzr71.19 | 7 | 196 | 139 |
| of which tk-1tfzr71.20 | 13 | 181 | 122 |
| of which tk-1tfzr71.18 | 6 | 94 | 93 |
| of which tk-1tfzr71.17 | 1 | 0 | 0 |
| `merge.test.sh` (tk-1tfzr71.20) and `deferred-dispatch.test.sh` (tk-1tfzr71.16) | 2 | 211 | 185 |
| Suites the merge member's branch deletes that the plan's rows do not list (tk-1tfzr71.20) | 10 | 95 | 48 |
| Kept: the move's queued Features and tasks | 13 | 512 | 389 |
| Kept: `gc-helm.sh` suites no Feature moves | 10 | 209 | 143 |
| Kept: engagement scripts no Feature names | 18 | 489 | 332 |
| Kept: the rest, by subsystem: shared 521, review 288, doctor 259, merge 193, work 153, patrol 110, unplaced 109, feedback 41, engagement 11, keeper 10 | 168 | 1,695 | 1,317 |

The ten are `assets/scripts/<name>.test.sh` for check-set-normalize,
find-work-gating-guard, mr-aware-rejection-failclosed, one-anchor-per-pr,
pr-stack, preexisting-failure-dedup, refinery-human-gate-wiring,
refinery-prep-worktree, rig-check-commands and unrecorded-direct-landing. Each
is deleted on `integration/tk-1tfzr71.20` at 2f3f1c1d3, read with
`git diff --name-status --diff-filter=D origin/main...origin/integration/tk-1tfzr71.20`.
The other live integration branches delete no test file other than
`deferred-dispatch.test.sh`.

Spread of the 221 files the deletion plan keeps, merge.test.sh and
deferred-dispatch.test.sh among them, on macOS: 14 files of 60 s or more hold
1,378; 37 files of 20 to 59 s hold 1,135; 59 files of 5 to 19 s hold 541; 111
files under 5 s hold 157. Over the 209 kept files: 12 files of 60 s or more
hold 1,167; 35 of 20 to 59 s hold 1,073; 54 of 5 to 19 s hold 510; 108 under
5 s hold 155. The median kept file takes 4 s.

Of the 209 kept files, 126 write a gc stub of their own (a line that redirects
into a path ending in `/gc`). They hold 2,408 of the kept ground's 2,905 macOS
test-seconds. 22 of the 209 call `harness_init` of `test-harness.sh`.

### What each check caught

`gh run list --workflow tests.yml --event pull_request --created '>=2026-10-08'`
returned 1,000 runs, the API's limit, from 2026-10-08T23:19Z to 2026-11-14:
693 passed, 170 skipped as drafts, 107 cancelled, 28 failed and 2 still
running. Of the 28:

| Failed checks | Runs |
|---|---|
| test and test-macos | 21 |
| test only, test-macos passed | 3 (`blocker-holder.test.sh`, `queue-priority.test.sh`, `branch-end.test.sh`) |
| test-macos only, test passed | 2 (`preexisting-failure.test.sh` in run 38212434528, `liveness-sweep.test.sh` in run 38149711904) |
| test, with test-macos cancelled | 2 |

Both macOS-only failures failed the serial re-run too. Their fixes, 87936ea3a
and 13fa10a16, record one cause: `$name…` with no braces, where bash 5.3 on
macOS, in a UTF-8 locale, read the ellipsis's first byte into the variable's
name and `set -u` stopped the script.

### The Linux outlier

`assets/scripts/step-number-citation.test.sh`, added by 88617e371 (#1411) on
2026-11-06, took 244 s at a45da5bf9 (2026-11-07), and 204, 204, 232 and 256 s at
c3d9f4e32, 46e03c4ed, 1d744d59f and a4ee5ae43, on Linux. It took 4 to 6 s on
macOS. It reads every tracked text file in one `xargs awk` pass whose regular
expression is built from every formula and skill name.

## The host profile

The host is the city's macOS machine: 18 cores, `/opt/homebrew/bin/bash` 5.3.20,
jq 1.8.2, Go 1.27.4. Every suite ran from this branch's worktree at a4ee5ae43,
under `env -i` with HOME, USER, `LANG=en_US.UTF-8`, a PATH of
`/opt/homebrew/bin:/usr/local/go/bin:/usr/bin:/bin:/usr/sbin:/sbin`, and a
TMPDIR under `~/.cache`, six suites at a time. The load average was 4 to 20
while they ran.

### Cost of one start

A loop of N calls, timed with `$EPOCHREALTIME`, in ms per call:

| Program | Load about 11 (N = 200, 500, 500) | Load 17 to 20 (N = 300, twice) |
|---|---|---|
| `/usr/bin/true` | 1.83 to 1.91 | 2.69 to 2.90 |
| a Go program that does nothing | 2.81 to 5.02 | — |
| `cat`, `tr`, `dirname`, `grep`, `sed` | — | 2.66 to 3.52 |
| `jq` | 3.62 to 4.31 | 4.65 to 4.96 |
| `jq` inside `$( )` | — | 5.80 to 6.96 |
| `git --version` | — | 7.40 to 7.55 |
| `bash -c :` | 6.35 to 6.62 | 8.87 to 8.95 |
| the harness's gc stub, `bd show --json` | 12.67 to 13.34 | — |
| the harness's gc stub, `bd update --set-metadata` | 15.55 to 19.10 | — |
| `meta()`, the harness's jq read of one key | 3.64 to 5.05 | — |
| a compiled stand-in, `bd show --json` | 3.49 to 4.56 | — |
| a compiled stand-in, `bd update --set-metadata` | 3.19 to 4.73 | — |

The stub calls ran against a store of 40 beads with 12 metadata keys each. The
compiled stand-in was about 90 lines of Go answering those two verbs from the
same store file, built for this measurement and not committed.

### The profiled suites

The 24 suites were chosen from the costliest kept suites, leaving out
`merge.test.sh`, `deferred-dispatch.test.sh`, `signoff.test.sh` and
`pr-open.test.sh`. They hold 1,571 of the kept ground's 2,905 macOS
test-seconds. Each passed in every run below, except as noted.

- **Plain run:** each suite under `/usr/bin/time -p`. Their walls summed 1,156 s,
  and their CPU 940 s: 369 s user and 571 s system, a 61% system share and 0.81
  of a core per suite. `detached-job.test.sh` waits rather than works: 2 s of
  CPU in 25 s of wall.
- **Process profile:** BASH_ENV named a file that every non-interactive bash
  loads. It records the process's `$0`, its start after bash's own setup, and
  its end, from an EXIT trap, and it exports the name as the caller of anything
  the process starts.
- **jq attribution:** a jq first on PATH that logs its caller and execs the real
  jq.
- **Census:** a small C program first on PATH under the name of each of 66
  common commands. It logs the name and the caller, then execs the real
  program by its absolute path. `check-session-store-scope` failed 9 of its
  cases under it, and the counts keep that run.

| Suite | macOS CI s | Linux CI s | Host wall s | Host CPU s (user + sys) | Stub calls | Stub share | jq by test file / stubs / script | Projected saving |
|---|---|---|---|---|---|---|---|---|
| `assets/scripts/gc-helm-engage.test.sh` (sh) | 173 | 152 | 173 | 106 (41 + 66) | 2445 | 33% | 6565 / 3167 / 182 | 42% |
| `assets/scripts/stand-down.test.sh` | 130 | 75 | 101 | 84 (33 + 50) | 2038 | 27% | 182 / 2015 / 5575 | 20% |
| `assets/scripts/bead-rehome.test.sh` | 118 | 76 | 87 | 79 (31 + 48) | 1560 | 29% | 0 / 633 / 4538 | 22% |
| `assets/scripts/render-seed-audit.test.sh` | 101 | 71 | 69 | 76 (29 + 47) | 1 | 0% | 0 / 0 / 113 | 0% |
| `assets/scripts/demo-engine-lib.test.sh` | 99 | 44 | 59 | 52 (19 + 33) | 0 | 0% | not counted | 0% |
| `assets/scripts/converse-signoff.test.sh` | 87 | 65 | 94 | 89 (35 + 54) | 2348 | 33% | 1861 / 2237 / 5053 | 31% |
| `assets/scripts/work-submit.test.sh` | 87 | 37 | 58 | 45 (18 + 26) | 865 | 18% | 267 / 743 / 1291 | 14% |
| `assets/scripts/gc-helm-accept.test.sh` (sh) | 82 | 51 | 54 | 45 (17 + 28) | 896 | 42% | 2268 / 1950 / 425 | 52% |
| `assets/scripts/queue-priority.test.sh` | 78 | 46 | 45 | 33 (14 + 19) | 754 | 33% | 270 / 1470 / 1958 | 29% |
| `assets/scripts/gh-origin-guard.test.sh` (sh) | 60 | 44 | 46 | 34 (11 + 22) | 0 | 0% | 1803 / 0 / 0 | 16% |
| `assets/scripts/patrol-finding.test.sh` | 52 | 35 | 35 | 28 (12 + 16) | 632 | 41% | 220 / 1384 / 1334 | 36% |
| `assets/scripts/gc-helm-open.test.sh` (sh) | 51 | 40 | 50 | 29 (12 + 17) | 699 | 28% | 2201 / 657 / 119 | 40% |
| `assets/scripts/bead-context.test.sh` | 46 | 29 | 34 | 25 (10 + 14) | 419 | 32% | 128 / 961 / 1600 | 29% |
| `assets/scripts/worktree-setup.test.sh` | 45 | 15 | 34 | 20 (8 + 12) | 0 | 0% | 12 / 0 / 0 | 0% |
| `assets/scripts/effort-bring-current.test.sh` | 44 | 7 | 32 | 23 (9 + 14) | 134 | 5% | 157 / 106 / 87 | 5% |
| `assets/scripts/self-review-check.test.sh` | 43 | 18 | 40 | 29 (12 + 17) | 340 | 7% | 300 / 93 / 1284 | 7% |
| `doctor/check-armed-dispatch-owed/run.test.sh` | 41 | 31 | 35 | 19 (8 + 12) | 469 | 52% | 60 / 598 / 354 | 48% |
| `assets/scripts/conversation-merge-hold.test.sh` | 36 | 22 | 25 | 18 (7 + 11) | 437 | 44% | 823 / 1374 / 187 | 50% |
| `assets/scripts/feedback-miner.test.sh` | 36 | 26 | 29 | 25 (11 + 15) | 595 | 26% | 409 / 432 / 1765 | 24% |
| `assets/scripts/work-setup.test.sh` | 36 | 17 | 30 | 22 (9 + 13) | 301 | 14% | 133 / 348 / 532 | 12% |
| `assets/scripts/gc-helm-place.test.sh` (sh) | 36 | 24 | 29 | 23 (10 + 13) | 648 | 31% | 1373 / 833 / 184 | 41% |
| `doctor/check-session-store-scope/run.test.sh` | 33 | 26 | 23 | 16 (5 + 11) | 232 | 23% | 0 / 0 / 0 | 18% |
| `assets/scripts/detached-job.test.sh` | 30 | 26 | 26 | 2 (1 + 1) | 0 | 0% | 0 / 0 / 0 | 0% |
| `assets/scripts/first-reaction-dispose.test.sh` | 27 | 22 | 24 | 17 (8 + 10) | 601 | 27% | 180 / 153 / 821 | 20% |

The stub calls are the bash processes named gc, bd, gh, git, tmux and the other
stand-ins the suites put on PATH. A stub's share is the time inside those
processes plus one bash start each, 6.4 ms, over the suite's wall. The
projected saving puts a compiled call, 4.0 ms, in place of each stub call, and
takes away each jq the test file starts, 4.0 ms each. Every total uses the
costs measured at a load of about 11.

`(sh)` marks a suite whose script under test runs under sh, which loads no
BASH_ENV. Its script's starts are counted under its test file.

**The census.** The 24 suites started 180,166 processes through the 66 commands
counted, and 16,394 stub processes besides, which their absolute interpreter
lines start without a PATH lookup. By command: jq 65,772 (36.5%), cat 14,766,
tr 14,444, bash 11,413, grep 9,495, git 7,089, dirname 6,188, rm 5,612, sed
5,391, mv 4,196, awk 3,668, mktemp 3,357, basename 3,327, head 3,313, cut 3,118,
timeout 3,102, mkdir 1,997, ln 1,722, date 1,400, env 1,274 and sleep 1,154.

By caller, in the 19 suites whose script under test is bash: the test files
started 24,045 (18%), the stubs 11,707 stub processes and 22,690 children
(26%), and the scripts under test 75,341 (56%). Of their 44,045 jq, the test
files started 5,006 (11%), the stubs 12,547 (28%) and the scripts 26,492 (60%).

**Starts against CPU.** At the costs measured at a load of 17 to 20, the
counted starts come to about 1,000 s: jq about 395, the stub processes 146,
the PATH-started bash 102, git 53, and the rest about 307 at 3.2 ms each. The
plain run went at a load of 4 to 10, where a start costs about 0.7 of that, so
the starts are about 700 of its 940 CPU seconds, about three quarters. That is
an estimate. The system share of 61% was measured.

### The shared-harness suites

The same profile, for the kept suites that call `harness_init` and spend
anything in stubs, with `pr-facts.test.sh` beside them:

| Suite | Host wall s | Stub calls | Stub share | Projected saving |
|---|---|---|---|---|
| `bd-lib.test.sh` | 9 | 203 | 35% | 26% |
| `review-workspace.test.sh` | 12 | 96 | 7% | 4% |
| `blocker-holder.test.sh` | 12 | 45 | 5% | 4% |
| `branch-end.test.sh` | 14 | 114 | 9% | 6% |
| `pr-stack.test.sh`, deleted on the merge member's branch | 17 | 335 | 22% | 14% |
| `scratch-reap.test.sh` | 30 | 0 | 0% | 0% |
| `pr-open.test.sh` | 38 | 947 | 26% | 16% |
| `pr-facts.test.sh`, retiring, all parts in one run | 812 | 21,860 | 35% | 24% |

### gctk's build

`go build ./cmd/gctk` took 4.3 s with an empty build cache and the modules
already downloaded, and 0.3 s with the cache warm. Thirteen suites build gctk
for themselves, so the builds are a few seconds of the suite.

## The platform's own fakes

Read at Gas City upstream (gastownhall/gascity) dc5486b99, 2026-11-14:

- `internal/beads/memstore.go`: `MemStore`, "an in-memory Store implementation
  ... exported for use as a test double in cross-package tests".
- `internal/beads/beadstest/conformance.go`: `RunStoreTests`, one suite every
  `beads.Store` implementation runs.
- `internal/beads/beadstest/fake_bd.go`: `FakeBd`, "a minimal, stateful
  stand-in for the bd CLI, backed by a MemStore", which plugs into a `BdStore`
  as its `beads.CommandRunner`.
- `test/acceptance/beads_cli_contract_test.go`, behind the build tag
  `acceptance_bd_contract`: every bd command Gas City depends on, run when the
  beads pin moves.

gctk's own module carries the store adapter's fake (`internal/gcbd/fake`) and
its acceptance test (`internal/gcbd/acceptance_test.go`, opt-in through
`GCTK_STORE_ACCEPTANCE=1`, needing bd and dolt on PATH).

## Limits

- The host profile ran beside the city's agents, so its absolute times move
  with load. Its shares and counts hold better than its seconds, and the CI
  numbers are the ones the budget uses.
- A process that sets its own EXIT trap replaces the profile's, so its record
  is lost. The stubs set none, so the stub counts are whole, while the counts of
  script runs are not.
- The census counts the 66 commands named, and only when a PATH lookup starts
  them. A program started by its absolute path, or a command outside the 66,
  is not counted, so the census is a floor.
- The projections for units 3 to 5 assume the fake's per-call cost of the
  compiled stand-in and the removal of every jq a test file starts. A suite whose
  fake reads cost more, or whose test file keeps some jq, saves less.
