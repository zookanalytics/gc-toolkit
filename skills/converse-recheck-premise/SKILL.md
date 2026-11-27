---
name: converse-recheck-premise
description: Converse's premise re-check, and the close of a conversation whose premise died or needs no person, with nothing posted.
---

# Re-check the premise

Each call starts a fresh shell, so set `CONV`, `CONVERSATION` and `SUBJECT`
literally, from the entry's output, at the top of every call below.

The condition that justified a conversation, or a gate it replies to, often
dies before the operator engages the conversation. Test that condition against
live state before you prepare, so a conversation that closes here has not
moved the operator's session title or posted on the subject's PR.

The premise is the conversation's ask, which is its description, together with
the title and description of each gate it replies to, the entry's `GATES`:

```bash
gc bd show "$CONVERSATION"
gc bd show <each gate GATES names>
```

The conditions they state are the premise, often bulleted literally, such as
*"no `triage.hold` on the root"*. Check that each condition still holds, on the
subject and on whatever bead the condition is about:

```bash
gc bd show "$SUBJECT" --json | jq -r '.[0] | "hold=\(.metadata["triage.hold"] // "")\n\(.notes // "")"'
```

A non-empty `triage.hold` is a live hold, and an empty one is cleared. A
headline in the notes, under a `## Takeaway` heading, dates the sitting that
wrote it rather than naming a live wait: read it, then check whether the wait
it names is still open.

Two readings end the question with nothing posted:

- **moot**: the premise no longer holds. The frontier was routed, the bead
  closed, or another answer settled it.
- **benign**: the premise holds but needs no person. A non-empty
  `triage.hold` or another open human gate already names the wait, or the
  condition is a known acceptable state. An open PR awaiting the operator's
  review is the canonical case when the PR is incidental to the ask, whose
  condition, such as a stall or a missing stamp, comes down to the PR's wait:
  the PR is in their own review queue, and handing it back to them is the
  mistake this check prevents. The ask is the PR itself when the operator
  asked about the PR, or picked the PR or its anchor to talk over, which
  files an ask that has you prepare and hold for them. The PR's wait is then
  what they came about, so the premise holds and needs them. A headline alone
  is never a benign wait, because nothing clears it: re-check the ids it names
  (`gc bd show`, and `gc bd list --parent "$SUBJECT" --all`), and it is moot
  only if something is open again.

Either reading names the stamp or the state it rests on. When you cannot name
one, hold the sitting: uncertain is not benign.

Clear each gate the reading answers, with the reading as the gate's answer, and
read the gate back. A gate another answer already closed keeps that answer,
and a gate assigned to a person is that person's to clear:

```bash
gc bd gate resolve <gate> --reason "<moot|benign>: <the premise, and what is true instead>" \
  && gc bd show <gate> --json | jq -r '.[0] | "\(.status) \(.close_reason // "")"'
```

When the conversation's own ask has died too, close the conversation with its
record:

- The reading goes on the subject's notes.
- The conversation closes with the reading as its reason.
- The close is recorded among the visit's actions, which the comment on the
  subject's PR then shows, so write that action as one plain sentence that
  names no other rig or its beads.
- The close writes no headline, because a headline for a conversation that
  needs nobody spends the attention the close saves.

Each write takes its exit, and the conversation closes only after them:

```bash
KIND="<moot|benign>"; WHY="<the premise, and what is true instead>"
ACTION="<what ended the visit, in one plain sentence>"
gc bd update "$SUBJECT" --append-notes "$KIND (conversation $CONVERSATION): $WHY" \
  && gc bd update "$CONVERSATION" --set-metadata gc.work_outcome=no-op \
  && { gc bd close "$CONVERSATION" --reason "${KIND}: ${WHY}" \
       || gc bd close "$CONVERSATION" --reason "${KIND}: ${WHY}" --force; } \
  && { gc bd comment "$CONVERSATION" "$ACTION" >/dev/null \
       || echo "the close was not recorded among the actions of $CONVERSATION"; } \
  && { "$CONV/pr-sitting-comment.sh" refresh --sitting "$CONVERSATION" || true; } \
  && echo "closed $CONVERSATION as $KIND"
```

Then take the case that matches what the block printed:

- **It printed its `closed` line.** Drain (the prompt's How a sitting ends),
  and post nothing, not even "this turned out to be fine".
- **It printed no `closed` line.** The close stopped short, and the
  conversation stays open under this sitting, still holding an open PR's
  merge. Say in the thread what the block printed, fix what it names, and run
  the block again: the gates cleared above stay cleared, and each write is
  safe to repeat.

When the premise holds and needs a person, the conversation earns a sitting:
prepare it (`converse-prep`). A gate this check cleared stays cleared.
