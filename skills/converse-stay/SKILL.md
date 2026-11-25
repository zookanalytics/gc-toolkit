---
name: converse-stay
description: Converse's stay, which keeps a sitting until the one piece of work it stays for is back, its turns while that work is out, and its return to discuss the result with the operator before their next decision about it.
---

# Stay until the work is back

Each call starts a fresh shell, so set `CONV`, `CONVERSATION` and `SUBJECT`
literally, from the entry's output, at the top of every call below.

## When a stay comes back

A stay comes back for one piece of work, before the operator's next decision
about it, and it always comes back to discuss the result with them, whatever it
finds:

| The stay is for | It comes back |
|---|---|
| New work that opens its own PR | Once the city has finished with that PR and only the operator's part is left, which is after its review and its required checks have passed, or once the work closes. |
| A rework of the PR under discussion | Once the rework is done and the city has finished with the PR again. |
| The conversation's own subject | Once the city has finished with the subject's PR, or once the subject closes. |
| Work that opens no PR of its own | Once the work closes. |

Trouble on the work does not bring the sitting back: a required check that
failed, a review that ran out of attempts, a question filed on the work, or its
PR closed unmerged. Each reaches the operator as it does today, and the stay
waits on until the city has finished with the PR. Other work the ruling sends
brings no return of its own: it lands as work does today, or, on a PR the
conversation already holds, waits for the sitting's next return.

