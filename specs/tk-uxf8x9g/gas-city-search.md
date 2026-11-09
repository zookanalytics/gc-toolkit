---
name: Gas City search for await-ruling.sh --held-by
description: The Gas City and bd primitives searched before await-ruling.sh gained --held-by, the form that arms a declined run's re-sling with no new edge when the store already holds the work bead, cited by symbol at gastownhall/gascity main d12e89601880 and gastownhall/beads 7ef2fd05e. Read it when you review or change --held-by or the work gate's wait.
---

# Gas City search for `await-ruling.sh --held-by`

The work gate (`assets/scripts/work-gate.sh`) asks `gctk bead holds` what
holds the work bead before a run builds it. A bead the answer holds through a
parked ancestor, or by a `waits-for` edge of its own, has no blocker of its own
for `await-ruling.sh --blocked-by` to write an edge onto. So the script gains
`--held-by <bead>`: the store already keeps the wait, no edge is written, and
the run's re-sling is armed as for any other wait. The gate passes it for every
hold, a blocker of the bead's own included, since that edge is already there.

## The need

Pour `mol-polecat-work` over the work bead, to its pool and once, when nothing
holds the bead any longer, where what holds it is a wait the store already
keeps.

## What was searched, at gastownhall/gascity main d12e89601880

- **`gc sling --on`** (`docs/reference/cli.md`, "gc sling"). It pours at once.
  Its one read of a bead's dependencies is `DetectCycle`
  (`internal/sling/cycle.go`, called at `internal/sling/sling_core.go:113-115`),
  which refuses a cycle, not a held bead, and none of its flags defers a pour
  until the bead is ready. That is why a held bead reaches the gate at all.
- **The ready queue, through a route** (`gc sling --no-formula`, and the pool's
  routed demand query, `PoolDemandServeRulesForQuery` in
  `internal/config/workquery.go:267`). The pool is offered a routed bead once
  `bd ready` lists it, and a parent's wait keeps it out of that list, so the
  release is native. But the pool claims the bare bead and pours no formula, so
  `mol-polecat-work`'s steps would not run.
- **core's `cascade-nudge-on-blocker-close` order**
  (`internal/bootstrap/packs/core/orders/cascade-nudge-on-blocker-close.toml`,
  `on = "bead.closed"`). It nudges the assignee or routed target of each
  dependent a `blocks` edge links to the closed bead. It reads no parent-child
  hold and pours nothing.
- **`gc session pin`** (`docs/reference/cli.md`, "gc session pin"). The
  reconciler starts a pinned named session once its canonical bead is
  unblocked. That starts a session, not a pour onto a work bead.

None records a pending "pour this formula to this pool once nothing holds this
bead". The pack's deferred-dispatch arm does, under the deferred dispatch
residual warrant (`docs/warrants.md`), and `await-ruling.sh` already writes it
for its other two forms. `--held-by` composes the same parts, the claim
release, the route clear and the arm, and leaves out the edge.

## Why no edge, in bd at gastownhall/beads 7ef2fd05e

The bd the city runs (`bd version`: 1.3.4, 7ef2fd05e) refuses a close only for
the bead's own live waits: `IsBlockedInTx`
(`internal/storage/issueops/dependency_queries.go:906`) reads the bead's own
`blocks`, `waits-for` and `conditional-blocks` edges, so a bead held only
through its parent closes. A `blocks` edge from the work bead onto its
ancestor's gate, which `--blocked-by` would write, would make bd refuse the
bead's close while the park stands, and would keep holding the bead once its
work starts, where `gctk bead holds` holds work in flight only by its own
waits. With no edge, the store's own answer is the only wait, and the arm fires
when that answer clears.
