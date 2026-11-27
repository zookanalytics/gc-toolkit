---
name: A review that goes on while it converges
description: The design tk-vdyedm5 built for a PR's review run, which goes on while its must-fix findings fall and stops for a person's answer when they do not, in place of the fixed three-round stop: the account of each round, the rule that forces a question, the fresh look, how a stop ends the run, the bound, and the rule replayed on the recorded stops. Read it when changing how a review run's loop ends, or when judging a stopped review.
---

# A review that goes on while it converges

A review run (`formulas/mol-pr-review.toml`) used to stop after three rounds,
whatever its counts did, and wait for the operator behind a
`review-loop-exhausted` gate. Of the 14 such stops the team classified on
2026-11-25, 8 were on runs whose must-fix findings were still falling, and they
held about 300 of the roughly 400 hours PRs sat stopped. The 6 that were not
falling each changed the PR's course once a person looked. So the run now goes
on while it converges, and it brings a person only a review that is not
converging, as one framed question.

## The account of a round

At each round, code counts the lane findings the round ruled must-fix
(`services/gctk/review/converge.go`). A person's ask ruled must-fix is left
out: it is the person's request and no finding of the review, and counting it
blurs the record (see the replay). A round that fixes only an ask still goes on
to the next.

The round's ruler marks a finding that raises again a point an earlier round of
the run ruled must-fix and fixed, in the ruling's `restates`, which the output
check holds to that earlier finding. Code follows a chain of such marks to its
first finding. Each round's comment on the PR carries the account in one line,
such as `Round 4: 3 must-fix findings (5, 4, 4, 3 by round), falling, so the
review goes on to round 5.`

## The rule

The rule forces a question at round n when:

- the round ruled must-fix findings, no fewer than round n-2 did, and round n-2
  ruled some, so its must-fix findings have not fallen over two rounds; or
- one finding has come back a second time, so findings of two rounds of the run
  restate it, directly or through each other. Two lanes that raise it again in
  one round are one return.

A round two back with no must-fix finding is no baseline, as when round 1 fixed
only an ask and the next rounds judge the work the ask added. Comparing over two
rounds, and not one, also catches a count that falls and rises in turn.

## The fresh look

A fresh look (`formulas/mol-pr-review-look.toml`) is due at a round that goes
on, one that ruled something must-fix or pushed, when the round is the third or
every third after, when the rule forces a question there, or when it is the
run's last round by its bound. The repair's output check fills the round's
`look` list from the account, and rule-and-repair's fan-out bonds the look. The
look runs on the run's review pool, so it is never the round's ruler, who runs
on the repair pool.

The look reads the whole review through `gctk review look`. That read covers
every round's findings and rulings, the PR's earlier runs, and the review's
rules that changed on the PR's target since its first run: the rig's
AGENTS.md, CLAUDE.md, check index and guidance, and the pack's review skills and
review formulas. Its method is the `review-look` skill. It sends the review on,
or stops it for a person's answer with one question, a recommendation and its
reading of why the findings keep coming, which says whether the trouble points
to the PR's approach being wrong overall.

At a round the rule forces a question, the look sends the review on only by
naming commits among the rules that changed as the cause of the counts, so a
rise new rules on main explain is not read as a review failing to converge. At
the last round it stops the review. The record (`gctk review look --file`)
writes the look into the round's comment through the next post, and into the
notes of the bead that owns the PR.

## How a stop ends the run

