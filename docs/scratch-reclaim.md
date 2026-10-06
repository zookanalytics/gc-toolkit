# Scratch reclaim

Every Claude Code session gets a private tree under a per-uid scratch root,
`$TMPDIR/claude-<uid>/<project-slug>/<session-id>/`, holding its scratchpad,
task output and shell snapshots. The harness reclaims none of it when the
session ends and session directories arrive by the thousand per day, so
without a reaper the trees are a standing floor under the per-uid tmpfs
quota.

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

One rule: a session whose tree has not been touched in
`SCRATCH_REAP_INACTIVE_AFTER` (24h) has that tree removed whole. Files loose
above the session trees — at the scratch root, or beside the session
directories inside a project-slug directory — age the same way, having no tree
to protect them and no owner to return to.

A tree is aged by the newest entry anywhere inside it, directories included,
so one stale file cannot condemn a session that is still working, and a tree
whose only recent activity was a `mkdir` still reads as active. A session with
a running process is held whatever its mtime. Claude Code exports
`CLAUDE_CODE_SESSION_ID` to its children, so `/proc` names the sessions that
are certainly alive. The signal is one-directional: a session between turns
owns no process and does not appear, so it only ever protects, and the horizon
carries the rest.

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

## Reaping a retiring session

A long-running patrol agent recycles its context as it works, and each recycle
abandons its session tree whole: the inheriting session gets a new id and a new
tree. This churn is the largest source of dead trees, and the horizon is slow
to take it — a session between turns owns no process and reads as inactive, so
the horizon stays long on purpose, to spare a session that is only idle.

The retiring session has the certainty the horizon lacks. At the recycle, the
cycle-recycle hook names its own session to `scratch-reap.sh --session <id>`,
which takes that one tree at once: the same root rails and chmod-before-delete
as the full pass, but no horizon and no running-process hold, because the hook
is itself that process and the hold would decline the very tree the recycle
leaves. The hourly pass is the backstop for every session that ends without
naming itself.

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
against a synthetic root in a tempdir — no city, no network, no `gc`.

## Operating it

```bash
assets/scripts/scratch-reap.sh --dry-run     # the plan, and the largest files in it
assets/scripts/scratch-reap.sh               # reap, one summary line
assets/scripts/scratch-reap.sh --session <id> # take one session's tree now
```

`SCRATCH_REAP_ROOT` overrides the root, `SCRATCH_REAP_BUDGET` (default 240s)
bounds the pass. Every run names the five largest files it took, session trees
and loose files alike, so a writer that keeps recreating the same artifact
stays visible in the order log rather than only in the total.

## What it does not touch

Scope is the harness scratch root. Other `/tmp` tenants are reclaimed
elsewhere: build and test scratch left by killed or crashed runs is
`build-scratch-reap.sh`'s, the worktrees of closed beads are
`worktree-reap.sh`'s, the workspaces of ended reviews are
`review-workspace.sh`'s, and a horizon on `/tmp` as a whole is the host's
policy, not the pack's.
