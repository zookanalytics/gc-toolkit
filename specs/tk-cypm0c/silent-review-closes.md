---
name: Cause distribution over review beads that close without a verdict
description: What the gc-toolkit store actually holds behind the "27 of 47 reviews recorded nothing" finding — the measurement, the four causes it separates into, why the round-counter half of the bead was already answered by #493, and what residue was left to fix.
---

# Cause distribution over review beads that close without a verdict

Measured against the gc-toolkit store on 2026-09-01, before any fix landed.

## The population and the query

A gate review is a bead carrying `task_kind=review` and a `check_name`. That is
what `gate-ensure.sh` and `pr-facts.sh` stamp when they dispatch one, and it is
the identity `signoff.sh` and `review-sweep.sh` resolve against.

```bash
gc bd list --status closed --limit 0 --json \
  | jq '[.[] | select((.metadata.task_kind // "") == "review"
                  and (.metadata.check_name // "") != "")]'
```

That is 855 closed gate reviews. Filtering on the title `^Review ` instead
returns 1052, because the formulas pour step beads titled "Review the diff and
run verification" that are not gate reviews at all.

The figures the bead was filed with — 47 closed reviews, 27 of them silent — do
not reproduce against the store. Neither the total nor the ratio matches at any
`--limit`; the default listing is not truncated, and returns the same 1052/855.

## What "recorded nothing" has to mean

Reading bead notes is the wrong probe, because `signoff.sh` writes the verdict
to two different places depending on where the anchor is:

- **Post-open**, `post_artifact` posts the body as a `gh pr review --comment` on
  the PR and writes nothing to the bead.
- **Pre-open**, there is no PR, so the same body is appended to the review
  bead's notes.

So an empty-notes review with `gc.outcome=recorded` is a post-open verdict that
landed on GitHub exactly as designed. 120 of the 128 empty-notes reviews are
that case.

The probe that separates disposal from silence is close-time evidence. Both
authorized closers stamp `gc.outcome`: `signoff.sh` writes `recorded`,
`review-sweep.sh` writes `moot` and appends the reason it had no verdict to
give. Dispatch-time stamps — `reviewed_oid`, `check_name`, `review_branch`,
`review_base`, `review_pool`, `fix_target_pool` — say the review was asked a
question, not that it answered one.

## The distribution

Of the 855, eight carry neither notes nor `gc.outcome`. They separate into four
causes, and only the last is the defect:

| Cause | Beads | Evidence it left |
|---|---|---|
| Verdict recorded in metadata by the pre-rewrite reviewer | 3 | `verdict=COMMENT`, and on two of them a `review_id` naming the GitHub review |
| Superseded and closed as a duplicate | 1 | `duplicate_of` plus a `review_note` naming the rebase that killed the pin |
| Reviewing session declined and stamped its own outcome | 2 | `gc.work_outcome=no-op` |
| **Recorded nothing anywhere** | **2** | none |

The three legacy keys have no writer in the current pack. They date from before
the workflow-shaped rewrite, and a bead carrying one recorded a disposal under
the code of its day.

The two genuine cases are `tk-w88ll7` (anchor `tk-utjreo`, still open) and
`tk-83okw` (anchor `tk-zf4vm`, closed). One live residue, out of 855.

## Why the round-counter half was already answered

The bead states that `signoff.sh` computes `ROUNDS = TOTAL - FLOOR` where
`TOTAL` counts review beads under the anchor, so an empty review spends a round.
That was true, and #493 changed it. `rework_children()` now counts children
stamped `source_review_bead`, which only a `request-changes` signoff files:

```bash
n=$(printf '%s' "$kids" | jq '[.[] | select((.metadata.source_review_bead // "") != "")] | length')
```

`signoff.test.sh` holds it from both sides — "only rework children count as
rounds" and "dispatch_count is not a round count: reviews of one commit never
cap". A review that produces nothing files no child and spends no round.

What a silent close does still spend is a **dispatch**, against
`gate-ensure.sh`'s `GC_MAX_REVIEW_DISPATCHES` ceiling. That ceiling is meant to
bound dispatches, and gate-ensure says so where it fires: "This ceiling bounds
DISPATCHES; it is not GC_MAX_REVIEW_ROUNDS, which counts attempted rework in
signoff.sh." The live case shows both counters at once. `tk-utjreo` sits at
`dispatch_count=5` with `check.codex=exception@9f027aa8` and `gc.routed_to=human`,
and its `blocked_reason` names three rework rounds. The cap fired on three real
rounds; the silent review burned one of the five dispatches.

So the bead's cited anchors are not evidence of empty rounds advancing the cap.
They are anchors whose reviews kept failing to raise the gate, which is the
condition the dispatch backstop exists to stop.

## Where the silence came from

`signoff.sh` and `review-sweep.sh` both record. The hole was an instruction.
When `gate-ensure.sh` finds a wedged review — its poured workflow spent, no
verdict, no route — it escalates with two suggested repairs, and the second was
a bare `gc bd close $rid`. An operator following it produced exactly the residue
shape: closed, no outcome, no note, nothing saying the round was abandoned.

The repair now names a write that records the disposal, and
`gate-ensure.test.sh` asserts the escalation offers it and never offers a bare
close.

## The detector

`doctor/check-review-verdict-recorded` reports a closed review under an open
anchor that carries no close-time evidence. Anchor-open is the scope because
that is where the silence still costs something: the gate is owed and the
dispatch ceiling is counting. Under a closed anchor the same residue is history.

It reports one finding across the five stores — `tk-w88ll7` — and nothing else.
