---
name: converse-stay
description: Converse's stay, which keeps a sitting until the work it sent returns, its turns while that work is out, and its return to the operator with what landed.
---

# Stay until the work returns

Each call starts a fresh shell, so set `CONV`, `CONVERSATION` and `SUBJECT`
literally, from the entry's output, at the top of every call below.

## Stay

Stay only once the operator has agreed to it. First run the end up to its
sign-off (`converse-settle`): record the outcome, send the work, reply to the
gates the ruling settles and name what each answer releases, and settle the
subject's dispatch path. Then run the sign-off with `--stay`, giving in one
line what the operator agreed. The return compares the work with that line.

The sign-off with `--stay` writes in this order:

1. It appends `staying: <what was agreed>` to the conversation's notes, so a
   restart anywhere in the call finds the stay.
2. It writes everything an ending sign-off writes: the subject's headline and
   wait, the close brief and the validating closer's arm where it arms one,
   and the gate answers. So the subject's record stands even if this sitting
   never comes back.
3. In place of the close, it appends
   `staying: <what was agreed> (waits on <the work>)`, makes the conversation
   wait on that work, and leaves the conversation open under this sitting.

Write the headline as what the conversation waits for. Give `--close-brief`
only when the sign-off arms the subject's validating closer, as
`converse-settle` says: leave it out for a subject it arms no closer for, such
as an epic or the anchor of a PR, where it refuses the brief and names the
case. When the call exits non-zero, it stopped short, and you have not stayed:

```bash
if "$CONV/converse-signoff.sh" --conversation "$CONVERSATION" \
     --outcome "staying — <what this conversation waits for, at most 140 characters>" \
     --ruled yes --ruling "<the ruling, one line>" --waiting-on <the work> \
     --close-brief "<what that work's landing settles here, and what to check once it has>" \
     --stay "<what the operator agreed, which the return compares the work with, one line>"
     # no --close-brief for a subject the sign-off arms no closer for, such as an epic or a PR's anchor
     # --rework --no-wait in place of --waiting-on and --close-brief when the work is the PR's rework, and the other flags as converse-settle's sign-off takes them
then
  "$CONV/converse-entry.sh"  # staying: waiting while the work is out, returned once it has closed
else
  # NOT staying: repair what it printed and re-run, or sign off without --stay to end at the hand-off.
  exit 1
fi
```

**A member of the subject**, such as the member an epic's ruling files under
the epic, goes in `--waiting-on` like any other work, though an ending sign-off
gives it none (`converse-settle`). bd refuses the subject's edge onto its own
member, so the sign-off makes the member the conversation's wait alone: the
subject's headline leaves it out, and says `--no-wait` when nothing else is
left, and no closer is armed on it.

The sign-off refuses three stays, each before any write:

- **A stay on work in another store** than the conversation's, where the wait
  would hold nothing.
- **A stay on the subject itself**, as when the ruling sends the subject or
  takes its recommendation, because the conversation tracks the subject and bd
  keeps one edge from a bead onto another.
- **A stay for the landing of the PR whose merge this conversation holds**, or
  for work that waits on that PR, directly or through other beads.

After either of the first two refusals, end at the hand-off
(`converse-settle`), and tell the operator why the sitting does not stay. After
the third, lift the hold (`converse-hold`) and run the stay again when the
operator wants that PR to land first, and otherwise end at the hand-off.

The block runs the entry as soon as the stay lands, because the work can close
before the conversation waits on it, as on a re-run, and then no close is left
to bring the sitting back. Act on what the entry prints:

- **`returned`**: carry out the return (below) in place of a hand-back.
- **`waiting`**: record and post the hand-back. It opens with where the subject
  stands, and says that the sitting stays until the work lands and then comes
  back to compare it with what was agreed. Below the hand-back, offer the
  close-out line a framing offers (`converse-hold`), because a sitting that
  stays ends the same way.

A stay closes nothing, so it drains nothing: end the turn without
`gc runtime drain-ack`. Gas City stops the session once no tab is attached,
and wakes it with its thread when the work closes. When the work closes while
the session is still up, Gas City keeps the session up for the ready
conversation and sends it a notice that a blocker closed, on which the prompt
runs the entry. On an open PR, the merge this conversation holds waits for the
return too. When the operator wants the PR to land without the return, lift
that hold (`converse-hold`).

