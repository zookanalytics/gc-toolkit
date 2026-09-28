---
title: Blocked-on-human frontier is not "working"; surface the attention type
bead: tk-0kc9l1
convoy: tk-x4oc74
status: implementation
author: gc-toolkit.polecat
date: 2026-09-28
---

# Blocked-on-human frontier is not "working"; surface the attention type

Implements design.md section B on branch `integration/review-engagement`.

## The two defects

1. A `blocked` in-flight child counts toward `working`. The label derivation
   (`services/gctk/prstatus`) counts the whole `anchor_bead` in-flight set,
   `blocked` included, and any non-empty set returns `working`. A frontier that
   is blocked — including blocked on a human — is not the city holding the ball.

2. The board phase chip re-derives the taxonomy in `services/helm`
   (`board.prPhase`) instead of consuming `prstatus.Derive`, and it counts a
   narrower set (open/in_progress rework children only). So the label and the
   board disagree for the same PR, against the "one code path" claim at
   `prstatus.go:5-7` and `cli/prstatus.go:21-23`.

## The fix

`prstatus.Derive` is the single authority. It gains the blocked-frontier rule
and returns an attention reason; the board consumes it directly.

### prstatus.Derive (services/gctk/prstatus)

- `Facts.InFlightCount` splits into `InFlightActive` (progressing members) and
  `InFlightBlocked` (members whose status is `blocked`), plus `HumanVisitAwaits`
  (an open human visit holds the anchor).
- `Derive` returns `(State, Reason)`. Reason names the needs-attention cause:
  `cap-park`, `merge-hold`, `rebase-hold`, `approved-wedged`, `visit-engage`,
  `stall`; empty otherwise.
- New rule, ordered after the holds and before the working arm: a frontier that
  is entirely blocked (`InFlightActive == 0 && InFlightBlocked > 0`) is
  `needs-attention` — `visit-engage` when a human visit awaits, else `stall`.
- The existing working arm becomes `InFlightActive > 0`, so a blocked-only set
  no longer reads working while an active member still does.

### The label (services/gctk/internal/cli/prstatus.go)

Splits the `anchor_bead` in-flight rows by status into active/blocked and calls
the new `Derive`. The label is coarse (state only); it leaves `HumanVisitAwaits`
false and ignores the reason — the reason is the board's to render, and the
state is `needs-attention` for a blocked frontier regardless.

### The board (services/helm)

- `helm` requires `services/gctk` (replace `../gctk`) so `board` imports
  `prstatus` — the one code path the doc already claims.
- `board.prPhase` deletes its duplicate switch and calls `prstatus.Derive`,
  returning phase and attention. `Tile.PRAttention` carries the reason.
- The board's in-flight membership now matches the label's: `Facts.PRInflight`
  maps each anchor id to its active/blocked counts, gathered in
  `source/beads.go` by one bulk query per rig (`HasMetadataKey: anchor_bead`
  over open/in_progress/blocked/deferred/hooked/pinned — the same population the
  label's `--metadata-field anchor_bead=… --status …` query selects).
- `HumanVisitAwaits` = `Facts.Visits[anchor]` (an open visit names the anchor in
  `gc.continuation_group`), the board's existing "held by a conversation" signal.

## Agreement test

A Go test builds one set of `Facts` and asserts `prstatus.Derive` gives the
phase both consumers read, exercising the blocked-frontier + visit/stall cases.
Because the board calls `Derive`, label and board share the function and cannot
disagree on the phase. `pr-status-label.test.sh` adds the blocked-frontier cases
to the shell acceptance bar.
