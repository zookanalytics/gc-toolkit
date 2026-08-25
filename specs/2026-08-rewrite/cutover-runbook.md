---
name: Cutover runbook — 2026-08 rewrite (PR #465)
description: Directions for the OUTSIDE AGENT the operator hands this to. One-shot; delete with assets/scripts/cutover-2026-08.sh once the cutover is done.
---

# Cutover runbook

You are an agent running OUTSIDE the city, in the city's checkout, with `gc`,
`bd`, `gh`, and `git` on PATH. The operator is reachable; anything below that
says OPERATOR is their decision, not yours. Work the steps in order.

## Sequence

0. **Verify the dog seam — BEFORE anything else.** The rewrite drops the
   gastown dog pool, but the `dolt` builtin pack (a required builtin) may
   still route Dolt maintenance to it. With the city up, record the answers
   to both:

       gc order list                                   # any dog/dolt-maintenance orders?
       gc bd list --status open --limit 0 --json \
         | jq -r '.[] | select((.metadata["gc.routed_to"] // "") | test("dog")) | .id'

   Report the results to the operator before proceeding. If a backup or
   cleanup order routes to a dog pool that no longer exists, its beads will
   sit unclaimed after cutover and **Dolt backups stop silently** — the
   deacon will FLAG every database ~12h later with no actor behind the flag.
   The operator decides the replacement (see decisions-and-todos.md TODO-4)
   before the quiet window closes.

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

4b. **Wire the learned-rule lint into the gc-toolkit rig** (operator-approved,
   2026-08-24). In the town repo's `city.toml`, on the gc-toolkit rig entry,
   set the rig's lint command to run the learned-rule detectors over the
   change set, matching the shape the rig's other `*_command` keys use:

       lint_command = "tools/lint-learned.sh $(git diff --name-only origin/main...HEAD)"

   The runner exits 0 on an empty file list. This rig only — the pack ships
   the tool; each rig owns its own gates.

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

9. **File the follow-up work.** After `verify` is green, the outside agent
   files each item below as a bead in the city — one bead per item, routed
   normally. The operator's rule: scoped follow-ups must become slung work,
   not doc notes.

   1. Implement review-gates per `specs/2026-08-review-gates/scope.md`.
   2. Implement gctk per `specs/2026-08-review-gates/gctk-promotion.md`,
      including the helm build-status row.
   3. Resolve the proactive-placement open question
      (`specs/2026-08-review-gates/scope.md`, Costs and open questions):
      where proactive/first-reaction sits once triage exists.
   4. The Dolt backup actor decision, from step 0's findings.
   5. The `docs/architecture.md` re-ratification conversation with the
      operator.
   6. LAYOUT STABILITY: nothing leaves the operator's view without explicit
      human action, board AND tmux. Board: banding/ordering in
      `services/helm` `internal/board/derive.go` (closed may sink, never
      vanish). Tmux: explicit dismiss replaces idle cycling for converse
      sittings; pane-lifetime/session-lifetime decoupling evaluated via the
      upstream ladder (gascity local-patch candidate).
   7. LEARNING V2: audit city feedback history to populate the operator
      profile; widen the distiller's output vocabulary beyond prose bullets
      (profile entries, review-rubric amendments, exemplar diffs); add a
      repeat-feedback recurrence report (obs.category supports counting) as
      the loop's success metric.
   8. REVIEW-WEDGE VISIBILITY: a poured review abandoned without a verdict
      or restore (agent died after closing its step chain) still holds its
      gate silently — add a liveness-qualified escalation (escalate.sh,
      deduped situation key) to gate-ensure's exec-stamp-only reach once
      live-city step/convoy semantics can be probed; stub-based tests cannot
      pin that probe.
   9. I1 DOCTOR CHECK (carried from PR #469, whose diff targets the old
      doctor): check-wait-is-an-edge — assert every wait is a graph edge,
      not a metadata string (component-model I1). Rebuild in the new doctor
      layout (`doctor/check-state-space` is the model); I1 and I9 are the
      only component-model invariants without a check in this tree.
   10. ONE SCRUBBER (carried from PR #461): the tree still carries ~22
       inline `tr -d` control-character scrub definitions across
       assets/scripts and tools; consolidate to one shared helper with one
       byte set, and a lint-learned detector to hold it.
   11. WORK FEEDER (carried from PR #464): nothing converts ready beads
       into dispatches (252 ready unrouted, oldest 123d, at last count).
       Fold this evidence into bead 1 (review-gates/triage) — the feeder is
       a triage-design decision, not a bolt-on arm.
   12. PLAN-TO-BEADS PIPELINE (carried from PR #455): a merged plan's
       targets do not reliably become beads (the consolidation plan dropped
       its largest target silently). Decide the mechanism that makes a
       landed plan's target list a filing checklist.
   13. NON-CODE GATE CALIBRATION (carried from PR #454): spec/design beads
       ride the code merge gate with a code-calibrated round cap. The
       mechanism exists (per-anchor check_set `none`/`approval`,
       GC_MAX_REVIEW_ROUNDS); write the doctrine/default that applies it to
       non-code beads.

   Superseded open PRs: when the operator confirms this branch has landed,
   close the open zook-bot PRs it obsoletes, each with a one-line comment
   naming the disposition — superseded by the rewrite (#447, #448, #449,
   #450, #456, #458, #459, #460, #462, #463, #467), re-filed as the bead
   above (#454, #455, #461, #464, #469), or carried onto this branch
   directly (#466 and #468: the continuation-group writer/reader guards;
   #457: doctor/check-pour-text-current). The gc-na313/PR#159 anchor-close
   incident is likewise carried: the close decision left the agent surface
   in the rewrite, and this branch adds the lifecycle.sh close/terminal
   pairing guard, the sanctioned `lifecycle.sh reopen` repair, and the I4
   anchor-shape filter — the reopened gc-na313 needs no further repair
   beyond landing this.

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
