---
name: Gas City search and census for retiring the pack's worktree machinery
description: What tk-1tfzr71.10 looked for in Gas City before deciding which of the pack's worktree reaper, wrapper and convoy check could go, what the live city showed, why the work split into a rollout, and what the home wrapper's sync saves before it moves a home. Read it when judging the home wrapper's warrant or its sync, the reaper's cutover, or the per-bead move onto gc worktree.
---

# Gas City search and census for retiring the pack's worktree machinery

Read on 2026-11-01 at `gastownhall/gascity` main 6b90a9fb22ff and
`gastownhall/gascity-packs` main 0b0d96250f66. The city's deployed `gc` is the
fork's 1.4.3 at e03752646, which is named only where it is what runs. The census
ran read-only on the live city at about 06:20Z, with load near 60. The home
sync's rule, what gc writes into a home before a session starts, and a second
census of the homes were read on 2026-11-05 at `gastownhall/gascity` main
44e0d11e4625 and `gastownhall/gascity-packs` main 796d7ecd73cf, between 07:30Z
and 08:00Z. The forced move's putting back and the quit of a stopped operation,
with the search behind them, were read at about 09:15Z the same day, at
`gastownhall/gascity` main 357c30c631cf, whose one commit past 44e0d11e4625
changes only security-scan and build files.

## What was decided

| The bead's part | Outcome |
|---|---|
| `orders/convoy-check.toml` | Already gone: an earlier change deleted it, so core's `convoy-autoclose-backstop` is the only hourly `gc convoy check`. Nothing to do. |
| `worktree-reap.sh`, its order, its test | The controller's reaper replaces the worktree pass, in the three stages this bead's description asks for. tk-1tfzr71.40 turned the dry run on, tk-1tfzr71.41 compares and turns reaping on, and tk-1tfzr71.42 deletes the pack's copy, keeping the branch pass as a residual if it still has work to do. |
| `worktree-setup.sh` | Stays, as agent home provisioning under a warrant, because `gc worktree` cannot provision a home. Its sync now saves what a move would lose and moves the home to the default branch's tip at every start, so no home stays on an old checkout. It also drops what no case needs. |
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
  reports the same refusal in the sibling prune path, and is open). Upstream removed
  this gate from the reaper and the worker-dir prune on 2026-11-02 (b244d69f5),
  after the deployed build.
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

Under main's rule all 18 stay where they are for good. Each is clean in its tracked
files, and a dry run of the checkout (`git read-tree -n -u -m HEAD <tip>`) passes on
every one. Five more homes carry a tracked change, each to `.claude/settings.json`,
and none of them is stuck, because a fast-forward that does not touch that file
still applies. No home was mid-rebase or mid-merge, and no stage or orphan directory
existed anywhere under `.gc/worktrees/`.

A second read at about 09:40Z counted the same 18 and the same five tracked changes.
Every home's own branch tracks its rig's default branch, and none sits ahead of the
tip with nothing to pull, which is the shape a rewind to an ancestor leaves.

