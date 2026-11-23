---
name: Gas City search — park, place and accept as gctk commands
description: The record, for tk-1tfzr71.226, of the Gas City and bd primitives searched before gc-helm.sh's park, place and accept became gctk commands, and why none covers each need, read at gastownhall/gascity upstream b31d0b1194 and beads v1.3.4. Read it when reviewing those commands' surface, or before moving a park, a placement or an acceptance onto a native primitive.
---

# Gas City search: park, place and accept

The commands are `gctk bead park`, `gctk bead place` and `gctk reaction
accept`, which carry gc-helm.sh's verbs of the same names
(specs/tk-1tfzr71.213/design.md, section 5). Section 8 of that design names
where each search starts. Gas City is read at gastownhall/gascity upstream
`b31d0b1194`, and bd at beads `v1.3.4`, the module Gas City depends on. No gc or
bd command is named park, place or accept (`docs/reference/cli.md` and `cmd/`
at `b31d0b1194`; `cmd/bd` at `v1.3.4`), so no native call shares a word with
these verbs.

## park: bd's deferred status and its gates

A park holds everything under a bead that has not started, leaves work in
flight running, says why the bead is parked and what releases it, and releases
when its blocker closes, or for one bead when that bead's edge comes off.

- **bd's defer.** `bd defer` sets a bead `deferred`, and `--until` gives it a
  `defer_until` that returns it to open once the time passes (`deferCmd` in
  `cmd/bd/defer.go`). bd's ready read leaves out the deferred bead and the
  children of a parent whose `defer_until` is still in the future
  (`getChildrenOfDeferredParentsInTx` in `internal/storage/issueops/ready_work.go`,
  which selects only rows whose `defer_until` is set and later than now, and
  `BuildReadyWorkWhere` in `internal/storage/sqlbuild/ready.go`). So a defer
  with no date holds the bead alone and none of its children, a dated one holds
  them only until the date, and neither releases on a condition or a person's
  decision. A defer also changes the bead's own status, which a bead in flight
  carries as its claim, and it releases its children all at once, never one
  bead alone.
- **bd's gates.** A gate is a bead a `blocks` edge waits on, and bd marks every
  bead under a blocked parent blocked, so one edge on the bead holds its whole
  subtree in the store's own answer. That is the primitive a park composes: the
  text form files a plain gate titled with the park's reason, born with its
  edge (`bd create --type gate --deps blocks:<bead>`), and closing it releases
  the park. What bd does not do is refuse the edge on a bead in flight, whose
  own open blocker would hold its merge and its close, or find the gate an
  earlier park filed under the same title. The command adds those two, and the
  survey that says what the park holds and what it leaves running.

## place: gc sling and the deferred-dispatch arm

A placement gives a bead `hold:mayor` holds its parent or none, settles its
priority, dispatches it, and lifts the hold, in an order a run again after a
stop can finish.

- **gc sling.** `gc sling` pours a formula on a bead and routes it, and nothing
  in `internal/sling` reads a dispatch hold: Gas City reads its hold labels
  where it serves work, in the hook's serve rule (`beadmeta.HasDispatchHold` in
  `cmd/gc/demand_serve_predicate.go`, `cmd/gc/cmd_hook.go` and
  `cmd/gc/assigned_work_scope.go`). So a sling of a held bead starts the work
  with the label left on, and no write of Gas City's both dispatches a bead and
  lifts its hold. A sling also refuses a second live run of one formula at one
  bead (`sourceworkflow.ConflictError`, which `cmd/gc/cmd_sling.go` answers with
  exit 3), which a placement reads as the dispatch an earlier run made.
- **The arm.** A bead a wait holds, its own or an ancestor's such as a park, is
  armed rather than slung (`gctk bead arm`), the pack's residual for a launch
  that waits on its input bead (docs/warrants.md, "Deferred dispatch
  residual"). The arm keeps the wait holding the bead and sends it once nothing
  does.

The command is the order of those native writes, each taking its exit: the
route's clear, the parent, the priority through `queue-priority.sh` (priority
following, docs/warrants.md), the sling or the arm, and the lift with its note
in one write.

## accept: gc sling's launch lock

An acceptance answers the recommendation's human gate and dispatches the
recommended formula at the bead once, even after the work it sent has
finished, and a later run finishes one an earlier run left part way.

- **The launch lock.** A graph.v2 `gc sling <bead> --on <formula>` launches
  under a per-bead lock (`withGraphV2SourceWorkflowLock` and
  `withSourceWorkflowLaunchLock` in `internal/sling/sling_core.go`) and refuses
  a second launch only while a root an earlier launch poured is live:
  `liveConvoyTrackedWorkflowRoots` in `internal/sling/sling_attachment.go`
  skips a terminal root. Once that root closes, the next launch pours again,
  and no `gc sling` flag checks an earlier root by a caller's key. So the
  acceptance keeps its own lock, one flock per bead, and titles its root with
  its token, which a later run searches before it slings
  (docs/warrants.md, "Accept's lock").
- **The gate's answer.** bd's `gate resolve` closes a gate with its reason and
  exits 0 on a gate already closed without changing it (`gateResolveCmd` in
  `cmd/bd/gate.go`), so its exit does not say whose answer the gate holds. An
  update guarded by `--if-status` refuses a closed gate, but it writes no close
  reason, and every reader takes a gate's answer from its close reason. The
  command reads the gate after its answer to settle which answer reached it
  first, a read that settles a race and confirms no write
  (docs/gctk-architecture.md, "The ledger").
- **An unfinished pour.** While the city's gc can leave a pour unfinished,
  fenced by `gc.instantiating` or open with `molecule_failed`, the command reads
  such a root as the arm's start reads one, and slings nothing beside it.
