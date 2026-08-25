---
name: Cutover runbook — 2026-08 rewrite (PR #465)
description: Directions for the OUTSIDE AGENT the operator hands this to. One-shot; delete with assets/scripts/cutover-2026-08.sh once the cutover is done.
---

# Cutover runbook

You are an agent running OUTSIDE the city, in the city's checkout, with `gc`,
`bd`, `gh`, and `git` on PATH. The operator is reachable; anything below that
says OPERATOR is their decision, not yours. Work the steps in order.

## Sequence

1. **Quiet the city.** Stop filing new work and let the polecats drain their
   claims. To be extra safe, put open anchors on hold so nothing new enters the
   merge queue: `bd set-state <anchor> hold=external` on each open anchor
   (record the list — you will lift these holds in step 6).

2. **Approve and merge PR #465.** The pack replacement lands on the default
   branch. Do not restart anything yet.

3. **ff-sync the rig checkouts** with the city still up but quiet, so the new
   scripts exist on disk: `git -C rigs/gc-toolkit pull --ff-only` for each rig
   (or wait one 15m reconcile-rig-checkouts tick). Confirm
   `assets/scripts/cutover-2026-08.sh` now exists in the rig checkout.

4. **Run the sweep — BEFORE shutdown.** The sweep writes through the bd data
   plane, so it must run while that is still up:

       assets/scripts/cutover-2026-08.sh sweep            # dry-run, review it
       assets/scripts/cutover-2026-08.sh sweep --apply    # then write

   Review the dry-run output before `--apply`. Exit 0 = clean. Exit 1 = the
   summary table's OPERATOR column is non-zero; see failure handling below.
   Re-run `--apply` after resolving — it is idempotent and re-does nothing.

5. **Shut down and restart the city** so the new pack config loads in one
   clean reload. No partial reloads: down, then up.

6. **Run the post-restart checks**, and lift any holds set in step 1:

       assets/scripts/cutover-2026-08.sh verify

   Exit 0 = all green (helm binary fresh and serving, doctor green, all 9 pack
   orders registered). Exit 1 = see failure handling below.

7. **Expect and allow, without intervening:**
   - the first witness patrol re-pools claims held by dead sessions — orphaned
     work beads getting re-routed is recovery, not a defect;
   - the first refinery cadence pass is the first live execution of the new
     merge writer. The operator attends the first merge — watch the pass log
     and the PR itself — before anyone walks away.

8. **Clean up.** Once verify is green and the first merge has landed, delete
   `assets/scripts/cutover-2026-08.sh`, `assets/scripts/cutover-2026-08.test.sh`,
   and this runbook in a follow-up commit.

## Failure handling

**Sweep exits 1 (OPERATOR items).** Each item is printed with the bead id and
why the script refused to write:
- *closed bead over an OPEN PR*: the ledger says done, GitHub says in-flight.
  The operator decides: reopen the anchor (it re-enters the merge queue after
  restart) or close the PR. Then re-run `sweep --apply`.
- *no PR identity / identity did not certify / unreadable store*: the operator
  inspects the bead by hand and records the real terminal state via
  `assets/scripts/lifecycle.sh`, or fixes access and re-runs.
- *molecule with unclosable steps*: something still blocks a step bead after
  10 passes; inspect its `blocks` deps, clear or close them, re-run.

**Verify: doctor non-ok.** Read each non-ok line — the checks name the bead
and the invariant. A sweep gap (healer key, unlanded closed bead) means re-run
`sweep --apply` and then doctor again; anything else goes to the operator
before the city is considered cut over.

**Verify: helm stale or restart-pending.** The served dashboard would be
yesterday's build. Re-run `assets/scripts/gc-helm-build.sh --deploy`; if the
restart keeps failing, `gc service restart helm` by hand and re-run verify.

**Verify: orders missing.** The new pack config did not fully load — check
`gc order list` against `orders/*.toml`, and redo step 5 as one clean
down/up rather than reloading in place.
