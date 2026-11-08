---
name: A/B probe of the converse hand-back definition
description: Whether the rewritten hand-back definition changes what a sitting writes, measured on the three framings the operator could not place. Read it to check the numbers in the commit, or to rerun the probe after changing the definition.
---

# A/B probe of the converse hand-back definition

The bead reports that a second statement of the operator's goal would not have
changed these framings, because the shape let them pass. So the change has to be
shown to change what a sitting writes, not only to read better.

## Method

Each arm's system prompt held the same short role line, the operator-profile
entry on one-minute decisions, and that arm's copy of the hand-back definition,
from its opening line up to "Record each hand-back". The old arm's copy came from
`origin/integration/tk-nrsd2fd`. The new arm's came from this branch.

The user message was the same in both arms for a given case. It held the facts
the prime prints for that subject, the visit's title and body, and the
"what I found" paragraphs that sitting wrote, cut from its transcript above the
hand-back it then posted. It ended by asking for the framing, leaving out the
close-out line.

Each run was one call from an empty directory, with no tools:

`claude -p --model claude-opus-5-5 --tools "" --max-turns 1 --no-session-persistence --output-format json --system-prompt "<arm>" "<case>"`

That is three cases, two arms and three runs each, so 18 calls, for $0.77 in all.
An earlier single pass of six calls, on a draft of this wording, is not counted.

## What the probe does not show

It is a cut-down prompt, not a full sitting: no skills, no tools, and findings
already written. Three runs per cell shows a direction, not a rate. It tests only
a sitting's first framing, so a later hand-back and the sign-off are unmeasured.
The real sittings ran before the definition changed, so no sitting has yet been
seen under the new text.

## Result

A run places the subject when the text names it as the operator asked: the
witness and no PR for the report, PR #1240 for the decision, and the operator's
own ask for the capture. A message's opening is its first paragraph, or the
first bullet under it when that paragraph is only a heading. A hand-back's
opening is the first paragraph of its body. "Bare words" are moot, twin, fold,
retract or park, in any form, anywhere in the hand-back.

| Case | Arm | Message's opening places it | Hand-back's opening places it | Bare words in the hand-back |
|---|---|---|---|---|
| Report | old | 0/3 | 0/3 | fold, folds, moot, parked, twin |
| Report | new | 3/3 | 2/3 | none |
| Decision on a PR | old | 2/3 | 1/3 | none |
| Decision on a PR | new | 3/3 | 3/3 | none |
| Operator's ask | old | 0/3 | 0/3 | fold, folds |
| Operator's ask | new | 3/3 | 3/3 | none |

Totals: the message's opening places the subject in 2 of 9 old runs and 9 of 9
new runs, and the hand-back's opening in 1 of 9 old runs and 8 of 9 new runs.

Read by eye, beyond the table:

- The one new miss is report run 2, which wrote "This automatically filed bug has
  no PR" and named no filer in the hand-back. Its message opening does name the
  witness.
- No new-arm report header names who filed the report. Each names what it found,
  and the body's first sentence carries the rest.
- Decision run 1 opens on "the PR that creates the gap, #1240" and says what the
  PR does only in its next sentence. Runs 2 and 3 open on what it does.
- Each new decision message says what the decision is in its first sentence and
  names PR #1240 in its second.

Messages grew by about 5%, averaging 436 words in the old arm and 456 in the new
one.

## Each run's opening

Each opening is cut to its first sentence, or to the sentence that names the
subject when that one comes later.

### The witness's bug report (tk-eiphpx, sitting tk-ab9p1pk)

- **old 1.** Message opens: **Why the proposed close fell through:** it assumed last week's fix for false auto-closes had removed the cause.
  Header: `tk-eiphpx — Stuck-work alerts can stay muted after an auto-close`. Body opens: When an alert auto-closes because its condition cleared, the system can treat that as "no action needed" and mute the next alert on that work for 24 hours.
- **old 2.** Message opens: **Why the proposed close fell through:** it assumed last week's fix for false auto-closes had removed the cause.
  Header: `tk-eiphpx — Stuck-work alerts can stay muted after an auto-close`. Body opens: An alert that auto-closes when a handoff bounces mutes the next alert on that handoff for 24 hours, even if it comes back and stalls again.
- **old 3.** Message opens: **Why the proposed close failed.** It assumed last week's fix for false auto-closes had removed the cause.
  Header: `tk-eiphpx — Stuck-work alerts muted for a day after an auto-close`. Body opens: When a stuck-handoff alert auto-closes because the handoff left the queue, the next alert on that handoff is muted for 24 hours, even if it comes back and stalls again.
- **new 1.** Message opens: This is a bug report from the witness, with no PR on it, about stuck-handoff alerts going silent.
  Header: `tk-eiphpx — muted stuck-handoff alerts`. Body opens: This witness report has no PR, and it needs your ruling because its proposed close failed validation.
- **new 2.** Message opens: This is a bug filed by the witness, with no PR yet: after a stuck-handoff alert closes, the next alert on that handoff can stay muted for 24 hours.
  Header: `tk-eiphpx — Stuck-handoff alerts muted after an auto-close`. Body opens: This automatically filed bug has no PR, and it's with you because the proposed close failed validation.
