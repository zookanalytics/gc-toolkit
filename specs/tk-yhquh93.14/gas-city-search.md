---
name: Gas City search for the Needs you count (tk-yhquh93.14)
description: The Gas City and bd primitives searched before the rig board counted every need by kind and left the needs about parked work out of its count, and why the board composes its own readers' answers instead. Read it when judging whether the document's kinds, counted and not_counted keys, or the board's reading of a park, should exist.
---

# Gas City search for the Needs you count

The change grows the rig board's document (`GET <mount>/helm/rigs/{rig}`).
Every Needs you view, the rig's and each epic's and Delivery's, now carries
`count`, `kinds`, `counted` and `not_counted`, and each need in it its `kind`.
An epic's and a Delivery's `needs` was a list of needs and is now that view. It
adds no route, verb, order, metadata key, bead kind, label or lifecycle state,
and it writes nothing.

The upstream code below was read on 2026-11-13, at the commits the city runs:

- Gas City at `gastownhall/gascity` `f143846427`. The city's gc reports a build
  of a fork's `6589a7df45`, whose upstream base is that commit.
- beads at `gastownhall/beads` `7ef2fd05e`, the commit `bd version` reports for
  the city's bd 1.3.4.

## Telling a park

| Primitive | What it gives | Covers the need? |
|---|---|---|
| bd's gate types: the help of `gateCmd` in beads' `cmd/bd/gate.go`, and `AwaitType` in its `internal/types/types.go` | A gate's await type, of the types the help names: human, timer, gh:run, gh:pr and bead. `bd gate check` (`evaluateGates`) closes the timer, GitHub and bead gates itself and skips a gate of any other type, so a gate with no await type closes only by hand | In part. The await type tells a gate a person answers from one bd closes by itself, and a park's gate from both: `gc-helm.sh park` files a gate with no await type. No type, label or field says "park", so a park made with `--waiting-on` onto a task or a human gate carries nothing that tells it apart |
| bd's blocked rule, as `bd blocked` and `bd ready` apply it | Whether a bead is blocked, by its own open blockers or a parent-child ancestor's | No. It names the blockers and says nothing of why each was made. The board already reads it through `services/gctk/waits` |
| Gas City's dispatch holds, `DispatchHoldLabels` and `HasDispatchHold` in its `internal/beadmeta/hold_labels.go` | The hold labels `hold:mayor` and `hold:external`, compared trimmed and in any case | For work held for the Product Owner, yes, and the board's `carriesHoldMayor` compares the label the same way. A hold label is no park: docs/steering.md's park is a blocker, and Gas City has no park label or state |
| Gas City's parked seats (`parkSeats` in its `cmd/gc/allocator_plan.go`) | A pool seat the allocator parks | No. It is about sessions, not beads |

So the board tells a park the way its table already reads a gate no person
answers, "Held by a gate" (row 4 in `internal/rigboard/table.go`): a wait on a
gate that is not a human gate. Row 4 and the count call one function,
`gateHold`, so a row and the count cannot read a gate two ways. At
2026-11-13T02:28Z the city's seven stores held 53 open gates, 43 human gates and
10 with no await type, so the reading and a park's gate select the same gates.

## Counting needs by kind

| Primitive | What it gives | Covers the need? |
|---|---|---|
| Gas City's dashboard set of beads that need the operator, `selectBeadsNeedingAttention` in its `internal/api/dashboardspa/web/frontend/src/attention/beadsNeedingAttention.ts` | One count, read by the nav badge and the page alike, of beads with a reason: ready-unclaimed, escalated, stalled or waiting-human. It leaves out a bead a dependency blocks | No. Its reasons are not the board's asks: it has no pull request awaiting review, human gate, conversation or ruling, and it counts ready and stalled work, which the board leaves to its Work queue. It tells no park, and it reads the supervisor's bead list, whose rows carry no await type ([specs/tk-yhquh93.2/gas-city-search.md](../tk-yhquh93.2/gas-city-search.md)) |
| The same dashboard's agents that need the operator (`agentNeedsYou.ts` beside it) | Agents awaiting input, errored, rate limited or stalled | No. It is about sessions |
| The supervisor's bead routes, `GET /v0/city/{cityName}/beads` | A rig's beads | No count, kind or reason |

So the board counts its own asks, which the pack's shared readers already
answer (`prstatus.IsHumanGate`, `prstatus.Derive`, `prstatus.IsPersonBlocker`,
`conversation.IsAssignee`), and a need's kind is its ask in the table's own
words. One function, `view` with `kindCounts` in `internal/rigboard/build.go`,
gives every view its counts, so the lead, the tab, an epic's line and each kind
read one answer.

## How it is cached

The counts are a function of the rig's one read, computed while the read builds
the document. They are cached with it by the board's existing rule
(`server.RigBoardTTL`, dropped when a write route succeeds), so they add no
cache and no read.
