---
name: Gas City search and census for retiring the pack's worktree machinery
description: What tk-1tfzr71.10 looked for in Gas City before deciding which of the pack's worktree reaper, wrapper and convoy check could go, what the live city showed, why the work split into a rollout, and the rule the home wrapper's sync follows, a fast-forward or a failed start that reports what a session left in the home. Read it when judging the home wrapper's warrant or its sync, the reaper's cutover, or the per-bead move onto gc worktree.
---

# Gas City search and census for retiring the pack's worktree machinery

Read on 2026-11-01 at `gastownhall/gascity` main 6b90a9fb22ff and
`gastownhall/gascity-packs` main 0b0d96250f66. The city's deployed `gc` is the
fork's 1.4.3 at e03752646, which is named only where it is what runs. The census
ran read-only on the live city at about 06:20Z, with load near 60. The home
sync's rule was ruled on 2026-11-05 in conversation tk-g0hh666 (its note on
tk-1tfzr71.10 at 20:21Z). What gc writes into a home before a session starts,
where a failed start reaches a person, and a census of every home under that rule
were read the same day between 20:30Z and 21:10Z, at `gastownhall/gascity` main
9f807760c191 and `gastownhall/gascity-packs` main 796d7ecd73cf.

## What was decided

| The bead's part | Outcome |
|---|---|
| `orders/convoy-check.toml` | Already gone: an earlier change deleted it, so core's `convoy-autoclose-backstop` is the only hourly `gc convoy check`. Nothing to do. |
| `worktree-reap.sh`, its order, its test | The controller's reaper replaces the worktree pass, in the three stages this bead's description asks for. tk-1tfzr71.40 turned the dry run on, tk-1tfzr71.41 compares and turns reaping on, and tk-1tfzr71.42 deletes the pack's copy, keeping the branch pass as a residual if it still has work to do. |
| `worktree-setup.sh` | Stays, as agent home provisioning under a warrant, because `gc worktree` cannot provision a home. Its sync fast-forwards a home to the default branch's tip at every start, and fails the start on anything a session left in the home, reporting it through `patrol-finding.sh`. It also drops what no case needs. |
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
hand at about 07:25Z, and each was left detached there. A census at 21:06Z read
every home under this change's rule, read-only: the same git commands the sync
runs, with no fetch, and the fast-forward as a dry run,
`git read-tree -n -u -m HEAD <tip>`, against a copy of each home's index. Three
of the city's six rigs were suspended.

| Homes | In active rigs | In suspended rigs |
|---|---|---|
| on their own branch at the tip | 25 | 7 |
| on their own branch, fast-forwarding to the tip | 293 | 8 |
| detached at the tip, their own branch on an old main | 0 | 15 |
| failing their start | 3 | 3 |

- Every home that fails holds `findings.json` and `findings.md`, which a review in
  a Codex review slot writes into its working directory, the home. They are the
  two Codex slots in this rig, one in another active rig, and three in suspended
  rigs. The newest pair dates from 2026-11-01. tk-irp6lb4 carries the review's
  writes.
- The 17 homes in the rig that holds Gas City's fork are the 17 the mechanik moved
  there. Each sits detached at the tip, its own branch still on the main the
  fork's rebase replaced, 59 to 100 commits the tip lacks. 15 of them start and
  stay detached at the tip, as main's rule keeps them, and the other two are that
  rig's Codex review slots.
- Five homes carry gc's merge into a tracked `.claude/settings.json`, all in one
  suspended private rig, and each fast-forwards with it.
- No home is on another branch, holds a commit the tip lacks on its HEAD, or has
  an operation stopped partway. Every other untracked path git shows in a home is
  one gc writes: skill links, `.gc/` and the prune's `.worktree-stale` marker.

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

The fix is at the third link. What a session leaves in a home is a sign of a bug, so
the next start fails and files a report a person reads, one per home, and the
start after the person clears the home records that the report has cleared. The
second link stays by design: the sync moves a home only by a fast-forward, and
saves, discards and forces nothing, so what a session did is a person's to keep or
drop. The first link stays too, because a session may still move or edit its
home, and the report is what finds it.

## What gc writes into a home before the session starts

The sync must not take what gc writes into a home for a session's edit. This is
read for the tmux provider, the session runtime this city runs, since
`city.toml` sets no `[session] provider`.

