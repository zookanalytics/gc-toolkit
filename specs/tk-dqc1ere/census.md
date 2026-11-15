---
name: The pack suite's process-start census, and the cuts made from it
description: Use when you look for the process starts that cost the pack's suite most, rerun the census on a later commit, or check the measurements behind tk-dqc1ere's cuts.
---

# The pack suite's process-start census

Main stood at 65a86b0e7 when these were taken, on 2026-11-15 (MST), on the
city's macOS host. Main's macOS check at that commit (run 43691629333) summed
5,812 test-seconds over 280 runs of 258 files, 2,341 of them in files
`tools/deletion-plan.tsv` lists and 3,471 in the files it keeps. tk-dqc1ere's
target, half of run 41978698787's 4,643, is at most 2,321, which the kept files
alone exceed.

## Method

Every non-interactive bash loads the file `BASH_ENV` names, so a profile there
sees every bash the suite starts, and the scripts under test with them:

- At start it logs the process's `$0`, the `$0` of the bash that started it,
  and the suite it belongs to, which it exports when `$0` is a `*.test.sh`.
- It defines a function for each of 49 common commands, among them jq, tr,
  grep, sed, cat, dirname, mktemp, rm, git, gh and timeout. Each logs the
  command, the file and line that called it, the running script's `$0` and
  the suite, then runs the real command through `builtin command`.
- It defines `command` too, so that `command -v` of a wrapped name prints the
  name's path on PATH. Without that, `$(command -v jq)` prints `jq`, and a
  suite's jq shim that runs `exec "$REAL_JQ"` runs itself until it is killed.

The whole suite then ran under `tools/run-tests.sh -j 5 --no-retry` from a
detached worktree of main, under `env -i` with a TMPDIR under `~/.cache`.

Limits:

- `gc-helm.sh` and `gh-origin-guard.sh` run under sh, which loads no
  `BASH_ENV`, so their starts are not counted.
- A command started by its absolute path or by `exec`, and whatever `timeout`,
  `env` or `xargs` starts, is not counted, so the counts are a floor.
- 30 of the 280 runs failed under the profile, the `gc-helm.sh` suites among
  them, so their counts stop where they failed. All 280 pass on main without
  it.
- A script that defines `scrub` and then sources a library that defines it
  again runs the library's copy, so its tr starts are logged at the library's
  line. They are read by the running script's `$0` instead.
- A start's cost is estimated from the per-start costs measured on this host
  for tk-a5mwcic.1 (`specs/tk-a5mwcic.1/measurements.md`): jq 4.3 ms, git 7.5,
  bash 6.5 and 3 for most other commands. The estimate ranks call sites, and
  only paired runs time them.

## What the suite starts

Over the whole run: 234,166 jq, 42,781 tr, 31,055 cat, 27,999 dirname, 25,418
grep, 22,576 git, 20,235 awk, 15,626 sed, 13,132 mv and 10,001 rm, and 102,782
bash processes, 54,254 of them the suites' `gc` stubs.

The shared libraries' busiest lines start mostly on behalf of code the
deletion plan retires:

| Line | Starts | Of them, from scripts the plan retires |
|---|---|---|
| `bd-lib.sh` `bd_list`'s array check | 9,371 jq | 8,878, chiefly `pr-facts.sh`, `finding.sh`, `lane-state.sh` and `gate-ensure.sh` |
| the `scrub` `run-lib.sh` defines | 9,424 tr | 7,358, 7,002 of them from `pr-facts.sh` |
| `bd-lib.sh` `_bd_store_joined` | 2,528 jq | 2,497, chiefly `pr-facts.sh` and `lane-state.sh` |

The kept scripts whose own starts cost most, by the estimate above:

| Script | Estimated seconds | Carried by |
|---|---|---|
| the doctor checks' `run.sh`, together | 77.5 | no one bead; `check-session-store-scope`'s `env_val` was cut here |
| `render-seed-audit.sh` | 49.5 | the move, tk-ssm8qns.10 |
| `converse-signoff.sh` | 46.4 | cut here in part |
| `rig-map.sh` | 43.2, and 2,973 bash starts | cut here in its callers |
| `queue-priority.sh` | 41.4 | the move, tk-ssm8qns.7 |
| `bead-rehome.sh` | 33.2 | cut here |
| `pr-post.sh` | 25.6 | the move, tk-ssm8qns.8 |
| `signoff.sh` | 22.2 | cut by tk-nalm16x |

`lifecycle.sh` and the `dirname` in `gctk-resolve.sh` it sources start mostly
for the transition machine, which tk-1tfzr71.70 retires.

## What was cut

- `bead-rehome.sh` read the rig map four times a run: through two runs of
  `bead-store.sh`, and through a memo that each `$( )` subshell set and
  dropped. `bead-store.sh`'s derivation is now sourceable, and `bead-rehome.sh`
  reads the map once.
- `bead-rehome.sh` and `converse-signoff.sh` read the fields of a row in one
  jq, where they ran one per field.
- `bd_human_gates` and `bead-rehome.sh`'s store reads skip the notice strip and
  scrub for a read of one line, as `bd_json` does.
- `check-session-store-scope`'s `env_val` reads a value by parameter expansion,
  where it ran `sed` and `head`.

## Paired timings

Each pair ran main's tree (65a86b0e7) and the branch's at the same moment,
under `env -i`, with other agents' work running beside them.

- **The whole suite**, `tools/run-tests.sh -j 3` from each tree, 10:43 to
  11:09Z, with the branch at 5b8e7d848. Both passed 280 of 280 runs, in 1,576
  and 1,565 s of wall time. Summed, main took 4,724 test-seconds and the
  branch 4,692. The five suites below went from 387 to 288, and the other 275
  runs came out 1.5% slower on the branch side, a few seconds a file.
- **One suite at a time**, at the head's code, at a load of 6 to 8.

| Suite | Whole suite: main | branch | One at a time: main | branch |
|---|---:|---:|---:|---:|
| `bead-rehome.test.sh` | 98 | 56 | 71.7 | 37.8 |
| `stand-down.test.sh` | 109 | 68 | 83.1 | 59.3 |
| `converse-signoff.test.sh` | 149 | 140 | 106.5 | 99.8 |
| `doctor/check-session-store-scope/run.test.sh` | 27 | 21 | 18.4 | 13.8 |
| `bead-store.test.sh` | 4 | 3 | 2.6 | 2.6 |

The suites of the scripts that reach the changed ones, among them
`finalize-gate`, `human-gate`, `await-ruling`, `first-reaction-dispose`,
`converse-rework` and `gc-helm-accept`, moved by two seconds or less in the
whole-suite pair.

## What was not cut, and why

- `rig-map.sh` starts about 20 ms of processes a run besides `gc`: its bash,
  `mktemp`, `timeout`, jq and `rm`. The temporary file keeps `gc`'s stderr for
  the reason a failed listing gives, and bash has no way to remove it without
  a process, so the cut is in how often it runs.
- A scrub ahead of a pretty-printed read could be skipped by letting jq parse
  the read first, because jq 1.8.2 refuses every raw C0 byte inside a string
  and takes only tab, newline and carriage return between tokens. It refuses
  with exit 5, as it does for a runtime error, so the read would need a second
  jq whenever it refuses, and the equivalence would rest on jq's strictness.
  The cuts here hold whatever jq does.
- The test side of these suites, their stubs and their jq, is the testing
  epic's (tk-a5mwcic), whose design moves them onto a compiled fake.
