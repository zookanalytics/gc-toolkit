---
name: Root cause — recurring rig-scoped order-firing stall (order-firing-current)
description: Investigation record for tk-5v3k5y. The recurring blocking finding order-firing-current is a gascity order-dispatch defect, not a gc-toolkit pack registration defect. The scope=rig "unbound city-scope registration" the finding's Lead named is dropped before dispatch (discovery.go:182) and is a red herring. The real cause is that non-idempotent rig-scoped orders single-flight against the per-rig Dolt stores under one city-wide orderMu, so a recurring ~15-min store-contention window starves exactly those orders for 15-18min while city/idempotent orders keep firing. Fix routed to gascity gc-q1ttz.
---

# Root cause — recurring rig-scoped order-firing stall

- **Bead:** tk-5v3k5y — "root-cause the recurring rig-scoped order-firing stall (doctor order-firing-current, recurred 100x over 11d)"
- **Finding tracker:** tk-ou35ed — "doctor order-firing-current: scheduled orders are stale"
- **Routed fix:** gascity gc-q1ttz (p1 bug). Related cluster: gascity gc-uhrgn, gc-7s8mo.
- **Investigated:** 2026-09-26, city `/home/zook/loomington`, `gc` 1.4.1, git 2.55.0, gascity source at `cb8c260db`.
- **Author:** gc-toolkit/gc-toolkit.polecat (claude provider)

## Scope

Why `order-firing-current` recurs and where the fix lives. The deliverable of
this bead is a diagnosis and a routing decision: the durable fix is in the
gascity runtime, a repo a gc-toolkit polecat cannot push to, so it is filed as
gc-q1ttz with the mechanism, the patch sites, and a proposed test. This record
is the gc-toolkit-side historical account and the evidence behind that routing.
It is not the fix and not authoritative on what gascity will become — gc-q1ttz
owns that.

## Symptom

Six non-idempotent, rig-scoped orders that this pack defines and every rig
imports — `refinery-reconcile` (60s), `deferred-dispatch` (2m),
`gate-visit-sweep` (2m), `liveness-sweep` (condition), `feedback-miner` (48h),
`feedback-distiller` (24h) — periodically stop firing for ~15-18 minutes across
all four rigs at once, then resume on their own. The city-scoped orders keep
firing (~2-3m) throughout. It self-recovers, which is why it ran as a recurring
blocking finding 100 times over 11 days (2026-09-15 .. 2026-09-26) without being
actioned. The finding tracker tk-ou35ed carries the full timeline; a
representative episode's detail array shows the rig orders 15-18m stale
("CRITICAL: stale") while every city order reads 0-3m fresh.

Underneath the acute episodes there is a chronic band: every cooldown order
fires at roughly one run per 3 minutes regardless of its declared interval
(measured live: `gate-sweep` at 1m, `refinery-reconcile` at 60s, and
`deferred-dispatch` at 2m all landed on a ~3m period, and cross-rig orders fire
at identical timestamps). gascity gc-uhrgn already tracks that chronic band.

## The Lead was a red herring

The finding's Lead named the "unbound city-scope registration nothing could
claim" that `gc order check` reports for each of the six orders as a plausible
cause. It is not the cause. Reading the runtime that produces and consumes that
registration (`internal/orderdiscovery/discovery.go`):

- `ScanAll` scans an imported pack's `orders/` twice — once on the city pass
  (leaving `Rig=""`) and once per importing rig — so a rig-scoped order picks up
  an extra city-pass copy with no rig binding.
- `dropUnboundRigScoped` (discovery.go:198-222) exists to remove that copy, and
  the code cuts it before validation and before the set is used:
  `allOrders = slices.DeleteFunc(allOrders, isUnboundRigScoped)` (discovery.go:182).
- The live dispatcher is built from that filtered set
  (`scanOrderSetSnapshotFS` -> `ScanAll`, `cmd/gc/order_dispatch.go:407`), so the
  phantom is visited only during scan, where it re-emits the warning, and never
  enters the per-tick registration set `m.aa`.

So the phantom is a benign, already-handled scan artifact. Its only live cost is
a log-flood: the 1-minute rescan re-emits all six warnings to stderr every 60s
(`gc patrol: order scan: ...` x6/min in `~/.gc/supervisor.log`). A design or
rename change to the registration would not touch the stall.

## Root cause

Order firing is coupled, synchronously and under one city-wide lock, to the
latency of the per-rig Dolt stores. Read from the gascity source:

1. A single 30s-ticker goroutine drives dispatch. `orderDispatchLoop`
   (`cmd/gc/order_dispatch_loop.go:20`) calls `dispatchOrders`, which takes one
   lock for the whole pass — `cr.orderMu.Lock()` (`cmd/gc/city_runtime.go:1564`).
   Under that lock the pass also runs the 1-minute full rescan, the 30s
   tracking-sweep watchdog, and the 15-minute retention watchdog (deletes up to
   100 closed tracking beads via store subprocesses). Order evaluation and heavy
   store maintenance are serialized against each other.

