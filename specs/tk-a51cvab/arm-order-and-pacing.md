---
name: Merge-cadence arm order and pacing (tk-a51cvab)
description: Why gc-toolkit's refinery-reconcile passes stopped landing and opening PRs on 2026-10-04/05, the measurement that attributes it to the gating-set size, and the reorder plus per-arm budgets chosen to keep merge and pr-open running. Read it before changing the arm order or the arm budgets.
---

# Merge-cadence arm order and pacing

## What was measured

Sources: `<GC_PACK_STATE_DIR>/refinery-reconcile/gc-toolkit/pass.log` (12,411
lines; no pass had reached `END` since 2026-10-03T01:20:23Z, so the log was
never trimmed and held every pass back to 2026-10-02T18:30Z), the city event
log and its archives from 2026-10-04T00:07Z, a live sample of the 14:03:09Z pass
on 2026-10-05, and the bead store at 14:13Z.

### Per-arm time, live

The 2026-10-05T14:03:09Z pass was the first under the 1800s city override. A
2-second sampler of the driver's process tree timed it:

| Arm | Start | Duration | Set it walked |
|---|---|---|---|
| (1) gate-ensure | 14:03:16 | 767s | 90 gating anchors, about 8.5s each |
| (2) pr-posture | 14:16:03 | 160s | 33 PR anchors, about 4.8s each |
| (3) pr-feedback | 14:18:43 | 243s | 33 PR anchors, about 7.4s each |
| (4) merge | 14:22:48 | killed at 621s | 26 of 33 PR anchors, about 24s each; landed PR #1013 |

Arms 1 to 3 took 1170s together. The controller killed the pass at its 1800s
limit inside merge, so pr-open did not run on this pass either.

### The gating set

At 14:13Z the rig had 90 open gating anchors: 57 at `pre_open_gate` and 33 at
`pull_request`, on an 8-CPU host at load average 21. gate-ensure's machine axis
called 65 of them `settled`: 41 pre-open anchors that only pr-open can move,
and 24 PR anchors waiting on approval or merge.

Replaying every `merge_result` change in the event log gives the set's size
over the window (a lower bound early on, since an anchor that never changed
appears only from its first event; the replay ends at the live 90):

| Time (UTC) | 10-04 00h | 12h | 17h | 20h | 23h | 10-05 03h | 04h onward |
|---|---|---|---|---|---|---|---|
| Gating anchors | 27 | 37 | 48 | 53 | 64 | 82 | 88-91 |

Anchors kept arriving from new work at one to nine an hour. Twelve left the set
in the whole window, so outflow had nearly stopped.

### Rate against size

For the 54 passes from 2026-10-04T12Z on whose gate-ensure end could be
bracketed by the `SKIPPED ... <n>s elapsed` lines around it, gate-ensure's
duration divided by the set size at that hour:

| Set size | Passes | Mean size | Mean gate-ensure | Seconds per anchor |
|---|---|---|---|---|
| under 45 | 18 | 39.7 | 367s | 9.2 |
| 45 to 69 | 22 | 55.8 | 569s | 10.2 |
| 70 and over | 14 | 87.6 | 688s | 7.9 |

The bracket is coarse (about ±100s), and passes killed inside gate-ensure
cannot be bracketed, which biases the top row low. The live 8.5s per anchor
agrees with the table.

## Cause

The anchor count made arms 1 to 3 slow, not a rise in per-call cost. The
per-anchor rate stayed between about 8 and 10 seconds across the window while
the set grew from about 37 to about 90, and gate-ensure's duration grew with
the set. Host load sets that rate. It did not move.

The growth fed itself. gate-ensure walks the whole gating set and arms 2 and 3
walk its PR anchors, and merge and pr-open ran behind all three. Once the set passed about 50 anchors (around 20Z on
10-04), arms 1 to 3 alone outran the 900s timeout, so merge and pr-open stopped
running. Work kept arriving and nothing landed, so the set kept growing and
arms 1 to 3 got slower still.

## What changed, and why

Arm order is now posture, merge, pr-open, pr-feedback, pre-open-rebase,
gate-ensure, pr-facts, then the sweeps and pr-stack.

- **Posture stays ahead of merge.** merge.sh reads `pr_posture` off the bead
  and never asks GitHub, so the posture must be written in the same pass. It
  is merge's only same-pass interlock, and running it immediately before merge
  narrows the window in which a new comment goes unseen.
