---
name: converse-stay
description: Converse's stay, which keeps a sitting until the work it sent returns, its turns while that work is out, and its return to the operator with what landed.
---

# Stay until the work returns

Each call starts a fresh shell, so set `CONV`, `CONVERSATION` and `SUBJECT`
literally, from the entry's output, at the top of every call below.

## Stay

Stay once the operator has agreed to it. First run the end up to its sign-off
(`converse-settle`): record the outcome, send the work, reply to the gates the
ruling settles and name what each answer releases, and settle the subject's
dispatch path. Then run the sign-off with `--stay`, giving in one line what the
operator agreed, which the return compares the work with.
The call first appends `staying: <what was agreed>` to the conversation's
notes, so a restart anywhere in it finds the stay. Then it writes everything the
ending sign-off writes: the subject's headline and wait, the close brief, the
validating closer's arm and the gate answers. So the record stands even if this
sitting never comes back. In place of the close, it appends
`staying: <what was agreed> (waits on <the work>)`, makes the conversation wait
on that work, and leaves the conversation open under this sitting. Write the
headline as what the conversation waits for. It exits non-zero when it stopped
short, and then you have not stayed:

```bash
if "$CONV/converse-signoff.sh" --conversation "$CONVERSATION" \
     --outcome "staying — <what this conversation waits for, at most 140 characters>" \
     --ruled yes --ruling "<the ruling, one line>" --waiting-on <the work> \
     --close-brief "<what that work's landing settles here, and what to check once it has>" \
     --stay "<what the operator agreed, which the return compares the work with, one line>"
     # --rework --no-wait in place of --waiting-on and --close-brief when the work is the PR's rework, and the other flags as converse-settle's sign-off takes them
then
  "$CONV/converse-entry.sh"  # staying: waiting while the work is out, returned once it has closed
else
  # NOT staying: repair what it printed and re-run, or sign off without --stay to end at the hand-off.
  exit 1
fi
```

The sign-off refuses a stay on work in another store than the conversation's,
where the wait would hold nothing. It refuses one on the subject itself, as when
the ruling sends the subject or takes its recommendation, because the
conversation tracks the subject and bd keeps one edge from a bead onto another.
Either sitting ends at the hand-off (`converse-settle`) and says why, as does
one whose context is too full to compare the work once it lands. It also refuses a stay for the landing of the
PR whose merge this conversation holds, and for work that waits on that PR,
itself or through other beads: when the operator wants that PR to land first,
lift the hold (`converse-hold`) and run the stay again, and otherwise end at
the hand-off.

A stay that lands runs the entry at once, as the block above does, because the
work can close before the conversation waits on it, as on a re-run, and then no
close is left to bring the sitting back. On `returned`, carry out the return
(below) in place of a hand-back. On `waiting`, record and post the hand-back.
It opens with where the subject stands, and says the sitting stays until the
work lands and comes back then to compare it with what was agreed. Below it,
offer the close-out line a framing offers (`converse-hold`), since a sitting
that stays ends the same way. A stay closes nothing, so it drains nothing: end
the turn without `gc runtime drain-ack`. Gas City stops the session once no tab
is attached, and wakes it with its thread when the work closes. When the work
closes while the session is still up, Gas City keeps it up for the ready
conversation and sends it a notice that a blocker closed, on which the prompt
runs the entry. On an open PR, the merge this conversation holds waits for the
return too, so lift that hold (`converse-hold`) when the operator wants the PR
to land without it.

## While the work is out

The entry says `waiting` when an attach, a restart or a notice brought the
sitting back before all its work closed. When the operator speaks, answer their
turns as `converse-continue` says, through the sign-off's `--answer`, and do
not hold: a hold keeps its conversation claimed, and this one is open while its
work is out.
When nobody speaks, end the turn with nothing said and nothing recorded: a
hand-back nobody asked for would replace the stay's, which the tab prints.
Nothing needs registering again: the conversation's edge onto the work is the
wait, and the session sleeps again once the tab detaches.

