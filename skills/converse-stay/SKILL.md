---
name: converse-stay
description: Converse's stay, which keeps a sitting until the work it sent returns, its turns while that work is out, and its return to the operator with what landed.
---

# Stay until the work returns

Each call starts a fresh shell, so set `CONV`, `CONVERSATION` and `SUBJECT`
literally, from the entry's output, at the top of every call below.

## Stay

Stay once the operator has agreed to it. File and send the work first
(`converse-settle`, Send the work). Then run the sign-off with `--stay`, giving
in one line what the operator agreed, which the return compares the work with.
The call writes everything the ending sign-off writes: the subject's headline
and wait, the close brief, the validating closer's arm and the gate answers. So
the record stands even if this sitting never comes back. In place of the close,
it makes the conversation wait on the work, appends
`staying: <what was agreed> (waits on <the work>)` to the conversation's notes,
and leaves the conversation open under this sitting. Write the headline as
what the conversation waits for. It exits non-zero when it stopped short, and
then you have not stayed:

```bash
if "$CONV/converse-signoff.sh" --conversation "$CONVERSATION" \
     --outcome "staying — <what this conversation waits for, at most 140 characters>" \
     --ruled yes --ruling "<the ruling, one line>" --waiting-on <the work> \
     --close-brief "<what that work's landing settles here, and what to check once it has>" \
     --stay "<what the operator agreed, which the return compares the work with, one line>"
     # --rework --no-wait in place of --waiting-on and --close-brief when the work is the PR's rework, and the other flags as converse-settle's sign-off takes them
then
  : # staying — record the hand-back, post it, and end the turn with no drain
else
  # NOT staying: repair what it printed and re-run, or sign off without --stay to end at the hand-off.
  exit 1
fi
```

The sign-off refuses a stay on work in another rig's store, where the wait
would hold nothing, and on the landing of the PR whose merge this conversation
holds until you lift that hold (`converse-hold`). When it refuses, or your
context is too full to compare the work once it lands, end at the hand-off
instead (`converse-settle`) and say why.

Then record and post the hand-back. It opens with where the subject stands,
and says the sitting stays until the work lands and comes back then to compare
it with what was agreed. Below it, offer the close-out line a framing offers
(`converse-hold`), since a sitting that stays ends the same way. A stay closes
nothing, so it drains nothing: end the turn without `gc runtime drain-ack`.
Gas City stops the session once no tab is attached, and wakes it with its
thread when the work closes. On an open PR, the merge this conversation holds
waits for the return too, so lift that hold (`converse-hold`) when the operator
wants the PR to land without it.

## While the work is out

The entry says `waiting` when an attach or a restart woke the sitting before
the work closed. Answer the operator's turns as `converse-continue` says,
through the sign-off's `--answer`, and do not hold. Nothing needs registering
again: the conversation's edge onto the work is the wait, and the session
sleeps again once the tab detaches.

- **More work**: stay again, with a `--waiting-on` for every bead the
  conversation now waits on, the earlier work and the new, so the return waits
  for the last of them.
- **End the stay**: sign off without `--stay` (`converse-settle`), which closes
  the conversation over its wait.

The entry says `interrupted` and names this skill when the conversation is
still claimed while its work is out: the stay's call stopped before it left
the conversation to wait. Run the call again, which is safe, and end the turn.

## The return

The entry says `returned` once the work closes, with `WORK` and `AGREED`. The
return reports to the operator. It works on nothing, takes no check's
send-back, and passes and fails nothing, because it is not one of the work's
checks, and the validating closer the stay armed checks the subject.

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
   place of a `--rework`, whose child has landed. It answers nothing the stay
   already answered, and leaves the subject's closer as the stay armed it. When
   the comparison leaves the operator anything to answer before the sitting
   ends, hold instead (`converse-hold`): the hold's record tells a restart that
   the return is done.

When your context is too full for the comparison, say so in a hand-back and
sign off the same way: the validating closer still checks the subject.
