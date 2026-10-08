# Scratch reclaim

Every Claude Code session gets a private tree under a per-uid scratch root,
`/tmp/claude-<uid>/<project-slug>/<session-id>/`, holding its scratchpad,
task output and shell snapshots. Claude Code puts the root under
`$CLAUDE_CODE_TMPDIR` in place of `/tmp` when that is set, and never under
`TMPDIR`, which macOS sets for every process; the reaper's default root
follows the same rule. The harness reclaims none of it when the session ends
and session directories arrive by the thousand per day, so without a reaper
the trees are a standing floor under the per-uid tmpfs quota.

Exhausting that quota is not a disk problem. Past it, every command that
prints fails with empty output while silent ones still succeed, so the whole
city loses its shell at once and nothing in the failure names the cause. `df`
is no guide either: it reports the filesystem's free space, while the binding
limit is the quota, so the two disagree by gigabytes exactly when it matters.

## What the reaper does

`orders/scratch-reap.toml` runs `assets/scripts/scratch-reap.sh` hourly,
`scope = "city"`, no LLM and no agent. The scratch root is per-uid, one tree
for every rig, and nothing in it belongs to a bead, so a pass skipped or cut
short by its budget costs only the reclaim the next pass takes instead.

Two rules decide what a pass removes. A session that has ended loses its tree
at the next pass (see "Ended sessions" below). Any other session whose tree has
not been touched in `SCRATCH_REAP_INACTIVE_AFTER` (24h) has that tree removed
whole. Files loose above the session trees — at the scratch root, or beside
the session directories inside a project-slug directory — age the same way,
having no tree to protect them and no owner to return to.

A tree is aged by the newest entry anywhere inside it, directories included,
so one stale file cannot condemn a session that is still working, and a tree
whose only recent activity was a `mkdir` still reads as active. A session with
a running process is held whatever its mtime. Claude Code exports
`CLAUDE_CODE_SESSION_ID` to every command it runs and writes the command's
output to a file in the session's tree, so two readings name the sessions
that are certainly alive:

- **A process carries the session's id in its environment.** Linux exposes
  each process's environment under `/proc`. Elsewhere `ps -E` prints it, and
  macOS hides the environment of its own system binaries, `/bin/zsh` and
  `/bin/sleep` among them, from every other process.
- **A process holds a file open inside the session's tree, or stands in it.**
  lsof reads this on Linux and macOS alike, whatever binary the process runs.

The signal is one-directional: a session between turns owns no process and
does not appear, so it only ever protects, and the horizon carries the rest.
A reading that cannot be taken holds everything it would have protected. When
lsof fails or its listing leaves out the pass's own process, or the
environments cannot be read with the pass's own among them, the pass takes no
session tree at all, keeps every one, and says why; stray files still age out.

Reclaim is reported as measured before/after bytes, never as a count of
removals. A read-only tree — a Go module cache copied into scratch is mode
0555 — refuses deletion, and a wrapped `rm -rf` reports success while freeing
nothing. The script chmods before it deletes, and the measurement is what
proves the deletion happened.

Agents are told the rule rather than a set of habits. The `scratch-reclaim`
prompt fragment states that scratch does not outlive an inactive session, so
durable work goes in the repo. It carries one habit beyond that, because the
reaper cannot cover it: a single turn can exhaust the quota between passes, so
build artifacts and whole-store bead dumps stay out of scratch.

## Ended sessions

Most sessions end within hours. A pool worker drains after one bead, and a
patrol agent that restarts gets a new session id and a new tree. Each ended
session leaves its tree behind, so the horizon alone keeps a day of them. So a
pass removes an ended session's tree without waiting for the horizon.

A session has ended when nothing can still own its tree. Three readings decide
that, and each of them only ever holds a tree:

- **A process names the session.** `CLAUDE_CODE_SESSION_ID` names a session
  that is running a tool. gc starts every agent session as
  `claude --session-id <id>` and wakes one as `claude --resume <id>`, so an
  agent between turns is still named on its own process's command line. Any
  UUID on any command line counts.
