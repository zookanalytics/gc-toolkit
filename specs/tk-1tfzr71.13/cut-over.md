---
name: Cut-over of the beads the retired successor keys describe
description: What tk-1tfzr71.13's backfill wrote on 2026-11-06, giving every closed bead that named its successor in gc.superseded_by bd's own duplicates or supersedes edge, the beads it left alone and why, the live beads still parked under the retired keys, and the follow-up that finishes the cut-over once the change lands. Read it when a closed bead names no successor through an edge, or before re-running the backfill.
---

# Cut-over of the beads the retired successor keys describe

The readers of a disposition read bd's `duplicates` and `supersedes` edges
([gas-city-search.md](gas-city-search.md)). A bead disposed before the edges
named its successor only in the retired `gc.superseded_by` key. Without an edge
of its own, `doctor/check-closed-implies-landed` (I5) would read such a closed
anchor as one that left the merge queue without landing, and
`doctor/check-epic-closed-implies-ruled` (I15) would read such an epic as closed
without a ruling.

## What the backfill wrote

[backfill.sh](backfill.sh) ran as a dry run that finished at 2026-11-06T23:53Z,
then with `--apply` from 23:54Z to 00:07Z on 2026-11-07. It read every rig `gc rig list` names.
The two suspended rigs' stores answered through the city's shared Dolt server,
and no other Dolt server started. For each closed bead carrying the key, it
wrote `duplicates` when the close reason or a note said "duplicate of" the bead
the key names, and `supersedes` otherwise. It read each edge back.

| Store | Carry the key | Written | After dropping a blocks edge | Not closed | Left alone | Failed |
|---|---:|---:|---:|---:|---:|---:|
| loomington | 93 | 90 | 1 | 1 | 1 | 0 |
| gc-toolkit | 814 | 705 | 0 | 1 | 107 | 1 |
| signal-loom (suspended) | 44 | 36 | 1 | 0 | 7 | 0 |
| gascity | 82 | 81 | 0 | 0 | 1 | 0 |
| shutupandlisten (suspended) | 19 | 18 | 0 | 0 | 1 | 0 |
| sprintshow | 5 | 4 | 0 | 0 | 1 | 0 |
| growth-factor | 72 | 50 | 0 | 0 | 22 | 0 |

Of the 986 edges written, 271 are `duplicates` and 715 are `supersedes`. The two
blocks edges it dropped were waits from a closed bead onto its own successor
(lx-trgcl6 onto tk-tashy2, sl-wdy7 onto sl-qddz). The disposition had ended
those waits, and bd keeps one edge per pair of beads.

The one failure is tk-t88hg, a closed rework child whose key names `763e282`, a
commit rather than a bead. bd refuses an edge onto an id that is no bead, and
the close reason already records what superseded it. It carries no
`merge_result`, so I5 does not judge it.

## What it left alone

140 closed beads keep only the key, because the pair of beads already carries
another edge, which bd would have to drop to record the disposition:

| Edge on the pair | Beads | Stores |
|---|---:|---|
| `tracks` | 71 | gc-toolkit 64, signal-loom 5, gascity 1, loomington 1 |
| `until` | 62 | gc-toolkit 39, growth-factor 22, sprintshow 1 |
| `related` | 6 | gc-toolkit 3, signal-loom 2, shutupandlisten 1 |
| `relates-to` | 1 | gc-toolkit 1 |

The backfill's dry run names each of them. Neither check that judges a closed
bead by its disposition needs them. Run from this change's branch after the
backfill, I5 and I15 passed on every live store. I5 judged 57 closed anchors in
gc-toolkit, 16 in gascity and 6 in growth-factor as disposed through their
edges, and I15 judged 5 epics in gc-toolkit that way.

## What is still parked

Two beads that are not closed carry `gc.superseded_by`: lx-0kl2y, naming
tk-9749w9, and tk-s5caebf, naming tk-hl17x4i. Ten open beads in the gc-toolkit
store carry `duplicate_of`. Eight name tk-8akayez, tk-gro371a names
tk-1tfzr71.44, and tk-s5caebf is the tenth. The backfill writes nothing on a
bead that is not closed, because each is a disposition whose close never
landed. Until this change lands, main's writer keeps stamping the key, so a
bead disposed in between carries the key and no edge.

tk-1tfzr71.53 finishes the cut-over once this change lands. It waits on
tk-1tfzr71.13 by a blocks edge and is armed to dispatch when that closes. It
re-runs the backfill and closes the parked beads through `bead-rehome.sh`.
