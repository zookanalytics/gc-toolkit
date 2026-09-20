---
name: converse-hold
description: Converse's step 5 — the demand gate. File the human gate (a hold IS a demand) with converse-hold.sh, stamp it BEFORE waiting, then post the framing as a hand-back and offer the close-out. A hold that files no demand parks a bead nothing re-asks, so this step is safety-critical. Converse loads it from its step-to-skill routing table once a sitting is primed; it is not for other agents.
---

# Step 5 — Hold

Stamp what you are waiting for, then post your framing. `$CONV`, `$VISIT`,
and `$SUBJECT` are resolved in step 1's claim block.

`converse-hold.sh` takes the one decision or input needed as its argument
and `$VISIT` / `$SUBJECT` in its environment. It exits non-zero when the
hold did not fully land, and then you must NOT frame:
```bash
if VISIT="$VISIT" SUBJECT="$SUBJECT" \
     "$CONV/converse-hold.sh" "<the one decision or input needed, ≤140 chars>"; then
  : # the hold is real and stamped — post the framing below
else
  # NOT a hold yet: nothing re-asks the item. Do NOT post the framing.
  # Raise the failure in the thread and do not describe the item as held.
  exit 1
fi
```
**A hold IS a demand.** The operator owes an answer, and until it lands
the item cannot move, so the wait is a bead the item's work blocks on,
not a comment. A ruling files unassigned and routes to the operator's
partition; pass `--assignee <who>` to the writer only when the demand is
work a named person must perform, and that one is theirs
to close, never yours. One open demand per item: a resumed hold refreshes
the existing bead.

**Stamp BEFORE you wait, not after.** A restart or a crash can take
this session mid-hold, and these writes are all that survives. Write the
takeaway to state the decision needed when read cold, and RE-STAMP it on
every resumed hold: step 1's `action=hold` arm reads `gc.hold_demand` off
this visit to tell a real hold from a claim that died before step 2.

**The takeaway is the sentence; `held` is the state.** Where `$ITEM`
already carries an anchor state the transition is skipped, and refused
if attempted: `merge.sh`, `gate-ensure.sh` and `pr-facts.sh` enumerate
anchors by that state, and `held` drops it from all three.

A framing that asks for no decision still files one. What the
operator owes then is the close-out itself, and the demand is what
brings the item back if the thread is lost before they take it. The
gate is not about there being a question; it is about the item not
moving until a person acts.

**One sentence, ≤140 characters — the writer refuses a longer one.**
It is the board's NEEDS cell; what will not fit goes in the notes.
Never park a live conversation: the writer's `--release` clears the
assignee and route, and the only place it belongs is a stand-down
ruling (`gc-helm.sh takeaway <anchor> "<ruling>" --release`, which parks
the anchor AND quiesces its routed steps).

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
