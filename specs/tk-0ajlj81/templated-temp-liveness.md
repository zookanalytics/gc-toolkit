---
name: Liveness for templated build and test temp — tk-0ajlj81
description: Why build-scratch-reap.sh waits for a templated entry (go-build*, go-link*, gctk-*) to go unmodified before it trusts a missing holder, why the wait is an hour for Go toolchain trees and a day for gctk-* temp, what the rule still leaves exposed, and what else was weighed. Read it when judging the reaper's waits, or a temp file a pass took from a live run.
---

# Liveness for templated build and test temp

Bead: `tk-0ajlj81`. It changes `assets/scripts/build-scratch-reap.sh` and its
test, the order's and the component model's account of the rule, and the
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
  91 failed (2026-10-06). Eleven more suites lost their dirs the same way by
  2026-11-06. Some of them passed on the runner's serial retry, so the gate
  recorded a pass. When a suite's dir goes, its PATH stubs go with it, and the
  script under test reached the live city's gc.
- A Go build's `$WORK` holds nothing while a package compiles. A full lsof
  snapshot during a 30-second compile showed nothing open inside it, and a real
  pass then failed the build with `can't create $WORK/b001/_pkg_.a`
  (2026-10-18).
- mol-feedback-distiller's pending set, `gctk-feedback-distiller.*`, is handed
  from load-and-gate to the later steps with no process between shell blocks.
  A pass took it mid-run twice (2026-10-09 and 2026-10-26). The second time,
  the gate read the missing set as nothing pending.
- mol-polecat-work's PR summary file took the same route twice (2026-10-09 and
  2026-10-31). The formula no longer writes it as `gctk-*` temp.

The cause is the reaper's evidence, not its timing. For a name that carries no
owner, a holder seen at one instant shows the owner alive. When no holder is
seen, that shows nothing about the owner.

## The rule

A templated entry is removed only when no holder is seen and nothing anywhere
inside it, directories included, was modified within its wait. The wait is 60
minutes for `go-build*` and `go-link*`, and 1440 minutes for `gctk-*`. The wait
is read at the scan and again just before the remove, beside the holder and pid
rechecks. A tree that cannot be read in full is kept, because what it could not
read may be what was written. A pid-encoded name is unchanged: its pid is its
owner, so a dead pid stays the proof, and no wait applies to it.

This is the model the sibling reaper already uses.
[scratch-reclaim.md](../../docs/scratch-reclaim.md) ages a session tree by the
newest entry anywhere inside it, and a running process only ever protects a
tree there. The reading is the modification time, as it is there. A suite can
backdate a fixture's modification time, so the tests need no clock seam. Change
time cannot be set back, but nothing the pack runs needs that: a run would have
to copy old times onto its whole entry and then write and hold nothing for the
wait.

## Why these waits

