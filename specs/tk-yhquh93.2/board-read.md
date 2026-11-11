---
name: The rig board's read, and where it departs from the Claude Design export
description: The record of unit 1 of the board's build (tk-yhquh93.2) - the read, its routes and cache, the generated types and the fixture - with each place the board departs from the operator's Claude Design export and why, and the bead that carries each part this build leaves out. Read it before changing what a board row says, or when the page and the export disagree.
---

# The rig board's read

The operator drew the board in their own Claude Design session, and on
2026-11-11, in conversation tk-w2hvygn, ruled on where that design meets the
store. Their rules for the build, quoted in the brief on tk-yhquh93.2:
"don't create new concepts to make this work", "one read, no way to allow it
to be inconsistent with other logic", "Use words that already exist vs
creating new concepts", and "the design should think of caching". This record
covers unit 1 of the build. Unit 2, the page, its actions and the old page's
removal, is tk-yhquh93.9.

## What was built

- **One read per rig** (`services/helm/internal/rigboard`). It gathers the
  rig's store through the gc command and asks each of the pack's shared
  readers once: `waits` for what holds a bead and whether it is in flight,
  and for which beads are a run's root or a step under one,
  `prstatus.Holding` for what a person owes through `blocks` edges,
  `prstatus.Read` for each open pull request, and `conversation` for a
  conversation's shape. `table.go` turns their answers into a row's group and
  signal, and `build.go` lays them out as one document: every row once, and the
  four pages as lists of row ids.
- **Two routes and a cache** (`services/helm/internal/server/rigboard.go`).
  `GET /helm/rigs` lists the rigs, and `GET /helm/rigs/{rig}` answers one rig's
  document with its read time beside it. Each answer is cached per rig for a
  minute, one gather at a time, and dropped when a write route succeeds. A
  gather of gc-toolkit took 5.5 s on 2026-11-11, 3.7 s of it the waits snapshot
  over 837 beads. A failed read answers 502 with the failure.
- **Generated types.** `services/helm/web/src/rigboard/document.gen.ts` is
  generated from the Go types by tygo, and a test fails when it is stale.
- **Real data.** `internal/rigboard/testdata/gc-toolkit.fixture.json` is the three
  epics the export was drawn from (tk-wmwcdlc, tk-ssm8qns, tk-yhquh93) and
  their graph, cut through the read's own gather, every string scanned against
  the city's other rigs, host paths, emails and the repository's accounts. The
  document the read builds from it is the golden beside it.
- **The search** for a Gas City read that would serve this is
  [gas-city-search.md](gas-city-search.md). No supervisor route carries a
  gate's await type, a deferred status or an epic's members.

## Where the board departs from the export

The export decides each state with a walk of its own: it follows `blocks` edges
to the end of every chain and ranks the ends (`db()` and `ORDER` in
board.dc.html). The board takes each state from the shared readers instead, so
where those readers answer differently, the board shows their answer.