- **gate-ensure moved behind merge and pr-open.** Neither needs anything it
  writes in the same pass. merge.sh and pr-open.sh each hold an anchor whose
  `check_set` is empty on their own read, so the rc=3 hold that used to sit
  between gate-ensure and merge guarded nothing those reads did not already
  guard. gate-ensure's other writes, a dispatch onto a lane already short of
  green and the close of a must-fix finding whose fix landed, can delay a
  landing or an open by one pass but never allow one early.
- **pr-feedback moved behind pr-open.** Its rc never held anything, and merge
  already holds on the `commented@` posture it would route.
- **Every arm that walks a set growing with the queue shares one pass budget**
  (`REFINERY_RECONCILE_PASS_BUDGET_SECS`, 420s by default, below the 600s
  timeout). That is merge's non-landable PRs, pr-open, pr-feedback,
  pre-open-rebase, gate-ensure, pr-facts and pr-stack. Each arm's deadline is
  an equal share of what the budget has left when it starts, never under a 20s
  floor. Past it the arm starts no new anchor, and a cursor (pace-lib.sh)
  resumes it in id order after the last anchor it finished. An arm that
  finishes early leaves its time to the arms behind it, every arm runs on
  every pass, and a pass stays short, so merge comes round again sooner.
  Without the cursor, a stopped walk that restarted at the same anchor would
  starve the tail of its list.
- **merge visits the PRs that could land first and never paces them.** The
  live sample showed merge's own cost (about 24s per PR) would otherwise keep
  pr-open behind it and cut merge off at the same PR every pass. One paginated
  GraphQL read (about 2s for 106 open PRs) lists each open PR's draft flag,
  head, and every account's latest APPROVED or CHANGES_REQUESTED review. A PR
  is paced only when that read, its anchor row, or the merge state the posture
  arm recorded at its live head this pass rules its merge out: a draft,
  `merge_hold`, an unanswered-comment posture, an empty `check_set`, a veto or
  no approval under merge.sh's own approval rule, or a recorded state other
  than CLEAN, UNSTABLE or UNKNOWN. PRs that left the open list (they owe a
  record) are never paced either. The rest only refresh a verdict, so they
  rotate.
- **pr-open visits first the anchors gate-ensure last marked settled whose
  rows carry no hold pr-open applies** (`merge_hold`, `rebase_hold`, an empty
  `check_set`), then the rest, with one of each visited every pass. An anchor
  it opens leaves its set, so a pass the budget stops still opened what it
  reached. gate-ensure settles a green anchor whatever holds it: at
  2026-10-05T17:00Z two of the four settled pre-open anchors carried an
  operator's `merge_hold`. Each group rotates on its own cursor, because a
  first-group anchor pr-open still holds (a PR a human closed at this head) would
  otherwise lead every pass while the anchors behind it were never reached.
- **pass.log carries each arm's start time, its elapsed seconds and rc, the
  pass's total, and how much of its set each paced arm covered.** A slowdown
  is then visible as a duration and a set size before it stops landing.

## The mechanik note (2026-10-05T14:35Z)

Two measurements were added to the bead after this work began.

- **Landing is one PR per pass.** After a squash, GitHub reads the sibling PRs
  as `UNKNOWN` until something asks again, and merge held them. tk-moje52c
  re-reads an `UNKNOWN` merge state inside the merge arm, which is the direct
  fix. Here, an approved `UNKNOWN` PR counts as landable, so it is visited
  first rather than paced, and the pass budget keeps passes short, so merge
  runs again sooner.
- **pr-facts starved too** (its red-required-check auto-fix sat unrun from
  2026-10-04T22:33Z). Every walking arm now shares the pass budget, so pr-facts
  and the arms behind it run on every pass, however slow the arms ahead of
  them are.

## Code review round (2026-10-06)

A code review of the PR at 8baf31ed raised seven findings. Each one changed the
branch:

- **merge's landing group keyed an uncomputed merge state on `reviewDecision`**,
  which GitHub leaves empty on a base that requires no approving review. The
  group now reads approval from the reviews themselves, under the rule the
  merge applies (one jq definition, `REVIEW_VERDICT_DEF`, serves both). The
  `gh pr list` that read the merge state also failed: at 106 open PRs on
  2026-10-06 it returned HTTP 502 after about 11s on every try, because GitHub
  computes each PR's merge state on request, so the arm ran unpaced. 30 PRs
  took 5.5s. The read now asks for no merge state and takes about 2s, and the
  merge state comes from the posture arm's per-PR record instead.
- **The landing group held PRs merge always refuses** (an operator's hold, an
  unanswered-comment posture, no approval). It now drops every PR that a
  check readable without a per-PR call already holds. An UNSTABLE PR with a
  red required check stays in it, because naming one takes the required-check
  set and the PR's check rollup.
