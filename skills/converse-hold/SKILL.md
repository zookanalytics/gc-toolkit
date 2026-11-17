---
name: converse-hold
description: Converse's hold, which records what the operator owes, gates what must wait for the answer, and posts the framing (safety-critical).
---

# Hold for the operator

Each call starts a fresh shell, so set `CONV`, `CONVERSATION` and `SUBJECT`
literally, from the entry's output, at the top of every call below.

A hold means the operator owes an answer. The conversation stays claimed, and
this session waits for the operator with its thread. Record the hold before you
post the framing: until the record lands, nothing outside this pane knows the
sitting waits, and a restart reads it as a sitting that never held. Write what
the operator owes as one sentence of at most 130 characters. The headline reads
`holding — <your sentence>`, and the headline's writer refuses a longer
sentence, so what does not fit goes in the notes.

## 1. Record the hold

The conversation's `holding:` line is the record the entry reads after a
restart, so post no framing until the block below has written that line:

```bash
NEED="<the one decision or input needed, at most 130 characters>"
gc bd update "$CONVERSATION" --append-notes "holding: $NEED" \
  && gc bd update "$SUBJECT" --append-notes "Conversation $CONVERSATION holding: $NEED" \
  && echo "the hold is recorded"
```

No closing line means the store refused a write: do NOT post the framing, and
say so in the thread rather than describing the subject as held.

## 2. Gate what must wait

The gates the conversation replies to stay open and owed until the sign-off
answers them. Nothing is written to them now.

**On an open PR, the merge waits for this conversation.** The subject may be an
open PR's anchor (`merge_result` `pull_request`, `pull_request_pending` or
`pull_request_head_changed`, and not closed), or a bead whose `anchor_bead`
names one, such as its review or rework. Then the anchor depends on this
conversation through a `blocks` edge, which bd lets go once the
conversation closes by any route. `gc-helm.sh open` and engage add that edge,
so only a PR that opened after the conversation was opened or engaged lacks
it. Add the edge each time you hold, unless this sitting lifted the hold; bd
takes an edge it already holds as a no-op. The edge holds only the anchor, so
reviews and reworks go on:

```bash
ANCHOR="<the open PR's anchor: the subject, or the bead its anchor_bead names>"
gc bd dep add "$ANCHOR" "$CONVERSATION" --type blocks \
  && echo "the merge of $ANCHOR waits for this conversation"
```

No closing line means the merge is NOT held: do NOT post the framing.

**A sitting that is helping the PR land lifts the hold**, and so does a sitting
whose conversation has nothing to do with whether the PR should land, because
there the hold works against the operator. Remove the edge and record why, in
one plain sentence that names no other rig, because the PR's visit comment
lists it. Say in the framing that the merge no longer waits:

```bash
ANCHOR="<the open PR's anchor: the subject, or the bead its anchor_bead names>"
WHY="<why the PR's merge need not wait for this conversation, one plain sentence>"
gc bd dep remove "$ANCHOR" "$CONVERSATION" \
  && gc bd comment "$CONVERSATION" "Lifted the hold on the PR's merge: $WHY" \
  && echo "the merge of $ANCHOR no longer waits for this conversation"
```

The lift lasts for this sitting, and engage adds the edge again for the next
sitting. A hold the operator wants to outlast the conversation is a gate of its
own on the anchor (the `prs` skill, holding its merge).

**On any other subject, gate only what must wait for the answer**, and only
when no gate the conversation replies to holds it already. Such a bead is a
pre-open anchor whose PR must not open before the operator rules, or the one
member of an epic whose work waits. Without that need, file nothing. A gate
someone else filed asks another question, and its answer releases the bead
whether or not your question is settled, so that gate never stands in for
yours. The block's key names this conversation, so a resumed hold finds the
gate it filed, and the conversation replies to that gate:

```bash
GATE=$("$CONV/human-gate.sh" --subject <the bead that must wait> --key "conversation.$CONVERSATION" --message "$NEED
<what the operator owes, and what waits on it>") \
  && gc bd dep add "$CONVERSATION" "$GATE" --type replies-to \
  && echo "gate $GATE holds what waits, and the conversation replies to it"
```

