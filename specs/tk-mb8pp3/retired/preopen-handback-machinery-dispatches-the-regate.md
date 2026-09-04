---
name: preopen-handback-machinery-dispatches-the-regate
description: "On a pre-open rework hand-back the reconcile pass dispatches the re-review within ~30-60s, so the refinery's job is the terminal close, not the dispatch"
metadata: 
  node_type: memory
  type: project
  originSessionId: 1423de36-c238-4464-8ebe-a42867c29b72
  modified: 2026-08-14T17:50:00.220Z
---

When a rework bead is handed back on a **pre-open** anchor, `reconcile-merged-prs.sh`
(stale-gate arm) dispatches the codex re-review on its own, typically **30–60
seconds** after the hand-back. Confirmed three times on 2026-08-14: `tk-agzpl`
(hand-back 17:48:04 → `tk-hcnp8` at 17:48:58), `tk-7h51d` (17:25:47 →
`tk-4kwlz`), `tk-5savt` (→ `tk-ndu4o`). Each time a state check moments earlier
had reported *no review in flight*.

So the refinery's actual job on these hand-backs is the **one-anchor-per-PR
terminal close** — note the landing on the anchor, close the rework bead as
landed-on-branch — not the dispatch.

**Why:** a state check and the act it guards are separate round-trips, and the
machinery reliably lands inside that window. A dispatch decided from the earlier
reading mints a twin review on the same branch+anchor.

**How to apply:** put the `EXISTING_REVIEW` dedup **inside the acting script**,
immediately before the create — never in a prior tool call. Use
`assets/scripts`-style lookup on `task_kind=review` + `review_branch` +
`anchor_bead` with `--status=open,in_progress`. The reusable driver lives at
`scratchpad/rework-handback.sh` (resolves the anchor by branch equality, refuses
to twin, enforces the ROUNDS cap, verifies `anchor_bead` persisted before
closing, and never rebases or pushes). Same lesson as
[[dont-move-a-head-under-a-live-review]]: a check that does not gate the action
is a log line. Related: [[refinery-rework-handback-one-anchor]],
[[refinery-pre-open-regate-strand]].

**2026-08-20 — the dedup-in-the-acting-script is NOT sufficient; do the CLOSE ONLY.**
Followed the "How to apply" below exactly — dedup on `task_kind=review` + `review_branch` +
`anchor_bead`, `--status=open,in_progress`, immediately before the create, same script, no
prior tool call — and still minted a twin: mine `tk-2wyxa` 09:05:56Z, check-set-heal's
`tk-rviza` 09:05:59Z, 3 seconds apart on `tk-fdstg`/`polecat/tk-fdstg`. The dispatcher here
was check-set-heal's **`fixable@` re-gate arm**, which fires the moment the rework child stops
being `acting()` — and a hand-back makes it stop being acting (assignee non-empty) BEFORE the
refinery gets to run its arm. So the two dispatchers are racing on a window no same-script
dedup can close: there is no shared lock, only two independent reads.
**Revised rule: on a pre-open rework hand-back, run the terminal close and nothing else.**
Do not dispatch, not even with a guarded dedup. If check-set-heal has not re-gated by the time
you close, it will on the next pass — `fixable@<head>` with no open remediation child and no
acting review is exactly its dispatch condition.
**And prefer ITS review if you do end up with two:** the machinery's bead carries the
`review --blocks--> anchor` edge that close-on-land and the rework arm walk; a hand-rolled one
typically has `anchor_bead` only, which is just the fallback. Close yours as the duplicate,
then correct any anchor note that named it.

**Same day — the "close only" rule has ONE exception: the CONVERGENCE CAP.**
`check-set-heal.sh` has no rounds/cap logic at all (grep `MAX_REVIEW_ROUNDS` — the only `cap`
hits are about a bead-scan LIMIT, not review rounds). The cap lives solely in the refinery's
formula arm and the polecat's done-template. So deferring the dispatch every time also defers
the only place the refinery enforces the cap, and past it check-set-heal will keep dispatching
round N+1 forever.
**So: count rounds BEFORE you close, every time.**

    ROUNDS=$(gc bd dep list "$ANCHOR" --direction=down -t blocks --json \
      | jq '[.[] | select((.metadata.source_review_bead // "") != "")] | length')
    # then: DC=$(anchor metadata.dispatch_count); [ "$DC" -gt "$ROUNDS" ] && ROUNDS=$DC

**The edge type is `blocks`, not `parent-child`, and the anchor's
`dispatch_count` can outrank the child count.** Copied from `signoff.sh`'s
own `count_rounds` (it reads `--direction=down -t blocks`, then takes
whichever is larger of that count and `metadata.dispatch_count`). Verified on
anchor tk-7k4862, 2026-08-27: `-t parent-child` returned 0 while three rework
children (tk-1wc0xj, tk-4ju1w9, tk-9vfmrq) hang off it as `blocks`. A refinery
running the `parent-child` form reads 0 rounds on every anchor, concludes it is
under the cap forever, and never runs the arm that is the only thing standing
between a non-converging anchor and an endless re-gate. `rejection_reason` is
the cheap cross-check: signoff writes `round $((ROUNDS + 1))` into it, so
"round 3" on the newest child means the count was 2 when that child was filed.

Below `${GC_MAX_REVIEW_ROUNDS:-3}` -> close only, let the machinery re-gate. At or above it ->
you must actively run the cap arm instead (`gc.routed_to=human` + `blocked_reason` on the
anchor, escalate through `escalation-gate.sh`, and do NOT touch `check.<gate>` — see
`signoff-cap-no-gate-write`), because nothing else will. Related:
[[refinery-convergence-cap-arm]].


**2026-08-27 — the dispatcher is now `assets/scripts/gate-ensure.sh`.**
`check-set-heal.sh` and `pre-open-resolve.sh` are gone from gc-toolkit; do not
grep for them. Arm 1 of the merge cadence is `gate-ensure.sh`, called by
`refinery-reconcile.sh`, and its anchor enumeration is
`gc bd list --status=open --metadata-field merge_result=<state> --limit=0`
(`assets/scripts/gate-ensure.sh:286`). It is **route-blind** — it never reads
`gc.routed_to` — so the only thing that hides an anchor from the re-gate is
`status != open`. It also refuses a dispatch that cannot produce a new answer
(a head a closed request-changes verdict already judged whose rework child is
still open) and carries a `GC_MAX_REVIEW_DISPATCHES` backstop distinct from
signoff.sh's convergence cap.

**So a polecat's `gc hook --claim` on a parked anchor IS the strand.** Confirmed
on tk-q2v159: parked `pre_open_gate` at 20:01Z, the gascity detached-orphan lane
re-stamped `gc.routed_to=<rig>/gc-toolkit.polecat` ~50s later (gc-gf1l6, specced
at `specs/tk-eh64m/parked-anchors-and-pool-demand.md`), the pool offered it, and
the claim flipped `open -> in_progress` where gate-ensure stops seeing it. The
round-2 re-gate could not fire until the claim was released.

**`lifecycle.sh transition` cannot perform that release.** It writes
`--status=closed` only under `--close`; there is no arm that writes
`status=open`. A self-edge `--to pre_open_gate --assignee ""` clears assignee
and route and leaves `in_progress` intact. Release with a direct
`gc bd update <id> --status=open --assignee=""`, and clear the route in a
SEPARATE EARLIER write — the intermediate `open + unassigned + routed` is the
pool's offer predicate, so route-first, claim-release-last. See
[[refinery-quiesce-split-update-claim-guard]] for the same ordering rule.