**Agent homes on 2026-11-05.** The mechanik moved the 18 stuck homes to the tip by
hand at about 07:25Z, and each was left detached there. The census after it found
344 homes: 326 on their own branches and those 18 detached at the tip. None was on
another branch, and none held a commit that no branch, tag or remote-tracking ref
other than its own branch holds, so the new rule's first pass saves no commit. The
five tracked changes are still the only ones, all in one rig that tracks
`.claude/settings.json`, and each is gc's merge of the pack's hooks into that file
(see [what gc writes into a home](#what-gc-writes-into-a-home-before-the-session-starts)).
The same dry run of the move, against a copy of each home's index so nothing was
locked or written, passes on all 344. So the first start after this lands forces no
move and saves nothing, and those five merges are carried to the tip. A read of the
344 homes' git directories at 09:12Z found none with a rebase, a `git am`, a run of
cherry-picks or reverts, a bisect or a merge in progress.

## What caused the stuck homes

Conversation tk-n5lvgu8 traced the stuck slot in this rig through its HEAD reflog and
a Codex session log, and its notes on tk-1tfzr71.10 record the chain:

1. **A session moved its home.** On 2026-10-15 at 05:33Z a triage review ran
   `git checkout --detach <commit>` in the home it started in, to run the review
   script as the reviewed commit had it. The review formula's first step had no
   checkout of its own then, and it makes one now, so that trigger is gone. Any
   session can still move its home with a plain git command, because a session
   works in its home's checkout.
2. **The sync could not undo it.** The reviewed branch was squash-merged 17 minutes
   later, and main's rule moves a detached home only when the tip already contains
   its commit, which a squash merge never makes true.
3. **Nobody saw it.** The refusal was one stderr line at pre_start, and gc discards
   a command's output when the command succeeds.

The fix is at the second link: whatever a session did, the next start moves the home
to the tip, after saving what the move would lose. The third link goes with it.
Nothing refuses any more, and a move that fails fails the start, which gc reports
with the command's output (`setupCommandFailure`, from `runSetupCommand` in
`internal/runtime/tmux/adapter.go`). The first link stays, because a session may
still move its home, and the next start puts it back.

## What gc writes into a home before the session starts

The ruling asked this rework to check that the move does not undo what gc writes
into a home before a session starts. This is read for the tmux provider, the session
runtime this city runs, since `city.toml` sets no `[session] provider`.

1. `Start` in `internal/runtime/tmux/adapter.go` calls `stageStartFiles` before it
   starts the session. It stages the pack overlays and the agent overlay into the
   work dir through `StageProviderOverlayDir` (`internal/runtime/staging.go`),
   which merges the pack's hooks into the provider's settings file, such as
   `.claude/settings.json`, and copies the hook scripts. Then it stages
   `CopyFiles`.
2. `doStartSession` then runs `runPreStart`. Its first command is the agent's own
   `pre_start`, this script. The commands gc generates for skills and project MCP
   config come after it (`appendMaterializeSkillsPreStart`,
   `appendProjectMCPPreStart` append to the list), so what they write lands after
   the move.
3. Between sessions, the reconciler stages the overlays and installs hooks into the
   work dir on its ticks (`prepareTemplateResolution` in
   `cmd/gc/build_desired_state.go`), and writes a skill catalog snapshot under
   `.gc/tmp/` for the skills command (`writeSkillSnapshotFile` in
   `cmd/gc/skill_integration.go`). The worker-dir prune leaves a `.worktree-stale`
   marker in a home it keeps (`writeWorktreeStaleMarker` in
   `cmd/gc/session_worktree_prune.go`).

What survives the move:

- **Untracked files.** gc's settings, hook scripts, skill links and snapshot sit
  under paths the script excludes, and the marker is untracked. The move keeps
  them, except where the default branch adds a tracked file at the same path,
  which git's checkout overwrites (suite cases (i) and (v)).
- **A tracked file gc merges into.** In a rig that tracks `.claude/settings.json`,
  gc's merge is a tracked change, as in the five homes the census found. The move
  carries it to the tip unless the tip changes that same file (case (t)). Then git
  refuses, the change is saved as `changes`, and the forced move brings the tip's
  file (case (u)). That one session starts without gc's merged hooks, and gc merges
  them in again before the next session starts. When something else forces the
  move, such as an untracked file where the tip adds one, or a session's change to
  a file the tip changes, the merge is put back after the forced move (cases (aa)
  and (ab)).
- **A new home.** gc's staging lands in a directory that is not a worktree yet. The
  script moves its contents aside, adds the worktree and moves them back, keeping
  each file the checkout did not bring (cases (e), (f) and (h)).

## What the wrapper's change is

- **The sync rule.** At every start, a home moves to the default branch's tip on its
  per-target branch. First it saves what the move would lose under
  `refs/gc-toolkit/home-save/<per-target branch>/<UTC time>/`: HEAD's commits as
  `head`, and the per-target branch's as `branch` when that branch points at another
  commit, because the move resets it. A commit is saved only when no branch, tag or
  remote-tracking ref other than the per-target branch holds it, which is the set
  Gas City's own reach test counts (`HasUnreachableCommitsResult` in
  `internal/git/git.go`). A reach git cannot read is saved anyway.