1. `Start` in `internal/runtime/tmux/adapter.go` calls `stageStartFiles` before it
   starts the session. It stages the pack overlays and the agent overlay into the
   work dir through `StageProviderOverlayDir` (`internal/runtime/staging.go`),
   which merges the pack's hooks into the provider's settings file, such as
   `.claude/settings.json`, and copies the hook scripts. Then it stages
   `CopyFiles`. This pack's overlays put every file under `.claude/`, and no agent
   copies files of its own.
2. `doStartSession` then runs `runPreStart`. Its first command is the agent's own
   `pre_start`, this script. The commands gc generates for skills and project MCP
   config come after it (`appendMaterializeSkillsPreStart`,
   `appendProjectMCPPreStart` append to the list), so what they write lands after
   the sync, and the next start finds it.
3. Between sessions, the reconciler stages the overlays and installs hooks into the
   work dir on its ticks (`prepareTemplateResolution` in
   `cmd/gc/build_desired_state.go`), and writes a skill catalog snapshot under
   `.gc/tmp/` for the skills command (`writeSkillSnapshotFile` in
   `cmd/gc/skill_integration.go`). The worker-dir prune leaves a `.worktree-stale`
   marker in a home it keeps (`writeWorktreeStaleMarker` in
   `cmd/gc/session_worktree_prune.go`).

What the sync counts as gc's own:

