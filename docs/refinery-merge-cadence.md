---
name: Refinery merge cadence
description: The exec order that drives the merge queue — the driver and its arms, the rc=3 interlock, the single-flight guarantee, and how to read what a pass did. Read it to know what drives merges, and why nothing else may.
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
`scope = "rig"`) execs `assets/scripts/refinery-reconcile.sh`, the ~100-line
driver, which runs the arms in order and exits.

| | |
|---|---|
| Cadence | `interval = "60s"`, tunable from city.toml `[[orders.overrides]]` |
| Scope | `scope = "rig"` — one registration per importing rig |
| Working directory | the rig's own root, so `git remote get-url origin` resolves |
| Environment | controller-built: `GC_RIG`, `GC_RIG_ROOT`, `BEADS_DIR`, `GC_BEADS_PREFIX`, `PACK_DIR`, `GC_PACK_STATE_DIR`, the Dolt projection, the `gh` token |
| Timeout | `timeout = "600s"`, tunable per rig from city.toml `[[orders.overrides]]` — it bounds how long a wedged pass holds the per-rig lock. It must cover a whole pass at the slow end of host load and stay under the driver's `REFINERY_RECONCILE_LOCK_STALL_SECS`, and it does *not* fit inside the controller watchdog's 2m tracking-sweep window |

Anything per-rig is derived inside the driver from `GC_RIG` / `GC_RIG_ROOT`;
one `[order.env]` serves every registration. The refinery agent does not drive
the cadence — the arms run whether or not any refinery session is awake.

## The arms

