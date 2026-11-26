---
name: Gas City search for the rows gctk pr status shows (tk-ivqez0f)
description: What tk-ivqez0f read in the supervisor's bead routes before moving the rows `gctk pr status` shows onto one supervisor request, why those routes cannot serve them as the command shows them, the 2026-11-26 measurements, and where the command's runs come from. Read it before moving another gctk bead read onto the supervisor's copy.
---

# Gas City search for the rows gctk pr status shows

Gas City was read at `gastownhall/gascity` main 44246e7f5a (2026-11-26). The
city's gc 1.4.3 is built from the fork's 210638e33c, which serves the same bead
row: its `beads.Bead` declares the same JSON fields, and the list handler, the
cache's scan query and the native store's metadata decode read the same at both
commits. The city's supervisor reads its stores through Gas City's native Dolt
store, as its status reports (`beads.beads_store` is `NativeDoltStore`). The
live reads below were made on 2026-11-26 between 07:45Z and 08:20Z.

## The need

`gctk pr status <anchor>` prints where a PR stands
([prstatus.go](../../services/gctk/internal/cli/prstatus.go)). tk-ivqez0f was to
take the rows it shows from one request to the supervisor and to keep the
store's blocked answer on `gc bd`, changing nothing the command prints for the
same state of the store. A run reads these rows:

| Read | Rows | What the command uses of each row |
|---|---|---|
| The walk: `prstatus.Holding` through `gcbdStore.Blockers`, one `gc bd show` a level | the far bead of each `blocks` edge, open and closed | its issue type and await type, which tell a human gate (`person.IsHumanGate`); its await id, which tells a gate a review run's failure filed (`prstatus.IsMachineGate`); its status, whether open or closed, and exactly `open` for a conversation that stays (`conversation.Staying`); its assignee and metadata; and each closed review run's close time, by which `prstatus.runFailed` finds the run that ended last |
| The waits snapshot: `waits.Read` inside `pr.FromStore`, through the ledger's `gc bd list --id ... --all` | the anchor, and the far bead of each wait and parent edge, a generation at a time | the anchor's typed keys, and each wait's title and status, which `pr.ownWaits` prints as "the bead waits on X (blocks, status)" |
| The anchored work: `pr.anchoredTo` | each live bead whose `anchor_bead` names the anchor | its status and title, which it prints as "X (status) names the bead as its anchor" |
| The in-flight count: `gcbdStore.Anchored` | the same beads, at a live status | their number, `Facts.InFlightCount` |
| The blocked set: `gc bd blocked` and the marks query | none | the store's own answer, which stays on `gc bd` ([gctk-architecture.md](../../docs/gctk-architecture.md), "The adapters") |

## What was searched

| Primitive | What it gives | How it bears on the need |
|---|---|---|
| `GET /v0/city/{city}/beads` (`humaHandleBeadList`, `internal/api/huma_handlers_beads.go:40`) | A rig's live beads from the cache, filtered by status, type, label, assignee and rig, 1000 rows a page with `next_cursor`. With `all=true` it reads closed beads too, but "all=true reads bypass the CachingStore (closed history lives only in the backing store)" (`:72`) | Serves no closed bead from memory. Its history read is a read of the store, the cost this work set out to remove |
| `GET /v0/city/{city}/bead/{id}` (`humaHandleBeadGet`, `:751`) | One bead, from the cache, or from the store when the cache does not hold it | Serves a closed bead one request at a time, in the same row |
| `GET /v0/city/{city}/bead/{id}/deps` | The bead's children | Not the `blocks` edges the walk follows |
| `beads.Bead` (`internal/beads/beads.go:127`), the row every bead route serves | Id, title, description, status, issue type, priority, creation and update times, assignee, `from`, parent, `ref` and `needs`, labels, metadata, dependencies as `issue_id`, `depends_on_id` and `type`, the ephemeral and no-history flags, the defer time, the blocked mark and the close reason | It has no await type, no await id and no close time, and a dependency names its far bead by id alone. Its status is one of Gas City's three: "bd's blocked, deferred, review, testing, hooked and pinned all read as "open"", and the store's own status stays in `SourceStatus`, which is `json:"-"` (`:259`) |
| `metadataValueText` (`internal/beads/native_dolt_store.go:3690`), the native store's decode of each metadata value | A string as itself, and any other JSON value as its JSON text | A stored false comes back as "false", and a stored null as "null". The ledger reads both as values the bead holds, where it reads the store's null, and a false under a String key, as no value. The bd CLI store's decode, `StringMap.UnmarshalJSON` (`internal/beads/bdstore.go:983`), gives a null as an empty string instead |
| `cacheFullScanQuery` (`internal/beads/caching_store_reconcile.go:62`) | What the cache holds: every bead that is not closed, in both tiers | No closed row is cached |

## Measured

The route reads were made with `curl` against the supervisor's
`/v0/city/<city>/bead/<id>` and `/v0/city/<city>/beads?rig=gc-toolkit&limit=1000`,
the list paged through `next_cursor`, and set beside `gc bd show <id> --json`.
The counts were read from 08:13Z to 08:19Z. The anchors came from one
`gc bd list --status open,in_progress,blocked,deferred,hooked,pinned
--has-metadata-key merge_result --json --limit 0`, which listed 62 live PR
anchors. 60 of them were on the pending record, where `merge_result` is
`pull_request_pending` or `pull_request_head_changed` (`record.OnRecord`). One
`gc bd show` of those 60 gave each anchor's `blocks` edges with each far bead
whole, and jq counted them.

