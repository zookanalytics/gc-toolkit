# Worktree reclaim

A polecat works each bead in a git worktree of its own under its agent home,
and records the path in `metadata.work_dir`. Its hand-off to the refinery
removes the tree and deletes the tree's local branch. A tree the hand-off
leaves is the controller's: Gas City's closed-bead reaper removes it once its
bead has closed, the tree reads clean, and a ref reaches every commit in it.
Every checkout is a full working tree, so a tree that nothing removes stays as
a floor under the disk.

## Scope

**Mandate.** What removes a polecat's per-bead worktree and its local
`polecat/<bead-id>` branch, what each removal checks first, what stays, and how
a person releases a tree the controller holds or restores a removed one.

**Boundaries.** Who holds each removal, with its evidence and its limits, is
[authority-map.md](authority-map.md). A review's workspace is
[review-workspace.md](review-workspace.md)'s, an agent's home is
`worktree-setup.sh`'s ([pack-authoring.md](pack-authoring.md)), and harness
scratch is [scratch-reclaim.md](scratch-reclaim.md)'s.

## At the hand-off

`work-submit.sh` removes the run's tree once the branch is pushed, the hand-off
is written and the step is closed. It runs `git worktree remove` without force,
deletes the local branch, and clears `work_dir`. A tree with an uncommitted or
untracked path stays on its branch, and so does a tree that holds a checkout of
any repository or has a directory the walk cannot read. `work_dir` keeps naming
each of them. A run that takes the store-only exit, halts before its push
(`auto_push=false`) or ends before its hand-off leaves its tree on its branch
too.

## The controller's closed-bead reaper

A city turns the reaper on with `auto_reap_closed_bead_worktrees = true` under
`[daemon]` in `city.toml`
([DaemonConfig](https://docs.gascity.com/reference/config#daemonconfig)).
Without it, nothing removes a tree the hand-off leaves. On each tick the
controller lists each rig's registered worktrees with `git worktree list`, run
in the rig's own repository. It removes a tree with `git worktree remove`, never
forced, when all of these hold (`reapClosedBeadWorktrees` in
`cmd/gc/bead_worktree_reaper.go`):

- the tree sits under the city's worktree root for the rig,
  `.gc/worktrees/<rig>/`
- its directory name, or its parent's, carries a bead id with one of the
  city's prefixes, and that bead reads closed in the rig's store
- it is not a named agent's home
- it is older than `auto_reap_closed_bead_worktrees_min_age_minutes`, 10 by
  default, measured from the mtime of its `.git` file
- no bead outside the terminal states names it in `work_dir` or `gc.work_dir`
- no live process and no active session stands at or under it
- `git status --porcelain` reads empty in it, and every commit it holds is
  reachable from a branch, a tag or a remote-tracking ref

A probe that fails holds its tree, and a liveness scan that cannot be read
holds every tree for that tick. A build without upstream b244d69f5 also holds
every tree of a repository whose stash list is not empty. A repository's
worktrees share one stash list, so in such a build one stash anywhere in a rig
holds all of that rig's trees until it is dropped.

The removal deletes the tree's ignored files with it, and the reaper does not
look under the tree first, so a checkout of another repository under an ignored
path goes too. The hand-off keeps a tree that holds such a checkout, so the
checkout is safe until the tree's bead closes, and no longer. That gap is filed
as work on Gas City.

Each removal records a `bead.worktree.reaped` event, which names the bead, the
path, the rig and the branch. A closed bead's tree that the reaper holds records
`bead.worktree.reap_skipped` with the reason when the reaper first holds it, and
again each time the reason changes, so a tree held for days for one reason can
have a single event:

```bash
gc events --type bead.worktree.reaped --since 24h | jq -r '.payload.path'
gc events --type bead.worktree.reap_skipped --since 24h \
  | jq -r '"\(.payload.path)\t\(.payload.reason)"'
```

So the reaper never takes:

- a tree outside `.gc/worktrees/<rig>/`, such as a review's workspace under
  `$TMPDIR`
- a tree whose directory name carries no bead id, such as an agent's home
- a tree that reads dirty
- a tree whose commits no ref reaches

## What stays, and how to release it

A dirty tree stays until a person keeps or discards what it holds. The first
tick that finds it clean takes it.

A tree whose commits no ref reaches stays for good, because removing it would
lose them. A detached tree comes to this when nothing else reaches its commits,
as when its branch is deleted locally, then from origin by a squash merge, and
then from the remote-tracking refs by the next `git fetch --prune`. The reaper
names such a tree in a `bead.worktree.reap_skipped` event whose reason carries
`unreachable=true`, so read back far enough to reach that event, or check the
tree itself, which prints each commit no ref reaches. To release such a tree,
pin its HEAD with an annotated tag. The tag keeps the commits, and the next
tick takes the tree:

```bash
gc events --type bead.worktree.reap_skipped --since 168h \
  | jq -r 'select(.payload.reason | contains("unreachable=true")) | .payload.path' | sort -u
git -C <tree> log HEAD --oneline --not --branches --remotes --tags
sha=$(git -C <tree> rev-parse HEAD)
git -C <tree> tag -a "archive/worktree/<bead>@${sha:0:12}" "$sha" \
  -m "worktree <tree> (bead <bead>) pinned so the controller can remove it
Restore: git -C <repo> worktree add <path> archive/worktree/<bead>@${sha:0:12}"
```

## Branches

The hand-off deletes the local `polecat/<bead-id>` branch with the tree.
Nothing deletes the branch that a kept tree, a store-only exit, a halt or a run
that ended before its hand-off leaves behind. The controller's reaper deletes
no ref, and core's `prune-branches` order reads only `gc/*` branches and
deletes with `git branch -d`, which refuses a squash-merged tip. Such a branch
costs one ref. It keeps the commits of work that never landed reachable, so the
controller can still take the tree they sit in once its bead closes.

## Restoring a removed tree

A repository's `archive/worktree/<bead>@<sha>` tags each pin the tip of a tree
that was removed or released. A tag can be the only ref to the commits it pins,
so none is deleted. Its message names the tree's path and its bead, and the
command that restores it:

```bash
git -C <repo> tag -l 'archive/worktree/*'
git -C <repo> cat-file -p archive/worktree/<bead>@<sha>
git -C <repo> worktree add <path> archive/worktree/<bead>@<sha>
```

Restore to a path outside `.gc/worktrees/`. A tree restored at its old path
belongs to its closed bead again, so the controller takes it once it is 10
minutes old. The restored tree is detached at the tag, and
`git -C <path> switch -c <branch>` puts a branch there to work on.