- **A process stands in the project directory.** Claude Code names a session's
  project directory after the path its main process was launched from, and
  that process stays in that directory. A session started inside a running
  process, by a `/clear` or in an interactive session, carries an id that no
  command line shows, but its tree is written after that process started. So
  a process standing in the project directory, or anywhere below it, holds
  every tree written after the process started.
- **gc can still wake the session.** A sleeping session that wakes with
  `--resume` reuses its tree, and gc's session list is the only record of it.
  The open sessions of every city registered with gc hold the trees their keys
  name.

A tree goes only when its last write is at least `SCRATCH_REAP_ENDED_AFTER`
(10 minutes) older than the pass, and at least that much older than the start
of the earliest process standing in its directory. The margin covers a session
that starts while the pass runs, and the one-second resolution of a process's
start time.

The rule judges only the trees Claude Code writes: a UUID-named tree under a
project directory named for an absolute path. A project name longer than 200
characters ends in a hash of the path that the reaper cannot recompute, so
those trees wait for the horizon. When gc's session list or the processes'
start times cannot be read, the rule judges nothing, the summary line names
the reason, and every tree waits for the horizon.

## Reaping a retiring session

A long-running patrol agent recycles its context as it works, and each recycle
abandons its session tree whole: the inheriting session gets a new id and a new
tree. The retiring session knows its tree is dead at once. At the recycle, the
cycle-recycle hook names its own session to `scratch-reap.sh --session <id>`,
which takes that one tree immediately: the same root rails and
chmod-before-delete as the full pass, but no horizon, no ended-session test
and no running-process hold, because the hook is itself that process and the
hold would decline the very tree the recycle leaves. The hourly pass takes the
tree of every session that ends without naming itself.

## Rails

The script deletes recursively, so it refuses any root that is not a scratch
root this user owns. The basename must be `claude-<uid>`, symlinks are
resolved before that check, ownership is asserted, and every walk is `-P` and
`-xdev`. A symlink is unlinked as it stands and never chmod-ed, because chmod
dereferences a symlink argument and would change the mode of a target the
script has no claim on. The horizon must be a positive whole number of
seconds. Empty directories are pruned only at the top level, since anything
deeper belongs to a session the pass chose to keep.

`assets/scripts/scratch-reap.test.sh` is the regression suite, hermetic
against a synthetic root in a tempdir, with a stand-in for gc's session list —
no city and no network. One case reaches outside the tempdir: with neither
`SCRATCH_REAP_ROOT` nor `CLAUDE_CODE_TMPDIR` set, it asks the real default root
for a session id no session has, which reads that root's directory names and
removes nothing. The live-session and ended-session cases run real processes,
so each hold is shown holding a tree and then, with that process gone, letting
the same tree go.

## Operating it

```bash
assets/scripts/scratch-reap.sh --dry-run     # the plan, and the largest files in it
assets/scripts/scratch-reap.sh               # reap, one summary line
assets/scripts/scratch-reap.sh --session <id> # take one session's tree now
```

`SCRATCH_REAP_ROOT` overrides the root, `CLAUDE_CODE_TMPDIR` moves the default
root as it moves Claude Code's, `SCRATCH_REAP_BUDGET` (default 240s)
bounds the pass, `SCRATCH_REAP_ENDED_AFTER` (default 600s) sets the quiet
margin of the ended-session rule, and `SCRATCH_REAP_GC` names the gc binary
that lists the open sessions. The summary line counts the trees taken past the
horizon apart from those of ended sessions. Every run names the five largest
files it took, session trees and loose files alike, so a writer that keeps
recreating the same artifact stays visible in the order log rather than only
in the total.

## What it does not touch

Scope is the harness scratch root. Other `/tmp` tenants are reclaimed
elsewhere: build and test scratch left by killed or crashed runs is
`build-scratch-reap.sh`'s, the worktrees of closed beads are
`worktree-reap.sh`'s, the workspaces of ended reviews are
`review-workspace.sh`'s, and a horizon on `/tmp` as a whole is the host's
policy, not the pack's.
