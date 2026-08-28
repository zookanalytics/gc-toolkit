---
name: seed-audit staleness at merge time
description: Why tk-mp9c4q's squash-merge premise is falsified, what the two cited instances actually were, why the residual merge-time race needs no gate, and the one time the silent path fired (#517) before main carried a render to collide with. Read before adding a merge-time or pre-land check for generated/seed-audit/.
---

# seed-audit staleness at merge time

Recommended disposition: **WONTFIX**. Build no merge-time gate.

tk-mp9c4q reports that `generated/seed-audit/` goes stale at squash-merge,
because the recorded source digest is computed against a branch tree while the
squash combines that render with whatever inputs main gained meanwhile. It
cites two landed commits as proof and asks whether to add a refinery pre-land
re-render, a rebase-freshness requirement, or neither.

The premise is falsified. Neither cited instance was introduced by a
squash-merge, and the race the bead names is reachable only as a consequence of
the defect that did cause both: the pre-commit hook was never wired, so it never
ran. That defect was tk-hq4v3l, and it is fixed.

## Re-deriving the cited evidence

Each tree was extracted with `git archive` and hashed by its own copy of
`assets/scripts/render-seed-audit.sh --print-digest`, which is the same
computation `doctor/check-seed-audit-current` performs.

| commit | PR | recorded | actual | |
|---|---|---|---|---|
| `e15ae44` | #441 | `d0418708dfaa` | `d0418708dfaa` | match |
| `b8a4a6a` | #451 | `d0418708dfaa` | `1cfd502f0e67` | mismatch |
| `5c1499c` | #452 | `3adad85932e5` | `23d71a581321` | mismatch |
| `e723ae5` | #453 | `3adad85932e5` | `23d71a581321` | mismatch, inherited |
| `f51aa02` | #471 | none | `7d64f2d0e3ac` | no `INDEX.md` |

The bead's three numbers reproduce exactly. Its reading of them does not.

## What #452 actually was

The bead states that #452 "regenerated correctly for its own branch tree and
recorded `3adad859…`", and that "its branch was based before b8a4a6a, so the
merged tree hashes `23d71a58…`". Three facts contradict that.

The branch was not based before `b8a4a6a`. Its `baseRefOid` is `b8a4a6a`, and
the parent of its single commit `9e2b014` is `b8a4a6a`. `b8a4a6a` landed at
`2026-08-24T04:24:44Z` and `9e2b014` was committed at `2026-08-24T04:33:14Z`,
eight and a half minutes later. The PR timeline records one commit and no
force-push, so nothing rebased it afterwards.

The squash-merge changed nothing. `tree(9e2b014)` and `tree(5c1499c)` are the
same object, `d4227b9ddf43575af2a76ed30100ef75ab940046`. The tree that landed on
main is byte-identical to the tree that sat on the branch.

The recorded digest describes a tree the branch never had. Reconstructing
`e15ae44` plus the branch's own edit to `agents/converse/prompt.template.md`
yields `3adad85932e5db6e4b70d9d8739b02a155e2f87e21dcfc9d3c4de7058692c1ca`, which
is the recorded value in full. The render was taken against the pre-`b8a4a6a`
input set and the output was committed on top of `b8a4a6a`.

Had the hook been wired, staging `agents/converse/prompt.template.md` would have
re-rendered and re-staged the artifact, and the recorded digest would have been
`23d71a58…`. It was not wired: tk-hq4v3l established that `core.hooksPath` was
unset across the gc-toolkit checkout for this entire period. So #451 and #452 are
one defect, not two. #451 shows it as an artifact that never moved, and #452
shows it as an artifact carrying a hand-run render from an earlier input set.

## The residual race, and why it self-detects

A squash-merge can strand a stale artifact, in principle. The branch renders
against its own inputs, main moves a different input, and the merge takes main's
input alongside the branch's artifact. What decides whether that is silent is
whether main re-rendered.

Both cases were run against a scratch repository seeded with the real `INDEX.md`
from `e15ae44`.

Both sides re-render. Main moves one input and the hook regenerates; the branch
moves a different input and the hook regenerates. `git merge` exits 1 with
`generated/seed-audit/INDEX.md` conflicted. Every render rewrites the single
`- source digest:` line, and two independent renders always write different
values there, so the collision is unconditional. GitHub reports the pull request
as not mergeable, `assets/scripts/merge.sh` holds on its `mergeStateStatus
CLEAN` gate, and the refinery repools the work with `prepare_mode=rebase`. The
resuming polecat rebases and the hook re-renders against the combined input set.

