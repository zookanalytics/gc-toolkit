---
name: Disposing of a stranded graph.v2 step or root
description: Why gc workflow delete-source matches nothing for convoy-poured graph.v2 chains, what the old witness disposal actually did to a step and a root bead, and the disposal that replaced it.
---

# Disposing of a stranded graph.v2 step or root

`mol-witness-patrol` step `recover-orphaned-beads` part 5 disposed of every
non-visit orphan with one line:

    gc workflow delete-source <bead> --apply && gc workflow reopen-source <bead>

tk-k08jiv reported that the first half matches nothing for graph.v2 chains and
asked two questions: whether `delete-source` keys on something those chains do
not carry, and what the correct disposal for a stranded step or root is.

## Why delete-source matches nothing

`delete-source` resolves roots through `sourceworkflow.ListLiveRoots`, which
lists beads whose `metadata["gc.source_bead_id"]` equals the id it was handed
and then filters them through `WorkflowMatchesSource`. The match is an exact
comparison on that one key.

The key is written in `internal/sling/sling_core.go`, in `doStartGraphWorkflow`,
and only when the pour carries a non-empty `sourceBeadID`. A molecule poured
from an input convoy passes none. Its root carries `gc.input_convoy_id` and no
`gc.source_bead_id`, and the source bead gets no `workflow_id` back-link either,
so the linkage is absent in both directions.

Measured against the gc-toolkit rig on 2026-09-02: 0 of 9 live graph.v2 roots
carry `gc.source_bead_id`. So `already_clean` is a false clean for these chains
rather than a correct answer, and it is false whichever of a chain's four ids
the command is handed. The gascity-side gap is tracked as tk-990pcv.

## What the old disposal did

The bug report inferred the consequence. Running the shipped disposal against a
step bead and a root bead in the hermetic harness measured it.

A **step** came out `status=open`, `assignee=""`, `gc.routed_to` still pointing
at the polecat pool. That is a pool's offer predicate exactly. `reopen-source`
clears `gc.session_affinity` and `gc.continuation_group`, but not
`gc.session_id`, so the released step also still named the dead session. Open,
unassigned, routed, and pinned to a session that will never return is the
re-offerable husk shape.

A **root** came out `status=open`, `assignee=""`, routed to the polecat pool,
which offers the molecule root itself to a worker as if it were work.

Neither call closed anything, because neither could match.

## The disposal that replaced it

`assets/scripts/orphan-dispose.sh` owns part 5 and picks by what the bead is.
Four kinds reach it and two are returned to the pool.

**visit** — release the assignee and nothing else. Its route, continuation
group and task_kind are its identity.

**workflow-step** — release the dead session's pin and preserve the chain.
`gc.session_id`, `gc.session_affinity` and `gc.continuation_group` are cleared;
`gc.routed_to`, `gc.step_ref`, `gc.root_bead_id` and the dependency list stay.
The molecule resumes at the same step under whichever pool member claims it
next. Nothing is closed, so no close can ready a downstream step and mint
duplicate work, and a step that is still blocked stays unofferable on its own
dependency edges.

**workflow-root** — skip, and write nothing. Nothing claims a root. It closes
when its `workflow-finalize` step closes, and its chain is recovered through
its steps, which are candidates in their own right. Setting it open, unassigned
and routed is what manufactures the shape where a pool offers a root as work.

**source** — `delete-source --apply` then `reopen-source`, the contract those
two commands were built for, with `reopen-source` skipped when the close fails.

### Write order

bd's claim guard refuses an assignee change on an in_progress bead with a live
holder and rejects the whole update, so a release batched into one call rolls
back every field while reporting success. Each field gets its own call:
metadata first, which needs no claim; then status, whose intermediate state of
open, assigned and routed is invisible to a pool; then the assignee, guarded on
`--if-assignee` so a bead re-claimed in the meantime is left alone. The script
re-reads the bead afterwards and exits 3 when only some fields landed, because
a half-released bead needs an escalation rather than a retry.

The guard is the assignee, not the owner, and the two are easy to conflate. The
host-bead-skip filter resolves an owner by precedence over `gc.session_id`,
`assignee` and `gc.session_name`, so on the shape this disposal most often
receives — a step whose dead owner is its `gc.session_id`, sitting beside an
assignee that names the still-live pool slot — they are different strings.
Guarding on the owner would mismatch and refuse exactly the releases that matter.

## Population

Of the 23 owned candidates the host-bead-skip filter admitted in the gc-toolkit
rig on 2026-09-02, 11 were source beads, 4 visits, 4 graph.v2 roots and 4
graph.v2 steps. Roughly a third of every recovery pass was reaching the arm that
could not dispose of it.

## Not changed here

The **source arm** keeps its behavior. The missing linkage means `reopen-source`
also returns a source bead to the pool while its molecule is still live, so a
second molecule can be poured on it. Closing that needs either the gascity-side
linkage or a reverse walk from the bead through each live root's
`gc.input_convoy_id` to the convoy's children, and it is tracked on tk-990pcv
rather than guessed at here.

Part 3's **salvage** arm reads `work_dir` and `branch`, which a step or root
never carries, so its husk guard refuses and escalates `witness-salvage-refused`
for beads that never had a worktree. That is tk-5c1syj.
