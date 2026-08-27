---
name: A review dispatched into an in-flight rework, and the guard that stops the verdict
description: Why gate-ensure re-dispatched a review at the commit the previous verdict had just rejected, why signoff then bound that verdict to a commit the rebase had removed, which half #493 already fixed, and what the remaining guard is responsible for. Read when changing signoff's evidence binding, gate-ensure's dispatch conditions, or the rework loop.
---

# A review dispatched into an in-flight rework (tk-bpo8cj)

Two components each did their own job correctly and, between them, spent a
review round and a polecat round on a commit that had left the branch.

## The measured run

PR#559 in signal-loom, 2026-08-27, all times UTC.

| time | event |
|---|---|
| 02:33:26 | review sl-ztp2u dispatched, pins dc47a703 |
| 02:59:38 | sl-ztp2u returns request-changes; rework sl-9k9um filed; `check.codex` cleared |
| 03:00:43 | sl-9k9um claimed |
| 03:01:01 | review sl-udwwq dispatched, pins dc47a703 — the same commit sl-ztp2u just rejected |
| 03:11:35 | sl-9k9um rebases and force-pushes 0b59bf73; dc47a703 leaves the branch |
| 03:15:08 | sl-9k9um closes |
| 03:30:31 | sl-udwwq submits request-changes against dc47a703 |
| 03:31 | rework sl-u4caj minted from that verdict |

sl-u4caj had nothing to implement. Its polecat verified both P1 findings at
the live head, found them already closed, ran the gates green, declined to
commit, and escalated.

## Two defects, not one

**Dispatch.** `signoff.sh --verdict request-changes` clears `check.<gate>`
when it files the rework child. gate-ensure classifies an absent marker as
"needs raising" and dispatches — its own message already named the case,
`check.codex is absent (never reviewed, or cleared by a REQUEST_CHANGES
signoff)`. Nothing consulted the rework child, so the pass 82 seconds after
the clear re-reviewed the exact commit the previous round had rejected. This
is not a race: it fires on every request-changes verdict.

**Binding.** `signoff.sh` binds a verdict to the `reviewed_oid` stamped at
dispatch and never asked whether that commit was still on the branch. The pin
was correct when taken and wrong ten minutes later. `mol-review` already told
reviewers that signoff refuses "a head that moved past your pin"; no such
refusal existed. The verdict text itself recorded the discrepancy and
reviewed the dead pin anyway, because the formula pins to `reviewed_oid` by
contract.

## The dispatch defect is #493's (tk-gr420e)

This branch carried a second guard for the dispatch half, and it was dropped
on the rebase: #493 landed `already_answered` in `gate-ensure.sh` first, and
its refusal is the better-bounded one.

`already_answered` refuses a dispatch when a **closed review judged this exact
head on this gate** and the rework child that verdict filed is still open.
That is the measured run precisely: sl-ztp2u closed against dc47a703, sl-9k9um
was open, and the 03:01:01 pass would have been refused. #493 also wires the
refusal into the stranded-review re-sling arm, which this branch did not, and
puts a `GC_MAX_REVIEW_DISPATCHES` ceiling behind it for the reviews that leave
no verdict and no visible child.

The guard dropped here refused a dispatch while **any** open rework child
blocked the anchor, keyed on `source_review_bead` or `rejection_reason`.
Replayed on top of #493 it would have shadowed the more precise refusal, and
it refuses more: at a head that has already moved past the judged commit, #493
dispatches — a new commit is a new answer — where this one waited for the
child to close. Nothing bounded that wait, which is the shape #493's own
backstop exists to prevent.

One case is left uncovered: `pr-facts.sh` files its conflict rework with
`rejection_reason` and no `source_review_bead`, so a review dispatched while a
rebase rework is in flight is invisible to `already_answered` and gets its pin
rewritten out from under it. That case is now handled downstream rather than
prevented — the binding guard below refuses the verdict, clears the dead pin,
and the reviewer re-pins at the live head. The cost is one review dispatch,
which #493's ceiling counts and escalates.

## signoff: no verdict for a commit that has left the branch

Growth and replacement are different questions, and only one of them is a
defect:

