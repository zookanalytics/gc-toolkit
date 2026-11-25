---
name: Gas City search for one owner of a bead's standing
description: The search AGENTS.md asks for before gctk gains `gctk bead stands`, the verb that answers where a bead stands and whose move it is. What Gas City and bd offer toward that question, read at named upstream commits, why none answers it, and why the verb composes them through gctk's domains. Read it when checking whether the verb can move onto a Gas City primitive, or before giving it a new input.
---

# Gas City search for one owner of a bead's standing

The design ([design.md](design.md)) adds one verb, `gctk bead stands
<bead>...`, and the packages behind it, `standing` and `standing/person`. For
each bead it answers the helm board's group for it (Waiting on you, Queued,
Not moving or Closed), the rule that placed it there, what a person owes when
the bead is itself the ask, and whether the city carries it to its end without
a person. It adds no metadata key, no bead kind and no state. It reads the
store through gctk's ledger and asks gctk's domains.

## The need

For a bead id: whose move it is, a person's, the city's or nobody's, and when
it waits on other beads, the first of them that does not move without a
person. The answer reads the bead's own waits, the waits of the beads it waits
on, the pull request it carries, a conversation about it, and whether any pool
takes it as things stand.

## Where the search looked

Each was read on 2026-11-19:

- Gas City at `gastownhall/gascity` `17d7d77ce29c`, upstream main.
- bd as `github.com/steveyegge/beads` `v1.3.4`, the version the city's bd
  reports.

## What each offers

- **bd's ready and blocked answers.** `bd ready` (`readyCmd`,
  `cmd/bd/ready.go`) lists the beads no open blocker holds, and `bd blocked`
  the beads one does. `bd ready --explain` (`runReadyExplain`, with
  `types.ReadyExplanation` in `internal/types/types.go`) gives each blocked
  bead's blockers by id, title, status and priority, over the whole graph.
  Neither says whose move a blocker is: a human gate, a decision, a pull
  request that waits on a review and work a pool holds all read alike. gctk
  composes the store's blocked answer through `waits` (`gctk bead holds`), and
  the verb takes it from there.
- **bd's `human` label.** `bd human list` (`humanListCmd`, `cmd/bd/human.go`)
  lists the beads that carry the label `human`. Gas City reads the label as a
  bead waiting on a person's decision (`HumanLabel`,
  `internal/beadmeta/hold_labels.go`) and serves it to no pool through
  route-scoped dispatch. It is a mark a writer sets on the bead itself, so it
  cannot say that a bead is a person's move because a gate, a decision, a
  conversation or a pull request it waits on is one. No pack writer sets it,
  and no bead in the city's seven stores carries it, live or closed. gctk's
  armed start leaves it out of what it starts, as Gas City's pool does
  (`serveRule`, `services/gctk/arm/arm.go`), and `queue` does not yet read it
  (tk-whnukvi, held for placement).
- **Gas City's hold labels.** `hold:mayor` and `hold:external` name a bead's
  required next actor (`DispatchHoldLabels`,
  `internal/beadmeta/hold_labels.go`;
  `engdocs/contributors/hold-label-conventions.md`), and dispatch serves a held
  bead to no worker. gctk's `queue` reads them as Gas City's `HasDispatchHold`
  does, and the verb takes that reading from `queue`. They are marks a writer
  sets as well, so each answers for the bead that carries it and for no bead
  that waits on it.
- **Gas City's human gate.** A gate bead whose await type is `human` is Gas
  City's native wait for a person. The verb's rules read it, as the board and
  `prstatus` read it today.
- **`gc ready`.** It lists the work a pool would claim now, city-wide
  (`newReadyCmd`, `cmd/gc/cmd_ready.go`, over `internal/readywork`). It
  answers whether a pool takes a bead, and says nothing of whose move a bead
  no pool takes is.
- **Gas City's run status.** `CanonicalRunStatusForLane`
  (`internal/runproj/canonical_status.go`) gives a workflow run's state:
  pending, active, waiting, canceling, or how it ended. It answers for a run's
  root, says that a run waits and not on whom, and answers nothing for a bead
  no run works.

## Why the verb composes them

No primitive answers whose move a bead is from its own state and the beads it
waits on. Each answers a part, and gctk's domains already compose those parts:
`waits` reads the store's blocked set, `queue` reads routes, arms, assignees
and Gas City's hold labels, `prstatus` reads where a pull request stands over
the GitHub read the landing order saved, and `conversation` reads a
conversation's shape. The verb adds the rule that turns those answers into a
group and a move, the rule the helm board's rig read holds today. The board and
an agent's read of a bead then take one answer, and a pull request's status
reads the same rules about a bead.

## The verb's word

`bd status` answers with counts over a whole store, and a bead's status is a
field of its row, so a verb named `status` would be taken for either and answer
differently. No command in Gas City or bd at the commits above uses `stands`,
and it pairs with `gctk bead holds`.