- Gate fields. The route's row for the open human gate tk-s8lwegw carried
  created_at, description, id, is_blocked, issue_type, status and title.
  `gc bd show` gives its await type, human, and its await id,
  refinery-invalid-existing-pr. 10 of the 60 anchors on the pending record had
  an open human gate among their blockers.
- Close times and closed rows. The route's row for the closed tk-a1oxlpg carried
  no close time, where `gc bd show` gives 2026-11-26T07:37:27Z. The rig's list
  without `all=true` held 928 open and 12 in-progress beads and no closed one.
  All 60 anchors on the pending record had a closed review run among their
  blockers.
- Status. `gc bd list --status <status> --json --limit 0` gave 50 bd-blocked
  beads in the gc-toolkit store and 151 deferred ones. All 49 anchors at
  `merge_result=pull_request_pending` were bd-blocked, and the route read one of
  them, tk-0bxcur0, as `open`. No anchor's blockers held a blocked or deferred
  bead.
- Metadata. Live rows show the coercion: tk-36fz90k's `gc.takeaway_settled`,
  the number 1 in bd, came back as the string "1", tk-npkp7mk.3's
  `pr_reconcile_pending`, true in bd, as "true", and tk-qulxvk's `merge_hold`,
  false in bd, as "false". None of the 62 live PR anchors held a false or null
  value, and no bead in the gc-toolkit store held a stored null, by a regular
  expression over its metadata column through `gc bd sql`.
- Calls. A logging `gc` on PATH, a script that appends its arguments to a file
  and runs the real `gc`, counted 9 `gc bd` calls for a run on tk-1nio71o,
  whose walk read one level, and 11 for tk-1tfzr71.21, whose walk read three. A
  second run of each at 08:15Z counted the same.

## What the copy can serve

The walk cannot take the copy. Without the await type it cannot tell a human
gate from any other gate, and without the await id it cannot tell a gate a
review run's failure filed. It also reads closed review runs and their close
times, which the list does not hold and no route's row carries. The waits
snapshot reads closed far beads too, and it prints each wait's status, which the
copy folds: an anchor that waits on another pending PR's anchor would print
`open` where the store says `blocked`. The anchored work prints each bead's
status the same way. Each of these would print something other than what the
command prints today for the same state of the store.

The in-flight count is the one read the copy serves as it is. For an anchor on
the pending record, 60 of the 62 live PR anchors, the command prints
`prstatus.Render`'s answer ([prstatus.go:121](../../services/gctk/internal/cli/prstatus.go)),
and `Render` never reads `Facts.InFlightCount`. Moving that read would save a
call whose answer the command does not print for those anchors. So no read
moves, and `gctk pr status` keeps reading the store.

The operator wrote, in the description of conversation tk-sr5658g: "I often
feel like having to avoid a cache is an indication that we're either using the
wrong cache key or otherwise doing something weird." Here the key is not the
cause: the cache holds every live bead of the rig, and the list route returns
them all. What this command needs is a gate's await fields, a close time, a
closed bead and bd's own status, and none of them is in the row Gas City's API
serves.

## The reason Gas City gives, tested here

Gas City states the status fold as its design. `SourceStatus` holds the status
the store recorded "before Status folded it into Gas City's three-state model"
(`beads.go:249`). The `IndefinitelyDeferred` comment beside it says the HTTP,
SSE and `--json` surfaces report a bd-deferred bead as `open`, and that "giving
the exclusion a derived read-only representation is a wire-design decision"
(`:230`). Gas City gives no reason for leaving a gate's await fields and a close
time out of the row, and the row has never carried them: `git log -S` over
`beads.go` finds no commit that adds or removes `await` or `closed_at`. No Go
code in Gas City reads an await type. Its own readers of one, the core pack's
`renudge-stale-human-gates.sh` and `notify-on-human-gate-creation.sh`, read it
from `gc bd gate list --json` and `gc bd show --json`. Both fall back to the
`gc.gate_type` metadata of a gate a formula synthesized, because "gc's stores
have no await_type column" (the renudge script's header). So Gas City reads a
gate's await type from bd, as gctk does, and its row carries what its Go
readers use. That is its model, not a fault, and it holds here, where the store
keeps bd's own fields and a reader that needs them reads `gc bd`. No fix at the
source is owed, and this work asks nothing of Gas City, as its description
bounds it.

## Where the runs come from

A 174-second sample of the process table (`ps`), from 07:51 to 07:54Z, caught
16 runs of `gctk pr status` besides the measurement's own.

- The landing order, `gctk pr reconcile`, started 10. It derives every owned
  PR's labels in its own process, over its pass (`labelPlans` in
  [labels.go](../../services/gctk/pr/labels.go)). For each PR whose saved
  labels differ, it runs `pr-status-label.sh reconcile`, and that script runs
  `gctk pr status --json` to derive the same labels again
  ([pr-status-label.sh](../../assets/scripts/pr-status-label.sh), `derive_value`).
- pr-facts.sh started 4.
- Three of the 13 PRs the sample saw were refreshed twice, about two minutes
  apart.

## Follow-ups

Both are filed for the operator's placement. Until one lands, each run of
`gctk pr status` keeps making 9 to 11 `gc bd` calls, and tk-sezabk tracks what
that costs the database.

- tk-vhexrh0: the landing order's label write uses the labels the order
  derived. The 10 runs it started in the sample come to about 3.4 a minute,
  and at 9 to 11 `gc bd` calls a run, to about 35 calls a minute.
- tk-girlkg9: one run of `gctk pr status` reads each bead once. The walk's first
  level and the waits snapshot's first reads return the same beads, and the
  in-flight set is the anchored-work read narrowed. A `gc bd list` row carries
  everything the walk reads of a far bead, so one pass can serve both reads.
