---
name: Gas City search — bringing a branch current over a rewritten target
description: The search behind `gctk pr bring-current`, the verb a review run's repair runs to merge a PR's target into its branch, from the commit of the target the branch took last when the target's history was rewritten after that, as AGENTS.md requires. It names each Gas City, Gas Town, bd and git primitive searched, at gastownhall/gascity 887a253144d4 and gastownhall/gascity-packs 44b9db7168f6, what the verb composes, and why none covers the rest. Read it to judge the verb's divergence from Gas City, or before changing how the pack brings a branch current.
---

# Gas City search for tk-sorhyoq

Read on 2026-11-25 at `gastownhall/gascity` main 887a253144d4, through the
upstream remote of the city's gascity checkout, and at
`gastownhall/gascity-packs` main 44b9db7168f6, through the GitHub API. Gas City
is cited by path and line at that commit, and Gas Town by path and line.

The surface the change adds is one verb of gctk's pr noun,
`gctk pr bring-current --target <branch>`. It fetches the target, finds the
commit of the target the branch took last when the target's history was
rewritten after that, and merges into the checkout it runs in. The change adds
no metadata key, bead kind, lifecycle state, order or formula step. The text of
the review skills that calls the verb is not surface.

The change accommodates no behavior of Gas City. The rewrite is the fork's own
upstream sync, and the base a merge takes is git's.

## A merge from a base the caller chooses

**Searched.**

- **Gas City's commands.** No gc command merges a branch or brings one
  current. `gc sling --merge` and `gc convoy --merge` take a landing strategy,
  direct, mr or local (`cmd/gc/cmd_sling.go:153`, `cmd/gc/cmd_convoy.go:142`),
  which routes how finished work lands, not how a branch takes its target.
  Outside tests, every `merge-base` in `cmd/` and `internal/` is an ancestry
  check, such as `internal/worktree/worktree.go:556`, or git's default base, as
  in `cmd/openapi-breaking/main.go:146`. Nothing reads a reflog, and nothing
  passes `--fork-point` or `--merge-base`.
- **Gas City's core pack.** A polecat brings its branch current by rebasing
  onto the base: `git pull --rebase origin {{base_branch}}` and
  `git rebase origin/{{base_branch}}`
  (`internal/bootstrap/packs/core/formulas/mol-polecat-commit.toml:66`,
  `:148`), and a rebase conflict is resumed by rebasing again
  (`internal/bootstrap/packs/core/formulas/mol-polecat-base.toml:102`). A
  rebase onto a named upstream replays every commit the upstream does not
  hold, since git turns `--fork-point` off when the upstream is named on the
  command line (git-rebase(1), `--fork-point`). After a rewrite that set
  includes the old history the branch carries.
- **Gas City's lifecycle example.** Its refinery merges with a plain
  `git merge --no-edit "$BRANCH"`
  (`examples/lifecycle/packs/lifecycle/assets/scripts/lifecycle-refinery-merge.yaml:104`).
- **Gas Town's refinery.** It rebases a diverged branch with
  `git rebase origin/$TARGET`, after an ancestry probe
  (`gastown/formulas/mol-refinery-patrol.toml:444`, `:472`).
- **bd** holds no git.
- **git.** `git merge` computes its own merge base and takes no other.
  `git merge-tree --write-tree --merge-base=<commit>` merges from a chosen
  base, but it writes only a tree: no commit, and no merge state in a worktree
  where a conflict can be resolved by hand. `git merge-base --fork-point` reads
  the target's reflog to find where a branch left an earlier incarnation of
  its target (git-merge-base(1), "Discussion on fork-point mode"). Of the eight
  PRs open on the gascity fork on 2026-11-25, six carry the old history and
  have already taken the rewritten main, and for each of those six it answered
  none. `git rebase --fork-point` uses the same answer, and the pack does not
  rebase a PR's branch, whose commits bead notes cite.

**Not covered, so the verb.** No primitive merges into a worktree from the
commit of the target the branch took last, and none finds that commit once a
branch has taken one rewrite. The verb composes git's own: it reads the clone's
reflog of the target with `git reflog`, keeps the commits the target no longer
holds with one `git rev-list`, and takes the newest whose `git merge-base` with
HEAD is newer than git's own. It then writes, with `git commit-tree`, the
commit `git merge -s ours` would record for that commit merged into the target,
the target's tree with both as parents, and runs `git merge` on it. git's merge
then goes from the commit the branch took last, leaves a conflict in its own
merge state, and `git show --remerge-diff` on the merge reads only what was
resolved by hand. With no rewrite, the verb is `git merge` of the target.

## Measured

On a shared clone of the gascity checkout carrying that checkout's reflog of
`origin/main`, at main 13cdf670ca, with the verb built from this branch:

| Head | Plain merge | The verb |
|---|---|---|
| PR #259 before its rework, fffce55212 | 100 conflicts, 43 in files the PR never touched, and 56 untouched files left unlike main | base 96179ad1f6 found; 56 conflicts, every one in a file the PR changed, the set `git merge-tree --merge-base=96179ad1f6` gives, and no untouched file unlike main |
| PR #260 before its rework, f959e523e8 | 53 conflicts, 52 in files the PR never touched, and 58 untouched files left unlike main | base 96179ad1f6 found; 1 conflict, the PR's own test file, and the merge differs from main only in the PR's two files |
| The eight open PR heads | | a plain merge each, in about 3 s with the fetch |