## While the work is out

The entry says `waiting` when an attach, a restart or a notice brought the
sitting back before all its work closed. Nothing needs registering again: the
conversation's edge onto the work is still the wait, and Gas City sleeps and
brings back the session as it does after the stay (above). Take the case that
fits:

- **The operator speaks.** Answer their turns as `converse-continue` says,
  through the sign-off's `--answer`. Do not hold: a hold keeps its
  conversation claimed, and this conversation stays open while its work is
  out.
- **Nobody speaks.** End the turn with nothing said and nothing recorded. A
  hand-back nobody asked for would replace the stay's hand-back, which the tab
  prints.
- **The operator rules that more work is needed.** Stay again, with a
  `--waiting-on` for every bead the conversation now waits on, the earlier work
  and the new, so the return waits for the last of them.
- **The operator ends the stay.** Sign off without `--stay`
  (`converse-settle`), which closes the conversation over its wait.

## A stay that stopped short

The entry says `interrupted` and names this skill when a stay stopped short:
before its sign-off finished, before the conversation waited on all its work,
or before the sign-off left the conversation to wait. The recovery is the
stay's call, run again with the same ruling, but only when you can give the
whole call. Take the case that fits:

- **Your thread holds the call.** Run it again with the same ruling, and act on
  the entry it runs, as after any stay.
- **Your thread no longer holds the call, and the record gives all of it.**
  Rebuild the call from the record, then run it again:
  - `AGREED` is its `--stay`.
  - The conversation's comments record its ruling and what the call already
    did.
  - The subject's latest close brief is its `--close-brief` when the brief's
    heading holds it on work that `WORK` names. When no brief is held on that
    work, the stay gave none, because the sign-off armed the subject no
    closer.
  - `WORK`, which the entry prints once the sign-off has finished, names its
    work for `--waiting-on`. A bead in `WORK` whose `source_ruling_bead` is
    this conversation is the ruling's rework, so the call takes `--rework` for
    it, in the rework form the stay example's comment gives.
- **The record does not give the whole call**, as when `WORK` is empty. Hold
  instead (`converse-hold`, after the claim-back below), and tell the operator
  that the stay stopped short and what it had done.

A re-run with the same ruling never files a second rework. What it does
depends on the rework the stopped stay left:

- **The ruling's record names the rework it filed.** The re-run files no
  second one, even after that rework has closed, and the entry then reads
  `returned`.
- **A rework of this ruling is open, and no record names it yet.** The re-run
  adopts that rework and records it.
- **The stay stopped after its rework was filed and before the record named
  it, and that rework has since closed.** The sign-off cannot tell that rework
  from an earlier ruling's, so the call refuses before any write, saying it
  found a closed rework that no recorded ruling names. Run nothing again: hold
  instead (`converse-hold`, after the claim-back below), and tell the operator
  which rework closed, because the ruling may already be carried out.

Before either hold, claim the conversation back. A hold keeps its conversation
claimed, but a second stay that stopped short leaves the conversation open,
waiting on the first stay's work, and a hold recorded on that open conversation
would read as a fresh sitting once that work closes. Run the claim-back, and
record the hold only once it prints its line:

```bash
gc bd update "$CONVERSATION" --if-assignee "$GC_ALIAS" --if-status open --status in_progress >/dev/null 2>&1; RC=$?
if [ "$RC" -eq 0 ] || { [ "$RC" -eq 13 ] && gc bd show "$CONVERSATION" --json 2>/dev/null \
     | jq -e --arg a "$GC_ALIAS" '.[0] | .status == "in_progress" and .assignee == $a' >/dev/null 2>&1; }; then
  echo "conversation $CONVERSATION is claimed, so its hold stands once that work closes"
fi
```

The guarded write exits 13 when the conversation does not read open under this
sitting, and the read after it then accepts a conversation this sitting
already holds. When no line prints, the conversation is not claimed: the store
refused the write, or the conversation moved, as when a dismiss closed it.
Record no hold until the line prints, and say in the thread what stopped it.

## The return

