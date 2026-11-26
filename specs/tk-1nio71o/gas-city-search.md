---
name: Gas City search for moving the work formula's tree onto the claim's worktree
description: Why mol-polecat-work's workspace-setup keeps its own cut of a work bead's tree now that the city's gc carries gc hook --claim --worktree, what the claim's tree is keyed on and which branch and base it takes, the census of a week of runs that tests Gas City's reason in this city, and the fix at the source with the bead that carries it. Read it when judging the work formula's warrant, a proposal to move workspace-setup onto the claim's tree, or a change to assets/scripts/work-setup.sh.
---

# Gas City search for moving the work formula's tree onto the claim's worktree

Read on 2026-11-26 at `gastownhall/gascity` main 77143ecd18ff, and in the city's
gc, 1.4.3 built from the fork at 13cdf670ca, whose `cmd/gc/cmd_hook_worktree.go`
and `internal/worktree/worktree.go` are the same as upstream main's.

## What was decided

`workspace-setup` keeps its own cut of the work bead's tree
(`assets/scripts/work-setup.sh`). The city's gc now carries
`gc hook --claim --worktree` (upstream #9082, b9393bcf41), but the tree that
claim makes belongs to the bead the claim takes, on a branch Gas City names,
made from the rig's `default_branch`. In this city the claim takes a step of a
run, the run's tree serves several steps and several sessions, and the work's
branch and base are the work bead's. The warrant "The work formula's
overrides" says so, and its trigger is the fix at the source below.

## What the claim's tree is

**What it composes.** `gc hook`'s reference gives `--worktree` as "with
--claim, create or verify a gc-owned git worktree for the claimed work"
(`docs/reference/cli.md`). Upstream's reason, in #9082's text: "so a claimed
bead can receive a verified, gc-owned workspace with its receipt". So the
claimed bead is taken to be the work, and everything about the tree follows
from it (`hookClaimWorktreeProvisioner.provision`, `cmd/gc/cmd_hook_worktree.go`):

- **Its key.** The path is `<worktrees root>/<rig>/<claimed bead>`, and the
  receipt, `work_dir`, the work branch and the tree's ownership metadata, is
  stamped on the claimed bead.
- **Its branch.** `gc/<rig>/<claimed bead>`, made new from the base unless a
  local branch of that name exists (`resolveCreationState`,
  `internal/worktree/worktree.go`).
- **Its base.** The rig's `default_branch`, resolved against the rig
  checkout's own refs (`RevParseVerifyCommit`). A rig that sets none is
  refused before the claim: "--worktree requires rig %q to set default_branch"
  (`newHookClaimWorktreeProvisioner`).
- **Its check.** `Verify` wants HEAD attached to exactly that branch
  (`verifyGitState`), and a claim that finds the receipt verifies the tree
  again (`reusePublishedEvidence`). Gas City has no supported move of an owned
  tree onto another branch: upstream #8963 asks for one and is open.

**What the work formula needs.** One tree per work bead, cut by
`workspace-setup` and used by `preflight-tests`, `implement`, each
`self-review` iteration and `submit-and-exit`, which removes it at the
hand-off. Its branch is `polecat/<work bead>` cut from freshly fetched
`origin/<base>`, where the base is the work's target and a caller-set
`integration/<id>` wins, or the branch `metadata.branch` already names, for a
rejected branch or a rework child, which the run brings current by merge.

## The reason, tested in this city

Gas City's reason is that the claimed bead is the work. A census of the city's
stores tested it on 2026-11-26, over every run of `mol-polecat-work` created
from 2026-11-18 to then, in each rig's store:

- **What was counted.** The run roots (`gc.formula_name=mol-polecat-work`,
  closed), the step beads that name each root in `gc.root_bead_id`, with the
  session each step was assigned to, and the work bead each run's input convoy
  tracks (`gc convoy status`), with its `branch`, `target`, `task_kind` and
  `rejection_reason`.
- **The runs.** 252 closed runs in six rigs, 237 that passed and 15 that were
  cancelled, on 247 work beads. Every run had 9 step beads, and none of them is
  the work bead, which no step's claim takes.
- **The tree's sessions.** The steps that work in the tree were claimed by
  three sessions in 199 runs, four in 36 and two in 2, so 237 runs' trees
  served more than one session. 13 ran in one session, and 2 cancelled runs
  never reached the tree.
- **The base and branch.** 48 of the 247 work beads target an integration
  branch, not `main`. 8 ran on a branch that already existed: 4 rework
  children on their anchor's branch and 4 effort landing beads on their own
  `integration/<id>`. 10 resumed a branch with a rejection recorded.
- **The rig's base.** `gc config show` sets `default_branch` for two of the
  city's six rigs and for none of the other four, gc-toolkit among them, so
  `--worktree` refuses in most of the city's rigs before it claims.

So the reason does not hold here. A step's claim is not the work: a claim-made
tree would be one tree and one branch per step, which the next step's claim
neither finds nor verifies, and none on the branch or base the work names.
Setting `default_branch` on every rig would fix only the refusal.

## What else was searched

- **`gc worktree ensure` on the work bead.** The earlier search
  ([specs/tk-1tfzr71.43/gas-city-search.md](../tk-1tfzr71.43/gas-city-search.md))
  found that `gc worktree cleanup` cannot remove a tree at the hand-off, before
  the merge, and the pack removes it with git. That holds at this commit.
- **A session's own tree** (`work_dir` and `pre_start` on the agent). It is cut
  per session, and the run's steps go to different sessions. Upstream #6442,
  open, asks to give those templates the step a session is bound to and its
  root or source bead, because "several steps of one lane share a worktree, so
  keying on the root/source bead rather than the step is what lanes actually
  need". That is the key this formula needs.

## The fix at the source

`gc hook --claim --worktree` would serve this formula if the claim could key
its tree on the work rather than the step it takes, on the branch and base the
work names:

- key the path, the branch and the receipt on the run's root or the bead its
  convoy tracks, as #6442 proposes for a session's tree;
- take the branch and base from that bead, so a new branch is cut from the
  freshly fetched target and an existing branch, such as a rework's, is
  checked out as it stands.

By this reading of the two files it is a change of a few hundred lines with
its tests, in `cmd/gc/cmd_hook_worktree.go` and `internal/worktree/worktree.go`,
and nothing of it is built. gc-jfqa5v in the gascity rig's store carries it,
held for the operator's placement.

Short of that change, #8963's supported move of an owned tree onto another
branch would let the pack move a claim's tree onto the work's branch. That
answers the branch but not the key.

## What it costs to keep the pack's cut

`work-setup.sh` stays, at the path Gas City's claim would use, with its
recorded `work_dir`, which Gas City's closed-bead reaper reads. The warrant's
trigger moves from the build carrying the flag, which has fired, to Gas City
keying a claim's tree on the work it serves.
