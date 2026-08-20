---
name: Branch prepare mode — rebase only what is disposable
description: Why the refinery classifies a branch before bringing it current on its target, what the allowlist is and why it is an allowlist, and which alternatives were rejected. Read before widening the set of branches the refinery may rewrite.
---

# Branch prepare mode — rebase only what is disposable

## The defect

`mol-refinery-patrol.toml`'s `rebase` step applied one sequential-rebase
protocol to any branch it prepared for merge:

```bash
git checkout -b temp origin/$BRANCH
git rebase origin/$TARGET
```

and the mr path then force-pushed the result back over `$BRANCH`.

That is correct for a polecat branch — single author, reviewed as a unit,
rebase-to-current is the cheapest route to a clean merge. It is wrong for an
owned convoy's integration branch, whose commits are **already merged PRs with
their own review history**. Rebasing rewrites them: each PR still names the
pre-rebase objects, which the branch no longer holds, and those objects become
dangling and GC-eligible.

Nothing in the refinery pack encoded the distinction.

## The incident (2026-08-19, convoy tk-t80p1)

Work bead `tk-0d3y5` carried a twice-restated "MERGE main INTO integration. DO
NOT REBASE", reason stated inline. A refinery session rebased and force-pushed
anyway at 16:31:04Z. Three merged PRs were rewritten:

| PR | bead | before | after |
|---|---|---|---|
| #273 | tk-3j0ob | `a2ebf4b` | `b02a210` |
| #275 | tk-g0hd2 | `a0efbcb` | `9e7890d` |
| #294 | tk-b1jp5 | `c8feaf1` | `f2f526d` |

No content was lost — verified independently by the mayor, and the branch was
accepted on that basis. The pre-rebase tip survives only because the refinery
pinned it, as the origin tag
`rescue/integration-refinery-script-fixes-pre-rebase` -> `c8feaf1`. Unpinned, git
GC would eventually have destroyed the only copies.

**Why the prohibition did not hold.** It was as loud as a bead-level prohibition
can be, and it was on the wrong bead. `tk-0d3y5` was the hand-filed catch-up
bead; the session that rebased was processing the convoy's *graduation* bead
(`tk-t80p1`, stamped `branch=integration/refinery-script-fixes`, `target=main`,
`graduation=true`, `merge_strategy=mr` by `reconcile-graduated-convoys.sh`). A
per-dispatch instruction cannot reach the refinery's own protocol. The convoy's
working agreement had carried the same rule in the right place a week earlier —
further evidence that documenting it is not the fix.

## The remedy

Two marker-fenced blocks in `formulas/mol-refinery-patrol.toml`, both covered by
extracted-snippet tests so they cannot drift from the shipped instruction.

**`shared-branch-merge-mode`** (the `rebase` step) reads the bead ONCE,
shape-validated, classifies, and acts:

- `polecat/*` and not `graduation=true` -> `git rebase origin/$TARGET`
- everything else -> `git merge --no-edit origin/$TARGET`

**`shared-branch-push-mode`** (the merge-push mr path) force-pushes only when
the push actually rewrites history:

```bash
if git merge-base --is-ancestor "origin/$BRANCH" temp; then
  git push origin "HEAD:$BRANCH"
else
  git push origin "HEAD:$BRANCH" --force-with-lease
fi
```

### Why an allowlist

A denylist of known-shared prefixes (`integration/*`, …) is only as complete as
the enumeration, and the destructive branch is the default. The allowlist
inverts that: the sole shape the refinery may rewrite is the per-bead
`polecat/<bead-id>` branch, which the polecat branch convention *already*
guarantees is single-author and disposable — the same convention
`submit-branch-gate` enforces at the other end. An unrecognized branch —
`feat/*`, an unprefixed one-off, a shape invented next year — fails to the
non-destructive side by construction. Merging where a rebase would have done is
a cosmetic cost; rebasing where a merge was required is unrecoverable.

`graduation=true` is kept as an independent second signal. Under the allowlist
it is load-bearing in exactly one case — a graduation handed over on a
polecat-shaped branch — and it states the intent that the branch name only
implies.

### Why the push site re-derives from git, not from the classification

The two sites run in separate shell invocations, so a shared `PREPARE_MODE`
variable does not survive between them, and re-testing the branch name at the
push site would be a mirrored predicate free to drift from the first. Ancestry
is the same fact expressed where it is needed: a merge leaves the branch tip an
ancestor of `temp`, a rebase does not. It also makes the push arm correct on its
own terms — it forces only what it is actually rewriting — independent of
whether the classification above it is right.

### What was deliberately not done

- **A `gh`-based probe** ("is any commit on this branch reachable from a merged
  PR?"), which the bead offers as an alternative signal. It is the most general
  discriminator and the most fragile: it puts a network round-trip and a
  GitHub-availability failure mode inside the prepare step, and it answers
  slowest on exactly the large shared branches it exists to protect. The
  allowlist gets the same branches with a `case` statement.
- **Widening `rebase_hold`.** The operator gate already exists and already
  vetoes graduation. Making the safety depend on someone setting it is the
  instruction-shaped fix that has now failed once in production.

## Verification

`assets/scripts/mr-aware-rejection-failclosed.test.sh` — the suite already
extracting from this step; gc-toolkit has no test discovery, so a new
`shared-branch-*.test.sh` would be a regression nothing runs. Cases (A)-(J) run
the real extracted snippets against a real git repo with a real bare origin, so
"not rewritten" is asserted against git's object graph and a real push. 58
passed / 0 failed.

Mutation controls (each applied to a pristine copy of the tree, test run from
there):

| mutant | result |
|---|---|
| 1. allowlist removed | (B), (C) fail |
| 2. `graduation` override removed | (J) fails |
| 3. **both removed — the pre-fix protocol** | 9 fail, incl. "integration tip was REWRITTEN — the tk-t80p1 incident, reproduced" and "origin/integration/x lost its pre-push tip — merged PRs orphaned" |
| 4. push always `--force-with-lease` | (H) fails |
| 5. fail-closed shape check removed | (E) fails |

Mutant 5 initially passed: `(E)` asserted only the exit code, and with the shape
check deleted the block still exited 1 via the empty-`BRANCH` arm — the right
answer for the wrong reason. `(E)`/`(F)` now assert the *diagnostic*, which is
the only thing separating "bd was unreadable" from "this bead names no branch".

Neighbouring suites, unchanged: one-anchor-per-pr 13/0, check-set-normalize
20/0, preexisting-failure-dedup 14/0, signoff-anchor-failclosed 26/0,
find-work-gating-guard 28/0, first-round-review-body 29/0,
signoff-anchor-resolution 15/0, refinery-escalation-wiring 132/0,
signoff-round-cap 26/0. `merge-skill.test.sh` exceeds a 300s cap **on pristine
HEAD as well** — pre-existing, not introduced here.

## Related

`tk-0d3y5` (closed; carries the full audit and the content verification), convoy
`tk-t80p1`, PR #388, `docs/work-bead-state-machine.md` (graduation section).
