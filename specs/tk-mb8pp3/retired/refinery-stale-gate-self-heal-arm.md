---
name: refinery-stale-gate-self-heal-arm
description: "head-moved-past-codex-marker stall is now AUTO-healed by reconcile-merged-prs.sh's stale-gate arm (needs --review-pool); check for the in-flight re-review before hand-dispatching; ABSENT marker is NOT auto-healed"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 1275d9ba-ea8f-4766-8838-a09a88480238
  modified: 2026-07-30T05:13:24.494Z
---

As of 2026-07-23 the refinery reconcile block's `reconcile-merged-prs.sh` has a
LIVE stale-gate self-heal arm (WS4 GAP1). For an OPEN gating anchor whose
`check.codex=green@<oid>` and whose PR head advanced PAST `<oid>` with NO rework
bead filed (a direct push / operator fixup — the su-PR#31 stall), it files a
codex RE-REVIEW child at the live head, routed to `--review-pool`, anchored to
the gating anchor (`anchor_bead` + BLOCKS edge), bounded one-per-head via
`stale_gate_head`. This is the case [[refinery-merge-gate-human-approval]] calls
"real stall = stale head-bound check.<name> with NO open review bead" — it is
now AUTOMATED, not a manual refinery dispatch.

**Why:** the arm is idempotent + twin-avoiding (reuses an in-flight review,
respects an already-green marker, skips if any open child references the PR). I
nearly hand-dispatched a duplicate re-review for PR#204 (head moved
a012918→9e89480); the arm had ALREADY filed `tk-h51jg`, and its twin-avoidance
was the only backstop to my duplicate. Hand-dispatching races the arm.

**How to apply:**
- Before dispatching a re-review for a stale-marker/head-moved PR, CHECK for an
  in-flight review child first: `gc bd list --metadata-field pr_number=N
  --status open,in_progress` (task_kind=review, anchor_bead=<anchor>). The arm
  likely already did it.
- If you run `reconcile-merged-prs.sh` BY HAND, pass BOTH `--fix-pool` AND
  `--review-pool <codex pool>` — omitting `--review-pool` makes the self-heal
  silently no-op (I ran it degraded once this session; the summary line then
  omits the `stale-gate re-reviews routed/held` counters entirely).
- The formula (`mol-refinery-patrol.toml`) + `assets/scripts/*` are shared
  symlinked files and can SYNC MID-SESSION. Re-read the formula's reconcile
  invocation before reconstructing it from an earlier read — the `--review-pool`
  arg AND the script's stale-gate counters both appeared between two reads this
  session (a pack sync at ~17:40 rewrote both).

**Boundary — ABSENT marker is NOT this arm's job.** The arm fires ONLY on
`green@<oid>` (stale-GREEN). An ABSENT/empty `check.codex` (never reviewed —
e.g. a rework hand-back that moved the head, or a design PR codex never greened)
is left to the normal dispatch / rework-handback flow. Verified this session:
PR#219 anchor `tk-zgse0.2` had `check.codex` ABSENT after the tk-zgse0.2.1 doc
git-mv landed, and NO automated pass (check-set-heal skips already-normalized
check_set; the stale-gate arm needs green@) dispatched it — the refinery hand-
dispatched the codex review per [[refinery-rework-handback-one-anchor]].

**Interlock — an OPEN rebase/rework child SUPPRESSES the self-heal arm, so the
agent's handback dispatch is the PRIMARY path (not a twin-race).** Verified
2026-07-30 (PR#224 / anchor `tk-16753`, rebase child `tk-kc5z0`): the arm's
in-flight probe selects any bead with the anchor's `pr_number`, `id != anchor`,
and empty `merge_result`. A rebase/rework child carries exactly that shape
(`pr_number` set, no `merge_result`), so WHILE it is open the arm hits
`skipped++; continue` and does NOT re-dispatch — even though the gate is
stale-GREEN. So when you process a rebase-handback (green@old != live head after
the polecat force-pushed), hand-dispatching the re-review during the merge-push
one-anchor-per-PR flow is CORRECT and does not race the self-heal arm: the child
you are still holding open is what suppresses it. The fail-closed ORDER matters —
dispatch review → verify `anchor_bead` recorded → THEN close the child — so there
is never a window where neither the arm nor the agent owns the re-dispatch. Do
NOT stamp `merge_result` on the child (gateless 2nd anchor) and do NOT close it
before the review's `anchor_bead` verifies. See also
[[refinery-anchorless-open-pr-blindspot]], [[doc-relocation-rework-pure-git-mv]].
