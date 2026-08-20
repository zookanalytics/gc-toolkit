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

## Round 2: the hand-back carries the classification

The signoff on round 1 found that refusing to rewrite the branch *here* does not
stop the rewrite from happening — it moves it one step downstream, to an actor
this block cannot reach (review `tk-wz00c`, P1; rework `tk-j32ep`).

Both rejection arms of this same step — `PREPARE_FAILED` on a conflict, and a
test regression in `handle-failures` — repool the same work bead to the polecat
pool. `mol-polecat-work.toml`'s workspace-setup then brought any rejected branch
current with `git rebase origin/{{base_branch}}`, and its submit step prints
"force-needed?" when the push that follows is non-fast-forward. So an
`integration/*` branch whose merge-from-main conflicted was handed to a worker
who would rebase it and then be invited to force-push it: the prohibition held
for the refinery and leaked around it, reaching the same three-merged-PRs
outcome by a different actor.

The prohibition cannot be restated on the bead — that is precisely what failed
in the incident. The classification has to travel.

**The remedy.** The `shared-branch-merge-mode` block stamps the mode it derived
onto the work bead, `metadata.prepare_mode` (`rebase` | `merge`), *before* it
touches the worktree, and refuses to prepare at all if it cannot record it:

```bash
if ! gc bd update $WORK --set-metadata prepare_mode="$PREPARE_MODE" >/dev/null 2>&1; then
  echo "could not record prepare_mode=$PREPARE_MODE on $WORK — NOT preparing the branch..."
  gc runtime drain-ack
  exit 1
fi
```

A new marker-fenced block in `mol-polecat-work.toml`,
`rejected-branch-resume-mode`, reads that key and merges instead of rebasing
when it says `merge`; the submit step's "force-needed?" hint is qualified with
the one case where a non-fast-forward push is a bug rather than an obstacle.

### Why the bead, and why on the happy path

The classifier runs once, in this step. The two rejection arms run in **separate
shell invocations** — the formula says so at its own branch-delete site — so
`PREPARE_MODE` does not survive to either of them, and `handle-failures` never
had it in scope at all. The bead is the only carrier that reaches both. Which
is why the stamp sits with the classification rather than inside the conflict
arm: written only where `PREPARE_MODE` is live, it would cover the conflict
hand-back and miss the test-failure hand-back, which rewrites just as
destructively.

This is the same reasoning as *Why the push site re-derives from git*, arriving
at the opposite mechanism, and the difference is worth stating. The push site is
in the refinery's own process and can observe the consequence directly
(ancestry); re-testing the branch *name* there would be a mirrored predicate free
to drift. The polecat can observe neither — by the time it holds the bead the
prepare has been aborted and there is no artifact of it to inspect — so the only
alternatives are a carried value or a second copy of the `case` statement in
another formula. A carried value cannot drift.

### Why absent means rebase

`rejected-branch-resume-mode` treats an absent `prepare_mode` as `rebase`, which
is the pre-existing behaviour, not a fail-open hole:

- every bead the refinery hands back has passed through the stamp, and the stamp
  is fail-closed, so absence never means "the refinery declined to say";
- absence means some *other* writer set `rejection_reason`, and both such writers
  want a rebase. One is the sibling site below, unchanged by this round rather
  than newly exposed by it. The other is
  `packs/gascity-keeper/template-fragments/refinery-rebase-handling.template.md`,
  whose preflight-failure hand-back repools a `mol-upstream-gc-rebase` bead —
  a bead whose entire purpose is divergent history force-pushed to `main` under
  an explicit lease. Defaulting *that* to a merge would break the one branch
  family that is supposed to be rewritten;
- the alternative, defaulting to `merge`, silently puts a merge commit into every
  ordinary rework branch in the city to guard a case that cannot occur.

Case (Q) pins the default so it cannot drift unnoticed.

## The sibling site this change does NOT cover

Sweeping for every path that can rewrite a shared branch — rather than only the
one the bead named — turns up a second reachable route to the same destruction,
which is filed as `tk-rvspf` rather than fixed here.

