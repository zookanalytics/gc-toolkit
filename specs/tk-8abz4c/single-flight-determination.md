---
name: Determination — why the merge cadence took its per-rig flock back
description: The evidence falsifying tk-d83wm's Q1 (that the controller's open-tracking gate is a sufficient single-flight for refinery-reconcile), the two-minute watchdog sweep that reopens that gate under a running pass, and the alternatives weighed before restoring the flock. Read this before removing the lock or raising the order timeout.
---

# Why the merge cadence took its per-rig flock back

Bead: tk-8abz4c. The standing description of the arrangement is
[docs/refinery-merge-cadence.md](../../docs/refinery-merge-cadence.md); this
file is the determination behind the change.

## What was believed

[specs/tk-d83wm/exec-order-cadence.md](../tk-d83wm/exec-order-cadence.md) Q1
asked whether the order runner gives the same guarantee the deleted `/tmp`
idle daemon got from a per-rig `flock`, and answered "it does, and by a
stronger mechanism": the tracking bead is created synchronously before the
dispatch goroutine launches and closed in a `defer` after the exec returns, so
the window in which a second dispatch can start is exactly the window in which
no run is in flight. The flock was dropped on that reading, and the driver
carried a comment forbidding its return.

The determination did record one way to lose the guarantee: core's
`order-tracking-sweep` closes tracking beads older than `--stale-after`, whose
default is 10m, so `timeout = "300s"` was set to keep the controller's kill
earlier than the sweep.

## What falsified it

The 10m figure is the wrong mechanism. Two independent things sweep tracking
beads:

- The `order-tracking-sweep` **order**, at `defaultOrderTrackingSweepStaleAfter
  = 10 * time.Minute`. This is the one the determination read.
- The controller's **watchdog**, `runOrderTrackingSweepWatchdog` in gascity
  `cmd/gc/city_runtime.go`, which runs every
  `orderTrackingSweepWatchdogInterval = 30 * time.Second` and closes tracking
  beads older than `orderTrackingSweepWatchdogStaleAfter = 2 * time.Minute`.
  It passes a `nil` order filter, so it sweeps *every* order, not only its
  own — a deliberate widening (gascity #2168) so a jammed dispatcher can
  recover without depending on any single order being scheduled.

Two minutes is well inside the 300s timeout, so the invariant the order file
asserted was not merely undocumented, it was unsatisfiable at the configured
cadence: `refinery-reconcile`'s own gate is removed while its pass is still
running, and the next 60s tick dispatches a second pass onto the same anchors.

Observed on 2026-08-27: tracking bead `tk-wisp-tnk` was dispatched at 17:43:48Z
and closed at 17:46:22Z — 2m34s, which is the 2m window plus watchdog
granularity — carrying `order_tracking_sweep = stale-order-tracking` and
`order_tracking_sweep_by = controller-watchdog`. `tk-wisp-dhg`, `tk-wisp-psz`
and `tk-wisp-dgn` closed the same way in the same hour, and passes were seen at
279s and 135s elapsed against the 60s cadence.

gc-toolkit is the only rig that trips it because it is the only rig whose pass
routinely runs longer than two minutes. A tmpfs quota exhaustion made every arm
slow enough to cross the line on every pass at once, which is why the failure
appeared as a storm rather than an occasional double.

## What was weighed

**Lower `timeout` under the watchdog window.** This is the fix the old
invariant implies, and it is not available: a 120s kill would cut real passes
mid-`merge.sh` on the one rig whose passes routinely exceed it. It trades a
duplicate writer for a truncated one.

**Lengthen the watchdog window.** It is a compile-time constant in gascity, not
this pack's to set, and it exists to recover a jammed dispatcher — lengthening
it slows exactly that recovery. Raising it is worth proposing upstream on its
own merits, but it cannot be this pack's guarantee.

**Restore the flock.** Chosen. The single objection tk-d83wm raised against a
lock was that the tracking gate "needs no on-disk artifact to survive a
reboot". That objection does not survive inspection: `flock` ownership is
kernel state keyed to an open descriptor, not file content, so a lock file left
behind by a reboot or a kill holds nothing. The arms inherit the descriptor, so
the lock is held for exactly as long as a writer is live and the kernel
releases it on any exit including `SIGKILL`, and it depends on no bead
surviving.

## What shipped

`assets/scripts/refinery-reconcile.sh` takes a non-blocking exclusive `flock`
on `<state-dir>/<rig>/pass.lock` before the first arm and stamps the holder's
pid and start epoch into `pass.holder`. A tick that finds the lock held records
one `SKIPPED` line and exits 0. A holder older than
`REFINERY_RECONCILE_LOCK_STALL_SECS` (900s) is a wedge rather than a slow pass —
the driver is gone and an arm still owns the descriptor — so that tick exits 1
and `order.failed` names it.

The arms now append to `pass.log` as they run instead of into a `mktemp` file
that an `EXIT` trap deleted. Under the old arrangement a pass that was killed
or overran wrote nothing at all, which is why an hour of duplicated passes read
from outside as a merely stopped cadence. A `===` header with no `END` line
under it is now a killed pass, and the arms above it are how far it got.

`assets/scripts/refinery-reconcile.test.sh` holds the invariant mechanically
rather than in a comment: it parses `timeout` out of the shipped order file and
accepts a value above the 2m watchdog window only in a run that has already
demonstrated one `merge.sh` writer across two overlapping ticks. Run against
the pre-fix driver, that arm fails and the concurrency arm reports two writers.

## Residue

The tracking bead is still swept at 2m, so the controller still re-dispatches
`refinery-reconcile` every 60s while a long pass runs. Each extra dispatch now
exits immediately on the lock, which costs a process rather than a merge, but
it means `gc order history` reports more runs than there were passes. The
`SKIPPED` lines in `pass.log` are what tell the two apart.

tk-h17iz is the same hazard from a different cause: the retired `/tmp` idle
daemons and the exec order in disjoint lock domains. Both now serialise on
this lock if they run the same script; anything that does not is still a merge
writer neither the gate nor the lock can see.
