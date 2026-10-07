---
name: molecule-hold.test.sh concurrent-run flake — cause and fix
description: Why molecule-hold.test.sh reports random false failures under load, what actually reaps the subprocess, and why the fix is test-side resilience rather than a change to molecule-hold.sh or run-tests.sh.
---

# molecule-hold.test.sh flake under load (tk-6244t3)

A host process reaper occasionally sends SIGTERM to a `molecule-hold.sh`
subprocess mid-run. `molecule-hold.sh` runs under `set -uo pipefail` with no
`set -e`, so the signal shows up as the process's own exit 143 (128 + SIGTERM),
which the test then reads as a logic result. The fix makes the test resilient to
that signal; `molecule-hold.sh`, its assertions, and `tools/run-tests.sh` are
all correct.

## The failure is real on current main, not obsolete

The tracker was filed against a snapshot, so the first question is whether it
still reproduces. It does. On current `main` (04bc0253), standalone, no
concurrent `run-tests.sh`, the suite failed roughly one run in three across
repeated loops. Each failure is the same shape and lands in a different
scenario each time:

```
FAIL - a re-run over an already-held molecule exits 0 (got '143' want '0')
FAIL - a sibling list that returns non-array JSON exits 1 ... (got '143' want '1')
FAIL - a sibling left open AND assigned exits 1 ... (got '143' want '1')
```

One `molecule-hold.sh` invocation exits 143; the follow-on assertions in that
one scenario then fail because the script died before printing its diagnostic
or finishing its writes. The file runs to completion otherwise. So a single
child was signalled while the parent test survived.

## What it is not

- Not the assertion logic. A clean run is 159/0, repeatedly.
- Not `run-tests.sh`'s own signalling. Its only two SIGTERM sources are the
  per-file `timeout -k 5 -s TERM` (line 142) and the completion reaper
  `kill -- -"$pid"` (line 153). Both signal a whole process group, which kills
  the test file together with its children. Measured here (uutils coreutils
  0.8.0, bash 5.3.9): a file whose child is mid-`$(...)` when that timeout fires
  dies whole and the runner sees exit 124, not one child at 143 while the file
  continues. `molecule-hold.sh` starts no background job, `setsid`, or monitor
  mode, so its children share its group and cannot be singled out by a group
  kill.
- Not the agent's own Bash sandbox. With the sandbox disabled the flake
  persists (2 of 9 runs), so the reaper is host-level, present in both the
  refinery's `run-tests.sh` context and a bare shell.

## What reaps it

A trivial jq-forking victim invoked exactly as the test invokes the script —
`OUT=$(victim); RC=$?` — took 0 SIGTERMs in 80 runs under the same host load
(~33 on 8 cores). A heavier victim carrying a pool worker's identity (a
`molecule-hold.sh` command line, `--step mol-polecat-work.load-context` args,
and `GC_SESSION_NAME=gc-toolkit--gc-toolkit__polecat-1-pool`) took a SIGTERM
where an equally heavy but plain victim did not. So the reaper targets processes
wearing a live pool worker's identity, not any subprocess under load — and this
test wears exactly that identity on purpose, to exercise the session-substring
matching in `molecule-hold.sh`.

The exact reaper was not pinned to a gascity mechanism. The workspace-service
orphan sweep (`internal/workspacesvc/orphan_reap.go`) is the closest match but
keys on `GC_SERVICE_NAME` / `GC_SERVICE_STATE_ROOT` and an exact service command
line, none of which this process carries, so it is not the one. The behavior is
consistent with a session-scoped cleanup firing while the real
`gc-toolkit--gc-toolkit__polecat-1-pool` slot recycles, which is intermittent
and explains the rate.

## The fix

Make the hermetic test not assert against a signalled run. An outer supervisor
pass — carrying none of the pool-worker identity — runs the test body and
re-runs it from scratch, bounded, whenever a reap is detected. The kill can
land in two places, and the supervisor catches both:

- On a `molecule-hold.sh` subprocess: a shim around every invocation records the
  reap in a marker (via its exit >=128, or a SIGTERM trap if the shim itself is
  the one waiting). The body finishes, the supervisor sees the marker, and
  re-runs.
- On the body process itself (it exports the pool `GC_SESSION_NAME`, so it wears
  the identity too): the body exits on a signal, and the supervisor sees a body
  exit >=128 and re-runs.

`molecule-hold.sh` and the body exit only with small codes on a real run, so an
exit of 128 or higher is unambiguously the reaper, never a logic outcome; a
clean run trips neither branch, so the body runs exactly once on the happy path.

The retry re-runs the whole body, not one invocation. A signalled run can leave
the store half-written, and several scenarios assert on the accumulated `gc`
call log, so only a fresh store per attempt keeps the assertions sound.

This is test-side because there is nothing to fix in the code under test, and
because the reaper is host-level: no change to `molecule-hold.sh` or
`run-tests.sh` stops an external SIGTERM. Retrying masks no product behavior —
the script's logic is deterministic, and the only thing being retried past is an
external kill.

## Not done, and why

- Changing the test's session identity to something no live slot uses would
  make it invisible to a session-scoped reaper — but only if the reaper keys on
  `GC_SESSION_NAME`, which is unconfirmed, and it would weaken the deliberate
  substring-trap coverage that needs a realistic pool name. Left as a follow-up
  if the vector is confirmed.
- A `run-tests.sh` retry-on-failure would cover every suite at once, but the
  signal is invisible to the runner (the test launders it into its own exit 1),
  and a blanket gate retry is a policy change to what a green suite means.
