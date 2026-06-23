---
name: Work-bead state machine
description: The lifecycle a unit of work moves through as one bead, and which evidence — pull request, review bead, CI — drives each transition between dispatch and closure. Read it to know what a bead's status is allowed to mean.
---

# Work-bead state machine: a bead closes when its work merges

## Scope

**Mandate.** The lifecycle of a single unit of work as it moves through
gc-toolkit: the states a work bead occupies from dispatch to closure, the
transitions between them, and the evidence — pull request, review bead, CI,
approval — that drives each transition. It owns one invariant above all:
**what `closed` is allowed to mean.** It also owns the claim that a convoy is
*the same machine* applied to an aggregate, not a second machine.

**Boundaries.** This doc covers the *states a bead moves through*, not the
*routing* that delivers it to an agent — the field-level contract (sling vs
direct assignee vs `gc.routed_to`) lives in
[gascity-routing-model.md](gascity-routing-model.md). It describes the
refinery's role *in* the machine, not the refinery's full patrol loop, which
lives in the `mol-refinery-patrol` formula. It is not a command tutorial.

## The invariant: `closed` means merged

Everything is a bead. A unit of work is a single bead that holds its own
state; the PR, branch, review bead, and CI are **evidence** that drive its
transitions — not separate truth. A work bead is `closed` only when its work
is **merged to its `target`**: "done" means landed, never "handed off."

This is **locality of truth**: the bead you query tells the truth about its
own doneness without a tree-walk. A still-open bead is still-unmerged work;
a closed bead is merged work, with `merged_sha` naming the commit. Nothing
in between reads as done.

`target` is not always `main`:

- **standalone bead** — `target == main`.
- **convoy child** — `target ==` the integration branch; `main` moves later,
  at graduation.
- **non-PR work** (research, docs-only, investigation) — scope-complete with
  no merge; closed by the worker itself when the artifact is posted. This
  path is unchanged by close-on-merge and is out of the PR machine below.

## The machine (one work bead)

```
gc sling
  -> open . gc.routed_to=<pool>                              -- pool demand
       -> polecat claims -> in_progress . assignee=polecat        (builds on polecat/<id>, sets target)
            -> hands off  -> open . assignee=refinery . branch,target set
                 -> refinery direct-mode: FF-merge to target, push
                 |     -> closed . "Merged to $TARGET at <sha>" . merge_result=merged
                 |
                 -> refinery mr-mode: push branch, open (draft) PR
                       -> GATING . open . assignee="" . gc.routed_to="" . pr_url,pr_number set . merge_result=pull_request
                       |    -- gates hang off the anchor as deps: the codex review
                       |    -- bead BLOCKS it; GitHub approval + CI are gate conditions
                       |
                       |- PR merges       -> closed . "Merged to $TARGET at <sha>" . merge_result=merged
                       |- a gate fails    -> rework: SAME anchor re-routed to the fix pool
                       |                     (open . rejection_reason . gc.routed_to=<fix-pool>) -> polecat reworks
                       \- PR abandoned    -> open . merge_result=abandoned . gc.routed_to=human (escalated)
```

### States

| State | Status | assignee | gc.routed_to | Marker |
|---|---|---|---|---|
| pool demand | open | — | `<pool>` | `branch` unset until claimed |
| building | in_progress | polecat | — | `work_dir`, `branch` |
| handed off | open | refinery | — | `branch`, `target` |
| **gating** | **open** | **—** | **—** | `pr_url`, `pr_number`, `merge_result=pull_request` |
| rework | open | — | `<fix-pool>` | `rejection_reason` set, `merge_result` **cleared**, PR fields (`pr_url`, `pr_number`, `branch`) retained |
| closed (merged) | closed | — | — | `merged_sha`, `merge_result=merged` |
| abandoned | open | — | `human` | `merge_result=abandoned` (escalated to mayor) |

The **gating** state is the one close-on-merge adds. The anchor stays open —
its PR has not merged — but it is detached from both work queues on purpose:

- `assignee=""` so the refinery's find-work query (`assignee=$GC_AGENT`,
  `status=open`, has `branch`) does **not** re-grab it and re-open the PR in a
  loop; and
- `gc.routed_to=""` so an open + unassigned anchor is **not** read as pool
  demand (the pool-demand coupling: open + unassigned + `gc.routed_to` set =
  demand). See [gascity-routing-model.md](gascity-routing-model.md).

A gating anchor is therefore invisible to find-work and to the pool
reconciler. The thing that watches it is the merge-detection pass.

### Movers

- The **polecat** builds (`open -> in_progress -> hands off`) and reworks.
- The **refinery** is the only mover that reaches `closed`. It opens the PR,
  transitions the anchor to gating, and — on a later idle pass — detects the
  merge and closes. The refinery's *active* endpoint is still PR-created: it
  hands the bead to gating and moves on; it does **not** babysit a PR to
  merge. Closure is reconciled, not awaited.
- **Gates** are conditions, satisfied by the codex review bead, CI, or a
  human approval. They are pluggable; the machine is blind to who staffs
  them.
- No coordinator (mayor / mechanik / deacon / witness) sits in this loop.

### Transitions the refinery drives on an idle pass