- **What the move keeps.** The move is a plain `git checkout -B` of the per-target
  branch at the tip, which carries every tracked change and untracked file it does
  not overwrite. When git refuses, because the move would overwrite a tracked change
  or an untracked file, the tracked changes are saved as `changes`, the move is
  forced, and each saved change on a path the tip leaves alone is put back,
  unstaged, so a forced move drops only what was in its way. A three-way
  `git read-tree` from the commit the home was on puts them back, by git's own rule
  for which paths a move may carry, and a reset unstages them. An untracked file the
  forced move overwrites is not saved: it sits where the tip adds a file, and the
  ruling names tracked changes and commits.
- **A stopped operation is quit.** A rebase, a `git am`, or a run of cherry-picks
  or reverts that a session stopped partway keeps its state through the move, and
  continuing or aborting it would take the home off the tip. So once the move is
  made, the script quits it, which keeps HEAD, the index and the work tree, while
  the saves above hold its commits. A rebase's autostash is saved as `autostash`
  first, because `git rebase --quit` would put it on the stash stack, and a
  `git am` session is quit with `git am --quit`, because `git rebase --quit`
  refuses one. A stopped merge needs nothing, because the move's checkout ends it.
  That checkout also puts a merge's autostash on the stash stack, and no home holds
  a stopped merge. A home whose move fails keeps the operation for a person to
  abort, and a quit git refuses fails the start (cases (ac) to (af)).
- **What Gas City has for either.** Nothing in Gas City clears a stopped operation
  in a tree or carries a tree's changes through a forced checkout. A code search of
  `gastownhall/gascity` at 357c30c631cf finds no `rebase --quit`,
  `cherry-pick --quit`, `rebase-merge` or `read-tree`, and `stash create` only in
  the reaper's and the prune's tests and one release-gate note. Its agent-home
  cleanup
  (`cleanupClosedBeadAgentHomeWorktrees` in `cmd/gc/agent_home_worktree_cleanup.go`)
  moves a home only when it carries the prune's `.worktree-stale` marker, sits on a
  branch that names a closed bead and has no uncommitted work, so it neither
  carries nor saves a change. Gas Town's script neither quits nor aborts an
  operation.
- **Where this departs from the ruling.** The ruling says to save any tracked change
  and then move. Saving and then discarding a tracked change would undo gc's merge in
  a rig that tracks the settings file, at every start, and saving it at every start
  would add a ref per start in each such home. So a tracked change is saved only
  when the move would overwrite it, and otherwise it moves to the tip with the home.
  A session's own edit to a tracked file rides along the same way, until the tip
  changes that file.
- **Where the saves go.** Gas City has no primitive that keeps what moving a tree
  would lose. `gc worktree ensure` never moves a tree, and the closed-bead reaper and
  the worker-dir prune leave a tree with uncommitted changes, or with commits no ref
  holds, where it is and save nothing. git's stash stack is shared by every worktree
  of a repository, so another session's pop can take an entry. The deployed reaper
  also holds every tree of a repository while that repository holds any stash (the
  census above). Upstream dropped that gate on 2026-11-02, and doctor's
  nested-worktree prune check still refuses a tree while its repository holds a stash
  (`internal/doctor/checks_semantic.go`). Gas Town's script refuses instead of
  saving. So the script pins with `git stash create` and `git update-ref` under its
  own namespace, as `reconcile-rig-checkouts.sh` pins a rig checkout's local changes
  under `refs/gc-toolkit/reconcile-set-aside/`.
- **Hooks off, upstream untouched.** The move runs with `core.hooksPath=/dev/null`,
  because a hook's exit status becomes the checkout's, and a move that carried a
  change over but read as failed would then be forced over it. It passes
  `--no-track`, because setting the upstream rewrites the repository's config, which
  every worktree of the rig shares, so every start would contend for its lock. The
  upstream stays as the home's creation set it.
- **A move that fails fails the start.** A move git cannot make even when forced,
  such as one onto a per-target branch another worktree has checked out, a home with
  unmerged paths, which `git stash create` cannot save, a home whose HEAD names a
  branch that no longer exists, and an unset `origin/HEAD` each end the run
  non-zero, and so does a quit or a putting back that git refuses. The session does
  not start, and gc reports what the run printed. No home is in any of these shapes
  today.
- **Only a linked worktree moves.** A main checkout given as the target keeps its
  branch, because it is the rig's own checkout.
