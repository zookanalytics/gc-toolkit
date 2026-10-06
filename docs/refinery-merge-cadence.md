---
name: Refinery merge cadence
description: The exec order that drives the merge queue — the driver and its arms, the posture interlock, the arm budgets, the single-flight guarantee, and how to read what a pass did. Read it to know what drives merges, and why nothing else may.
---

# Refinery merge cadence

The merge side of the anchor lifecycle is driven entirely by one order:
`merge.sh` fires only from this cadence, so the cadence *is* the merge queue's
clock. When it stops, gated-green CLEAN pull requests sit unlanded and nothing
else about the city looks wrong — which is why its liveness has its own doctor
check (`check-cadence-live`).

## Scope

**Mandate.** What drives the merge-side writers, what each arm owns, and the
runtime guarantees the arrangement depends on.

**Boundaries.** The states the arms move an anchor through are
[state-machine.md](state-machine.md). The refinery *agent*'s judgment calls
(rejection, blocked, refused) live in `formulas/mol-refinery-patrol.toml` and
are not driven by this order.

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
| Pass budget | `REFINERY_RECONCILE_PASS_BUDGET_SECS` (420, below the timeout; 0 = unpaced) is shared by the seven arms that walk a set growing with the queue: merge (its PRs that cannot land this pass), pr-open, pr-feedback, pre-open-rebase, gate-ensure, pr-facts and pr-stack. Each paced arm's deadline is an equal share of what the budget has left when it starts, never under `REFINERY_RECONCILE_ARM_FLOOR_SECS` (20), and it resumes from its cursor in the pass state dir. Set both per rig through the override's `env` |

Anything per-rig is derived inside the driver from `GC_RIG` / `GC_RIG_ROOT`;
one `[order.env]` serves every registration. The refinery agent does not drive
the cadence — the arms run whether or not any refinery session is awake.

## The arms

1. **pr-facts.sh --posture-only** — the posture record, and nothing else.
   `merge.sh` answers "is a human waiting on this?" off the bead and never asks
   GitHub, so the value it reads has to be written in the same pass. It runs
   first, immediately before merge, so the window in which a newly arrived
   comment goes unseen is only as long as these two arms make it. This arm
   writes `pr_posture` and `pr_merge_state` at the live head for every open
   non-draft anchor, then stops: no dispatch, no watermark, and MERGED/CLOSED
   reconciliation stays with arm 7. A held merge still gets one, because
   recording a fact is not a dispatch, and the pass that finally merges must not
   be reading a posture from a previous tick. **A non-zero rc is the
   interlock.** An anchor this arm could not make current — an unreadable review
   history, a posture write that did not persist — is one `merge.sh` would
   validate against a fact from an earlier tick, so the driver holds arm 2 for
   the pass. An anchor whose standing posture is already `commented@` is exempt:
   it is holding its own merge, and failing the arm over it would hold every
   other anchor's too.
