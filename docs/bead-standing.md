---
name: Where a bead stands and whose move it is
description: Read it when a bead on the helm board, or in an agent's report about it, reads Waiting on you, Queued or Not moving, or names what you owe on it, and you want to know what the word means, whose move it is, and what you can do.
---

# Where a bead stands and whose move it is

Each bead the city tracks stands somewhere: you owe its next move, the city
moves it, or nothing moves it as things stand. The helm board's rig page shows
this as the group each row sits in, and as the words on the row. Agents give
you the same answer when they report on a bead, such as the Product Owner's
epic snapshot or a sitting's preparation, because one rule answers for all of
them. That rule is the `standing` package in gctk, and `gctk bead stands`
prints its answer for the beads you name.

This page explains the words: each group, and each ask, which is the kind of
thing you owe when a bead is itself what waits on you.

## Scope

**Mandate.** What a person reading the board, or an agent's report about a
bead, sees of where the bead stands: each group and each ask, what it means,
whose move it is, and what you can do.

**Boundaries.** The rule that places a bead, part by part in the order the
parts are tried, is
[gctk-architecture.md](gctk-architecture.md#the-bead-stands-contract). A pull
request's own status words are
[pull-request-states.md](pull-request-states.md). How the board draws, orders
and counts its rows is the
[helm README](../services/helm/README.md#the-rig-board-get-mounthelmrigsrig).

## The groups

| The board shows | `gctk bead stands` prints | What it means | What you can do |
|---|---|---|---|
| Waiting on you | `waiting-on-you` | You owe the bead's next move. Either the bead is itself an ask, [below](#the-asks), or a question or a bead only you can clear holds it, through one of its own waits or further along them. The row reads the ask, "Waits on your answer", or "Waits on" and the beads it waits on. | Act on the ask, or on what holds the bead, which the row names. |
| Queued | `queued` | The city moves it as things stand. It is work in flight, and the row reads "In flight", or "Pull request #n" with that pull request's status. It is work a pool or an agent takes, and the row reads "Queued", or "Waits on" the work ahead of it. Or it is a conversation whose sitting waits for the work it sent, or a decision your ruling left waiting on the work it sent, and it is yours again once that work closes. | Nothing. |
| Not moving | `not-moving` | Nothing moves it as things stand. A park holds it, and the row reads "Held by a gate". Its status is one no pool takes, such as "Deferred". Or it is work nothing sends: no pool, agent, arm or live run takes it, or a hold keeps it from dispatch, and the row reads "Not scheduled". | Decide whether it should move. You can release its park ([steering.md](steering.md#releasing-a-park)), set its status back to open, or send the work to a pool or an agent. |
| Closed | `closed` | The bead is closed. | Nothing. |

Some beads sit in no group, because they have no move of their own. A
conversation that answers a question is carried on the question's row. An epic
or a Delivery with open members moves as its members do, and one with no
members has nothing to move yet. A gate that asks no one, such as a park, holds
the beads that wait on it. A bead the board could not read reads "unread", in
no group.

## The asks

A bead that waits on you is often itself what you owe: an ask. It reads under
Waiting on you, and the board's Needs you view counts it by its kind.

| The board shows | `gctk bead stands` prints | What it means | What you can do |
|---|---|---|---|
| Question | `question` | A question the city asked you, or a decision that waits on your ruling. A decision your ruling left waiting on the work it sent is not a question again until that work closes. When a conversation answers the question, the row reads that conversation's words. | Answer it. Start the conversation from its row, or rejoin the one that answers it. |
| Conversation waits for you, or In conversation | `conversation` | An open conversation. It waits in your queue for you to take it up, or a sitting holds it with you. A conversation that answers a question reads on the question's row instead. One whose sitting waits for the work it sent is not an ask until that work closes. | Rejoin the conversation from its row. |
| Pull request, with its status | `pull-request` | The bead's pull request reads `needs-review`, so it waits for your review, or `needs-attention`, so something only you can clear stops it. | Review it, or clear what stops it, as [pull-request-states.md](pull-request-states.md#the-labels-on-a-pull-request) says. |
| Routed to you | `routed-to-you` | Any other bead only you can clear, such as a task in your queue, one assigned to `human`. | Act on it, or open a conversation about it with Discuss, in the row's Details. |
| Needs a ruling, or landed — waits for its Epic Checkpoint | `ruling` | An epic whose members have all closed, or a Delivery whose Stories have all closed. Each waits for your review of the epic. | Call the epic's review ([epics.md](epics.md#reviewing-an-epic)). Discuss, in the row's Details, opens a conversation about it. |

Work held for the Product Owner, which carries `hold:mayor`, asks nothing of
you, whatever it would ask, such as a review of its pull request. It waits for
you and the Product Owner to place it
([steering.md](steering.md#the-queue-the-po-works)).

## Where a bead's words meet its pull request's

A pull request has a status of its own, one of four words, which its
`status:` label and the board show
([pull-request-states.md](pull-request-states.md#the-labels-on-a-pull-request)).
A bead whose pull request reads `needs-review` or `needs-attention` is itself
the ask, `pull-request`, so it reads under Waiting on you, and its row shows
that status. A bead whose pull request reads `working` or `merging` is work in
flight, so it reads under Queued as "Pull request #n" with that status, unless
a park holds it.

## Where the words are defined

- `services/gctk/standing` declares each group, ask and rule, and each kind of
  bead the rules tell apart, with its meaning beside it, in `rules.go`. Its
  `advance.go` declares how far the city carries a bead: `ready`, `advancing`
  or `stuck`, the words `bead-context.sh` prints, which
  [bead-store-resolution.md](bead-store-resolution.md#reading-a-beads-whole-context)
  explains.
- `gctk bead stands <bead>...` prints the answer for each bead named, and its
  help gives the output's fields.
- The board's own words for each group and each ask are in
  `services/helm/internal/rigboard/table.go`.
- The rule that places a bead, part by part in the order the parts are tried,
  is [gctk-architecture.md](gctk-architecture.md#the-bead-stands-contract).
- A pull request's status words are declared in `services/gctk/prstatus`, as
  `State` and, for the `held:` labels, `Hold`.
  [pull-request-states.md](pull-request-states.md) explains them.
