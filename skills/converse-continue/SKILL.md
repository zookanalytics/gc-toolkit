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
operator ruled on open. Answer it through the sign-off's writer with
`--answer`, never with a bare `gc bd gate resolve`. A gate can be what holds a
merge, so the writer puts the ruling's consequences in place before it
resolves the gate. When the ruling reaches an open PR, the subject or one the
gate releases, the first of them is the rework or the retirement the ruling
calls for, passed the way step 7 passes it, and the next is the subject's
headline with each wait this turn routed. A ruling that takes the subject's
recommendation names the recommendation's gate with `--answer` and adds
`--accept`, so Accept's writer answers that gate and sends the formula, as at
the sign-off (step 7). A subject that reads held is released by that writer
before it sends the formula. The `--answer` call resolves only the gates it
names, leaves the conversation open, and exits non-zero when it stopped short.
Until it exits 0, do not tell the operator the ruling is in place:
```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate> \
  --ruling "<the operator's ruling, one line>" \
  --outcome "<where the subject stands now, at most 140 characters>"
  # when the ruling reaches an open PR, add --rework, --no-rework or --retire <kind> (step 7)
  # when it takes the subject's recommendation, --answer its gate and add --accept (step 7)
  # --waiting-on <bead> for each bead this turn routed work into, or --no-wait
```
An answer that reached the gate first stands, and the writer prints it: tell
the operator. It also prints a line for each open PR the ruling leaves standing
whose merge still needs, or may still need, the operator's Approve review on
GitHub. Tell them what the line says, with the link, after whatever the ruling
leaves holding the PR, so it reads as what the merge needs rather than a request
to approve now. The sign-off reads a gate you answered here as already cleared
and leaves it. Record what each turn settles as step 6 says, and sign off
(step 7) once nothing important is pending.

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
this session itself, and a tab showing the sitting exits when the session
ends, printing the last hand-back recorded on the conversation. A new concern
the operator raises is a new conversation. Open it on its bead, where it waits
in the operator's queue until they engage it:
`"$CONV/gc-helm.sh" open <bead> --reason "<what it is about>" --body "<the ask>"`.
The one sitting that drains with its conversation still open is the
low-context path in the prompt's Rules, once its sign-off has handed the
conversation back to the queue.
