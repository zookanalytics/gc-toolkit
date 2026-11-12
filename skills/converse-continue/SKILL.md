---
name: converse-continue
description: Converse's continuation of a sitting until its conversation closes, and the return of a sitting that stayed for the work it sent.
---

# Step 8 — Continue until the conversation closes

A sitting holds one conversation, and its thread ends when that conversation
closes: by your sign-off (step 7), by step 2's silent close, or by the
operator's dismiss. Each tool call starts a fresh shell, so set `CONV`,
`CONVERSATION` and `SUBJECT` literally, from what step 1 found, at the top of
every call below.

**While the conversation is open, every operator turn continues the
sitting.** Before you answer, re-read the conversation's replies (step 1's
read) and the subject's human gates (step 4's read): a gate filed on the
subject while the sitting runs shows up there, and so does one another answer
has already cleared. Answer a gate only once the operator rules on it,
replying to it first and naming what the answer releases (step 7). The
sign-off resolves it. A ruling given on a turn that does not sign off is
answered at once, so a dismiss that ends the sitting later leaves nothing the
operator ruled on open.

First settle the subject's dispatch path, its arm and its route, by step 7's
rule, which every answer to a gate on the subject follows. The hold kept both,
and the writer leaves them as they are, so once the gate is answered and
nothing else holds the subject, an arm sends it and a pool route has that pool
claim it. Read them:
```bash
ROW=$(gc bd show "$SUBJECT" --json) \
  && printf '%s\n' "$ROW" | jq -er --arg s "$SUBJECT" 'if type == "array" and length == 1 and .[0].id == $s then (.[0].metadata // {}) | "arm: \(.["gc.dispatch_when_ready"] // "none") \(.["gc.dispatch_when_ready_args"] // "") route: \(.["gc.routed_to"] // "none")" else error("unread") end'
```
When the ruling leaves the subject to go where its arm or route already sends
it, by the same method, keep them. Under any other ruling, one that sends it
elsewhere or nowhere, withdraw them before the answer, with or without
`--accept`. The block disarms an arm and clears a pool route, and keeps a
`human` route, which sends the subject to no pool. It prints its
`carries no arm and no pool route` line only once each write has exited 0:
```bash
WHY="<the ruling, one line>"
ROW=$(gc bd show "$SUBJECT" --json) \
  && ARM=$(printf '%s\n' "$ROW" | jq -er --arg s "$SUBJECT" 'if type == "array" and length == 1 and .[0].id == $s then (.[0].metadata["gc.dispatch_when_ready"] // "") | tostring else error("unread") end') \
  && ROUTE=$(printf '%s\n' "$ROW" | jq -er '(.[0].metadata["gc.routed_to"] // "") | tostring') \
  && { [ -z "$ARM" ] || "$CONV/deferred-dispatch.sh" disarm "$SUBJECT" --reason "$WHY"; } \
  && { [ -z "$ROUTE" ] || [ "$ROUTE" = human ] || gc bd update "$SUBJECT" --unset-metadata gc.routed_to; } \
  && echo "$SUBJECT carries no arm and no pool route"
```
Without that line, answer nothing: fix what the block printed and re-run it.
A ruling that sends the subject on is carried out once the answer below exits
0: send the subject then, as step 7's cases do.

Then answer the ruling through the sign-off's writer with `--answer`, never
with a bare `gc bd gate resolve`. A gate can be what holds a merge, so the
writer puts the ruling's consequences in place before it resolves the gate.
When the ruling reaches an open PR, the subject, the PR whose merge this
conversation holds or one the gate releases, the first of them is the rework or the retirement the ruling
calls for, passed the way step 7 passes it, and the next is the subject's
headline with each wait this turn routed. A ruling that takes the subject's
recommendation names the recommendation's gate with `--answer` and adds
`--accept`, so Accept's writer answers that gate and sends the formula, as at
the sign-off (step 7). The `--answer` call resolves only the gates it
names, leaves the conversation open, and exits non-zero when it stopped short.
Until it exits 0, do not tell the operator the ruling is in place:
```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate> \
  --ruling "<the operator's ruling, one line>" \
  --outcome "<where the subject stands now, at most 140 characters, or 95 when the ruling leaves an open PR standing>"
  # when the ruling reaches an open PR, add --rework, --no-rework or --retire <kind> (step 7)
  # when it takes the subject's recommendation, --answer its gate and add --accept (step 7)
  # --waiting-on <bead> for each bead this turn routed work into, or --no-wait
  # --close-brief "<what that work's landing settles here, and what to check once it has>" beside a --waiting-on on work (step 7)
```
An answer that reached the gate first stands, and the writer prints it: tell
the operator. It also prints a line for each open PR the ruling leaves standing
whose merge still waits on GitHub. Pass the line on, with its link, after
whatever else the ruling leaves holding the PR. The sign-off reads a gate you
answered here as already cleared and leaves it. Record what each turn settles
as step 6 says, and sign off (step 7) once nothing important is pending.

