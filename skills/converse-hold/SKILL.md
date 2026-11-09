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
sitting never claimed them, and the sign-off answers them (step 7).

**On an open PR the merge already waits.** When the subject is an open PR's
anchor (`merge_result=pull_request`), or a bead whose `anchor_bead` names one,
such as its review, rework or supplement, the PR's merge waits for this
conversation from the moment it opened until it closes. `gc-helm.sh open`
filed a human gate on the anchor under this conversation's key, and the
conversation replies to it. The gate holds only the merge: reviews and reworks
go on. Run the block below on that anchor each time you hold, unless this
sitting withdrew that gate to help the PR land (below). It prints the gate, and
files it when the conversation has none. Its message is used only when it
files.

**On any other subject,** gate only what must wait for this conversation's
answer. When something must wait and no gate the conversation replies to holds
that bead, file a human gate on the bead that must wait: a pre-open anchor
whose PR must not open before the operator rules, or the one member of an epic
whose work waits. Without that need, file nothing.

A gate that another conversation or anyone else filed asks another question,
and its answer releases the bead whether or not yours is settled, so it never
stands in for yours. The key names this conversation, `conversation.<its id>`,
so a resumed hold finds the gate it filed instead of filing a second, and two
conversations on one bead each hold with a gate of their own. Reply to the gate
from the conversation, so a resumed or handed-off conversation knows the gate
it owes without a search by key:
```bash
GATE=$("$CONV/human-gate.sh" --subject <the bead that must wait> --key "conversation.$CONVERSATION" --message "$NEED
<what the operator owes, and what waits on it>") \
  && gc bd dep add "$CONVERSATION" "$GATE" --type replies-to \
  && echo "gate $GATE holds what waits, and the conversation replies to it"
```
A gate that blocks a bead with open children pauses every part of it that has
not started, so when only one member waits, gate that member. No closing
line means the wait did not land, so the merge or the work it was to hold is
NOT held: do NOT post the framing.

**A sitting that is helping the PR land withdraws the merge's hold.** When the
operator opened this conversation to get the PR merged, as with a stuck PR you
are shepherding, the hold on its merge works against them. Withdraw the gate
under this conversation's key from the anchor, and record why on the
conversation, where the visit's comment on the PR lists it among the visit's
actions, so write it as one plain sentence that names no other rig:
```bash
WHY="<why this sitting is helping the PR land, one plain sentence>"
"$CONV/human-gate.sh" --retract --subject <the anchor of the PR> --key "conversation.$CONVERSATION" --message "$WHY" \
  && gc bd comment "$CONVERSATION" "Released the PR's merge: $WHY" \
  && echo "the PR's merge no longer waits for this conversation"
```
The withdrawal holds for this sitting: a later sitting on the conversation
holds the merge again when engage starts it. A hold the operator wants to
outlast the conversation is a gate of its own on the anchor, under a key that
names what it waits for (the `prs` skill, holding its merge).

**3. Write the headline.** The subject's headline says what the operator
owes, and its wait flag says what holds the subject. Pass `--waiting-on` the
gate that holds it, one the conversation replies to or the one step 2 filed on
it. The gate is what holds the subject: bd reads the subject as blocked while
the gate is open, and the hold leaves the subject's route and lifecycle state
as they are. On an open PR's anchor that is the conversation's own gate, for
as long as it is open.
```bash
"$CONV/gc-helm.sh" takeaway "$SUBJECT" "holding — $NEED" --by converse --waiting-on <the gate that holds the subject>
```
When no gate holds the subject, write the headline alone, with `--no-wait` in
place of `--waiting-on`: nothing waits on it but the conversation, which the
board shows in session on the subject's row, and a held bead must carry a live
edge (`doctor/check-wait-is-an-edge`). A review, rework or supplement of an
open PR is such a subject when no gate of its own holds it: the conversation's
gate holds the PR's anchor, not the subject, and a `--waiting-on` onto that
gate would make the subject wait on it too, stopping the review or the rework
the gate leaves running. When the writer refuses the headline, the board
cannot show the hold, so do NOT post the framing. Fix what it names and
re-run.

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
sitting. It withdraws only the conversation's own hold on an open PR's
merge, which ends with the conversation. It falls back to `--force` when the plain close is refused,
which is what a hand-written `gc bd close <conversation>` walks into: a
held conversation is assigned to the sitting's alias, and bd closes an
assigned bead only for its assignee. Then wait for operator input in this
session.

When the operator replies, record and sign off (steps 6–7, the
`converse-settle` skill). If context runs low mid-hold before they do,
take the low-context path in the prompt's Rules.
