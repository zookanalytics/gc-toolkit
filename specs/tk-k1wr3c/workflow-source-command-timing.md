---
name: Why gc workflow delete-source and reopen-source looked hung
description: Timing measurements of the two source-workflow commands, the SIGTERM deferral that made slow calls read as post-print hangs under timeout(1), and the bound orphan-dispose.sh puts on them.
---

# Why gc workflow delete-source and reopen-source looked hung

Two beads reported that `gc workflow delete-source --apply` and
`gc workflow reopen-source` print their result line and then never exit.
tk-k1wr3c measured `delete-source` as exit 124 under `timeout 20` after
`result=already_clean` had printed, and `reopen-source` as exit 124 with no
output under `timeout 15`. tk-ljebin saw `result=reopened` print and the
process outlive a 20 s and a 40 s limit, with strace showing a child process
blocked reading a socket. `assets/scripts/orphan-dispose.sh` runs both
commands in its source arm with no bound, so a real hang there would stall the
witness patrol.

## Neither command hangs after printing

Measured 2026-10-04 on gc 1.4.3, on a host at load average 19 to 31 with 8
cores. Each run wrote the command's output to a file rather than a pipe and
polled it every 0.1 s, so the moment the result line appeared and the moment
the process exited were timed separately. The scratch bead (tk-rlsech5) was
created for the measurement and closed after it. The orphan shape is the one
recovery hands the source arm: `in_progress`, assigned to a dead session, with
`gc.session_id`, `gc.session_name`, `gc.session_affinity`,
`gc.continuation_group` and `workflow_id` set.

| Command | Bead shape | stdin | Printed and exited | rc |
|---|---|---|---|---|
| `delete-source --apply` | bare | `/dev/null` | 21.5 s | 0 |
| `reopen-source` | bare | `/dev/null` | 24.8 s | 0 |
| `reopen-source` | bare | open pipe, nothing sent | 25.3 s | 0 |
| `delete-source --apply` | orphan | open pipe, nothing sent | 19.9 s | 0 |
| `reopen-source` | orphan | open pipe, nothing sent | 24.1 s | 0 |

In every run the process exited within one poll of its result line. The
first reaction's three read-only `delete-source` previews took 16.6 s, 22.3 s
and 43.8 s. The two of them it timed this way exited as they printed. A plain
`gc bd show` took 1.0 s to 1.7 s on the same host.

So the commands are slow, not stuck. Both scan every store in the city (here
the city store and five rigs), and a healthy call takes tens of seconds under
load. A 15 s or 20 s limit is shorter than a healthy call.

The child blocked on a socket in tk-ljebin's strace was not reproduced. A slow
call that has taken SIGTERM looks the same from outside as a hung one until it
finishes, as the next section shows.

## SIGTERM is deferred once the lock is held

Sending SIGTERM to the read-only `delete-source` preview at different points:

| `timeout` | Exited | rc | Output |
|---|---|---|---|
| 3 s | 3.1 s | 124 | none |
| 10 s | 33.0 s | 124 | `result=already_clean …` |
| 16 s | 26.0 s | 124 | `result=already_clean …` |
| none | 22.5 s | 0 | `result=already_clean …` |

TERM at 3 s killed the process at once. TERM at 10 s and at 16 s did not: the
command ran on, printed its result, and exited normally, and `timeout` still
reported 124 because its timer had fired.

The code says why (gascity `cmd/gc/cmd_convoy_dispatch.go`). Both
`cmdWorkflowDeleteSource` and `cmdWorkflowReopenSource` resolve the city and the
source bead, then call `sourceWorkflowCommandContext`, which is
`signal.NotifyContext` on SIGINT and SIGTERM. From that point the default
action of those signals is replaced by a context cancel. The context goes to
`sourceworkflow.WithLock`, which honors it for the in-process mutex wait and
the flock wait and nowhere else. The work inside the lock is plain store calls
that take no context, so it runs to completion, and the command then returns
normally. A TERM before the signal context exists, during config load and
target resolution, still kills the process outright.

