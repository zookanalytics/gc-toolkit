---
name: unengaged-review-thread-backstop
description: Why review comments on a green, open PR trigger no follow-up, and why the fix is a posture-pass merge-hold plus a visit in pr-facts.sh rather than auto-rework or a gc-doctor check.
---

# Review comments on a green open PR trigger no follow-up

## The gap

A review posts unresolved comments on a PR that is already OPEN with a green
gate. When those comments are authored under the automation's own gh login — an
outside review agent, an operator-run review, and a codex verdict all post under
it — nothing ingests them: no rework is filed, no cadence re-engages, no doctor
check flags the PR. Observed on PR #708: an outside review agent posted ten
unresolved findings under the `zook-bot` login; they sat unaddressed ~23h and
surfaced only when the operator picked the anchor off the helm board.

## Why (verified against the code)

Two correctly-scoped mechanisms leave a hole between them.

- `gate-ensure.sh` dispatches a re-review only when a lane is not green, and
  `lane-state.sh` derives green from the finding and review-outcome beads, never
  from PR comment threads (`lane-state.sh:2-33, 99-125`). A push creates no bead
  in that set, so green survives new commits and an already-green open PR is
  never re-reviewed.
- `pr-facts.sh` arm 4 is the only PR-feedback ingestion path, and its posture
  counts only comment/review ids whose author login is not ours (the `max_c`/
  `max_r` computation in the posture section, and the `feedback_body`/
  `feedback_reviews`/`live_comments` helpers, all `select(login != self)`). A
  review posted under our own login never sets `unanswered`, so left to arm 4 the
  posture falls to `review_required`, which holds nothing (`merge.sh` holds on
  `commented@*` or a non-self `CHANGES_REQUESTED`, never on `review_required`).

No doctor check inspects PR comments, and `liveness-sweep.sh` keys on PR age,
not comments.

Codex does not widen the collision surface: its findings are beads plus a single
`COMMENTED` review body (`signoff.sh:653`), never inline review threads. So the
unresolved review threads that back this gap come only from genuine external
reviewers, and keying on them does not double-file against the codex loop.

## Decision: a merge-hold in the posture pass, a visit in the full pass

`merge.sh` reads its hold signals off the bead — `merge_hold`, the `commented@`
posture, and in-flight `pr_number`/`blocks` holders — and never reads PR threads.
`refinery-reconcile.sh` runs the passes in the order `pr-facts.sh
--posture-only`, then `merge.sh`, then the full `pr-facts.sh`. A visit filed by
the full pass does hold `merge.sh` off its `pr_number`, the way arm 4's visits
do — but only on the *next* cycle, because the full pass runs *after* `merge.sh`
has already had its chance this cycle. So the hold has to exist in the posture
pass, before `merge.sh` runs, and the posture is the only signal that pass
writes.

The posture pass folds an unengaged self-login finding thread into the
`commented` posture — the signal `merge.sh` already holds on. An unengaged thread
is one that is unresolved, holds a comment that is not one of our own write-back
replies, and holds no write-back reply of ours. Detection is login-independent by
construction (it reads `isResolved` and the write-back marker, not the author),
which is what closes the gap. A cheap pre-gate keeps it from spending a thread
read on anchors that cannot be hiding the gap: it reads threads only when the
comments already fetched for the posture carry a comment under our own login that
is not a write-back reply — the exact class arm 4 filters.

The full pass then files one visit for that hold — the follow-up nothing else
raises. The hold stands off the open visit until it closes (`visit_for`), and the
anchor is head-watermarked (`pr_unengaged_threads`) so a closed visit does not
re-raise until a new commit. Reading the threads once per head (the watermark and
the standing visit answer every later pass) keeps the posture pass cheap.

### The hold fails closed on an unreadable read

The hold rests on two reads: the in-flight ledger (is a review or rework child
already covering this anchor?) and the review threads. Either can fail to answer,
and a read that did not run is not proof of zero unengaged threads, so
`unengaged_holds` reports "could not determine" as a third outcome distinct from
"nothing holds". On that outcome the posture pass records no posture. An
unrecorded posture is uncurrent, `--posture-only` reports it in its exit code,
and `refinery-reconcile.sh` holds `merge.sh` for the pass — `merge.sh` never
reads a posture across a read that did not happen. The read retries next pass.
Only a clean read of zero threads records the `review_required`/`approved`/`none`
the review decision earns; a read that did not answer holds instead.

## Why not the alternatives

- **Auto-rework in arm 4 (the bead's leaning).** Filing a rework child off a raw
  thread read would loop on our own output: a polecat's "why not" reply and the
  write-back's own reply are both self-authored, and threads left `live` or
  `norights` stay unresolved on purpose. Telling a finding from an answer well
  enough to drive an auto-fix loop is arm 4's watermark machinery, and routing
  self-login threads through it also departs from a documented invariant
  (`state-machine.md`: the city's own feedback is signoff.sh's loop, not
  arm 4's). A visit surfaces the follow-up the operator asked for without that
  risk; a human dispositions it — answer, file rework, or resolve. Auto-rework
  remains a possible later step if detection-only proves too manual.
- **A new `gc doctor` check.** `gc doctor`'s checks live in the `gc` binary, not
  in this pack's `assets/scripts/`, so a new check is a cross-rig change. Hosting
  the backstop in `pr-facts.sh` keeps it in-rig and reuses the reviewThreads
  query, the `escalate`/`visit_for` helpers, and the write-back sweep that will
  react to and resolve the threads once addressed.

## Known limitation

The pre-gate keys on self-login comments still present on the PR, and first
detection is suppressed while any review, rework child, or visit is already open
on the anchor (the in-flight guard, which keeps the backstop from stacking a
second follow-up behind one that already holds the merge). A self-login finding
thread that arrives while a foreign batch's rework child is still live is
therefore not caught until that child closes. The primary case — a PR whose
findings were never engaged at all — is covered.
