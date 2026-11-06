---
name: Where the pack suite's test-seconds go
description: Read before working on the pack test suite's run time, or before choosing what to cut next to bring its summed test-seconds down. It records the profile taken on tk-pgl0s8j, what that bead cut, and the call sites that hold most of what is left.
---

# Where the pack suite's test-seconds go

## How it was measured

Each suite was run with bash's xtrace on, a trace line carrying
`$EPOCHREALTIME`, the file and the line, written to a descriptor of its own
(197, because the pass locks in `bd-lib.sh` and `queue-priority.sh` take 9).
The gap after a trace line is the time that line took, so the gaps summed by
command name, by file and by `file:line` show where a run's time goes.
Exporting `SHELLOPTS=xtrace` traces every bash process a suite starts, the
scripts under test and the stubs included. A traced run is slower than a plain
one, and the trace inflates builtins most, so these shares rank call sites; they
are not timings.

Before-and-after timings come from paired runs: the same suite run at once from
a worktree of main and from the branch, so both share the host's load. Single
runs on this host vary by half or more with the load other agents put on it.

## What the time is

In every suite profiled (deferred-dispatch, finding, gate-ensure's dispatch
part, bead-rehome, bring-current-guard, signoff, pr-facts' posture part, pr-open,
queue-priority, converse-signoff, render-seed-audit, reconcile-rig-checkouts,
quota-park-nudge, demo-engine-lib, gc-helm-accept and gc-helm-engage) 89 to 97
percent of the wall time is spent inside runs of the script under test. The test
files' own work, their assertions and fixture writes, is the rest.

Inside those runs the time is process starts. One run of `finding.sh` in
`finding.test.sh` starts about 84 commands: 16 jq, 8.5 tr, 5 gc stub calls, 3.5
grep, 2.4 awk, 1.7 sed, 1.3 mv and 1.1 dirname. On the macOS host a bash start
costs about 7 ms, a jq about 4 ms and a tr or cat about 2.5 ms. The stubs hold 20
to 50 percent of a run, the most where a suite's own gc stub forwarded to a
second bash; the scripts' own reads hold the rest.

The time is spread wide. On macOS CI run 41978698787, with
`migrate-visits-to-gates.test.sh` left out, runs of 60 s or more summed 2,237
test-seconds, runs of 20 to 59 s 1,417, runs of 5 to 19 s 813 and shorter runs
176. No one file, and no one technique, holds half.

The sweeps, sleeps and per-case fixtures that the bead named are small shares
in the suites profiled. `signoff.test.sh` has no sweep loop: its one
interrupted write is a single case. `sleep` was 2 to 6 percent of the profiled
suites that call it, and `gc-helm-engage.test.sh` runs its polls on a fake
clock. The harness suites' per-case fixtures are `printf` writes of a JSON
store, and the test file's own git calls were a tenth of
`bring-current-guard.test.sh`.

## What tk-pgl0s8j cut

- `bd-lib.sh`'s `bd_json`, `bd_list` and `_bd_anchor_up`, `run-lib.sh`'s
  `run_lib_read` and `hold-lib.sh`'s graph read start grep and tr only for a read
  carrying a leading `gc bd:` notice or a control byte other than a newline that
  ends it. Any other read is one line those two would print unchanged, less that
  newline. `bd_json` keeps the newlines that end gc's answer, so that it returns
  the pipeline's statuses, and every answer ends in one, whether a stub's `jq -c`
  line or a real store's indented JSON. Its test therefore leaves that last
  newline out.
- `test-harness.sh`'s gc stub answers `dep list` in one jq pass, and its writes
  name their temp files by pid instead of starting mktemp.
- `deferred-dispatch.test.sh` and `bead-rehome.test.sh` run their bd stub inside
  the gc stub's process, and `deferred-dispatch.test.sh`'s bd stub lands an update
  in one jq pass.

## What that came to

Two paired runs of the whole suite on the macOS host passed all 293 runs on
both sides. Their figures leave out `migrate-visits-to-gates.test.sh`.

- At ea95ddcab, both trees at `-j 3` at the same time, at load 18 to 38, the
  summed test-seconds were 10,482 on main and 9,646 on the branch, 92 percent.
  The branch took 3,797 s of wall time against main's 4,118 s. The kept suites
  came to 93 percent and the retiring ones to 90 percent.
- At e22829359, once `bd_json`'s test left out the newline that ends a read,
  both trees at `-j 6`, at load 7 to 56, they were 14,278 on main and 13,648 on
  the branch, 96 percent. `tools/run-tests.test.sh` failed under contention on
  both sides, before the serial re-run recovered it, and took 858 s on the branch
  against 554 s on main. Without it the branch came to 93 percent. The wall
  times were 3,238 s and 3,061 s. The suites on the shared harness came to 92 percent,
  the kept suites to 98 percent and the retiring ones to 92 percent.

The second run came out higher although the branch gained only a fix between
them, so two paired whole-suite runs on this host differ by several percent.
Suite by suite, paired runs measured `gate-ensure.test.sh`'s dispatch part at 65
and 85 percent, `deferred-dispatch.test.sh` at 72 to 83 percent and at 74
percent, and `finding.test.sh` at 90 and 59 percent. They left `signoff.test.sh`,
`bead-rehome.test.sh` and `bring-current-guard.test.sh` within the noise of
even. The shortest suites moved by half or more either way, such as
`hold-lib.test.sh` at 58 and 170 percent. Two copies of `deferred-dispatch.test.sh`
at e22829359 ran at the same moment, one with its stub's one-pass update and one
with main's jq per flag, and took 132 s and 158 s.

## What holds most of what is left

Each is a script the suites run, so a cut here is a change to what the pack
ships, which `bd-lib.sh`'s change above was too.

- `row_meta` in `bd-lib.sh` reads one metadata key per jq. `signoff.sh` has 43
  call sites of it, and one run of `signoff.test.sh` made 2,236 such calls.
- `queue-priority.sh` is 12 to 17 percent of the gate-ensure, pr-facts and
  signoff profiles. Each call resolves its store through `rig-map.sh` and takes
  a flock.
- `rig-map.sh` has no cache, and each call starts mktemp, timeout, gc, tr, two
  jq and rm. `bead-rehome.test.sh` made 242 calls.
- `gate-ensure.sh` took 3.2 s a run in its dispatch part, starting
  `queue-priority.sh`, `finding.sh` and `lane-state.sh` as scripts of their own.
- Every `#!/usr/bin/env bash` script start is an env exec and a bash start; a
  script that finds its own directory with `$(cd "$(dirname ...)" && pwd)` adds
  two subshells and a dirname.
- `pr-facts.test.sh`'s parts summed 1,105 test-seconds on that CI run, a quarter
  of the suite. The deletion plan retires `pr-facts.sh` with tk-1tfzr71.21, so it
  gets no new work, and deleting it removes that time.
