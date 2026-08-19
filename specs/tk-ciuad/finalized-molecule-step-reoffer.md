---
name: A Finalized Molecule Keeps Offering Its Steps
description: Why a CLOSED graph.v2 step is reopened and re-offered after its root closed, which gc write sites are eliminated as the writer (with the one earlier acquittal this pass overturns), and why the durable gate is in the gc binary while the pack ships only a detector.
---

# A Finalized Molecule Keeps Offering Its Steps

> **Bead:** tk-ciuad. **Investigated:** 2026-08-19 (pass 5). **Author:** Polecat gc-toolkit.furiosa.
> **gascity pin for every file:line below:** `f475b68fc`.

## Scope

What this records: the elimination evidence produced by pass 5 against the
`rigs/gascity` write sites that could reopen a closed step bead, and the
reasoning behind shipping a pack-side detector rather than a pack-side fix.

What it does not record: the observational evidence for the loop itself —
the cycle table, the session-teardown correlation, the writer signature.
That is on bead tk-ciuad and is not duplicated here.

## The defect in one paragraph

A graph.v2 step bead that had closed normally, on a molecule whose root had
already closed `gc.outcome=pass`, was reset to `status=open` with its
assignee cleared, and the pool offered it again as fresh work. A polecat
claimed it and re-ran the whole step — a city-wide census including a live
`gh pr list` — against a molecule with no reader left. It repeated: four
polecat incarnations across two polecats, each reopen landing in the same
*second* as the teardown of the session that had just closed the step.

## Correction to the bead's pass-4 notes

Pass 4's notes state that the assignee-clearing mitigation was "applied to
tk-5suq6 on this pass as a live probe". **It was not, and there is no probe
result.** `tk.dolt_history_issues` for tk-5suq6 shows that session (lx-py6x3)
claimed the step at 04:28:24 and left it `in_progress`; the row that follows
is a release to `open`/`""` at 04:35:58 on session teardown. The step was
never closed by that pass, so the "close, then clear the assignee in a
separate write" probe never ran. Anyone reading pass 4 for an empirical
result on that mitigation will not find one.

This matters beyond bookkeeping: the mitigation's premise is that the
release paths enumerate by assignee, and §"What this pass overturns" below
weakens the case that any of those paths is the writer at all.

## What this pass establishes

### The writer signature narrows much less than pass 4 assumed

Pass 4 treated the commit message `gc: update bead <id>` as evidence
pointing at a particular actor. It is not. That string is built in
`NativeDoltStore.Update` (`internal/beads/native_dolt_store.go:953`), which
is the generic single-op update for the native store:

```go
return storage.RunInTransaction(ctx, fmt.Sprintf("gc: update bead %s", id), ...)
```

Every `store.Update(...)` from anywhere in the gc binary commits under that
message. It distinguishes the gc binary from a pack shell script (which
shells out to `bd` and commits `bd: ...`) and nothing finer. All the
candidate paths below would produce it.

### What this pass overturns

Pass 4 recorded `ReleaseWorkBead` tier 1 as acquitted because
`ReleaseIfCurrent` CASes on `status = 'in_progress'`. The predicate is real,
but **tier 1 never runs on a graph.v2 step bead**:

```go
// cmd/gc/work_assignment.go:212
singleWriteRequired := stampFallbackRoute || beadHasActiveContinuationGroup(item)
```

Every graph.v2 step carries `gc.continuation_group` (`pool-workflow`), so
`beadHasActiveContinuationGroup` (`cmd/gc/pool_session_name.go:453`) is true
and the atomic conditional tier is skipped by construction for exactly the
class of bead this defect is about. The acquittal was granted on a guard
that this bead class cannot reach.

### Why tier 2 is nonetheless acquitted, on stronger grounds

The fallback tier writes unconditionally after a live re-read, so it is the
natural suspect once tier 1 is out. It still cannot produce the observed
row, for two independent reasons:

1. **The status flip is gated on the snapshot.**
   `cmd/gc/work_assignment.go:261` only sets `Status: "open"` when
   `item.Status == "in_progress"`. A snapshot that already read `closed`
   clears the assignee but cannot reopen the bead.
2. **The live re-read is genuinely live.**
   `liveWorkAssignmentAssigneeMatches` (`cmd/gc/work_assignment.go:328`)
   lists with `Live: true`, and `CachingStore.List` short-circuits that
   straight to the backing store (`internal/beads/caching_store_reads.go:20`).
   The stale-cache hypothesis pass 4 floated dies here: `refreshCachedBeads`
   (`caching_store_reads.go:212-330`) folds stale cached rows into the
   **cache** via `absorbFreshLocked`/`evictLocked` and never appends them to
   the returned slice, so a bead closed in backing cannot reappear in a live
   `in_progress` listing.

So both halves of the TOCTOU would have to fail together, and the observed
gap is ~6.5 minutes between the step's close and its reopen — far too wide
for the recheck→write window that the code's own comment describes as
"shrinks the window rather than closing it".

