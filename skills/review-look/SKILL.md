---
name: review-look
description: Use when you hold a review run's fresh look step, or when asked why a PR's review keeps finding things, or whether a review that has not passed should go on or come to a person.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Review look

You read the whole review of one PR, at a round the run's account called for
you, and you decide one thing: whether the review goes on to its next round, or
stops for a person's answer. You are a fresh session and never the round's
ruler, so the round's reasoning is not yours to defend. You rule no finding,
change no code and never narrow what a lane reviews. A review that keeps
finding real problems is doing its job. Your work is to find why the findings
keep coming.

## What the read gives you

The read prints the account of the run's rounds in one line, such as
`Round 3: 1 must-fix finding (5, 2, 1 by round), falling`, and whether the rule
forces a question at this round. Then it prints every round's findings with
their rulings and each finding that came back after a fix (its `restates`),
the PR's earlier review runs with their counts and how each ended, and each
commit that changed the review's rules under the PR. Those are the commits on
the PR's target that the head its review first judged does not carry, and the
pack's commits since its first run. Last come the commands that read the PR's
change. Read the change itself, and the findings against it, before you judge.

## Why the findings keep coming

Weigh each cause against what the read shows. More than one can hold.

- **The review's rules changed under the PR.** A commit in the read's rules
  list, such as a new method rule or a guidance edit, landed after the PR was
  written, and the findings apply it. Such findings are real. A rise in the
  counts they explain is not the review failing to converge. Name each such
  commit in your output's `rules`.
- **Text from an earlier design.** The PR changed course partway, and its
  comments, docs or summary still describe the first design. Each round fixes
  one place and a lane finds the next.
- **Each fix breaks something new.** The counts fall slowly or not at all,
  and each round's findings sit in code the round before wrote. The approach
  may be harder to get right than the PR's purpose needs.
- **The same point comes back.** A finding restates one an earlier round fixed,
  so that fix did not remove its cause.
- **Findings about what the PR should not do.** A lane keeps asking for work
  outside the PR's purpose, or re-raises a point a round declined.
- **The approach is wrong overall.** The findings cluster on the design
  itself, such as one section that draws a blocking finding every round, or a
  lane's note that questions the plan.

## Going on, or stopping

Send the review on when both of these hold:

- Its must-fix findings are falling, or new rules explain their rise.
- The causes you found are ones its next rounds remove.

Stop it when it will not converge on its current path. That is the case when
any of these holds:

- The count stays level or rises, for reasons new rules do not explain.
- The same point keeps coming back.
- The trouble points to the PR's approach.

At the run's last round by its bound, stop the review.

When the rule forces a question at this round, read the rules list first:

- When its commits explain the counts, name them in your output's `rules`.
  Only then can the review go on.
- When they do not, stop the review.

In your reading, say plainly whether you read the trouble as pointing to the
PR's approach being wrong overall.

## The one question a stop asks

Write the question so the person can answer it in about a minute, without
looking anything up. Lead with what is at stake in plain words: what the PR is
for, and what keeps it from passing. Give the options, usually two or three,
such as going on as it is, a named change of approach, splitting the PR, or
closing it. For each, say what it ships and what it asks of the person, and
recommend one with your reason. Name a bead or a PR only as a reference in
parentheses. Never let an id be the noun a sentence turns on.

## The output

Write one JSON object in the shape the read printed:

- `review`: `look`
- `head`: the head the round judged, as the read names it
- `verdict`: `continue` or `stop`
- `reading`: why the findings keep coming, and whether that points to the PR's
  approach being wrong overall, in a few sentences the round's comment shows
  the person
- `recommendation` and `question`: for a stop, the question as above and the
  option you recommend
- `rules`: each commit from the read's list that the reading gives as the
  cause of the counts

The record refuses a stop without its question or its recommendation, a
continue at a round the rule forces a question at that names no rule, a rule
that is not in the read's list, and a continue at the run's last round. A stop's
record files the question and marks your step failed hard, and you close the
step failed, which ends the run's loop at this round.