2. **merge.sh** — `pull_request → merged`. It runs the moment its one
   same-pass interlock, the posture record above, is done. Landing is the main
   way an anchor leaves the gating set, and every arm that walks that set costs
   time in proportion to it, so none of them sits ahead of merge: one that did
   could spend the pass budget before merge ran, and a set that stops draining
   keeps growing, which slows that arm further. merge needs nothing
   gate-ensure (arm 6) writes in the same pass. It holds an anchor whose
   `check_set` is empty on its own read, and gate-ensure's review-graph writes
   (a dispatch onto a lane already short of green, the close of a must-fix
   finding whose fix landed) can delay a landing by one pass but never allow
   one early.

   Its own cost grows with the PR set too, so it visits in an order that never
   defers a landing. One `gh pr list` reads every open PR's
   `mergeStateStatus` and `reviewDecision`. An anchor whose PR is `CLEAN` or
   `UNSTABLE` (the only states the merge proceeds on), or `APPROVED` with its
   merge state not yet computed (GitHub recomputes every PR's after a squash
   moves the base), or whose PR has left the open list (merged, which owes the
   record below, or closed), is visited first, and no budget stops that group.
   The rest cannot merge this pass (`BLOCKED`, `BEHIND`, `DIRTY`, or
   unapproved), so a visit there refreshes a verdict and lands nothing. They
   are visited in id order starting after the last one a pass finished
   (`merge.cursor` in the pass state dir), wrapping, until merge's share of the
   pass budget runs out, so every one is reached within a bounded number of
   passes. When the list cannot be read, every anchor joins the first group and
   the arm is not paced.

   Per anchor: pinned `gh pr view`, identity gates
   (same repo, not a fork), re-read the anchor and check it still gates this
   PR — open, still `pull_request`, same number, url and head branch. Then
   either the record for a PR already merged, or, for an OPEN non-draft one,
   validate holds/posture/checks/children/open-visit/approval/base/CLEAN, check
   that the merge result keeps `generated/seed-audit` current, re-read the full
   authorization set immediately before merging, `gh pr merge --squash
   --match-head-commit <validated oid>`, then close + record via one
   `lifecycle.sh` call. The posture it validates is the value **pr-facts
   recorded on the anchor**, never a fresh read of GitHub. The open-visit clause
   is the finalize gate: an open visit tracking the anchor holds its merge
   (`docs/finalize-gate.md`), re-asserted in the terminal re-read because a visit
   filed mid-pass does not move the head.

   Landing and recording are two writes, and a pass killed between them leaves
   an anchor saying `pull_request` over a PR already on the target branch.
   This arm records that PR rather than leaving it to pr-facts: the arms are
   ordered, so a recovery downstream of the merge is reached least often
   exactly when it is needed. The record stands on the same live anchor
   identity the merge does, since it writes merged truth about one PR onto a
   bead that may have moved to another since the enumeration.

   A record that fails is retried on the next pass, which is the whole repair
   for the common cause and no repair at all for a cause the next pass meets
   unchanged. `record-failure-cap.sh` is what tells the two apart: it counts
   consecutive failures in `merge_record_failures` on the anchor and, past
   `GC_MAX_RECORD_FAILURES` (3), files one visit naming the PR, the anchor and
   the by-hand record. The record that lands clears the count. This arm, the
   merge's own record below it, and pr-facts's out-of-band record all call it,
   so the same repair attempted by three writers spends one budget rather than
   three. The count is metadata-only because every refusal it bounds is a
   refusal of the transition's own write, which a bare `--set-metadata` on the
   same bead is not subject to.

   The seed-audit check is the one gate here that is a property of the merge
   rather than of the head. `generated/seed-audit` is rendered from the whole
   source tree and committed per branch, so a PR carrying a render made at an
   older base overwrites prompt inputs it never saw, and two PRs that touch no
   common file still clobber each other. Every `check.<gate>` marker is a
   bare lane state bound to no commit and settles at any head once green, so
   it stays green while the base moves underneath, the pre-commit hook is
   branch-local, a rebase replays commits without running it, and `-diff` in
   `.gitattributes` keeps the clobber out of the PR diff.
   So the arm fetches the two commits into `refs/gc-toolkit/merge-gate/*`, and
   `render-seed-audit.sh --check-merge` re-hashes the merged tree's inputs and
   compares them against `generated/seed-audit/SOURCES.txt` in that same tree.
   That costs hashes rather than a render, and needs no `gc` binary. A drifting
   input, or a probe that cannot answer, holds the merge and files one visit per
   PR under `seed-audit-merge-gate.<n>`, naming the inputs that moved. Nothing
   is routed from here: the way out is to bring the head branch current with
   its base, re-render, and push.

   That manifest is one record per input rather than one digest over all of
   them, and the shape is what keeps this artifact out of the queue's way. A
   repo-global value in a per-branch committed file moves on every seed-input
   edit, so two PRs touching two unrelated agents collide on it whatever else
   they do; per-input records move only where the input moved. The record is
   two lines, path then hash, because git needs one unchanged line between two
   changes to merge them and neighbouring entries in a flat list leave none.
