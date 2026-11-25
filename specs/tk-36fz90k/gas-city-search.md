---
name: Gas City search — host slots for the checks gctk rig runs
description: The search behind the slots tk-36fz90k gives every run gctk rig makes, as AGENTS.md requires, cited at gastownhall/gascity 33a7d167c8, with the measurements the design rests on. Read it to judge the change's divergence from Gas City, or before changing how checks share the machine's memory.
---

# Gas City search for tk-36fz90k

Gas City is cited at `gastownhall/gascity` 33a7d167c8 (upstream main,
2026-11-25), by page or by symbol.

The surface the change adds:

- Every run `gctk rig` makes (test, lint, typecheck, setup and build) holds
  slots on the machine while its command runs, and waits for them when too few
  are free. A slot stands for 4 GiB, and a run takes one for each 4 GiB the last
  ten runs of its check in the same repository used at most, or every slot
  while none of them is measured.
- The slots are files in the push gate's directory, `<city>/.gc/gate-slots`:
  `slot-<i>.lock` up to the machine's count, and `queue.lock`, which orders the
  runs that wait.
- `GCTK_RIG_SLOTS` sets the machine's count. With it unset, the count is as
  many slots as five eighths of the machine's memory holds, 10 on a 64 GiB
  host.
- `GC_PUSH_GATE_NO_CAP=1` has a run take no slots, and every command a run
  starts gets it.
- Each repository keeps its runs' peaks in `<git common dir>/gc-rig-memory/<check>`.
- The host adapter reads a file's lock, the machine's memory and a process
  tree's resident memory.

The change adds no metadata key, bead kind, lifecycle state, order or formula
step.

## A bound on what a session's processes hold

**Searched.** A Gas City or bd primitive that bounds the processes the
sessions of a city start on its host, by count or by memory.

- `max_active_sessions` on an agent (`internal/config/session_capacity.go`)
  bounds how many sessions a pool runs. One session can run lint, typecheck and
  test at once, and the refinery's gate is a session of another agent.
- `probe_concurrency` (`DaemonConfig.ProbeConcurrency` in
  `internal/config/config.go`) bounds the bd probes the daemon runs at once.
- `providerOpSemaphores` (`cmd/gc/beads_provider_lifecycle.go`) bounds a city's
  store-provider operations, inside one gc process.
- Order dispatch (`cmd/gc/order_dispatch.go`) bounds the orders a city runs,
  which are not the commands a session runs.
- bd bounds nothing outside its store.

None bounds a process a session starts, and none weighs memory. So the bound
is gctk's, in the verb every recorded check already goes through.

## The push gate's slots

**Composed.** Gas City's own repository bounds the runs of its heavy test
suites across a host (`TESTING.md`, "Cross-invocation concurrency bound via
push-gate slots", and `scripts/push-gate-lock-lib.sh`). A run of
`scripts/test-local-parallel` holds one of `PUSH_GATE_MAX_CONCURRENT` (2 by
default) numbered `flock(1)` slot files under `<city_root>/.gc/gate-slots`,
falling back to the repository's git common directory outside a city. It
stamps the file `<pid> <iso8601-utc> <label> <hostname>`, and
`GC_PUSH_GATE_NO_CAP=1` bypasses it. This city's directory is live: its
`slot-0.lock` was last stamped 2026-11-24T21:25Z.

gctk takes the same files the same way: flock(2), which `flock(1)` shares (a
probe on this host: `flock -n` fails while a Go process holds the lock, and
succeeds once it frees it), the same directory and fallback, the same stamp and
the same bypass. So a push's suites and the checks share the machine's memory.

What the push gate leaves uncovered: it bounds only runs of its own runner,
while the commands `gctk rig` runs, such as `go test`, `go vet` and
`golangci-lint run`, call the toolchain directly. And it counts each run as one
slot, while the runs differ in memory by more than ten times (below). The
change adds slots above the push gate's two, a run's weight, and `queue.lock`.
The push gate reads none of them, and a run takes free slots from the top
down, so a push waits only once the checks fill the machine.

## Measurements

**The 11-23 crash.** The kernel's panic report
(`/Users/Shared/panics/panic-full-2026-11-23-222753.0002.panic`, its
`processByPid`) holds three `gctk rig` checks started in the same second, 374 s
before the panic, each under a bash whose parent had exited. Following each
`compile` process's parent chain up to its check:

| Check | Its compiles | Resident |
|---|---|---|
| test | four builds of one large package, from a command that runs four lanes at once | 13.0, 12.8, 11.9 and 11.5 GB |
| lint (golangci-lint) | one | 11.0 GB |
| typecheck (go vet) | one vet, its compiles done | 1.0 GB |

Free memory was 912 pages of 16 KiB and the compressor held about 35 GB. So a
bound of two checks would still have run the test and the lint check together,
60 GB of compiles on a 64 GB host. The unit that fills the machine is memory,
not a count of checks.

**How runs overlap.** Every record in the six rigs' record stores from
2026-11-11 to 2026-11-25, 2,783 runs, gives each run's start and end
(`recorded_at` less `duration_ms`). Across the host, one run was going for 63%
of the time any was, two for 23%, three for 10%, four for 3%, and at most six
at once. Replaying them through a bound of whole slots, first come first
served:

| Bound on every run | Runs that wait | Waiting, over 14.4 days |
|---|---|---|
| 1 | 1,978 | 4,057 h |
| 2 | 714 | 134 h |
| 3 | 208 | 16 h |
| 4 | 37 | 2.3 h |

The one rig whose runs build the large package had 153 of them: a bound of
one makes 68 wait, 14.6 h in all over 13 days.

**How much runs differ.** The largest single process of a lint run in this
repository (`tools/lint-change.sh` over 30 commits, read from the kernel's
account of the command) is 5.8 GiB. A build of the large package is 11 to 13
GB. A run's largest process is not its total: a probe on this host read 913
MiB for a grandchild's 900 MB, and 413 MiB for two 400 MB children at once.
So a run's weight is the largest sum over its process tree, read every five
seconds, and never less than its largest process.

## What is left

A single run that alone uses more than all the slots stand for runs alone,
with a warning, and can still exhaust the machine beside the city's other
work. The four-lane test command above is one. Its cause is in the command
and in the package's size, not in how runs share the machine, and tk-2a3xy7x
carries it to where such commands are written.