The same reasoning acquits `releasePoolAssignmentWithRecheck`
(`cmd/gc/pool_session_name.go:513-534`), which shares the guard.

Note the snapshot read itself *is* cache-served — `OpenAssignedToBasic`
(`cmd/gc/work_assignment.go:129`) lists without `Live`. That is a real
staleness surface and worth knowing, but on its own it only produces a stale
*candidate*, which the live recheck then rejects.

### Two further single-write sites, eliminated

These are the only other places in `cmd/` and `internal/` that set
`Status: open` and an empty `Assignee` in one `UpdateOpts` — the exact shape
of the observed row:

| Site | Why it is not the writer |
|---|---|
| `internal/storebinding/beads_nudge_queue.go:995-998` (`nudgeQueueUnclaim`) | Operates only on nudge-queue beads, whose ids are hash-derived by `nudgeQueueBeadID` with a fixed prefix and suffix. A step bead is not reachable. |
| `cmd/gc/cmd_convoy_dispatch.go:1553-1558` (`gc workflow reopen-source`) | An operator CLI acting on a workflow's *source* bead, not a step. It also calls `clearSessionAffinityMetadataOnBead` first, whereas the observed reopen **preserves** the dead session's `gc.session_id`. |

## What is left for the gascity implementer

Everything above is elimination. The writer is still unidentified, and the
remaining surface is now:

- A write path that reaches a **closed** bead without consulting its status
  at all — none of the four sites above qualifies, so this is likely not a
  "release" in the sense the release paths mean it.
- Something in the graph.v2 engine itself
  (`internal/beads/caching_store_graph_apply.go`,
  `caching_store_graph_ready.go`) that re-derives step readiness. This pass
  did not open these; they are the obvious next stop precisely because the
  observed row keeps `gc.routed_to` and `gc.session_id` intact, which reads
  more like a *projection* being reapplied than like a release.
- A `Tx`-batched multi-write, which would not be found by the
  single-`UpdateOpts` grep this pass used.

The decisive experiment remains what pass 4 proposed: instrument the gc
reconciler across one polecat session teardown. Every candidate logs on its
skip path (`ReleaseWorkBead: skipping release for %s: ...`), so a run that
reopens a bead while logging *no* skip line convicts a path outside the
release family. The supervisor's stdout is not currently a usable channel
for this — `gascity-supervisor.service` is in a crash-restart loop on this
host (restart counter ~82k as of 2026-08-19T04:41Z) and journald carries
only systemd's own lines.

Two proposed gates, either of which closes the loop regardless of writer:

1. `gc hook --claim` refuses a step bead whose `gc.root_bead_id` names a
   closed root. This is the stronger one: it is a single choke point, and it
   holds even if the reopen is never fixed.
2. Whatever performs the write refuses a bead already `closed`.

## What ships in the pack instead

`doctor/check-finalized-molecule-step-reoffer/` — a detector, not a fix, on
the same footing as `check-routed-work-claimable`: the pack cannot reach the
binary's claim path, so it makes the failure loud and becomes the regression
gate once the binary gate lands.

It flags any `status=open` bead carrying `gc.root_bead_id` whose root
resolves in the same store as `closed`, past a settle window (default 300s,
because finalize closes the root a few seconds *before* the terminal step's
own close lands). It separates two shapes on one free metadata key, no
history query needed:

- **REOPENED** — the step carries `gc.outcome`, so it completed and was
  reset afterwards. This is tk-ciuad.
- **NEVER-CLOSED** — no `gc.outcome`; the molecule finalized around a step
  that never ran. The orphaned-repour family.

On the live city at 2026-08-19T05:00Z it reported three molecules that
nothing else was reporting:

| Rig | Molecule | Root closed | Shape |
|---|---|---|---|
| gc-toolkit | tk-5r029 | 2026-08-19T04:02:11Z | REOPENED — 1 step (tk-5suq6) |
| gc-toolkit | tk-iekvu | 2026-08-15T17:59:26Z | NEVER-CLOSED — 7 steps |
| gascity | gc-3lxdv | 2026-08-12T10:13:17Z | NEVER-CLOSED — 6 steps |

The two never-closed strands had been sitting for four and seven days. That
is the argument for the check existing: the reopen loop was caught by a human
noticing a duplicate census, and the quiet shape was not caught at all.

## Related

- `docs/gascity-routing-model.md` — the authority on the claim/offer
  predicate (`hookClaimMatchesRoute`, the `bd ready --metadata-field` demand
  read) that this document assumes when it says a step with a blank
  `gc.routed_to` is still offer-able. The empirical confirmation is in
  tk-ciuad's own cycle table: tk-5suq6 carried `gc.routed_to=""` throughout
  and was claimed three separate times.
- `specs/tk-5cgyk/unqualified-route-targets.md` — the same split-deliverable
  shape: pack-side detector, gascity-side durable guard, and the reasoning
  for why the pack cannot self-defend against a binary-layer defect.