A gate on a bead with open children pauses every part not yet started, so when
only one member waits, gate that member. No closing line means the wait did
not land: do NOT post the framing.

## 3. Write the headline

The subject's headline says what the operator owes, and `--waiting-on` names
what holds the subject: a gate the conversation replies to, the gate step 2
filed, and, on an open PR's anchor, this conversation while its hold stands.
The writer records each wait as a `blocks` edge and leaves the subject's route
and lifecycle state as they are:

```bash
"$CONV/gc-helm.sh" takeaway "$SUBJECT" "holding — $NEED" --by converse --waiting-on <what holds the subject>
```

When nothing holds the subject, pass `--no-wait` in place of `--waiting-on`.
Nothing holds a review, rework or supplement of an open PR when no gate of its
own holds it, because this conversation holds the anchor, not that subject.
Nothing holds an anchor whose hold this sitting lifted, either. When the writer
refuses, the board cannot show the hold: do NOT post the framing, fix what the
writer names, and run it again. Never park a live conversation: the writer's
`--release` belongs only to a ruling that stops the work and keeps the bead
(the `work` skill).

## 4. Post the framing

When you judge that a recommendation the subject carries is no longer the
right course, but the subject still needs discussion, withdraw it (the `work` skill, stopping or redirecting work).
Never edit a recommendation in place, because Accept sends whatever formula
the subject names. The recommendation's gate is then answered like any gate
the operator rules on.

**On an open PR, say where each of its open review points lands.** Before you
recommend a ruling on an open PR, list each point its reviews raised that is
still open: a review comment of the operator's that the branch has not
answered, and a finding of the city's review that its round put to a person or
deferred to a later fix. The PR's conversation holds both, with the city's
review comment saying how its round ruled each finding. `converse-prep` read
it when the subject's metadata carries the PR's `pr_number` or `pr_url`.
Otherwise read it from the anchor with
`"$CONV/converse-pr-conversation.sh" <the anchor>`. The PR's status names what
still holds it, such as a question a person owes or a review thread that waits
on the city's answer:

```bash
ANCHOR="<the open PR's anchor: the subject, or the bead its anchor_bead names>"
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
"$GCTK" pr status "$ANCHOR" --json
```

The recommendation says where each point lands. A point lands on the PR's
branch, before approval, when the operator's review asked for it, when the PR's
change caused it, or when the PR's stated purpose covers it. Sharing a file, a
screen or a record entry with the PR does not make a point the PR's. A
follow-up carries only a point outside that scope, or one the operator rules
separable.

Post the framing as a hand-back whose decision leads with your recommendation,
and record it on the conversation first (the prompt's hand-back). When the
recommendation sends work, the decision names the formula the work goes on,
chosen as the `work` skill says. The decision also says whether you recommend
that the sitting end at its hand-off or stay for the work's return, and why
(the prompt's End or stay). It says when a stay would come back, in the
operator's terms, and recommends ending at the hand-off when that is after the
merge:

| The ruling sends | A stay comes back | You recommend |
|---|---|---|
| A rework of the PR under discussion | When the rework reaches the PR's branch, before the merge, which waits for the return | Staying when the discussion will help judge the result, and ending otherwise. Say that the PR's checks review the reworked branch again. |
| New work that opens its own PR | Only after that PR has merged | Ending at the hand-off, with what was agreed written into the work's brief in full. Say that a stay would report only after the merge. |
| Work that opens no PR of its own | When the work closes | Staying when the discussion will help judge the result, and ending otherwise. |

Then offer the close-out as the last line, the only thing below the hand-back.
The close-out is the switch that ends the sitting, put where the operator
already reads. Offering it is not a request to use it, and it does not stand in
for the decision above it:

```
! <the resolved gc-helm.sh path> dismiss --reason "<this sitting's real reason>"
```

Write the resolved path, not the variable, because the leading `!` runs the
rest of the line in the operator's own prompt. `dismiss` infers this sitting's
conversation and closes it with a reason that answers no gate: every gate the
conversation replies to stays open and owed, and an open PR's merge the
conversation held is free once the close lands.

Then wait for the operator. When they reply, carry out what they rule: a turn
that leaves the conversation open (`converse-continue`), or the end
(`converse-settle`), whose sign-off becomes a stay when they agreed to one
(`converse-stay`).
