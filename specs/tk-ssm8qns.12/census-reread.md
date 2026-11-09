---
name: Unit 3's re-read of the stores and its census of prompts and skills
description: What the seven stores held on 2026-11-09 for the cases where gctk bead holds answers differently from the reads it replaces, and every prompt and skill that teaches a read of "is this blocked?", with where each went. Read it when you judge what unit 3 changed for a live bead, or look for a place that still decides it by its own rule.
---

# Unit 3's re-read of the stores and its census of prompts and skills

Unit 3 of the gctk effort (tk-ssm8qns.12) moves every caller that decides "is
this blocked?" onto `gctk bead holds`. The census
([blocked-census.md](../tk-ssm8qns.2/blocked-census.md)) names the places and
the rules they used. This page records two things the unit owed beside it: a
re-read of every store for the cases where the one rule answers differently,
and a census of the prompts and skills, which teach reads an agent runs by
hand.

## The stores, re-read

Read 2026-11-09 at 02:20Z, at a one-minute load of 6.5 to 7.7, over all seven
stores the city binds, the city's own among them. Each count covers the issues
and the wisps tables.

| Case | What the one rule changes | Found |
|---|---|---|
| A `waits-for` or `conditional-blocks` edge on any bead | a `waits-for` edge holds as unjudged, and a `conditional-blocks` edge holds as a `blocks` edge does, where the old readers ignored both | none, in any store |
| A parent held only by an open human gate, with live children | the children read held through their ancestor | none, in any store |
| A pinned human gate | it holds nothing, as the store counts a pinned blocker, where `hold-lib.sh` held on it | none, in any store |
| A live bead's wait edge onto a bead in another store | it holds nothing, and is listed under `foreign` | three, all in gc-toolkit's store: tk-7rea7j onto gc-8kwa5, tk-r05k0v onto gc-tobpf and tk-nt5uda onto gc-vz6v0, each a `blocks` edge |
| An armed bead `hold-lib.sh` and `gctk bead holds` answer differently | reconcile would sling, or hold, the other way | none of 184 armed beads, 136 of them in gc-toolkit's store and 8 in gascity's |
| A refinery handoff the two answer differently | find-work would take, or skip, the other way | none of 8 |

So no live arm, handoff or hold changes its answer with the move, except the
three foreign edges, which the converted check-wait-is-an-edge now reports
(its FOREIGN section). The converted checks were also run live against the
old ones:

- check-armed-dispatch-owed reads OK under both.
- check-wait-is-an-edge reports the old check's 64 findings and the three
  foreign edges. Two stale lines that called gc-8kwa5 and gc-tobpf "in no store
  this scope can read" now say each is in another store, where an edge holds
  nothing.
- check-step-terminal no longer warns that three stalled frontiers sit under
  open molecules: tk-7n4ixq2, tk-7129u0i and tk-9k1pseh. Each waits on
  tk-u5t8h6x, an open park gate. The old check's id lookup did not see it,
  because `bd list --id` hides a gate without `--include-gates`, and so read a
  blocker that resolves nowhere. The converted check holds all three, as the
  store does, and lists them among its notes.

## A place the census predates

The helm board now derives each bead's state (in flight, in review, in
conversation, parked, queued, stranded) from what holds it
(`services/helm/internal/board/state.go`, PR #1351, merged after the census).
It sorted a bead's open blockers by each blocker's own status and counted
the open waits of its ancestors, a board-side answer to what holds a bead.
The design's Compositions rule gives that question to `bead holds`, since a
loop also acts on it, so it moves too: the source marks each blocker it
hydrates, an anchor's and an open child's, with the store's own answer from
the rig's one read, and the state reads that answer, falling back to the
blocker's status only for a bead the read did not answer. The census's D25
places (`ruled`, `ruledInFlight` and `dispositionDue`) read the same answer
through the anchor's landed waits.

## The prompts and skills

Every agent prompt, skill, formula's prose and template fragment was searched
for a read that decides whether a bead is held: a `blocks` row read off `bd
show` or `bd dep list` and judged by its status, `bd blocked`, `bd ready`,
`blocked_by`, `bead-context.sh --frontier`, and `hold-lib.sh`.

| Place | The read it teaches | After |
|---|---|---|
| `skills/converse-recheck-premise/SKILL.md`, the close's check that another open blocker still holds the subject | `gc bd dep list --type blocks` rows not closed | moves: pending |
| `skills/converse-epic-checkpoint/SKILL.md`, the list of a Delivery's open blockers that finds its park | `gc bd dep list --direction=down -t blocks` rows not closed | moves: pending |
| `skills/work/integration-effort.md`, the block for a bead that joins an effort later (the census's D18, which moved here from the mechanik's prompt) | the summary task's show row, a `blocks` edge not closed | moves: pending |
| `skills/converse-prep/SKILL.md` and `skills/converse-iterate-document/SKILL.md` | `bead-context.sh <bead> --frontier` | stays: the script asks `gctk bead holds` since this unit |
| `skills/converse-epic-checkpoint/SKILL.md`, every other bead still waiting on a park | the park's dependents, `--direction=up` | stays: it asks what a park holds, the reverse of what holds a bead, which `gctk bead holds` does not answer |
| `formulas/mol-witness-patrol.toml`, check-refinery's list of what each queue gate blocks | the gate's dependents, `--direction=up` | stays: the same reverse question, and the step retires with tk-1tfzr71.19 |
| `skills/converse-prep/SKILL.md`, the subject's human gates | a `blocks` listing filtered to human gates, for the sitting to read | stays: it names the gates, and decides nothing |
| `skills/converse-epic-checkpoint/SKILL.md`, the children of an epic or a Delivery | `parent-child` listings | stays: decomposition, not a wait |
| `agents/proactive/agent.toml`, `work_query` and `scale_check` | `gc bd ready` | stays: the store's own query (the census's D3) |
| `formulas/mol-design-convoy.toml`, six places, and `skills/converse-settle/SKILL.md`, `skills/prs/SKILL.md`, `skills/work/integration-effort.md` and `skills/waits/SKILL.md` | `gc bd dep list ... -t blocks` after a `dep add` | stays: each asks whether a write landed, not whether a bead is held |
| `agents/_converse/prompt.template.md` and the converse skills' `tracks` and `replies-to` reads | a conversation's edges | stays: the shape of a conversation, not a wait |

No prompt teaches a read of its own. The mechanik's prompt held the one the
census found, and that text moved into the work skill before this unit
(tk-ufmime2).
