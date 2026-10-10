---
name: Telling a superseded branch from a drifted one
description: The tells branch-supersession.sh reads in a trial merge to decide that a landed change made a conflicting branch moot, its thresholds, and the pack history they were checked against — five known supersessions, 34 stale-base rework children, and 13 bring-current merges.
---

# Telling a superseded branch from a drifted one

The conflict arms (`pre-open-rebase.sh`, and the CONFLICTING arm of
`pr-facts.sh`) dispatch a merge-in rework child whenever a branch no longer
merges into its target. Most conflicts are drift, and a polecat merges the
target in. Some are not: a change that landed first deleted or rewrote the code
the branch edits, or shipped the branch's purpose under the same names. A
polecat sent there either keeps the branch's side of the conflict, reverting
what landed, or stops and asks the operator, after the session is spent.

`assets/scripts/branch-supersession.sh` tells the two apart before the dispatch,
and for a supersession files the operator's `rework-base-supersession` decision
instead of a child. This records what it reads and why its thresholds sit where
they do.

## The tells

All three come from one `git merge-tree --write-tree` of the branch into the
target, with nothing checked out.

| Tell | Shape in the trial merge |
|---|---|
| Deleted or rewritten block | A conflict hunk (`git merge-file --diff3`) whose target side keeps at most 25% of the words of a base region of 50 words or more. |
| Deleted file | A modify/delete conflict: the target deleted a file of 50 words or more that the branch edits. |
| Duplicate definition | A function or type name that both sides newly define in one file (one package directory for Go), which the merge result then defines twice. |

None of these count:

- **Moved code.** A block or file that the target moved is no tell. Moved means
  more than half of its lines of 8 characters or more reappear among the
  target's added lines. The branch's edit can follow it.
- **Minified output.** A block or file averaging over 40 words a line is
  minified or bundled output, not authored code.
- **Generated and test files.** Files the repository declares
  `linguist-generated` are not read, and neither are test files (`*_test.go`,
  `*.test.*`, `*.spec.*`, `test_*.py`).
- **Collapsed definitions.** Identical definitions that the merge collapses into
  one copy are not a duplicate.
- **Go `init`.** `init` may be defined any number of times in a package.

Retention is counted in **words**, not lines. Rewrapping a comment changes every
line and keeps every word. A line count read the rewrapped signoff.sh comment
under PR#546 (rebase child tk-11cho7) as a rewrite, at 0% of lines kept. By
words it kept 100%. Prose with renamed headings, as in PR#480 (tk-z6yme4), keeps
77–95% of its words.

## What the guard does with a supersession

`branch-supersession.sh hold` runs after each arm's own vetoes and dedup, just
before the arm files or re-routes a child:

1. **A decision is already open.** If a `rework-base-supersession` visit is open
   on the anchor and its route addresses somebody, it holds. The demand a
   converse sitting files while working the visit sits on the visit, not the
   anchor, so the visit itself is the hold. The route is judged with
   `pool-route.sh --verdict`, the reading `escalate.sh` gives an open visit it
   finds. A visit with no route, a route no live agent carries, or another rig's
   pool has asked nobody, so it holds nothing and the guard goes on to classify.
   On a supersession `escalate.sh` finds that visit and repoints it at the
   board, or refuses and the arm proceeds.
2. **Classify.** Drift, or a trial merge it cannot read, proceeds to the
   ordinary child.
3. **File the decision.** On a supersession it files the visit through
   `escalate.sh` on the anchor and holds behind it. If the visit cannot be
   filed or repointed, or no open visit that asks somebody stands behind it
   afterwards, it proceeds. A guard that removed a dispatch with no record
   behind it would be a silent strand.

The operator rules the visit one of three ways:

- **Retire it.** Disposing of the anchor (`pr-dispose.sh`, or `bead-rehome.sh`
  before a PR exists) takes it out of both arms.
- **Re-scope it.** A rework child the sitting sends sits live on the branch, so
  the arm's dedup stands down before the guard is asked.
