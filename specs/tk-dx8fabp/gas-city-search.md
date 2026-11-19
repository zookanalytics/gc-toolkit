---
name: Gas City search for a decision's last hand-back on the board
description: The search AGENTS.md asks for before the rig board's document gains a hand-back on a decision's row. What Gas City and bd offer for finding the conversations that track a bead and the hand-backs they record, read at named upstream commits, and why the board's read composes bd's metadata-key listing. Read it when checking whether that read can move onto a Gas City primitive, or when its cost matters.
---

# Gas City search for a decision's last hand-back on the board

The rig board's document gains one key, `handback`, on an open decision's row.
It holds the newest hand-back a converse sitting recorded on a conversation
that tracks the decision, with when it was recorded and on which conversation,
and the page's Details opens with it. A sitting records each hand-back on its
conversation as `gc.handback` and `gc.handback_at`, which `gc-helm.sh handback`
writes ([the search behind those keys](../tk-6sn8yea/gas-city-search.md)). The
board reads both keys through gctk's listing, read-only, and adds no key to the
store.

The change's other two rules add no surface. A decision that waits on work of
its own reads as waiting rather than as a question, and a decision a
conversation tracks reads that conversation's state. Both compose what the
board and a pull request's status already read: bd's blocked set through
gctk's `waits`, the `blocks` edges `prstatus.Holding` walks, and a
conversation's own `tracks` edge.

## The need

For each open decision, the conversations that track it and the hand-back each
records, closed conversations included. A sitting that ends at its hand-off
closes its conversation, so a read of the live beads alone misses the hand-back
the operator most needs: the one that says where the last sitting left the
decision.

## Where the search looked

Each was read on 2026-11-17:

- Gas City at `gastownhall/gascity` `f143846427`, upstream main and the commit
  the city's fork builds on: its supervisor API and its bead store.
- bd as `github.com/steveyegge/beads` `v1.3.4`, the version the host's bd
  reports.

## What each offers

- **The supervisor's bead routes.** `GET /v0/city/{cityName}/bead/{id}/deps`
  (`humaHandleBeadDeps`, `internal/api/huma_handlers_beads.go`) answers a
  bead's parent-child children, not the beads that track it.
  `GET /v0/city/{cityName}/beads` (`BeadListInput`,
  `internal/api/huma_types_beads.go`) filters by status, type, label, assignee
  and rig, and takes no metadata key and no edge. So the page cannot ask the
  supervisor for a decision's conversations the way it reads a bead's
  description, and no route lists them for the service either.
- **A hand-back in Gas City.** Gas City has none of its own. The one name it
  gives one is a launch's startup nudge (`queueStartupNudgeHandback`,
  `cmd/gc/startup_nudge_handback.go`), which has nothing to do with a sitting.
- **`bd list --has-metadata-key <key> --all`** (`listCmd`'s flag,
  `cmd/bd/list.go`) lists every bead that carries a key, closed beads included.
  gctk's ledger already composes it as `ledger.Carrying(key).WithClosed()`, and
  the board's read uses it: one call per rig read, made only while the rig has
  an open decision. Its rows decode through the listing's declarations like
  every other row the board reads.
- **`bd dep list <ids> --direction=up --type tracks`** (`depListCmd`,
  `cmd/bd/dep.go`) names the beads that track each bead, closed ones included.
  A batch answer does not say which bead each row tracks, and its rows carry no
  edges, so a reader needs a second read by id for the rows. Gas City reads a
  bead's children in that shape (`BdStore.ChildrenOfAny`,
  `internal/beads/children_batch.go`: one `bd dep list --direction=up
  --type=parent-child` for every parent, then one batched `bd show`). gctk's
  store adapter has no selection of that kind.
- **`bd show`** answers how many beads depend on a bead (`dependent_count`),
  not which.

## Why the board composes the metadata-key listing

On gc-toolkit's store both reads cost about the same today. The metadata-key
listing took 0.72 to 0.78 s for its 212 rows at a load of 8, and `bd dep list`
over the rig's five open decisions took 0.53 s before the by-id read of the
closed conversations it names. The listing needs nothing gctk's adapter lacks.
Its cost grows with the hand-backs the store holds: 212 were recorded between
2026-10-26 and 2026-11-17, about ten a day. The dependents read stays bounded
by the open decisions' conversations, at the price of a new kind of selection
in gctk's store adapter, the two-call shape `ChildrenOfAny` takes for
parent-child edges. The rig's document is cached for a minute
(`server.RigBoardTTL`), so the read runs at most once a minute per rig, and
once more after each write the board makes.
