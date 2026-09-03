---
name: Deferred dispatch verification against the synthesis-bead repro
description: Measurements showing that an armed dispatch fires once the last blocker closes, run against the repro shape tk-gtgn0 filed, plus the one case the mechanism does not cover.
---

# Deferred dispatch, measured against the filed repro

tk-gtgn0 reported a synthesis bead that stayed unrouted for a day after
the last of its three blocking children closed, and asked for wiring
rather than a remembered workaround. The wiring is
`assets/scripts/deferred-dispatch.sh` and `orders/deferred-dispatch.toml`
(docs/deferred-dispatch.md). This pass measured whether it covers the
shape that was filed.

**Verdict.** It covers it. An armed bead whose blockers all close is
slung by the next reconcile pass, and `bd`'s readiness predicate holds a
bead until the last of N blockers closes. One case is not covered: a
blocker in another rig's store never holds the bead at all.

All measurements ran read-only against the live gc-toolkit store on
2026-09-03 between 01:54Z and 02:15Z. `bd` was v1.2.2 (`62d211937`).

## The cadence runs

`gc order list` registers `deferred-dispatch` at a 2m cooldown on
gascity, gc-toolkit, shutupandlisten and signal-loom.
`gc order history deferred-dispatch --limit 0` shows all four firing:
gc-toolkit passed at 01:41:07Z, 01:45:07Z, 01:47:36Z, 01:50:40Z,
01:53:35Z, 01:57:05Z, 01:59:37Z, 02:03:05Z, 02:05:40Z, 02:09:12Z and
02:11:34Z, a spacing of two to three and a half minutes.

`doctor/check-cadence-live` (I10) reports no finding against this order,
which is the stronger statement: the registration exists on every
importing rig and has fired within `max(3×interval, 15m)`. Its four
findings that pass name `feedback-distiller`, a separate condition the
hourly doctor sweep already carries.

`assets/scripts/deferred-dispatch.test.sh` passes 78/0 at
`7f6351a2`, including its positive control over the shipped order file.

## An armed dispatch fires when the blocker closes

Six beads in this store carry both an arm note and the disarm note the
reconcile pass writes when it performs the sling. For each, the blocker
open at arm time and the interval between that blocker closing and the
dispatch:

| bead | armed at | blocker | blocker closed | dispatched | latency |
|---|---|---|---|---|---|
| tk-q0ml23 | 2026-08-27T02:25:25Z | tk-s4fg87 | 2026-08-28T18:01:07Z | 2026-08-28T18:01:24Z | 17s |
| tk-uqolwg | 2026-09-02T19:27:46Z | tk-0iig96 | 2026-09-02T20:50:27Z | 2026-09-02T20:51:03Z | 36s |
| tk-edvlur | 2026-08-27T02:38:56Z | tk-jus6e4 | 2026-08-31T17:22:54Z | 2026-08-31T17:23:40Z | 46s |
| tk-gdtgvr | 2026-08-26T13:59:30Z | tk-xgm761 | 2026-08-26T18:09:53Z | 2026-08-26T18:11:25Z | 1m32s |
| tk-qs1j6 | 2026-08-27T02:27:21Z | tk-w26b6 | 2026-08-27T21:43:58Z | 2026-08-27T21:46:11Z | 2m13s |
| tk-nnx2gd | 2026-08-28T18:21:08Z | tk-lb3u4m | 2026-08-31T17:26:57Z | 2026-08-31T17:31:09Z | 4m12s |

Each row is a single-blocker case at dispatch time: every other `blocks`
edge these beads carry was created after the dispatch stamp, so none of
them was open when the pass ran. Five of six dispatched inside one
declared cooldown and the sixth inside two.

The longest hold is the one that answers the filed report directly.
tk-edvlur sat armed for four days and fifteen hours with nobody holding
it, and went out forty-six seconds after its blocker closed. The bug
described eighteen hours of sitting and counting.

The arms come from three different callers: `gc-toolkit.mechanik`,
`gc-toolkit/gc-toolkit.nux`, and a polecat pool session. Eight more
beads carry a live arm to the polecat pool right now, all waiting on a
blocker.

