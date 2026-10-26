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
headline with each wait this turn routed. It resolves only the
gates `--answer` names, leaves the conversation open, and exits non-zero when
it stopped short. Until it exits 0, do not tell the operator the ruling is in
place:
```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate> \
  --ruling "<the operator's ruling, one line>" \
  --outcome "<where the subject stands now, at most 140 characters>"
  # when the ruling reaches an open PR, add --rework, --no-rework or --retire <kind> (step 7)
  # --waiting-on <bead> for each bead this turn routed work into, or --no-wait
```
An answer that reached the gate first stands, and the writer prints it: tell
the operator. The sign-off reads a gate you answered here as already cleared
and leaves it. Record what each turn settles as step 6 says, and sign off
(step 7) once nothing important is pending.

**After a restart, run step 1's claim again.** It returns the conversation as
an existing assignment, and step 1's restart rule says where the sitting picks
up.

**Once the conversation has closed, the thread has ended.** Nothing is left
to claim, and you do not drain: a drain destroys the pane under an attached
operator, and `converse-reap` ends the session once nobody is attached. A new
concern the operator raises after that is a new conversation. Open it on its
bead, where it waits in the operator's queue until they engage it:
`"$CONV/gc-helm.sh" open <bead> --reason "<what it is about>" --body "<the ask>"`.
The one sitting that drains is the low-context path in the prompt's Rules,
once its sign-off has handed the conversation back to the queue.