3. **pr-open.sh** — `pre_open_gate → pull_request`. It runs right behind merge
   and ahead of every other arm, because it is what puts a green branch in
   front of the operator for the approval merge waits on. merge reads none of
   its output: the city approves nothing at open (the verdict is replayed only
   as a comment), so a freshly opened PR is never mergeable on the same tick,
   and running after merge costs a PR its open-pass landing only in the
   ungated lane-only case. It needs nothing gate-ensure writes in the same
   pass, for the reasons merge does not. A pass that ends inside this arm still
   makes progress: an anchor it opened has left its domain, and an open
   interrupted before its record is adopted by the next pass rather than
   opened twice. It walks under its share of the pass budget: the anchors
   gate-ensure last recorded as `settled` first (the mark only orders the walk;
   each still meets the full gate), then the rest, with at least one of each
   visited every pass. Each group rotates on a cursor of its own
   (`pr-open.cursor.first` and `pr-open.cursor` in the pass state dir), because
   a settled anchor this arm holds, such as an operator's `merge_hold` on a
   green branch, stays settled, and in a fixed order it would lead every pass
   while the settled anchors behind it waited. For each anchor whose
   every `pre-open` check in `check_set` reads `green` (the one resolver names
   that set — `none`/`off` and the universal `approval` rule dropped; an empty
   set is held, never read as ungated): adopt an existing PR for the branch or
   `gh pr create` — as a draft when `check_set` names an `open-as-draft` check,
   so a preview can deploy before the change is surfaced, else ready — re-read
   the created PR by number, refuse a moved head, replay the verdict as a comment
   (never an approval), then one `lifecycle.sh` transition carrying
   `pr_url`/`pr_number`/`merged_target`. A later pass flips a draft to ready once
   its `open-as-draft` checks are green. That draft-to-ready walk runs after the
   pre-open walk, under the same deadline, and rotates on `pr-open.cursor.ready`
   with at least one draft visited every pass, because a draft the arm holds
   stays a candidate. Each anchor's head comes from one fetch
   of origin's branches per pass, with the API answering when that fetch could
   not and confirming the head before any create, so an anchor parked on a red
   lane costs no API read for its head. Its gates are resolved once at that
   head, and the one answer feeds the gate, the draft decision and the body; a
   resolver that is missing or fails holds the anchor. An adopted draft is the
   refinery's to flip only when the city opened it as a draft and nobody has
   re-drafted it since. Any other draft is adopted without that claim and stays
   with whoever parked it.
   The body's `## Summary` is the polecat's `pr_summary`, written at handoff
   by the only actor that has read the diff; the anchor's description is
   dispatch text, demoted to a collapsed section and standing in as the
   summary only when the handoff carried none. The region writes that heading
   itself, so a `pr_summary` opening with one of its own is de-duplicated. The
   composed body lives between `gc:pr-summary` markers, so adopting an OPEN PR
   re-splices it from the anchor's current `pr_summary` — a rework's restamp
   reaches the published merge surface — while text an operator or `pr-stack.sh`
   added outside the markers stays. A body a create wrote before these markers
   is the same stale-body case: the region is established over its legacy
   `## Summary`…`## Refinery handoff` prefix, keeping what follows, so the
   restamp still lands. A body carrying no such managed region — hand-written,
   or a malformed marker shape — has nothing stale to republish and is adopted
   as it stands; a MERGED PR is a landed record, flipped untouched. A refresh
   this arm cannot verify — an unreadable or unparseable body, a missing head,
   or a scratch failure — holds the anchor at `pre_open_gate` for the next pass
   rather than flip a managed body that may be stale. This adopt-time re-splice
   covers only the `pre_open_gate` window; once the anchor is `pull_request`,
   republishing a rework's restamp is arm 12's job (`pr-stack.sh`), the anchor
   never returning to the state this arm scans (no `pull_request → pre_open_gate`
   lifecycle edge).