2. Single-flight for each order is an open-work gate keyed on `ScopedName()`
   (`refinery-reconcile:rig:<rig>`), evaluated synchronously on the tick.
   `gateOpenWorkBounded` (`order_dispatch.go:2755`) walks the order's wisp
   tracking subtree via synchronous `bd` subprocesses against that order's store,
   bounded at 8s (`orderGateTimeout`, :2708). An order does not re-fire until its
   prior tracking bead closes — so its cadence is the tracking-bead lifetime, not
   its declared interval (this is the mechanism gc-uhrgn asked to have confirmed).

3. On a gate contention timeout, `gateFailClosed` (`order_dispatch.go:2818`) fails
   CLOSED for a non-idempotent order (skip) and fails OPEN only for idempotent
   ones (the vp-gprv / #2893 relief). All six stalling orders are
   `idempotent=false` (verified via `gc order show`), so the one escape from a
   contended single-flight gate does not cover them.

4. The per-rig stores are the ones under recurring write pressure. The supervisor
   log shows a mass prune of ~130-290 tracking-bead tombstones per rig store every
   ~15 minutes (13:08, 13:23, 13:38, 13:54Z on 2026-09-26); the finding's last
   detection at 13:38:18Z lands on the 13:38:34Z prune. The gc-toolkit store is
   the largest (1116 beads vs 27-157) and reconciles slowest.

City-scoped orders single-flight against the quiet city store and several are
idempotent, so they are insulated; the six non-idempotent rig-scoped orders
single-flight against the contended per-rig stores, so a store-contention window
suppresses exactly them across every rig at once. That is the observed
all-rig-but-not-city shape.

## What is proven vs what needs runtime instrumentation

Proven from the code and live state: the phantom drop (discovery.go:182); the
single 30s tick and city-wide `orderMu`; the synchronous per-order gate and its
non-idempotent fail-closed policy; that all six stalling orders are
non-idempotent; that `order.suppressed` fires (live, hourly, on
`feedback-distiller:rig:gc-toolkit`, which `gc order check` shows 166h overdue
against a 24h interval — a permanently suppressed non-idempotent order, i.e. a
live reproduction of the starvation); and the ~15-min prune cadence aligned with
the finding.

Not pinned, because it needs instrumentation only a gascity worker can add:
whether the many-consecutive-tick gate refusal during an acute episode is (a) the
gate genuinely seeing the prior tracking bead still open (a slow-to-close pass
plus a watchdog that clears only 4 beads / 30s — `orderTrackingSweepCloseBudget=4`),
or (b) the 8s gate timing out under Dolt contention and failing closed. No
gate-timeout stderr lines appear in `~/.gc/supervisor.log`, which argues for (a),
but the acute episodes are already pruned from the retained order history and
traces reachable from a gc-toolkit worktree. gc-q1ttz names the discriminating
trace to capture.

## Related cluster

- gc-uhrgn (p2): the chronic ~3m band this stall degrades from; it asked for the
  code-read pacing determination that this investigation supplies.
- gc-7s8mo (p1): the opposite failure of the same coupling — the flat 2m
  `orderTrackingSweepWatchdogStaleAfter` closes a tracking bead while its exec
  pass still runs, reopening single-flight and double-dispatching. A watchdog
  window too short for a long pass and a single-flight that starves when a bead
  stays open too long are two faces of "the tracking-bead lifecycle is the
  single-flight signal, coupled to a contendable store."

gc-q1ttz cross-references both and asks gascity to de-dupe or relate rather than
fix in isolation.

## Fix direction

The fix is a design that decouples order firing from per-rig store latency, not a
detector re-tune (an explicit constraint on the originating finding: do not lower
the finding's severity or widen its cadence, and a watchdog/self-heal is a
backstop only alongside the root-cause fix). gc-q1ttz records the candidate
directions: serve single-flight from the in-memory tracking index refreshed off
the critical path; give non-idempotent orders a starvation escape tied to the
tracking bead's age; move heavy store maintenance off `orderMu`; make the stale
close budget adaptive; and fix `feedback-distiller:rig:gc-toolkit`'s leaked wisp
subtree as the regression fixture.

## Why no gc-toolkit code change

The pack's order tomls are correct (`scope = "rig"` is right; the phantom is the
runtime's to drop, and it does). Nothing in the gc-toolkit pack calls the order
dispatcher, so there is no pack surface to defend with a backstop check. The
honest deliverable is the routed gascity bead plus this record. tk-5v3k5y carries
`gc.filed_as=gc-q1ttz`.
