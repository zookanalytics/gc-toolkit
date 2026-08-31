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
| Timeout | `300s` — it bounds how long a wedged pass holds the per-rig lock; it does *not* fit inside the controller watchdog's 2m tracking-sweep window |

Anything per-rig is derived inside the driver from `GC_RIG` / `GC_RIG_ROOT`;
one `[order.env]` serves every registration. The refinery agent does not drive
the cadence — the arms run whether or not any refinery session is awake.

## The arms

1. **gate-ensure.sh** — gate satisfiability. Every gating anchor declares a
   non-empty `check_set` (the default is stamped when absent; the `none`
   sentinel is respected), and every declared gate is *raisable*: marker green
   at the live head, or a live routed review bead in flight, else dispatch one
   (stamp first, then attach `mol-review` via `gc sling --on`; read the pour
   back). An `exception@` marker bound to the live head also ends the arm's
   interest with no dispatch, because it reads as settled. It holds the merge,
   and it says so on the anchor: `signoff.sh` set `gc.routed_to=human` and a
   `blocked_reason` naming the cap in the same act that wrote the marker. No
   visit is filed for it, so the anchor is parked rather than queued. A head
   move past a recorded `exception@` undoes that. The gate is no longer
   settled and one dispatch is re-armed.
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
2. **pr-open.sh** — `pre_open_gate → pull_request`. For each anchor whose
   every marker-bearing `check_set` gate reads `green@<live head>` (the same
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
   (same repo, not a fork, head branch matches), re-read the anchor, validate
   holds/posture/gates/children/approval/base/CLEAN, re-read the full
   authorization set immediately before merging, `gh pr merge --squash
   --match-head-commit <validated oid>`, then close + record via one
   `lifecycle.sh` call. The posture it validates is the value **pr-facts
   recorded on the anchor**, never a fresh read of GitHub.
5. **pr-facts.sh** — external facts only, no merge authority: PR merged
   out-of-band (record), closed-unmerged (→ `abandoned` + visit), base changed
   (→ `retargeted` + visit), CONFLICTING (one rework child per head), a gate
   `green@` or `exception@` at a stale head (one re-review child per head,
   carrying `mol-review`), hold-resolved retraction. It also records every open
   non-draft anchor's **posture** — `pr_posture`, `pr_merge_state`, and the
   comment watermarks ([state-machine.md](state-machine.md#posture)) — before
   any of those arms run, and routes an unanswered review comment to a rework
   child or a visit. The posture write is idempotent, so re-running it here
   after arm 3 costs nothing when nothing changed. Routing lives only in this
   arm: arm 3 records, this one decides what answers the comment.
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
  keep the pass inside the watchdog window — at `300s` it cannot — so the lock
  is what carries single-flight. `refinery-reconcile.test.sh` asserts the pair
  mechanically: a timeout above the 2m window passes only in a run that also
  demonstrates one `merge.sh` writer across two overlapping ticks.

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