**After a restart, run step 1's claim again.** It returns the conversation as
an existing assignment, and step 1's restart rule says where the sitting picks
up.

## While a sitting stays

A sitting that stays keeps its conversation open, waiting on the work it sent,
and its agent sleeps until that work closes (step 7, **Staying for the
return**). The operator can still engage it before then: an attach wakes this
session with its thread, and step 1's claim answers `drain`, because the
conversation is not ready while it waits. Step 1 then reads the `staying:` line
and keeps the sitting. Answer the operator's turns as any turn above, through
the sign-off's writer. Nothing needs registering again, because the
conversation's edge onto the work is the wait, and the session sleeps again on
its own once the tab detaches. A ruling that sends more work while the sitting
stays runs step 7's stay call again with the new work as a `--waiting-on`. One
that ends the stay signs off (step 7) without `--stay`, which closes the
conversation over its wait.

## The return

When the work a sitting that stays waits on closes, Gas City wakes this
session with its thread, and step 1's claim returns the conversation as a
`ready_assignment` whose newest line is a `staying:` line. The return reports
to the operator. It works on nothing, takes no check's send-back, and passes
and fails nothing, because it is not one of the work's checks, and it checks
nothing on the subject, whose validating closer the stay armed.

1. **Read what landed.** `gc bd show <the work>` gives how it closed and its
   PR. Read the PR's diff or the change it made, at the depth the comparison
   needs. A work bead that still reads open means the stay was cut short
   before it left the conversation waiting, so this is no return: run the
   stay's call again (step 7), which finishes the stay, and end the turn.
2. **Compare it with what the operator agreed in this conversation.** The
   thread holds what they agreed. A session that came up without it reads the
   `staying:` line, the subject's notes and the resolve reasons of the gates
   the conversation answered.
3. **Tell the operator where it matches and where it departs**, in plain
   words, in two places. Post it on the work's PR as a comment through
   `pr-post.sh` (the prompt's Rules give the call). Then put it in a
   hand-back, recorded on the conversation and posted here. A departure is
   what the operator needs to know, and never a verdict on the work. One they
   want changed is new work, filed and sent as step 7 says.
4. **Then sign off, or hold.** Sign off (step 7) with the stay's call less
   `--stay`, with `--no-wait` in place of its waits and brief, and with
   `--no-rework` in place of a `--rework`, whose child has landed. It answers
   nothing the stay already answered and leaves the subject's closer as the
   stay armed it. When the comparison leaves the operator a decision, hold for
   it (step 5) as any sitting does.

A sitting whose context is too full for the comparison says so in a hand-back
and signs off as step 4 says: the subject's validating closer still checks
what the work's landing settles.

**Once the conversation has closed, the thread has ended, and so does this
session.** Whichever path closed it, once the close has landed and every write
that must follow it has run, drain, with nothing after it (the prompt's **How
this thread ends**):
```bash
gc runtime drain-ack
```
Nothing is left to claim, so never claim again. The operator's dismiss stops
this session itself. A tab showing the sitting holds the stop until it
detaches, with a title that leads with `done`, and then prints the last
hand-back recorded on the conversation. A new concern
the operator raises is a new conversation. Open it on its bead, where it waits
in the operator's queue until they engage it:
`"$CONV/gc-helm.sh" open <bead> --reason "<what it is about>" --body "<the ask>"`.
The one sitting that drains with its conversation still open is the
low-context path in the prompt's Rules, once its sign-off has handed the
conversation back to the queue. A sitting that stays keeps its conversation
open too, but it never drains: it ends its turn and sleeps.
