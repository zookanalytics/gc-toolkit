---
name: The gc-toolkit merge-cadence false alarm
description: tk-fdstg reported that the refinery-reconcile order had never fired on gc-toolkit. It had been firing in lockstep with the other three rigs since the order's first tick. What was actually wrong, why the triage surface said otherwise, and what shipped so neither the outage nor the false report can be silent again.
---

# The gc-toolkit merge-cadence false alarm

## Scope

**Mandate.** The determination for tk-fdstg: what was measured, what the
reported defect turned out to be, and why the pack-side deliverable is a
detector rather than a fix to the cadence.

**Boundaries.** It does not restate what the cadence is or how it is
guaranteed — [docs/refinery-merge-cadence.md](../../docs/refinery-merge-cadence.md)
owns that, and is where the durable half of this work landed. The daemon this
order replaced is history, kept as history, in
[specs/tk-agzpl/refinery-idle-driver-liveness.md](../tk-agzpl/refinery-idle-driver-liveness.md);
the decision to relocate it is in
[specs/tk-d83wm/exec-order-cadence.md](../tk-d83wm/exec-order-cadence.md).

## Verdict: the reported defect was not happening

tk-fdstg (P1) reported that `refinery-reconcile` "has NEVER fired on
gc-toolkit", that "zero tracking beads have ever existed" for it, and that the
rig was covered only by the retired `/tmp` idle driver.

Every part of that is false. gc-toolkit's registration fired from the order's
very first tick, at the same second as gascity's, and had not missed one since.

Pass logs at 2026-08-20T08:28:32Z — `<GC_PACK_STATE_DIR>/refinery-reconcile/<rig>/pass.log`,
one `=== <ts> rig=<rig> …` header per completed pass, and not subject to bead
retention:

| rig | passes | first | last |
|---|---|---|---|
| gascity | 20 | 06:44:20Z | 08:26:53Z |
| **gc-toolkit** | **19** | **06:44:20Z** | **08:19:23Z** |
| shutupandlisten | 18 | 06:45:18Z | 08:21:00Z |
| signal-loom | 18 | 06:45:18Z | 08:21:00Z |

Tracking beads agree. They are **wisps**, not issues, so they are absent from
`bd list`; read through the control plane they are all there:

```
$ gc order history refinery-reconcile --limit 0 | awk 'NR>1{print $2}' | sort | uniq -c
     11 gascity
     11 gc-toolkit
     10 shutupandlisten
     10 signal-loom
```

The bead was filed at 08:07:38Z. gc-toolkit's tracking bead `tk-wisp-7jy` was
created at 08:05:37Z and closed at 08:06:10Z — the premise was already false at
the moment of filing, and had been false for the preceding hour and a half.

## What was actually wrong

The bead's second clause was right, and it was the whole defect: the mayor's
`gc-refinery-idle-gc-toolkit.service` was still running, pid 1553610, up 24h.
Three rigs' drivers were retired on 2026-08-19 once their orders were confirmed
firing; gc-toolkit's was deliberately kept as a safety net, and stayed.

So the rig that owns this pack and carries most of the city's PR traffic was
running **two** `merge-skill.sh` writers against the same anchors:

- the order, single-flighted by the controller's tracking-bead gate on
  `ScopedName()` = `refinery-reconcile:rig:gc-toolkit`;
- a daemon holding `flock` on `/tmp/gc-refinery-idle-gc-toolkit/lock`, which
  that gate cannot see.

Both ran the same seven passes in the same order — the runner is a faithful
relocation of the daemon's `run_passes()`. That is what made the duplication
survivable and invisible for a day, and it is also why retiring the daemon costs
nothing: the order already does all of it.

The unit was stopped at 2026-08-20T08:27:33Z. It was transient
(`systemd-run --user`), so stopping it removes it, and nothing in the pack arms
a replacement — a concept sweep for `idle-loop`, `gc-refinery-idle`,
`systemd-run` and `systemctl --user` finds only history: this order's own
header, the two spec files above, and prose in `mol-refinery-patrol.toml` that
already tells the refinery agent not to drive the cadence itself.