- **More work**: stay again, with a `--waiting-on` for every bead the
  conversation now waits on, the earlier work and the new, so the return waits
  for the last of them.
- **End the stay**: sign off without `--stay` (`converse-settle`), which closes
  the conversation over its wait.

The entry says `interrupted` and names this skill when a stay stopped short:
before its sign-off finished, before the conversation waited on all its work,
or before it left the conversation to wait. Run the call again with the same
ruling, which is safe, and go on from the entry it runs, as after any stay. The
sign-off records the rework it filed under the ruling, so the call files none
again, even once that rework has closed, and the entry then reads `returned`.
When your thread no longer holds that call, rebuild it from the record:
`AGREED` is its `--stay`, the conversation's comments record its ruling and
what it did, the subject's latest close brief is its `--close-brief`, and
`WORK`, once the sign-off finished, names its work, in which a bead whose
`source_ruling_bead` is this conversation is its `--rework`.
When the record does not give the whole call, as when `WORK` is empty, hold
instead (`converse-hold`), and tell the operator the stay stopped short and
what it had done.

The hold keeps its conversation claimed, and a second stay that stopped short
leaves the conversation open, waiting on the first stay's work. A hold
recorded there would read as a fresh sitting once that work closes. So claim
the conversation back first, and record the hold only once this prints its
line:

```bash
gc bd update "$CONVERSATION" --if-assignee "$GC_ALIAS" --if-status open --status in_progress >/dev/null 2>&1; RC=$?
if [ "$RC" -eq 0 ] || { [ "$RC" -eq 13 ] && gc bd show "$CONVERSATION" --json 2>/dev/null \
     | jq -e --arg a "$GC_ALIAS" '.[0] | .status == "in_progress" and .assignee == $a' >/dev/null 2>&1; }; then
  echo "conversation $CONVERSATION is claimed, so its hold stands once that work closes"
fi
```

Its guard misses, with exit 13, when the conversation does not read open under
this sitting, and the read then accepts one this sitting already holds. No line
means it is not claimed: the store refused the write, or the conversation
moved, as a dismiss closes it. Hold nothing until the line prints, and say in
the thread what stopped it.

## The return

The entry says `returned` once the work closes, with `WORK` and `AGREED`. The
return reports to the operator. It works on nothing, takes no check's
send-back, and passes and fails nothing, because it is not one of the work's
checks, and the subject closes as it would after a hand-off, such as through
the validating closer the stay armed.

When your thread shows a return already under way, as after a restart, carry
it on from where it stopped, so nothing is posted twice.

1. **Read what landed.** `gc bd show <each WORK bead>` gives how it closed and
   its PR. Read the change at the depth the comparison needs.
2. **Compare it with what was agreed.** Your thread holds the discussion.
   `AGREED` is its one-line summary, and the subject's notes and the resolve
   reasons of the gates the conversation answered hold the rest.
3. **Tell the operator where it matches and where it departs**, in plain words,
   on the work's PR and in a hand-back. Post on the PR through `pr-post.sh`, as
   the `prs` skill gives the call. A departure is what the operator needs to
   know, never a verdict. One they want changed is new work (`converse-settle`,
   Send the work).
4. **Then sign off, or hold.** Sign off with the stay's call less `--stay`,
   with `--no-wait` in place of its waits and brief, and with `--no-rework` in
   place of a `--rework`, whose child has landed. Its `--outcome` says what
   landed, in place of the stay's `staying —` headline, which would otherwise
   stay on the subject. It answers nothing the stay already answered, and
   leaves the subject's closer as the stay armed it. When the comparison
   leaves the operator anything to answer before the sitting ends, hold
   instead (`converse-hold`): the hold's record tells a restart that the
   return is done.

When your context is too full for the comparison, say so in a hand-back and
sign off the same way: the subject still closes as it would after a hand-off.
