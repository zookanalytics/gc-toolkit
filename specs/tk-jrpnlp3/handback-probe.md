---
name: A/B probe of the converse hand-back's purposes
description: Whether saying what each part of a converse hand-back is for changes what a sitting writes, measured on the four hand-backs the operator corrected on 2026-11-17 and 2026-11-18 and on a control. Read it to check the numbers in the PR, or to rerun the probe after changing the hand-back section.
---

# A/B probe of the converse hand-back's purposes

The bead asks that the new text be shown to change what a sitting writes on the
four hand-backs the operator corrected, and that it leave a full course where the
detail above the hand-back does not already lay one out.

## Method

Each arm is a rendered converse page, `generated/seed-audit/agents/converse-opus.md`.
Main's arm is taken at 8d778ffee. Three wordings of this branch were tried in turn,
and the third is the one committed, with two edits made after the probe. The list of
how a hand-back names its subject keeps main's bullets, where the third wording ran
it into one sentence, and the body's sentence on what the conversation is settling
opens with "Every hand-back's body" in place of "Either one". No measure below reads
either. The page went in as the system prompt, and the case went in as the user
message, in one call with no tools from an empty directory:

`claude -p --safe-mode --restricted --strict-mcp-config --disable-slash-commands --no-session-persistence --tools "" --model claude-opus-5-5 --max-turns 1 --output-format json --system-prompt "<arm>" < <case>`

The call ran with `env -i`, so no user settings, memory, hooks or skills reached it.
It ran on the rotation's current account.

Each case comes from the sitting's own transcript. It gives the subject's facts and
the part of the message the sitting had written above the hand-back it then posted.
It then asks for the hand-back alone, with no close-out line.

| Case | The moment | What the operator said next |
|---|---|---|
| recap | conversation tk-hx3btob, 2026-11-18T18:26Z, a brainstorm whose detail already made the case | "Your recap is kind of crap under Recommended." |
| label | conversation tk-gy4953q, 2026-11-18T00:32Z, a design that called a change of a bead's assignee "the name" | "\"A waiting bead that someone holds by name\" I don't follow" |
| terms | conversation tk-reymwh1, 2026-11-18T18:44Z, an answer on attach and reset, with the operator's turn before it | "Nearly everything else, your words are cryptic and unfollowable" |
| place | conversation tk-reymwh1, 2026-11-17T03:20Z, a framing that asks to place two held Gas City changes, with their descriptions | "I don't know what this work is that you're proposing" |
| control | the recap case with only the message's first paragraph above the hand-back, and the findings on the bead's notes, which the operator has not read | (none: the course must be stated in full) |

A separate call graded each run blind. It used Opus 5.5 with no tools, and it saw
the case's context and the hand-back but never the arm. It answered the case's
question and listed the words in the hand-back the operator would not know.
`bin/grade.py` in the kept copy holds each question.

## Result

Six runs in each cell.

| Case | Measure | Main | Wording 1 | Wording 2 | Wording 3 (committed) |
|---|---|---|---|---|---|
| recap | decision restates the detail above it | 6 | 6 | 6 | 6 |
| recap | decision in the "today … it becomes …" form | 4 | 0 | 0 | 0 |
| recap | decision's median words | 162 | 161 | 162 | 151 |
| label | the assignee change named in plain words | 0 | 0 | 1 | 2 |
| label | words the operator would not know, mean | 9.3 | 11.2 | 5.8 | 4.7 |
| terms | operator could follow each recommended change | 4 | 1 | 1 | 3 |
| terms | words the operator would not know, mean | 7.2 | 9.2 | 9.2 | 8.3 |
| place | says what both changes do, in the operator's words | 3 | 4 | 6 | 6 |
| place | says what they do before cost and timing | 3 | 4 | 5 | 6 |
| control | course stated in full | 5 | 6 | 5 | 6 |
| control | decision in the "today … it becomes …" form | 5 | 0 | 1 | 1 |

What changed between the wordings:

- **Wording 1** replaced the course form and the list of pipeline words with what each part is for. It dropped the "today … it becomes …" form and changed nothing else.
- **Wording 2** named each change by what it would change for the operator or the people the work serves, as they would see it or use it. It also had the sitting read the hand-back as the operator would and put each word they would not know in their terms, even a word the detail above used. The place case went to 6 of 6, and the label case's unknown words fell by a third.
- **Wording 3** gave a course the detail already lays out by its gist, and had each unfamiliar word replaced with plain words. The label case's unknown words halved against main's, and the place case said what the work does first in all six runs.

No wording stopped the recap. Every decision after the recap case's detail still
listed the course's parts again, though under wording 3 the list was shorter and no
run used the "today … it becomes …" form. The terms case is within the grader's noise.
Its word lists flag words the operator does see on the board, such as sitting, gate
and visit, and it split yes and no on hand-backs that used the same words.

## What the probe does not show

It is a cut-down sitting: no tools, no skills and one turn, with the detail above
the hand-back fixed in the original sitting's words. So it measures how far the
hand-back resists the detail's vocabulary, not what a sitting would write as a whole.
Six runs a cell shows a direction, not a rate. Only Opus ran, while two of the four
sittings ran on Fable. A later hand-back and the sign-off are unmeasured, and so
are the body's two new purposes, what the conversation is settling and what a
return's result settles, because no case turns on them.

## Size

240 runs: 120 hand-backs (1.64M tokens, 25 agent minutes) and 120 grades
(0.50M tokens, 11 agent minutes). The committed section is 856 words, against
611 on main, and the rendered converse page grows from 4,866 words to 5,111.

## Kept copy

`~/.cache/tk-jrpnlp3`: `bin/build.py` writes the cases from the transcripts,
`bin/gen-job.sh` and `bin/grade-job.sh` run one call each through `bin/clean.sh`,
`bin/grade.py` writes the blind grades, and `bin/score.py` prints the table. `arms/`
holds the four rendered pages, `cases/` the five cases, and `runs/gen` and
`runs/grade` every run's prompt and output.
