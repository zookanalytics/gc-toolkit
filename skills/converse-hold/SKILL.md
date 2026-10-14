---
name: converse-hold
description: Converse's demand-gate hold (safety-critical).
---

# Step 5 — Hold

Stamp what you are waiting for, then post your framing. `$CONV`, `$VISIT`,
and `$SUBJECT` are resolved in step 1's claim block.

`converse-hold.sh` takes the one decision or input needed as its argument
and `$VISIT` / `$SUBJECT` in its environment. It exits non-zero when the
hold did not fully land, and then you must NOT frame:
```bash
if VISIT="$VISIT" SUBJECT="$SUBJECT" \
     "$CONV/converse-hold.sh" "<the one decision or input needed, ≤130 chars>"; then
  : # the hold is real and stamped — post the framing below
else
  # NOT a hold yet: nothing re-asks the subject. Do NOT post the framing.
  # Raise the failure in the thread and do not describe the subject as held.
  exit 1
fi
```
**A hold IS a demand.** The operator owes an answer before the
conversation can conclude, so the wait is a bead with a `blocks` edge,
not a comment, and `converse-hold.sh` files it against the right bead for
you. A conversation about a PR anchor gates the VISIT: the conversation
cannot conclude until the operator answers, and the subject anchor keeps
moving — a conversation does not freeze its subject's merge. Only a
pre-PR (unanchored) subject takes the demand on itself, because its `held`
marker needs that edge. A ruling files unassigned and routes to the
operator's partition; pass `--assignee <who>` to the writer only when the
demand is work a named person must perform, and that one is theirs to
close, never yours. A resumed hold refreshes the demand this sitting
filed rather than filing a second. The visit's `escalation_key` scopes the
demand, so a sibling sitting with its own key on a shared subject keeps its
own.

**Stamp BEFORE you wait, not after.** The hold IS a demand: until the
demand is filed nothing re-asks the question, so it lands before you hand
control to the operator. Write the takeaway to state the decision needed
when read cold off the board. The same step sets `gc.hold_demand` on this
visit, the trace step 1's `action=hold` arm reads to tell a real hold
from a claim that died before step 2.

**To pause the merge, pass `--hold-merge` — by default a conversation does
not.** The hold above leaves a PR free to land while you talk, which is the
shepherd case a conversation opened to help a stuck PR wants. When the sitting
instead decides the merge must wait on the operator — the PR should not land
until this is settled — add the flag to the same call:
```bash
if VISIT="$VISIT" SUBJECT="$SUBJECT" \
     "$CONV/converse-hold.sh" --hold-merge "<the one decision or input needed, ≤130 chars>"; then
  : # the hold is real and the merge is held — post the framing below
else
  # the conversation hold or the merge hold did not land — do NOT frame.
  exit 1
fi
```
It files a second demand on the anchor — the `blocks` edge the merge sweep
already honors — and fails the hold closed if that demand does not land, so a
framing never claims a merge hold it did not take. Omit the flag and the PR
keeps moving. Either way the step-7 sign-off discharges whichever demands you
filed.

**The takeaway is the sentence; `held` is the state.** Where `$SUBJECT`
already carries an anchor state the held transition is skipped, and
refused if attempted: `merge.sh`, `gate-ensure.sh` and `pr-facts.sh`
enumerate anchors by that state, and `held` drops it from all three. It
is the pre-PR hold; the explicit merge hold above is an edge on the
anchor, not this state.

A framing that asks for no decision still files one. What the
operator owes then is the close-out itself, and the demand is what
brings the subject back if the thread is lost before they take it. The
gate is not about there being a question; it is about the subject not
moving until a person acts.

**One sentence, ≤130 characters.** The takeaway reads
`holding — <your sentence>`, the board's NEEDS cell, and the prefix spends
part of the headline cap. `converse-hold.sh` refuses a longer sentence
before it writes anything and says how far to cut it. What will not fit
goes in the notes.
Never park a live conversation: the writer's `--release` clears the
assignee and route, and the only place it belongs is a stand-down
ruling, written as
`gc-helm.sh takeaway <anchor> "<ruling>" --release --no-wait`. It parks
the anchor AND quiesces its routed steps, and `--no-wait` records that
the ruling ended the wait rather than moving it.

Then post the framing as a **hand-back** in the shape the prompt's
Definitions define (**The hand-back**): detail and evidence first, the
hand-back itself as the last word, and — since a decision is open here —
lead its close with the recommendation. Every framing that returns a
decision wears that shape; this hold and the step-7 sign-off both.

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
`dismiss` needs no bead-id: it infers this sitting's subject from the
session it runs in, which is what lets the bare line stand and the
same act sit behind a keystroke. The verb closes every open visit on
the subject and stamps the outcome the board reads for a finished
sitting. It falls back to `--force` when the plain close is refused,
which is what a hand-written `gc bd close <visit>` walks into: a held
visit is assigned to the session holding it, and a session restarted
mid-hold closes under a different identity string than the one on the
bead. Then wait for operator input in this session.

When the operator replies, record and sign off (steps 6–7, the
`converse-settle` skill). If context runs low mid-hold before they do,
take the `cut-short` path in the prompt's Rules.
