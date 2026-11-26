---
name: A window for the Dolt GC that connected sessions block (tk-0bxcur0)
description: How fast the city's Dolt stores grow while no full GC can run, and the window with the city's writers stopped that this bead proposes for collecting them, for the operator to approve in its PR. Read it when building that window (tk-npkp7mk.2) or judging whether it is still needed.
---

# A window for the Dolt GC that connected sessions block

## The decision

Gas City's `gc dolt compact` runs no full GC on a store any session is
connected to. While the city runs, its supervisor keeps a session connected to
every store, so no full GC runs anywhere. This rig's store grows about
0.76 GiB a day as a result, and Gas City's compactor order fails every two
hours. This bead's change stops the pack's own daily pass from failing, and
nothing it changes collects a store. Collecting the stores takes a window in
which the city's writers are stopped. The proposal:

**Once a week at 16:00 UTC, stop the city, run Gas City's compaction and this
pack's reclaim with no session connected, and start the city again.** Gas
City's compactor order is turned off, so compaction runs only in the window.
Each window takes the city down for about five minutes. Every running agent
session stops, and each picks its work up again from its bead when it starts.

| Option | What stops | What the stores do |
|---|---|---|
| **Weekly window, Dolt's auto-GC left on (recommended)** | The city, about five minutes once a week | This rig's store grows up to about 5.3 GiB between windows. Dolt's auto-GC keeps trimming each store's journal with sessions connected, as Gas City ships it. |
| Daily window, auto-GC off | The city, about five minutes every day | No GC ever runs with a session connected, which is what Gas City's own config note asks of a city that keeps mail and wisps in `dolt_ignore`d tables. The HQ store's journal then grows untrimmed between windows, by 4 to 8 GB a day. |
| No window | Nothing | This rig's store keeps growing about 0.76 GiB a day and passes 20 GB, the size Gas City's bloat runbook lists as a symptom, in about three weeks. The compactor order keeps failing every two hours. |

The ruling this bead carries says nothing collects these stores until a
window is approved. Dolt's auto-GC is the exception: it is Gas City's default,
it collects each store's journal with sessions connected today, and this
change leaves it as it is. Gas City's note says auto-GC can lose `dolt_ignore`d
data. That is recorded upstream as tk-2h0yvep, and the daily option is the
choice that stops it here.

The operator approves the window in this PR. Merging it approves the
recommended option. To take another, say so on the PR, and this page changes to
it before the merge. The window's build is tk-npkp7mk.2, under The city runs
unattended. It waits on this bead and is held for placement.

## The window, step by step

1. Stop the city with `gc stop`. That stops the agents, the supervisor and the
   managed Dolt server, and waits up to the city's 60-second shutdown timeout.
2. Start only the Dolt server, with `gc dolt start`. No session connects.
3. Run Gas City's compaction, `gc dolt compact`. It flattens any store past its
   commit threshold and runs every pending full GC, which the live-session gate
   lets through with no session connected.
4. Run this pack's reclaim pass, `assets/scripts/dolt-reclaim.sh`, which runs
   `gc dolt compact --gc-only` on each store still over its 2 GiB line.
5. Start the city with `gc start`.

The window stops the supervisor that runs the city's orders, so it cannot be
an order. A job on the host's scheduler runs it, which makes it town setup.
Before building it, tk-npkp7mk.2 measures whether a suspended city leaves no
session connected to any store. If it does, the window can suspend the city
instead of stopping it.

**What a window costs, from what was measured.** The pack's whole daily pass,
both stores' full GCs included, took 31 to 49 seconds on 2026-11-21, 11-22 and
11-23, the last days its GCs ran. When the host restarted on 2026-11-26, the
city's controller was up about three minutes after the boot at about 06:08Z.
With the stop's 60 seconds, a window takes about five minutes, plus any flatten
compaction runs, which was not timed. What restarting every agent session
costs in plan usage was not measured either.

**When.** The city never goes quiet. Its event log from 2026-11-18 to
2026-11-26, about 690,000 events, counted by UTC hour, is quietest at 16:00 UTC
with 16,578 events and busiest at 02:00 UTC with 47,507. 16:00 UTC is 09:00 on
the host's clock (MST).

## How fast the stores grow

Each store was read at 2026-11-26T06:26Z with `du -sk` on its `.dolt/noms`
directory and on its `oldgen` subdirectory. Only a full GC rewrites `oldgen`,
so the files written there since a store's last full GC are what it gained
while none ran.

| Store | Size | In `oldgen` | Growth with no full GC |
|---|---|---|---|
| This rig's store (tk) | 4.17 GiB | 4.06 GiB | 0.76 GiB a day |
| The HQ store (lx) | 3.43 GiB | 0.06 GiB | Little: its `oldgen` is 0.06 GiB in all. Its size follows its journal through the day. |
| The other five stores | 0.15 to 0.79 GiB each | | All under the 2 GiB line |

**This rig's store.** Its last full GC wrote a 2,349 MiB `oldgen` file at
2026-11-23T21:37Z. The `oldgen` files written after it hold 762 MiB dated
2026-11-24, 724 MiB dated 2026-11-25 and 284 MiB dated 2026-11-26 up to 04:12Z.
That is 1,769 MiB in 54.6 hours, or 0.76 GiB a day. Between weekly windows it
gains about 5.3 GiB.

**The HQ store.** Almost all of it is one 3.44 GB table file written at
2026-11-26T06:11Z, three minutes after the host restarted, beside a journal that
grows between GCs. The journal grew from 144 MB at 06:26Z to 213 MB at 06:38Z,
about 0.35 GB an hour just after that restart, and the doctor's hourly readings
of the store on 2026-11-04 rose about 0.17 GB an hour. With auto-GC off, the
journal would grow 4 to 8 GB a day until a window. The store's size has not
climbed without a full GC: it read 3.69 GiB 90 minutes after its last one, on
2026-11-23, then 3.26 GiB at 2026-11-24T20:55Z and 3.43 GiB at
2026-11-26T06:26Z. So a window frees little here while auto-GC runs.

**What a full GC leaves.** The pass ran its full GCs daily up to 2026-11-23,
and both stores stayed over the line. A dry run about 90 minutes after the last
one read the HQ store at 3.69 GiB and this rig's at 2.60 GiB
(tk-0bxcur0's description), and this rig's store's last full GC left a
2.29 GiB `oldgen`. So a window brings this rig's store back to about 2.3 to
2.6 GiB, not under the line. A flatten since then may let the next full GC free
more, which was not measured. The doctor's `dolt-noms-size` warning stays
either way, and its own decision is tk-pado8uq, folded into tk-mecvxq2.1.

**What waits for a window now.** Gas City's compactor flattened four stores and
left a pending-GC marker on each, three at 2026-11-24T03:38Z and one at 07:39Z.
All four were still there at 2026-11-26T06:27Z. Each one is a full GC that the
compactor has skipped every two hours since then, and each skip fails the
order (tk-ascz5ab, which now waits on tk-npkp7mk.2).