Main moves an input without re-rendering. `git merge` exits 0 and the stale
artifact lands with nothing raised. This is the only silent path. Reaching it
requires main to hold no render that would collide. One way is main being stale
itself, which is the unwired-hook defect again. The other is main holding no
`INDEX.md` at all, which is the state #465 left behind. The second way is how
this path fired at #517, recorded below.

The self-detection depends on `INDEX.md` carrying one whole-tree digest on one
line. A future `INDEX.md` that dropped that line, or recorded per-file digests
instead, would remove the property. `doctor/check-seed-audit-current` already
exits 2 when the line is missing, which holds the dependency in place.

## Options weighed

A refinery pre-land re-render was the bead's first option. `merge.sh` merges
through `gh pr merge --squash --match-head-commit` and never touches repository
content, so it would have to construct the merged tree, run a render needing
`gc` on the refinery host, and push the result to the head branch. That push
moves the head, which invalidates `--match-head-commit`, voids every
`green@<oid>` gate on the anchor, and returns the pull request to review. The
cost is a review round on every land that touches a prompt input, paid to
prevent a case that conflicts on its own.

A rebase-freshness requirement was the second. It would hold any branch whose
merge-base lags main on a digest input. Those inputs are `agents/`,
`template-fragments/`, `formulas/`, `packs/`, `pack.toml` and the renderer,
which are the most-edited paths in the repository, so the gate would fire
constantly. It buys nothing over the conflict, which already holds exactly the
branches that would land something wrong.

Neither is worth its cost against a race that surfaces as a merge conflict.

## What the disposition rests on

`core.hooksPath` is per-clone local configuration and cannot travel in a commit.
It reads `assets/hooks` in `rigs/gc-toolkit` today, and it resolves through
linked worktrees because the path is relative. #465 made
`render-seed-audit.sh --install-hook` a documented first-install step, and
`doctor/check-seed-audit-current` warns whenever the setting is anything else.
That warning is the standing control on the one silent path, and it is
tk-hq4v3l's ground rather than this bead's.

`generated/seed-audit/` in main holds a rendered tree as of #517. The stub state
#465 left behind is over, so there is a recorded digest to go stale and the
absent-artifact warning no longer stands.

## What #517 landed

#517 committed the first rendered tree since #465, and it was stale when it
landed. Its render recorded `356b6788f3b6`, taken at the branch base `70198d8`.
#516 (`e1bf479`) moved `template-fragments/polecat-doctrine.template.md` between
that base and the merge. Restoring that one file to its `70198d8` content on top
of `0c50151` and re-running `--print-digest` returns
`356b6788f3b637f5c96fcd265c637c3135933f03b225bcd90643bfcdcd921f19`, the recorded
value in full, so that change is the whole delta.

The squash exited 0 because main still held the `README.md` stub and carried no
`INDEX.md` to conflict on. `doctor/check-seed-audit-current` went from the
absent-artifact warning to exit 2 at that commit. Each row below was measured by
checking the commit out and running the check against it with `GC_PACK_DIR` set
to that tree.

| commit | PR | recorded | actual | exit |
|---|---|---|---|---|
| `8ca3304` | #518 | none | | 1, absent |
| `0c50151` | #517 | `356b6788f3b6` | `4c57bb1500d3` | 2 |
| `0514729` | #503 | `356b6788f3b6` | `4c57bb1500d3` | 2 |
| `c66b054` | #515 | `356b6788f3b6` | `8a7421219dc6` | 2 |
| `b5169c3` | #506 | `356b6788f3b6` | `8a7421219dc6` | 2 |
| `ba5e093` | #488 | `356b6788f3b6` | `8a7421219dc6` | 2 |
| `cb8393e` | #523 | `356b6788f3b6` | `8a7421219dc6` | 2 |
| `2057968` | #510 | `b75dd6222f76` | `b75dd6222f76` | 0 |
| `d73daef` | #525 | `b75dd6222f76` | `b75dd6222f76` | 0 |

main sat at exit 2 for six commits, from 2026-08-27T21:26:03Z to
2026-08-27T23:16:04Z. `pack.toml` moved at `c66b054`, which changed the actual
digest while the recorded one stayed pinned. #510 closed the window without
being about the audit: it edited the renderer and `formulas/mol-review.toml`, its
branch rendered against main's current inputs, and the artifact matched at land.

This does not reopen the gate question. The collision that holds the race is a
conflict on the single `- source digest:` line, and it needs a render on both
sides. Main carries one now, so a branch that renders against an input set main
has moved past conflicts rather than landing silently.
