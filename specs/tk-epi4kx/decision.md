---
name: unengaged-review-thread-backstop
description: Why review comments on a green, open PR trigger no follow-up, and why the fix is a visit-guardrail in pr-facts.sh rather than auto-rework or a gc-doctor check.
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
  counts only comment/review ids whose author login is not ours
  (`pr-facts.sh:494, 500`). A review posted under our own login never sets
  `unanswered`, so the posture falls to `review_required`, which holds nothing
  (`merge.sh` holds on `commented@*` or a non-self `CHANGES_REQUESTED`, never on
  `review_required`).

No doctor check inspects PR comments, and `liveness-sweep.sh` keys on PR age,
not comments.

Codex does not widen the collision surface: its findings are beads plus a single
`COMMENTED` review body (`signoff.sh:653`), never inline review threads. So the
unresolved review threads that back this gap come only from genuine external
reviewers, and keying on them does not double-file against the codex loop.

## Decision: a visit-guardrail in pr-facts.sh

A new arm at the end of the `pr-facts.sh` dispatch loop reads the review
*threads* — not the comment authors — of an otherwise-clear anchor and files one
visit when the PR carries an unengaged finding thread: unresolved, holding a
comment that is not one of our own write-back replies, with no write-back reply
of ours in it. The visit is stamped with `pr_number`, so `merge.sh` holds the
merge behind it exactly as arm 4's own visit branch does, and the anchor is
head-watermarked (`pr_unengaged_threads`) so it does not re-file.

The arm is login-independent by construction (it reads `isResolved` and the
write-back marker, not the author), which is what closes the gap. A cheap
pre-gate keeps it from spending a thread read on anchors that cannot be hiding
the gap: it activates only when the comments already fetched for the posture
carry a comment under our own login that is not a write-back reply — the exact
class arm 4 filters.

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

The pre-gate keys on self-login comments still present on the PR, and the arm
skips an anchor whose feedback arm 4 already routed (a `pr_comment_disposition`
is set). A self-login finding thread that arrives *after* a foreign batch was
routed is therefore not caught here; it needs the watermark integration this
change deliberately avoids. The primary case — a PR whose findings were never
engaged at all — is covered.
