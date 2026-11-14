---
name: Gas City search for the refinery's scripts on Gas Town's flow
description: The Gas City, Gas Town and git primitives searched for each piece of operational surface unit 4 of the merge effort (tk-1tfzr71.75) adds beyond what the merge design's own search record covers, what each search found at a named upstream commit, and what the unit composes or why the primitive does not cover the need. Read it when reviewing the refinery's patrol scripts, or when the arch check asks for their search.
---

# Gas City search for the refinery's scripts on Gas Town's flow

Read on 2026-11-12 at `gastownhall/gascity` main 6bd609f5bfb4 and at
`gastownhall/gascity-packs` main 7f86098c04ea, the commits the merge design was
read at, and in git's own documentation for 2.56. The merge design's record,
[gas-city-search.md](../tk-1tfzr71.66/gas-city-search.md) on this branch,
covers the refinery's selection of work, the requeue, the PR the refinery
takes, the per-rig switch and the long gate, which `refinery-find-work.sh`,
`refinery-requeue.sh`, `refinery-publish.sh`, `refinery-land.sh` and
`refinery-gate.sh` compose as that record says. This record covers the rest.

## The push under a lease (`branch-push.sh`)

The need: every city push onto a branch goes under git's lease on the commit
the writer read there, and never forces (the design, section 4): the refinery's
publication and hand-back, the integration-effort hand-off, the polecat's push
at submit and the witness's salvage push.

- **Gas City** has no push of its own. Its CLI reference
  (`docs/reference/cli.md`) offers a push only as `gc build-image --push`, for
  an image.
- **Gas Town's** merge-push pushes an existing PR's branch with
  `git push origin HEAD:$BRANCH --force-with-lease`, a lease that names no
  commit (`gastown/formulas/mol-refinery-patrol.toml` at 7f86098c04ea, step 1
  of its `mr` arm). That bare form compares against the remote-tracking ref,
  which every worktree of a rig shares and any fetch moves (tk-ni0i48p).
- **git** offers `--force-with-lease=<refname>:<expect>`, the one form of the
  lease its documentation does not call experimental, which sends the update
  only while the ref holds `<expect>`, and with an empty `<expect>` only while
  the ref does not exist ([git-push](https://git-scm.com/docs/git-push)).

What the unit composes: git's explicit lease, after its own check that the new
head descends from the commit read, since a lease that matches also sends an
update that is not a fast-forward. One script holds that pair, because five
writers need it and step text holds no procedure.

## The refinery's tree for a bead (`refinery-lib.sh`, `refinery-prep.sh`)

The need: the refinery prepares one bead's branch in a worktree of its own,
merges the target in there, runs the rig's gate there, and removes the tree in
whatever state the gate or a conflict left it, without moving the HEAD of the
directory its session starts in.

- **Gas City's** `gc worktree ensure` makes a worktree "with the bead's
  uniquely named branch checked out on an attached HEAD (never detached)", at a
  direct child of the per-rig root, and `gc worktree cleanup` "refuses dirty
  worktrees, commits reachable from no branch, tag, or remote-tracking ref, and
  commits not merged into --base", with "no force mode"
  (`docs/reference/cli.md`, `gc worktree`). A prepared head is a merge commit
  that no ref reaches until it is pushed, and that is never merged into the
  base when the work goes back to the pool, and a gate can leave files in the
  tree, so cleanup refuses the trees the refinery must remove.
- **Gas Town's** rebase step prepares the branch in the refinery's own working
  directory, on a local `temp` branch, and checks out the target again at the
  end (`gastown/formulas/mol-refinery-patrol.toml` at 7f86098c04ea). The pack
  starts each agent home only when the home is on its own branch or detached
  at a commit the default branch contains (`assets/scripts/worktree-setup.sh`,
  `sync_worktree`), so a session ended between the prep and the checkout would
  leave the refinery unable to start.

What the unit composes: a plain `git worktree` per bead under the refinery's
own home, at `worktrees/<bead>`, the layout gc writes a polecat's per-bead tree
in and which the home's sync reads as gc's own, detached at the commit read,
and removed with git's `worktree remove --force --force`.

## The commit the prep read (`refs/worktree/refinery/<branch>`)

The need: each script takes the bead it acts for, and refuses a bead whose
branch is not the one checked out in the refinery's tree (tk-w0hkwos), and the
push leases on the commit the prep read on that branch.

- **Gas City's** worktree provenance is stored in the private git directory of
  a worktree `gc worktree ensure` made, which the tree above is not (the
  previous section).
- **git** keeps refs under `refs/worktree/` per worktree: "refs inside
  refs/bisect, refs/worktree and refs/rewritten are not shared"
  ([git-worktree](https://git-scm.com/docs/git-worktree#_refs)), and they go
  with the worktree.

What the unit composes: one per-worktree ref, `refs/worktree/refinery/<branch>`,
naming the commit the prep read on `<branch>`. Its name is the branch the tree
holds, and its value is the lease every later push of the iteration takes. No
file of the pack's own records either.

## The patrol's own loop (`refinery-patrol.sh`)

The need: the validate-identity and next-iteration steps each call one tested
script (the design, section 10, rule 2).

- **Gas Town's** steps hold the identity check and the pour-then-burn as shell
  in step text (`mol-refinery-patrol.toml` at 7f86098c04ea, validate-identity
  and next-iteration).
- **Gas City** pours and burns a wisp with `gc bd mol wisp` and
  `gc bd mol burn`, and has no command that pours a patrol's next iteration.

What the unit composes: Gas Town's two steps, moved into one script that calls
`gc bd mol wisp` and `gc bd mol burn`, with the pack's patrol finding for an
empty identity.

## The integration-effort hand-off (`effort-bring-current.sh`)

The need: the refinery brings an integration effort's branch current with its
target when a hand-off asks (tk-gmjtb2e), and its push takes the lease.

- **Gas City's** `gc convoy land` "Land[s] an owned convoy, verifying all
  children are closed", closing the convoy bead (`docs/reference/cli.md`). It
  moves no branch. The convoys member (tk-1tfzr71.23) moves efforts onto it,
  and the hand-off goes with the difference it ends (the design, section 1).
- **Gas Town** has no integration efforts.

What the unit composes: the hand-off as the refinery's prompt carried it, moved
into a tested script whose push goes through `branch-push.sh`.
