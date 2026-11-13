---
name: The rig board's Needs you count, by kind and less parked work (tk-yhquh93.14)
description: The design record of the build that made every Needs you view on the rig board count each need that counts, count the needs of each kind with each count a filter, and fold the needs about parked work or work held for the Product Owner beneath the rest. It records the rule as built, how the read tells a park, the calls the build settled and the live measure. Read it before changing what a Needs you view counts, the kinds it counts, or how the board tells a park.
---

# The Needs you count

The operator ruled the design in conversation tk-e2snvj8 on 2026-11-12: "Yes
as recommended is where we'll go", and on the parked rule, "Yes, build with the
parked rule as recommended." The bead holds the rest of their words and the
reading of the parked rule they approved. The board's two views are recorded in
[board-views.md](../tk-yhquh93.13/board-views.md).

## What was built

- **The count.** Every Needs you view counts the needs it lists that count,
  whether or not an epic holds them: the rig's page, whose count is the lead's
  number and the tab's, and each epic's and Delivery's, whose count is its
  heading's and its line's needs count. A count reads 0 only when nothing that
  counts needs the operator. The lead reads "N things are waiting on you", or
  "Nothing is waiting on you".
- **The kinds.** Each need carries its kind, the table's ask in its own words:
  Pull request, Question, Conversation waits for you, In conversation, Ruling
  and Routed to you. A Conversation's kind is its row's words, whether it waits
  in the operator's queue or a sitting holds it, and a question whose
  conversation a sitting holds is In conversation. Each view counts the needs
  of each kind that count, the first five always and Routed to you only when
  one counts. The page draws the counts beneath the lead, and beneath an epic's
  or a Delivery's Needs you heading. A count shows its kind alone, and a second
  click shows every kind again.
- **The parked rule.** A need does not count when what it is about is parked or
  waits for the Product Owner. It is parked itself when it, or an epic or
  Delivery above it, waits on a park. A gate, a decision or a conversation does
  not count when every bead it holds or is about is parked, is a need that does
  not count, or carries hold:mayor. A pull request or other work that is itself
  a need counts unless it is parked itself, whatever it holds, and a need about
  nothing else counts. An epic's and a Delivery's line counts only the needs
  that count.
- **The fold.** The needs that do not count are listed beneath the rest, under
  "Parked or unprioritized" with their own count, closed until opened, as closed
  work folds. Nothing changes what is parked.
- **One rule.** `view` and `kindCounts` in `internal/rigboard/build.go` give
  every view its counts, and each need carries its kind, so the all-rigs Needs
  you (tk-yhquh93.6) can sum each rig's views with no second rule.

## How the read tells a park

docs/steering.md said no reader tells a park from any other blocker. The rig
board's table already read one wait apart: a wait on a gate that is no human
gate, which its row 4 reads as "Held by a gate", the reading the Epics page
gives a parked epic. The text form of `gc-helm.sh park` files exactly such a
gate, one with no await type. So the build reads a park as that wait, through
the function row 4 calls (`gateHold`), and a row and the count read a gate one
way. It reads the waits `services/gctk/waits` answers for the need and for each
epic and Delivery above it. The bead asked the build to say where it must tell a
park, and why: the count has to leave parked work out, and this is the one wait
the readers answer that a park makes and other work does not.

What the reading leaves:

- A park made with `--waiting-on` onto a task or a human gate reads as the wait
  it is, since nothing on the edge says it is a park. On a human gate the
  question is a need of its own.
- A gate of a type bd closes by itself, a timer, a GitHub run or pull request,
  or a bead, reads as a park too. No such gate was open in any of the city's
  stores at 2026-11-13T02:28Z ([gas-city-search.md](gas-city-search.md)).
- Work in flight under a parked epic is parked with it, because the build reads
  the epic's own waits. waits does not hold work in flight by its parent's wait,
  so a pull request under a parked epic still lands, and its review stops
  counting until the park lifts.
- A parent that is no epic or Delivery parks a need only as waits answers the
  need itself, which it does for work that has not started.

## The calls this build settled

| The question | The call | Why |
|---|---|---|
| What a need holds or is about | Every bead whose `prstatus.Holding` answer names it, whatever its kind and work held for the Product Owner included, and the bead its conversation tracks, the need's own or its question's conversation's | The rule weighs every bead a need holds. The board's list beneath a need draws only its work, epics and Deliveries, less hold:mayor work, so a question holding only a parked decision lists nothing and still folds |
| A need that holds or is about a need which does not count | It weighs that need as it weighs a parked bead, so a question holding a decision about nothing but parked work leaves the count with the decision | The approved reading names parked beads and hold:mayor work, and such a decision is neither. Weighed as live, it would keep its question counting for work that is parked, where the operator ruled that "A parked epic shouldn't surface what it needs". This call is the build's reading of that ruling |
| A need about a bead the read did not gather, such as a conversation about a bead in another store | It counts | The read cannot tell that bead is parked or held, so the need stays in the count |
| A question whose conversation waits in the operator's queue | Question, and its row reads "Conversation waits for you" as before | The bead's item 3 makes a question In conversation when a sitting holds its conversation, "since the operator's attention is already on it". A conversation not yet started holds no one's attention |
| The words beside each kind's count | "pull requests", "questions", "conversations waiting for you", "in conversation", "rulings", "routed to you", each in the singular for one | The bead's names for the kinds, lower-cased beside a number as an epic's line reads its counts |
| The fold's heading | "Parked or unprioritized" | The words of the operator's ruling, "A parked epic" and "unprioritized work", and the Unprioritized page's name for work carrying hold:mayor |
| A kind with no need that counts | Its zero is text, not a control, as an epic's line draws a zero. A kind shown alone stays a control after its count falls to zero, so the view can show every kind again | A click on an empty kind would show an empty list |
| What a kind shown alone filters | Both lists of the view, the counted and the folded | "Clicking a kind shows only the needs of that kind" |
| How long a kind stays shown alone | Per view, while the page is open, as each view's folds are | The page keeps its view state no longer |
| When an epic's or a Delivery's Needs you is drawn | While it lists any need, counted or not, with its heading's count the needs that count. A Delivery folds by default only when it lists no need at all and its work has closed | A folded need is still listed |

## The live measure

Read through the branch from every rig's store at 2026-11-13T02:20Z, about ten
hours after the bead's measure, so the stores had moved.

- gc-toolkit listed 32 needs and counted 31: 6 pull requests, 21 questions, 1
  conversation waiting for you, 2 in conversation and 1 ruling. tk-ht9m4vu
  folded, the gate the bead named. Its only work, tk-hok6w, waits on the
  question and on the park gate tk-u5t8h6x and carried no label at the read.
  The bead describes that work as carrying hold:mayor, and either takes the gate
  out of the count. No epic of gc-toolkit folded a need.
- One other rig went from 20 to 15, as the bead measured: four decisions wait on
  a park themselves, and a gate is about parked or held work.
- Another went from 8 to 7: a parked epic asks for a ruling.
- The other four folded nothing.

The committed fixture parks nothing a need is about, so its document folds no
need, and the page tests fold one by editing a copy of it. A document that shows
the fold on gc-toolkit's live data is the branch's read of the store, which
`helm-fixture --rig-board <file>` serves to the page.

## What this build leaves out

| Left out | The bead that carries it |
|---|---|
| What counts as a need at all | tk-99h9ijx |
| Needs you rolled up across every rig | tk-yhquh93.6 |
| The board's direct store reader | tk-1tfzr71.24 |
| The contract's parity check | tk-1tfzr71.25 |