4. **pr-facts.sh --route-comments-only** — the feedback routing of arm 7, run
   ahead of the slow arms. Arm 7 runs behind gate-ensure, so a pass the timeout
   kills before arm 7 would leave the operator's review stamped-as-seen by the
   posture yet unrouted while the anchor reads as handled. This arm closes that
   window: it re-reads each open anchor's feedback and dispatches the same
   rework child or visit and opens the same validation pass arm 7 would, then
   stops — no write-back sweep, no external-fact reconciliation, none of the
   arms that belong at the tail. Arm 7 still runs the routing idempotently (a
   landed batch's watermark and `pr_comment_disposition` make the re-run a
   no-op) and still owns the write-back and the terminal-state records. Its rc
   is reported but holds nothing: merge has already run, routing is not the
   posture interlock, and the full pass is the backstop. It runs ahead of
   gate-ensure, so a validation pass it opens is in place for gate-ensure to
   dispatch a validator onto. It walks the PRs in a rotation under its share of
   the pass budget. The observability half is
   `doctor/check-feedback-routing-owed`, which flags an anchor whose posture still
   says a human is waiting with no disposition past a window.
5. **pre-open-rebase.sh** — the conflict observer for anchors that have no PR
   yet. It runs after merge and pr-open, neither of which reads its output, so
   it observes the anchors pr-open left at `pre_open_gate`. Every other arm reads
   whether a branch still merges off the PR (`mergeable`, `mergeStateStatus`),
   and `pr-facts.sh` skips any anchor whose `pr_number` is absent before it reads
   anything else. That is not a narrow enumeration one could widen: the facts
   those arms dispatch on are PR facts, so a pre-open anchor has none of them and
   a widened net routes nothing. This arm asks git instead. One fetch per pass
   mirrors every branch on origin into `refs/gc-toolkit/pre-open-rebase/heads/*`
   — one round trip costs the same as 38, and this arm holds the pass lock while
   it runs — pruned, so a branch deleted on origin does not linger as a ref the
   probe would believe. It walks the anchors in a rotation under its share of
   the pass budget, and per anchor requires both sides to resolve there and
   probes `git merge-tree --write-tree`; a conflict files the same merge-in
   rework child arm 7 files for a PR anchor, stamped `prepare_mode=merge` (every
   branch shape is brought current by merge, never rebase). An anchor pr-open
   flipped this pass carries a PR, where `mergeable` answers the question and
   arm 7 owns the dispatch. Both arms probe
   children on `metadata.branch` and write the same `head <oid>` phrasing, so
   whichever sees a branch first files and the other stands down. The vetoes are
   arm 7's: `merge_hold`, `rebase_hold` on the anchor or on any bead naming the
   branch, and a live demand. A failure here is not a merge hold — an anchor it
   could not observe is left exactly as the pass found it.