That accounts for the exit codes and output in both reports.
`result=already_clean` followed by 124 is a call that took TERM inside its
lock, finished, and exited. 124 with no output is what a call killed before it
installs the signal context produces, as the 3 s run shows. Neither is a
process that never exits.

The lock is a kernel flock, so a SIGKILL releases it with the process and
leaves no stale lock behind.

## The bound orphan-dispose.sh uses

The source arm runs both calls through `run_bounded`:
`timeout -k 30 180 <cmd> </dev/null`, tunable as `GC_ORPHAN_WORKFLOW_TIMEOUT`
and `GC_ORPHAN_WORKFLOW_KILL_AFTER`.

- **180 s** is about four times the slowest healthy call measured, so a slow
  call on a loaded host has room to finish.
- **`-k`** is required, not a refinement. A TERM-only `timeout` sends TERM once
  and then waits for as long as the child runs. Measured with this host's
  timeout (uutils coreutils 0.10.0): a child ignoring TERM ran its full 4 s
  under `timeout 1`, a child trapping TERM in a loop was still running at 68 s
  when it was killed by hand, and `timeout -k 1 1` ended each of them at 2 s
  with rc 137. BusyBox 1.37's timeout also ran a TERM-ignoring child to the end
  without `-k`, and with `-k` ended it at 2 s with rc 137.
- **30 s of grace** covers the 10 s to 23 s a locked section took to finish
  after TERM in the table above, so a call is cut off mid-write only when it is
  still running 30 s past the bound.
- **`</dev/null`** keeps the commands off the caller's stdin, as in every other
  copy of the idiom in the pack. Neither command waited on an open, silent stdin
  in any run.

A timeout exit is 124, or 137 when the KILL was needed. Because of the
deferral, neither proves the call wrote nothing, so the arm decides by what it
can prove.

- A **delete-source** cut off by the bound counts as failed
  (`failed=delete-source-timeout`), whatever it finished. `reopen-source` does
  not run, the bead stays owned, and the next cycle repeats the disposal.
  `delete-source` is idempotent.
- A **reopen-source** cut off by the bound is judged by re-reading the bead. If
  it reads open and unassigned, it is released. The arm then clears the pins,
  restores the route and runs verify exactly as after a clean exit, and reports
  `detail=reopen-source-past-bound`. If it is still in progress or assigned, it
  was not released. The arm writes nothing, reports
  `failed=reopen-source-timeout`, and exits 3, the same partial any
  `reopen-source` failure after a landed `delete-source` gets. The bead keeps
  its pins and recovery finds it again next cycle.

The first reaction proposed trusting a printed `result=reopened`. The re-read is
used instead for two reasons. It also covers a call killed after its
status/assignee write but before it printed. And capturing the output through
a pipe would let any child that inherits stdout hold the reader open past the
bound, so the arm discards the output and reads the bead. What the re-read
guards against is clearing the pins of a bead that was not released, which
would leave a still-claimed bead with its session pins stripped.

`orphan-dispose.test.sh` proves the three cases with stubs that stall while
ignoring SIGTERM, before or after their writes. Each bounded case returns in 4
to 5 s against a 60 s stall. Run against mutated copies of the script, the
suite fails 7 assertions when the re-read is removed, 2 when any timeout is
treated as a release, and 8 when `-k` is dropped, all three elapsed ceilings
among them.

## Other callers

`formulas/mol-refinery-patrol.toml` runs
`gc workflow delete-source $WORK --apply && gc workflow reopen-source $WORK` in
two rejection arms, unbounded, inside the refinery agent's own tool call. With
no hang on the current binary there is nothing those lines need a bound
against, and with no `timeout` they cannot misread a 124. A caller that does
add a bound needs both rules from the source arm: `-k` behind the TERM, and no
reading of 124 as nothing landed.

No gascity bead was filed. The hang the reports describe does not reproduce,
and deferring SIGTERM until the locked writes finish is what keeps those writes
whole.
