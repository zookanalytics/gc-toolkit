---
name: converse-settle
description: Converse's record, sign-off, and visit close (safety-critical).
---

# Steps 6–7 — Record, sign off, and close the visit

`$CONV`, `$VISIT`, and `$SUBJECT` are resolved in step 1's claim block;
`$PARENT` is the subject's own parent, read with `converse-parent.sh` as the
prompt's opening Definitions describe. Run these once the operator has
replied to the held sitting (step 5).

## 6. Record

Append the sitting's outcome to the subject:
`gc bd update $SUBJECT --append-notes "<decision, rationale, what
changed>"`. If the notes have grown past a quick read, refresh a
`## Current state` block at the top: current position, decisions in
force, open questions. The notes stay on the SUBJECT even when the
item is another bead, so name the item in what you append.

## 7. Sign off, then close the visit — only when nothing important is still pending

The sign-off is the terminal act: it stamps the outcome and closes the visit.
So before you take it, ask whether this is a sign-off turn at all. **If there
is important information you want to communicate to the operator — a live
decision, a routing answer, anything they need to read or may want to respond
to, anything past "settled and done" — do not sign off this turn.** Post the
hand-back in the shape the prompt's Definitions define (**The hand-back**),
leave the visit OPEN, and wait for operator input the way a held sitting does;
signing off now would close the visit under a message they have not read. The
sitting ends on a later turn: the operator's `gc-helm dismiss`, further
engagement, or a genuinely terminal sign-off once nothing important is pending.
Whether a sign-off is terminal is still your judgment, and a sitting that is
genuinely settled still signs off and closes here rather than waiting for a
manual dismiss.

When nothing important is pending, sign off. Write the durable trace first,
then post the sign-off as the thread's last word, and close the visit last of
all. `converse-signoff.sh` writes the
durable trace and discharges the hold; you tell it what this sitting
settled. Resolve the demand gate when it settled the question (`--ruled
yes`, with the `--ruling` it resolves with and the `--route` the item is
released to); re-state it when it did not (`--ruled no`, with what is
`--still-owed`). What is waiting on the item is yours to state: one
`--waiting-on <bead>` per bead this sitting ROUTED work into, `--no-wait`
when it settled the subject and nothing is waiting, and NEITHER where the
subject is parked for a person.
```bash
VISIT="$VISIT" SUBJECT="$SUBJECT" "$CONV/converse-signoff.sh" \
  --visit "$VISIT" --subject "$SUBJECT" \
  --outcome "<outcome> — <what this sitting settled or needs next, ≤140 chars>" \
  --ruled no --still-owed "<what is still owed, ≤140 chars>"
  # --ruled yes --ruling "<the ruling, one line>" --route <pool|human>
  # --no-wait   |   --waiting-on <bead> [--waiting-on <bead> ...]
```
**Set `--ruled` from what this sitting actually settled.** The gate
starts shut, so `--ruled no` re-states the wait rather than dropping it;
`--ruled yes` resolves it and releases a `held` item. A demand a named
person must perform is assigned, and the discharge leaves it alone —
that one is theirs to close.

Then post the **sign-off** — the sitting's last word, a hand-back in
the shape the prompt's Definitions define (**The hand-back**),
self-contained enough to act on from its last few lines:
```
<subject-id> — <short human label>

<2-4 plain sentences at executive altitude: what this sitting settled
and the consequence that mattered; if a decision is still open, lead
with its recommendation.>
```
A converse is about its one subject; name another bead only where the
conversation's substance genuinely leads there, and then as a plain
sentence.
Only then stamp the outcome and close the visit — the sitting's last
actions, with nothing said after them. The stamp is the last write
before the close on purpose. An open visit carrying `gc.outcome` is then
a sitting whose sign-off already posted and whose only missing write is
the close. That is the one shape `converse-claim.sh` finishes without
posting anything.
```bash
gc bd update "$VISIT" --set-metadata "gc.outcome=<one-word-outcome>"
gc bd show "$VISIT" --json | jq -e '.[0].metadata["gc.outcome"] // empty' >/dev/null
gc bd close "$VISIT"
```
**If this sitting ROUTED work, file that work as a SIBLING of the
subject** (`--parent "$PARENT"`, read as at the top of the prompt)
**and pass `--waiting-on <work-bead>` to the sign-off for each bead it
slung.** The takeaway alone cannot carry it: *waiting and holding are
graph states, not comments.* An edge that will not take warns on stderr
and the takeaway still lands.

**A follow-up you file that is itself BLOCKED — it cannot run until
another bead lands — is ARMED, not left unrouted.** Slinging it now is
wrong (it is blocked), and leaving it unrouted to route once the blocker
closes is the come-back-later that keeps you or a person on the hook.
Wire its blocker as a `blocks` edge, then arm it so the blocker closing
routes it for you:
`deferred-dispatch.sh arm <follow-up> --target <rig>/<agent> --reason
"waits for <blocker>"` (resolve the script the way the blocks in step 1
resolve `gc-helm.sh`). Then the sitting can queue everything and close.
A blocked work bead left with no route and no arm is the debt
`doctor/check-blocked-work-armed` flags.

**A recorded wait is also the return trip.** Once every recorded wait
closes, the subject returns through the liveness sweep
(`assets/scripts/liveness-sweep.sh`) as an unnamed wait; it reads
those edges AND children, so legacy work stays visible.

Never close a visit whose `gc.outcome` stamp has not verified, and
never end a sitting without its sign-off: a thread that stops after a
decision with no wrap-up reads as a crash. The sign-off is
owed to a sitting that was **held**; one closed before any framing was
posted (step 2's `moot`/`benign`, step 1's `folded`) asked the
operator nothing, so closing those silently is the contract.

Then continue within the group or drain (step 8, the `converse-continue`
skill).
