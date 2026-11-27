---
name: Gas City search for the queue's reading of bd's human label (tk-whnukvi)
description: The record, for tk-whnukvi, of the Gas City skip gctk's queue mirrors when it reads an armed or routed bead that carries bd's human label as sent nowhere, read at gastownhall/gascity upstream main, with the reason Gas City gives for the skip, the city's measurement of it and why it is no fault to fix at the source. Read it when reviewing the queue's scheduled rule, or before the pack gives the human label a writer or another reading.
---

# Gas City search: routed dispatch serves no bead that waits on a person

`scheduled` in `services/gctk/queue/queue.go` reads an armed or routed bead that
carries bd's `human` label as one nothing sends, and an assigned one as sent.
That mirrors a skip of Gas City's: its routed, unassigned dispatch serves no
bead that carries the label, and its assignee-scoped tiers still serve one. Gas
City is read at gastownhall/gascity `17d7d77ce29c`, the commit the change
cites, and at upstream main `6dce31bbb6` (2026-11-27T05:51Z), where the code
quoted below reads the same.

## The behavior

- **The routed tier leaves the label out.** `PoolDemandServeRulesForQuery`
  (`internal/config/workquery.go`) gives the routed pool-demand tier
  `RequireUnassigned`, and `ExcludeLabels` of the two dispatch holds and
  `beadmeta.HumanLabel`. Every generated routed demand query takes its flags
  from it, through `ShellArgs`.
- **The assigned tiers do not.** Their reads exclude only the dispatch holds
  (`excludeLabelArgs(beadmeta.DispatchHoldLabels)` in the same file).
- **The label is compared trimmed and in its exact case.** `HasHumanLabel`
  (`internal/beadmeta/hold_labels.go`) serves a bead labeled `Human` as
  ordinary work.
- Upstream added the skip in `88e4d10a91`, "fix(dispatch): exclude human beads
  from routed readiness (#7366)", on 2026-10-12.

## The reason Gas City gives

`HumanLabel`'s comment calls the label "bd's native label for a bead waiting on
a person's decision", and gives the reason for the skip: "Route-scoped,
unassigned dispatch excludes it all the same, for the reason it excludes a
hold: a worker cannot advance a bead that is waiting on a person, and serving
it back on every tick burns a turn each time (ga-7yfnyv). The assignee-scoped
tiers stay transparent to it."

## Why the queue mirrors it

The queue asks whether anything sends a bead as things stand, from the rows it
already reads. Gas City ships the rule a row is classified by as
`PoolDemandServeRulesForQuery`, which its comment says callers that classify a
row consume. It lives in Gas City's `internal/config` package, which Go lets no
module outside Gas City import. Gas City's command for the routed set,
`gc ready` (`cmd/gc/cmd_ready.go`), lists ready, claimable work, so a routed
bead that an open blocker holds is absent from it, though a pool takes it once
the blocker closes. So gctk's runtime adapter, `services/gctk/internal/gascity`,
holds the label beside the dispatch holds, compared as `HasHumanLabel` compares
it, and every gctk reader of the label reads that one copy.

## Tested against this city

Measured from 2026-11-27T22:40Z to 22:42Z, after the change was built.

- **The city's gc leaves the label out of every routed read and of no assigned
  one.** `gc agent list --json`, run in the city, gives each agent's effective
  work query. The city's gc is 1.4.3, built from `210638e33c`, which is not on
  upstream main and carries `88e4d10a91` in its history. Each work query was
  split into its `bd` and `gc` `ready`, `query` and `list` calls. Across the
  city's 136 agents, all 816 calls that carry `--unassigned` carry
  `--exclude-label "human"`, and none of the 816 calls that carry `--assignee`
  does. The label appears 136 more times, once in each agent's query, in the
  jq filter over unassigned rows routed to the agent, which drops a row that
  carries it.
- **No bead in the city has ever carried the label.** In each of the city's
  seven stores, its own and its six rigs', one SQL read per table counted the
  labels whose text, trimmed, is `human` in any case. It found none of the
  23,894 rows of `labels` and none of the 65,777 rows of `wisp_labels`. A read
  of the `label_added` and `label_removed` events whose label, trimmed, is
  `human` in any case found none of the 24,494 in `events` and none of the
  65,770 in `wisp_events`. Each store's label events start at its first one,
  between 2026-04-23 and 2026-10-18 for beads and between 2026-09-18 and
  2026-11-21 for wisps, so the count reaches back that far. A label given at
  create is logged as a label event too: the newest bead created with two
  labels, at 2026-11-27T22:34:58Z, carries a `created` event and a
  `label_added` event for each.
- **Nothing in the city writes the label.** A search of the pack's scripts, Go
  code, formulas, orders and docs at this head finds no write of it, and every
  use of it in the Go code reads it. At upstream main, Gas City uses
  `beadmeta.HumanLabel` only in reads: its serve rules, the demand predicate in
  `cmd/gc/demand_serve_predicate.go` and the dead-assignee sweep's skip in
  `cmd/gc/pool_session_name.go`. By its help, bd 1.3.4's `bd human` lists,
  answers, dismisses and counts such beads, and none of those adds the label.
  A person or an agent sets it only through a plain label write, such as
  `bd label add <id> human`.

## What the census can and cannot show

- The zero shows that nothing in this city gives the label another meaning, so
  nothing here contradicts Gas City's reason. The label means here what bd and
  Gas City mean by it, a bead that waits on a person, which is how the board
  reads it (the bead stands contract in `docs/gctk-architecture.md`). It also
  shows that no board row reads differently when the change lands.
- It cannot show how the queue reads a bead that carries the label, because
  there is none. Fixtures show that. `TestScheduled` in
  `services/gctk/queue/queue_test.go` reads an armed bead and a routed one that
  carry the label, trimmed, as not scheduled, an assigned one and a worked one
  as scheduled, and a routed one labeled `Human` or `humans` as scheduled.
  `TestTheHumanLabelIsHumanInItsExactCase` in
  `services/gctk/internal/gascity/hold_test.go` covers the comparison.
- Nor can it show the turn a served bead would burn here, because no bead here
  carries the label to be served.

## No fault to fix at the source

The skip is Gas City's design, stated with its reason, and its reason holds in
this city, so this change files no fix at the source.

## When the evidence came

- Before the change: the bead was filed with a count, dated 2026-11-19, that no
  bead in the city's seven stores carried the label and that no pack writer set
  it, with no method recorded. The plan read `HumanLabel` and
  `PoolDemandServeRulesForQuery` at `17d7d77ce29c` at 2026-11-23T19:07Z, before
  the change's first commit, `1009e81cba`, at 19:17Z.
- After the change: counts at 2026-11-23T19:18Z and 19:35Z, a conversation's
  count at 2026-11-26T07:39Z of beads that ever had the label added or removed,
  and the PR summary's count at 2026-11-27T22:10Z each found none, with no
  method recorded. The measurements under "Tested against this city" are this
  record's own.