## The last of N blockers is what releases the bead

The script never enumerates blockers. It asks
`bd list --has-metadata-key gc.dispatch_when_ready --ready`, so whether
N children all have to close is `bd`'s predicate to answer, not this
script's. Asked of the live store, it answers correctly.

Over every open gc-toolkit bead carrying at least one `blocks` edge, 180
of 181 are classified by `bd list --ready` exactly as their blockers'
statuses predict: 25 with every blocker closed are ready, 155 with at
least one blocker still open are not. The listing and the ready query
were taken thirteen seconds apart to keep a busy store from drifting
between them.

Restricted to the beads whose shape matches the report, three or more
blockers, the separation is 24 of 24 with no exception. The two extremes
carry the argument on their own:

- tk-xgfhj3 has 17 blockers, all closed, and is ready.
- tk-1tb5t0 has 18 blockers, exactly one still open, and is not ready.

tk-qf055w (12 blockers, one open) and tk-utjreo (14 blockers, one open)
are held the same way. A partially closed set does not release the bead,
and the pass re-asks every two minutes rather than deciding once, so
hypothesis 3 in the report is answered as well.

## The reset-safety worry

The report's Source section asks whether a fresh mechanik would know to
do this without being told. It reads it in its own prompt.
`template-fragments/watch-dispatched-work.template.md` names
`deferred-dispatch.sh arm` as the way to record sequencing, and both
`agents/mechanik/prompt.template.md` and
`packs/gascity-keeper/agents/keeper/prompt.template.md` include it. The
rendered copies at `generated/seed-audit/agents/mechanik.md` and
`generated/seed-audit/agents/keeper.md` carry it.

## Hypotheses in the report

Hypothesis 4 was closest and generalizes past its own wording. Dispatch
is not event-driven on readiness for any bead. `gc sling` reads no
`blocks` deps at all (docs/gascity-routing-model.md), so an unrouted
ready bead is the backlog's resting state rather than a fault, and the
synthesis bead was never selected against. Hypotheses 1 through 3 are
superseded: no type, title, label or parent rule discriminates here.

## What is not covered

A blocker in another rig's store does not hold an armed dispatch, because
`bd` resolves dependency ids within one store. Live in this store,
tk-x2tw7 carries a `blocks` edge to `sl-kg9z6`, which is open in
signal-loom:

- `gc bd list --id tk-x2tw7 --json` renders the edge.
- `gc bd show tk-x2tw7 --json` returns `dependencies: null`.
- `gc bd blocked` does not list it.
- `gc bd list --ready` does list it.

So an arm on that bead would be slung by the next pass with its blocker
still open, and `arm`'s own hint would say "no open blocker right now"
while printing it. This is the single exception in the 181-bead
measurement above. The population is small today: two open beads in this
store name a blocker absent from it, tk-x2tw7 and tk-4gzw7o, and
tk-4gzw7o is held anyway by two in-store blockers.

The same-store limit is the hold doctrine's, stated as I1 in
docs/component-model.md and checked by `doctor/check-wait-is-an-edge` for
beads carrying a hold marker. What is missing is that `arm` inherits it
silently. Tracked on tk-6shsru.

## Re-running this

```bash
export GC_RIG_ROOT=/path/to/rigs/gc-toolkit
gc order list                                   # registration per rig
gc order history deferred-dispatch --limit 0    # passes actually fired
assets/scripts/deferred-dispatch.sh list        # what is armed now
bash assets/scripts/deferred-dispatch.test.sh   # hermetic suite
bash doctor/check-cadence-live/run.sh           # I10
```

The two live tables come from one `gc bd list --all --json --limit 0`
and one `gc bd list --ready --json --limit 0`, taken together, joined on
each bead's `blocks` edges. Re-verify any bead that lands on the wrong
side before believing it: graph.v2 step beads close within seconds and a
stale snapshot manufactures exceptions, which is what four of the five
first-pass outliers turned out to be.
