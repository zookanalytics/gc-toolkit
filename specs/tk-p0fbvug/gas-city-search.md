---
name: Gas City search for moving an agent home after its default branch is rewritten
description: Use when you judge why worktree-setup.sh moves a home whose HEAD is a tip the default branch had before a rewrite, such as a fork's rebase, how it tells that home from one holding a session's work, where that departs from the 2026-11-05 ruling that a rewrite is a cutover step, or when you re-verify the agent home provisioning warrant.
---

# Gas City search for moving an agent home after its default branch is rewritten

Read on 2026-11-23 at `gastownhall/gascity` main dfd5200c3ee3 and
`gastownhall/gascity-packs` main 44b9db7168f6, with git 2.56.1. The change it
records makes `assets/scripts/worktree-setup.sh --sync` move a home whose HEAD is
a tip origin's default branch had before it was rewritten. Before it, the sync
failed that home's start and filed a report until a person moved the home.

## What the search looked for

- **A Gas City owner that moves a home after its default branch is rewritten.**
  None. The agent home cleanup (`cleanupClosedBeadAgentHomeWorktrees` in
  `cmd/gc/agent_home_worktree_cleanup.go`) moves a home to a detached origin/main
  only when it carries the worker-dir prune's `.worktree-stale` marker, sits on a
  branch whose bead is closed and has no uncommitted changes. A home a rewrite
  strands carries no marker. `Ensure` in `internal/worktree/worktree.go` returns
  an already-valid worktree unchanged and never repairs state it did not create,
  and it serves a bead's tree, not an agent's home, as the agent home provisioning
  warrant in [docs/warrants.md](../../docs/warrants.md#agent-home-provisioning)
  records. Nothing else reads a reflog or handles a forced update of a default
  branch: `git grep -E 'fork-point|reflog|forced-update|force-push'` over the
  `*.go`, `*.toml` and `*.sh` files outside tests finds bd's Dolt compact and sync
  commands under `examples/bd/dolt/commands/` and `scripts/push-ownership-guard.sh`,
  none of them about a worktree.
- **Gas Town's copy.** `gastown/assets/scripts/worktree-setup.sh`, last changed on
  2026-10-03 (f709abe5d0c6), refuses such a home. The home's stable branch sits on
  the old main, which is not an ancestor of the new tip, so the script prints
  "has unique or diverged work; preserving it and refusing sync" and exits 1. Its
  `for-each-ref --contains` test over `refs/heads` and `refs/remotes` lets a
  detached HEAD that some ref holds reach that check, and moves nothing.
- **The primitive git ships for it.** `git merge-base --fork-point <ref> <commit>`
  finds where the history leading to `<commit>` forked from `<ref>`, and takes
  `<ref>`'s reflog into account "to see if the history leading to <commit> forked
  from an earlier incarnation of the branch <ref>"
  ([git-merge-base](https://git-scm.com/docs/git-merge-base#_discussion_on_fork_point_mode)).
  `git rebase --fork-point` and `git pull --rebase` use it to rebase onto an
  upstream that was rewritten. It reads every tip the reflog records, the new
  value of each entry and the old value of the oldest, and answers only with one
  of them. So when it prints HEAD itself, HEAD is a tip the default branch had,
  and the home's history holds nothing that branch did not hold.
- **The test the bead proposed.** `git branch -r --contains HEAD` finds nothing in
  the fork's rig for e03752646, the old tip the 2026-11-06 rewrite left every home
  at. The refs that contain it are local: `refs/heads/backup/pre-sync-20261105`,
  two under `refs/backup/` and one under `refs/backups/`. Origin carries
  `backup/pre-sync-20261013` and not the 2026-11-05 backup
  (`git ls-remote origin 'refs/heads/backup/*'`). That test would have refused
  those homes, and it would move a home on a commit a session pushed to a branch
  of its own, which the sync must report (case (ag)).
- **The keeper's sync formulas.** `packs/gascity-keeper/formulas/mol-upstream-gc-*.toml`
  are not the path a sync takes. Neither the HQ store, this rig's store nor the
  fork's holds a run of the sync or rebase formula created since 2026-10-20, and
  the fork's one keeper run since then is a pr-prep, on 2026-11-12. The record of
  sitting tk-tf79ak6 (tk-497orjy's notes, 2026-10-30) says the operator runs
  syncs with a non-keeper session and then does the cutover. A step in the
  keeper's formula would not have run at either rewrite.

## What the fork's rig shows

- **How often its main is rewritten.** The reflog of `refs/remotes/origin/main` in
  the fork's rig records three rewrites, on 2026-10-24 (107 commits of the old
  main dropped), 2026-11-06 (102) and 2026-11-10 (96). Every other move it records
  is a fast-forward.
- **What became of the cutover step.** Since #1389 a home on the old history fails
  its start, and its report names the move, which the sync task carried as a
  cutover step (tk-z3hkju4, note of 2026-11-05T20:23Z). That task closed at
  2026-11-06T21:19Z with the step not run. The rig resumed at 22:54Z, six home-sync
  findings were filed in the fork's store, and the rig started nothing for 41
  minutes, until the mechanik moved the 17 homes by hand at 23:35Z. The bead's
  description counts 40 failed creates in that time. After the 2026-11-10
  rewrite, pushed at 23:41:05 -0700, one pass moved every home of the rig at
  23:50, each by commit id where the sync names `refs/remotes/origin/main`, and no
  finding was filed. The step runs when a person remembers it, and it was missed
  at one of the two rewrites since the rule.
- **Where homes sit.** On 2026-11-23, every linked worktree under `.gc/worktrees/`
  in the three rigs whose HEAD is not a tip that `origin/main`'s reflog records is
  a closed conversation's home in this rig (38), which never starts again, or a
  per-bead tree holding its own commits (4), which the sync never runs in. Every
  home in the fork's rig sits at a recorded tip. `merge-base --fork-point` took
  8 ms on the reflog of this rig's `origin/main`, 325 entries.

## What the change is

- **The rule.** `check_head` reads a HEAD the tip does not contain as no finding
  when `git merge-base --fork-point <default ref> HEAD` prints HEAD itself. The
  home then moves as a detached home does: back onto its own branch when that
  branch fast-forwards to the new tip, and otherwise detached at the tip, its own
  branch left on the old history. A home on its own branch at the old tip moves
  detached as well, since that branch cannot fast-forward. The run prints nothing,
  files no report and records the clear, as any clean start does (case (z)).
- **What still fails the start.** A commit a session made on the old history
  (case (z)), a commit on a branch the default branch never had as its tip, though
  a remote branch holds it (case (ag)), and every edit, untracked file and stopped
  operation. The sync still saves, discards and forces nothing, and it moves a
  home only from a commit the default branch had as its tip.
- **When the record runs out.** git expires a reflog entry whose old or new
  commit the tip does not reach once the entry is older than
  `gc.reflogExpireUnreachable`, 30 days by default, at a later `git gc`. The old
  tip is the new value of the entry that brought it, and the old value of the
  entry the rewrite's fetch writes, which `--fork-point` reads while that entry is
  the oldest left. In the fork's rig every entry older than a rewrite's is one the
  new tip does not reach, so those go first, and a home at the tip from before
  the rewrite is recognized until 30 days after the rig fetched the rewrite. A
  home that first starts after that fails its start and files the report, as
  every such home did before this change (case (ag)).
- **Why the fork point and not containment.** Asking whether any tip the reflog
  records contains HEAD would also move a home behind an old tip. The census finds
  no such home, so the change composes git's primitive as it stands. Reading the
  tips with `git rev-list -g` would also miss one: it prints each entry's new
  value, and a clone writes `origin/main` no reflog, so the tip a rig was cloned
  at is only the old value of the first entry. A mutant built that way fails
  case (z).
- **The report.** A HEAD with commits the tip lacks still fails the start, and its
  report no longer calls its move "the step that moves every home of a rig whose
  default branch was rewritten", a step nothing runs.

## Where this departs from a ruling

On 2026-11-05 the operator said, in conversation tk-g0hh666 (tk-1tfzr71.10's notes
at 20:21Z): "Handling the forced push situation (why gascity fork has issues) is
an isolated scenario and can have clear steps to resolve instead of having it be a
core part of the packs logic", and "edits to a home should be flagged quickly and
vocally, they are a sign of a bug". The rule the sitting proposed from those, which
the operator accepted, made a rewrite of the fork's main a cutover step and "not
script logic". This change makes one case of it script logic: a home whose HEAD is
a tip the default branch had. At the first rewrite after the ruling the step went
unrun, and the rig started nothing for 41 minutes. The sync still fails the start
on every edit, as the second quote asks. The bead's placement (backlog refinement,
2026-11-23T05:08Z, the bead's notes) quotes the operator: "Always happy to have PRs
to review for a set of items to fix when they're independent of epics and broadly
applicable", which does not speak to the ruling.

## How this copy differs from Gas Town's

One row joins the table in
[specs/tk-1tfzr71.10/gas-city-search.md](../tk-1tfzr71.10/gas-city-search.md#how-this-copy-differs-from-gas-towns),
and it narrows that table's row for a detached HEAD the tip does not contain, which
fails the start unless it is a tip the default branch had.

| This script | Gas Town's | Why | Ends when |
|---|---|---|---|
| A home whose HEAD is a tip the default branch had before a rewrite moves to the new tip, detached when its own branch cannot fast-forward there | Refuses and exits 1, since its stable branch is not an ancestor of the new tip | The fork's main is rewritten every one or two weeks, and the cutover step that moved each home by hand was missed at one of two rewrites | The fork's main is no longer rewritten, or Gas Town's script moves such a home |

## Limits of this record

- A home behind an old tip that is not itself a recorded tip fails its start after
  a rewrite, as before. No home that starts is in that shape today.
- A rig whose `core.logAllRefUpdates` is off records no tips, and a rig whose
  `origin/HEAD` moves to a renamed branch reads that branch's reflog, which holds
  none of the old branch's tips. Their homes fail their starts after a rewrite, as
  before. Every rig here is a non-bare checkout, where git logs remote-tracking
  refs by default.
- The census is one moment, read with `GIT_OPTIONAL_LOCKS=0`.
