---
name: Gas City search for the reader of the human gates that hold a PR
description: The search the arch check asks for before the pack adds `gctk pr-status gates` and grows `blocker-holder.sh`'s stuck answer, what each bd and Gas City primitive covers and leaves, and the measurements behind the walk's bound and its read. Read it when judging whether that reader should exist, or when a later bd or Gas City release may retire it.
---

# Gas City search for the reader of the human gates that hold a PR

A PR's anchor can wait on a rework that waits on a human gate. The change makes
one reader, `prstatus.HoldingGates`, return the open human gates reached from a
bead through its open `blocks` edges, and points the `held: gate` label, the
board's PR row and `gc-helm engage` at it. It adds this surface:

- `gctk pr-status gates --anchor <id>`, a new verb, which is how `gc-helm.sh`, a
  POSIX shell script, reaches the Go reader.
- `blocker-holder.sh`'s `stuck` answer, which now names every blocker nothing
  marks instead of the first, so `gctk merge` can read each for a gate. Its `actor`
  answer also counts `gc.dispatch_when_ready`, the pack's own arm, which has no
  Gas City reader to ask.

It adds no metadata key, bead kind or lifecycle state. Read on 2026-11-01 at
beads upstream `6ebaacba8` (`gastownhall/beads`) and Gas City upstream `f3c4ca5bb`
(`gastownhall/gascity`).

## What was searched

| Primitive | What it gives | Why it does not cover the need |
|---|---|---|
| `bd dep tree <id>` (`GetDependencyTreeInTx`, `isDependencyTreeEdge` in `internal/storage/issueops/dependency_tree.go`) | A bounded, cycle-safe walk down from a bead | It follows every dependency type except `relates-to`, so it walks parent-child and tracks edges too, and a bead reached first through one of those is listed once under that edge (the first-visit rule on `TreeResult.Nodes`, `issueops/treewalker.go`). `cmd/bd/dep.go` omits `--type` on purpose and says to use `bd dep list --type`. Its `--status` filters what it shows, and a walk must not pass through a closed blocker. A walk that must follow only open `blocks` edges cannot be rebuilt from its rows |
| `WalkTreeRequest` (`issueops/treewalker.go`) | The same walk as a library call: `RootID`, `Direction`, `MaxDepth`, `Status`, `MaxRows` | It has no edge-type field, and its walk counts every dependency type but `relates-to` as an edge |
| `bd graph <id> --json` (`loadGraphSubgraph` in `cmd/bd/graph.go`, `loadGraphSubgraphUOW` in `cmd/bd/graph_proxied_server.go`, `GraphNode.DependsOn`) | One read of a bead's connected component: a row per bead with its status and await type, and each node's `blocks` edges | It reaches that component through every edge type in both directions, a read per bead, so its cost is the size of the bead's whole family. On one live PR anchor in an epic it took about 8 minutes at a load of 20 to 50, where this walk answers in 0.3 s; on an anchor with a small family it took 0.25 s. A read that fails inside its walk is skipped on both routes, so a partial component reads as a whole one, which a reader of what holds a PR cannot take |
| `bd dep list <id> --type blocks` | One bead's blockers, whole rows | One level. Over several ids it prints bare edges with no far bead, so a status needs a second read |
| `bd gate list <id>` (`cmd/bd/gate.go`) | "ONLY the gates that block that issue" | One level. It cannot see a gate on a rework from the PR |
| `bd show <ids> --json` | A row per id, each dependency's far bead with its `dependency_type`, `status`, `issue_type`, `await_type` and `title` | One level per call, and this is the read the walk composes |
| `GET /v0/beads/graph/{rootID}` (`humaHandleBeadGraph` in `internal/api/huma_handlers_beads.go`, `collectBeadGraph` in `internal/api/handler_beads.go`) | A root's member set: its root id and parent-child closure, with a convoy's members | That is membership, not the `blocks` graph, and `beads.Bead` (`internal/beads/beads.go`) carries no await type, so no API bead can be told to be a human gate |
| `bdBurnDependents` (`cmd/gc/bd_split_judges.go`) | Gas City's own transitive walk | It walks dependents through any edge type, and it is private to `gc`. It asks bd "one level at a time" as this walk does, so upstream has no primitive it could use either |

No primitive returns what the bead asks for at the cost a label pass can pay, so
the pack composes `bd show` a level at a time. A release of `bd dep tree` that
takes `--type`, keeps a bead reached by a second path and stops at a closed
blocker retires the walk in `gates.go`, and only that.

## Why the shell asks gctk

The operator's ruling in sitting `tk-m4utp80` on 2026-10-30, quoted in
`tk-1sks8ez`, says of engage and the label: "They shouldn't be architecturally able
to diverge." That bead reads it to exclude copies kept in agreement by a parity
test. `gc-helm.sh` is POSIX shell and cannot import Go, so it asks the binary
rather than holding a jq copy of the walk.

