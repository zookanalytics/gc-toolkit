---
name: attribution of the tk issues-table SELECT load, and the gc-toolkit vs gascity split
description: What drives the full-row SELECT load on the tk Dolt store, why the Helm board is a bounded contributor rather than the dominant driver, and which part of the remedy is gc-toolkit's and which is gascity's.
---

# What drives the full-row SELECT load on the tk store

The finding records a `dolt sql-server` saturated across its threads while
many clients run full-row `SELECT`s against the tk issues table, with a
concurrent backup sync overlapping the peak. "Full-row" is the beads library's
default projection: a non-lite read returns all issue columns, including the
six heavy TEXT columns the library groups as its heavy-drop set — `description`,
`design`, `acceptance_criteria`, `notes`, `waiters`, `payload`. Every reader on
the non-lite path pays that width per row.

## The Helm board is one bounded client

`services/helm/internal/server` caches the computed board for a TTL
(`GC_HELM_CACHE_TTL`, default 45s) and coalesces concurrent cache misses through
a `singleflight` group, so a burst of board requests drives one gather, not one
per request. A gather reads each rig's store sequentially; per rig it runs a
fixed batch of `SearchIssues` at open and at closed status, a count set by the
anchor kinds rather than by how many anchors exist. So Helm is a single process
reading on a bounded cadence — not the "many clients" the finding names.

## The dominant driver is poll volume on the shared binary

The many clients running full-row reads against tk are the agent and patrol
poll loops — `gc hook`, `bd list`, `bd ready` — across the rig's sessions. Their
cadence and their query shape live in the `gc`/`bd` binary, which is the gascity
rig, not gc-toolkit. The per-query heavy-column width is the same library
default every one of them inherits.

## The gc-toolkit slice: read lite where no heavy column is read

The board renders none of the six heavy columns. The only one it reads at all is
`description`, and only in `crossRigRefs`, which scans an open anchor's prose for
other-rig bead ids and adds them to the anchor's weight. So Helm's gather asks
for the lite projection on every read that does not need `description`:

- The closed/DONE pass. `rankScore` orders a `SevDone` row by recency and
  discards its weight, so the cross-rig scan cannot move a closed row; no other
  reader of a closed anchor reads a heavy column. The DONE tile's `cross_rig_refs`
  is empty, which is already its derived value.
- The edge hydration. A hydrated far end becomes a `board.Child` or
  `board.Blocker`, and neither carries a heavy column.

The live anchor pass stays full, because `crossRigRefs` weighs an open anchor by
its `description`. The lite projection keeps `metadata`, and labels hydrate
regardless, so convoy ownership and every tile's metadata are unaffected.

## What stays with gascity

Filed for gascity as `gc-x4ekd` in the gascity store:

- The poll volume against tk, and the non-lite default on the hot read paths
  (`gc hook`, `bd list`, `bd ready`): both are the shared binary's cadence and
  projection.
- Cutting the live pass further. Helm's live pass still reads five heavy columns
  it never uses, because the library's lite lever is all-or-nothing and Helm
  needs `description`. A projection that keeps `description` while dropping the
  other five is a library change Helm cannot make from here.