| The export | The board | Why |
|---|---|---|
| A bead's group is the most blocking end of its chains, ranked you, gate, deferred, unscheduled, pull request, queued, in flight | The first matching row of one table over the readers' answers: closed, an ask, what `prstatus.Holding` names, a gate no person answers, deferred, in flight, queued, not scheduled | The operator's rule against a second rule. `Holding` is the pack's one walk, and it answers only what a person owes |
| "Waits on <id> +N" names the first blocker | "Waits on" names each wait behind the bead's status | `waits` returns them all, and naming each is the smallest form |
| Line 3 names the end of the chain, with words for its kind | Line 3 names what `Holding` returned first, the gates before the beads a person owes, as `prstatus.Reasons` orders them, and only on work whose wait ends on a person. Work nobody scheduled names each wait there instead | The brief's table rows 3 and 8 |
| In flight is work with an assignee other than the operator | In flight is `waits`' answer, the test in docs/steering.md: claimed, carrying a branch, a merge result or a rejection, or worked by a live run past load-context | The shared reader's answer |
| An open pull request is Queued | A pull request that reads needs-review or needs-attention is an ask, in those words, with what holds it beneath. One that reads working or merging is Queued as "Pull request #<n>" | The brief, and the pack's words for where a pull request stands |
| Queued is armed work | Queued is work that is armed, routed to a pool or assigned to an agent | The brief's row 7 |
| "Held by a gate" when the first blocker is a gate no person answers, and "held with its epic" on line 3 only when the epic itself has an open blocker | "Held by a gate" when any wait behind the bead's status is such a gate, its own or an ancestor's, with the gate's title | `waits` names an ancestor's waits for work that has not started, so a parked epic holds its unstarted work by the same answer |
| Deferred and not scheduled come from the bead's status and its arm | Deferred is the store's own status. Any other status that is neither open nor a claim reads as the store's word, and the Work queue lists it in the Deferred section | Gas City's bead routes fold every status into open, in_progress and closed, so the read takes the store's status from `gc bd list` |
| "Closed · merged", or the outcome | "Closed", with the bead's `gc.work_outcome` as stored (shipped, no-op) | A stored word, read as it is |
| Asks are human gates (Question), other gates (Event) and conversations | Asks are the brief's five kinds: Question (a human gate or a decision), Conversation (one that replies to no open human gate), Pull request, Routed to you, and Ruling (an epic whose members have all closed, or a landed Delivery, in the words docs/epics.md gives its row). A gate no person answers is never an ask | The brief. A conversation that replies to a gate no person answers is its own ask, since that gate is no ask |
| The header counts every human gate and conversation | The header counts the asks that hold or concern work under an epic, each once, so it reaches zero. Asks under no epic are listed last and not counted | The brief, and the operator's principle that a leading count must be able to reach zero |
| The Work queue lists the members of the captured epics | The Work queue lists every open piece of work in the rig that is not on the Product Owner's desk and does not wait on the operator directly | The brief |
| The Work queue's "Waiting behind other work" is one section | It has two parts, "Ends on you" and "The rest". A gate no person answers is drawn once in "Held by a gate", with the work it holds beneath | The brief. "The rest" is this build's label for the part the brief leaves unnamed |
| No section for a bead the export could not read | A last section, "Unread", lists work a reader could not answer | A failed read of one bead stays in sight rather than leaving the page |
| Work is every captured bead | Work is what `gc bd list` returns by default, less epics, conversations, decisions, the beads that carry `anchor_bead`, and a workflow run's own beads: its root, its steps and its input convoy | The brief, and this build's reading of the operator's ruling that the order workers take things "is a level of detail that a working system shouldn't have to expose". The learning loop's standing records stay in as the brief defines work, and tk-yhquh93.10 takes them out |
| One rig, with a count in the rig switch | One rig a page, the rig in the address, and the rig list as plain links | The brief: nothing rolls up across rigs |
| The data file carries each description, trimmed | The document carries no piece of work's description, and Details reads that one bead's text when it opens | The brief. Line 2 carries a gate's, a decision's and a conversation's whole message, less its first line when that line is the title |

## What this build leaves out

| Left out | The bead that carries it |
|---|---|
| The page, the Start, Rejoin and Discuss actions, and the old page's removal | tk-yhquh93.9 |
| A conversation's terminal on the page | tk-yhquh93.5 |
| Needs you rolled up across every rig | tk-yhquh93.6 |
| Work behind other work split by whether what is ahead is moving | tk-yhquh93.7 |
| A mark for work that started and has no live worker | tk-yhquh93.8 |
| The Product Owner's session on the Unprioritized page | tk-c9dcsbn |
| The command line's rows moving onto this read, and the old reader's retirement | tk-1tfzr71.24 |
| The learning loop's standing records out of the Work queue | tk-yhquh93.10 |

tk-yhquh93.4, listing every child of an epic on its page by title and state, is
folded into this build. The Epics page lists each epic's Deliveries and its
work at any depth by title and state, in the four groups. The closed work it
lists is what sits directly under an open epic or Delivery, the members the
read gathers closed.
