---
name: Design note — surfacing a stalled pre-open codex-gate anchor on the board
description: Why the board's stall signal fires on the bare pre_open_gate+codex shape rather than the whole population, why it reads live-worker liveness instead of routed-ness, why the threshold is three days, and how the target population had shrunk from the census by build time.
---

# A held gate the board could not tell from a working one

Work record for `tk-ju4jfy`, the visibility half of the pre-open codex-gate
invisibility (subject `tk-7i77rv`, operator ruling in visit `tk-6g99sp`,
2026-09-14). The authoritative behaviour lives in `services/helm/README.md`
(*Stalled at the pre-open codex gate*); this note records the reasoning, the
census drift that narrowed the target, and the one discrimination the signal
turns on.

## What was funded

The operator approved a staleness-fired board/dashboard signal for a genuinely
stalled pre-open codex-gate anchor — past a threshold, no live review, no
in-flight rework — that names the gate, the age, and the reason. The root cause
(why anchors stall after review, and why no codex pool runs) is a separate bead,
`tk-w73r2q`; this bead is visibility only.

## The census had already drifted

The subject's census (2026-09-12) found 17 anchors at `merge_result=pre_open_gate`
with `check_set=codex`, all mis-framed as routine and banded `LOW`. By build time
(2026-09-14) the live store held 18, and the shape had moved: 15 now carried
`pr.machine=wedged-exception` + `gc.routed_to=human` + a `gc.takeaway` +
`merge_hold=signoff_cap`. The refinery's convergence cap had parked them, and that
park is already surfaced — a human-routed anchor bands `ELEVATED` and is `owed`,
and its `needs` reads the wedge sentence. One more (`tk-iunfnh`) carried a takeaway
and rendered through the parked/disposition path.

So the genuinely invisible population was two anchors, not seventeen:
`tk-9ntg93` (a stale `progressing` marker, an open **unrouted** rework child) and
`tk-or0ha2` (no machine axis, no review ever run). Both are the shape the design
lever names exactly — "the pre_open_gate-and-not-green shape [that] has no owed
cause today". The signal targets that shape and defers to every stronger
surfacing (wedge, disposition, takeaway, human route), so it neither double-names
the 15 parked rows nor competes with the disposition path.

Live render on 2026-09-14 confirms it: `tk-9ntg93` and four gascity anchors
(`gc-1fke8`, `gc-vveco`, `gc-blaw4`, `gc-l1l06` — the board is city-wide) now band
`ELEVATED`, are owed, carry "owed 3d", and read the codex-gate NEEDS; the 15
signoff-cap and ruled rows keep their own framing untouched.

`tk-or0ha2` is the one named target that does NOT surface, and correctly. It is
the sole `pre_open_gate` anchor left at status `in_progress` — the refinery never
re-parked it to `open` — and the board gathers merge anchors at status `open`
only. That stuck status is itself the post-review-progression failure the
root-cause bead (`tk-w73r2q`) owns; widening the board's gather to `in_progress`
for one anomalous bead would risk pulling genuinely in-flight work onto the board,
so the derivation surfaces it once the root cause re-parks it.

## The lever: an owed cause in the board derivation

Of the levers offered, this is the board one: a new owed cause in
`services/helm/internal/board/derive.go`. It is the single change that reaches
both live renderers — the `helm-svc board` CLI and the web dashboard share one
model, and the signal reuses existing `Tile` fields (`Severity`, `Owed`,
`PROwedSince`, `Needs`, `Frontier`), so nothing new crosses the wire and the
TypeScript frontend needs no change. `assets/scripts/liveness-sweep.sh` is a
separate escalation surface, not a board renderer; it is left to its own track.

## The discrimination that matters: live, not routed

`pr_machine` already reads an anchor with an open pool-routed blocker as
`progressing`, which renders "in the merge cadence" — an agent has it. That read
is liveness-blind: it turns on the route, not on whether any session is draining
the pool. When no codex pool runs, a review routed to `polecat-codex` sits
unclaimed and the anchor reads "in the merge cadence" while nothing reviews it.
That is the mis-framing.

So the stall's suppression turns on a **live worker**, not a route: an open
pool-routed blocker suppresses the signal only when `ownerLive(assignee)` or
`wfLive(id)` holds. A routed-but-unclaimed review is not a healthy hold — it is
the stall. `Blocker` gains an `Assignee` (gather-side only, it never crosses the
wire) so the derivation can ask. `TestPreOpenCodexGateLiveVsDeadReview` is the
paired control: two anchors identical but for the session state behind one routed
review, both reading `progressing`, splitting on liveness alone — one "in the
merge cadence", the other the stall.

Failing loud is deliberate and matches the board's own posture (`WaitingUnknown`,
`pr_machine=unknown`): when liveness cannot be confirmed the signal fires rather
than assuming a review is live, because a false "in flight" is the one lie a board
whose job is to say what needs a human must not tell.

## The threshold, the age, the reason

Three days (`preOpenStaleThresholdDays`). The census floor: 13 of the 17 were
untouched more than three days, and below that a hold is still plausibly fresh. It
is far tighter than the 14-day `staleThresholdDays`, which stale-bumps an already-
`NORMAL` row; a childless pre-open gate bands `LOW` and never reaches that bump.

The age is the anchor's own `updated_at`, carried on the owed clock
(`pr_owed_since`) and rendered by the frontier as "owed Nd". This is
self-consistent: the signal fires only once `updated_at` is old, and a genuinely
stalled anchor is written by nothing, so its last-touch instant is when it went
quiet. An anchor a reconcile pass still writes is fresh and never reaches the
threshold — the correct non-fire.

The reason (`no review has run` / `findings open` / `reviewed, not advanced`) is a
best-effort read of the blocker titles the cadence writes ("Review branch …",
"Rework branch …"). It is a NEEDS hint, so it degrades to never-reviewed rather
than guessing when a title does not match.

## Deliberately not done

- **`liveness-sweep.sh`.** A separate surface, offered as an "and/or". The board
  lever covers the acceptance (a board/dashboard row) for both renderers; the
  sweep is its own track.
- **Naming whether a codex pool runs.** A global fact, not a per-anchor one, and
  closer to the root-cause bead's concern than this visibility one. The
  per-anchor liveness check already answers "is anything moving THIS row", which
  is what the row can act on.
- **Re-sectioning.** A stalled anchor is still a merge anchor, so it reads in the
  `review` band beside the wedged pre-open rows rather than moving to `stalled`.
  Splitting the pre-open population across two sections by liveness would be less
  legible than one band the operator already reads for pull requests.