- **Untracked files.** Every pattern the script hides through the local excludes:
  the bead redirect and bd's files beside it, each provider's directory
  (`.claude/`, `.codex/`, `.gemini/`, `.opencode/`, `.github/hooks/`), runtime
  state and logs, the per-bead trees under `worktrees/`, `.gc/`, bd's workspace
  gate, the prune's `.worktree-stale` marker, and the skill links the ownership
  manifests record under `.agents/skills/`. The sync passes each to git as a
  command-line exclude, which takes precedence over a tracked `.gitignore`
  ([gitignore](https://git-scm.com/docs/gitignore)), because the repository of
  Gas City's fork re-includes `/.claude/skills/`, so gc's skill links show in
  `git status` there (suite case (u)). A file the rig's own ignore rules hide is
  not counted either, as `git status` does not show it.
- **A tracked file gc merges into.** gc merges its hooks into the provider
  settings files Gas City lists as `mergeablePaths` (`internal/overlay/merge.go`):
  `.claude/settings.json`, `.codex/hooks.json`, `.gemini/settings.json`,
  `.cursor/hooks.json`, `.agents/hooks.json` and `.github/hooks/gascity.json`. In
  a rig that tracks one, gc's merge is a tracked change in every home, as in the
  five homes the census found. The sync does not count a change to those files,
  and the fast-forward carries it to the tip unless the tip changes the same
  file. Then git refuses, and the start fails and is reported, which the ruling
  accepted (suite case (t)). A session's edit to one of those files goes
  unreported the same way. Because gc merges into such a file again before
  every start, a restart after clearing what git names meets the same refusal,
  so the report names the move to make by hand once that is cleared,
  `git -C <home> merge --ff-only origin/HEAD`, or `checkout --detach origin/HEAD`
  for a detached home, and the start after it goes through.
- **A new home.** gc's staging lands in a directory that is not a worktree yet. The
  script moves its contents aside, adds the worktree and moves them back, keeping
  each file the checkout did not bring (cases (e), (f) and (h)).
- **Not counted, with no case.** gc's project MCP config, a file per provider
  such as `.mcp.json` or `opencode.json` (`MCPProjection` in
  `internal/materialize/mcp_project.go`), and the entries gc adds for it to the
  work dir's `.gitignore` (`ensureMCPGitignoreBestEffort` in
  `cmd/gc/mcp_integration.go`). No agent in this city declares MCP servers, so no
  home holds either. A rig that adds one would see its homes fail and report until
  the script's list names those paths.

## Where a failed start reaches a person

The report is new operational surface, so this is the search for what Gas City
already does with a failed start.

- A `pre_start` command that exits non-zero fails the start. The last 4 KiB of
  its output goes into the start's error, which "may appear in controller and
  reconciler logs" ([Agent](https://docs.gascity.com/reference/config#agent),
  `pre_start`). Each command runs under `[session] setup_timeout`, 10 s by
  default ([SessionConfig](https://docs.gascity.com/reference/config#sessionconfig)),
  and 30 s in this city's `city.toml`.
- A failed start of a session gc has already created, such as a named session
  waking from asleep, counts as a failed wake (`recordWakeFailure` in
  `cmd/gc/session_reconcile.go`). Five in a row hold the session for five minutes
  (`defaultMaxWakeAttempts` and `defaultQuarantineDuration` in
  `cmd/gc/session_types.go`). The hold records a telemetry count, and the
  `session.quarantined` event is reserved, with no production path emitting it
  (`cmd/gc/cmd_analyze_reliability.go`).
- A failed pending create, such as a new pool session's, also counts toward a
  startup-health episode (`recordStartupHealthFailure` in
  `cmd/gc/session_lifecycle_parallel.go`, for a start whose
  `pending_create_claim` is set). At five, the episode marks an alert pending
  (`RecordStartupFailure` in `internal/session/startup_health.go`), and no code
  sends it. The doctor check `startup-health-episodes`
  (`startupHealthEpisodesCheck` in `cmd/gc/doctor_startup_health.go`) lists those
  sessions, leaves the error text out on purpose, and fixes nothing. A failed
  wake of a session gc already created opens no episode, so the check never
  names it.
- Gas Town's script prints one stderr line and exits 1, which reaches the same
  logs and nothing more.

The city's deployed build, the fork at e03752646, does the same on each of these
points, as the conversation's note of 19:53Z read it there.

So a home that cannot start reaches no person through Gas City. The pack already
has a reporting process every patrol uses: `patrol-finding.sh` files one bead per
situation key, and the first reaction on it routes it, holds it, or puts it to
the operator. The script calls it with a key per home,
`home-sync.<per-target branch>`, in scope `home-sync` at priority 1, so a
recurrence lands on the bead that home already has. A clean start calls it with
`--cleared` under the same key, which sets that bead's situation to cleared when
one is live and records nothing otherwise. That clear is one store lookup per
start: 0.42 s at load 26, measured twice on 2026-11-05.

## What the wrapper's change is

- **The sync rule.** At every start a home fast-forwards to the default branch's
  tip. A home on its own branch merges the tip with `--ff-only`. A detached home
  whose HEAD the tip contains moves to the tip, back onto its own branch when that
  branch fast-forwards there (`git checkout --track -B`, case (i)), and otherwise
  detached at the tip (cases (l) and (y)), as main's rule moves a detached home.
  Hooks run as they do in main's script. A fast-forward on the home's branch is a
  merge, whose `post-merge` hook cannot change the result, and a checkout counts
  as done once HEAD is the tip, since a `post-checkout` hook's exit status becomes
  the checkout's after the move is made (case (n)).
- **What fails the start.** Anything else, each named in the report: a HEAD with
  commits the tip lacks (cases (j) and (z)), a branch not the home's own (s), a
  rebase, `git am`, merge, cherry-pick, revert or bisect stopped partway (v), a
  change to a tracked file other than gc's merged settings (k), an untracked file
  gc did not write (m), a fast-forward git refuses (t), an `origin/HEAD` that
  names no commit (x), and a HEAD that names no commit (ab). The sync saves,
  discards and forces nothing, so the home stays as the session left it.
- **The report.** Its first line reads "<home> did not start, because its sync
  found <what>. To clear it, <how>. The next start that finds it clean clears this
  report.", followed by git's own error when git refused the fast-forward. The
  title names the agent and the first thing found. The run prints the same text
  on stderr last, so gc's error carries it, and says so when the report did not
  land (case (aa)).
- **A rewrite of the default branch.** The operator's rebase of the fork's main,
  about every one or two weeks, replaces main, so every home of that rig then
  holds commits the new tip lacks, and its start fails. Moving those homes is a
  step in the rebase cutover, not script logic. The report names the move for its
  home, `git -C '<home>' checkout --detach origin/HEAD`, which is the step the
  fork sync task carries for every home of the rig (tk-z3hkju4, note of
  2026-11-05T20:23Z). After it, the next start finds the home detached on the
  tip's history and moves it with the tip, its own branch left on the old main
  (case (z)).
- **Where this departs from the ruling's words.** The ruling says a home detached
  on the tip's history "re-attaches and moves, as main does". Main's rule
  re-attaches such a home only when its own branch fast-forwards to the tip, and
  otherwise moves it detached, and this change does the same. The 17 homes in the
  fork's rig are the second case, with their own branches on the main the rebase
  replaced. Re-attaching them would reset those branches, which a sync that forces
  nothing cannot do, and failing them would leave the fork sync task's step unable
  to clear them. So a detached home whose own branch holds a commit the tip lacks
  starts with no report. Each of those 17 branches holds only commits that some
  other branch, tag or remote-tracking ref also holds (`git rev-list <branch>
  --not --exclude=<branch> --branches --remotes --tags`, at 21:15Z).
- **Removed.** The save refs under `refs/gc-toolkit/home-save/`, the forced move,
  the putting back of changes after it, and the quitting of a stopped operation,
  with their tests. Main's refusals with one stderr line and exit 0 become
  failed, reported starts. Main's abort of a stopped rebase or merge at start goes
  too, since it threw away what the operation did, and so does adopting and
  quarantining orphaned stage directories, which Gas Town's script does not do
  either. A kill mid-stage leaves its directory beside the home.
- **Not built.** Anything that clears a home. A person reads the report and
  clears what a session left, as its first line says.

## How this copy differs from Gas Town's

Each is a difference from `gastown/assets/scripts/worktree-setup.sh` at
796d7ecd73cf, where the script last changed on 2026-10-03, with its reason and what
ends it. The rows cover every difference in where a home ends up and whether its
session starts. Checks with no case here, such as Gas Town's ref-format check on the
branch name, are left out.

| This script | Gas Town's | Why | Ends when |
|---|---|---|---|
| A start that fails is reported through `patrol-finding.sh`, one report per home, and the next clean start clears it | Prints one stderr line and exits 1 | Nothing in Gas City brings a failed `pre_start` to a person | Gas City reports a failing start to a person |
| A home on a branch not its own fails the start | Switches a clean home back to its own branch | A session that moved its home is a bug to find | The operator rules otherwise |
| A detached HEAD the tip does not contain fails the start, even when another ref holds it | Switches a clean home whose detached HEAD a ref holds to its own branch | The same | The same |
| A detached home whose own branch holds commits the tip lacks moves to the tip detached | Refuses and exits 1 | After a fork's rebase, the cutover's step leaves every home of that rig in this shape | Gas Town's script takes the same rule |
| gc's merge into a tracked provider settings file is no edit, and each path gc writes is excluded ahead of the rig's `.gitignore` | Refuses any tracked or untracked change git status shows | gc writes into a home before `pre_start` runs, a rig can track a file gc merges into, and a rig's `.gitignore` can re-include a path gc writes | Gas City writes nothing into a home that git reports |
| A rebase, `git am`, merge, cherry-pick, revert or bisect stopped partway fails the start, named in the report | Has no check of its own for one | A person finishes or aborts it, and the report says which | Never by itself |
| A failed fetch does not stop a sync, which then fast-forwards to the last tip it fetched | Refuses and exits 1 | A slot that cannot reach origin still takes work | A start on a stale tip is found to cost more than a start that fails |
| A repository with no origin is left alone with no line, and an unset `origin/HEAD` fails the start with the command that sets it | Refuses a repository with no origin, and tries `git remote set-head origin --auto` before failing on an unset `origin/HEAD` | No case: every home has both, and git's fetch sets a missing `origin/HEAD` again | A case appears |
| The redirect and excludes are completed on every run | Excludes every run, redirect only at creation | A hook failure or a kill can leave a half-built tree | Gas Town's script completes the redirect |
| Hides only the skill links gc's manifest names under `.agents/skills/`, and adds `.runtime/`, `.beads.gate.lock` and `.worktree-stale` | Hides all of `.agents/skills/` | Some repositories track skills there, this one included, and a person's new skill must still show | gc excludes its own links |
| Keeps a staged directory that loses to a file from ending the run | Recurses and fails | The checkout can bring a file where the stage holds a directory | Gas Town takes the same guard |
| Does not check that an existing tree belongs to the rig, and syncs only a linked worktree | `validate_existing_worktree` refuses a tree of another repository, and treats a main checkout of the rig like a linked worktree | No case of the first, a tree whose git metadata is gone must still get its redirect, and the rig's own checkout keeps its branch | A case appears |

## Limits of this record

- The census is one moment. The stage that replaces it is the dry run over days,
  which tk-1tfzr71.41 reads.
- The cost figure is a loop of the same git calls from a shell, not a measurement
  of the controller's tick. The mechanik saw the tick rate hold over the dry run's
  first five minutes, which says nothing yet about a longer run.
- A report runs inside the start, under the 30 s `setup_timeout`. Its first filing
  makes several store calls and slings the first reaction, so on a host loaded
  enough to pass that bound the run is killed partway. The start fails either way,
  and the next start's report lands on the bead the first one filed. A finding
  whose reaction never slung waits for the proactive scan's sweep, which this
  city has off for this rig, the gap the conversation's 20:06Z note proposes a
  separate fix for.
- Until tk-irp6lb4 lands, a review in a Codex review slot writes its findings
  files into the slot's home, so that slot's next start fails and is reported
  until a person removes them.