- **Removed.** Every refusal and its stderr line: a tracked change, a detached HEAD
  whose commits no ref reaches, a branch that is not the home's own, and an untracked
  file in the way. The fast-forward path goes with them, and so does detaching at the
  tip when the per-target branch cannot be reset. Two earlier removals stand, with no
  case behind either: adopting and quarantining orphaned stage directories, which Gas
  Town's script does not do either, and aborting a rebase or merge at start, which
  throws away what the operation did. A stopped operation is quit after the move
  instead. A kill mid-stage leaves its directory beside the home.
- **Not built.** Anything that removes old saves. A save is made only when a move
  would lose something, and no home would today. A person reads a saved commit with
  `git log <ref>`, and takes a path back with `git checkout <ref> -- <path>`.

## How this copy differs from Gas Town's

Each is a difference from `gastown/assets/scripts/worktree-setup.sh` at
796d7ecd73cf, where the script last changed on 2026-10-03, with its reason and what
ends it. The rows cover every difference in where a home ends up and whether its
session starts. Checks with no case here, such as Gas Town's ref-format check on the
branch name, are left out.

| This script | Gas Town's | Why | Ends when |
|---|---|---|---|
| Nothing refuses a sync: what the move would lose is saved under a ref, and the move goes ahead | Refuses a home with any change, tracked or untracked, a detached HEAD no branch or remote-tracking ref reaches, or a per-target branch holding a commit the default branch lacks, and exits 1, so the session does not start | A home holds no work of its own, and each refusal is a way for a home to stay stuck | Never by itself |
| A tracked change the move does not overwrite is carried to the tip | Refused with the rest of a dirty home | gc merges the pack's hooks into a provider settings file before pre_start, and a rig can track that file | gc stops writing into a file a rig tracks |
| An untracked file never blocks the move, and one in the way of a file the tip adds is replaced | Any untracked file blocks it | gc writes untracked files into a home, such as `.worktree-stale` and its provider settings | Gas City writes nothing untracked into a home |
| A rebase, `git am`, or run of cherry-picks or reverts that a session stopped is quit once the home moves, keeping HEAD, the index and the work tree | Leaves it in progress whenever it syncs | Continuing or aborting it would take the home off the tip | Never by itself |
| A failed fetch does not stop a sync, which then moves to the last tip it fetched | Refuses and exits 1 | A slot that cannot reach origin still takes work | A start on a stale tip is found to cost more than a start that fails |
| A repository with no origin is left alone with no line, and an unset `origin/HEAD` fails the run | Refuses a repository with no origin, and tries `git remote set-head origin --auto` before failing on an unset `origin/HEAD` | No case: all 344 homes have both, and git's fetch sets a missing `origin/HEAD` again | A case appears |
| The move runs with hooks off and leaves the upstream as it is | The checkout runs the repository's hooks | A hook's exit status becomes the checkout's, which would force a move that had carried a change over | Never by itself |
| Reachability also counts tags | Counts branches and remote-tracking refs | The pack's archive tags pin commits, and Gas City's reaper counts tags too | The tags are gone |
| The redirect and excludes are completed on every run | Excludes every run, redirect only at creation | A hook failure or a kill can leave a half-built tree | Gas Town's script completes the redirect |
| Hides only the skill links gc's manifest names under `.agents/skills/`, and adds `.runtime/` and `.beads.gate.lock` | Hides all of `.agents/skills/` | Some repositories track skills there, this one included, and a person's new skill must still show | gc excludes its own links |
| Keeps a staged directory that loses to a file from ending the run | Recurses and fails | The checkout can bring a file where the stage holds a directory | Gas Town takes the same guard |
| Does not check that an existing tree belongs to the rig, and syncs only a linked worktree | `validate_existing_worktree` refuses a tree of another repository, and treats a main checkout of the rig like a linked worktree | No case of the first, a tree whose git metadata is gone must still get its redirect, and the rig's own checkout keeps its branch | A case appears |

## Limits of this record

- The census is one moment. The stage that replaces it is the dry run over days,
  which tk-1tfzr71.41 reads.
- The cost figure is a loop of the same git calls from a shell, not a measurement
  of the controller's tick. The mechanik saw the tick rate hold over the dry run's
  first five minutes, which says nothing yet about a longer run.
