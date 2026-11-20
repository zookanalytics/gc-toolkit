---
name: Refinery merge cadence
description: The exec orders around a PR's merge — the merge cadence, with its driver and arms, the arm budgets, the single-flight guarantee and how to read what a pass did, and the landing order that merges a PR on the pending record. Read it to know what drives merges, and why nothing else may.
---

# Refinery merge cadence

The merge side of the anchor lifecycle is driven by orders, never by an agent.
The landing order merges each PR on the pending record
([The landing order](#the-landing-order)), and the merge cadence's arms read
and route what happens on the PR. The cadence's liveness has its own doctor
check (`check-cadence-live`).

## Scope

**Mandate.** What drives the merge-side writers, what each arm of the merge
cadence owns, what a run of the landing order does, and the runtime guarantees
the arrangement depends on.

**Boundaries.** The states the arms and the landing order move an anchor
through are [state-machine.md](state-machine.md). The refinery *agent*'s steps,
which land, publish, park or send work back, live in
`formulas/mol-refinery-patrol.toml` and the scripts each step calls, and are not
driven by either order. The witness patrol's `check-refinery` step watches
that patrol's queue for a hand-off gone stuck.

## Mechanism

Every 60s, per rig: `orders/refinery-reconcile.toml` (`trigger = "cooldown"`,
`scope = "rig"`) execs `assets/scripts/refinery-reconcile.sh`, the driver,
which runs the arms in order and exits.

| | |
|---|---|
| Cadence | `interval = "60s"`, tunable from city.toml `[[orders.overrides]]` |
| Scope | `scope = "rig"` — one registration per importing rig |
| Working directory | the rig's own root, so `git remote get-url origin` resolves |
| Environment | controller-built: `GC_RIG`, `GC_RIG_ROOT`, `BEADS_DIR`, `GC_BEADS_PREFIX`, `PACK_DIR`, `GC_PACK_STATE_DIR`, the Dolt projection, the `gh` token |
| Timeout | `timeout = "600s"`, tunable per rig from city.toml `[[orders.overrides]]` — it bounds how long a wedged pass holds the per-rig lock. It must cover a whole pass at the slow end of host load and stay under the driver's `REFINERY_RECONCILE_LOCK_STALL_SECS`, and it does *not* fit inside the controller watchdog's 2m tracking-sweep window |
| Pass budget | `REFINERY_RECONCILE_PASS_BUDGET_SECS` (420, below the timeout; 0 = unpaced) is shared by the arms that walk a set growing with the queue, listed in `PACED_ARMS` in refinery-reconcile.sh: pr-feedback, gate-ensure and pr-facts. Each paced arm's deadline is an equal share of what the budget has left when it starts, split among it and the listed arms still to run, never under `REFINERY_RECONCILE_ARM_FLOOR_SECS` (20); an arm the pass does not run leaves the split. Each visits first the anchors it can act on and then resumes its rotation from its cursor in the pass state dir. Set both per rig through the override's `env` |

Anything per-rig is derived inside the driver from `GC_RIG` / `GC_RIG_ROOT`;
one `[order.env]` serves every registration. The refinery agent does not drive
the cadence — the arms run whether or not any refinery session is awake.

## The arms

Each arm keeps the number the driver logs it under.

- **(1) pr-facts.sh --posture-only** — the posture record, which the
   PR-finishing rank and the board read. It runs first, and writes `pr_posture`
   and `pr_merge_state` at the live head for every open non-draft anchor, then
   stops: no dispatch, no watermark, and MERGED/CLOSED reconciliation stays with
   arm 7. A held merge still gets one, because recording a fact is not a
   dispatch. Its rc is reported and fails the order. Where this arm
   changes an anchor's posture value, it also
   re-derives that PR's `status:` and `held:` labels, so an approval moves them
   in the pass that records it
   ([state-machine.md](state-machine.md#the-status-label-github-projection)).

   Its cost follows the PRs that moved, not the PR set. One paginated GraphQL
   read lists every open PR with its head, base, draft flag, review decision,
   merge state, `updatedAt`, and the count and newest id of its reviews and of
   its Conversation comments. An inline comment arrives inside a review of its
   own, so it moves the review count. GitHub computes the merge state per PR on
   request and times out on about a hundred at once, so the read pages 25 PRs at
   a time. The arm keeps, in `pr-posture.seen` in the pass state dir, the facts
   each posture was last derived from: those PR facts with the anchor's
   watermarks, its provenance cutover, its lift line (`bring_current_lifted_at`),
   the acting login, and a checksum of the script and of the city's own-post
   definition. An anchor whose facts all read the same, and whose bead still
   carries that posture at that head, keeps it with no per-PR read, and its
   merge state is recorded from the batched read.
   Any other anchor is read whole, as every anchor is when the batched read
   fails. A `commented` posture keeps no basis, because a routing or a cleared
   human gate can release it with nothing on the PR moving, and neither does a posture an
   unengaged-thread candidate decided, because that answer turns on bead state.
   A derivation whose answered marks (`pr_comment_answered`,
   `pr_review_answered`) did not record keeps none either. The marks let the
   next derivation drop answered feedback without reading the review threads, so
   until they land each derivation reads the threads again. The marks stay out of
   the basis, because only a derivation writes them.
   `updatedAt` cannot stand in for the counts: GitHub can leave it at the first
   of several reviews submitted seconds apart. The batched read and the per-PR
   reads are separate requests, and GitHub can answer one of them from a moment
   ahead of the other, so a derivation's lists can be older than the facts the
   batched read gave. A derivation therefore records its basis only as a
   candidate, which keeps no posture. The next pass derives the posture again,
   and a derivation that reads the same facts and derives the same posture
   confirms the basis. A PR that moved is therefore read whole on two passes.
- **(4) pr-facts.sh --route-comments-only** — the feedback routing of arm 7, run
   ahead of the slow arms. Arm 7 runs behind gate-ensure, so a pass the timeout
   kills before arm 7 would leave the operator's review stamped-as-seen by the
   posture yet unrouted while the anchor reads as handled. This arm closes that
   window: it re-reads each open anchor's feedback and dispatches the same
   rework child or human gate and opens the same validation pass arm 7 would, or
   on a PR on the pending record files the same ask, then
   stops — no write-back sweep, no external-fact reconciliation, none of the
   arms that belong at the tail. A batch it routes is live work on the anchor,
   which the `status:` label reads, so it re-derives that PR's labels as it
   routes. Arm 7 still runs the routing idempotently (a
   landed batch's watermark and `pr_comment_disposition` make the re-run a
   no-op) and still owns the write-back and the terminal-state records. Its rc
   is reported but holds nothing: the full pass is the backstop. It runs ahead of
   gate-ensure, so a validation pass it opens is in place for gate-ensure to
   dispatch a validator onto. It walks the PRs under its share of the pass
   budget, first the anchors whose recorded posture is `commented` (feedback no
   routing has answered) and the `changes_requested` ones whose PR changed since
   this arm last visited them (that posture alone cannot say whether its
   feedback is routed), then the rest in a rotation. The observability half is
   `doctor/check-feedback-routing-owed`, which flags an anchor whose posture still
   says a human is waiting with no disposition past a window.
- **(6) gate-ensure.sh** — check satisfiability, on the old review path, for an
   anchor at `pre_open_gate` or `pull_request`, which no bead carries; a PR on
   the pending record has a review run instead ([state-machine.md](state-machine.md#checks)). Every gating
   anchor declares a non-empty `check_set` (the default is stamped when absent;
   the `none` sentinel is respected), and every declared check is *raisable*: the lane
   derives `green`, or a live routed review bead is in flight, else dispatch one
   (stamp first, then attach `mol-review` via `gc sling --on`; read the pour
   back). A lane that derives `green` ends the arm's interest however far the
   branch has advanced since — no lane's green compares to a head. An
   operator's own `merge_hold` also ends the arm with no dispatch: gate-ensure
   raises no review under a hold.
   A review whose only reach is the pour stamp is qualified before it counts
   as in flight: if its workflow is spent — every step closed but
   `workflow-finalize`, which belongs to the control-dispatcher — no verdict
   can still be coming, and the arm puts it to a person through `human-gate.sh`
   under the `review-wedge` key rather than holding the anchor in silence. It
   files on the second consecutive sighting, because `mol-review`'s failure arm
   closes its chain before it restores the bead's route. No dispatch goes out
   while anything is acting on the anchor — a fix unit in flight (including the
   one answering an open `must-fix` finding on any lane), a validation pass in
   flight, or a full review already in flight on the lane — which is the
   QUIESCENCE predicate one authority computes so it cannot disagree with itself
   about whether a review was already out. The hold names the actor. A
   `must-fix` finding no fix unit answers is a demand on the anchor, not an
   actor: it holds the merge through its `blocks` edge and keeps the anchor
   `progressing`, but it does not hold the dispatch, and the arm reports it as
   unanswered. The same authority also releases a finding: on the first pass
   after every fix unit answering a `must-fix` finding has closed, it closes the
   finding, so a fix that has landed on the branch stops holding the publish
   and the merge. A review that read a mid-change diff would raise
   only the no-op rework the declination texts are full of. There is no dispatch
   ceiling: quiescence forbids the redundant round a ceiling would have bounded,
   and the runaway shapes left — a reviewer that dies after claim, a fix unit
   filed with its edge reversed, a landed fix whose finding that release missed
   — stop the PR moving rather than spin the dispatcher.
   It visits every gating anchor, so its cost grows with the set. It runs under
   its share of the pass budget. It first visits the
   anchors it can act on: one with no `check_set` (it owes the stamp), one with
   no machine verdict (never visited; a `check_set` of `none` or `off` never
   gets one), and one whose mark moved since this arm last visited it. The mark
   joins `merge_result`, the draft markers and `check_set`, which decide the
   lanes a stage dispatches, `merge_hold`, which holds the anchor's review
   dispatch while it is set, and the ids of the anchor's live children. A hold
   lifting, or a review, validation pass, finding or fix unit opening or
   closing, puts the anchor first; a review this arm opens joins the mark its
   own visit records.
   Then it visits the rest in id order starting after the last one a pass
   finished (`gate-ensure.cursor` in the pass state dir), wrapping, and starts no
   new anchor once its share is spent. The first group rotates on
   `gate-ensure.cursor.first`, and `gate-ensure.cursor.seen` holds the marks. A
   slow walk therefore delays review dispatch for the anchors it has not reached,
   and nothing else, and every anchor is reached within a bounded number of
   passes. Its rc=3 (an anchor whose `check_set` stamp did not persist, or an
   enumeration it could not read) is reported without failing the order or
   holding anything.

- **(7) pr-facts.sh** — external facts only, no merge authority: PR merged
   out-of-band (record), closed-unmerged (→ `abandoned` + a human gate), base
   changed (→ `retargeted` + a human gate), CONFLICTING (one rework child per head, on an
   approved PR only, by the approval rule `review-verdict.sh` states; the child's
   handoff runs `bring-current-guard.sh`, which refuses it until the worker's
   audit covers every conflict and, when the round conflicted, reopens triage
   to rule on what it reopens and whether the approval stands, adding triage
   to an anchor whose `check_set` declares no triage lane, or, on the `none`
   or `off` opt-out, lifting the approval itself; a ruling that lifts the
   approval draws `bring_current_lifted_at`, before which no approval counts,
   and files no gate
   ([state-machine.md](state-machine.md#bringing-a-branch-current)). When the
   conflict is a landed change deleting code the branch edits,
   the approved PR gets the operator's supersession decision instead of the
   child), `BLOCKED` on an unresolved review thread or a
   missing required approving review (→ no gate. The write-back below resolves
   every thread the city rules on, whether it fixed, declined or deferred the
   point, and a thread whose question only a person can answer waits on a gate
   of its own, as a `needs-you` finding's does.
   A missing approving review is the operator's own review queue, the state the
   board's review section already surfaces from the recorded `pr_posture`.
   Neither asks a person anything, so the cadence withdraws any open
   `merge-blocked-threads` or `merge-blocked-approval` gate, resolving it
   `moot:`, at the top of its run ahead of the no-anchors early-exit and in
   every rig. It lists the store's gates and reaches the beads each one blocks
   from the gate's end, and leaves a gate whose beads do not read for the next
   pass), hold-resolved retraction, and the withdrawal of its own merge-path gates
   once their situation is gone (an unengaged-threads gate once the head moves
   past the one it counted, the retarget and abandoned gates once the base or
   the PR is back, and a red-check park's gate once GitHub reads the PR
   mergeable). A feedback gate
   waits for its answer, and a gate a person is assigned is left to them. It re-reviews no moved head: a lane state is a
   state of the lane, and only gate-ensure dispatches on it. It also records every open
   non-draft anchor's **posture** — `pr_posture`, `pr_merge_state`, and the
   comment watermarks ([state-machine.md](state-machine.md#posture)) — before
   any of those arms run, and routes unanswered review feedback — under a
   `commented` posture and equally under a human `changes_requested` — to a
   rework child, or to a human gate when no fix pool is configured or the head
   branch is unresolved. Feedback is every review, inline comment and
   conversation comment that is neither the city's own post nor marked as not
   for review ([state-machine.md](state-machine.md#operator-feedback)), whoever
   wrote it.
   The posture write is idempotent, so re-running it
   here after arm 1 costs nothing when nothing changed. The routing runs in two
   places by design: arm 4 picks the feedback up ahead of the slow arms, and this
   arm re-runs the same routing idempotently — a landed batch's watermark and
   `pr_comment_disposition` make the second run a no-op — while owning the
   write-back sweep and the terminal-state records that only make sense after
   merge. Arm 1 records the posture; arm 4 and this arm decide what answers it.
   Each batch it
   routes also opens one validation pass on the anchor — a
   `task_kind=validation` bead, unrouted, blocking the anchor — from which
   `gate-ensure.sh`'s quiescence holds a fresh whole-diff review while the
   validator rules the batch.
   The batch is watermarked only once that pass records the shape the validator
   reads — `anchor_bead`, `check_name=human`, `reviewed_oid` — and its `blocks`
   edge holds.
   A write-back sweep then answers the operator in the PR itself, marking each
   routed comment as looked at, awaiting a person, or resolved. On an anchor
   carrying `pr_comment_disposition`, every comment at or below its space's
   watermark gets an EYES reaction. The watermarks are cumulative and a
   disposition holds one batch at a time, so each id space keeps a ledger of the
   batches routed under it: `pr_comment_batch` for inline comments,
   `pr_review_batch` for review bodies, and `pr_issue_comment_batch` for
   Conversation comments. A ledger holds one `<disposition>|<floor>|<mark>`
   record per batch, oldest first, written in the same transition that advances
   the disposition, and a comment's batch names the bead that answers it. While
   that bead is a human gate still open, the comment gets an answer that leads
   with a question mark and names the gate. A rework child closes when it lands,
   and a gate when a person clears it. Once the comment's bead has closed, and
   its own finding has closed if it has one, the comment is resolved: an answer
   leading with a check mark says what resolved it, and the comment trades its
   EYES reaction for THUMBS_UP. An answer for a rework child names the commits
   it made: the PR's non-merge commits whose message names the child, and of
   those only the ones naming the comment when any do. It says Fixed when the
   comment's must-fix finding closed with that rework. It never names the PR
   head for being the head, since the head can be a merge of the base. A
   finding ruled needs-you keeps its comment awaiting a person while it is
   open, and its owed reply is the answer, leading with the question mark. A
   declined or deferred finding's owed reply is its comment's answer too. That
   reply leads with the ruling ("Declined" or "Deferred"), so a reader scanning
   the PR tells a fix from a pushback. The comment trades EYES for THUMBS_UP
   once the reply is on the PR. Whether an
   owed reply is on the PR is read back off GitHub on every pass, by its own
   text, so another reply in the thread never stands in for it. An inline
   comment is answered in its thread.
   The thread is answered once every routed comment in it is resolved: the
   comments a batch resolved by one reply naming each bead, and a comment its
   own finding answers by that finding's owed reply. It is resolved behind
   those answers, whether the city fixed, declined or deferred the point, on
   a pass whose own read of the PR shows each owed reply in it, never on a
   stamp an earlier read left. A thread
   holding a needs-you finding stays open until the person rules. A post in a
   thread the city resolved is feedback like any other, so a reply of the
   reviewer's there is ruled as a finding of its own, and the declined or
   deferred finding stays closed. A needs-you finding closes once the human
   gate holding its question, followed
   through any re-home, has been cleared with a reason headed `ruled:` (or the
   finding records the bead whose ruling released it, `finding.ruling_bead`),
   and no fix unit on its lane, nor a ruling's rework child, is in flight, and
   its comment then resolves through its batch's bead like any other. A gate
   cleared `moot:` or `benign:` carries no ruling and releases nothing. A
   Conversation comment has no thread, so a Conversation comment of the city's
   links to the comments one bead answers and carries their answer. A review
   body has no thread either, and its review round's living answer carries its
   answer and the mark that trades its reaction. Each review round that raised
   findings has one living answer. A round is the reviews one reviewer
   submitted against one commit, however many GitHub reviews their client split
   that pass into. The answer is a Conversation comment posted once the round's
   pickup reactions land and edited in place whenever its rendering changes
   (`assets/scripts/review-answer.sh` states what it shows): any human gate
   waiting on the operator first, a count line, then one point per finding, sorted into
   Needs you, Worth a look, In progress and Done, each a label linked to the
   comment, a sentence in the words of whoever answered it, and the commit,
   follow-up or gate carrying it. A declined or deferred point that owes its
   raiser a reply is worth a look, since the city resolves its thread, and a
   reply of the reviewer's in that thread is a point of its own. The count line
   counts the points under Needs you, so it never reads all answered while one
   waits, and it still says where the other points stand. It carries a digest of its own
   rendering, so a pass that changes nothing writes nothing. When the city
   holds more than one comment for a round, each keyed to one of its reviews,
   the pass keeps one, moves every mark the others carry into it, and deletes
   the others. It is rendered to fit the size GitHub takes in one comment: a
   long review shortens its notes from the fix, then its quoted replies, then its
   sentences, each cut naming the bead that holds the whole text, and past that
   lists the points that fit and names the rest. Once every finding a human
   CHANGES_REQUESTED review raised has closed and every answer one of them owes
   is on the PR, the sweep re-requests the reviewer and dismisses that review
   with a one-line note linking its round's living answer, which then says the
   review was dismissed. A review whose body was ruled restates waits for every
   finding of its round. A dismissal is not an approval. The routing arm leaves
   out of a batch the feedback the review threads already answered: an inline
   comment in a resolved thread with a later post of the city's, or a review
   body whose every inline comment is one. Such feedback sits inside the
   batch's range, but the batch's bead never saw it, so unless a finding names
   it, it is acknowledged and never marked. A record is dropped once
   every comment it covers carries its final mark and every inline comment the
   batch answered sits in a resolved thread, unless the comment's own finding
   answers it, which the plan reads from the finding until its thread is
   resolved. The reactions are written
   first and bounded per pass; when the cap or a failed write leaves one owing,
   that pass posts no answer, so no comment is answered before it is
   acknowledged. A thread with a post after the city's own reply that is not
   itself the city's own is left open, and so is one holding a comment above
   the mark: no batch covers that
   comment, so nothing has answered it, and resolving would put the thread past
   every later pass. A thread left open this way keeps its batch's record, so
   every later pass still answers for it: the post that left it open routes as
   feedback of its own, and the answer to that post resolves the thread. A
   thread the city answered for a batch or for a ruled machine finding (below)
   and cannot resolve under its identity (GitHub reports `viewerCanResolve`
   false) stays owed. Each pass tries the resolve again and logs the thread,
   and files the situation through `patrol-finding.sh` as one finding for the
   repository, keyed `pr-thread-unresolvable.<owner>.<repo>`. The finding names
   no anchor, so it holds no merge. Idempotence is read back off GitHub, so a
   repeat pass writes nothing and a failed write is retried by the next one.
   The per-anchor walk runs under the arm's share of the pass budget,
   first the anchors that need action, then the rest in a rotation. Needing
   action is a PR that left the open list (a merge or a close to record), an
   approved PR the posture arm recorded `DIRTY` at its head with no rework child
   in flight (it owes a merge-in), and a PR whose head, base, draft flag, review
   decision, or review or comment count changed since this walk last visited
   it. An approved conflicting PR under a `merge_hold`, a `rebase_hold` or an
   armed re-dispatch owes no merge-in, because the conflict arm stands down on
   each, so it rotates with the rest until the hold lifts. The marks live in
   `pr-facts.cursor.seen`, and a walk with none records them and puts nothing
   first for a change. The write-back sweep reads GitHub only for the anchors
   carrying a disposition or owed a finding post or answer (below), at least
   four calls each, so it runs under the same deadline in a rotation of its own
   (`pr-facts.cursor.writeback`), with one anchor visited even on a pass whose
   walk spent the deadline. It visits first an anchor whose disposition, a
   watermark, or its live children changed since the sweep last visited it: a
   batch routed, or the work answering one closing. An anchor with no
   disposition, there only for the findings its PR is owed, rotates with the
   rest.
   The same sweep carries each machine-lane finding ruled worth fixing
   (`must-fix` or `deferred`) to the PR. A finding whose locus begins with a
   file the diff touches becomes a file-level review comment on that file, and
   any other locus becomes a Conversation comment. Once the finding closes, the
   comment is answered with how it closed: the fix units and the commits they
   made, the deferral's follow-up, or the decline. Its thread is then
   resolved, whether the finding was fixed, declined or deferred, unless a post
   that is feedback has come after it. A thread the identity cannot resolve
   leaves the finding owed its answer, as above. A declined or deferred
   finding's answer is recorded `settled`. One recorded `1` can still have its
   thread open, behind an answer carrying the `<!-- gc-finding:<id>:open -->`
   line, so it is answered again, and its thread is resolved by the same rule.
   A Conversation comment is edited to carry the answer. A finding that closed
   before it was posted, as a pre-open round's findings have, is posted with its
   answer already in place. A human finding is never posted, because it already
   sits on the PR where its raiser wrote it and is answered there. One
   store-wide read of the findings serves the pass, and `finding.pr_comment` and
   `finding.pr_answered` record each write, so an anchor whose findings are
   settled costs no GitHub call; at most `WB_FINDING_CAP` posts and answers go
   out per pass. A posted finding holds nothing, since a `must-fix` holds the
   merge through its own `blocks` edge. Its comments go through `pr-post.sh`, so
   they carry the city's mark and no feedback reader routes them or reads their
   thread as unengaged. Each also carries a `<!-- gc-finding:<id> -->` marker,
   which is how a later pass finds the finding's comment.

   On a PR on the pending record every arm of this script runs but the three
   that record the PR merged, closed without merging or moved to another base,
   which are the landing order's ([The landing order](#the-landing-order)). Its
   posture, its feedback routing, its conflict merge-in and its red-check fix and
   park reach that PR. The park files only its human gate. The merge-in, the
   red-check fix and a feedback batch each go to the PR's review run as an ask
   (`gctk review ask`), with no rework child and, for a batch, no validation
   pass: each comment becomes a human finding the run rules. The pass lists such an
   anchor at `pull_request_pending` on a blocked bead and at
   `pull_request_head_changed` on an open one, beside `pull_request` on an open
   one, which no bead carries. Each of its writes on such a bead is one plain
   metadata write guarded on the status and assignee the pass read.
- **(8) review-sweep.sh** — cleanup over closed anchors on the old review path, no
   merge authority. A
   dispatched review whose anchor is closed and whose `review_branch` is gone
   from origin has no verdict left to give. Both `signoff.sh` verdicts bind a
   marker to a commit and there is no commit, and `request-changes` would
   additionally file a rework child against work that already landed. The arm
   closes such a review with `gc.outcome=moot` and the reason recorded on the
   bead, and writes nothing to the anchor. Both conditions are required, so a
   branch that is merely unfetched and an anchor that still gates are each
   left alone. Branch existence comes from one `git ls-remote --heads origin`
   per pass, and a listing that could not be read sweeps nothing. The release
   verb lives here rather than as a third `signoff.sh` verdict because the
   residue is filed by two dispatchers, arm 6 and arm 7.
- **(9) scaffolding-sweep.sh** — cleanup over DISPOSED anchors' old review
   scaffolding, no merge authority.
   An anchor withdrawn won't-do or closed not-planned carries a disposition —
   the duplicates or supersedes edge `bead-rehome.sh` records onto its successor,
   or `gc.pr_close_disposition_kind` (the intent `pr-dispose.sh` records) — but its
   machine review scaffolding does not close with it: the validation pass, the
   finding beads, and the rework/fix-unit beads stay open, each holding a
   `blocks` edge on the anchor (a fix unit also blocks the must-fix findings it
   answers), and each holding gate-ensure's quiescence, so the disposed anchor
   stands stuck behind work that will never land. Nothing else retires them on a
   disposal: `close-answered` keys on a fix LANDING, and `review-sweep` on an
   anchor already closed. This arm closes each
   `task_kind=validation|finding|rework` bead whose `anchor_bead` names a
   disposed, non-merged anchor — `gc.outcome=moot`, the reason appended, read
   back — reworks before the findings they block so a finding's close is not
   refused the same pass. A finding is mooted only when it objects to the
   disposed diff. A human review comment on a line the PR left unchanged can
   cite code the target branch already carries, so its finding is carried
   forward to a bug bead of its own through `bead-rehome.sh` instead; the PR's
   inline comments are read once per anchor that carries such a candidate. It
   leaves `task_kind=review` to review-sweep, a human gate or a conversation to
   the human side, and a `rebase_hold` freeze to the operator, and never closes
   the anchor itself: that is `bead-rehome.sh`'s (via arm 7), held by `finalize-gate.sh`
   while a human gate on the anchor is open — which clearing the machine
   scaffolding here lets land once none is. Arm 7 runs this same sweep with `--anchor` for
   the one anchor whose PR-close disposition it is consummating, just before
   that close, so the close lands in the pass that reads the closed PR. A
   merged anchor is a landing, never a disposal, and is skipped.

## Single-flight: the tracking gate and the pass lock

Two passes writing the same anchors at once is the failure this
arrangement exists to prevent. The controller's open-tracking gate is one half
of the guarantee and a `flock` in the driver is the other, because the gate can
be reopened underneath a pass that is still running.

The gate:

- The tracking bead for a run is created **synchronously before** the run
  launches and closed in a `defer` **after** it returns.
- The dispatcher's first gate skips any order with an open tracking bead.
- That gate keys on `ScopedName()` — `refinery-reconcile:rig:<rig>` — so each
  rig has its own single-flight and co-tenant rigs never serialise against
  each other.

Why that is not sufficient: the controller runs a tracking-sweep watchdog every
30s which closes **any** order's tracking bead older than 2m
(`orderTrackingSweepWatchdogStaleAfter`, gascity `cmd/gc/order_dispatch.go`) —
a separate mechanism from the `order-tracking-sweep` order's own 10m
`--stale-after`, and much shorter. A pass that runs past two minutes has its
gate removed while it is still working, and the next tick dispatches a second
one onto the same anchors. gc-toolkit is where this bites, because it is the
rig whose pass routinely outruns two minutes.

The lock:

- The driver takes a non-blocking exclusive `flock` on
  `<state-dir>/<rig>/pass.lock` before the first arm and records the holder's
  pid and start time in `pass.holder` beside it. It depends on no bead
  surviving. The lock is `bd-lib.sh`'s `take_pass_lock`.
- `<rig>` is the rig name with each byte outside `A-Za-z0-9._-` read as `_`,
  and `rig` for a name of `.` or `..`. Every version of the driver must derive
  it the same way. A deploy can start a new driver while the one it replaces
  is still running a pass, and the two passes stay apart only when both name
  the same lock file. So the key is not `bd-lib.sh`'s `rig_state_key`, which
  cuts a rig name past 64 bytes and adds a checksum to any name it rewrites.
- The driver holds the descriptor, and each arm runs through `bd-lib.sh`'s
  `pass_child`, from a subshell that holds it until the arm exits. So the lock
  is held for exactly as long as a writer is live, and the kernel releases it
  on any exit, `SIGKILL` included.
- The arm itself runs with the descriptor closed, and so does the drop-tail
  report. An arm's store read can bring up a Dolt server, and `gc` hands the
  descriptors it was given to what it starts. A server that kept the descriptor
  would outlive the pass and hold the lock against every later one.
- A tick that finds it held logs one `SKIPPED` line and exits 0 — the cadence
  is firing and the pass in flight is doing the work.
- A holder older than `REFINERY_RECONCILE_LOCK_STALL_SECS` (900s default) is
  not a slow pass, because the order's timeout stops the pass's whole process
  group well before that: a driver run by hand, or an arm still running after
  its driver was killed by itself, holds the lock. That tick exits 1, so
  `order.failed` names the wedge rather than letting a stopped queue look like
  a firing one.
- A tick that cannot take the lock at all runs no arm and exits 1. That covers
  `flock` missing from `PATH` and a lock file the driver cannot create or open.
  Nothing else carries single-flight, so a pass that ran anyway would be the
  second writer.

Two settings must never change, because each would undo the guarantee:

- **Never set `no_work_gate` on this order.** It opts the order out of both
  open-work gates, and the first of them is the tracking gate above.
- **`timeout` bounds how long a wedged pass can hold the lock.** It does not
  keep the pass inside the watchdog window, because no budget that covers a real
  pass fits there, so the lock is what carries single-flight.
  `refinery-reconcile.test.sh` asserts the pair mechanically: a timeout above the
  2m window passes only in a run that also demonstrates one pass running its
  arms across two overlapping ticks. The suite holds the upper bound the same way,
  reading both numbers from the files that set them: a timeout at or above the
  driver's `REFINERY_RECONCILE_LOCK_STALL_SECS` would make a pass that is still
  running read as a wedged one.

Never run a cadence driver out-of-band (by hand, cron, or a daemon). Running
this script by hand at least serialises against the lock; anything else is a
second writer that neither the gate nor the lock can see.

## Reading what a pass did

The controller keeps an exec order's output only on non-zero exit, folding a
bounded tail into the `order.failed` event. So: an unexpected arm failure makes
the driver exit 1 (the failing arm names reach `order.failed`); gate-ensure's
rc=3 is reported but does not fail the order. Every pass logs to
`<GC_PACK_STATE_DIR>/refinery-reconcile/<rig>/pass.log`, trimmed to
`REFINERY_RECONCILE_LOG_KEEP` lines (2000 default) and not subject to bead
retention. Arms append as they run, so the shape of the log is what tells you
how a pass ended:

| Line | Meaning |
|---|---|
| `=== <ts> rig=<rig> refinery=<agent>` | a pass started |
| `-- (<n>) <arm> (started <ts>)` | an arm started; its output follows |
| `-- (<n>) <arm>: done in <s>s (rc=<rc>)` | that arm returned after `<s>` seconds. An arm with a start line and no done line is the one the pass was killed in |
| `<arm>: visited <k> of <n> ...` | how much of its walk a paced arm covered; `the next pass resumes at <id>` follows when its share of the pass budget stopped it. gate-ensure's `<n>` is the size of the gating set every walking arm's cost grows with. gate-ensure and pr-facts add `(<f> needing action first)`, and `<m> needing action wait for the next pass` when the budget left some of that group |
| `pr-facts: posture-only — ...; <k> unchanged since the basis they were derived from, <r> read per PR` | the posture arm's split between the anchors it kept from the batched read and the ones it read whole. `<r>` covers each PR that moved, on the pass that sees the move and on the pass after, which confirms its basis. It covers every PR on a pass whose batched read failed (a `WARN` line names it), and on the first two passes after the script changes or after `pr-posture.seen` is lost |
| `END <ts> (<s>s)` | that pass finished after `<s>` seconds; a `FAILED:` line sits above it if any arm failed |
| a `===` with no `END` under it | the pass was killed or hit its timeout — the arms logged above it are how far it got |
| `--- <ts> rig=<rig> SKIPPED: ...` | the tick found a pass already in flight and did nothing |
| `--- <ts> rig=<rig> STALLED: ...` | the lock has been held past the stall bound; the arms have stopped |

**`gc order history` is store-complete only when the read is unbounded.** Any
positive `--limit` — including the default 50, and a limit larger than the row
count — returns runs from the city store alone, printed under a `RIG` column,
so a single-rig answer looks city-wide. Always:

```bash
gc order history refinery-reconcile --since 30m --limit 0
```

Prefer `gc doctor` (`check-cadence-live`) over hand-rolled queries: it asserts
per rig that the order is registered and firing within its interval.

## The landing order

`orders/pr-reconcile.toml` merges each PR on the
pending record ([state-machine.md](state-machine.md#the-pending-record)). It is
a rig-scoped cooldown exec order, every 5 minutes with a 300-second timeout,
run in the rig's checkout, where it fetches the target.
`assets/scripts/pr-reconcile.sh` names the rig's refinery from the roster and
execs `gctk pr reconcile --refinery <it>`. A roster that does not read runs
nothing and exits 2 for the next tick, and a rig whose roster names no refinery
has no record to read.

Each run takes up to 20 beads that carry the marker `pr_reconcile_pending`, or
that carry a ruling's disposition on the record, the least recently checked
first (`pr_last_checked_at`), and starts none after four minutes (its
`--count` and `--budget`). It takes an open or blocked bead only while it is
assigned to nobody or to the refinery. A run writes nothing to a bead someone
else works, so that bead's last check never moves, and if it were taken it
would hold a place in every run. It reads each PR from GitHub by its number,
never from a list of open PRs, because a PR missing from that list can have
closed without merging.

| The PR | The run |
|---|---|
| open at the head the refinery validated | marks a draft ready, without waiting for CI, once a review result passed at that head and target, no review run is attached and no ask a run can take is open. Otherwise it asks the evaluator whether the PR is ready, and asks GitHub to squash-merge a ready one only while its head is that commit (`mergePullRequest` with `expectedHeadOid`), or adds it to its base's merge queue with that head where the base requires one, and pours a review run for one that is not ready when no review result passed at that head and target, or an ask nothing holds is open on the bead (below). It records the check either way, and the next run reads the PR again |
| open at another head | records the bead open, as `pull_request_head_changed`, and hands the head to the refinery in the write that assigns it the bead, once no withdrawal and no review run holds the head. While only conversations and asks hold the bead, it wakes the refinery after that write and clears the marker only once the wake lands (below). The refinery validates the new head and records it pending again. When it will not land the head as it stands, such as on a conflict with the target, it files the reason as an ask and then records the PR pending at the head its prep read (`refinery-requeue.sh`), so the ask holds the merge before the head is pending, a later run pours the review run that answers it, and its find-work leaves the ask alone |
| merged at the validated head, with the merge commit on the freshly fetched target | records `mr_merged` and closes the bead; when bd refuses that close, for an open child or a live blocker, records the exception `pull_request_merged_close_refused` with the merge's evidence, and files its human gate |
| closed unmerged, merged at another head, or no longer the PR the record names | records the exception, keeps the bead blocked and files a human gate keyed by its value |
| retired by a ruling, whose bead carries the disposition `pr-dispose.sh` records under the record lock before it closes the PR | requests no merge, pours no review run and marks nothing ready while the PR is open. Once the PR has closed and no review run is attached, it closes the asks and the withdrawals still open on the bead, then, with the record lock free, closes the bead onto the ruling's successor through `bead-rehome.sh`, run as the refinery ([state-machine.md](state-machine.md#disposition)). The script closes it only while it still has the status and assignee the run read under the lock and still records the ruling the run read, so a bead reassigned or ruled again once the lock is free goes to the next run, which reads it again. A close the script holds, such as one the ruling's open conversation holds, is tried again by the next run. A retired PR that merged all the same lands as any other |
| a lookup or a fetch that failed, or a merge commit not yet on the target | records why in `pr_reconcile_error`, and the next run reads it again |

**Withdrawals come first.** While the PR is open, a run first carries out each
open withdrawal on the bead, which a review run's triage files when it rules a
head material (`gctk pr withdraw`). It waits while an approval it would dismiss
carries an inline comment the intake has not routed. It dismisses each approval
that stands on a commit that does not contain the withdrawal's head, by
GitHub's compare of the two, or that GitHub refuses to compare, with the
withdrawal's reason and the city's mark, then reads the reviews again and closes
the withdrawal once none stands. When GitHub refuses a dismissal, it files a
human gate on the bead keyed `approval-withdraw-refused`. A compare or a
dismissal GitHub does not answer leaves the withdrawal for the next run. A
withdrawal holds the bead from the refinery until it is carried out, so a
changed head stays assigned to nobody and keeps its marker while one is open,
and the order still reads it.

**The review run.** A run pours a PR's review run, `mol-pr-review`, with
`gc formula cook --attach` onto the bead under the record lock. Its vars are the
record's PR bead, head, target and branch, and the pools and the binding the
refinery's address names (`<rig>/<binding>refinery`): `review_target`
`<rig>/<binding>polecat-codex`, `repair_target` `<rig>/<binding>polecat` and
`binding_prefix` `<binding>`. It pours none while a run is attached to the bead,
while another open bead names the PR's branch, such as a rework child, or while
a human gate holds it. A conversation on the PR holds its merge and nothing
else, so runs are poured while one is open, and the evaluator's wait holds the
merge until it closes. A run that ended without a result is poured again.
When the last two runs at the validated head both ended without one, counting
only runs that ended after the bead's last `review-run-failed` gate closed, it
files a human gate keyed `review-run-failed` instead, naming both runs and how
each ended ([state-machine.md](state-machine.md#checks)).

**A pour cut short.** The pour is one `gc formula cook --attach`. It writes the
bead's input convoy, then the review run, and last, in a write of its own, the
bead's `blocks` edge onto the run's root (`wireFormulaCookGraphV2AttachRoot`,
gascity `cmd/gc/cmd_formula.go`). A launch that stops between the run's write
and the edge's leaves a review run that no edge of the bead names. bd writes
the run in one transaction, so that run is whole, unless a transient failure
had Gas City write it bead by bead (`Instantiate`, gascity
`internal/molecule/molecule.go`), where a launch that stops partway leaves part
of one. A launch stops there when Gas City
ends the order's run at the order's timeout, which ends the run's process group
and each group the run started, the cook's among them (`shellExecRunner`,
gascity `cmd/gc/order_dispatch.go`), when the host goes down, or when the store
fails the edge's write, on which the cook exits non-zero and leaves the run.
The next run of the order then finds no run attached and pours a second at
that head. That costs one more review of the head, because a review run pushes
only under a lease on the head its round judged, and Gas City's claim retires
the first once the refinery is assigned the bead. Gas City does not promise one
run per bead here: each attach onto a bare bead makes an input convoy of its
own, and "A caller that wants stable grouping or dedupe should create and
target an explicit convoy" (gascity
`engdocs/design/convoy-first-formulas-and-drain-v0.md`). Measured on
2026-11-19, the 49 attaches the order made on 2026-11-17 wrote the edge 6 to 21
seconds after the run's root was created, about 10 on average, and none of the
135 review runs poured from 2026-11-17 to 2026-11-19 lacks its edge. The pack
carries no code for this gap, and nothing in it watches for such a run.

**How the refinery hears of a changed head.** A changed head is the refinery's
to take once no withdrawal is open on the bead and no review run is attached to
it. Until then the bead stays assigned to nobody and keeps its marker, so a
later run carries the withdrawal out or reads the run's end, and no run is ever
attached to a bead the refinery is assigned, which Gas City's claim would read
as handed off ([the search](../specs/tk-1tfzr71.209/gas-city-search.md)). The
run then hands the head over in one write that assigns the bead to the
refinery and clears the marker. When nothing holds the bead at that point, Gas
City gives the refinery its turn: an
open bead assigned to the refinery that the store reads as ready is demand that
wakes it, and core's `cascade-nudge-on-blocker-close` order nudges it when the
bead's last blocker closes. A conversation or an ask on the PR holds the bead
too, and holds only its merge, so the refinery's find-work takes the bead past
it, but while one is open Gas City gives the refinery no turn for the bead. So
when only conversations and asks hold the bead, the run hands the head over in
two writes with the wake between them. It assigns the bead to the refinery,
wakes the refinery and nudges it, with `gc session wake` and
`gc session nudge` as a polecat's hand-off does, and only then clears the
marker, so the find-work the wake starts lists the bead. That is the run that
requeues the head when no withdrawal or run holds it, and otherwise the first
run that reads the record after the review run or the withdrawal ends. The
order starts a run every five minutes, but each run reads a bounded number of
records and starts none after its budget (above), so while more records carry
the marker than one run reads, the wake can come several runs after the review
run ends. A wake that does not land keeps the marker and says why in
`pr_reconcile_error`, and the next run that reads the record wakes the
refinery again. The search for a Gas City primitive that covers the wake is
[specs/tk-1tfzr71.165/gas-city-search.md](../specs/tk-1tfzr71.165/gas-city-search.md).

A merge request binds only the head the evaluator judged, so a push that lands
first makes GitHub refuse it, and the next run finds the head moved. The order
turns on no auto-merge, so no permission outlives the decision. A PR that waits
on the operator's approval or on its checks holds no agent: the wait is the
order's next run.

**One record at a time.** Gas City starts no run while the last one's tracking
bead or work is open, but its watchdog closes a tracking bead two minutes after
it was made whether or not its run still works, so the next tick can start a
second run beside the first. Each run therefore reads each record under the
store's record lock, a `flock` on `pr-record.lock` in the store's `.beads`
directory, from its read of the record to its last write of it, and leaves the
lock free a moment between two records so a publication waiting for it takes it
there. Two runs that overlap act on one record one after the other, the second
from the record as the first left it. The refinery's `gctk pr record`, a
review run's `gctk pr withdraw` and `gctk review passed --record`,
`bead-rehome.sh`'s close and `pr-dispose.sh`'s stamp of a ruling's disposition
take the same lock. So a ruling's disposition lands before a run reads the
bead, or waits until the run's last write of it, and a merge the run requests
comes before the ruling, never after it. The kernel frees the lock of a run
the timeout stops, and the records it did not reach wait for the next run. No
webhook fires the order, because an order a webhook fires skips Gas City's
gates and each event would start a run of its own.

**What a run acts on.** A run acts only on a bead it reads under the lock as
carrying the marker, or as an open or blocked bead on the record that carries a
ruling's disposition, with or without the marker, and each write is guarded on
the status and assignee it read. A bead's assignee says who works it now:
nobody while its PR waits, and the refinery while it validates a head the PR
moved to. A bead assigned to anyone else is that assignee's while they work
it. A run does not take it, and a run that reads it assigned after taking it
writes nothing to it, requests no merge and pours no review run. The PR's
status names who holds it, and a later run works it once the assignee is gone.
What takes a PR off the record is a write that says so: the refinery's send-back
to the pool clears the marker in the write that reopens the bead, and a ruling
retires the PR. A human gate on the bead holds its merge and its next review
run.

**The seed audit after a landing.** In a rig whose clone carries
`generated/seed-audit`, a run that closes a bead on a merge into the rig's
default branch, the branch `origin/HEAD` names, then checks that branch's seed
audit with the record lock released. It reads the branch at its tip as the run
fetched it to verify the merge, so the check judges that merge and every one
after it, and a tip that one landing in a run has checked is not checked again
in that run. `render-seed-audit.sh --check-merge <tip> <tip>` renders the tip's
tree once and names each file the tip commits other than as rendered, and the
run hands those files to `seed-audit-reaudit.sh`, which slings the one bead that
re-renders the default branch and lands the new text in a pull request of its
own. The writer runs in the rig's clone, whose `origin/HEAD` it reads, and holds
a lock of its own from its read of the live re-renders to its sling, a `flock`
on `seed-audit-reaudit.lock` in the store's `.beads` directory, so two runs that
land on the default branch at once file one re-render between them. A call that
finds the lock held files nothing. The check holds no PR, so until that
re-render lands, a PR's diff can show render lines it did not change. A check
that does not run holds nothing either: when the default branch or its tip does
not read, the render does not complete, the writer dispatches nothing, or the
run has reached its deadline, the next landing on the branch checks again. The
landing's line says what the check found.

**Reading what a run did.** Each record's outcome prints on a line of its own,
`<bead> <action>: <detail>`, where `readied` names a draft the run marked ready
and `poured` a review run it attached. `gc order history pr-reconcile` lists the runs
with their exits: 0 when every record read was handled, and 2 when the listing
or the lock did not answer or a record's write failed.

## Adjacent order: rig-checkout sync

The live `rigs/*` checkouts are what the runtime executes, and the landing
order merges PRs on GitHub — so a merged PR is **not live** until
`orders/reconcile-rig-checkouts.toml` (every 15m, city-scoped) fast-forwards
each rig checkout:
`git fetch origin && git merge --ff-only --no-overwrite-ignore origin/<default>`.
`--ff-only` mutates nothing on divergence, on a local change to a path the
incoming commits rewrite, or on untracked content in the way of what they write,
and `--no-overwrite-ignore` makes that include an ignored file, which git
otherwise overwrites. A file the incoming commits delete leaves the working
tree with them when its copy is unmodified, so a change that stops tracking a
file a live checkout still needs, such as machine-local config, removes an
unmodified copy of it there. A checkout whose HEAD is off its default branch is
not fast-forwarded. A refused fast-forward and a checkout off its default
branch each file one idempotent human gate per blocked rig (via
`human-gate.sh`, on the rig's subject bead and carrying what git refused and
`git status`). Once the rig fast-forwards cleanly, the gate is withdrawn
`moot:` and the subject bead closes. The 15-minute window is also the exposure behind
component-model I9, watched by `doctor/check-pour-text-current`.
