---
name: Temp that names its owner — tk-0ajlj81
description: Why build-scratch-reap.sh removes only scratch whose name records its owner's pid and never a templated name (go-build*, go-link*, gctk-*), why tools/run-tests.sh gives each run its own run.<pid> temp directory, what a killed run now leaves to the host, and what else was weighed. Read it when judging what the reaper may remove, or when a run's temp went missing or was left behind.
---

# Temp that names its owner

Bead: `tk-0ajlj81`. It changes `assets/scripts/build-scratch-reap.sh` and its
test, `tools/run-tests.sh` and its test, the accounts of the rule in the order,
the component model, `docs/scratch-reclaim.md` and the test floor, and the
workarounds that kept temp out of the reaper's reach. The reaper's design
record is
[specs/tk-jp1fg5/build-scratch-reap.md](../tk-jp1fg5/build-scratch-reap.md).

## What went wrong

The reaper removed a `go-build*`, `go-link*` or `gctk-*` entry when two lsof
snapshots, taken seconds apart in one pass, showed no process with a file in it
open and no process with its cwd in it. A run that owns such an entry holds
nothing for most of its life, so the order took live temp in every class the
bead's notes record:

- A hermetic suite's `gctk-<suite>-test.*` dir is held only while a stub or jq
  has a file in it open. The first hit was `lifecycle.test.sh` at 435 passed,
  91 failed (2026-10-06), and eleven more suites lost their dirs the same way by
  2026-11-06. When a suite's dir goes, its PATH stubs go with it, and the script
  under test reached the live city's gc.
- A Go build's `$WORK` holds nothing while a package compiles. A real pass
  failed a build with `can't create $WORK/b001/_pkg_.a` (2026-10-18).
- mol-feedback-distiller's pending set, `gctk-feedback-distiller.*`, has no
  process between the shell blocks that hand it on. A pass took it mid-run
  twice (2026-10-09 and 2026-10-26).
- mol-polecat-work's PR summary file took the same route twice (2026-10-09 and
  2026-10-31).

## Why the temp needs a reaper at all

Every owner removes its own temp when it ends normally. 220 of the 258 suites
make `gctk-*` temp, and each removes it on an EXIT trap, which bash runs on TERM
and HUP as well (bash 5.3.20, probed 2026-11-15). The go command removes its `$WORK` when it exits, and
it keeps going through SIGINT and SIGQUIT to exit that way (`signalsToIgnore`
and `closeBuilders` in `cmd/go/internal/base` and `cmd/go/internal/work`,
go1.27.4). A formula removes its hand-off file at its last step.

Temp is left only when its owner is ended first. Bash skips its EXIT trap on
SIGKILL, which `tools/run-tests.sh` sends five seconds after a timeout's TERM
(`timeout -k 5 -s TERM`) and Gas City sends after its TERM to a closed
session's leftover processes (`KillByPID` in
`internal/runtime/proctable/kill_unix.go`). The go command does not handle
SIGTERM or SIGHUP, so either one leaves its tree, and `gctk rig` stops a
command's process group with SIGTERM before SIGKILL (`stopGroup` in
`services/gctk/internal/rig/run.go`), as a demo capture's `gctk rig serve` does
to `go run ./cmd/helm-fixture`. A crash or an OOM kill leaves anything. A formula run that stops partway never reaches the step that removes
its file. The Bash tool of Claude Code is not one of these killers: a command
past its timeout moves to the background and runs to its end, EXIT trap
included (probed 2026-11-15).

What is left needs someone else to remove it, and only a name says whose it is.
`gct<pid>-<n>`, `gct-<pid>-<n>` and `run.<pid>` record their owner, so its end
is a fact a reaper can read. `go-build*`, `go-link*` and `gctk-*` all land in one
host-shared root under names that record nothing about their owner. Every rule
for them is a guess at whether the owner has ended. The holder rule guessed
from an instant with no file open. A first version of this change guessed from
a quiet spell, an hour for Go trees and a day for `gctk-*`. Each guess removes
some live owner's temp, because a live run can hold nothing and write nothing
for longer than any wait.

## The rule

The reaper removes an entry only when its name records its owner's pid, that
pid is gone, and no process holds the tree, all re-read just before the
remove. It never removes a templated name. Such temp belongs to the run that
made it, which removes it when it ends.

`tools/run-tests.sh` gives every run a temp directory of its own and runs it
with TMPDIR set to it: `run.<pid>` in the physical path of the caller's temp
directory. The pid is the run's own process. The runner's subshell `exec`s
through `nice` and `ionice` into `timeout`, which lives as long as the file it
runs. A suite's `gctk-*` temp and any Go build it starts land inside. The
runner removes the directory once the run ends and its process group is
reaped, a run its timeout ended included. A run still going when the runner
itself is ended keeps its directory while its process lives, and the reaper's
dead-pid rule removes it after that. The form is the one the build scripts
already use for their Go scratch (`run.$$` under `/var/tmp/gotmp`), so the
reaper gains no new name.

What each producer gets:

- A suite run through the runner, which is every pre-flight, self-review and
  refinery gate: its temp sits in the run's directory, removed when the run
  ends, or by the reaper once the run's process is gone.
- A suite run directly, a pack script's `gctk-*` temp, and a formula's
  hand-off file: no pass removes them while they live. What a run ended first
  leaves waits for the host's own temp cleanup.
- A Go build the build scripts start: its tree sits in their `run.<pid>`,
  unchanged. A Go build started by hand puts `go-build*` and `go-link*` in
  TMPDIR, which the go command removes on exit, and what a killed one leaves
  waits for the host.
- gascity's gc.test trees: unchanged.

## A hand-off between sessions

