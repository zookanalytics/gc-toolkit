---
name: Gas City search and census for retiring the pack's worktree machinery
description: What tk-1tfzr71.10 looked for in Gas City before deciding which of the pack's worktree reaper, wrapper and convoy check could go, what the live city showed, and why the work split into a rollout. Read it when judging the home wrapper's warrant, the reaper's cutover, or the per-bead move onto gc worktree.
---

# Gas City search and census for retiring the pack's worktree machinery

Read on 2026-11-01 at `gastownhall/gascity` main 6b90a9fb22ff and
`gastownhall/gascity-packs` main 0b0d96250f66. The city's deployed `gc` is the
fork's 1.4.3 at e03752646, which is named only where it is what runs. The census
ran read-only on the live city at about 06:20Z, with load near 60.

## What was decided

| The bead's part | Outcome |
|---|---|
| `orders/convoy-check.toml` | Already gone: an earlier change deleted it, so core's `convoy-autoclose-backstop` is the only hourly `gc convoy check`. Nothing to do. |
| `worktree-reap.sh`, its order, its test | The controller's reaper replaces the worktree pass, in the three stages this bead's description asks for. tk-1tfzr71.40 turned the dry run on, tk-1tfzr71.41 compares and turns reaping on, and tk-1tfzr71.42 deletes the pack's copy, keeping the branch pass as a residual if it still has work to do. |
| `worktree-setup.sh` | Stays, as agent home provisioning under a warrant. `gc worktree` cannot provision a home. This bead fixes the stuck-slot problem it carried and removes what no case needs. |
| The per-bead tree | tk-1tfzr71.43 removes it at hand-off, so a tree never reaches the state the controller's reaper refuses, and moves its creation to `gc worktree ensure` where that holds. It waits on tk-1tfzr71.12's `work-setup.sh` and `work-submit.sh`, where those calls will live. tk-1tfzr71.42 waits on it. |
| `review-workspace.sh reap` | Stays. Review worktrees live under `$TMPDIR`, and the controller's reaper drops anything outside `.gc/worktrees/<rig>/` before any gate, so no dry run is needed to answer this. tk-1tfzr71.22 reshapes reviews. |
| `scratch-reap.sh`, `build-scratch-reap.sh` | Stay, as the description says. |

## What Gas City provides, and where it stops