- **The overlap is incidental.** A visit closed `benign` opens `escalate.sh`'s
  verdict window (24 hours by default). Within it, the next pass finds no open
  visit and the arm dispatches the ordinary merge-in child.

## Calibration

The thresholds were set against everything the pack's history offers.

### Known supersessions

| Branch (rework that went to a polecat) | Target, with the landed change | Classification |
|---|---|---|
| polecat/tk-lcv9a @f2a29cd1 (tk-ejc2qm) | main @98241e0f, #614 removed the commit pin | rewritten 25-line and deleted 7-line blocks in `gate-ensure.sh`; names #614 |
| polecat/tk-bcb6n1 @d1a6cf6e, PR#583 (tk-qcbjqf) | main @e423db60, #695 routed the deacon sweep through `patrol-finding.sh` | two rewritten blocks in `mol-deacon-patrol.toml`; names #695 |
| polecat/tk-mq9bvj @86629c74 (tk-tr90rf, tk-50kn6y) | main @1fa6a359, #747 shipped the same stall signal | `preOpenStallReason` defined on both sides in `services/helm/internal/board`; names #747 |
| polecat/tk-xhwits @9ebab091, PR#564 (tk-lskt27) | main of 2026-09-02, the signoff-cap park rewrites (#546 among them) | deleted 15-line block in `signoff.sh` |
| polecat/tk-j81t84 @d90999ef, PR#473 (tk-z81s7z) | main of 2026-09-01, #554 landed the successor docs | **missed**: a prose successor; its conflict hunks keep 48–83% of their words |

The miss falls through to the ordinary child, which is what happens today. A
polecat finds the rebase resolves to empty and escalates by hand.

### Ordinary conflicts

- **Stale-base rework children.** There are 37 on record whose
  `rejection_reason` cites the head they were filed at, and 34 of those heads
  are still in the object store. Each was classified against main as of the
  child's creation. Three fire: tk-qcbjqf, tk-lskt27 and tk-50kn6y, all
  supersessions above. None of the other 31 fires. That includes all 23 that
  shipped as ordinary merges or rebases.
- **Bring-current merges.** There are 13 merge commits in the object store whose
  parents conflict (parent 2 is the target, parent 1 the branch). None fires.

### Near misses that set the thresholds

| Case | What happened | Why the classifier stays quiet |
|---|---|---|
| `services/helm/web/src/App.tsx`, merges into polecat/tk-jlzsdz (2026-09-30) | main restructured the board markup the branch changed one line of; the polecat re-applied it | a 39-word region is under the 50-word floor |
| `agents/converse/prompt.template.md`, PR#817 (tk-7egc9c) | main moved a 104-line block into `skills/converse-settle/SKILL.md`; the polecat moved the branch's edit with it and shipped | 76% of the block's lines reappear among main's additions, so it is moved |
| `services/helm/web/dist/assets/*` against tk-mq9bvj's branch | the Helm app's committed build output, rebuilt on both sides, reads as modify/delete | 118 to 473 words a line, over the 40-word ceiling; the densest hand-written file in the repo averages about 11 |

The floor of 50 words sits between the smallest true block (58 words, the 7-line
deletion in `gate-ensure.sh`) and the largest ordinary one (39 words, `App.tsx`).
That margin is thin. A future false positive near the floor is a reason to
revisit it with the new case added to this table.

## What this does not cover

- **Rework queued before the sibling lands.** Two of the four wasted dispatches
  on record were filed by `signoff.sh` before the superseding change landed:
  tk-ejc2qm, the original instance, and tk-tr90rf. A dispatch-time check sees
  nothing then. The catch point is the polecat's rework resume, tracked as
  tk-5oim02l, which reuses this classifier.
- **Two efforts on one area before either lands.** That is gap 1 of tk-b7c72m.
  Without a diff, the only signals are proxies, which tk-boj67o measured. This
  guard covers its observed cost only once the first effort has landed.