mol-feedback-distiller and mol-feedback-miner hand a `gctk-*` file between
steps. Each later step declares `gc.session_affinity = "require"`, so the step
that reads the file runs in the session that wrote it, and the path lives only
in that session. No pass removes the file, so a hand-off works as it does with
no reaper at all. A TMPDIR per session would remove it when the session ends,
which is the first time it could matter.

## What it leaves in place

Killed runs' leftovers under templated names are no longer the pack's to
reclaim. On the host this city runs on, the pack does not need them to be:
neither the per-user TMPDIR nor `/private/tmp` holds an entry older than the
last boot, `dirhelper` runs daily with `CLEAN_FILES_OLDER_THAN_DAYS=3`
(`/System/Library/LaunchDaemons/com.apple.bsd.dirhelper.plist`), and the data
volume has 1.5 TiB free (all read 2026-11-15). On a host whose temp is a per-uid
tmpfs, a killed hand-run Go build's tree, which can reach gigabytes, counts
against the quota until the host's cleanup removes it. A host where that bites
runs its builds with GOTMPDIR under a `run.<pid>` directory, as the build
scripts do, and the reaper takes the tree once that process is gone.

One such leftover comes from the pack itself: a demo capture's
`gctk rig serve` stops `go run ./cmd/helm-fixture` with SIGTERM, which leaves
about 7M of Go tree each time. That can be fixed where it arises, by stopping
the command with SIGINT first or by giving it a `run.<pid>` TMPDIR, and
tk-d7vy8wo tracks it.

`assets/scripts/gc-build.sh` keeps its own rule for its Go scratch root: a
dead pid's `run.<pid>` on sight, and anything else there a day old. This change
does not touch it.

## What else was weighed

- A quiet spell before the remove, the first version of this change. At
  review the operator objected to its hard-coded limits and asked what keeps
  temp from being removed by its owner once the owner is done. The validation
  pass ruled that a time limit may not stand as the proof that an owner has
  ended.
- A TMPDIR per session that names the session, removed once Gas City records
  the session's end. Gas City cannot set one: an `env` value is expanded
  against the controller's own environment, so it cannot name a session, and
  `pre_start` and `session_setup`, which can, run as commands of their own and
  set nothing in the agent's environment. It would also remove a hand-off file
  when its session ends.
- A TMPDIR from the agent-level or workspace-level `env` keys. Their values are
  the same for every session, so they name no owner.
- Removing an entry only after it is unheld at two consecutive passes. That is
  a guess from two instants instead of one, and it needs state across passes.
- A descriptor that `test-harness.sh` or the runner holds on a suite's dir.
  That still guesses from holders, and it leaves a suite run directly, a Go
  build and a hand-off between shell blocks exposed.

The workarounds that kept temp out of the reaper's reach go, since nothing
removes a `gctk-*` entry now: the `exec 9>` hold in `doctor/check-cadence-live`
and in the `doctor-parallel-reads` block of `check-armed-dispatch-owed`,
`check-hq-marooned-work` and `check-po-queue-only`, and `mol-feedback-miner`'s
temp dir name outside `gctk-*`.

## Gas City search

Searched `gastownhall/gascity` main at `294079d53` for a primitive that removes
host temp once its owner ends, or that names a session's temp:

- `reapClosedBeadWorktrees` (`cmd/gc/bead_worktree_reaper.go`) removes the
  worktrees of closed beads under `.gc/worktrees/`.
- `runReapStage` (`cmd/gc/cmd_dolt_cleanup.go`) signals orphaned dolt servers
  whose config lives under test temp roots and removes their data dirs.
- `reapStaleBdExportJSONL` (`cmd/gc/bd_env.go`) removes a stale bd export file
  in a scope root.
- `sweepProcessTableOrphans` (`cmd/gc/session_beads.go`) ends a closed
  session's leftover processes by the `GC_SESSION_ID` they carry. It ends
  processes and removes no files.
- `expandEnvMap` (`cmd/gc/cmd_start.go`) expands an agent's, a provider's and
  the workspace's `env` values through `ExpandSessionEnvValue`
  (`internal/processenv/provider.go`), against the controller's environment.
  `docs/reference/config.md` lists `pre_start` and `session_setup`, which take
  `{{.Session}}`, as commands run before and after session creation.

None removes build or test temp, and none can give a session a TMPDIR of its
own, so the pack's reaper stays and the owner is named where the pack sets
TMPDIR, in `tools/run-tests.sh`. The change adds no flag, environment key or
output field. The reaper's `--verbose` reasons gain `skip (records no owner)`.

## Verified

- `build-scratch-reap.test.sh`: 42 passed, 0 failed. A month-old unheld
  `go-build*`, `go-link*` and `gctk-*` entry is kept, while every dead pid's
  tree goes. Main's holder rule for templated names fails 7 cases, and dropping
  the pid gate fails 1.
- `tools/run-tests.test.sh`: 150 passed, 0 failed. A run's TMPDIR is
  `run.<pid>` in the caller's physical temp path, it exists while the file runs
  and its pid is live then, two runs at once have two, and the runner removes
  it after a pass and after a timeout. Skipping the removal fails 2 cases, and
  reading `$BASHPID` inside the command substitution fails 3.
- A dry run of main's script on the live roots on 2026-11-15, during the first
  version of this change, listed two `go-build*` trees modified two minutes
  earlier as "would reap".
- Dry runs on the live roots at 2026-11-15T22:54Z, ten seconds apart: this
  script listed four `go-build*` trees and three `gctk-*` entries as
  `skip (records no owner)` and planned nothing. Main's script planned to
  remove the four `go-build*` trees, 7.1M. No go process was running and none
  had been written for six minutes: three were empty, and one held a
  `go run ./cmd/helm-fixture` binary, so they were leftovers of stopped runs,
  which this rule leaves to the host.
