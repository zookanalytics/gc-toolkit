---
name: converse-hold
description: Converse's hold, which records what the operator owes and gates what must wait for the answer (safety-critical).
---

# Step 5 — Hold

Record what you are waiting for, then post your framing. Each tool call
starts a fresh shell, so set `CONV`, `CONVERSATION` and `SUBJECT`
literally, from what step 1 found, at the top of every call below.

**A hold is the operator owing an answer later.** The conversation stays
claimed and this session stays, so the sitting keeps its thread. The hold's
record lands BEFORE the framing, because until it does nothing outside this
pane knows the sitting is waiting, and a restart reads a sitting that never
held. One sentence, at most 130 characters, says what the operator owes. The
headline reads `holding — <your sentence>`, which the board shows as this
sitting's headline, and the prefix spends part of the headline cap, so
`gc-helm.sh takeaway` refuses a longer one. What will not fit goes in the
notes.

**1. Record the hold on the conversation and the subject.** The
conversation's `holding:` line is the trace step 1's restart rule reads, so
the framing waits until its write exits 0:
```bash
NEED="<the one decision or input needed, at most 130 characters>"
gc bd update "$CONVERSATION" --append-notes "holding: $NEED" \
  && gc bd update "$SUBJECT" --append-notes "Conversation $CONVERSATION holding: $NEED" \
  && echo "the hold is recorded"
```
No "the hold is recorded" line means the store refused a write: do NOT post
the framing. Raise the failure in the thread, and do not describe the subject as
held.

**2. Gate what must wait for the answer.** The gates the conversation
replies to stay open and owed: nothing is written to them, because the
sitting never claimed them, and the sign-off answers them (step 7). A
conversation on an open PR holds the PR's merge until it closes, and otherwise
blocks nothing: its subject keeps moving while you talk.

**On an open PR the merge waits for this conversation.** When the subject is
an open PR's anchor (`merge_result=pull_request`, not closed), or a bead whose
`anchor_bead` names one, such as its review, rework or supplement, the anchor
depends on this conversation through bd's `blocks` edge. bd holds the anchor
while the conversation is open and lets it go once the conversation closes, by
any route, so nothing releases it by hand. `gc-helm.sh open` added the edge
when it filed the conversation on an open PR, and engage added it when it
started this sitting, so only a PR that opened since then lacks it. Add it each
time you hold, unless this sitting lifted the hold (below), since bd takes an
edge it already holds as a no-op. The edge holds only the anchor: reviews and
reworks are beads of their own, and they go on.
```bash
ANCHOR="<the open PR's anchor: the subject, or the bead its anchor_bead names>"
gc bd dep add "$ANCHOR" "$CONVERSATION" --type blocks \
  && echo "the merge of $ANCHOR waits for this conversation"
```
No closing line means the merge is NOT held: do NOT post the framing.

**A sitting that is helping the PR land lifts the hold.** When the operator
opened this conversation to move the PR forward, as with a stuck PR you are
shepherding, or when the conversation has nothing to do with whether the PR
should land, the hold works against them. Remove the edge, and record why on
the conversation, where the visit's comment on the PR lists it among the
visit's actions, so write it as one plain sentence that names no other rig.
Say in the framing that the merge no longer waits for this conversation.
```bash
ANCHOR="<the open PR's anchor: the subject, or the bead its anchor_bead names>"
WHY="<why the PR's merge need not wait for this conversation, one plain sentence>"
gc bd dep remove "$ANCHOR" "$CONVERSATION" \
  && gc bd comment "$CONVERSATION" "Lifted the hold on the PR's merge: $WHY" \
  && echo "the merge of $ANCHOR no longer waits for this conversation"
```
The lift holds for this sitting: engage adds the edge again when it starts the
next sitting on the conversation. A hold the operator wants to outlast the
conversation is a gate of its own on the anchor, under a key that names what it
waits for (the `prs` skill, holding its merge).