- The branch **grew**. The reviewed commit is still in the history, the
  findings still describe code that is there, and `green@<pin>` correctly
  fails the merge's live-head condition. This is the documented design and is
  unchanged.
- A rebase, amend or squash **removed** the pinned commit. The findings
  describe a diff the branch no longer carries.

`oid_on_branch` answers `on | gone | unknown`. Post-open it asks GitHub's
compare endpoint and tests `merge_base_commit.sha == <pin>` — an exact
ancestry answer that needs no local objects and does not depend on reading
compare's `status` field. Otherwise it fetches the branch and asks
`git merge-base --is-ancestor`. Unknown proceeds: a probe that cannot reach
the remote must not discard a review round that actually happened.

On `gone` both verdicts refuse and exit 1. Nothing is written to the anchor —
no marker cleared, no marker stamped, no rework child, no PR comment. The
refusal is recorded on the review bead, and the dead dispatch pin is cleared
so a re-claim resolves the live head instead of landing back here. A caller
who passed a dead `--reviewed-oid` over a live dispatch pin has not staled the
dispatch, so that pin is left alone.

Both verdicts, not just request-changes: an approve at a departed commit is
inert against the merge condition, but it posts a public comment certifying a
commit nobody can find.

This is the backstop for every way a head moves under a live review that
`already_answered` cannot see: an author pushing directly, an operator rebase,
a `pr-facts.sh` conflict rework between passes. Applied to the run above, it
refuses at 03:30:31 and sl-u4caj is never minted.

## Ordering against the 40-hex grammar (#489)

`signoff.sh` now runs two refusals over the same resolved `reviewed_oid`, and
the order is load-bearing. #489 (`tk-43chr6`) refuses an oid that is not 40
lowercase hex; this branch refuses one that has left the branch. The grammar
check runs first, so an abbreviated pin is refused on the grammar and its
`reviewed_oid` is left in place — the dead-pin clear below belongs to a pin
that was well-formed and got rebased away, not to one that was never valid
evidence. Reversing the two would start clearing malformed pins as though they
were dead ones, and `oid_on_branch` would be comparing a short oid to a full
head. The crossing case is pinned in `signoff.test.sh`; nothing pinned it
before, because when each guard was written the other did not exist.

## Adjacent, not fixed here

`docs/state-machine.md` documents `check.<g>=fixable@<oid>` as "addressable
problems; a rework child is in flight". Nothing writes it — `signoff.sh`
clears the marker instead — though `merge.sh` holds on it and
`doctor/check-gate-integrity` enforces its grammar. The condition that marker
names is tracked by the dep edge rather than by the marker. Whether the verb
should be written, or dropped from the grammar, is a separate decision.

A rebase silently stales `generated/seed-audit`. `assets/hooks/pre-commit`
regenerates the tree when a commit stages a seed input, but `git rebase`
replays commits without running it. Both of this branch's rebases hit it: onto
`12c67c4`, which carried a `formulas/mol-witness-patrol.toml` edit, and onto
`cb8393e0`, where main's own committed render was already stale against #516's
polecat-prompt edit. `doctor/check-seed-audit-current` catches it, but only
after the merge. Whether a `post-rewrite` hook should re-check is a separate
decision; until then, re-run the renderer after any rebase that crosses a seed
input.

## Verification

- `assets/scripts/signoff.test.sh` — 107 assertions, 27 of them new. Against
  the pre-change script 16 fail, so they are not vacuous. They cover post-open
  refusal, approve refused on the same terms, growth still binding at the pin,
  an unanswerable probe proceeding, the pre-open git-ancestry fallback,
  `git rc=128` reading as unknown, and the pin-clearing rules. Three mutants
  were run: an always-`gone` probe fails 63 assertions, an unguarded pin unset
  fails the caller-override assertion, and a probe that refuses growth fails
  the two ancestor-pin assertions.
- The suites sharing `test-harness.sh` — `gate-ensure`, `merge`, `pr-facts`,
  `pr-open`, `refinery-reconcile`, `lifecycle`, `convoy-graduate`,
  `cutover-2026-08` — all pass unchanged, as does `review-dispatch-body`.
