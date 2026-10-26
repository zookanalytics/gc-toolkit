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
resolved at once, so a dismiss that ends the sitting later leaves nothing the
operator ruled on open:
```bash
gc bd gate resolve <gate> --reason "ruled: <the operator's ruling, one line>" \
  && gc bd show <gate> --json | jq -r '.[0] | "\(.status) \(.close_reason // "")"'
```
A close reason other than yours is an answer that reached the gate first, and
it stands: tell the operator. The sign-off reads a gate you answered here as
already cleared and leaves it. Record what each turn settles as step 6 says,
and sign off (step 7) once nothing important is pending.

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
