---
name: A/B probe of the PR summary's brief
description: Whether the brief in mol-polecat-work's submit step 4 changes what an author writes, measured on real summaries of a decision, a design, a release boundary and a restamp, and on one small change. Read it to check the numbers in the commit, or to rerun the probe after changing the step's wording.
---

# A/B probe of the PR summary's brief

The operator-profile rule on one-minute decisions was already in the polecat
prompt when these summaries were written, so a second statement of the same goal
proves nothing by reading well. The change has to be shown to change what an
author writes.

## Method

Each arm's system prompt held the same short role line, the operator-profile
entry on one-minute decisions, and that arm's copy of submit step 4, from its
heading up to step 4b. The old arm's copy came from
`origin/integration/tk-nrsd2fd` at 097c9ef33. The new arm's holds the same words
as this branch's step, wrapped differently.

The user message was the same in both arms for a given case. It held what the
author had when the real summary was written, and it ended by asking for only the
text of the summary file.

| Case | The real summary | What the author got |
|---|---|---|
| Decision | PR #1307's first composition. Its second sentence said it "asks you one thing", and the operator opened a visit because they were "not sure where it's asking or what decision it made". | The bead and the three commits that summary covered |
| Design | PR #1271's first composition, a design for the operator's checkpoint, which listed what the operator approves after its account of the design. | The bead, the doc's decision section and alternatives section, and its other headings |
| Boundary | Unit C's first composition (anchor tk-5u2xpan). One stamp later the pm check sent it back, because it opened on identifiers and named its wait on the cutover at word 535, under "Worth checking". | The bead, the design's paragraph on the units' order, and the bodies of the fifteen commits that summary covered |
| Restamp | The round on anchor tk-0brqmv that took its summary from 1,424 words to 1,723 with nothing folded. The round's exception sat at word 954, in the fifth decision bullet, with part of it among the mechanics at word 305. The pm check sent it back. | The summary as stamped before that round, and the round's commit 6ff43ab2 |
| Small | PR #1361, a plain removal with nothing to decide. It tests for padding and for an invented decision. | The bead and its commit |

Each run was one call from an empty directory, with no tools and the case on
stdin:

`claude -p --model claude-opus-5-5 --tools "" --max-turns 1 --no-session-persistence --output-format json --system-prompt "<arm>"`

That is five cases, two arms and three runs each, so 30 calls, for $2.11 in all.
Two earlier passes of the new arm, on drafts of this wording (30 calls, $2.40),
are not counted in the table.

## What the probe does not show

It is a cut-down prompt, not a real submit step: no tools, commit bodies in place
of the whole diff, and the rule set next to the step instead of among the rest of
the polecat prompt. That favors the old arm: its boundary runs state the wait at
about word 340 where the real summary stated it at word 535, and its restamp runs
rewrote the summary where the real round edited it in place. Its decision runs
match the real summary's open text, about 500 words against 522, with the real
one's other 311 words in a fold. Three runs per cell shows a direction, not a
rate. No real session has yet composed a summary under the new text.

## Result

Positions count whitespace-separated words from the start of the summary. The open
text is everything before the first `<details`. Each row lists runs 1, 2 and 3.

| Case | Measure | Old arm | New arm |
|---|---|---|---|
| Decision | Names keeping the order, with what that costs | 2 of 3 | 3 of 3 |
| Decision | Says what happens if the operator does not decide | 0 of 3 | 3 of 3 |
| Decision | Open text | 504, 534, 500 | 580, 570, 493 |
| Design | First sentence poses the decision | 1 of 3 | 3 of 3 |
| Design | Position of the first rejected option and its cost | 265, 296, 247 | 183, 163, 144 |
| Design | Says what happens if the operator does not decide | 0 of 3 | 3 of 3 |
| Design | Open text | 509, 522, 520 | 578, 565, 516 |
| Boundary | Position where the wait on the cutover is first stated | 333, 344, 336 | 32, 33, 56 |
| Boundary | Open text | 574, 583, 557 | 328, 364, 384 |
| Restamp | Position where the round's exception is first stated | 29, 73, 258 | 26, 7, 15 |
| Restamp | Open text | 1,246, 927, 616 | 465, 426, 542 |
| Small | Whole summary | 364, 361, 367 | 413, 427, 401 |
| Small | Invents a decision | 0 of 3 | 0 of 3 |

Read by eye, beyond the table:

- The old boundary runs open "Moves human engagement off visits" (runs 1 and 3)
  and "Unit C of the native-gates design" (run 2). Each states the wait under a
  heading past the middle: "What to weigh", "Worth checking" and "Limits to
  weigh". That is the shape the pm check sent back. All three new runs open
  "Approving moves".
- The design's first sentence: old run 2 asks "should the refinery stop relying on
  a clock to notice stuck work?", and old runs 1 and 3 say it adds one design doc.
  New runs 1 and 2 open "Decision: should the refinery", and run 3 opens "Decide
  how the refinery should pick up work."
- Every new restamp run folded the earlier rounds' text into three or four
  sections, each opened on one line. Runs 2 and 3 made the round's exception the
  decision they open on. Run 1 says "with one narrow exception you can rule on
  below" in its first sentence.
- The decision case is the weakest. Two old runs already set out retiring against
  keeping, with both costs, as the profile entry asks. The new arm adds what
  follows if the operator does not decide, and its open text is no shorter.
- In the small case the new runs come to about 50 words more: a sentence on cost,
  and one saying nothing starts on merge. That is what the rule costs on a change
  with nothing to decide. No run invents a decision.
- No run in either arm wrote a bare `<details>` line.

## What the drafts changed

The first draft asked for "what approving sets in motion, any release boundary
included", and its decision clause named only a design doc. Six of its 15 runs
then said there was no release boundary or ordering, and none of its three
decision runs named keeping the order. So the step now asks for what approving
sets in motion only when there is something, and says to leave out what does not
apply, and the clause also reaches a call the branch made for the operator.

The second draft said "a call the branch made on their behalf". All three small
runs then raised the branch's one-clause departure from its bead, a choice of
wording in a docs table, to the operator as a decision, and one opened on it. So
the clause now reads "that costs something either way", which leaves that wording
out and keeps retiring against keeping in.
