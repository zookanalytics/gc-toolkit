---
name: Gas City search for the review evidence call's --worktree
description: Use when you judge review-evidence.sh's --worktree flag, or whether a review's gather could leave the directory its calls read to Gas City instead of naming the review's worktree in each call.
---

# Gas City search for the review evidence call's --worktree

Read on 2026-11-08 at `gastownhall/gascity` main 2264fa81082a. The change gives
`assets/scripts/review-evidence.sh` a `--worktree <path>` flag that names the
review's worktree, and every copy of the review gather passes it. The call then
reads that worktree whatever directory the agent's shell is in, so a shell that
never ran the gather's `cd` into the worktree still gets the worktree's records.

## What the search looked for

- **A formula step field that sets the directory a step's commands run in.**
  None. No field of `Step` (`internal/formula/types.go`) names one. It carries
  an id, a title, a description or a file holding it, notes, a type, a
  priority, labels and metadata, its dependencies and waits, an assignee, its
  expand, condition, children, gate, loop, completion, ralph, retry, drain and
  timeout settings, and the formula it came from. A step's description is text
  the agent runs in its own shell, and
  the agent's harness picks that shell's directory. A field could not name the
  review's worktree in any case, because the gather is what makes it.
- **A directory Gas City sets for a script.** Gas City sets one only for a
  script it runs itself. `runOnceNoPreExecRetry`
  (`internal/convergence/condition.go`) runs a check or condition script with
  `cmd.Dir` set to the work dir it was given, else the store, else the city
  ([formula-spec-v2.md](https://github.com/gastownhall/gascity/blob/2264fa81082a/docs/reference/specs/formula-spec-v2.md),
  "A check that cannot be launched"). A check script's exit only decides
  whether its step closes, and its output reaches no agent, so it cannot hand
  a review the lines the gather prints.
- **A Gas City record of the review's worktree.** None. `gc worktree`
  (`cmd/gc/cmd_worktree.go`) ensures, verifies and cleans up an agent's
  workspace for a bead, a direct child of the rig's worktree root with the
  bead's branch on an attached HEAD, never a detached one. A review's worktree
  is a detached checkout at the reviewed commit, in a workspace that
  `review-workspace.sh add` makes ([review-workspace.md](../../docs/review-workspace.md)),
  so Gas City holds nothing about it to look up.

## How the change uses what there is

`gctk rig <check> --check`, the pack's own service, reads the record at the
HEAD of the checkout its directory sits in, and takes no directory flag
(`services/gctk/internal/cli/rig.go`). So the script changes into the worktree
`--worktree` names before it reads, and its git reads and gctk's run there
alike.

## Not built

A directory flag on `gctk rig`. The script's one change of directory covers its
own git reads and gctk's.
