---
name: Cut-over of the beads the retired successor keys describe
description: What tk-1tfzr71.13's backfill wrote on 2026-11-06 and 2026-11-07, and its re-run on 2026-11-08 once the change was live, giving every closed bead that named its successor in gc.superseded_by bd's own duplicates or supersedes edge, the edges it replaced and the call behind each type, the beads it left alone and why, what became of the live beads parked under the retired keys, and the closed beads that name their canonical only in duplicate_of. Read it when a closed bead names no successor through an edge, when one has lost a tracks, until or related edge, or before re-running the backfill.
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
then with `--apply` from 23:54Z to 00:07Z on 2026-11-07. It read the city store
and every rig `gc rig list` names. Rigs other than gc-toolkit are lettered here.
The two suspended rigs' stores answered through the city's shared Dolt server,
and no other Dolt server started. For each closed bead carrying the key, it
wrote `duplicates` when the close reason or a note said "duplicate of" the bead
the key names, and `supersedes` otherwise. It read each edge back.

| Store | Carry the key | Written | After dropping a blocks edge | Not closed | Left alone | Failed |
|---|---:|---:|---:|---:|---:|---:|
| the city store | 93 | 90 | 1 | 1 | 1 | 0 |
| gc-toolkit | 814 | 705 | 0 | 1 | 107 | 1 |
| rig A (suspended) | 44 | 36 | 1 | 0 | 7 | 0 |
| rig B | 82 | 81 | 0 | 0 | 1 | 0 |
| rig C (suspended) | 19 | 18 | 0 | 0 | 1 | 0 |
| rig D | 5 | 4 | 0 | 0 | 1 | 0 |
| rig E | 72 | 50 | 0 | 0 | 22 | 0 |

Of the 986 edges written, 271 are `duplicates` and 715 are `supersedes`. The two
blocks edges it dropped were waits from a closed bead onto its own successor:
a bead of the city store onto tk-tashy2, and a pair of beads inside rig A. The disposition had ended
those waits, and bd keeps one edge per pair of beads.

The one failure is tk-t88hg, a closed rework child whose key names `763e282`, a
commit rather than a bead. bd refuses an edge onto an id that is no bead, and
the close reason already records what superseded it. It carries no
`merge_result`, so I5 does not judge it.

## The edges it replaced

That pass left 140 closed beads with only the key, because the pair of beads
already carried another edge and bd keeps one edge per pair. Once the key's
readers go, the resolver, the finding chain and the tracker chain can follow
those beads only through an edge. So a second pass, from 05:16Z to 05:23Z on
2026-11-07, replaced the edge on 138 of them, 4 with `duplicates` and 134 with
`supersedes`. It read each back, and a note on each bead names the edge it
replaced and how to put it back.

Each type was a call, made on what still reads it on a closed bead:

| Edge on the pair | Beads | Stores | What reads it on a closed bead | Call |
|---|---:|---|---|---|
| `until` | 62 | gc-toolkit 39, rig E 22, rig D 1 | Nothing acts on it since its auto-close went. `bead-context.sh` lists it for a person. | Replaced |
| `related` | 6 | gc-toolkit 3, rig A 2, rig C 1 | It is the membership edge of an anchor's child, and `bd_anchor_children` reads an untyped `dep list`, so the replacing edge keeps a child a member. `bead-context.sh` lists it for a person. | Replaced |
| `relates-to` | 1 | gc-toolkit 1 | `bead-context.sh` lists it for a person. | Replaced |
| `tracks`, on a visit or a bug | 69 | gc-toolkit 62, rig A 5, rig B 1, the city store 1 | Its readers read live beads or convoys: `bead_conversations` and the reaction dedup in `gc-proactive.sh` skip a closed tracker, `liveness-classify.sh` reads live beads, and `run-lib.sh` reads convoys. The board's closed conversations need a conversation's assignee, which no such bead carries, and a close inside its recent window. `patrol-finding.sh` writes the edge as advisory. `bead-context.sh` lists it for a person. | Replaced |
| `tracks`, on an input convoy | 2 | gc-toolkit 2 | It is what makes the bead a convoy, for `run-lib.sh`, `claim-context.sh` and Gas City's `internal/convoy`. | Left alone |

Of the 138, the successor of 4 was open, so those are the beads whose readers
would have lost a live bead: tk-zubfr1y, tk-196gnu and two in rig A. Run from this
change's branch, `gc-helm.sh resolve` reaches the successor of all four. The
backfill's dry run, re-run after the pass, finds nothing to write but tk-t88hg, so
every other closed bead carrying the key names through an edge the bead its key
names.

The same pass wrote 2 edges with no edge to replace, in rig E, on beads disposed
after the first pass, while main's old writer still stamped the key. Its counts by store:
the city store 1, gc-toolkit 105, rig A 7, rig B 1, rig C 1, rig D 1, rig E 22.

## What it left alone

The two input convoys, tk-04uqk and tk-43hnoq, keep only the key. Each key repeats
the one bead the convoy tracks, each convoy and each run poured over it is closed,
and nothing follows a closed input convoy to a successor.

Run from this change's branch after both passes, I5 and I15 passed on every live
store. I5 judged 57 closed anchors in gc-toolkit, 16 in rig B and 6 in rig E as
disposed through their edges, and I15 judged 5 epics in gc-toolkit that way.

