---
name: converse-recheck-premise
description: Converse's premise re-check, and the silent moot or benign close of a conversation and the gates it answers.
---

# Step 2 — Re-check the premise

The condition that justified a conversation, or a gate it replies to,
routinely dies before the operator engages it. Test the premise against live
state before you prep, and before the rename: a conversation that closes here
should not have moved the operator's session title.

Each tool call starts a fresh shell, so set `CONV`, `CONVERSATION` and
`SUBJECT` literally, from what step 1 found, at the top of every call below.

The premise is the conversation's ask, its description, together with the
title and description of each human gate it replies to. Read them:
```bash
gc bd show "$CONVERSATION"
for g in $(gc bd list --id "$CONVERSATION" --all --json | jq -r '.[0].dependencies[]? | select(.type == "replies-to") | .depends_on_id'); do gc bd show "$g"; done
```
Their stated conditions ARE the premise, often bulleted literally — *"no
`triage.hold` and no `gc.takeaway` on the root"*, *"its frontier is [...]
UNASSIGNED"*. Check each one still holds, on the subject and on whatever bead
the premise is about:
```bash
gc bd show "$SUBJECT" --json | jq -r '.[0].metadata
  | "hold=\(.["triage.hold"] // "") takeaway=\(.["gc.takeaway"] // "")"'
```
NON-EMPTY is the test for `triage.hold` — an EMPTY stamp is a CLEARED
hold. A `gc.takeaway` dates the last sitting rather than naming a live
wait: read what it says, then check whether that wait is still open.

Two readings end a gate's question here, with nothing posted:

- **moot** — the premise no longer holds. The frontier was routed,
  the bead was closed, another answer already settled it.
- **benign** — the premise holds but needs no human: the wait is
  already named by a non-empty `triage.hold` or another open human gate,
  or the condition is a known acceptable state. **An open PR
  awaiting the operator's review is the canonical case** — their own
  review queue, and handing it back is the bug this step prevents.

  **A takeaway is never a benign wait on its own**, because nothing
  clears it. Re-check the ids in the body (`bd show`, and
  `gc bd list --parent "$SUBJECT" --all`); it is moot only if
  something is open again.

Clear each gate the reading answers, with the reading as its answer, and read
it back. A gate another answer already closed keeps that answer, because the
first answer wins. A gate assigned to a person is theirs to clear, so leave
it:
```bash
gc bd gate resolve <gate> --reason "<moot|benign>: <the premise, and what is true instead>" \
  && gc bd show <gate> --json | jq -r '.[0] | "\(.status) \(.close_reason // "")"'
```

When the conversation's own ask dies with it, because the ask was those gates
or its concern is moot, close the conversation with the record written: the
reading goes on the subject's notes, the conversation closes with the reading
as its reason, and the PR reminder, where the engage left one, says so.
Deliberately **no takeaway stamp**: it is the subject's headline of what it
NEEDS, and one for a conversation that needs nobody spends the attention this
exit saves.

An earlier sitting on this conversation may have held and been cut short. Its
hold moved an unanchored subject to `held`, and a cut-short sign-off leaves it
there, so the close first reads the subject's state. A held subject that no
open human gate still holds goes back to `unanchored`, routed to `human` as
Accept routes its release. Its headline is replaced with the reading, because
the hold's headline names a question that no longer stands. A held subject
that another open human gate still holds stays held, since that gate's answer
is still owed. Every write is read back, and the conversation closes only
after them:
```bash
KIND="<moot|benign>"; WHY="<the premise, and what is true instead>"
STATE=$("$CONV/lifecycle.sh" state "$SUBJECT") \
  && if [ "$STATE" != held ]; then echo "$SUBJECT reads $STATE, so nothing is released"; else
       OPEN=$(gc bd dep list "$SUBJECT" --type blocks --json | jq -er 'if type == "array" then [ .[] | select(.issue_type == "gate" and .await_type == "human" and ((.status // "open") | ascii_downcase) != "closed") | .id ] | join(" ") else error("unread") end') \
         && if [ -n "$OPEN" ]; then echo "$SUBJECT stays held: $OPEN still holds it"; else
              "$CONV/gc-helm.sh" takeaway "$SUBJECT" "${KIND}: ${WHY}" --by converse --no-wait \
                && "$CONV/lifecycle.sh" transition "$SUBJECT" --to unanchored --expect held --route human \
                && [ "$("$CONV/lifecycle.sh" state "$SUBJECT")" = unanchored ] \
                && echo "released $SUBJECT from held"
            fi
     fi \
  && gc bd update "$SUBJECT" --append-notes "$KIND (conversation $CONVERSATION): $WHY" \
  && gc bd update "$CONVERSATION" --set-metadata gc.work_outcome=no-op \
  && { gc bd close "$CONVERSATION" --reason "${KIND}: ${WHY}" \
       || gc bd close "$CONVERSATION" --reason "${KIND}: ${WHY}" --force; } \
  && { "$CONV/pr-sitting-comment.sh" close --sitting "$CONVERSATION" --subject "$SUBJECT" --outcome "$KIND" --summary "$WHY" || true; } \
  && echo "closed $CONVERSATION as $KIND"
```
When it prints its `closed` line, go to step 8. **Post nothing** — no framing,
no sign-off, not even "this turned out to be fine".

No `closed` line means the close stopped short: the subject's state or its
gates did not read, or a write did not read back. The conversation stays open
under this sitting, and a held subject whose questions are answered would
otherwise wait on nothing a person can see. So say in the thread what the
block printed, fix what it names, and re-run the block. The gates cleared
above stay cleared, and each write in the block is safe to repeat.

The exit is gated on being *named*: if you cannot point at the stamp
or state that makes this benign, you hold the sitting.
Uncertain is not benign.

When the premise still holds and needs a human, this conversation earns a
sitting: prep it (steps 3–4, the `converse-prep` skill). A gate this step
cleared stays cleared, and the sitting goes on with the rest.