The refinery's `find-work` step, when no work is assigned, runs three
convergent reconcile passes each idle wake (cheap, idempotent, modeled on the
town's other reconcilers — config-drift drain, witness orphan-recovery):

1. **draft-PR reconcile** (`reconcile-draft-prs.sh`) — un-draft a codex-gated
   PR once its review has concluded and no rework is in flight. Both the idle
   gating anchor and an in-flight rework anchor carry `pr_number`, so the
   "rework in flight" guard discriminates on `merge_result`: the **idle**
   gating anchor carries `merge_result=pull_request` and is *excluded* (else it
   would pin its own PR in draft forever), whereas a **rework** anchor has had
   `merge_result` cleared by the REQUEST_CHANGES transition and so is *kept* as
   in-flight — the PR stays draft until the fix is resubmitted and the refinery
   re-stamps `merge_result=pull_request`.
2. **merged-PR reconcile** (`reconcile-merged-prs.sh`) — for each open gating
   anchor (`merge_result=pull_request`):
   - PR **merged** -> close the anchor, `"Merged to $TARGET at <sha>"`,
     `merge_result=merged`, `merged_sha=<merge commit>` — mirroring
     direct-mode's close.
   - PR **closed, unmerged** -> the **abandoned** path: flip
     `merge_result=abandoned`, route to `human`, escalate to mayor once. The
     anchor stays open and honest (the work did not land) but is now flagged,
     not silently lingering.
   - PR **open and ready** (not draft) -> best-effort `gh pr merge --auto` so
     the merge lands automatically once approvals + checks pass. Branch
     protection (a required approving review) still gates the actual merge —
     auto-merge only removes the manual "merge" click, it does not let the
     refinery self-merge.
3. **convoy graduation** (`reconcile-graduated-convoys.sh`) — the convoy half of
   close-on-merge, runs *after* pass 2 so the same wake that closes a convoy's
   last merged child graduates the now-complete convoy. For each **owned**
   integration convoy whose members are all closed, it assigns the convoy bead
   to the refinery as an ordinary mr-mode work bead (`branch=integration/<id>`,
   `target=main`, `merge_strategy=mr`); the next iteration lands
   integration->main behind a human-approved PR. Owned-only and rig-scoped —
   the non-owned auto-convoys (per-sling tracking bundles) are never touched.
   Idempotent: a convoy already carrying `branch` (graduation initiated) is
   skipped. Gated on `integration_branch_auto_land` (default on; the kill-switch
   is `"false"`). See "One level up" below.

This is why merge-detection is reconcile-driven rather than a poll loop: the
refinery never sits and polls GitHub as a primary trigger. `gh pr merge
--auto` lets GitHub do the merging; the convergent close pass does the
bead-closing; out-of-band polling is only a backstop.

### Gates are deps, not a back-pointer

The codex review bead **attaches as a dependency of the open anchor**: the
review bead BLOCKS the anchor (`gc bd dep <review> --blocks <anchor>`). The
dependency graph now shows, directly, which bead is on which PR and what gate
it waits on — the visibility that closing-at-PR-creation used to eject from
the graph during a work item's most contended phase.

This retires the old **backward `work_bead` pointer** (a review bead that
pointed at an already-closed work bead). Rework resolves the anchor by
walking the edge the other way — `gc bd dep list <review> --direction=up -t
blocks` — and re-routes that **same anchor** back to the fix pool. One unit
of work stays one bead across every review round; rework never spawns a
parallel fix bead that would leave two open anchors on one PR.

## One level up: a convoy is the SAME machine

A convoy is a bead whose members are work beads (joined by tracks). It runs
the identical machine — instantiated with a different ready-gate and target,
and the levels **chain through the target**:

| | ready-to-merge when... | target | `closed` means |
|---|---|---|---|
| work bead | its code gates pass | `integration/<id>` | merged to integration |
| convoy | all its members are closed | `main` | integration merged to main |

It graduates *through* the work-bead machine itself, and **system-auto**: a
convergent find-work pass (`reconcile-graduated-convoys.sh`, pass 3 above)
detects an owned convoy's completion and assigns the convoy bead to the refinery
with `branch=integration/<id>`, `target=main`, `merge_strategy=mr`; the refinery
then walks it `in_progress -> PR -> merge -> closed` like any bead. So it is
**recursion** — one machine, defined once, applied to an aggregate — not a
duplicated second machine. The target chain (member ->
`integration/<id>` -> `main`) threads the levels.

No coordinator drives this loop — no mayor, no `gc convoy land`. `gc convoy
land` remains available as a manual bead-state-flip primitive, but it is not the
graduation driver. Graduation is scoped to **owned** integration convoys; the
non-owned auto-convoys (the per-sling tracking bundles) carry no integration
branch and auto-close on their own — they never graduate.

Because a convoy child now closes on **merge to its integration branch**
(not at PR-creation), a convoy's completion gate shifts from "all children
PR-created" to "all children merged." That is the more correct gate — the
integration branch actually contains the children's work before graduation —
but it is the reason close-on-merge and the graduation path are designed
together. This is the **interlock**: "all members closed" now means "all
members merged," so graduation can never assemble a half-built integration
branch. An abandoned child stays open (escalated, not closed), so it keeps the
convoy incomplete and blocks graduation until a human resolves it.

**Bootstrap.** The graduation mechanism cannot graduate the change that
introduces it: this pack delta (the graduation pass together with
close-on-merge) lands to `main` by an ordinary human-approved PR, like any other
pack change.

## Deliberate divergence from stock GasTown

Stock GasTown mr-mode closes the work bead at **PR-creation**. gc-toolkit
keeps it **open through gating and closes on merge**, so `closed` always
means merged and the dependency graph always shows who is on which PR. This
is a pack-only delta — it lives entirely in the `mol-refinery-patrol` formula
and its reconcile scripts; gascity core is untouched and gains no new status
(`gating` is a metadata marker on an ordinary `open` bead, not a core state).
Direct-mode and non-PR/research beads are unchanged.
