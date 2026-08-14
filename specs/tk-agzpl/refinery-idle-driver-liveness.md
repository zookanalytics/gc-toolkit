---
name: Detecting a Dead Refinery Idle Driver
description: Why the merge cadence stops silently, why every cheap liveness signal for it is a confirmed false answer, and the holder-plus-cgroup test that replaces them.
---

# Detecting a Dead Refinery Idle Driver

> **Bead:** tk-agzpl. **Investigated:** 2026-08-13/14 by the mayor and the
> gc-toolkit refinery; implemented 2026-08-14. **Author:** Polecat
> gc-toolkit.furiosa.
> The bead's own notes are the primary record of the investigation, including
> two hypotheses that were raised and then retracted by their authors. This
> document keeps what survived, and states which discarded signal each shipped
> assertion exists to refuse.

## Scope

**Mandate.** The mechanism that stops the merge cadence, the evidence that
disqualifies each cheaper way of detecting it, and the shape of the two
artifacts that shipped. Written for whoever next sees
`check-refinery-idle-driver` fire, or next has to change what it asserts.

**Boundaries.** Not a description of the reconcile passes themselves
(`mol-refinery-patrol`'s find-work step owns those), and not a description of
`idle-loop.sh`, which is not in this pack — it is authored per rig and lives at
`/tmp/gc-refinery-idle-<rig>/idle-loop.sh`. Relocating it somewhere a reboot
does not erase is a known residual, recorded below and deliberately not fixed
here.

## The failure

`merge-skill.sh` fires only from the refinery's idle cadence. In this harness
that cadence is a per-rig driver — `<state-dir>/idle-loop.sh` holding
`<state-dir>/lock` for its whole life — because the formula's foreground
`sleep {{event_timeout}}` is blocked. A live refinery *agent* runs the same
passes inline, but only while it happens to be awake in find-work.

So when the driver stops, merging stops, and nothing anywhere reports it:

| Observation, 2026-08-13/14 | Value |
|---|---|
| gc-toolkit PR#345 and PR#346 | `reviewDecision=APPROVED`, `mergeStateStatus=CLEAN` from 19:36Z |
| landed | 02:49Z and 02:50Z, ~14 min after a manual nudge |
| driver's last tick | 17:38:40Z — before the PRs were even approved |
| rig suspended | no |
| refinery configured | yes (`gc rig status` showed it as "unknown (partial status)") |
| `gc doctor` | 148 checks passed; none covered this |
| witness escalation / mail / bead | none |

The work was merge-ready for seven hours. Only the server was missing.

## The mechanism: it is killed, not crashed

The driver does not exit. Verified on this host, not inferred:

1. Every agent session runs inside a systemd scope cgroup —
   `/user.slice/user-1000.slice/user@1000.service/tmux-spawn-<uuid>.scope`.
2. That scope is `KillMode=control-group`. When it stops, systemd SIGTERM/
   SIGKILLs **every** process in the cgroup, regardless of session id, parent
   pid, or reparenting to init.
3. `setsid` changes the SESSION, not the CGROUP. Positive control inside a live
   session: the setsid child got a new SID (925979, distinct from its launcher's)
   and stayed in `tmux-spawn-<uuid>.scope`.

Both observed deaths match: the 03:07:25Z arm (pid 3927, SID==PID, in session
lx-mnm43) ticked at 03:07:25 / 03:10:23 / 03:13:02, last wrote at 03:15:47Z, and
was gone by 03:19Z — killed when lx-mnm43's scope was torn down, ~8 minutes after
arming, not on any timer. The earlier 9h20m outage has the same signature: a
clean stop between ticks, no error, no traceback, no exit line. A self-exit would
have left the lock-contention line or a `PASS-EXIT` fault; neither appears.

**Consequence for any remedy: a re-arm performed from inside an agent session
cannot survive, whatever form it takes.** A re-arm that silently lapses is worse
than a known-dead driver, because it converts a visible gap into a false
all-clear — which is exactly what happened when SID==PID was reported up the
chain as a fix and propagated to a second rig before it was caught.

## Four false-greens, each confirmed against a live example

None of these may be used as the liveness test. They are listed with what
disproved them, because each looks like the obvious cheap answer.

**1. A refinery session in `gc session list`.** The first diagnosis of this bead
proposed exactly this, and it was retracted by its author. A live session with a
dead driver is indistinguishable from a healthy one: beads healthy, wisp
assigned, queue idle, session present — and approved PRs sit. Session presence is
*correlated* (the driver dies with the session that armed it) but is not the test.

**2. `gc rig status` agent lines.** "unknown (partial status)" is what an agent
that is merely not running reports. It cannot separate configured-and-idle from
configured-and-dead, which is why the rig read as healthy above.

**3. `driver.out` / `reconcile.log` mtime.** Wrong in *both* directions.
`reconcile.log` was written at 03:15, minutes AFTER the driver died — the refinery
*agent* running the same passes inline while awake in find-work (false green).
And after the 03:32 re-arm, `driver.out` went stale at 03:15 while the driver was
healthy, because the re-armed instance logs only to `reconcile.log` (false red).
Any detector keyed on one file's mtime is wrong both ways.

**4. Existence of the lock file.** A SIGKILLed driver orphans its lock as a
0-byte file with no holder. Directly checked at 03:25Z:
`-rw-rw-r-- 1 zook zook 0 03:07:25 /tmp/gc-refinery-idle-gc-toolkit/lock`,
`fuser -s` nonzero, no idle-loop process anywhere. `[ -f lock ]` reports "armed"
forever. (An earlier note here theorised that this stale lock trips the driver's
duplicate-arm guard and explains the short lifetime. That theory is **retracted**:
the guard never runs, because the driver is killed rather than started twice. The
stale lock is a symptom. It remains a false-green for detection, for the other
reason.)

## What is sound: holder-ship, then cgroup

Three states, and the middle one is the reason "alive" is not the question:

| Lock | Holder's cgroup | State |
|---|---|---|
| held | `gc-refinery-idle-<rig>.service` | healthy |
| held | a `*.scope` | **alive but doomed** — working now, SIGKILLed at the next rotation |
| unheld | — | dead |

Holder-ship is read with `fuser`/`lsof`, which are read-only. The lock is never
TAKEN to test it: `flock -n` answers the same question by acquiring the lock, and
a driver arming in that window would see contention and exit — making the probe
the cause of the outage it looks for.

"Someone holds it" is not the question either. The driver holds the lock on FD 9
for its whole life, so every child it forks — each reconcile pass, and the
interval `sleep` — inherits that descriptor and is a holder too. A live
gc-toolkit lock reads seven pids, four of which are pass scripts. Those orphans
outlive the driver by up to a full interval, so the holder must be identified by
its command line, and a teardown must clear the whole inherited set or the flock
survives the kill.

There is a fourth state that is not about liveness at all and belongs with these
because it produces the identical symptom — merge-ready work, silent host:

**armed, ticking, `active (running)`, and merging nothing.** A `systemd-run --user`
unit inherits `WorkingDirectory=!$HOME`, which is not a git work tree.
`merge-skill.sh:773` then fails closed on `git remote get-url origin`, prints
"NOTHING is merged this pass", and `exit 0`s — on every tick, forever. gc-toolkit
escaped this only by accident (its `idle-loop.sh:38` does its own `cd`);
signal-loom's copy has no `cd` and silently no-opped under the same unit
definition. So the unit's `WorkingDirectory` is asserted too, and the arming
script validates it *before* arming rather than waiting to observe it.

## What shipped

**`doctor/check-refinery-idle-driver/`** — per rig that is not suspended and has
a refinery configured, asserts the lock is HELD, by a process whose command line
is that rig's own `idle-loop.sh`, in the driver's own unit, whose
`WorkingDirectory` is a git work tree. A dead driver is the defect on its own;
APPROVED+CLEAN PRs escalate it from warning to error rather than triggering it,
because the stall is silent and its cost is set by when someone happens to look,
not by the queue depth at this instant. That PR probe runs only for a rig already
found unhealthy, so a green host makes no network call.

Its hermetic test's load-bearing case is not any of the failures — it is the one
where the driver is dead while a fresh `reconcile.log`, a fresh `driver.out` and
a present lock file all read healthy. A check built on any discarded signal
passes that case, and must not.

**`assets/scripts/refinery-idle-arm.sh`** — arms the on-disk driver in
`gc-refinery-idle-<rig>.service` with `Restart=always`, an explicit
`--working-directory`, and an explicit environment. It does not author
`idle-loop.sh`: the on-disk driver is the proven one, and rewriting its emit
filter from scratch is a trap that has been re-tripped six times. Idempotent —
already-armed is a no-op — and it refuses rather than guesses when a live driver
or an unidentified lock holder is on the lock.

The environment is passed explicitly because a `--user` unit inherits the systemd
user manager's, not the caller's: its PATH has no `~/.local/bin`, so `gc` exits
127 and an unreadable ledger reads as an empty queue. `GC_RIG`, `GC_RIG_ROOT`,
`BEADS_DIR` and `GC_AGENT` are resolved for the TARGET rig and override whatever
the caller holds, so arming another rig's driver cannot stamp the caller's
identity onto that rig's convoy graduations; session-scoped keys
(`GC_SESSION_*`, `GC_TEMPLATE`, `GC_ALIAS`, `GC_TRIGGER_*`) are dropped, since a
driver that outlives its launcher must not carry the launcher's identity.

`GC_AGENT` is worth naming separately: `idle-loop.sh` contains zero references to
it, so `reconcile-graduated-convoys.sh:111` printed "GC_AGENT unset; skip" on
every tick for as long as the driver existed. Owned-convoy graduation had never
run on the idle cadence at all. Passing it from the arming script fixes that in
the place that survives a driver rewrite.

**`formulas/mol-refinery-patrol.toml`** — the find-work cadence contract gains a
fifth invariant ("arm it outside your own session's cgroup") pointing at the
script, and states the ordering rule: probe the driver BEFORE running the
reconcile passes inline. If the driver is live it has been running them every
`event_timeout`, and a second inline run is a second `merge-skill.sh` writer
against the same anchors — the duplicate-writer hazard the canonical lock exists
to prevent.

## Residual, deliberately not fixed here — tk-d83wm

`idle-loop.sh` and its state dir live under `/tmp`, so a reboot removes the
script and the unit then fails to start. Both artifacts read the state-dir root
from `GC_REFINERY_IDLE_ROOT` (default `/tmp`), which is the seam a relocation
would use; the detector and the remedy read the same variable so they cannot
disagree about where a driver lives.

What makes this more than a path change is that `idle-loop.sh` is not in this
pack at all: it is hand-authored per rig, and the two copies that exist have
already drifted (signal-loom's has no `cd`, which is why it silently no-opped
under a unit definition gc-toolkit survived). So the open decision is whether the
pack should OWN the driver — shipped, parameterised, and pointed at from a
durable path — or whether only its location moves. Filed as **tk-d83wm**
(`discovered-from` tk-agzpl) with that framing.