6. **gate-ensure.sh** — check satisfiability. Every gating anchor declares a
   non-empty `check_set` (the default is stamped when absent; the `none`
   sentinel is respected), and every declared check is *raisable*: the lane
   reads `green`, or a live routed review bead is in flight, else dispatch one
   (stamp first, then attach `mol-review` via `gc sling --on`; read the pour
   back). A lane that reads `green` ends the arm's interest however far the
   branch has advanced since — nothing here compares a marker to a head. An
   operator's own `merge_hold` also ends the arm with no dispatch: gate-ensure
   raises no review under a hold.
   A review whose only reach is the pour stamp is qualified before it counts
   as in flight: if its workflow is spent — every step closed but
   `workflow-finalize`, which belongs to the control-dispatcher — no verdict
   can still be coming, and the arm escalates through `escalate.sh` under the
   `review-wedge` key rather than holding the anchor in silence. It escalates
   on the second consecutive sighting, because `mol-review`'s failure arm
   closes its chain before it restores the bead's route. No dispatch goes out
   while anything is acting on the anchor — an open `must-fix` finding on any
   lane, a fix unit in flight, a validation pass in flight, or a full review
   already in flight on the lane — which is the QUIESCENCE predicate one
   authority computes so it cannot disagree with itself about whether a review
   was already out. The same authority also releases that hold: it closes a
   `must-fix` finding once every fix unit answering it has closed, so a fix that
   has landed on the branch stops holding the re-gate rather than wedging the
   anchor at `pre_open_gate`. A review that read a mid-change diff would raise
   only the no-op rework the declination texts are full of. There is no dispatch
   ceiling: quiescence forbids the redundant round a ceiling would have bounded,
   and the runaway shapes left — a reviewer that dies after claim, a fix unit
   filed with its edge reversed, a landed fix whose finding that release missed
   — stop the PR moving and are caught by `liveness-sweep.sh`'s stale-gate pass,
   not a count on the check.
   It visits every gating anchor, so its cost grows with the set. It runs after
   merge and pr-open and under its share of the pass budget: it visits the
   anchors in id order starting after the last one a pass finished
   (`gate-ensure.cursor` in the pass state dir), wrapping, and starts no new
   anchor once its share is spent. A slow walk
   therefore delays review dispatch for the anchors it has not reached, and
   nothing else, and every anchor is reached within a bounded number of
   passes. Its rc=3 (an anchor whose `check_set` stamp did not persist, or an
   enumeration it could not read) is reported without failing the order or
   holding anything: merge.sh and pr-open.sh each hold an anchor with no
   `check_set` on their own read.

