---
name: Gas City search — a sitting's push onto an open PR's branch
description: The search behind `gctk pr push`, the verb a converse sitting runs to push its commits onto the branch of a PR on the pending record, as AGENTS.md requires. It names each Gas City, Gas Town and bd primitive searched, at gastownhall/gascity e60ed864f346 and gastownhall/gascity-packs 0f07496d2fa4, what the verb composes, and why none covers the rest. Read it to judge the verb's divergence from Gas City, or before changing how a sitting writes an open PR's branch.
---

# Gas City search for tk-e70808f

Read on 2026-11-16 at `gastownhall/gascity` main e60ed864f346, through the
upstream remote of the city's gascity checkout, and at
`gastownhall/gascity-packs` main 0f07496d2fa4, from a clone of that commit.
Gas City is cited by page or by symbol, and Gas Town by path and line.

The surface the change adds is one verb of gctk's pr noun,
`gctk pr push <bead> --held-by <conversation> [--check]`. It proves that the
sitting's conversation holds the branch of the PR the bead owns and that
nothing else writes it, returns the PR to draft, and pushes the checkout's
HEAD onto the branch under git's lease. `--check` proves the holding and
changes nothing. The change adds no metadata key, bead kind, lifecycle state,
order or formula step. The `converse-edit` skill's text, which calls the verb,
is not surface.

## A session's push onto an open PR's branch

**Searched.**

- **Gas City's commands.** `gc github pr` has one verb, `backfill`, which
  queries the configured PR readiness monitors (`newGitHubPRCmd` in
  `cmd/gc/cmd_github.go`). A monitor's answer for a PR that is not ready is a
  repair bead (`ensureGitHubPRRepairBead`, same file), work that a pool's
  writer takes, not a push by the session that holds the PR. No gc command
  pushes a branch or changes a PR's draft state. Outside tests, `cmd/` and
  `internal/` hold no `force-with-lease`, and their `git push` and `"push"`
  hits are docker's image push, `git stash push`, a message that tells a person
  to run `git push -u`, and the doctor check and SSH settings for an agent's
  own push (`internal/git/sshkeepalive.go`).
- **Gas Town's refinery.** It pushes a PR's branch inside its own patrol step,
  `git push origin HEAD:$BRANCH --force-with-lease`
  (`gastown/formulas/mol-refinery-patrol.toml:1136`). The lease names no
  commit, and no session other than the refinery runs the step.
- **Gas Town's crew.** A crew worker pushes straight to the default branch,
  with no PR, and meets a refused push with `git pull --rebase && git push`
  (`gastown/assets/prompts/crew.template.md:182`, `:185`). A rebase rewrites a
  PR's history, which no branch of the pack takes.
- **Gas Town's witness.** Its salvage of a worktree is
  `git add -A && git commit && git push origin HEAD`
  (`gastown/agents/witness/prompt.template.md:355`).
- **The gascity repository's pre-push guard.** `assert_bead_still_claimed`
  re-reads, just before a push leaves, whether the session still holds the
  bead the branch names, by the names a claim records: `GC_SESSION_NAME`,
  `GC_SESSION_ID`, `GC_ALIAS` and `GC_AGENT` (`scripts/push-ownership-guard.sh`).
  It is that repository's own tooling, run by its `.githooks/pre-push`, and no
  pack under `internal/bootstrap/packs` carries it.
- **Draft and ready.** Nothing in either repository moves an open PR between
  draft and ready (a search of `gastown/` for `gh pr ready`,
  `convertPullRequestToDraft` and `--draft` finds none). The pack's
  `gctk pr draft` does, through gh ([the review-loop design's
  search](../tk-1tfzr71.108/gas-city-search.md#the-draft-cycle-and-the-withdrawal-unit-2)).
- **bd** holds no git and no PR.

**Not covered, so the verb.** No primitive pushes a session's commits onto the
branch of an open PR that the session holds, returns the PR to draft first, or
proves the holding. The verb composes what exists:

- the hold is bd's `blocks` edge from the PR's bead onto the conversation,
  which the pack already writes for every conversation on an open PR, and
  which keeps the landing order's review runs and the refinery's find-work off
  the bead while the conversation is open;
- the proof's reads of an attached review run and of the open beads that work
  the branch are the pr domain's, the reads the landing order keeps a run off
  a held branch by;
- the return to draft is `gctk pr draft`'s rule;
- the push is the pack's one pusher, `branch-push.sh`, with its `--from-origin`
  read after a fetch of the branch, so the lease is on the tip origin holds
  and a HEAD that does not descend from it sends nothing;
- the session's names are the four the gascity repository's guard reads, the
  names a claim stamps as its assignee.

## The sitting's checkout of the PR's branch

**Searched.**

- **`gc worktree`.** `Spec.validate` refuses a path inside a registered
  worktree (`rejectRegisteredWorktreeAncestor` in `internal/worktree/worktree.go`,
  called at line 238), so it cannot make a tree inside a sitting's home, where
  the pack keeps every per-bead tree. It requires the branch checked out on an
  attached HEAD (`internal/worktree/worktree.go`, line 321), which a PR's
  branch still checked out in a polecat's tree refuses. Its cleanup refuses a
  tree whose HEAD is not merged into its base (line 500), and the sitting
  removes its tree before the merge.
- **The reaper.** `auto_reap_closed_bead_worktrees` removes a per-bead tree
  once its bead closes, when the tree is clean and its removal orphans no
  commit, and names a tree's bead by its directory (`reapClosedBeadWorktrees`
  in `cmd/gc/bead_worktree_reaper.go`, line 102). A sitting's tree at
  `worktrees/<the PR's bead>` under its home is reaped once the PR's bead
  closes, as a change's tree is
  ([the earlier search](../tk-rymdhac/gas-city-search.md#the-changes-tree)).

**Composed, no surface.** The skill cuts the tree with git's own
`git worktree add --detach` on the tip it fetches, so no local branch of the
PR's name is created and none collides with a tree that has the branch checked
out. The reaper removes a tree whose sitting ended before removing it.