**On any other subject,** gate only what must wait for this conversation's
answer. When something must wait and no gate the conversation replies to
holds that bead, file a human gate on the bead that must wait: a pre-open
anchor whose PR must not open before the operator rules, or the one member of
an epic whose work waits. Without that need, file nothing. A gate that
another conversation or anyone else filed there asks another question, and its
answer releases the bead whether or not yours is settled, so it never stands
in for yours. The key names this conversation, `conversation.<its id>`, so a
resumed hold finds the gate it filed instead of filing a second, and two
conversations on one bead each hold with a gate of their own. Reply to the
gate from the conversation, so a resumed or handed-off conversation knows the
gate it owes without a search by key:
```bash
GATE=$("$CONV/human-gate.sh" --subject <the bead that must wait> --key "conversation.$CONVERSATION" --message "$NEED
<what the operator owes, and what waits on it>") \
  && gc bd dep add "$CONVERSATION" "$GATE" --type replies-to \
  && echo "gate $GATE holds what waits, and the conversation replies to it"
```
A gate that blocks a bead with open children pauses every part of it that has
not started, so when only one member waits, gate that member. No closing
line means the wait did not land, so what it was to hold is NOT held: do NOT
post the framing.

**3. Write the headline.** The subject's headline says what the operator
owes, and its wait flag says what holds the subject. Pass `--waiting-on` what
holds it: a gate the conversation replies to, the one step 2 filed on it, and
on an open PR's anchor this conversation itself, while its hold stands. The
writer records each wait as a `blocks` edge, so the conversation's is the edge
that holds the merge. bd reads the subject as blocked while what it waits on is
open, and the hold leaves the subject's route and lifecycle state as they are.
```bash
"$CONV/gc-helm.sh" takeaway "$SUBJECT" "holding — $NEED" --by converse --waiting-on <what holds the subject>
```
When nothing holds the subject, write the headline alone, with `--no-wait` in
place of `--waiting-on`: nothing waits on it but the conversation, which the
board shows in session on the subject's row, and a held bead must carry a live
edge (`doctor/check-wait-is-an-edge`). A review, rework or supplement of an
open PR is such a subject when no gate of its own holds it: this conversation
holds the PR's anchor, not the subject, and a wait onto the conversation would
stop the review or the rework. So is an anchor whose hold this sitting lifted.
When the writer refuses the headline, the board cannot show the hold, so do
NOT post the framing. Fix what it names and re-run.

Never park a live conversation: the writer's `--release` clears the
assignee and route, and the only place it belongs is a ruling that
stops the work and keeps the bead, written as
`gc-helm.sh takeaway <anchor> "<ruling>" --release --no-wait`. It parks
the anchor AND cancels the run beneath it through gascity, and `--no-wait`
records that the ruling ended the wait rather than moving it.

Then post the framing as a **hand-back** in the shape the prompt's
Definitions define (**The hand-back**). Since a decision is open here,
lead its close with the recommendation. Every framing that returns a
decision wears that shape; this hold and the step-7 sign-off both.
Record the hand-back on the conversation just before you post it (**Record
each hand-back on the conversation, then post it**):
```bash
"$CONV/gc-helm.sh" handback "$CONVERSATION" <<'HANDBACK'
<the hand-back as you post it: header, body, decision>
HANDBACK
```

Then offer the close-out, as the last line and the only thing below
the hand-back. It keeps the bottom of a reply clear of standing-by
notes, wrap-up menus and status recaps, and the close-out is none of
those. It is a control, not a chore. It is the switch that ends the
conversation, put where the operator is already reading so that ending
a sitting is not a separate errand. It never stands in for the
decision above it, and offering it is not a request to use it.

```
! <the resolved gc-helm.sh path> dismiss --reason "<why this is done>"
```

Write the resolved path, not the variable. The leading `!` is what
runs the rest of the line, so the operator ends the sitting by typing
one thing into the same prompt they are already reading — and a path
that means nothing there is a command that does not run.
`dismiss` needs no id: it infers this sitting's conversation from the
session it runs in, which is what lets the bare line stand and the
same act sit behind a keystroke. The verb closes the conversation with
a reason that names the dismissal and answers no gate: every gate the
conversation replies to stays open and owed, for its filer or the next
sitting, and an open PR's merge the conversation held is free once the close
lands. It falls back to `--force` when the plain close is refused,
which is what a hand-written `gc bd close <conversation>` walks into: a
held conversation is assigned to the sitting's alias, and bd closes an
assigned bead only for its assignee. Then wait for operator input in this
session.

When the operator replies, record and sign off (steps 6–7, the
`converse-settle` skill). If context runs low mid-hold before they do,
take the low-context path in the prompt's Rules.