A stop files its question as a human gate keyed
`review-question-not-converging` on the bead that owns the PR. It writes
`gc.failure_class=hard` on its own step and closes the step failed, so Gas City
ends the loop at that round without running its check ([the
search](gas-city-search.md#ending-a-checked-loop-before-its-bound)). The run
records no result, as a run any hard failure ends.

The gate is a question of the review run's family. So the PR's status reads it
as a person's hold (`held:gate`), and a person's post on the PR filed after it
pours a run that rules the post and can settle it. Clearing the gate pours a
fresh run. The landing order counts a run its look stopped as no failure of the
re-offer (`review.Ending.Asked`), and the PR's status gives no machine fault for
it while the question is open.

## The bound

Gas City requires `max_attempts` to be an integer. Its default goes from 3 to
30. The rule ends a run long before that. A round with must-fix findings goes on
without a question only when it counts fewer than two rounds before, or when
that round counted none, as a round that fixed only a person's ask does. So a
run whose first two rounds count a and b must-fix findings, and none of whose
rounds fixes only an ask, passes or is stopped within a+b+2 rounds, unless a
fresh look names rules that changed on the PR's target as the cause of the
counts. The record's largest a+b is 18 (#1641's second run: 4, 14). A look is
due at the 30th round, and it stops the review, so the bound brings its reading
with it too.

## The rule replayed on the record

The 24 review-loop-exhausted stops in the store from 2026-11-18 to 2026-11-27,
each by its lane must-fix findings per round. Every stop came at round 3, which
went on, so a fresh look is due at each. `TestTheRuleOnTheRecordedStops` holds
the table.

| Stop | PR | Counts | The team's class | The rule at round 3 |
|---|---|---|---|---|
| tk-6mpj3cl | #1563 | 1, 2, 1 | not converging | forces the question |
| tk-yt62pij | #1584 | 1, 1, 1 | not converging | forces the question |
| tk-nju0cqr | #1588 | 2, 3, 3 | not converging | forces the question |
| tk-wb6wf46 | #1559, run 1 | 3, 2, 3 | not converging | forces the question |
| tk-r8aaxk5 | #1559, run 2 | 2, 3, 2 | not converging | forces the question |
| tk-0gqb484 | #1559, run 3 | 3, 3, 2 | not converging | the look decides |
| tk-gwoys0n | #1595 | 2, 1, 1 | converging | the look decides |
| tk-tj88b69 | #1606 | 2, 1, 1 | converging | the look decides |
| tk-kayrfpy | #1641, run 1 | 5, 2, 1 | converging | the look decides |
| tk-w2qbipl | #1647 | 2, 1, 1 | converging | the look decides |
| tk-s1rwuvu | #1660 | 3, 2, 1 | converging | the look decides |
| tk-sgq8w7m | #1653 | 2, 2, 1 | converging | the look decides |
| tk-ety7vxv | #1699 | 7, 3, 1 | converging | the look decides |
| tk-vj35xmv | #1641, run 2 | 4, 14, 3 | converging | the look decides |
| tk-pmzj6kb | | 5, 3, 1 | later | the look decides |
| tk-52xbn98 | | 0, 1, 1 | later | the look decides |
| tk-967x60p | | 3, 1, 1 | later | the look decides |
| tk-t6o6tex | #1641, run 3 | 5, 3, 1 | later | the look decides |
| tk-zafqctw | | 5, 2, 1 | later | the look decides |
| tk-mt06mrz | | 7, 2, 4 | later | the look decides |
| tk-s4o15xk | | 1, 1, 2 | later | forces the question |
| tk-k0hmxim | | 1, 2, 1 | later | forces the question |
| tk-n31dr90 | | 0, 3, 1 | later | the look decides |
| tk-cp8ajd0 | | 2, 1, 1 | later | the look decides |

The rule forces the question on 5 of the 6 runs the team found not
converging, and on none of the 8 it found converging, which each get a look
that can send them on. It differs in one case. #1559's third run fell from 3 to
2, so no count rule catches it. What a look would read there is a different
finding each round, mostly text the PR's redesign left describing the old
design, and two earlier runs of the same PR that stopped the same way. That is
the look's judgment, and its read prints both. No recorded run marked a finding
as restating another, because `restates` did not exist, so the replay tests the
count rule alone.

The thresholds tested and not chosen:

- **"Not falling for two rounds running"**, the description's starting point
  (m_n ≥ m_{n-1} ≥ m_{n-2}), forces only 2 of the 6.
- **Counting a person's asks with the findings** forces only 3 of the 6, since
  an ask fixed in round 1 raises its count.
- **Comparing with round n-2 even when that round had none** would force the
  question on tk-n31dr90 (0, 3, 1), whose round 1 fixed only an ask, and whose
  count then fell from 3 to 1.

## Where this departs from the description

- **Gas City has an exit.** The description says Gas City's checked step ends
  early only when its check passes, so the pack works around it and owes an
  upstream fix. A member's hard failure ends the loop, since upstream #7583, and
  upstream's own review loop uses it to stop for a maintainer's decision. The
  change composes that exit, accommodates nothing, and files no issue upstream.
- **The gate is a question.** The description has the review-loop-exhausted
  gate become the question. That key reads as the machine's fault, and a stop
  for non-convergence is a ruling a person owes, so the stop files a question of
  the review run's family. `review-loop-exhausted` stays for a loop whose check
  spends its last attempt with no look to stop it.
- **The count rule compares with two rounds back**, which the replay chose
  over the description's starting point, as above.
- **A person's asks do not count** toward the must-fix findings.

## Out of scope

No agent owns a PR, and no conversation or written state is kept for one, and
no PR comment is routed to a sitting, as ruled on 2026-11-25 in conversation
tk-ubdhc4f. A ruler adopting a reviewer's change to the PR's stated plan without
asking is not addressed.