The entry says `returned` once the work closes, and prints `WORK` and
`AGREED`. The return reports to the operator. It works on nothing, takes no
check's send-back, and passes and fails nothing, because the return is not one
of the work's checks. The subject closes as it would after a hand-off, such as
through the validating closer the stay armed.

Start where the return stands:

- **Your thread shows a return already under way**, as after a restart. Carry
  it on from where it stopped, so nothing is posted twice.
- **The conversation's notes carry a return hand-over** from an earlier
  session (below). Start from the newest one: it says what was already
  compared and posted, and what remains. Finish the comparison and report it.
- **Otherwise**, start at step 1.

1. **Read what landed.** `gc bd show <each WORK bead>` gives how each bead
   closed and its PR. Read the change at the depth the comparison needs.
2. **Compare it with what was agreed.** Your thread holds the discussion, and
   `AGREED` is its one-line summary. The subject's notes and the resolve
   reasons of the gates the conversation answered hold the rest.
3. **Tell the operator where it matches and where it departs**, in plain words,
   on the work's PR and in a hand-back. Post on the PR through `pr-post.sh`, as
   the `prs` skill gives the call. A departure is something the operator needs
   to know, never a verdict. A departure they want changed is new work
   (`converse-settle`, Send the work).
4. **Then sign off, or hold.** Sign off with the stay's call less `--stay`,
   with `--no-wait` in place of its waits and brief, and with `--no-rework` in
   place of a `--rework`, whose child has landed. Leave out the `--pr-anchor`
   that named the PR the rework went to: the sign-off takes one only beside
   `--rework` or `--retire`, and `--no-rework` leaves every PR the ruling
   reaches standing. The return's `--outcome` says what landed, in place of the
   stay's `staying —` headline, which would otherwise stay on the subject. This
   sign-off answers nothing the stay already answered, and leaves the subject's
   closer as the stay armed it. When the comparison leaves the operator
   anything to answer before the sitting ends, hold instead (`converse-hold`):
   the hold's record tells a restart that the return is done.

### When your context runs low during the return

Running out of context changes which session finishes the comparison, never
whether it is done. Never sign off, hold, or tell the operator that the
comparison is done because your context ran low, and leave the conversation
open with its waits as they are.

- **Compact and go on.** Claude Code and Codex compact a thread on their own as
  it nears its limit, and the session keeps its conversation through the
  compaction. After a compaction, run the entry again, which prints `AGREED`
  and `WORK`, and carry the return on from where your summary and what you
  already posted show it stopped.
- **Hand the return to a fresh session** when compaction cannot carry it, or
  when Gas City's context notice asks you to reset this session. Never reset
  during a return without this hand-over.

To hand the return over, first append the hand-over to the conversation's
notes. No line of it may start with `holding:` or `staying:`, because the
entry reads those lines as the conversation's state:

```bash
gc bd update "$CONVERSATION" --append-notes "## Return hand-over ($(date -u +%Y-%m-%dT%H:%M:%SZ))
Agreed: <what the operator agreed, and where it is recorded: AGREED, the subject's notes, the gates' resolve reasons, and what was said only in this thread>
Returned work: <each WORK bead, its PR, and the exact revision to examine>
Compared so far: <each match or departure found, with its evidence, and what was already posted on the PR or to the operator>
Remaining: <each question and check still to make>
Conversation: $CONVERSATION about $SUBJECT, waiting on <the WORK beads>" \
  && echo "the hand-over is recorded on $CONVERSATION"
```

No closing line means the store refused the write: reset nothing, and say in
the thread that the hand-over did not land. Once the line prints, record and
post a hand-back that says the comparison is not finished, and that the next
session on this conversation finishes it from the hand-over and reports it.
Then ask Gas City to restart this session with a fresh context, and end the
turn:

```bash
gc session reset "$GC_SESSION_ID"
```

When the reset exits non-zero, nothing was restarted: say so in the thread,
and carry the return on in this session, which compacts as it fills. Otherwise,
the session that takes the conversation up next reads `returned` from the
entry and starts from the hand-over. When no session has taken the
conversation up again, the operator brings one back by engaging the
conversation, and the hand-back has told them that the comparison is still
owed.
