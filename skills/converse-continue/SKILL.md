---
name: converse-continue
description: Converse's continuation of a sitting until its conversation closes.
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
conversation back to the queue.