- **new 3.** Message opens: A bug report from the automated witness monitor (no PR involved) has reached you because a proposed close didn't hold up: stuck-handoff alerts can still be muted when a handoff stalls again.
  Header: `tk-eiphpx — Stuck-handoff alerts muted after a bounce`. Body opens: This witness-filed bug report has no PR, and it reached you because the proposed close didn't hold up: the bug is still live on main.

### The decision about PR #1240 (tk-ffkaf0l, sitting tk-zugqzbt)

- **old 1.** Message opens: **What I found** - **The PR is otherwise ready.** The dismiss PR (#1240) has your approval, green CI and approval from every review lane.
  Header: `tk-ffkaf0l — Rulings that end a sitting on an open PR`. Body opens: Ending a sitting with a ruling can change what an open PR must contain, but the new dismiss path never asks whether it does.
- **old 2.** Message opens: **What I found** - **The gap is in your own hand on the board.** Dismissing a held sitting lets you resolve a gate by typing a ruling.
  Header: `tk-ffkaf0l — Can dismissing a sitting let a PR merge past your ruling?`. Body opens: The dismiss change is approved, green and ready to merge (PR #1240).
- **old 3.** Message opens: **What changed since this was filed** - **The dismiss PR is ready to merge (#1240).** You approved it at 02:54 UTC today, CI is green, and every review lane approved.
  Header: `tk-ffkaf0l — Should dismissing with a ruling ask whether the PR must change?`. Body opens: Dismissing a sitting can record a ruling that changes what an open PR must contain, without asking whether it does.
- **new 1.** Message opens: This is the open decision on whether dismissing a sitting should ask if your ruling changes an open PR. It affects PR #1240, which adds the dismiss step and is otherwise ready to merge: you approved it at 02:54 UTC today, CI is green, and every review lane approved.
  Header: `tk-ffkaf0l — Should dismiss ask if a ruling changes an open PR?`. Body opens: This decision is still open and reached you because the PR that creates the gap, #1240, is approved and ready to merge.
- **new 2.** Message opens: This decision is whether Dismiss should ask if your ruling changes an open PR, as a ruled sign-off already must. It reached you because PR #1240, which adds the Dismiss step, is approved and ready to merge with the question still open.
  Header: `tk-ffkaf0l — PR #1240: should Dismiss ask if a ruling changes the PR?`. Body opens: PR #1240 adds the board's Dismiss step and is ready to merge, but this question about it is still open and needs your call first.
- **new 3.** Message opens: You opened this to settle whether Dismiss should ask if a ruling changes an open PR. That question now decides how PR #1240 (the Dismiss step) ships, and PR #1240 is otherwise ready to merge.
  Header: `tk-ffkaf0l — PR #1240: should Dismiss ask whether a ruling changes the PR?`. Body opens: PR #1240 adds the board's Dismiss step and is approved and passing, but this decision is still open.

### The operator's skill-gap capture (tk-fqw7x2b, sitting tk-o73de41)

- **old 1.** Message opens: **What happened.** When you said go in a sitting on 10-13, the agent took 18 tool calls and nearly ten minutes to carry it out, and its first six calls went on reading script source, memory and help text.
  Header: `tk-fqw7x2b — Saying go on a recommendation should just work`. Body opens: When you accept a recommendation in a sitting, the agent has no defined way to carry it out, so it improvises.
- **old 2.** Message opens: **What happened.** When you said go on a recommendation in a sitting on 10-13, the agent took 18 tool calls and nearly ten minutes to carry it out.
  Header: `tk-fqw7x2b — Saying go on a recommendation should be one known step`. Body opens: Saying go on a recommendation in a sitting has no defined procedure, so agents hunt through source to work it out, and a partial attempt has already left a risk of dispatching the same work twice.
- **old 3.** Message opens: **What happened.** When you said go in a sitting on 10-13, the agent took 18 tool calls and nearly ten minutes to carry it out, and its first six calls were spent reading script source, memory and help text.
  Header: `tk-fqw7x2b — Saying go on a recommendation should just work`. Body opens: When you accept a recommendation in a sitting, the agent has no defined step for it, so it hunts for documentation and can do the job only partly.
- **new 1.** Message opens: This is your capture about an agent that "had no idea how to do a clear act that should have pre-defined steps" and went hunting for documentation.
  Header: `tk-fqw7x2b — agent had no skill for a clear act and went hunting for docs`. Body opens: This is your own ask, with no PR yet, and it's here because the fix needs your go.
- **new 2.** Message opens: You asked for agents to have a skill for a clear act instead of hunting for documentation.
  Header: `tk-fqw7x2b — Agents hunting for docs instead of having a skill to use`. Body opens: This is your ask, with no PR yet, and it needs your go before any work starts.
- **new 3.** Message opens: This is your capture about an agent that didn't know how to do a clear, routine act and went hunting for documentation.
  Header: `tk-fqw7x2b — agents should know the step, not hunt for docs`. Body opens: This is your own ask, with no PR yet, and it's here because the fix needs your go.
