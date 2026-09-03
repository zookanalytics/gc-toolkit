---
name: doctor-sweep vanishes on deacon session teardown — root cause and fix
description: Why the detached doctor sweep died with no rc/finished_at (3 of 4 runs), the teardown mechanism proven from code and live probes, and why the fix is an independent systemd scope rather than a longer bound, a retry, or instrumentation. Read when revisiting doctor-sweep.sh's launch or any detached-process-survives-its-launcher pattern.
---

# doctor-sweep vanishes on deacon session teardown

## Symptom

`assets/scripts/doctor-sweep.sh` starts `gc doctor` detached under `setsid` and
reads the result on a later patrol cycle. Three of four runs vanished mid-sweep:
the run dir held `pid`, `started_at`, `stderr.log` and an empty `payload.json`,
but no `rc` and no `finished_at`. Because the wrapper writes `finished_at` before
`rc`, the absence of both means the session leader itself died, not just
`gc doctor`. The collector then reports `state=failed reason=sweep-vanished` and
doctor coverage is lost until the next start.

## Diagnosis (corrects the bead description's exoneration)

The bead description argued the deacon-teardown hypothesis failed its control:
"zero deacon session-gone lines for run A between 01:20 and 01:49." That reading
was wrong — an unanchored time grep over a 330 MB log. Re-run anchored, all three
deaths sit on a deacon session teardown:

    run A: last stderr 01:32:23 -> deacon session gone 01:32:56  (+33s)
    run B: last stderr 02:39:30 -> deacon session gone 02:40:08  (+38s)
    run C: last stderr 03:52:58 -> deacon session gone 03:53:41  (+43s)

The deacon is `mode=always` / `wake_mode=fresh`: it drains at the end of each
patrol cycle (~every 18 min) and the controller starts a fresh session. The
teardown is normal, not a fault. The sweep is collateral.

## Mechanism (proven, not inherited)

The controller tears a session down with `KillSessionWithProcesses`
(gascity `internal/runtime/tmux/tmux.go`). It does **not** stop a cgroup — every
agent session shares the one `gascity-supervisor.service` cgroup, so a cgroup
stop would take the whole city. Instead it:

1. walks the pane leader's **entire descendant tree** and SIGKILLs it — its own
   comment says this is "to catch processes that called `setsid()`"; and
2. sweeps **process-group members reparented to init** (PPID==1).

`setsid` gives the sweep a new session and process group, so it escapes the pgid
sweep. It does **not** escape the descendant walk: when `doctor-sweep.sh` exits
(immediately, right after launching), the detached child reparents to the
session's harness, which is a `PR_SET_CHILD_SUBREAPER`, so it stays a descendant
of the pane leader and the walk SIGKILLs it.

Live probes on the host confirmed the escape path:

- a plain `setsid` child lands in the caller's cgroup
  (`…/gascity-supervisor.service`) — no isolation;
- `systemd-run --user` in **service mode** parents the process to the systemd
  user manager (PID 1273), outside the pane's process tree, process group, and
  cgroup;
- the live deacon's environment carries `XDG_RUNTIME_DIR` and a reachable user
  bus, so the fix engages in production, not only in a test shell.

## Fix

Launch the sweep as a **transient systemd user service** (`systemd-run --user`),
falling back to `setsid`/`nohup` where no user manager is reachable (or when
`GC_DOCTOR_SWEEP_NO_SYSTEMD` is set). A host with no per-session cgroup/tree
teardown needs only `setsid`, which is what the fallback covers.

Two traps the obvious implementation hits:

- **Use service mode, not `--scope`.** `systemd-run --user --scope` runs the
  command as a child of `systemd-run` in the caller's process tree, so the
  descendant walk still reaches it. Only service mode reparents to the user
  manager and escapes.
- **Pass the body as a file, not an inline `sh -c` string.** systemd performs
  variable expansion on a unit's argv: `$$` becomes a literal `$` (and `$VAR`
  expands against the unit's environment), which corrupts the pid the wrapper
  records. Read from a file, `sh` sees the body unexpanded. A service also
  starts with a clean environment, so the caller's is forwarded with
  `env -0` → `--setenv`; `gc doctor` needs the city context the caller holds.

## Why not a longer bound, a retry, or instrumentation

The sibling bead tk-hrjb8a retries a failed sweep once per hour. That bounds the
blind window; it does not restore the sweep — a systematically killed sweep just
dies twice an hour, and a retry started from the next deacon cycle inherits the
same teardown. The bead description's first suggestion — a signal trap and a
`/proc/self/cgroup` capture to make the next death self-describing — was a
diagnostic, superseded once the mechanism was proven from the teardown code and
live probes. The remedy is to make the sweep un-killable by the teardown, which
the independent scope does.