## The re-run once the change was live

The change landed on main at 2026-11-08T05:58Z, and the rig checkout ran it from
06:04Z. Until then every rig ran main's old writer, which stamped the key and
wrote no edge. tk-1tfzr71.53 then ran the backfill from the rig checkout, as a
dry run at 06:05Z and with `--apply` at 06:06Z.

| Store | Carry the key | Written | Already recorded | Not closed | Left alone | Failed |
|---|---:|---:|---:|---:|---:|---:|
| the city store | 93 | 0 | 92 | 1 | 0 | 0 |
| gc-toolkit | 820 | 6 | 810 | 1 | 2 | 1 |
| rig A (suspended) | 44 | 0 | 44 | 0 | 0 | 0 |
| rig B | 82 | 0 | 82 | 0 | 0 | 0 |
| rig C (suspended) | 19 | 0 | 19 | 0 | 0 | 0 |
| rig D | 5 | 0 | 5 | 0 | 0 | 0 |
| rig E | 75 | 1 | 74 | 0 | 0 | 0 |

No pair needed an edge dropped or replaced. Of the 7 edges written, 1 is
`duplicates` and 6 are `supersedes`, and each read back. They are the beads main's
old writer disposed between the second pass and the checkout's sync. The duplicate
sweep closed tk-gro371a at 2026-11-07T05:39Z as a duplicate of tk-1tfzr71.44.
tk-h2s7hj.3, tk-h2s7hj.4, tk-hf7nadf, tk-jvhkjy and tk-q1rsu4 closed as not
needed or folded between 05:50Z and 06:01Z on 2026-11-08, and one bead in rig E
closed as not needed on 2026-11-07. Each close reason names the kind its edge
took. The failure is tk-t88hg again, and the two left alone are the input
convoys.

Once the parked beads below were settled, a dry run at 06:21Z found nothing to
write but tk-t88hg's refused edge. `doctor/check-state-space` then found no live
bead carrying a retired key in any store it reads. The same listing, run on the
two suspended rigs' stores, which the check skips, found none there either. I5
and I15 passed on every live store, and I5 judged 7 closed anchors in rig E as
disposed through their edges.

## The beads that were parked

Eight open doctor findings in the gc-toolkit store named tk-8akayez in
`duplicate_of`: tk-f1ouz56, tk-cbwm0e8, tk-u71sytl, tk-nn62zvy, tk-qcvfkqt,
tk-n334ypp, tk-j0315fe and tk-osdwdw. tk-8akayez is the open bug that carries
the doctor-timeout family, checks that overran their fixed 60-second budget,
most of them at host-load peaks. Each finding was held on it because that
overrun was its own cause. Each closed on 2026-11-08 through
`bead-rehome.sh --kind duplicate`, with a note saying why it is the same work.
Each close replaced the finding's blocks edge onto tk-8akayez with the
`duplicates` edge, and no open bead waited on any of them, so no wait moved.
Three of them had later recorded a different situation under the same key: I2
violations, a PR with more than one open anchor under I4, and an order failing
repeatedly. Run at 06:08Z, I4 and the order check passed,
and I2 reported only the retired keys on the parked beads this section settles.
A recurrence after a close files a new bead that names the closed one
(`patrol-finding.sh`), so closing a held finding loses no later report.

tk-s5caebf named tk-hl17x4i in both keys. Its fix landed with PR #1203, which
closed tk-hl17x4i on 2026-10-13. Its blocks edge onto the operator's park gate,
tk-u5t8h6x, is what kept the duplicate sweep from closing it, and
`bead-rehome.sh` refuses a close that a live blocker holds, so it stays parked.
Its keys are cleared. A close brief names the fix and what to check, and an arm
sends the bead to the validating closer (`mol-validate-close`) once the operator
releases it from the park.

The city-store bead is mechanik's session bead, the record of an always-on
named session. tk-9749w9, a merged bug, carries `gc.supersedes` naming it, so a
disposition once named the session bead as its origin. No close is owed on a
live session, so its keys are cleared and it stays open. The back-pointer on
tk-9749w9 stays, because `gc.supersedes` is inert on every bead.

## Closed beads that name their canonical only in duplicate_of

The backfill reads the two `superseded_by` keys. Some closed beads carry
`duplicate_of` alone, with no `duplicates` or `supersedes` edge onto the bead it
names: 51 in gc-toolkit, 63 in rig A and 5 in rig B. Of gc-toolkit's, 32 keep a
`blocks` edge onto that bead, which holds nothing once the bead waiting on it is
closed. Before the edges, two scripts read `duplicate_of`. The duplicate sweep
read it to close a live duplicate, and on a closed rework child to keep a
disposed sibling from counting as the one that landed, and this change deleted
the sweep. `pr-stack.sh` also read it on a closed row, to keep a closed duplicate
out of a PR's ledger, which gathers rows by branch, and it reads the `duplicates`
edge there now. On 2026-11-08 no open PR in gc-toolkit, rig A or rig B was on a
branch any of these beads carries. Each that carries one either records a no-op
outcome, which keeps it out of a ledger anyway, or names a branch whose bead has
closed. So nothing acts on these beads, and they are left alone.