`assets/scripts/reconcile-merged-prs.sh`'s stale-base arm does not rebase; it
*dispatches* a rebase. It resolves `fix_branch="$head_ref"` — the PR's live head
branch, whatever its shape — and files a rework child into a live fix pool whose
`rejection_reason` reads "Rebase '$fix_branch' onto origin/$base ... and
force-push with --force-with-lease". `mol-polecat-work.toml`'s workspace-setup
then executes that on whatever `metadata.branch` names. Since round 2 that
execution is conditional on `metadata.prepare_mode` — but this arm stamps no
such key, so it still resolves to `git rebase origin/{{base_branch}}`. Neither
site classifies the branch.

The allowlist added here does not reach either of them: it guards the refinery's
own prepare step, and this path hands the rewrite to a polecat instead. A
graduation PR is the reachable case — PR #388's head branch was
`integration/refinery-script-fixes`; had it gone CONFLICTING rather than merging,
that arm would have dispatched a rebase and force-push of the same branch whose
rewrite is the incident above.

Its only current vetoes are `merge_hold` and `rebase_hold` — the operator markers
this document argues, two sections down, are the wrong thing to depend on.

Kept out of this change deliberately: different file, different actor, different
test suite (`reconcile-merged-prs.test.sh`, which already extracts from that
script). Fixing it here would mean a second, independently-invented classifier
landing unreviewed alongside this one; `tk-rvspf` proposes reusing this shape.

Round 2 makes that reuse concrete rather than aspirational: the carrier now
exists, so `tk-rvspf`'s remedy is to classify once at that dispatch site and
stamp `prepare_mode` on the rework child it files — the resume path already
honors it. No third classifier, and no change to `mol-polecat-work.toml`.

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

### Round 2

Same suite, cases (K)-(R) plus one work-order assertion — **85 passed / 0
failed**. (K)/(L) pin the stamp, (M) its fail-closed guard. (N)-(R) execute the
`rejected-branch-resume-mode` block extracted from the *other* formula against
the same real repo and bare origin, and follow it through the plain
`git push origin HEAD` that the submit step actually runs: whether that push
fast-forwards is precisely what decides whether the worker is shown
"force-needed?", so it is the assertion that proves the rewrite pressure is
gone rather than merely discouraged. (R) is case (G) followed through — the
branch whose merge conflicted, repooled and resumed.

| mutant | result |
|---|---|
| A. resume reverts to unconditional rebase | 8 fail: "integration/resume tip was REWRITTEN by the hand-back", "merge-mode resume pushes as a plain fast-forward (got '1' want '0')", "(R) the conflicting hand-back REBASED the shared branch — case (G) still leaks" |
| B. `prepare_mode` stamp deleted | 5 fail — (K), (L), (M) |
| C. work order stops naming the mode | 1 fail — the block1 work-order assertion |

All 23 suites that reference either formula, run at this commit: **0 failed**.
check-set-heal 184/0, check-set-heal-visibility 320/0, check-set-normalize 20/0,
detect-stalled-workflows 80/0, find-work-gating-guard 28/0,
first-round-review-body 29/0, gc-helm 23/0, liveness-sweep-delta 133/0,
merge-skill 274/0, mr-aware-rejection-failclosed 85/0, one-anchor-per-pr 13/0,
preexisting-failure-dedup 14/0, quiesce-completed-workflows 100/0,
reconcile-merged-prs 406/0, recover-stranded-branches 93/0,
refinery-escalation-wiring 132/0, resolve-salvage-branch 51/0,
signoff-anchor-failclosed 26/0, signoff-anchor-resolution 15/0,
signoff-rework-dispatch 45/0, signoff-round-cap 26/0, submit-branch-gate 29/0,
work-context-hook 21/0. `merge-skill` took 454s — over the 300s cap noted in
round 1, confirming that finding, and it passes when given room.

Neighbouring suites, unchanged: one-anchor-per-pr 13/0, check-set-normalize
20/0, preexisting-failure-dedup 14/0, signoff-anchor-failclosed 26/0,
find-work-gating-guard 28/0, first-round-review-body 29/0,
signoff-anchor-resolution 15/0, refinery-escalation-wiring 132/0,
signoff-round-cap 26/0. `merge-skill.test.sh` exceeds a 300s cap **on pristine
HEAD as well** — pre-existing, not introduced here.

## Related

`tk-0d3y5` (closed; carries the full audit and the content verification), convoy
`tk-t80p1`, PR #388, `docs/work-bead-state-machine.md` (graduation section),
`tk-rvspf` (the sibling dispatch site above, filed from this change's self-review).