Note what is *not* evidence of a driver: `/tmp/gc-refinery-idle-<rig>/`
directories still exist for all four rigs, lock files and all. Only a process
counts. Reading an idle directory as "armed" is the confusion catalogued in
tk-agzpl, where a lock file reported a driver that had been dead for hours.

## Why the triage surface said otherwise

`gc order history <name>` is store-complete **only** when the read is unbounded.
Any positive `--limit` returns runs from the city store alone — and prints them
under a `RIG` column, so a single-rig answer looks city-wide. Measured on this
city, 43 retained runs across four rigs:

| invocation | rigs returned |
|---|---|
| `--limit 40` | gascity only |
| `--limit 100` (more than the rows that exist) | gascity only |
| `--since 20m` (default limit 50) | gascity only |
| `--since 20m --limit 100` | gascity only |
| `--rig gc-toolkit --limit 40` | gc-toolkit (11 runs) |
| **`--limit 0`** | **all four** |
| **`--since 20m --limit 0`** | **all four** |

A limit of 100 against 43 rows still truncating to one rig rules out an
exhausted budget: the bounded and unbounded reads are different code paths, and
only the unbounded one fans out across stores. The city store happens to be
gascity's, so the bounded read always answers "gascity" — which reads as *the
one rig that works* rather than *the only rig I looked at*.

The command's own help steers into it: "prefer keeping a bound when triaging."
For an order whose registrations are per rig, triage is precisely when that
recommendation costs you the answer.

That is enough to explain a P1 filed in good faith. The reporter did the right
things — checked `gc order list`, ruled out overrides, ruled out suspension,
ruled out the dispatcher being down, and said which check they distrusted — and
still landed on an inverted conclusion, because every surface they could reach
either under-reported or (for `bd list`, which does not enumerate wisps) reported
nothing at all.

## What shipped

**`doctor/check-refinery-merge-cadence/`** — the detector that was missing. The
order's own header says that when the cadence stops, approved pull requests sit
unlanded "and nothing reports it". That was literally true. The check asserts,
per rig:

1. every rig importing this pack has a `refinery-reconcile` registration —
   `gc order list` omits disabled orders, so a clock switched off in city.toml
   presents here as a missing one, which is the right thing to say about it;
2. every registered, non-suspended rig has run it inside a window (15m by
   default). One rig stale while others are fresh is reported differently from
   every rig stale: the first proves the controller is up and the fault is
   rig-scoped, the second is the city-wide outage;
3. no out-of-band `idle-loop.sh` is running — a second merge-skill writer the
   controller cannot serialise.

It reads history with `--since <window> --limit 0`, and `run.test.sh` asserts
that `--limit 0` is present. That assertion is the point: a future reader
tidying the call into a bounded read would rebuild this bead's blind spot inside
the check written to prevent it.

Both the outage and its inverse are now cheap. A stopped cadence is a doctor
error naming the rig; a *claim* of a stopped cadence is one `gc doctor` run away
from being confirmed or dismissed, instead of an afternoon of store archaeology.

## Split out to the gascity repo

The binary-side fixes are not in this pack — `gc` is built from the gascity rig
— so they are filed there and the pack ships the detector that works regardless
of when they land:

- **`gc order history` bounded reads are not store-complete** (gascity **gc-6a6vz**, P1). The fix is to
  make the bounded path fan out over the same stores the unbounded path does,
  merging by `executed` before applying the limit. Until then, `--limit 0` is
  the only correct invocation, which is why the check and the docs both pin it.
- **Cooldown orders fire far slower than their declared interval** (gascity **gc-uhrgn**, P2). Measured
  over the same 20 minutes: `gate-sweep` (declared 30s) 6 runs, `dolt-health`
  (30s) 5, `order-tracking-sweep` (1m) 6, `boot-health` (2m) 5,
  `refinery-reconcile` (60s) 5. Every cooldown order lands near one run per
  3–4 minutes regardless of what it asks for, which points at the dispatcher's
  own tick rather than at any order's configuration.

The second one is why this check's staleness window is 15 minutes and not, as
the declared interval would suggest, two or three. A window sized to the
declared 60s would flag every rig in the city continuously. When the dispatcher
honours the declared interval, the window can tighten — it is a single env-
overridable constant, `GC_DOCTOR_MERGE_CADENCE_WINDOW`.
