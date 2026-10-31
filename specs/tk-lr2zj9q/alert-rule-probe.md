---
name: A/B probe of the time-based-alert wording in rule tk-b80kkz
description: Read it to check the numbers in tk-lr2zj9q's summary, to see which kind of stall remedy the wording moves, or to re-run the probe on a later wording.
---

# A/B probe of the time-based-alert wording

The proposal clears Gate 3 on a reading: an entry read when an agent proposes
the remedy names the timer as a non-fix, and the entry's existing clause gives
the action. Reading well proves nothing about that, so this measures what an
agent recommends with the old text and with the new.

The new text changes the call when the remedy is a new alert. It does not
change the call when the remedy is a repair to an alert that already exists.

| Case | What the remedy is | Old text | New text |
|---|---|---|---|
| D, a stall with no alert yet | Add an alert | 3 of 3 recommend an age alarm | 0 of 3 do; 3 of 3 recommend recording the hand-off so the lane restarts itself |
| A, sitting tk-ab9p1pk | Repair an alert's mute | 3 of 3 repair the mute | 3 of 3 repair the mute |
| B, sitting tk-0c9csp8 | Replace an alarm's clock | 3 of 3 land the fix, then replace the clock | 3 of 3 the same |
| C, control: a bounded lock wait | Not an alert | 3 of 3 merge and name the cause | 2 of 3 the same; 1 of 3 asks to fix the holder in the same PR |

## Method

Each arm's system prompt held the same short role line, the operator-profile
entry on one-minute decisions, and the whole "Standards for what you produce"
section of `template-fragments/work-quality-base.template.md`, without its
closing template marker. The old arm's copy came from `HEAD~1` of the rule's
commit and the new arm's from that commit. The third arm, the variant, is the
new arm with one clause added to the list, in the words of the pattern's Gate 2
sentence: "a change to such an alert's threshold or mute,". The variant is not
in the fragment.

The user message was the same in every arm for a given case. It opened "Facts
you have established on this visit:", held the case's facts, and closed "Write
what you recommend to the operator and what each option costs."

- **Case A** is the plain statement of the report that sitting tk-ab9p1pk gave
  the operator at 2026-10-15T01:07Z, from "**There's no PR.**" up to its `---`
  line, above its recommendation. The sitting recommended "an alert that closed
  itself no longer mutes the next one". The operator answered "4 hours is
  arbitrary, so I think something else is wrong here within the architecture of
  gc-toolkit" and "time based alerts, generally stupid and gloss over bad
  architecture".
- **Case B** is what sitting tk-0c9csp8 gave the operator at
  2026-10-10T03:52Z, from "**Where the number came from.**" up to "**What the
  alarm should be.**", with one opening line saying the operator asked whether
  the 2-day window is arbitrary. The sitting recommended a follow-up "that times
  the city's own recorded state and sets the window from measured turnaround".
  The operator answered "I thought you were going to suggest completely removing
  the check and the fix to the check."
- **Case C** is written for this probe, as a control with no alert in it. Its
  300 seconds is `queue-priority.sh`'s default; the rest is made up:

  > A review finding on an open PR says a script that updates a shared priority
  > file takes a lock first and waits for it with no upper bound. A caller behind
  > a holder that hangs waits for as long as the holder does, and it holds its own
  > claim the whole time. In the two recorded cases the holder was running a slow
  > store write and finished within five minutes. The PR's author proposes that
  > the caller wait at most 300 seconds for the lock, then report the failure on
  > stderr and exit non-zero, so that its own caller runs it again on the next
  > pass. The change raises no alert and files nothing. Nothing else changes.

- **Case D** is written for this probe, as the case where no alert exists yet.
  Its episodes and numbers are the evidence in tk-zvu0bd6's description, with the
  4-hour alert taken out of the facts:

  > A worker hands finished work to the merge agent by assigning the work to that
  > agent's role. Nothing else records the hand-off, and no session claims it.
  > Between Oct 7 and Oct 14 the merge lane stalled in four episodes: the merge
  > agent's session sat idle twice, a refused start froze its whole queue for
  > about 13 hours once, and a backlog outran the single merge agent once.
  > Handed-off work sat untouched each time, until someone noticed on the board.
  > No item stalled on its own: every episode hit the whole lane. Over 420
  > handoffs, time to the merge agent's first action had a median of 5 minutes, a
  > 75th percentile of 16 minutes and a 90th percentile of 132 minutes. Nothing
  > tells anyone today when handed-off work sits.

Each run was one call from an empty directory, with the case on stdin and no
tools:

`claude -p --model claude-opus-5-5 --tools "" --max-turns 1 --no-session-persistence --output-format json --system-prompt "<arm>"`

The old and new arms ran three times on each of the four cases. The variant ran
three times on cases A, B and C. That is 33 calls, for $1.71 in all. I read every
output. A run's recommendation below is the option it labels as recommended.

## Results

### Case D: a stall with no alert yet

Every old run picks a time limit, and each picks a different one. No new run
recommends an alert as the remedy.

- **old 1.** "approve option B now and open option C as follow-up work". B
  "Alerts someone when the oldest untouched handoff passes a time limit", and
  the run proposes 60 minutes.
- **old 2.** "Choose option B", where "You are alerted when the oldest untouched
  hand-off passes an age limit", starting at 2 hours.
