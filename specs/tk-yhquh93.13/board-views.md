---
name: The rig board's two views, Needs you and the Work queue (tk-yhquh93.13)
description: The design record of the build that laid the rig board out as two views, Needs you and the Work queue, shown for each epic and each Delivery on the Epics tab and across the rig on their own tabs. It records how the work is ordered, the calls the build settled, where it goes beyond the bead's calls, and the bead that carries each part it leaves out. Read it before changing how the board orders work, lists needs or draws an object.
---

# The rig board's two views

The operator adopted the target in conversation tk-4z7cs9x on 2026-11-12: "we
have 2 conceptual views, Needs you and Work Queue, how they sort, rerpresent
data, etc. is consistent. And the Epics tab is a grouping of those views and the
individual tabs are holistic, not grouped by Epic views of that data." The bead
holds their other words and the five calls the sitting proposed with the target.
The page and the read it lays out are units 1 and 2 of the board's build,
recorded in [board-read.md](../tk-yhquh93.2/board-read.md) and
[board-page.md](../tk-yhquh93.9/board-page.md). This record states what the two
views are.

## What was built

- **The order** (`services/gctk/queue`). The rig's open work is placed once, in
  the order it is expected to land. bd graph's execution layers put what can go
  now first: a bead with nothing ahead of it is in layer 0, and a bead that waits
  on others sits one layer past the latest of them. Within a layer the order is
  the pool's claim order, priority, then oldest, then id. Work nobody has
  scheduled comes after the queue, and so does work that waits on it. Whether
  work is scheduled is the board's existing test, armed, routed or assigned, or
  in flight, now held once in `queue.Scheduled`, and a bead that one of Gas
  City's hold labels holds is not scheduled unless it is in flight. The search
  behind these rules is [gas-city-search.md](gas-city-search.md).
- **The document.** Each epic and each Delivery carries its Needs you, its Work
  queue and its closed work, over the rows it holds nearest. The Needs you page
  carries every need in the rig, and the Work queue page every open piece of
  work that does not carry hold:mayor. A need's entry lists the beads it holds
  through any chain of waits, as `prstatus.Holding` answers it, in the Work
  queue's order, less work held for the Product Owner. A container's counts
  lead with its needs, then its queue, the work nobody scheduled, and its closed
  work, at any depth beneath it.
- **The words of a bead behind a person's move.** A bead whose own wait is
  another bead's pull request reads "Waits on" that bead, and never that bead's
  words. One whose own wait is a decision reads "Waits on your answer", as one
  waiting on a question does.
- **One rendering.** A need is tinted and tagged with its kind wherever it
  appears, and its line 3 says how many beads it holds up and, for a pull
  request, what holds it. Only a Needs you view nests rows, the beads a need
  holds beneath it, so a bead on a Work queue nests nothing.
- **The fixture**, cut again with tk-1tfzr71 among its epics, so the tests and a
  demo capture show the epic the target was adopted on.

## The calls this build settled

The bead left these to the build.

| The question | The call | Why |
|---|---|---|
| How a Delivery's two views sit beside its epic's | Each container's views cover the rows it holds nearest. An epic's Deliveries come first, each with its own views, and then "The rest of the epic" with the epic's own. An epic with no Delivery shows its views directly | The bead's own answer, "as groupsOf does today", and the layout the page already had |
| What the epic's line counts | It leads with the needs that hold or concern the epic or anything beneath it, each once, then the work in the queue, the work nobody scheduled and the closed work, at any depth. Each count opens its part and folds the others, and the work nobody scheduled opens at the foot of its Work queue, below the queue | The bead's answer. The needs count reaches zero as the operator acts, and a need held in a Delivery holds up its epic too |
| Whether the Needs you tab keeps its split by conversation | It drops the split, with the grouping by epic. One list in need order, and a need's row says whether a conversation answers it ("Question", "Conversation waits for you", "In conversation") | The tab shows the same view as an epic's Needs you, and the operator's words for the two views are "how they sort, rerpresent data, etc. is consistent" |
| Where a need that holds no queued work sorts | After every need that holds queued work, by the first unscheduled work it holds, and a need that holds no work at all comes last, by priority, then oldest, then id | Its place in the queue is what orders a need, and one that holds up nothing in the queue holds up nothing the city will take |
| Whether layers show beyond the order | No. The order carries them, and each row's signal names what it waits on | A layer number would be a concept the page does not have. The operator's rule for the build, quoted in [board-read.md](../tk-yhquh93.2/board-read.md), is "don't create new concepts to make this work", and applying it to layers is this build's reading |
| What stays | Closed work folds per container behind its toggle, and hold:mayor work stays on the Unprioritized tab, out of the queue | The bead |

