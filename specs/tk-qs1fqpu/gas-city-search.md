---
name: Gas City search for sending a conflicted effort bring-current to a polecat
description: Use when you need the evidence that the refinery's sending a conflicted bring-current of an integration effort's branch to the polecat pool composes Gas City and bd primitives, which upstream symbol each part uses, or why the merge goes to the pool as a new task rather than as the hand-off itself.
---

# Gas City search: a conflicted effort bring-current goes to a polecat

The refinery's `effort-bring-current` block brings an integration effort's
branch current with its target. When the merge conflicts, the block now files
the merge as a task on the effort's branch, with the hand-off and the landing
bead waiting on it, records the hand-off's notice, and slings the task to the
rig's polecat pool on `mol-polecat-work` with `--merge direct`. Before, it put
the conflict to the operator in a `bring-current-conflict` human gate. The
block grows by that send.
The change adds no script, metadata key, bead kind, lifecycle state or order.
Each primitive searched is below, with what it covers.

Read at `gastownhall/gascity-packs` main 1f6d8e41c, `gastownhall/gascity` main
6bd609f5b and `gastownhall/beads` main 125c62063, on 2026-11-12.

## Who resolves a conflict

**Gas Town's refinery sends a conflict to the polecat pool, never to a
person.** Covers the rule. In `gastown/formulas/mol-refinery-patrol.toml`, the
rebase step's arm "If rebase FAILED (conflicts)" puts the work bead back in the
pool with `rejection_reason="Conflicts with $TARGET at <sha>"` and
`gc.routed_to` set to the rig's polecat pool, and keeps the branch because the
"new polecat needs it for conflict resolution". `gastown/formulas/mol-polecat-work.toml`
says the same from the polecat's side: "If there's a conflict, the refinery
puts the bead back in the pool with `rejection_reason` metadata — a new polecat
picks it up and resumes from the existing branch", and its resume step resolves
the conflicts. The change follows that rule: the refinery detects the conflict,
and a polecat resolves it.

**Why the merge goes to the pool as a new task.** Gas Town sends back the bead
whose own `branch` conflicts, and the polecat resumes that branch. The hand-off
has no branch of its own. The branch it brings current is the effort's, which
the landing bead records and which reaches the default branch only through the
landing bead's PR, and a polecat pushes only its own branch. So the merge
reaches the pool as a bead of the effort, shaped as the integration-effort
recipe files every one: the effort's branch as its `target`, under the effort's
epic, with the landing bead waiting on it. The polecat's branch is cut from the
effort's branch, and the refinery lands it there, as it lands every bead of an
effort.

## What composes the send

**Filing the task with its waits in one write: `bd create`.** Covers it.
`cmd/bd/create.go` defines `--deps`: "'blocks:id' reverses direction (id
depends on this issue)". So `--deps "blocks:<hand-off>,blocks:<landing bead>"`
makes both wait on the task in the create that files it, with `--parent` and
`--metadata` in the same write. No write leaves the task filed while the
hand-off does not wait on it.

**The branch the work starts from and lands on: the bead's `target`.** Covers
it. `BeadMetadataTarget` in `internal/sling/sling.go` reads the bead's own
`target` metadata "used for branch targeting" before any parent's, so a task
whose `target` is the effort's branch starts its workflow from that branch, and
the pack's refinery lands it there.

**Sending it to the pool on a formula: `gc sling <target> <bead> --on <formula>`.**
Covers it. `docs/reference/cli.md`, "gc sling": `--on` is "attach wisp from
formula to bead before routing", and a v2 formula is routed "with gc sling
<target> <bead> --on <formula>". The block slings the task to the rig's
polecat pool on `mol-polecat-work`, the formula that every bead of an effort
runs.

**Landing the task as a fast-forward of the effort's branch: `gc sling --merge direct`.**
Covers it. `cmd/gc/cmd_sling.go` defines `--merge` as the "merge strategy:
direct, mr, or local". `SlingMergeStrategy` in `internal/sling/sling.go`
resolves "the explicit --merge value the caller passed" ahead of the
`default_merge_strategy` recorded on the rig, and `doStartGraphWorkflow` in
`internal/sling/sling_core.go` stamps the result on the work bead as
`merge_strategy` when a v2 formula is slung. The pack's refinery lands a bead
stamped `direct` whose target is not the default branch as a fast-forward of
that target, so the polecat's merge commit reaches the effort's branch with
the effort's target as its second parent. Without the flag, a rig whose
default is `mr` would have its task stamped `mr` and landed through a pull
request, which `gctk merge` merges by squash, and the hand-off would meet the
same conflict again.

**Bringing the hand-off back once the task lands: the hand-off's notice.**
Existing pack surface, unchanged. The recipe records the notice
(`deferred-dispatch.sh notify`) when it files the hand-off, and the conflict
path recorded it again behind the human gate. It now records it behind the
task. Gas City's core order `cascade-nudge-on-blocker-close`
(`internal/bootstrap/packs/core/orders/cascade-nudge-on-blocker-close.toml`)
also nudges the hand-off's assignee when the task closes. A nudge sends "text
input to a running session" (`docs/reference/cli.md`, "gc session nudge"), and
the hand-off's return already rests on the notice, so the change keeps that and
adds nothing beside it.

**The task's priority before the sling: `queue-priority.sh settle`.** Existing
pack surface, unchanged. The block settles the task before it slings it, as the
pack's other writers that sling a bead do, so its workflow is poured at the
effort's priority.