- **old 3.** "Add one alarm for the whole lane. It fires when the oldest
  handed-off work has had no action from the merge agent for 30 minutes".
- **new 1.** "A hand-off should create a durable record and something should
  keep the merge lane running until the queue is empty." It keeps one lane-level
  alert for a recovery that fails, and says that alert "doesn't replace fixing
  their causes".
- **new 2.** "Each handoff is recorded and claimed by a session. Waiting work
  with no live claim starts or restarts a merge session".
- **new 3.** "Each hand-off creates a durable record that a session must claim."
  It offers an alert only as an optional stopgap, and says "It would leave the
  missing claim in place".

The new runs head where sitting tk-ab9p1pk ended up, though new 1 advises against
claiming each item separately. There, tk-zvu0bd6 makes the merge agent a pool of
one that claims offered handoffs, and the operator took the recommendation to
start it with "yes as recommended".

### Case A: repairing an alert that exists

All nine runs recommend the repair the sitting recommended and the operator
turned down. No run asks whether the 4-hour alert should exist.

- **old 1.** "An alert that closes itself no longer mutes new alerts."
- **old 2.** "An alert that closes itself should not mute later alerts".
- **old 3.** "an alert closing itself no longer starts the 24-hour mute".
- **new 1.** "An alert that closes itself no longer starts the mute."
- **new 2.** "An alert that closes itself would no longer start the mute."
- **new 3.** "only start the mute when someone has actually handled the alert".
- **variant 1.** "A self-closed alert should no longer mute new alerts about the
  same work".
- **variant 2.** "A self-closed alert no longer starts the mute".
- **variant 3.** "Only a person's handling of an alert should be able to start
  the 24-hour mute."

The new text is visibly read. New 1 offers "a separate check for muted stuck
work" and advises against it because "the cause stays in place", and new 2 says
"Not offered: a sweep or timer that catches muted work." No old run raises such a
check at all. Both new runs still call the mute the cause. Variant 2 comes
closest to the operator's point: "You would still be relying on an alert after a
4-hour wait." The variant's words do not change the recommendation, so this
probe gives no reason to prefer them over the filed text.

### Case B: replacing an alarm's clock

All nine runs land the fix in review and replace the clock in a follow-up, and
none recommends a better number. All nine mention retiring the alarm, and none
recommends retiring it now. The arms show no difference. Every old run already
turns down a new number here, though the real sitting proposed a new window. The
cut takes out that sitting's own redesign paragraph, so this case is kinder to
the old text than the sitting was.

- **old 1.** "land #1150 once its wording rework passes, and replace the 2-day
  clock in a separate follow-up".
- **old 2.** "landing #1150 as soon as its wording rework passes, then replacing
  the clock in a follow-up".
- **old 3.** "land #1150 once the wording rework finishes, then replace the
  clock as separate work".
- **new 1.** "land #1150 once its wording rework passes, and open a follow-up to
  replace the clock".
- **new 2.** "land #1150 once its wording rework passes, and replace the 2-day
  clock in a follow-up".
- **new 3.** "land #1150 once its wording rework passes, then replace the 2-day
  alarm with state-based checks in a follow-up".
- **variant 1.** "land #1150 once its wording rework passes, keep the 2-day
  number for now, and open a follow-up to replace the clock".
- **variant 2.** "landing #1150 without changing the number, then replacing the
  clock in a follow-up".
- **variant 3.** "land #1150 as soon as its wording rework is done, then replace
  the 2-day clock with alarms on named PR states".

### Case C: a bounded lock wait

This control asks whether "a timer" makes a reader treat a plain bound as a
non-fix. The old text already asks for it to name its cause, through "a sweep or
a guard must still ship", so the new wording has little left to add. One new run
of three goes further than any old run.

- **old 1.** "merge the 300-second limit, on condition that the PR names what it
  leaves unfixed and a follow-up bead is filed".
- **old 2.** "accept the 300-second limit, on condition that the PR states what
  it leaves unfixed and a follow-up is filed".
- **old 3.** "merge the 300-second limit, and file a separate follow-up", with "a
  PR note naming the unbounded holder as the remaining cause".
- **new 1.** "Merge the 300-second limit, require the PR to name the cause it
  leaves in place, and file a follow-up".
- **new 2.** "Merge the bound, but have the PR name the cause it leaves in place,
  and file a follow-up".
- **new 3.** "don't merge this PR as the fix. Ask the author to also fix the
  holder", with merging the cap and a follow-up as its fallback.
- **variant 1.** "approve the 300-second limit, on the condition that the PR names
  the cause it leaves in place and a follow-up bead is filed".
- **variant 2.** "Merge the 300-second limit, but require the PR to name the cause
  it leaves in place, and file a follow-up".
- **variant 3.** "accept the 300-second limit, on the condition that the PR names
  the cause it leaves in place and a follow-up bead tracks that cause".

## What it cannot show

This is a cut-down prompt with no skills or tools, and three runs per cell, so
it shows a direction. A real sitting reads far more prompt beside this entry,
which can dilute the effect that case D shows. Cases A and B hand the agent facts
a sitting had already framed, and case A's framing calls the mute "the bug",
which is the framing the operator turned down. Cases C and D are written for the
probe. Case D's last sentence, that nothing tells anyone today, is the
counterfactual that makes it a new-alert case. The live system has the 4-hour
alert.
