---
name: Gas City search for the board's two views (tk-yhquh93.13)
description: The Gas City and bd primitives searched before the rig board ordered its work queue and laid out its two views, Needs you and the Work queue, what each covers, and why the board composes their rules over its own one read instead of calling them. Read it when judging whether services/gctk/queue or the document's views should exist.
---

# Gas City search for the board's two views

The change grows the rig board's document (`GET <mount>/helm/rigs/{rig}`). Each
epic and Delivery now carries its own Needs you, Work queue and closed work, the
Needs you and Work queue pages carry the same views across the rig, and a
container's counts lead with its needs. It adds one gctk domain package,
`services/gctk/queue`, which places work in the order it is expected to land.
It adds no route, verb, order, metadata key, bead kind, label or lifecycle state.

The upstream code below was read on 2026-11-12, at the commits the city runs:

- Gas City at `gastownhall/gascity` `f143846427`. The city's gc 1.4.3 reports
  a build of a fork's `36ad5186a`, whose upstream base is that commit, and the
  fork's commits change nothing in `internal/config/workquery.go`.
- beads at `gastownhall/beads` `7ef2fd05e`, on its `hotfix/1.3.1` branch. That
  is the commit `bd version` reports for the city's bd 1.3.4.

## The order work is expected to land in

| Primitive | What it gives | Covers the need? |
|---|---|---|
| `bd graph` (`computeLayout` in beads' `cmd/bd/graph.go`) | Execution layers over one bead's subgraph. Its help says "Layer 0 / leftmost = no dependencies (can start immediately)", "Higher layers depend on lower layers" and "Nodes in the same layer can run in parallel". A bead's layer is one past the latest layer of the beads its `blocks` edges name, and a child is lifted to its parent's layer | The rule, yes, and `queue` applies it. The command, no. `gc bd graph tk-1tfzr71 --compact` gave no answer in more than two and a half minutes on 2026-11-12 and was stopped, against the board's thirty-second read. It draws one bead's subgraph, never a rig's whole queue, and it reads only `blocks` edges, where waits answers what holds a bead across `blocks`, `conditional-blocks` and `waits-for` and through a parent |
| The pool's claim order: `routedReadyTierCommand` in Gas City's `internal/config/workquery.go`, and `SortBeadsReadyOrder` in its `internal/beads/query.go` | A pool worker claims routed ready work in "the reader's canonical (priority, created_at, id) default order", bd ready's default `--sort priority` | The rule, yes, and `queue` orders each layer by it. The reader, no. bd ready answers only the work nothing holds, and the queue lists the held work too, layer by layer |
| bd ready's sort (`BuildReadyWorkOrder` in beads' `internal/storage/sqlbuild/ready.go`) | `ORDER BY priority ASC, created ASC, id ASC` for the priority policy, bd ready's default | The same order as the claim order above, cited at the bd the city runs |
| bd ready's status rule (`BuildReadyWorkWhere` in the same file) | Ready work is at status open or in_progress, and a bead deferred to a later time is left out | Yes, as the test for what can go now. A bead whose status bd's ready set does not admit, such as deferred, sits in layer 1 at least, though no wait is ahead of it. A claim Gas City records as hooked goes as in_progress does, as the board's table already reads it |
| `gc ready` (Gas City's federated ready reader, `gcReadyCommand` in `internal/config/workquery.go`) | The ready set across stores, in the same canonical order | No, for the reason bd ready does not: it lists ready work alone |
| The supervisor's bead routes, `GET /v0/city/{cityName}/beads` and `GET /v0/city/{cityName}/beads/graph/{rootID}` (`collectBeadGraph` in `internal/api/handler_beads.go`) | A rig's beads, and one root's parent-child closure | No. Neither gives a layer or an order, and unit 1's search found their rows carry no await type and fold a deferred or blocked status into open ([specs/tk-yhquh93.2/gas-city-search.md](../tk-yhquh93.2/gas-city-search.md)) |

No primitive answers a rig's whole queue in order, so `queue` composes the two
rules over the waits the board's one read already answers. It computes no wait
of its own: a bead's waits are the waits behind its status as waits answers
them, less a review or a rework anchored to it, which the board does not list
apart from its anchor. A wait on a bead that is no queued work, such as a
question, counts as one on a bead in layer 0, as `computeLayout` places a bead
with no dependencies. Work nobody has scheduled comes after the queue, and so
does the work that waits on it, so nothing sits above what it waits on. Whether
work is scheduled is the board's existing test, armed, routed or assigned, or
in flight by waits' answer, now held once in `queue.Scheduled`.

## What holds a bead, and what a need is

These come from the pack's shared readers the board already asks, unchanged:
`services/gctk/waits` for the waits behind each bead's status, `prstatus.Holding`
for every bead a need holds through any chain of `blocks` edges, and
`services/gctk/conversation` for a conversation's subject. A need is one of the
asks the table already names. The search behind those readers is
[specs/tk-yhquh93.2/gas-city-search.md](../tk-yhquh93.2/gas-city-search.md).

## How the order is cached

The order is a function of the rig's one read, computed once while the read
builds the document. It is cached with the rig's document by the board's
existing rule (`server.RigBoardTTL`, dropped when a write route succeeds), so it
adds no cache and no read.