## What the read has to be

`bd show <ids> --brief-deps --json` looks like the better read, with about a
fifteenth of the bytes on a wide walk. It drops `await_type` from each dependency
row, leaving
`created_at`, `dependency_type`, `id`, `issue_type`, `priority`, `status`, `title`
and `updated_at`. On that read `gctk pr-status gates` answered `[]` for a real
gate, and a hermetic stub that printed `await_type` passed. The walk reads the full
`bd show <ids> --json`.

Timed at bd 1.3.2 on `gc-toolkit` at low load, the two forms cost the same per
call:

| Beads named | `--json` | `--brief-deps --json` |
|---|---|---|
| 1, a PR anchor with a gate | 0.22 s, 2.6 KB | 0.22 s, 1.8 KB |
| 1, an epic member | 0.23 s, 187 KB | 0.24 s, 12 KB |
| 15, the members of the migration epic | 1.06 s, 2.7 MB | 1.06 s, 186 KB |

The large answers are wide walks from an epic's members. A PR anchor's walk is the
first row.

## The walk's bound

Measured on 2026-11-01 over the city's seven stores, from the `dependencies` and
`issues` tables, following `blocks` edges onto beads that are not closed. No store
held a cycle, and no gate had an open blocker of its own.

| Across the stores | This rig's store | The widest and deepest of the others |
|---|---|---|
| Beads with an open blocker | 304 | 40 |
| Deepest walk from any of them | 7 | 6 |
| Most beads reached from one | 25 | 8 |
| Live PR anchors: deepest walk | 2 | 1 |
| Live PR anchors: most beads reached | 7 | 3 |

`walkDepth` is 16, about twice the deepest graph, and bounds the levels of a root's
walk, so the reads of one call too, since the walks of a call share a read per
level. `walkBeads` is 256, about ten times the widest, and bounds the beads a
root's walk reaches. Each root has both to itself, so a root's answer is the same
alone as beside others, and the board and the label cannot differ on it. A root past
either has no answer: its label stays as it is and the board's partial note names
it, rather than reporting a set it did not finish, and the other roots keep theirs.

## Live comparison

The deployed `gctk pr-status derive --json` and the branch's agreed on all 48 live
PR anchors across the stores before the routed-gate fix. No live PR had a gate
behind another bead at that moment, so the walk changed no value there. It found
the 7 gates on anchors themselves.

On those 7, `held` read both `gate` and `blocked`. Each gate carries
`gc.routed_to=human`, a stamp from before the native-gates cutover, so
`personBlocker` counted it a second time. `human-gate.sh` stamps no route, so a gate
it files reads once. A human gate now counts as a gate whatever its route, which the
board's comment on `demand` already said. Five of the 7 lose `blocked` by that. The
other two keep it, because each also waits on a task routed to a person.

Read again once each root walked for itself, over 46 live PR anchors and 755 board
rows, against the deployed build. Eight anchors hold a gate, each directly on the
anchor, and six of those gates carry the stamp. Five of the six lose `blocked`, and
the sixth keeps it because it also waits on a task routed to a person. Seven rows
read a gate's question in NEEDS where they read something else, and no other row
moved.

Because no live PR had a gate behind another bead, the walk was also checked
against an answer computed apart from it: the same closure, taken from each store's
`issues` and `dependencies` tables, for every open bead with an open blocker. Over
420 such beads in six stores, two of them two edges from a gate, `gctk pr-status
gates` gave the tables' answer for all 420, one bead at a time. The board's library
read gave it too, with each store's beads in one call and with each bead alone, so
the batch and the single read agree on the live graph, where nothing is near either
bound. The walk that shared one set across its roots gave the same answers.

The batch over this rig's 304 beads took 35 to 39 ms, and 42 to 64 ms on that earlier
walk, at a load of about 45. The store's reads are the cost, and each root's own set
adds nothing measurable.

## What this leaves

- `finalize-gate.sh` keeps reading only the gates directly on the bead. A gate on
  a rework already holds the merge, because the rework is an open blocker of the
  anchor, which `gctk merge` and `bd close` each refuse on.
- The supervisor backend walks nothing, because `beads.Bead` carries no await type,
  so it knows no human gate at all. `tk-1tfzr71.24`, which retires the embedded
  store reader, carries that requirement.
- The walk stays in the bead's store. `bd show` lists no edge onto another store's
  bead, and the board's hydration drops one, so a gate in another store counts
  nowhere. Three open beads carried such a `blocks` edge on 2026-11-01, none of them
  a PR anchor.
- `tk-1sks8ez` waits on this bead and reads what landed.