Go toolchain trees. Every action of a build writes in its `$WORK`, each
package's `importcfg` and then its output (`os.MkdirTemp(cfg.Getenv("GOTMPDIR"),
"go-build")` in `cmd/go/internal/work/action.go`, go1.27.4). So a live tree's
longest quiet stretch is one action, a compile or a link, which takes minutes.
The whole compile of gascity's `cmd/gc` test binary, many actions, took about
nine minutes under load (2026-10-18). A test binary runs from `$WORK`, and lsof
lists the running binary's own path. These trees are large: tk-jp1fg5's hand
reclaim found 1.8G and 311M ones.
So their wait stays near the order's interval. A killed build's tree is now
reclaimed one to two hours after its last write, where before it took up to one
hour.

gctk-* temp. It is small: tk-jp1fg5's reclaim found 35 such entries, about
0.5M in all. A suite writes in its dir many times a minute. A formula's handoff
file sits unwritten from the step that writes it to the last step that reads
it. Of mol-feedback-distiller's 67 recorded runs, the median stayed open 51
minutes from pour to close. 32 stayed open over an hour, and 2 over a day, both
opened before October. Pour to close is longer than the pending set's own span,
but it shows runs that routinely outlast an hour, which an hour's wait would
leave exposed. A day is the horizon scratch-reap.sh already gives an idle
session's scratch.

## What it leaves in place

The reaper still cannot see the owner of a templated name. It infers the owner
is dead because the entry has gone quiet. An owner that holds nothing and writes
nothing inside its entry for longer than the wait still loses it: a single Go
action longer than an hour, or a run that hands a `gctk-*` file across more
than a day. The cause cannot be removed where it arises. `go-build*` and
`go-link*` are the Go toolchain's names (`os.MkdirTemp("", "go-link-")` in
`cmd/link/internal/ld/lib.go`). For `gctk-*`, removing it would take an owner in
every producer's name or a place outside the scanned roots. 220 of the 258
suites name their temp this way, and a formula's handoff has no owning process
at all, only a session. The distiller gate's reading of a lost set as empty is
its own defect, tk-3njf5ac.1.

## What else was weighed

- Removing an entry only after it is unheld at two consecutive passes. That
  needs state carried across passes. It still removes a live entry that is
  unheld at both instants, such as a distiller run that spans two passes,
  unless the state also fingerprints the tree. A fingerprinted tree is this
  rule with a state file added.
- A descriptor that `test-harness.sh` or `tools/run-tests.sh` holds on a
  suite's dir, or a TMPDIR under the runner's own directory. Either covers a
  suite run through those paths, but not a bare `bash x.test.sh`, a Go build,
  or a formula's handoff between shell blocks. The holder-side workarounds in
  the tree are removed, because the wait covers them: the `exec 9>` that
  `doctor/check-cadence-live` held on its probe dir, and the one the
  `doctor-parallel-reads` block held on its scratch tree in
  `check-armed-dispatch-owed`, `check-hq-marooned-work` and
  `check-po-queue-only`.
- Moving handoff files out of `gctk-*`. That takes them out of the only reclaim
  they have, and it leaves suites and Go builds exposed. `mol-feedback-miner`
  had named its temp dir `feedback-miner.*` for this reason. It takes a
  `gctk-*` name again, so the dir of a run killed before its last step is
  reclaimed.
- Age as the only signal. tk-jp1fg5 rejected it, because a large live tree
  would eventually be removed. Here a recent write only ever keeps an entry,
  and every entry still needs no holder.

## Gas City search

Searched `gastownhall/gascity` main at `e9a628c50` for a primitive that
reclaims host temp under a liveness rule:

- `reapClosedBeadWorktrees` (`cmd/gc/bead_worktree_reaper.go`) removes the
  worktrees of closed beads under `.gc/worktrees/`.
- `runReapStage` (`cmd/gc/cmd_dolt_cleanup.go`) signals orphaned dolt servers
  whose config lives under test temp roots and removes their data dirs.
- `reapStaleBdExportJSONL` (`cmd/gc/bd_env.go`) removes a stale bd export file
  in a scope root.

None reclaims `go-build*`, `go-link*` or `gctk-*` scratch, so the pack's reaper
stays. This change adds no flag, environment key or output field to it. Its
`--verbose` keep reasons gain the new cases.

## Verified

- `build-scratch-reap.test.sh`: 53 passed, 0 failed, where main has 42 cases.
  Eight mutants of the rule each fail at least one case: no wait, the entry
  read without what is below it, an unreadable tree read as unmodified, no
  recheck before the remove, either wait swapped for the other, a wait applied
  to a pid-encoded name, and no read at the scan.
- `doctor/check-cadence-live/run.test.sh`: 97 passed, 0 failed, with its hold
  removed.
- `doctor-parallel-reads.test.sh`: 35 passed, 0 failed, with the hold removed
  from every copy of the block. The three checks that carry it pass their own
  suites: `check-armed-dispatch-owed` 164 of 164, `check-hq-marooned-work` 75
  of 75, `check-po-queue-only` 125 of 125.
- A dry run of main's script on the live roots on 2026-11-15, during this work,
  listed two `go-build*` trees modified two minutes earlier as "would reap".