**The closed-bead reaper** (`reapClosedBeadWorktrees`, `cmd/gc/bead_worktree_reaper.go`;
`auto_reap_closed_bead_worktrees` and its `_dry_run` and `_min_age_minutes` twins in
[DaemonConfig](https://docs.gascity.com/reference/config#daemonconfig)) covers the
worktree pass, with these differences from the pack's:

- It reads the bead from the directory name, or its parent's, and needs no
  `metadata.work_dir`. Dotted ids such as `tk-1tfzr71.4` pass its shape check.
- It holds a tree while a non-terminal bead names it in `work_dir` or
  `gc.work_dir`, while a live process or active session stands at or under it, or
  while it is dirty. It also holds a tree whose commits no branch, tag or
  remote-tracking ref reaches. The pack pins such a tree with a tag and removes it.
- It runs `git stash list` in each tree. A repository's worktrees share one stash
  stack, so one stash anywhere in a rig holds every tree in that rig
  ([gastownhall/gascity#8093](https://github.com/gastownhall/gascity/issues/8093)
  reports the same refusal in the sibling prune path, and is open).
- It has no 24-hour horizon: a tree older than 10 minutes qualifies as soon as its
  bead closes. It ignores open pull requests and live beads on the branch, which
  loses nothing, because removing a clean tree leaves the branch ref.
- It never removes a ref. Core's `prune-branches` reads `gc/*` only and deletes with
  `git branch -d`, which refuses a squash-merged tip, so renaming work branches to
  `gc/*` would not cover them either. tk-1tfzr71.42 keeps the branch pass unless its
  work has shrunk to nothing worth a script.
- It sees only `.gc/worktrees/<rig>/`
  ([gastownhall/gascity#5760](https://github.com/gastownhall/gascity/issues/5760)
  asks to widen that).
- It re-evaluates every candidate on each controller tick: at least three git
  calls per tree, serially. For the 107 candidates below that took 8.9 s at load 63, against
  the town's 30 s `patrol_interval`. Real reaping drains the set, and the dry run
  does not, so the dry run's window is the costly part.

**`gc worktree`** ([reference](https://docs.gascity.com/reference/cli#gc-worktree),
`internal/worktree/worktree.go`) probed with the deployed binary in a scratch
repository:

- `ensure` requires `--bead`, `--store-ref`, `--creator`, `--owner` and
  `--generation`, and an attached HEAD on the named branch. It never moves an
  existing tree, and writes no redirect and no excludes.
- A path inside a registered worktree is refused (`rejectRegisteredWorktreeAncestor`),
  so `<home>/worktrees/<bead>` cannot be used even with `--root` set to that
  directory. `.gc/worktrees/<rig>/beads/<bead>` works.
- On an existing tree it refuses a detached HEAD and a different `--owner`, so it
  fits creation only, with values a re-dispatch can reproduce.
- No core formula and no pack in `gascity-packs` calls it. Core's `mol-polecat-commit`
  and `mol-scoped-work` use `git worktree add`.
- `ensure` returns its evidence for the caller to publish on the bead, and the
  controller reads it there: `gc.work_dir`, `gc.work_branch` and the `gc.worktree_*`
  keys (`worktreeSpecForBead`). With all of them it starts a pool session inside that
  tree (`verifiedPoolTriggerWorkDir`), it leaves a start candidate out when they do
  not verify, and `gc hook --claim` from any other session skips the bead. So a tree
  that goes at hand-off has to take that evidence with it, which tk-1tfzr71.43
  carries. A fresh bead has no such evidence, since no caller runs `ensure` before a
  session exists, so its session still starts in a home.

**Agent homes.** Gas Town's polecat and refinery run
`gastown/assets/scripts/worktree-setup.sh` at `pre_start`, the script this pack's
copy descends from. A home serves many beads, so `ensure` could only provision one
by binding it to an invented bead, and would still leave the sync, the redirect
and the excludes to a script. The warrant "Agent home provisioning" records this.

## What the city showed

482 registered worktrees across seven repositories, 71 GB under `.gc/worktrees/`,
with 1.6 TB free on the disk. The pack's own dry run planned 5 removals. The pack
removed 90 trees in the 48 hours before the census.

**The 107 closed-bead trees under `.gc/worktrees/<rig>/`, by what each reaper does
with them now.** The controller's column comes from a shell emulation of its gates
over the real trees and stores, with the stash gate left out, since it holds a
whole rig and is read separately below. The dry run confirmed the emulation within
minutes of going live (town commit 20c749a, 2026-11-01T06:40:34Z): its first pass
said 29 would reap and 22 unreachable in gc-toolkit, the emulation's two numbers
there, and 14 and 21 in the next rig, whose emulated 26 had lost 5 to the pack's
reaper in between.

| The controller's reaper | The pack's reaper | Trees |
|---|---|---|
| would remove | holds: closed under 24 hours ago | 37 |
| would remove | holds: a live bead or PR has the branch | 9 |
| would remove | holds: no bead names the path | 1 |
| would remove | would remove | 1 |
| holds: no ref reaches the commits | holds: closed under 24 hours ago | 44 |
| holds: no ref reaches the commits | would remove | 4 |
| holds: dirty | holds: dirty | 11 |

- **All 107 are detached.** The submit step detaches the tree and deletes the
  local branch at hand-off, as Gas Town's polecat does.
- **Nothing the controller would take was in use.** For all 48, the bead still reads
  closed and no commit is newer than its close.
- **The 48 with unreachable commits come from that same hand-off.** A squash merge
  deletes the origin branch, and the next `git fetch --prune`, which every polecat's
  workspace setup and every refinery cycle runs, drops the remote-tracking ref. Then
  only the tree's detached HEAD reaches the commits, and every one of these trees
  reads that way: no local ref and no remote-tracking ref for its branch. The trees
  the controller would take are mostly reachable because something else happens to
  reach their commits: `origin` for 16, a `refs/remotes/origin-pr/<n>` ref nothing in
  this pack writes for 16, an archive tag for a few. So a tick soon after the close
  does not settle it, since a prune can land first, and a tree that loses the race is
  held for good. tk-1tfzr71.43 ends the case: a tree that goes at hand-off never
  reaches this state, as core's `mol-polecat-commit` and `mol-scoped-work` already
  clean up after themselves. Trees already in this state are why tk-1tfzr71.42 lands
  at least 24 hours after it, so the old tree pass can finish them.
- **The stash gate was live.** gc-toolkit's repository held one stash from
  2026-10-12, and the dry run's first pass read `stashes=true` on all 51 of its
  candidates. The mechanik dropped the stash under tk-1tfzr71.40, and the next pass
  read the numbers above.
- **The 11 dirty trees are all in the rig that holds Gas City's own fork.** That
  repository's tracked `.gitignore` re-includes `/.claude/skills/`, which outranks
  the local excludes, so the skills gc materializes show as untracked. Neither
  reaper takes these trees, at about 1.5 GB. Nothing is filed: both reapers behave
  the same, and the cost is small.
- **255 of the worktrees are the homes of converse sittings**, about 6 GB, and
  neither reaper takes them. Filed as tk-6lctp3w.

**Agent homes.** 317 registered trees are homes. 18 held commits their default
branch lacks, and none of those 18 holds a commit that no remote-tracking ref or
tag reaches:

- One detached slot in this rig, at a merge commit from a squash-landed branch. This
  is the slot the bead's notes name. Its checkout predates `AGENTS.md`, so sessions
  there did not load the file.
- 17 homes in the rig that holds Gas City's fork, attached to their own branches,
  most of them 722 commits behind. The fork's main was rewritten after they last
  synced, and a fast-forward cannot follow a rewrite.

Under the old rule all 18 stay where they are for good. Under the new one all 18
reach the tip at their next session start: each is clean in its tracked files, and
a dry run of the checkout (`git read-tree -n -u -m HEAD <tip>`) passes on every one. Five more homes carry a tracked change,
each to `.claude/settings.json`, and none of them is stuck, because a fast-forward
that does not touch that file still applies. No home was mid-rebase or mid-merge,
and no stage or orphan directory existed anywhere under `.gc/worktrees/`.

## What the wrapper's change is

- **The sync rule.** A home moves to the default tip unless that loses a tracked
  change, or a detached HEAD's commits no ref reaches. Ancestry of the tip was the
  old test, and a squash merge never satisfies it. Reachability is what Gas Town's
  script and Gas City's reaper both test.
- **Its own branch.** A home on its own branch moves too when it cannot fast-forward.
  The branch is reset when another ref reaches its commits. Otherwise the worktree
  detaches at the tip and the branch keeps them, so no home can be stuck by a commit
  on that branch. Any other branch stays as it is.
- **Removed, with no case behind them.** Adopting and quarantining orphaned stage
  directories, which Gas Town's script does not do either, and aborting a rebase or
  merge at start. The census found no such directory and no such home. The abort
  dates from when sync ran `pull --rebase`, and nothing in the pack does now. A kill
  mid-stage now leaves its directory beside the home, and a mid-merge home reports
  through the tracked-change refusal.
- **Not built.** Anything that makes a slot that cannot move visible to someone. The
  bead's note allowed for that, but the census leaves no such slot: every stuck home
  moves under the new rule. The one stderr line a refusal prints stays unread, as
  before. If a home ever holds a commit no ref reaches, a tracked change that blocks
  its fast-forward, or a branch that is not its own, it stays silently at its old
  checkout. tk-d3daseg holds the question of whether that needs a signal.

## How this copy differs from Gas Town's

Each is a difference from `gastown/assets/scripts/worktree-setup.sh` at
0b0d96250f66, with its reason and what ends it. The rows cover every difference in
where a home ends up and whether its session starts. Checks with no case here, such
as Gas Town's ref-format check on the branch name, are left out.

| This script | Gas Town's | Why | Ends when |
|---|---|---|---|
| A refusal prints a line, exits 0, and the session starts on the checkout it has | Exits 1, so the session does not start | A pool slot that cannot start takes no work, and these homes can carry a tracked `.claude/settings.json` change | Never by itself: a choice to weigh if refusals start to matter |
| A failed fetch does not stop a sync, which then reads the last tip it fetched | Refuses and exits 1 | The same as the row above: a slot that cannot reach origin still takes work | The exit-1 row above is adopted |
| A repository with no origin is left alone with no line, and an unset `origin/HEAD` is a refusal | Refuses a repository with no origin, and tries `git remote set-head origin --auto` first | No case: all 317 homes have both | A case appears |
| Only tracked changes block a sync | Any untracked file blocks it | gc writes untracked files into a home, such as `.worktree-stale` | Gas City writes nothing untracked into a home |
| Its own branch, when it cannot fast-forward, is reset if another ref reaches its commits, and otherwise the worktree detaches at the tip and the branch keeps them | Refuses and exits 1 whenever that branch holds a commit the default branch lacks | A stuck home silently loses every rule landed after it, and neither move loses a commit | The exit-1 row above is adopted |
| A home on any other branch stays there, fast-forwarding to that branch's upstream when it can | Switches a clean home to its own branch, and the other branch keeps its commits | No measured reason either way, so this change leaves the script's existing rule alone: no home is on such a branch, and no home's reflog shows one checked out in the last 30 days | A home is found stuck on one, and then Gas Town's rule goes in |
| Reachability also counts tags | Counts branches and remote-tracking refs | The pack's archive tags pin commits, and Gas City's reaper counts tags too | The tags are gone |
| The redirect and excludes are completed on every run | Excludes every run, redirect only at creation | A hook failure or a kill can leave a half-built tree | Gas Town's script completes the redirect |
| Hides only the skill links gc's manifest names under `.agents/skills/`, and adds `.runtime/` and `.beads.gate.lock` | Hides all of `.agents/skills/` | Some repositories track skills there, this one included, and a person's new skill must still show | gc excludes its own links |
| Keeps a staged directory that loses to a file from ending the run | Recurses and fails | The checkout can bring a file where the stage holds a directory | Gas Town takes the same guard |
| Does not check that an existing tree belongs to the rig | `validate_existing_worktree` refuses it | No case seen, and a tree whose git metadata is gone must still get its redirect | A case appears |

## Limits of this record

- The census is one moment. The stage that replaces it is the dry run over days,
  which tk-1tfzr71.41 reads.
- The cost figure is a loop of the same git calls from a shell, not a measurement
  of the controller's tick. The mechanik saw the tick rate hold over the dry run's
  first five minutes, which says nothing yet about a longer run.