In the city's own store a stay comes back only once its work closes, which for
new work that opens its own PR is after the merge, and a stay on the
conversation's own subject is refused there, because the landing order does
not read that store (In the city's own store, below). So recommend ending at
the hand-off there for new work that opens its own PR, with what was agreed
written into the work's brief. This read prints `city` for a conversation in
the city's own store, and `rig` for one in a rig's:

```bash
"$CONV/rig-map.sh" | jq -er --arg p "${CONVERSATION%%-*}" '[ .rigs[]? | select(.prefix == $p) ] | if length != 1 then error("no one rig carries the prefix \($p)") elif .[0].hq then "city" else "rig" end'
```

## Stay

Stay only once the operator has agreed to it, after you have told them, in
their terms, which piece of work the stay is for, when it would come back
(above), that it comes back to discuss the result whatever it finds, and what
each other piece of work the ruling sends does instead (the prompt's End or
stay).

Write what was agreed as a list of items the return can check, each one a
thing the result either covers or does not, in the work's brief or, for a
send-back, in the order its ruling sends (`converse-settle`, Send the work).
The stay's `--stay` takes one line that sums those items up, which the entry
prints as `AGREED`.

First run the end up to its sign-off (`converse-settle`): record the outcome,
send the work, reply to the gates the ruling settles and name what each answer
releases, and settle the subject's dispatch path. The stay then takes one of
two forms:

- **The stay's own call sends the work.** A ruling that sends the PR under
  discussion back goes out through the call's `--rework`, and one that takes
  the subject's recommendation through its `--accept`. Once that send has
  landed, the call promises the work itself: the PR's bead, or the subject.
- **You send the work.** New work, the subject you sling, and another PR you
  send back through the `prs` skill are sent before the sign-off. Once the send
  is made, promise the work, and then stay. The stay's call finds the promise
  and keeps it.

The promise is the gate the stay waits on, whose type names the condition that
resolves it:

```bash
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
"$GCTK" gate create --type gctk:needs-review --await-id <the work's bead> --blocks "$CONVERSATION" \
  && echo "the stay comes back for <the work's bead>"
```

Exit 0 prints the gate's id, filed now or found open. Exit 4 is a read or a
write that did not land: run it again. Exit 2 writes nothing and says why:

- **The conversation already waits for another piece.** The stay waits for one
  piece at a time, so this work brings no return of its own. Tell the operator.
- **The work has closed.** There is nothing to wait for: tell the operator how
  it closed, and end or hold as they rule.
- **The work is in the city's own store.** The stay there waits on the work
  itself (below).
- **The work is in another store** than the conversation's, where a gate holds
  nothing. End at the hand-off.
- **The work cannot move until something the conversation holds has landed.**
  Tell the operator: it moves once they settle that, which lifts its hold
  (`converse-hold`), or the sitting ends at the hand-off.
- **The conversation is not held under this sitting's alias.** Run it from the
  sitting that holds the conversation.

Then run the stay's call, giving in one line what the operator agreed. When the
call exits non-zero, it stopped short, and you have not stayed:

```bash
if "$CONV/converse-signoff.sh" --conversation "$CONVERSATION" \
     --outcome "staying — <what this conversation waits for, at most 140 characters>" \
     --ruled yes --ruling "<the ruling, one line>" --waiting-on <the work> \
     --close-brief "<what that work's landing settles here, and what to check once it has>" \
     --stay "<what the operator agreed, which the return checks the work against, one line>"
     # no --close-brief for a subject the sign-off arms no closer for, such as an epic or a PR's anchor
     # --rework --no-wait in place of --waiting-on and --close-brief when the work is the PR's rework, and the other flags as converse-settle's sign-off takes them
     # --no-wait --accept in place of --waiting-on and --close-brief when the ruling takes the subject's recommendation
then
  "$CONV/converse-entry.sh"  # staying: waiting while the work is out, returned once it is back
else
  # NOT staying: repair what it printed and re-run, or sign off without --stay to end at the hand-off.
  exit 1
fi
```

`--waiting-on` is the subject's wait, as in a sign-off that ends: the work the
subject waits on, with its close brief where the sign-off arms the subject's
validating closer (`converse-settle`). Give `--close-brief` only there: leave
it out for a subject the sign-off arms no closer for, such as an epic or the
anchor of a PR, where it refuses the brief and names the case. A ruling that
sends the subject itself signs off with `--no-wait`. An epic's own member
takes no `--waiting-on` either, because bd refuses the epic's edge onto its
own member: sign off with `--no-wait`, or a `--waiting-on` for only the
dependencies you also sent, and promise the member. The conversation waits on
its gate alone.

The sign-off with `--stay` writes in this order:

1. It appends `staying: <what was agreed>` to the conversation's notes, so a
   restart anywhere in the call finds the stay.
2. It writes everything an ending sign-off writes: the ruling's send, the
   subject's headline and wait, the close brief and the validating closer's arm
   where it arms one, and the gate answers. So the subject's record stands even
   if this sitting never comes back.
3. In place of the close, it keeps the gate you promised, or promises the work
   its own call sent, then appends
   `staying: <what was agreed> (waits on <the gate>)`, and leaves the
   conversation open under this sitting.

It refuses three stays, each before any write:

- **A call that sends nothing**, neither `--rework` nor `--accept`, while the
  conversation waits on no open gate. Its message gives the promise's command.
  When a gate you promised has closed since, it says that the work is back
  instead: carry out the return (below) in place of the stay.
- **A stay whose piece is in another store** than the conversation's. End at
  the hand-off, and tell the operator why the sitting does not stay.
- **A conversation this sitting does not hold**, such as one back in the
  operator's queue, and a call from a session under another alias than the
  sitting's.

After its send has landed, the call stops short when the promise of what it
sent is refused, as for a PR that cannot move until something the conversation
holds has landed. What the ruling sends is sent, and each gate it answers is
answered. Say so to the operator. Once what the message names is settled, the
same call promises the work and stays.

For each piece the call sends that the stay does not come back for, it prints
that the piece brings no return of its own. Say so in the hand-back.

The block runs the entry as soon as the stay lands, because the work can be
back before the stay's last write, and then nothing is left to bring the
sitting back. Act on what the entry prints:

- **`returned`**: carry out the return (below) in place of a hand-back.
- **`waiting`**: record and post the hand-back. It opens with where the subject
  stands, and says when the sitting comes back, in the table's terms, to
  discuss the result against what was agreed. Below the hand-back, offer the
  close-out line a framing offers (`converse-hold`), because a sitting that
  stays ends the same way.

A stay closes nothing, so it drains nothing: end the turn without
`gc runtime drain-ack`. Gas City sleeps the session once no tab is attached,
and wakes it with its thread when the stay's gate closes. When the gate closes
while the session is still up, Gas City keeps the session up for the ready
conversation and sends it a notice that a blocker closed, on which the prompt
runs the entry. While the work is out, the merge of an open PR this
conversation holds waits for the return. Once the city has finished with the
PR the stay is for, the city holds that PR's merge for the return too, before
it wakes the sitting, so an approval merges nothing until the operator has
settled the work with the sitting. When the operator wants a held PR to land
without the return, lift that hold (`converse-hold`).

### In the city's own store

The landing order does not read the city's own store, so nothing there
resolves a gate, and the promise refuses. A stay there waits on the work
itself: the stay's call makes the conversation wait on each `--waiting-on`
bead that is no gate, and on the rework its `--rework` files, and the sitting
comes back once that work closes. So the call needs a `--waiting-on` for the
work, or `--rework`, which it refuses without.

**A member of the subject**, such as the member an epic's ruling files under
the epic, goes in `--waiting-on` like any other work there. bd refuses the
subject's edge onto its own member, so the sign-off makes the member the
conversation's wait alone: the subject's headline leaves it out, and says
`--no-wait` when nothing else is left, and no closer is armed on it.

The sign-off refuses three stays there, each before any write:

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

## While the work is out

The entry says `waiting` when an attach, a restart or a notice brought the
sitting back while the work is still out. Nothing needs registering again: the
conversation's gate is still the wait, or in the city's own store its edge onto
the work, and Gas City sleeps and brings back the session as it does after the
stay (above). Take the case that fits:

- **The operator speaks.** Answer their turns as `converse-continue` says,
  through the sign-off's `--answer`. Do not hold: a hold keeps its
  conversation claimed, and this conversation stays open while its work is
  out.
- **Nobody speaks.** End the turn with nothing said and nothing recorded. A
  hand-back nobody asked for would replace the stay's hand-back, which the tab
  prints.
- **The operator rules more for the piece the stay is for.** That is an ask on
  that piece, and its gate is open already, so the stay goes on, and comes back
  once the city has finished with the PR again. For the PR under discussion,
  run the stay's call again in its rework form, which files the ask and keeps
  the gate. The sign-off refuses a second rework while the conversation's
  first is open, and then the point waits for the return. For another PR, such
  as new work's, file the ask on its anchor as the `prs` skill's send-back
  gives, and run nothing else. Work that has no PR yet takes no ask: tell the
  operator the point waits for the return.
- **The operator rules other work.** Send it as `converse-settle` gives (Send
  the work), and promise nothing, because the stay waits for one piece at a
  time and the promise refuses a second. Tell the operator that this work
  brings no return of its own, and that work on a PR this conversation holds
  stays held until the sitting is back.
- **The operator ends the stay.** Sign off without `--stay`
  (`converse-settle`), which closes the conversation and releases what it
  holds. The stay's gate then resolves with nothing waiting on it.

## A stay that stopped short

The entry says `interrupted` and names this skill when a stay stopped short:
before its sign-off finished, before the sign-off left the conversation to
wait, or after you promised the work and before the stay's call ran. The
recovery is the stay's call, run again with the same ruling, but only when you
can give the whole call. Take the case that fits:

- **Your thread holds the call.** Run it again with the same ruling, and act on
  the entry it runs, as after any stay.
- **Your thread no longer holds the call, and the record gives all of it.**
  Rebuild the call from the record, then run it again:
  - `AGREED` is its `--stay`.
  - The conversation's comments record its ruling, after `Ruled:`, and what the
    call already did: a PR it sent back for rework, which makes the call's
    `--rework`, and a recommendation it took, which makes its `--accept`.
  - `WORK` names the work the stay comes back for. When the call sent neither
    a rework nor a recommendation, it is work you sent and promised.
  - The subject's latest close brief is its `--close-brief` when the brief's
    heading holds it on work that `WORK` names, and that work is then its
    `--waiting-on`. When no brief is held on that work, the stay gave none,
    because the sign-off armed the subject no closer.
- **The record does not give the whole call**, as when `WORK` is empty, or
  `AGREED` is, after you promised the work and before the stay's call recorded
  what was agreed. Hold instead (`converse-hold`, after the claim-back below),
  and tell the operator that the stay stopped short and what it had done.

A re-run with the same ruling never files a second rework. What it does
depends on the rework the stopped stay left:

- **The ruling's record names the rework it filed.** The re-run files no
  second one, even after that rework has closed.
- **A rework of this ruling is open, and no record names it yet.** The re-run
  adopts that rework and records it.
- **The stay stopped after its rework was filed and before the record named
  it, and that rework has since closed.** The sign-off cannot tell that rework
  from an earlier ruling's, so the call refuses before any write, saying it
  found a closed rework that no recorded ruling names. Run nothing again: hold
  instead (`converse-hold`, after the claim-back below), and tell the operator
  which rework closed, because the ruling may already be carried out.

Before either hold, claim the conversation back. A hold keeps its conversation
claimed, but a stay run again on a visit that stopped short leaves the
conversation open, waiting on its gate, and the hold's record is written only
to a conversation this sitting has claimed. Run the claim-back, and record the
hold only once it prints its line:

```bash
gc bd update "$CONVERSATION" --if-assignee "$GC_ALIAS" --if-status open --status in_progress >/dev/null 2>&1; RC=$?
if [ "$RC" -eq 0 ] || { [ "$RC" -eq 13 ] && gc bd show "$CONVERSATION" --json 2>/dev/null \
     | jq -e --arg a "$GC_ALIAS" '.[0] | .status == "in_progress" and .assignee == $a' >/dev/null 2>&1; }; then
  echo "conversation $CONVERSATION is claimed, so its hold stands once that work is back"
fi
```

The guarded write exits 13 when the conversation does not read open under this
sitting, and the read after it then accepts a conversation this sitting
already holds. When no line prints, the conversation is not claimed: the store
refused the write, or the conversation moved, as when a dismiss closed it.
Record no hold until the line prints, and say in the thread what stopped it.

## The return

The entry says `returned` once the work is back, and prints `WORK`, the work
the stay came back for, and `AGREED`. Its line says why the gate closed: the
work's PR read `needs-review` or `merging` in its own right at a head it names,
or the work closed. In the city's own store, it reads `returned` once the work
has closed.

The return discusses the result with the operator. It works on nothing, takes
no check's send-back, and passes and fails nothing, because the return is not
one of the work's checks. The subject closes as it would after a hand-off, such
as through the validating closer the stay armed. In a rig's store, the work's
PR, when it has one, is held until the operator settles it with you.

Start where the return stands:

- **Your thread shows a return already under way**, as after a restart. Carry
  it on from where it stopped, so nothing is posted twice.
- **The conversation's notes carry a return hand-over** from an earlier
  session (below). Start from the newest one: it says what was already
  compared and posted, and what remains. Finish the comparison and report it.
- **Otherwise**, start at step 1.

1. **Record what the operator owes, first**, as `converse-hold` gives (Record
   the hold). The entry has claimed the conversation, so the hold's record
   lands only while this sitting holds it. Its `holding:` line is what a
   restart reads from then on.
2. **Read the result.** Read the work's PR at the head the gate's close names
   and at the head it has now, with the review's account of each round since
   the head you last read
   (`"$CONV/converse-pr-conversation.sh" <the work's bead>`), and with the
   PR's status, read as `converse-hold` reads an open PR's (Post the framing),
   the work's bead as its anchor. The city can start a round after the gate
   closes, such as a repair after a failing check or a merge of the target.
   When the two heads differ, read what changed between them, and report on
   the head the PR has now only once its status shows that head's review and
   required checks have passed. When the work has closed,
   `gc bd show <the work's bead>` gives how it closed and its PR.
3. **Check it against what was agreed, item by item.** The items are the ones
   written in the work's brief or in the send-back's order, with your thread
   and `AGREED` beside them. The subject's notes and the resolve reasons of the
   gates the conversation answered hold the rest.
4. **Post a short summary with your recommendation**, on the work's PR through
   `pr-post.sh`, as the `prs` skill gives the call, and in a hand-back. Work
   with no PR takes the hand-back alone. The summary names what was discussed,
   lists each agreed item with whether the result covers it and how you
   checked, and closes with one of three lines, so the operator can tell at a
   glance which it is:
   - every item is covered, you see nothing left to discuss, and they can
     approve when they are comfortable, or raise anything else;
   - some items are covered, and it names each one that still needs their
     word, with the question;
   - the work departs from what was agreed in a way they have to rule on.

   The summary is advice in your own voice. It claims no more than you checked,
   and it is not one of the PR's checks. Below the hand-back, offer the
   close-out line a framing offers (`converse-hold`).
5. **Wait for the operator**, whichever line the summary closed with. The PR's
   merge stays held until they settle.

When the gate closed because the work closed, merged or with no PR, read how it
closed, check it as above unless the PR merged at a head you already discussed,
and wait for the operator, as on any return.

Then carry out what the operator rules:

- **They settle it, and the sitting ends.** Sign off with the stay's call less
  `--stay`, with `--no-wait` in place of its waits and brief, and with
  `--no-rework` in place of a `--rework`, whose ask has closed. Add
  `--no-rework` to a call that had none when the work has a PR, because the
  ruling reaches the PR this return holds and leaves its branch standing.
  Leave out the `--pr-anchor` that named the PR the rework went to: the
  sign-off takes one only beside `--rework` or `--retire`, and `--no-rework`
  leaves every PR the ruling reaches standing. Leave out each `--check` and
  `--rework-waiting-on` the `--rework` carried too, since the sign-off takes
  them only beside it. The return's `--outcome` says where the work stands
  now, such as a PR that waits for the operator's approval, in place of the
  stay's `staying —` headline, which would otherwise stay on the subject. This
  sign-off answers nothing the stay already answered, leaves the subject's
  closer as the stay armed it, and releases the PR's hold with the close.
- **They settle it, and the sitting stays for another piece.** Lift the hold
  on the PR they settled (`converse-hold`), then promise the next piece and
  stay (Stay, above). Nothing promises the settled work again, and nothing
  waits for it to land.
- **They send the work back.** That is a new stay, and the ask comes before
  the promise. For the PR under discussion, run the stay's call in its rework
  form, which files the ask and then promises the PR. For another PR, such as
  new work's, file the ask on its anchor as the `prs` skill's send-back gives,
  then promise the PR, then run the stay's call. The hold from this return
  stays on the PR, so an approval given earlier merges nothing.
- **They want something else changed.** That is new work or a send-back
  (`converse-settle`, Send the work), and the stay for it, when they want one,
  is a stay of its own.

### When your context runs low during the return

Running out of context changes which session finishes the comparison, never
whether it is done. Never sign off, hold, or tell the operator that the
comparison is done because your context ran low, and leave the conversation
open with its waits as they are.

- **Compact and go on.** Claude Code and Codex compact a thread on their own as
  it nears its limit, and the session keeps its conversation through the
  compaction. After a compaction, run the entry again. Before the return's
  hold it prints `AGREED` and `WORK`, and after it, it reads the hold as
  standing. Carry the return on from where your summary and what you already
  posted show it stopped.
- **Hand the return to a fresh session** when compaction cannot carry it, or
  when Gas City's context notice asks you to reset this session. Never reset
  during a return without this hand-over.

To hand the return over, first append the hand-over to the conversation's
notes. No line of it may start with `holding:` or `staying:`, because the
entry reads those lines as the conversation's state:

```bash
gc bd update "$CONVERSATION" --append-notes "## Return hand-over ($(date -u +%Y-%m-%dT%H:%M:%SZ))
Agreed: <each agreed item, and where it is recorded: the work's brief or the send-back's order, AGREED, the subject's notes, the gates' resolve reasons, and what was said only in this thread>
Returned work: <the WORK bead, its PR, the head the gate closed at, and the head to examine>
Compared so far: <each item compared, covered or not, with its evidence, and what was already posted on the PR or to the operator>
Remaining: <each item and check still to make>
Conversation: $CONVERSATION about $SUBJECT, back from <the gate or the work>" \
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
the session that takes the conversation up next reads the return's hold as
standing, and `converse-continue` sends it back here to start from the
hand-over. When no session has taken the conversation up again, the operator
brings one back by engaging the conversation, and the hand-back has told them
that the comparison is still owed.
