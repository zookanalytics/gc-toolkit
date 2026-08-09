---
name: Positive control for the deacon-wisp status-axis false-empty
description: Live capture proving the second false-empty in boot's deacon-wisp probe — a healthy deacon's freshly-poured patrol wisp sits in status=open across the burn/claim handoff window, so --status=in_progress returns [] for all four query sites in layered-startup-discovery-boot while the same queries with the filter dropped return the wisp seconds old.
date: 2026-08-09
work_bead: tk-qdhnd
predecessor: tk-jd4b8 (fixed the infra axis only, left the status filter in place)
related: tk-9m8k7 (assignee axis, out of scope), tk-a0mc6, tk-1waw2
---

# Positive control: the status-axis false-empty

tk-qdhnd's description and the mayor's dispatch note both make the same
demand, for the same reason:

> Verify with a positive control: run the corrected query against a deacon
> known to hold a live wisp and confirm a non-empty row before calling it
> fixed — an empty result is exactly the failure mode here, so an empty test
> proves nothing.

This is that capture. It is recorded here rather than left in the bead
because the evidence is transient by nature: the window it documents is a
few seconds wide, and the next reader who is tempted to "narrow" these
queries back down needs to see that the window is real and was measured.

## What the window is

The deacon burns its previous patrol wisp **before** claiming the next one.
Between those two writes the live wisp exists, is assigned to the deacon, and
is in status `open` — not `in_progress`. A probe filtered to
`--status=in_progress` reports `[]` for that whole span, and boot's own triage
table reads `[]` plus a quiet pane as "possibly stuck" (nudge) or "clearly
stuck" (file a warrant → dog pool → shutdown dance) against an agent that is
working normally.

This axis is independent of the ephemeral/`--include-infra` axis fixed in
tk-jd4b8. Each reproduces on its own.

## Capture

Town store (`/home/zook/loomington/.beads`), against `gc-toolkit.deacon` live
and patrolling. Sampled every 2s.

Transition across the burn/claim boundary — the old wisp disappears and the
new one appears already `open`:

```
04:55:37Z  corrected=[{"id":"lx-wisp-ej2g","status":"in_progress","updated_at":"04:50:47Z"}]  shipped=[{"id":"lx-wisp-ej2g","status":"in_progress"}]
04:55:41Z  corrected=[{"id":"lx-wisp-17k3","status":"open",       "updated_at":"04:55:37Z"}]  shipped=[]
```

At `04:55:41Z` the deacon held `lx-wisp-17k3`, poured 4 seconds earlier and
assigned to it. The shipped probe saw nothing.

All four sites corrected by this bead were then sampled together at
`04:56:14Z`, still inside the same window:

| Fragment site | Query form | Result |
|---|---|---|
| `:40` Step 2 wisp freshness | shipped (`--status=in_progress`) | `[]` |
| `:40` Step 2 wisp freshness | corrected (filter dropped) | `lx-wisp-17k3` `status=open` |
| `:46` Step 2 broad plate read | shipped | `[]` |
| `:46` Step 2 broad plate read | corrected | `lx-wisp-17k3` `status=open` |
| `:66` quick-ref, check deacon work | shipped | `[]` |
| `:66` quick-ref, check deacon work | corrected | `lx-wisp-17k3` `status=open` |
| `:67` quick-ref, patrol wisp (`--title`) | shipped | `[]` |
| `:67` quick-ref, patrol wisp (`--title`) | corrected | `lx-wisp-17k3` `status=open` |

Every site false-empties on the status axis alone, and every site is
non-empty once the filter is dropped. The assignee axis is clean throughout —
the wisp carried `assignee=gc-toolkit.deacon` the whole time, so nothing here
overlaps tk-9m8k7.

An earlier sample from the mayor's dispatch note (`04:42:45Z`,
`lx-wisp-7tz4`, `status=open`, assigned) shows the same window on a previous
cycle, so this is the normal shape of a patrol handoff and not a one-off.

## Why dropping the filter is safe

`bd list` already excludes closed rows unless `--all` is passed
(`--all  Show all issues including closed (overrides default filter)`).
Dropping `--status=in_progress` therefore widens the result to live rows —
`open` plus `in_progress` — and does **not** drag in burned patrol history.

Measured against the town store, which does hold closed patrol wisps for this
assignee, so the exclusion is doing real work rather than being vacuously
true:

| Query | `mol-deacon-patrol` rows |
|---|---|
| corrected (default filter) | 1 — the live wisp |
| corrected + `--all` | 3 — 1 `in_progress` + 2 `closed` |

The two closed rows are visible only under `--all`. The corrected query never
sees them.

That is what makes "read `.status` off the row" a complete replacement for the
server-side filter rather than a loosening of it.

## Scope note

Only the `layered-startup-discovery-boot` define was changed. The
deacon/refinery/witness defines in the same file also read
`--status=in_progress`, but those agents **claim** the wisp they find, so the
filter is plausibly deliberate there; their known gap is on the assignee axis
and is tracked separately as tk-9m8k7. Widening this fix into them would be
speculative.
