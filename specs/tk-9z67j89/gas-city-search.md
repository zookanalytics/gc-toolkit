---
name: Gas City search for a copy whose app listens from a process group of its own
description: The search behind tk-9z67j89's change to gctk rig serve, as AGENTS.md requires, cited at gastownhall/gascity d6d5784f9cff. Read it to judge the change's divergence from Gas City, or before changing how gctk rig serve decides a copy is up or how a copy's processes are stopped.
---

# Gas City search for tk-9z67j89

Gas City is cited at `gastownhall/gascity` d6d5784f9cff (upstream main,
2026-11-24), by page under `docs/` or by symbol and file.

The surface the change grows is the readiness test of `gctk rig serve`
(`copyRec.ready` and `copyRec.owned` in `services/gctk/internal/rig/serve.go`).
It now tells a listener on the copy's port that the copy started, but that runs
in a process group of its own, from another program on the port. Such a
listener fails the copy at once, under the report's existing reason
`not-answering`, with a detail that names the listener's group and how a start
command keeps its app in the copy's group. Before, a start waited out its ten
minutes. A check of a running copy reports the same detail. The change adds no
flag, report key, reason or state.

## A process that leaves its starter's process group

**Searched.**

- **A service's process.** A `[[service]]` of kind `proxy_process` runs its
  command in a process group of its own (`proxyProcessSysProcAttr` in
  `internal/workspacesvc/proxy_process_other.go` and `proxy_process_linux.go`).
  It counts the service ready once it answers on the Unix socket Gas City hands
  it as `GC_SERVICE_SOCKET`, and on its `health_path`
  (`(*proxyProcessInstance).waitReady` in `internal/workspacesvc/proxy_process.go`,
  and ServiceProcessConfig in `docs/reference/config.md`). It stops the service
  by signalling that group (`stopProcessGroup`). A service is one supervised
  process per name that the city declares and the controller starts, which
  tk-rymdhac's search found a copy cannot be
  ([its search](../tk-rymdhac/gas-city-search.md#a-copy-of-a-rigs-ui)). Its
  readiness reads no TCP port, and neither its readiness nor its stop looks for
  a descendant that left the group.
- **An exec order's escaped groups.** `escapedOrderGroups` in
  `cmd/gc/order_exec_escaped_groups.go` meets the same escape: it returns the
  process groups that a descendant of an exec order's shell started for itself,
  as GNU timeout does, by following parent links from the shell, and the
  order's cancel kills them (`terminateProcessGroups`). It is internal to gc's
  order dispatch, with no command or API a copy can call. Its comment names its
  limit: "The walk follows parent links, so it cannot reach a descendant that
  was already orphaned (reparented away from the order's tree) before the
  cancel."
- **A session's processes.** The tmux provider's stop walks a session's process
  tree by parent links and also signals a descendant's own group
  (`buildProcessKillPlan` in `internal/runtime/tmux/tmux.go`). It stops agent
  sessions, not a process a session starts for a worktree, and it reads no
  port.
- **Gas City's orphan sweep.** A copy already composes it. Once the session
  that started a copy ends, the sweep finds a reparented process root by the
  session's `GC_SESSION_ID`, and ending the root signals its process group
  (`sweepProcessTableOrphans` and `processRootIncarnationOver` in
  `cmd/gc/session_beads.go`). The copy's leader carries those variables and
  leads the copy's group, so the sweep reaches every member of the group
  through it. The serve command runs with none of the variables that point a
  command at the city (`serve.go`'s header), so a listener in a group of its
  own is neither a member the sweep's group signal reaches nor a root the sweep
  recognizes.
- **Which process holds a port.** `ListenerPID` in `internal/pidutil/listener.go`
  and `findPortHolderPID` in `cmd/gc/dolt_process_inspection.go` name one
  process that holds a TCP port, for the managed Dolt server's ownership check.
  They compare one process id. None lists every listener or compares process
  groups.
- **A dev server or an app preview.** Nothing under `docs/` or `engdocs/`
  describes running an app for a worktree. `git grep -i` for dev server, app
  preview, preview server and `start_command` finds only the agent's
  `start_command` rows of `docs/reference/config.md`, and `pnpm` appears once,
  in a build-cache design note
  (`engdocs/design/bazel-remote-repo-contents-cache.md`).

**Composed.** The copy stays one process group, the shape its leader's stop
and Gas City's orphan sweep both end whole. A listener in another group escapes
both, and following parent links at the stop, as `escapedOrderGroups` does,
cannot reach it once the process between them has ended. So the change refuses
such a copy at once rather than count it up, and the demo-capture skill's start
contract gives the form that keeps the app in the group.

## Where the growth lives

The readiness test is gctk's, in Go, beside the copy's record and its stop.
It reads the process table through gctk's host adapter, as the rest of a copy's
decisions do.
