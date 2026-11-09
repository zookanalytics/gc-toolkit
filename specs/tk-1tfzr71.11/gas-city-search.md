---
name: Gas City search for the check that a blocks edge's two ends share a store
description: What bd and Gas City do with a blocks edge onto a bead in another store, and why a pack writer compares the two ids' prefixes before its dep add. Read it when judging bd-lib.sh's bd_same_store, a writer's refusal of a wait across stores, or a proposal to drop the check for a platform feature.
---

# Gas City search for the check that a blocks edge's two ends share a store

Read on 2026-11-08 at `gastownhall/beads` v1.3.4 (7ef2fd05e), the city's bd,
which reports `1.3.4 (7ef2fd05e+patched)`, and at `gastownhall/gascity` main
c7a45437f.

## What was decided

A writer adds a `blocks` edge only when both ids carry the same prefix, the
text before the first hyphen, which names the store that holds the bead. A wait
across two stores is refused before anything is written. The bash scripts share
bd-lib.sh's `bd_same_store`. gc-helm.sh, which is POSIX sh and cannot source
bd-lib.sh, the formula steps and the skills' blocks compare the prefixes
inline. human-gate.sh's gate is filed in its subject's store by `gc bd`'s
routing, so it compares the id its create returns with the subject's, and
reads nothing.

## What bd provides, and where it stops

- `bd dep add` (`depAddCmd` in `cmd/bd/dep.go`) resolves its target with
  `resolveIDWithRouting`. When that fails and the two ids' prefixes differ, as
  `types.ExtractPrefix` reads them (the text up to the first hyphen, in
  `internal/types/id_generator.go`), it stores the target as given, without
  finding it, and exits 0. No flag of `dep add` refuses such a target.
- The edge holds nothing. `markDirectBlockingDependencySourceInTx`
  (`internal/storage/issueops/dependencies.go`) marks the waiting bead blocked
  only for a target that is an issue or a wisp of its own store, and returns
  for any other.
- `bd dep list` leaves the edge out of its listing and says so only on stderr
  (`warnDroppedDepEdges` in `cmd/bd/dep.go`).

## What Gas City provides, and where it stops

- `gc bd` passes bd's exit through (`cmd/gc/cmd_bd.go`), so a `dep add` onto
  another store's bead exits 0 there too.
- On a split city, one that keeps a storage class in its own binding,
  `judgeBdEdgeVerb` (`cmd/gc/bd_split_judges.go`) refuses an edge whose
  endpoint is not a bead of the city's work stores. It reads each endpoint in
  its own store (`bdReadEdgeEndpoints` in `cmd/gc/bd_inventory_trust.go`), so
  an edge between two rigs' work stores passes it, and it runs only on a split
  city.

Neither refuses the edge, so the pack's writers compare the prefixes
themselves. The check is what to delete once `bd dep add` or `gc bd` refuses a
`blocks` edge whose ends sit in two stores.