The Needs you tab keeps its lead count, the needs that hold or concern work
under an epic, so the count can reach zero. Its list holds the needs under no
epic too, in their place in the order, uncounted.

## Where the build goes beyond the bead's calls

| The bead's call | The board | Why |
|---|---|---|
| Work nobody has scheduled comes after the queue | Work that waits on such work, at any depth, comes after the queue with it, under Not scheduled, and its row names what it waits on | Nothing sits above what it waits on, and the city takes none of it until someone routes the work ahead of it |
| What can go now comes first, by bd's execution layers | A status bd's ready set does not admit, such as deferred, keeps a bead out of layer 0 though no wait is ahead of it. A wait on a bead that is no queued work, such as a question, counts as one on a bead in layer 0 | bd ready admits open and in_progress beads alone, and bd graph places a bead with no dependencies in layer 0 |
| (none) | A review or a rework anchored to a bead puts nothing ahead of it, so a pull request whose own rework is pending sits in layer 0 | The anchor's row speaks for its reviews and reworks, so their work is the anchor's own |
| A bead that waits on another bead's pull request says "Waits on <that bead>" | Also a bead that waits on a decision reads "Waits on your answer" | A decision is a question, and a bead waiting on one owes no words of the decision's own either |
| A need is drawn as one on every page | A need's line 3 counts the beads it holds up wherever it is drawn, across the rig | One rendering. Under an epic the count can exceed the beads listed beneath it, which are the epic's alone |
| (none) | A bead on a Work queue nests nothing, and the asks no longer nest under work. "Held by a gate" is a row's signal, with the gate's title, and the gate is no longer drawn above the work it holds | The Needs you view beside each Work queue lists what holds each bead, and the queue is one list with no sections |
| hold:mayor work stays on the Unprioritized tab, out of the queue | It is out of every epic's and Delivery's views and counts too, where the Epics page listed it under its epic before, and no need lists it beneath it on any page. A need that holds such work, or a conversation about it, reaches an epic's views and counts only through other work. In the fixture, the Board UI epic (tk-yhquh93) lists three of its seven open beads, and its four units that carry hold:mayor (tk-yhquh93.5 to .8) are on the Unprioritized tab alone | An epic's views are the Work queue's and the Needs you tab's, grouped by epic, and neither lists hold:mayor work, which the city takes none of until the Product Owner places it. Reaching the epics' views and a need's list is this build's reading of the bead's call |
| (none) | Work that carries hold:mayor is placed with the rest before the views leave it out, so the work behind it comes after the queue, under Not scheduled. A bead that hold:mayor or hold:external holds is not scheduled, whatever routes, arms or assigns it, unless it is in flight | Gas City serves a held bead to no worker, and the deferred-dispatch pass slings no armed bead while a hold label holds it, so the work behind it waits for the hold to lift |
| (none) | A Delivery that is itself a need, such as one that landed and waits for its ruling, is listed in its epic's Needs you, and its band is drawn below with its own views | The need row is the need, listed as the epic's other needs are, and the band is the container |

## The live board

Read from gc-toolkit's store at 2026-11-12T04:18Z, before the build landed.

- tk-1tfzr71's Needs you listed question tk-q4dd6mk, holding tk-1tfzr71.39, then
  question tk-ucjq40f, holding twelve of the epic's beads with tk-1tfzr71.60
  first. Its Work queue started with tk-1tfzr71.66, the bead of PR #1459, in
  layer 0, since its only wait was its own pending rework. Then came
  tk-1tfzr71.39, .60 and .67 in layer 1. It held 21 beads in the queue and 2 that
  nobody scheduled.
- PR #1459 read "working" then, so it was no need. Of the three beads behind it,
  tk-1tfzr71.67 read "Waits on tk-1tfzr71.66" and .68 "Waits on tk-1tfzr71.67,
  tk-1tfzr71.66", by row 7, and .20 read "In flight". Once the pull request
  waits on a review again, row 3 names it the same way.
- Across the rig, Needs you listed 30 needs and counted 7, and the Work queue
  held 178 beads in the queue and 278 that nobody scheduled.

## What this build leaves out

| Left out | The bead that carries it |
|---|---|
| Words on each Work queue row saying whether what is ahead is moving | tk-yhquh93.7 |
| Needs you rolled up across every rig | tk-yhquh93.6 |
| A conversation's terminal on the page | tk-yhquh93.5 |
| A mark for work that started and has no live worker | tk-yhquh93.8 |
| The learning loop's standing records off the board | tk-yhquh93.10 |
| The command line's rows moving onto this read | tk-1tfzr71.24 |
| The contract's parity check: `contract.ts`, its two fixtures and `contract_parity_test.go` | tk-1tfzr71.25 |