7. **pr-facts.sh** — external facts only, no merge authority: PR merged
   out-of-band (record), closed-unmerged (→ `abandoned` + visit), base changed
   (→ `retargeted` + visit), CONFLICTING (one rework child per head), `BLOCKED`
   (→ a visit under `merge-blocked-threads`, only where
   `required_review_thread_resolution` is on and a thread is unresolved, read
   from the branch's own rules. A missing required approving review files no
   visit: it is the operator's own review queue, the state the board's review
   section already surfaces from the recorded `pr_posture`. Because such a
   review is state and never an escalation, the cadence also retires any open
   `merge-blocked-approval` visit `moot`, at the top of its run ahead of the
   no-anchors early-exit and in every rig, failing closed on an unreadable
   subject. A cause the rules cannot name — an unmodeled rule, or unreadable
   rules or thread count — escalates nothing and the next reconcile retries.
   `reviewDecision` cannot name the cause alone, reading EMPTY while threads
   are unresolved, so the rules are read directly),
   hold-resolved retraction. It re-reviews no moved head: a lane state is a
   state of the lane, and only gate-ensure dispatches on it. It also records every open
   non-draft anchor's **posture** — `pr_posture`, `pr_merge_state`, and the
   comment watermarks ([state-machine.md](state-machine.md#posture)) — before
   any of those arms run, and routes unanswered review feedback — under a
   `commented` posture and equally under a human `changes_requested` — to a
   rework child or a visit. The posture write is idempotent, so re-running it
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
   A write-back sweep then answers the operator in the PR itself. On an anchor
   carrying `pr_comment_disposition`, every comment at or below the recorded
   watermark gets an EYES reaction, and once the bead that disposition names
   closes, each thread holding one of the comments that bead answers gets one
   reply naming the commit and is resolved behind that reply. The watermark is
   cumulative and a disposition holds one batch at a time, so `pr_comment_batch`
   carries the history it cannot: one `<disposition>|<floor>|<mark>` record per
   batch, oldest first, written in the same transition that advances the
   disposition. A thread belongs to every record whose range holds one of its
   comments and whose disposition names a bead, and it is answered only once all
   of them have landed, by one reply naming each. A record is dropped once its
   batch has nothing left owing. The reactions are written first and bounded per
   pass; when the cap or a failed write leaves one owing, that pass replies to
   and resolves nothing, so no thread is answered over a comment still awaiting
   its acknowledgement. A thread a human answered after the city's own is left
   open, and so is one holding a comment above the mark: no batch covers that
   comment, so nothing has answered it, and resolving would put the thread past
   every later pass. A `visit:` disposition earns the reaction but never a
   reply, because no commit answered it. Idempotence is read back off GitHub,
   so a repeat pass writes nothing and a failed write is retried by the next
   one. The per-anchor walk runs in a rotation under the arm's share of the
   pass budget; the write-back sweep reads only the anchors carrying a
   disposition and is not paced.
8. **convoy-graduate.sh** — all convoy members closed AND ≥1 recorded merge
   onto the integration branch AND no hold/branch veto → assignee=refinery,
   `branch=integration/<id>`, `merge_strategy=mr`.
9. **review-sweep.sh** — cleanup over closed anchors, no merge authority. A
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
10. **scaffolding-sweep.sh** — cleanup over DISPOSED anchors, no merge authority.
   An anchor withdrawn won't-do or closed not-planned carries a disposition —
   `gc.superseded_by` (the pointer `bead-rehome.sh` stamps) or
   `gc.pr_close_disposition_kind` (the intent `pr-dispose.sh` records) — but its
   machine review scaffolding does not close with it: the validation pass, the
   finding beads, and the rework/fix-unit beads stay open, each holding a
   `blocks` edge on the anchor or on a rework that blocks it, and each holding
   gate-ensure's quiescence, so the disposed anchor stands stuck behind work that
   will never land. Nothing else retires them on a disposal: `close-answered`
   keys on a fix LANDING, and `review-sweep` on an anchor already closed. This
   arm closes each `task_kind=validation|finding|rework` bead whose `anchor_bead`
   names a disposed, non-merged anchor — `gc.outcome=moot`, the reason appended,
   read back — findings before the reworks they block so a rework's close is not
   refused the same pass. It leaves `task_kind=review` to review-sweep and
   `task_kind=visit` to the human side, and never closes the anchor itself: that
   is `bead-rehome.sh`'s (via arm 7), held by `finalize-gate.sh` while a human
   visit is owed — which clearing the machine scaffolding here lets land once no
   visit is. A merged anchor is a landing, never a disposal, and is skipped.
11. **duplicate-sweep.sh** — the reader for `duplicate_of`, no merge authority.
   A polecat that diagnoses a duplicate dispatch stamps the marker and parks
   the bead, because polecats never close work beads; with no reader the bead
   waits for a human ruling, one bead at a time. This arm closes the ones that
   are provably safe through `bead-rehome.sh --kind duplicate`, which is the
   one writer of a successor pointer, and leaves every other one alone with the
   reason on stdout. The stamp is never enough on its own: the named successor
   must resolve and be closed or shipped, and the duplicate must be proved to
   have recorded no work — either `work_outcome=no-op`, or no work-product key
   at all (`branch`, `work_dir`, `pr_number`, `pr_url`, `merge_result`,
   `gc.work_commit`). "No work" cannot be read off an absent `branch`: on a
   rework dispatch that field names the TWIN's branch, so most verified no-op
   duplicates carry one. A bead somebody else owns — assigned,
   `in_progress`, a review bead, a step bead, or already pointed at a different
   successor — is out of the population by construction. It runs after
   review-sweep so a twin that arm 2 merged or arm 7 recorded on this pass is
   disposable on the same tick.
12. **pr-stack.sh** — keeps an open PR's body current with its anchor in both
   managed regions. No merge authority, and the only arm that writes no bead. A
   body is composed once, by arm 3, out of one anchor; then two things drift it,
   and this arm lands both fixes in one body edit.

   It walks the open PRs in a rotation under its share of the pass budget.

   The `gc:branch-beads` section: commits keep arriving on the branch after open
   — a fold, a rework or rebase hand-back, a stacked bead's own PR — and none of
   them touch the body, so a reviewer approves a scope it does not describe. For
   each open anchor recording a `pr_number`, this arm reads the branch's bead
   ledger — `branch` (committed onto the branch: the anchor, plus every rework
   hand-back), `fold_target` (folded onto it by a polecat), and `merged_target`
   with `merge_result=merged` (landed its own PR into it) — and splices the list
   into a delimited section. A branch carrying one bead publishes nothing here,
   because arm 3 already named it.

   The `gc:pr-summary` region: a rework restamps the anchor's `pr_summary`, but
   arm 3 composes that region only at `pre_open_gate` and an open anchor never
   returns there, so the published `## Summary` — the merge surface, and the
   squash commit message — would otherwise keep describing superseded work. When
   the region is a well-formed marker pair whose summary is behind the anchor's
   current `pr_summary`, this arm recomposes and re-splices it; a region already
   current, a legacy markerless body (arm 3's adoption path establishes that), or
   a malformed shape is left alone. The recompose uses `refresh` mode: the
   reworked head has not re-signed-off, so the handoff bullet names the head and
   defers to the PR's checks rather than repeating arm 3's pre-open sign-off line.

   The title is left alone: it names the anchor, and the body is where a reviewer
   reads scope. Idempotence for each region is its rendered content compared
   against what the body carries, never the whole body, and the body is read
   `\r`-stripped: GitHub stores a body it re-wrapped with CRLF, and a marker
   line carrying a trailing CR would match nothing and append a second section
   every pass. Any read that fails leaves that PR as it stands — a truncated
   ledger published as the whole ledger is worse than last pass's section. It
   runs last, and after arm 2, so a bead this pass landed onto another anchor's
   branch is named on the same tick.

## Single-flight: the tracking gate and the pass lock

Two `merge.sh` writers against the same anchors is the failure this
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
  surviving.
- The arms inherit the descriptor, so the lock is held for exactly as long as a
  writer is live, and the kernel releases it on any exit, `SIGKILL` included.
- A tick that finds it held logs one `SKIPPED` line and exits 0 — the cadence
  is firing and the pass in flight is doing the work.
- A holder older than `REFINERY_RECONCILE_LOCK_STALL_SECS` (900s default) is
  not a slow pass: the driver is gone and an arm still owns the descriptor.
  That tick exits 1, so `order.failed` names the wedge rather than letting a
  stopped queue look like a firing one.
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
  2m window passes only in a run that also demonstrates one `merge.sh` writer
  across two overlapping ticks. The suite holds the upper bound the same way,
  reading both numbers from the files that set them: a timeout at or above the
  driver's `REFINERY_RECONCILE_LOCK_STALL_SECS` would make a pass that is still
  running read as a wedged one.

Never run a cadence driver out-of-band (by hand, cron, or a daemon). Running
this script by hand at least serialises against the lock; anything else is a
second merge writer that neither the gate nor the lock can see.

## Reading what a pass did

The controller keeps an exec order's output only on non-zero exit, folding a
bounded tail into the `order.failed` event. So: an unexpected arm failure makes
the driver exit 1 (the failing arm names reach `order.failed`); gate-ensure's
rc=3 is reported but does not fail the order. Arm 1 is the one that both holds
the merge arm and fails the order, because a posture that could not be recorded
is a fault to see rather than a routine gate. Every pass logs to
`<GC_PACK_STATE_DIR>/refinery-reconcile/<rig>/pass.log`, trimmed to
`REFINERY_RECONCILE_LOG_KEEP` lines (2000 default) and not subject to bead
retention. Arms append as they run, so the shape of the log is what tells you
how a pass ended:

| Line | Meaning |
|---|---|
| `=== <ts> rig=<rig> refinery=<agent>` | a pass started |
| `-- (<n>) <arm> (started <ts>)` | an arm started; its output follows |
| `-- (<n>) <arm>: done in <s>s (rc=<rc>)` | that arm returned after `<s>` seconds. An arm with a start line and no done line is the one the pass was killed in |
| `<arm>: visited <k> of <n> ...` | how much of its walk a paced arm covered; `the next pass resumes at <id>` follows when its share of the pass budget stopped it. gate-ensure's `<n>` is the size of the gating set every walking arm's cost grows with, and merge counts its landing-first PRs apart |
| `END <ts> (<s>s)` | that pass finished after `<s>` seconds; a `FAILED:` line sits above it if any arm failed |
| a `===` with no `END` under it | the pass was killed or hit its timeout — the arms logged above it are how far it got |
| `--- <ts> rig=<rig> SKIPPED: ...` | the tick found a pass already in flight and did nothing |
| `--- <ts> rig=<rig> STALLED: ...` | the lock has been held past the stall bound; merges have stopped |

**`gc order history` is store-complete only when the read is unbounded.** Any
positive `--limit` — including the default 50, and a limit larger than the row
count — returns runs from the city store alone, printed under a `RIG` column,
so a single-rig answer looks city-wide. Always:

```bash
gc order history refinery-reconcile --since 30m --limit 0
```

Prefer `gc doctor` (`check-cadence-live`) over hand-rolled queries: it asserts
per rig that the order is registered and firing within its interval.

### When a pass drops its merge tail

The log shows how a pass ended, but a killed pass leaves no record of the
approved-clean anchors its merge arm never reached — on the board they look
identical to a healthy "awaiting review". So each pass also stamps a
merge-decision marker, `<GC_PACK_STATE_DIR>/refinery-reconcile/<rig>/merge-decision`,
one line `<phase> <tick> <head>`, as it runs:

| Phase | Written | Meaning |
|---|---|---|
| `started` | before the arms | the pass began; dying here means it never reached the merge arm |
| `reached` | just before the merge arm | the merge arm is about to decide its candidates |
| `held` | when a same-pass interlock holds merge | merge was deliberately not run — a recorded decision, not a drop |
| `decided` | after the merge arm returns | every PR that could land this pass was decided; the ones its budget left for the next pass could not land this pass, so they are not a drop |

The controller kills a pass with SIGKILL, so one that overruns its budget runs
no at-exit code — but the phase it wrote before the kill survives. At each pass's
start, holding the pass lock so the pass that wrote the marker is already dead,
`merge-tail-report.sh` reads it: a marker left at `started` or `reached` while
open anchors still carry `merge_result=pull_request` is a dropped merge tail. It
files one `patrol-finding` naming those anchors, with the head and timestamp of
the pass that dropped them, keyed per rig (`reconcile-merge-tail-dropped-<rig>`)
so a recurrence updates one bead rather than filing another. It names only
anchors still open, so a tail the next pass lands leaves nothing to report, and
it keys on the pass failing to finish its merge decision, never on how long an
anchor has waited — slow-but-legitimate CI never trips it, and a real drop is
never invisible.

## Adjacent order: rig-checkout sync

The live `rigs/*` checkouts are what the runtime executes, and `merge.sh`
lands PRs via GitHub — so a merged PR is **not live** until
`orders/reconcile-rig-checkouts.toml` (every 15m, city-scoped) fast-forwards
each rig checkout: `git fetch origin && git merge --ff-only origin/<default>`.
`--ff-only` mutates nothing on divergence or a conflicting dirty file; on a
refusal the script files one idempotent visit per blocked rig (via
`escalate.sh`, carrying `git status` + `git log <remote>..HEAD`) and
auto-closes it once the rig fast-forwards cleanly. The 15-minute window is
also the exposure behind component-model I9, watched by
`doctor/check-pour-text-current`.
