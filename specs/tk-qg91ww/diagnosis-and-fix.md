---
name: Why the detached gc doctor sweep vanished, and the fix
description: Diagnosis and design record for tk-qg91ww — the hourly detached `gc doctor` sweep died mid-run because it carried the launching deacon session's GC_SESSION_ID and the city-wide session-orphan reaper killed its process group by that key, defeating the systemd-user isolation the launch relies on. Records the forensic trail (including the falsified hypotheses), the two-part remedy in doctor-sweep.sh, and the platform-level question left for the operator.
---

# Why the detached `gc doctor` sweep vanished

The deacon's hourly `gc doctor --json` sweep runs detached (a full sweep costs
~10 min; the harness kills any one call at 600s). It was reported failing under
finding key `doctor-sweep-failed` with `state=failed reason=sweep-vanished`:
the runner found the sweep's pid dead with no `rc` file and an empty payload,
so the process died mid-run. The report named no cause of death.

## Verdict

Two independent things were wrong, and both are fixed here:

1. **Root cause — the sweep was being reaped by the city's session-orphan
   reaper.** `doctor-sweep.sh` forwarded the *entire* launching (deacon) session
   environment into the detached sweep, including `GC_SESSION_ID`. gascity's
   session-orphan reaper finds a process by the `GC_SESSION_ID` in its
   `/proc/<pid>/environ` and kills its whole process group — a match that
   ignores process tree, process group, and cgroup, so the systemd-user
   isolation the launch relies on does not shield it. Wearing the deacon's
   session id, the sweep looked like that session, and the session's next
   patrol-cycle teardown reaped it. Fixed by shedding `GC_SESSION_ID` at launch.

2. **The sweep could not say how it died.** `reason=sweep-vanished` carried only
   `elapsed`, `pid`, and the stderr path. It never recorded the terminating
   signal or the systemd unit, so a reap, an OOM, and a crash were
   indistinguishable — which is why this took a from-scratch forensic dive.
   Fixed by making the wrapper record its own cause of death.

## The forensic trail

The dispatch note proposed a session-teardown reap and offered "enable
lingering" as the hardening. The measurements falsified the specific mechanism
it named and led to the real one.

Falsified:

- **User-manager teardown.** `loginctl show-user` reported `Linger=yes` and the
  user manager (`systemd[1273]`) was alive. Lingering was already the hardening
  the note proposed, so the user manager was not being torn down under the
  sweep.
- **Disk.** Filesystem at 74%, 57G free (from the filing).
- **cgroup memory / OOM.** `user.slice` `memory.max` and `memory.high` were both
  `max`; no MemoryMax on the user slice; no kernel OOM line. Each sweep peaked
  at ~242M / ~253M, far under any limit.
- **pids exhaustion.** `pids.max` 75812 vs `pids.current` 516.
- **journald loss.** No `Suppressed`/rate-limit lines, no user-manager
  reexec/reload in the window.

The decisive evidence was in the user journal. Both consecutive sweeps died
early — 55.6s and 127s wall clock, far under the 1800s bound — and for each unit
the journal held exactly two lines: `Started run-p…service` and `Consumed …
CPU time`. No `Deactivated successfully`, no `Failed with result 'X'`, no `Main
process exited`, no `oom-kill`.

That absence is the tell. systemd (259 here) counts SIGHUP, SIGINT, SIGTERM,
and SIGPIPE as a *clean* stop for a service main process and logs no failure
line for them. A unit that logs only its resource-consumption line was ended by
one of those catchable shutdown signals — not SIGKILL, not OOM (both of which
systemd logs), and not a clean exit (which would have written `rc`). So
something was sending the sweep a catchable signal ~1–2 min in, reproducibly.

The killer, read in the gascity source:

- `internal/runtime/proctable/scan_linux.go` — `ScanBySessionID` treats a
  process as an agent "root" when its `/proc/<pid>/environ` carries a
  `GC_SESSION_ID` and it sits outside its parent's envelope (the parent is gone
  or carries a *different* `GC_SESSION_ID`). The sweep's parent is the
  `systemd --user` manager, whose environ does not carry the deacon's session
  id, so the sweep qualifies as a root under the deacon's id.
- `internal/runtime/proctable/kill_unix.go` — the reaper signals `-pid` (the
  whole process group) with SIGTERM, a grace period, then SIGKILL. The SIGTERM
  first is exactly the catchable signal the journal evidence pointed to.
- Two call sites drive it, both timing-consistent with a ~1–2 min death:
  `killExistingOrphans` (`internal/session/manager.go`) runs immediately before
  every runtime `Start`, so a deacon session restart reaps the previous
  cycle's detached sweep; `sweepProcessTableOrphans` (`cmd/gc/session_beads.go`)
  runs every controller tick (default 30s) and reaps any untracked
  `GC_SESSION_ID`-carrying process whose session bead is closed or absent.

`gc doctor` itself reads no `GC_SESSION_ID` (grep of the doctor command and
`internal/doctor/` is empty), so the sweep never needed the value it was being
killed for.

## The fix (this bead)

Both parts live in `assets/scripts/doctor-sweep.sh`.

**Shed the session identity.** The systemd launch already filtered the
forwarded environment to POSIX-named vars; `GC_SESSION_ID` is now also excluded.
The setsid/nohup fallback inherits the caller's environment directly, so it
execs under `env -u GC_SESSION_ID`. A process with no `GC_SESSION_ID` is skipped
by `ScanBySessionID` outright (`if sessionID == "" { continue }`), so neither
killer can claim it. Shedding is the right lever, not reassigning: a *distinct*
fake id would still be reaped by `sweepProcessTableOrphans`, which reaps any
`GC_SESSION_ID`-carrying process whose session bead is absent.

**Record the cause of death.** The wrapper now traps HUP/INT/QUIT/PIPE/TERM and
writes `signal:<NAME>` to a `cause` file before exiting, and runs `gc doctor` in
the background so the trap fires at once rather than after doctor returns. The
`sweep-vanished` report reads it and emits `cause=` (the signal, or `unknown`
for an untrappable SIGKILL/OOM), plus `launch=` and `unit=` — the named
transient unit lets a reader pull the run's own journal after collection. This
is defense-in-depth: even with the reaper fix in place, any future death from a
different cause now names itself instead of vanishing silently.

## Verified

- `assets/scripts/doctor-sweep.test.sh`: 121 pass, including new cases — a
  vanished sweep reports `cause=signal:TERM` when killed by a catchable signal,
  `cause=unknown` when it left no death note, and the detached sweep carries no
  `GC_SESSION_ID` on both the setsid/nohup and the transient-user-service paths.
- The state contract test still passes: `cause=`/`launch=`/`unit=` are report
  *fields*, not new states, so the patrol decision table needs no new arm. Its
  prose now names the fields a vanished failure carries.
- `tools/lint-learned.sh` clean on the changed files.

## Left for the operator (out of scope here)

The reaper's match is by an environment variable across the cgroup boundary, by
design — it is meant to catch orphans wherever they hide. The defect was that
`doctor-sweep.sh` propagated a session identity to a process that deliberately
outlives that session. This fix corrects the sweep, which is the only process
the search found doing so today.

The latent trap remains for any *future* author who detaches a long-lived
process from an agent session: forward `GC_SESSION_ID` and the orphan reaper
will kill it once the session ends. A platform-level guard — the reaper sparing
a deliberately-detached transient user unit, or a shared "detach cleanly"
helper that strips session identity — would close the class rather than this
instance. That is a gascity design decision and a separate change; it is
recorded here for the operator to weigh, not taken on under this bead's
"one increment" bound.
