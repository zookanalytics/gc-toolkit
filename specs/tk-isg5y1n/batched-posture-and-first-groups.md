---
name: Batched posture read and needs-action-first walks (tk-isg5y1n)
description: The measurements behind batching the posture arm's PR read and putting the anchors that need action first in the paced arms, the designs set aside, and what the hermetic suites prove. Read it before changing how the posture arm skips its per-PR reads or how a paced arm picks its first group.
---

# Batched posture read and needs-action-first walks

## The problem as filed

The gc-toolkit pass of 2026-10-07 16:58Z spent 480-530s in the unpaced posture
arm, past the 420s pass budget, so every paced arm ran at its 20s floor:
pr-facts visited 2 of 87 PR anchors, pr-feedback 3 of 87, gate-ensure 1 of 99,
and the write-back 1 of 13. The rotations then came back to a given anchor about
every 11 hours (pr-facts) and 25 hours (gate-ensure), so approved PRs that
conflicted with main waited hours for a merge-in and review feedback waited as
long for its rework.

## What was measured

Read-only GraphQL reads against zookanalytics/gc-toolkit on 2026-10-07, between
19:45Z and 21:22Z, with the host at load average 26-35 on 8 CPUs.

| Read of every open PR (73 open) | Page size | Time |
|---|---|---|
| number, head, review decision, `mergeable` | 100 | 2.2s |
| the posture fields with `mergeStateStatus` | 100 | 7.4-9.7s |
| the posture fields with `mergeStateStatus` | 50 | 12.4s |
| the posture fields with `mergeStateStatus` | 25 | 14.9s |
| the same fields without `mergeStateStatus` | 100 | 3.7-4.3s |

At 19:4xZ every merge state came back computed (43 BLOCKED, 28 DIRTY, 2 CLEAN).
An earlier read at 106 open PRs, in one page, returned HTTP 502 after about 11s
on every try, so the posture read pages 25 PRs at a time: each request then
computes at most 25 merge states, well inside the time GitHub allows one.

`updatedAt` cannot detect every new review on its own. PR #1130 received five
reviews from one account between 18:29:55Z and 18:30:04Z, one per second, and
its `updatedAt` stayed at 18:29:55Z. A pass reading between the first and the
last would see no later change in `updatedAt` at all. The review count and the
newest review id do move with each one, and an inline comment arrives inside a
review of its own, so the posture basis keys on the counts and newest ids, and
on `updatedAt` as well for the edits it does catch.

The store at 19:5xZ, by machine verdict and posture:

| Gating anchors | Count |
|---|---|
| pull_request, settled | 65 |
| pull_request, progressing | 8 |
| pull_request, blocked (all approved and DIRTY) | 3 |
| pull_request, approved and DIRTY in total | 4 |
| pull_request, posture `commented` | 1 |
| pull_request, posture `changes_requested` | 5 |
| pre_open_gate, progressing | 8 |
| pre_open_gate, settled | 2 |
| pre_open_gate, no verdict | 1 |
| live beads carrying `anchor_bead` (one read, 2.4s, 142 KB) | 60 |

At 21:22Z, 2 of 65 open PRs had changed in the last 15 minutes, 10 in the last
hour and 23 in the last six hours. A pass every 12-22 minutes therefore reads
a handful of PRs whole, where it read every PR before.

## What changed

- **The posture arm reads every open PR in one batched call**, merge state
  included, and keeps in `pr-posture.seen` the basis each posture was derived
  from: the PR's head, review decision, `updatedAt`, review and comment counts
  and newest ids, the anchor's three watermarks and provenance cutover, the
  acting login, and a checksum of pr-facts.sh and of the own-post definition.
  An anchor whose basis reads the same, and whose bead still carries that
  posture at that head, keeps it without the pinned read or the feedback lists,
  and its merge state is recorded from the batched read. A `commented` posture,
  and one an unengaged-thread candidate decided, keep no basis, because each can
  change with nothing on the PR moving. The merge interlock is unchanged: the arm
  still makes every posture current and still exits non-zero when it cannot.
- **pace-lib.sh keeps seen marks**, what a walk saw of each anchor at its last
  visit, recorded when the visit finishes, the same moment the cursor records
  it. A walk with no marks yet records them and puts nothing first for a
  change, so a deploy does not turn the whole set into a first group.
- **Each paced arm named in the bead visits first the anchors it can act on.**
  The feedback arm puts first a `commented` posture and a `changes_requested`
  one whose PR changed since its last visit. The full pr-facts walk puts first a
  PR that left the open list, an approved PR recorded DIRTY with no rework child
  in flight, and a PR whose head, base, draft flag, review decision, or review
  or comment count changed since its last visit. The write-back sweep puts first
  an anchor whose disposition, watermarks or live children changed. gate-ensure
  puts first an anchor with no `check_set`, one with no machine verdict, and one
  whose stage, `check_set` or live children changed.

## Designs set aside

- **Batching the feedback lists into GraphQL.** The posture derivation reads the
  REST review, inline comment and Conversation lists, filtered by the city's
  own-post definition. Rebuilding those from nested GraphQL connections changes
  the shapes the derivation reads and needs per-PR pagination past 100 items, so
  the unchanged-PR skip keeps the derivation itself untouched instead.
- **Keeping the posture basis on the bead.** It would survive a lost state dir,
  but it is a ledger write on every PR change for a value only the posture arm
  reads. A lost `pr-posture.seen` costs one pass that reads every PR whole.
- **gate-ensure putting first every anchor not recorded settled** (tk-q1n2r3r's
  direction). 16 of the 87 anchors were `progressing`, most waiting on a review
  or fix already in flight, so they would have filled the first group every pass.
  A change in the anchor's live children is the event that turns a waiting lane
  into an owed one, and an anchor with no verdict at all is still put first.
- **pre-open-rebase and pr-stack.** Neither has a needs-action signal readable
  without its per-anchor probe, so both keep the plain rotation. merge.sh and
  pr-open.sh already visit their landable and settled anchors first.

## What the suites prove

pr-facts.test.sh's `pacing` part carries the bead's two done-when cases. An
approved PR gone DIRTY, the highest of four ids under a deadline that leaves the
rotation one visit, gets its merge-in filed in the first pass. New feedback on
the highest of three ids is routed by the feedback arm in the first pass. The
posture cases prove an unchanged PR costs no `gh pr view` and no feedback list,
that a review, a comment, a push, a review decision, `updatedAt`, a watermark or
a posture another arm rewrote each send it back to the per-PR read, and that a
failed batched read falls back to reading every PR. Eighteen mutants, each
removing one rule from pace-lib.sh, pr-facts.sh or gate-ensure.sh, each fail at
least one assertion.

Not measured: the pass length in production. That shows in pass.log once this
lands, as the posture arm's `done in <n>s` and its
`<k> unchanged since the basis they were derived from, <r> read per PR` line.
