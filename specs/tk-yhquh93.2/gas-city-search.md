---
name: Gas City search for the rig board's read (tk-yhquh93.2)
description: The supervisor and bd reads searched before the helm service gained the rig board's read and its two routes, what each covers, and why the read gathers through `gc bd list` rather than the supervisor's bead routes. Read it when judging whether that read should exist, or when a Gas City or bd release may let it read through the supervisor.
---

# Gas City search for the rig board's read

The change adds operational surface to the helm service:

- two routes, `GET /helm/rigs` and `GET /helm/rigs/{rig}`, with a cache of one
  document per rig (`services/helm/internal/server/rigboard.go`);
- the read behind them, `services/helm/internal/rigboard`, which gathers one
  rig's store through the gc command and asks the pack's shared readers
  (`services/gctk/waits`, `services/gctk/prstatus`,
  `services/gctk/conversation`) once per gather;
- an exported entry onto the service's gc command seam (`source.GC`,
  `source.NewGC` in `services/helm/internal/source/gccli.go`).

It adds no metadata key, bead kind, label or lifecycle state. Read on 2026-11-11
at Gas City upstream `6bd609f5b` (`gastownhall/gascity`) and beads upstream
`9d4ebf42f` (`gastownhall/beads`). The city runs gc 1.4.3 and bd 1.3.4
(`7ef2fd05e+patched`), and the live reads below were made against them.

## What the read needs

One read of a rig that answers, for every open bead: its raw status, its
edges, and for a gate the type of await that clears it; for every open epic,
its members, closed ones included. The board's groups turn on three of those
facts: whether a gate is one a person answers, whether a bead is deferred, and
which beads an epic holds.

## What was searched

| Primitive | What it gives | Why it does not cover the need |
|---|---|---|
| The supervisor's bead list, `GET /v0/city/{cityName}/beads` (`BeadListInput` in `internal/api/huma_types_beads.go`, `humaHandleBeadList` in `internal/api/huma_handlers_beads.go`) | Every open bead of a rig, paged, filtered by status, type, label, assignee and rig, with `all` adding closed history | Its rows are `beads.Bead` (`internal/beads/beads.go`), which has no await type, so a gate a person answers cannot be told from a gate that parks work. Live, a gate row carried only `created_at`, `description`, `id`, `is_blocked`, `issue_type`, `status` and `title`. It has no parent filter, and its closed history is a read of the whole rig's history, paged |
| Gas City's status model (`mapBdStatus` and `normalizedBdReadState` in `internal/beads/bdstore.go`, `IndefinitelyDeferred` and `SourceStatus` on `beads.Bead`) | The status every supervisor route serves | It folds bd's statuses into open, in_progress and closed. bd's deferred, blocked, hooked and pinned all read as open, and the two fields that keep the store's own status are `json:"-"`; the type's own comment says no read surface exposes the deferral. Live, `?status=deferred&rig=gc-toolkit` answered 0 beads while `gc bd list` held 10 deferred |
| `GET /v0/city/{cityName}/beads/graph/{rootID}` (`collectBeadGraph` in `internal/api/handler_beads.go`) | One root's parent-child closure, which is an epic's members | One call per epic, and its rows are the same `beads.Bead`, with no await type and the folded status |
| `GET /v0/city/{cityName}/bead/{id}` and `/bead/{id}/deps` | One bead and its dependencies | One bead per call, the same `beads.Bead` |
| `GET /v0/city/{cityName}/runs` | Workflow runs | Unit 2 of the gctk architecture searched it ([specs/tk-ssm8qns.11/gas-city-search.md](../tk-ssm8qns.11/gas-city-search.md)): a run names no bead it works, so in flight is read by `waits` from the run link |
| `bd list --include-gates --json` | Every bead the store lists by default and every gate, in one read, each with its raw status, its dependency rows and a gate's `await_type`. On gc-toolkit, 915 rows in 0.4 s | It covers the open beads. The read composes it |
| `bd list --parent <id> --status closed --json` | A parent's closed children | It also returns a bead whose own parent-child edge does not name the parent: on 2026-11-11 `--parent tk-ikpyzn --all` returned `tk-ikpyzn.3.1`, which carries no parent-child edge at all. The read composes it, one call per open epic, and keeps a bead only when its own parent-child edge names the epic |
| `bd blocked --json`, `bd gate list`, `bd graph`, `bd dep tree` | What holds a bead, and walks of the graph | The pack's shared readers already compose these: `waits` reads the blocked set ([specs/tk-ssm8qns.3/gas-city-search.md](../tk-ssm8qns.3/gas-city-search.md#the-blocked-set)), and `prstatus.Holding` is the walk of `blocks` edges, whose search is [specs/tk-1tfzr71.34/gas-city-search.md](../tk-1tfzr71.34/gas-city-search.md) |

No supervisor route carries a gate's await type, a deferred status or an
epic's members, so the read gathers through `gc bd list`, as the pack's
shared readers already read the store. A supervisor bead
route that served the await type and the store's own status, and filtered by a
parent's edge, would let the gather move onto it with no change to the
document.

## The cache

The supervisor caches its own `all=true` bead reads in a time bucket
(`humaHandleBeadList`, the `cacheKeyFor` branch), and nothing upstream caches a
composed answer for a caller. The read's cache is the one the helm service
already keeps for its board (`internal/server/server.go`): a time to live, one
gather of a key at a time, and every key dropped when a write route succeeds.
One gather of gc-toolkit, the city's largest store, took 5.5 s on 2026-11-11,
3.7 s of it the waits snapshot over 837 beads, and the time to live is a minute
from that measure.