1. **gate-ensure.sh** — gate satisfiability. Every gating anchor declares a
   non-empty `check_set` (the default is stamped when absent; the `none`
   sentinel is respected), and every declared gate is *raisable*: the lane
   reads `green`, or a live routed review bead is in flight, else dispatch one
   (stamp first, then attach `mol-review` via `gc sling --on`; read the pour
   back). A lane that reads `green` ends the arm's interest however far the
   branch has advanced since — nothing here compares a marker to a head. The
   convergence cap's park also ends it with no dispatch: `signoff.sh` set
   `merge_hold=signoff_cap` (the literal string, distinct from an operator's
   own `merge_hold=true`) with `signoff_cap=<gate>` beside it,
   `gc.routed_to=human`, a `blocked_reason` naming the cap, and
   the shorter `gc.takeaway` headline the helm board renders, in one act. No
   visit is filed for it, so the anchor is parked rather than queued. What
   undoes that is new operator feedback, which arm 5 records: the cap counts
   non-convergence, and a review the branch has never answered is not that
   ([state-machine.md](state-machine.md#the-round-cap-counts-from-the-last-operator-feedback)).
   An anchor capped before its PR was opened can receive neither, and says so
   in its `blocked_reason`; `signoff.sh reset <anchor> --reason <why>` is its
   release.
   A review whose only reach is the pour stamp is qualified before it counts
   as in flight: if its workflow is spent — every step closed but
   `workflow-finalize`, which belongs to the control-dispatcher — no verdict
   can still be coming, and the arm escalates through `escalate.sh` under the
   `review-wedge` key rather than holding the anchor in silence. It escalates
   on the second consecutive sighting, because `mol-review`'s failure arm
   closes its chain before it restores the bead's route. One dispatch is
   refused outright: a head that a closed request-changes verdict already
   judged, whose rework child is still open, can only be answered the same
   way, so the gate stays armed and the merge held until that rework moves the
   head. Behind that sits a ceiling on DISPATCHES —
   `GC_MAX_REVIEW_DISPATCHES`, default 5, and not `signoff.sh`'s round cap —
   for the reviews neither refusal can see: one that ends writing no marker
   and leaving no open rework child returns the anchor to the state that
   triggered the dispatch, so the next pass repeats it at the same head. At
   the ceiling the gate holds, the anchor carries `dispatch_backstop.<gate>`
   and a note saying why, and one visit is filed under the `dispatch-runaway`
   key. **rc=3 is the designed interlock**: it holds `merge.sh` for this
   pass — an anchor whose gates are not yet satisfiable must not be mergeable
   on the same tick — and is reported without failing the order.

   **1a. pre-open-rebase.sh** — the conflict observer for anchors that have no
   PR yet. Every other arm reads whether a branch still merges off the PR
   (`mergeable`, `mergeStateStatus`), and `pr-facts.sh` skips any anchor whose
   `pr_number` is absent before it reads anything else. That is not a narrow
   enumeration one could widen: the facts those arms dispatch on are PR facts,
   so a pre-open anchor has none of them and a widened net routes nothing. This
   arm asks git instead. One fetch per pass mirrors every branch on origin into
   `refs/gc-toolkit/pre-open-rebase/heads/*` — one round trip costs the same as
   38, and this arm holds the pass lock while it runs — pruned, so a branch
   deleted on origin does not linger as a ref the probe would believe. Per
   anchor it then requires both sides to resolve there and probes
   `git merge-tree --write-tree`; a conflict files the same rebase child arm 5
   files for a PR anchor, classified by the same branch allowlist and stamped
   `prepare_mode`. It runs before `pr-open.sh` because that arm ends its
   domain: once an anchor carries a PR, `mergeable` answers the question and
   arm 5 owns the dispatch. Both arms probe children on `metadata.branch` and
   write the same `head <oid>` phrasing, so whichever sees a branch first
   files and the other stands down. The vetoes are arm 5's: `merge_hold`,
   `rebase_hold` on the anchor or on any bead naming the branch, and a live
   demand. A failure here is not a merge hold — an anchor it could not observe
   is left exactly as the pass found it.

2. **pr-open.sh** — `pre_open_gate → pull_request`. For each anchor whose
   every marker-bearing `check_set` gate reads `green` (the same
   predicate `merge.sh` applies, `none`/`off` and `approval` dropped; an empty
   set is held, never read as ungated): adopt an existing PR for the branch or
   `gh pr create` non-draft, re-read the created PR by number, refuse a moved
   head, replay the verdict as a comment (never an approval), then one
   `lifecycle.sh` transition carrying `pr_url`/`pr_number`/`merged_target`.
   The body's `## Summary` is the polecat's `pr_summary`, written at handoff
   by the only actor that has read the diff; the anchor's description is
   dispatch text, demoted to a collapsed section and standing in as the
   summary only when the handoff carried none.
3. **pr-facts.sh --posture-only** — the posture record, and nothing else.
   `merge.sh` answers "is a human waiting on this?" off the bead and never asks
   GitHub, so the value it reads has to be written in the same pass. This arm
   writes `pr_posture` and `pr_merge_state` at the live head for every open
   non-draft anchor, then stops: no dispatch, no watermark, and MERGED/CLOSED
   reconciliation stays with arm 5. A held merge still gets one, because
   recording a fact is not a dispatch, and the pass that finally merges must not
   be reading a posture from a previous tick. **A non-zero rc is the second
   interlock.** An anchor this arm could not make current — an unreadable review
   history, a posture write that did not persist — is one `merge.sh` would
   validate against a fact from an earlier tick, so the driver holds arm 4 for
   the pass. An anchor whose standing posture is already `commented@` is exempt:
   it is holding its own merge, and failing the arm over it would hold every
   other anchor's too.
4. **merge.sh** — `pull_request → merged`. Pinned `gh pr view`, identity gates
   (same repo, not a fork), re-read the anchor and check it still gates this
   PR — open, still `pull_request`, same number, url and head branch. Then
   either the record for a PR already merged, or, for an OPEN non-draft one,
   validate holds/posture/gates/children/approval/base/CLEAN, check that the
   merge result keeps `generated/seed-audit` current, re-read the full
   authorization set immediately before merging, `gh pr merge --squash
   --match-head-commit <validated oid>`, then close + record via one
   `lifecycle.sh` call. The posture it validates is the value **pr-facts
   recorded on the anchor**, never a fresh read of GitHub.

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
5. **pr-facts.sh** — external facts only, no merge authority: PR merged
   out-of-band (record), closed-unmerged (→ `abandoned` + visit), base changed
   (→ `retargeted` + visit), CONFLICTING (one rework child per head),
   hold-resolved retraction. It re-reviews no moved head: a lane state is a
   state of the lane, and only gate-ensure dispatches on it. It also records every open
   non-draft anchor's **posture** — `pr_posture`, `pr_merge_state`, and the
   comment watermarks ([state-machine.md](state-machine.md#posture)) — before
   any of those arms run, and routes unanswered review feedback — under a
   `commented` posture and equally under a human `changes_requested` — to a
   rework child or a visit. The posture write is idempotent, so re-running it
   here after arm 3 costs nothing when nothing changed. Routing lives only in
   this arm: arm 3 records, this one decides what answers it. Each batch it
   routes also resets `signoff.sh`'s round cap, once per batch, retiring the
   cap's own park with it — but only while `merge_hold` still reads the
   literal `signoff_cap` with a non-empty `signoff_cap=<gate>` beside it; an
   operator's own `merge_hold=true` is never that pairing and is never lifted
   by this reset, even past an orphan `signoff_cap`.
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
   one.
6. **convoy-graduate.sh** — all convoy members closed AND ≥1 recorded merge
   onto the integration branch AND no hold/branch veto → assignee=refinery,
   `branch=integration/<id>`, `merge_strategy=mr`.
7. **review-sweep.sh** — cleanup over closed anchors, no merge authority. A
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
   residue is filed by two dispatchers, arm 1 and arm 5.
8. **duplicate-sweep.sh** — the reader for `duplicate_of`, no merge authority.
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
   rebase or rework dispatch that field names the TWIN's branch, so most
   verified no-op duplicates carry one. A bead somebody else owns — assigned,
   `in_progress`, a review bead, a step bead, or already pointed at a different
   successor — is out of the population by construction. It runs after
   review-sweep so a twin that arm 4 merged or arm 5 recorded on this pass is
   disposable on the same tick.
9. **pr-stack.sh** — the beads-on-this-branch section of an open PR's body. No
   merge authority, and the only arm that writes no bead. A body is composed
   once, by arm 2, out of one anchor; commits keep arriving on the branch after
   that and none of them touch it, so a reviewer approves a scope the body does
   not describe. For each open anchor recording a `pr_number`, this arm reads
   the branch's bead ledger — `branch` (committed onto the branch: the anchor,
   plus every rework and rebase hand-back), `fold_target` (folded onto it by a
   polecat), and `merged_target` with `merge_result=merged` (landed its own PR
   into it) — and splices the list into a delimited section at the end of the
   body. The title is left alone: it names the anchor, and the body is where a
   reviewer reads scope. A branch carrying one bead publishes nothing, because
   arm 2 already named it. Idempotence is the rendered section compared against
   the one between the markers, never the whole body, and the body is read
   `\r`-stripped: GitHub stores a body it re-wrapped with CRLF, and a marker
   line carrying a trailing CR would match nothing and append a second section
   every pass. Any read that fails leaves that PR as it stands — a truncated
   ledger published as the whole ledger is worse than last pass's section. It
   runs last, and after arm 4, so a bead this pass landed onto another anchor's
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
rc=3 hold is reported but does not fail the order. Arm 3 is the one that does
both, holding the merge arm and failing the order, because a posture that could
not be recorded is a fault to see rather than a routine gate. Every pass logs to
`<GC_PACK_STATE_DIR>/refinery-reconcile/<rig>/pass.log`, trimmed to
`REFINERY_RECONCILE_LOG_KEEP` lines (2000 default) and not subject to bead
retention. Arms append as they run, so the shape of the log is what tells you
how a pass ended:

| Line | Meaning |
|---|---|
| `=== <ts> rig=<rig> refinery=<agent>` | a pass started |
| `END <ts>` | that pass finished; a `FAILED:` line sits above it if any arm failed |
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
