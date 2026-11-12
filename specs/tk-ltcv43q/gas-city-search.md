---
name: Gas City search for the feedback pattern's lifecycle
description: What tk-ltcv43q looked for in bd and Gas City before moving the feedback pattern from a standing record onto bd's own work states, which primitives the distiller composes for each state (deferred with a date, a blocks edge onto the follow-up, close, reopen, the ready read), why the pattern stays a task with a task_kind and not a kind of its own, and why check-blocked-work-armed exempts a pattern instead of asking it for an arm. Read it when judging the feedback-pattern warrant, a change to the distiller's pattern states, or a proposal to move patterns onto another bead kind.
---

# Gas City search for the feedback pattern's lifecycle

bd was read at `gastownhall/beads` v1.3.4 (7ef2fd05eb0c, the build the city's
`bd` reports as `1.3.4 (7ef2fd05e+patched)`) and at main 125c62063406. Gas City
was read at `gastownhall/gascity` main 6bd609f5bfb4. The gc-toolkit store was
read on 2026-11-12 between 18:30Z and 19:00Z.

The operator ruled in conversation tk-2pvj50q that the city keeps no standing
records, so a feedback pattern becomes backlog work that closes once resolved.
Each state the ruling names maps onto a bd primitive, and the distiller composes
those primitives. Nothing new is built for a state.

## The states, and the primitive each one composes

| The pattern | The primitive | Where |
|---|---|---|
| Waits for more evidence, out of the work queues until a date | bd's `deferred` status with a date. `bd defer --until` is a snooze: once the date passes, the next ready read returns the bead to open. `bd ready` leaves a deferred bead out, and Gas City's ready view leaves it out too, dated or not, until the store lifts the deferral. | `StatusDeferred` in `internal/types/types.go` and the help in `cmd/bd/defer.go` (bd v1.3.4); `IsDeferred` and `IsReadyCandidate` in `internal/beads/beads.go` (gascity) |
| Waits on the follow-up it spawned | A `blocks` edge. bd's ready read leaves the bead out until the blocker closes, and Gas City's readiness counts `blocks` as blocking. | `readyBlockingDependencyTypes` in `internal/beads/beads.go` (gascity) |
| Resolved, and gone from the queues with its id, rollups and evidence kept | `bd close --reason`. A closed bead keeps its id and metadata, a later write to its metadata lands (the distiller already stamps `obs.distilled` on closed observations), and `bd list --all` lists it. | `cmd/bd/close.go` (bd v1.3.4) |
| Its feedback recurs | `bd reopen`, which sets the bead open, clears its `closed_at` and records a Reopened event. Gas City drops the close reason on any move out of closed. | `cmd/bd/reopen.go` (bd v1.3.4); `setBeadStatus` in `internal/beads/beads.go` (gascity) |
| Needs a decision | `bd ready --metadata-field task_kind=feedback-pattern`: open, unblocked and not deferred, which is also the read that returns an expired deferral to open. The distiller's every-run pass works this list, and the run ends when it is empty. | `cmd/bd/ready.go` (bd v1.3.4) |

## What neither provides

- **A kind for knowledge kept apart from work.** Every bd status is a work
  state (`AllStatuses` in `internal/types/types.go`). The `pinned` status,
  "Persistent bead that stays open indefinitely", is a record that never
  closes, the shape the ruling turned down, and Gas City folds every bd status
  but closed and in_progress into open (the `SourceStatus` comment in
  `internal/beads/beads.go`), so a pinned pattern reads as open work to gc. bd's
  Memory Beads proposal (`gastownhall/beads` issue #5877, open) would be that
  kind: a Memory Bead never becomes ready, blocked, claimed, completed or
  closed, and a derived-from field lists the beads it was written from. No
  memory type is in `internal/types/types.go` at v1.3.4 or at main.
- **A way for a pack to keep its own type out of the ready view.** Gas City's
  ready view leaves out a fixed list of types and a fixed list of labels
  (`readyExcludeTypes` and `HasReadyExcludedLabel` in
  `internal/beads/beads.go`), and a pack can add to neither.

So a pattern stays a task bead named by `task_kind=feedback-pattern`, the pack
noun [docs/warrants.md](../../docs/warrants.md) warrants until a knowledge kind
ships, and its lifecycle is the composition above.

## Why check-blocked-work-armed exempts a pattern

`doctor/check-blocked-work-armed` takes a bead's dispatch path to be a route or
an arm (`assets/scripts/dispatch-path.sh`). A pattern waiting on its follow-up
has neither. Its dispatcher is the distiller, whose run lists every ready
pattern and decides it.

Composing an arm was weighed. The waits skill's validating closer
(`mol-validate-close`) fits a bead whose whole job ends when its blocker closes:
it closes the bead, or asks a person when the blocker closed without the fix it
promised. A pattern's follow-up can close with no rule landing, as a vetoed
proposal does, and what follows is the distiller's judgment, not a person's
question. A pattern that waits on a contention gate needs the distiller to act
on the ruling, which no formula a pool runs does. An arm would add a second
decider for one transition and leave the gate case unarmed. So the check exempts
the kind, as it exempts a review bead, and names the distiller as the reason.