- **pr-facts' write-back sweep ignored the deadline.** It now runs under the
  walk's deadline on a cursor of its own (`<cursor>.writeback`).
- **A walk past its deadline could spend its one guaranteed visit on an anchor
  it then skipped for free.** Every arm now calls `pace_visit` after its free
  skips, and pace-lib.sh says so.
- **pr-open's first group admitted settled anchors pr-open holds.** It now
  excludes the holds pr-open reads off the row. A lane short of green already
  keeps an anchor out of it, because gate-ensure records such an anchor
  `progressing`. A lane whose derivation could not be read is the exception:
  it can still record `settled`, which tk-p19c3r0 tracks.
- **The driver divided the budget by a hand-kept arm count.** `PACED_ARMS` now
  lists the paced arms, each call takes its arm off the list, and a test checks
  the calls against it.
- **The `--deadline` check was copied into six scripts.** `pace_start` makes it
  for every walk.

#1008 landed while this round was in progress. Since then merge.sh hands its
arguments to `gctk merge`, the Go port, whenever a current binary is deployed,
and keeps its shell body as the fallback. The Go port reads no arguments, so
on that path the merge arm would run unpaced and in enumeration order.
tk-eku5dvv tracks bringing this branch current and porting the pacing and the
visit order into the Go path. It blocks the anchor, so #1077 cannot land
without the port.

## The gctk merge port (2026-10-07)

tk-eku5dvv merged main in at 4c9fbef6 and ported the merge arm's pacing and
visit order into `gctk merge` (services/gctk/internal/cli/merge.go, with the
rotation in pace.go). The binary now takes `--deadline` and `--cursor`, sends
the same GraphQL read of the open PRs, puts the same anchors first under the
same approval rule, and paces the rest through pace-lib.sh's rotation: id order
after the cursor, wrapping, an anchor recorded once the next visit begins, and
one paced anchor visited even past the deadline. It prints the same visit
summary.

merge.test.sh's pacing cases had been appended after `suite()`, so after the
merge they ran once, on the gctk arm, where 19 of their 29 assertions failed.
They now sit inside `suite()`, so both arms run them. Their PR numbers moved to
231-293, so no fixture they write is read by another case when the next arm
runs the suite. The Go tests cover what that suite does not reach: an open-PR
stream that breaks partway, a page with no pullRequests, and a cursor that
cannot be written.

Main then moved to 92893140 with #1076 (tk-moje52c), which reads an `UNKNOWN`
merge state again inside the merge arm, in merge.sh and in gctk merge alike.
tk-eku5dvv's self-review merged it in at eda53752, and neither change needed
adapting to the other. The re-read runs at the CLEAN check, the merge's last
validation, so an anchor reaches it in whichever group the visit order put it,
and the order already counts a recorded `UNKNOWN` as landable. The conflicts
were two places where both sides added lines: the field initializer in
`Merge()` and the end of merge.test.sh's `suite()`. The merge kept every line,
with main's re-read cases ahead of the pacing cases. Their PR numbers (150-163)
do not overlap the pacing cases' (231-293). The re-read waits at most ten
seconds a pass at the defaults, which adds to the pass-length estimate under
"For the city override's release".

## Considered and not done

- **Bounding the posture arm.** It is the one arm left ahead of merge whose
  cost grows with the PR set (160s at 33 PRs). A budget there needs merge.sh to
  hold only the anchors whose posture this pass did not make current, instead
  of holding the whole merge arm on any miss. That changes merge.sh's contract
  and the posture interlock, so it is filed as tk-93y5d53 rather than folded
  in here.
- **Running merge on the previous pass's posture.** This is the bead's second
  direction applied to posture. It would let a comment that arrived since the
  last pass go unseen by the merge it should hold.
- **Splitting the cadence into a landing order and a dispatch order.** Both
  would contend for the one pass lock, and a lock per order would put
  gate-ensure and pr-facts writes beside a live merge.sh.

## For the city override's release

The bead's release condition, "gc-toolkit passes reach the merge arm inside the
shipped 600s", holds once this lands: merge starts after the posture arm alone,
about 160s at 33 PRs. Whether a whole pass then fits 600s depends on the two
walks that are never paced: the posture record (tk-93y5d53 tracks bounding it)
and the landable PRs. At today's backlog that is an estimated 435s (the
posture's measured 160s, plus about 25s for each of the 11 approved PRs merge
visits first), past the 420s budget, so every paced arm gets only its 20s floor
and a pass runs to about 600s. The `END <ts> (<s>s)` line shows the pass length directly. "Passes
end inside 600s" is the condition under which nothing is cut off.
